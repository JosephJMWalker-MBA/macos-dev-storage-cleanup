#!/bin/zsh

emulate -LR zsh
set -e
setopt pipefail

INSTALL_BIN="$HOME/.local/bin/cachewarden"
CONFIG_DIR="$HOME/.config/cachewarden"
PLIST_FILE="$HOME/Library/LaunchAgents/com.cachewarden.storage-cleanup.plist"
LOG_FILE="$HOME/Library/Logs/cachewarden.log"
ERROR_LOG_FILE="$HOME/Library/Logs/cachewarden-error.log"
LABEL="com.cachewarden.storage-cleanup"
DOMAIN="gui/$(/usr/bin/id -u)"

REMOVE_USER_DATA=0

usage() {
  cat <<'EOF'
Usage: ./uninstall.sh [--purge]

  --purge   Also remove CacheWarden's configuration and log files.
  --help    Show this help text.
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --purge)
      REMOVE_USER_DATA=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      print -u2 -r -- "Unknown argument: $1"
      usage >&2
      exit 1
      ;;
  esac
  shift
done

print -r -- "Uninstalling CacheWarden..."

/bin/launchctl bootout "$DOMAIN" "$PLIST_FILE" 2>/dev/null || true
/bin/launchctl disable "$DOMAIN/$LABEL" 2>/dev/null || true

/bin/rm -f -- "$PLIST_FILE" "$INSTALL_BIN"

if (( REMOVE_USER_DATA )); then
  /bin/rm -rf -- "$CONFIG_DIR"
  /bin/rm -f -- "$LOG_FILE" "$ERROR_LOG_FILE"
  print -r -- "Removed configuration and logs."
else
  print -r -- "Preserved configuration and logs."
  print -r -- "Run './uninstall.sh --purge' to remove them as well."
fi

print -r -- "CacheWarden has been uninstalled."
