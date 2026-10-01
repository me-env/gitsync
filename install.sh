#!/bin/bash
# Install gitsync for the current user (no sudo needed).
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
BIN="$HOME/.local/bin/gitsync"
CONF="$HOME/.config/gitsync"
STATE="$HOME/.local/state/gitsync"
PLIST="$HOME/Library/LaunchAgents/com.gitsync.agent.plist"

mkdir -p "$(dirname "$BIN")" "$CONF" "$STATE" "$(dirname "$PLIST")"
install -m 755 "$HERE/gitsync.sh" "$BIN"
[ -f "$CONF/config" ] || cp "$HERE/config.example" "$CONF/config"
[ -f "$CONF/repos" ]  || cp "$HERE/repos.example"  "$CONF/repos"

sed -e "s#__BIN__#$BIN#" -e "s#__STATE__#$STATE#g" "$HERE/launchd/com.gitsync.agent.plist" > "$PLIST"
launchctl bootout "gui/$(id -u)/com.gitsync.agent" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "Installed. Edit your repo list:  $CONF/repos"
echo "Check it:                        $BIN status"
echo "Log:                             $STATE/gitsync.log"
