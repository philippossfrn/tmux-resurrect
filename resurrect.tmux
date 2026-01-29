#!/usr/bin/env bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source "$CURRENT_DIR/scripts/variables.sh"
source "$CURRENT_DIR/scripts/helpers.sh"

set_save_bindings() {
	local key_bindings=$(get_tmux_option "$save_option" "$default_save_key")
	local key
	for key in $key_bindings; do
		tmux bind-key "$key" run-shell "$CURRENT_DIR/scripts/save.sh"
	done
}

set_restore_bindings() {
	local key_bindings=$(get_tmux_option "$restore_option" "$default_restore_key")
	local key
	for key in $key_bindings; do
		tmux bind-key "$key" run-shell "$CURRENT_DIR/scripts/restore.sh"
	done
}

set_default_strategies() {
	tmux set-option -gq "${restore_process_strategy_option}irb" "default_strategy"
	tmux set-option -gq "${restore_process_strategy_option}mosh-client" "default_strategy"
}

set_script_path_options() {
	tmux set-option -gq "$save_path_option" "$CURRENT_DIR/scripts/save.sh"
	tmux set-option -gq "$restore_path_option" "$CURRENT_DIR/scripts/restore.sh"
}

install_attach_script() {
	local bin_dir="$HOME/bin"
	local attach_script="$bin_dir/attach"

	# Only create if attach script doesn't already exist
	if [[ -f "$attach_script" ]]; then
		return 0
	fi

	# Create $HOME/bin if it doesn't exist
	mkdir -p "$bin_dir"

	# Create the attach script
	cat > "$attach_script" << ATTACH_SCRIPT
#!/bin/bash

# Directory where tmux-resurrect saves sessions
RESURRECT_DIR="\$HOME/.tmux/resurrect"

# Path to restore script (set at install time)
RESTORE_SCRIPT="$CURRENT_DIR/scripts/restore.sh"

# Check if the directory exists
if [[ ! -d "\$RESURRECT_DIR" ]]; then
    echo "Error: Tmux-resurrect directory not found at \$RESURRECT_DIR"
    exit 1
fi

# List saved sessions
echo "Available saved tmux sessions:"
SAVED_SESSIONS=(\$(find "\$RESURRECT_DIR" -maxdepth 1 -type f ! -name "last" ! -name "readme*" -printf "%f\n" | sort))
if [[ \${#SAVED_SESSIONS[@]} -eq 0 ]]; then
    echo "No saved sessions found."
    exit 0
fi

# Display session names
for i in "\${!SAVED_SESSIONS[@]}"; do
    echo "\$i) \${SAVED_SESSIONS[\$i]}"
done

echo ""
echo "Options: [number] to restore, [d/D] to delete, [r/R] to rename"
read -p "Enter your choice: " CHOICE

# Handle delete option
if [[ "\$CHOICE" =~ ^[dD]\$ ]]; then
    read -p "Enter the number of the session to delete: " DEL_CHOICE
    if [[ ! "\$DEL_CHOICE" =~ ^[0-9]+\$ ]] || [[ "\$DEL_CHOICE" -ge "\${#SAVED_SESSIONS[@]}" ]]; then
        echo "Invalid selection. Exiting."
        exit 1
    fi
    DEL_SESSION="\${SAVED_SESSIONS[\$DEL_CHOICE]}"
    read -p "Are you sure you want to delete '\$DEL_SESSION'? [y/N]: " CONFIRM
    if [[ "\$CONFIRM" =~ ^[yY]\$ ]]; then
        rm "\$RESURRECT_DIR/\$DEL_SESSION"
        echo "Deleted: \$DEL_SESSION"
    else
        echo "Deletion cancelled."
    fi
    exit 0
fi

# Handle rename option
if [[ "\$CHOICE" =~ ^[rR]\$ ]]; then
    read -p "Enter the number of the session to rename: " REN_CHOICE
    if [[ ! "\$REN_CHOICE" =~ ^[0-9]+\$ ]] || [[ "\$REN_CHOICE" -ge "\${#SAVED_SESSIONS[@]}" ]]; then
        echo "Invalid selection. Exiting."
        exit 1
    fi
    OLD_SESSION="\${SAVED_SESSIONS[\$REN_CHOICE]}"
    read -p "Enter new name (without .txt extension): " NEW_NAME
    if [[ -z "\$NEW_NAME" ]]; then
        echo "Invalid name. Exiting."
        exit 1
    fi
    NEW_SESSION="\${NEW_NAME}.txt"
    if [[ -f "\$RESURRECT_DIR/\$NEW_SESSION" ]]; then
        echo "Error: A session with that name already exists."
        exit 1
    fi
    mv "\$RESURRECT_DIR/\$OLD_SESSION" "\$RESURRECT_DIR/\$NEW_SESSION"
    echo "Renamed: \$OLD_SESSION -> \$NEW_SESSION"
    exit 0
fi

# Handle restore (number input)
if [[ ! "\$CHOICE" =~ ^[0-9]+\$ ]] || [[ "\$CHOICE" -ge "\${#SAVED_SESSIONS[@]}" ]]; then
    echo "Invalid selection. Exiting."
    exit 1
fi

# Restore the selected session
SELECTED_SESSION="\${SAVED_SESSIONS[\$CHOICE]}"

# Extract the desired session name (remove .txt extension)
DESIRED_NAME="\${SELECTED_SESSION%.txt}"

# Check if 'last' is a symlink and remove it if necessary
if [[ -L "\$RESURRECT_DIR/last" ]]; then
    rm "\$RESURRECT_DIR/last"
fi

# Copy the selected session to 'last'
cp "\$RESURRECT_DIR/\$SELECTED_SESSION" "\$RESURRECT_DIR/last"

# Ensure the tmux server is running by creating a detached session
temp_session="resurrect-temp-\$\$-\$RANDOM"
created_temp_session=false
if tmux new-session -d -s "\$temp_session" 2>/dev/null; then
    created_temp_session=true
fi

# Restore the session using tmux-resurrect
tmux run-shell "\$RESTORE_SCRIPT"

# Wait for restoration to complete
sleep 2

# Kill the temp session only if we created it
if [[ "\$created_temp_session" == true ]]; then
    tmux kill-session -t "\$temp_session" 2>/dev/null
fi

# Get all sessions
SESSIONS=\$(tmux list-sessions -F '#{session_name}' 2>/dev/null)

if [[ -z "\$SESSIONS" ]]; then
    echo "Error: No sessions found after restoration."
    exit 1
fi

# Get the first session (the restored one)
FIRST_SESSION=\$(echo "\$SESSIONS" | head -n 1)

# Rename the session to match the filename
tmux rename-session -t "\$FIRST_SESSION" "\$DESIRED_NAME"

echo "Available sessions after restoration:"
tmux list-sessions

echo ""
echo "Attaching to session: \$DESIRED_NAME"
tmux attach-session -t "\$DESIRED_NAME"
ATTACH_SCRIPT

	# Make it executable
	chmod +x "$attach_script"
}

main() {
	set_save_bindings
	set_restore_bindings
	set_default_strategies
	set_script_path_options
	install_attach_script
}
main
