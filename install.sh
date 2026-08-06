#!/bin/zsh

emulate -LR zsh
set -e
setopt pipefail

REPO_DIR="${0:A:h}"
SOURCE_SCRIPT="$REPO_DIR/bin/cachewarden.zsh"
SOURCE_CONFIG="$REPO_DIR/config/cachewarden.conf.example"

INSTALL_BIN="$HOME/.local/bin/cachewarden"
CONFIG_DIR="$HOME/.config/cachewarden"
CONFIG_FILE="$CONFIG_DIR/config"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_FILE="$PLIST_DIR/com.cachewarden.storage-cleanup.plist"
LOG_DIR="$HOME/Library/Logs"
LOG_FILE="$LOG_DIR/cachewarden.log"
ERROR_LOG_FILE="$LOG_DIR/cachewarden-error.log"
LABEL="com.cachewarden.storage-cleanup"
DOMAIN="gui/$(/usr/bin/id -u)"

print -r -- "Installing CacheWarden..."

[[ -f "$SOURCE_SCRIPT" ]] || {
  print -u2 -r -- "Missing source script: $SOURCE_SCRIPT"
  exit 1
}

[[ -f "$SOURCE_CONFIG" ]] || {
  print -u2 -r -- "Missing example configuration: $SOURCE_CONFIG"
  exit 1
}

/bin/mkdir -p \
  "${INSTALL_BIN:h}" \
  "$CONFIG_DIR" \
  "$PLIST_DIR" \
  "$LOG_DIR"

/bin/cp "$SOURCE_SCRIPT" "$INSTALL_BIN"
/bin/chmod 700 "$INSTALL_BIN"

if [[ ! -f "$CONFIG_FILE" ]]; then
  /bin/cp "$SOURCE_CONFIG" "$CONFIG_FILE"
  /bin/chmod 600 "$CONFIG_FILE"
  print -r -- "Created configuration: $CONFIG_FILE"
else
  print -r -- "Preserving existing configuration: $CONFIG_FILE"
fi

cat > "$PLIST_FILE" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>

    <key>ProgramArguments</key>
    <array>
        <string>/bin/zsh</string>
        <string>$INSTALL_BIN</string>
    </array>

    <key>StartCalendarInterval</key>
    <dict>
        <key>Weekday</key>
        <integer>0</integer>
        <key>Hour</key>
        <integer>4</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>

    <key>ProcessType</key>
    <string>Background</string>

    <key>LowPriorityIO</key>
    <true/>

    <key>Nice</key>
    <integer>10</integer>

    <key>StandardOutPath</key>
    <string>$LOG_FILE</string>

    <key>StandardErrorPath</key>
    <string>$ERROR_LOG_FILE</string>
</dict>
</plist>
PLIST

/usr/bin/plutil -lint "$PLIST_FILE"

/bin/launchctl bootout "$DOMAIN" "$PLIST_FILE" 2>/dev/null || true
/bin/launchctl enable "$DOMAIN/$LABEL"
/bin/launchctl bootstrap "$DOMAIN" "$PLIST_FILE"

print -r -- ""
print -r -- "CacheWarden is installed."
print -r -- "Executable:    $INSTALL_BIN"
print -r -- "Configuration: $CONFIG_FILE"
print -r -- "LaunchAgent:   $PLIST_FILE"
print -r -- "Schedule:      Sundays at 4:00 a.m."
print -r -- ""
print -r -- "Review targets without deleting anything:"
print -r -- "  $INSTALL_BIN --dry-run --force"
print -r -- ""
print -r -- "Run a normal threshold-aware check:"
print -r -- "  $INSTALL_BIN"
