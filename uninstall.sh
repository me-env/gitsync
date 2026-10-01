#!/bin/bash
launchctl bootout "gui/$(id -u)/com.gitsync.agent" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/com.gitsync.agent.plist" "$HOME/.local/bin/gitsync"
echo "Uninstalled (config kept in ~/.config/gitsync, logs in ~/.local/state/gitsync)."
