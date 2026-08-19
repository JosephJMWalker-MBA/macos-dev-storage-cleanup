#!/bin/zsh

# CacheWarden
# Threshold-aware cleanup of explicitly approved, rebuildable developer caches.

emulate -LR zsh
setopt pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

PROGRAM_NAME="CacheWarden"
CONFIG_FILE="${CACHEWARDEN_CONFIG:-$HOME/.config/cachewarden/config}"
DATA_VOLUME="/System/Volumes/Data"

[[ -d "$DATA_VOLUME" ]] || DATA_VOLUME="/"

THRESHOLD_GB=30
ENABLE_GRADLE=1
ENABLE_NPM=1
ENABLE_PIP=1
ENABLE_HOMEBREW=1
ENABLE_CLAUDE_TEMP=1

DRY_RUN=0
FORCE_RUN=0

usage() {
  cat <<'EOF'
Usage: cachewarden [--dry-run] [--force] [--help]

  --dry-run   Report cleanup actions without deleting files.
  --force     Run enabled cleanup actions regardless of free-space threshold.
  --help      Show this help text.
EOF
}

log() {
  print -r -- "[$(/bin/date '+%Y-%m-%d %H:%M:%S')] $*"
}

fail() {
  log "ERROR: $*" >&2
  exit 1
}

is_enabled() {
  [[ "$1" == "1" ]]
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

trim_whitespace() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  print -r -- "$value"
}

validate_nonnegative_integer() {
  local key="$1"
  local value="$2"

  case "$value" in
    ''|*[!0-9]*) fail "$key must be a non-negative integer." ;;
  esac
}

validate_toggle() {
  local key="$1"
  local value="$2"
  [[ "$value" == "0" || "$value" == "1" ]] || fail "$key must be either 0 or 1."
}

free_kb() {
  /bin/df -Pk "$DATA_VOLUME" | /usr/bin/awk 'NR == 2 { print $4 }'
}

size_kb() {
  local target="$1"

  if [[ -e "$target" ]]; then
    /usr/bin/du -sk "$target" 2>/dev/null | /usr/bin/awk '{ print $1 }'
  else
    print -r -- "0"
  fi
}

approved_target() {
  local target="$1"
  local uid
  uid="$(/usr/bin/id -u)"

  case "$target" in
    "$HOME/.gradle/caches"|\
    "$HOME/.npm/_cacache"|\
    "$HOME/.cache/pip"|\
    "/private/tmp/claude-${uid}")
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

resolved_target_path() {
  local target="$1"
  local parent="${target%/*}"
  local base="${target##*/}"
  local resolved_parent

  [[ -n "$parent" ]] || parent="/"
  resolved_parent="$(cd -P "$parent" 2>/dev/null && pwd -P)" || return 1

  if [[ "$resolved_parent" == "/" ]]; then
    print -r -- "/$base"
  else
    print -r -- "$resolved_parent/$base"
  fi
}

validate_direct_target() {
  local target="$1"
  local resolved

  approved_target "$target" || {
    log "REFUSED: '$target' is not in CacheWarden's approved target list."
    return 1
  }

  if [[ -L "$target" ]]; then
    log "REFUSED: '$target' is a symbolic link; direct cleanup never follows symlink targets."
    return 1
  fi

  if [[ ! -e "$target" ]]; then
    return 0
  fi

  resolved="$(resolved_target_path "$target")" || {
    log "REFUSED: could not resolve the parent path for '$target'."
    return 1
  }

  if [[ "$resolved" != "$target" ]]; then
    log "REFUSED: '$target' resolves through a different parent path ('$resolved')."
    return 1
  fi

  return 0
}

remove_approved_path() {
  local description="$1"
  local target="$2"
  local before_kb

  validate_direct_target "$target" || return 1

  if [[ ! -e "$target" ]]; then
    log "Skipping $description; target does not exist."
    return 0
  fi

  before_kb="$(size_kb "$target")"

  if (( DRY_RUN )); then
    log "DRY RUN: would remove $description at '$target' (approximately $(( before_kb / 1024 )) MB)."
    return 0
  fi

  log "Removing $description at '$target' (approximately $(( before_kb / 1024 )) MB)."
  /bin/rm -rf -- "$target"
}

load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    local line
    local key
    local value
    local line_number=0

    while IFS= read -r line || [[ -n "$line" ]]; do
      (( line_number += 1 ))
      line="$(trim_whitespace "$line")"

      [[ -z "$line" || "$line" == \#* ]] && continue
      [[ "$line" == *=* ]] || fail "Invalid config line $line_number: expected KEY=VALUE."

      key="$(trim_whitespace "${line%%=*}")"
      value="$(trim_whitespace "${line#*=}")"

      case "$key" in
        THRESHOLD_GB)
          validate_nonnegative_integer "$key" "$value"
          THRESHOLD_GB="$value"
          ;;
        ENABLE_GRADLE)
          validate_toggle "$key" "$value"
          ENABLE_GRADLE="$value"
          ;;
        ENABLE_NPM)
          validate_toggle "$key" "$value"
          ENABLE_NPM="$value"
          ;;
        ENABLE_PIP)
          validate_toggle "$key" "$value"
          ENABLE_PIP="$value"
          ;;
        ENABLE_HOMEBREW)
          validate_toggle "$key" "$value"
          ENABLE_HOMEBREW="$value"
          ;;
        ENABLE_CLAUDE_TEMP)
          validate_toggle "$key" "$value"
          ENABLE_CLAUDE_TEMP="$value"
          ;;
        *)
          fail "Unknown configuration key '$key' on line $line_number."
          ;;
      esac
    done < "$CONFIG_FILE"
  else
    log "Configuration not found at '$CONFIG_FILE'; using built-in defaults."
  fi

  validate_nonnegative_integer "THRESHOLD_GB" "$THRESHOLD_GB"
  validate_toggle "ENABLE_GRADLE" "$ENABLE_GRADLE"
  validate_toggle "ENABLE_NPM" "$ENABLE_NPM"
  validate_toggle "ENABLE_PIP" "$ENABLE_PIP"
  validate_toggle "ENABLE_HOMEBREW" "$ENABLE_HOMEBREW"
  validate_toggle "ENABLE_CLAUDE_TEMP" "$ENABLE_CLAUDE_TEMP"
}

while (( $# > 0 )); do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    --force)
      FORCE_RUN=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      fail "Unknown argument: $1"
      ;;
  esac
  shift
done

load_config

FREE_BEFORE_KB="$(free_kb)"
validate_nonnegative_integer "available storage" "$FREE_BEFORE_KB"

THRESHOLD_KB=$(( THRESHOLD_GB * 1024 * 1024 ))
FREE_BEFORE_GB=$(( FREE_BEFORE_KB / 1024 / 1024 ))

log "=================================================="
log "$PROGRAM_NAME storage check"
log "Data volume: $DATA_VOLUME"
log "Available before cleanup: approximately ${FREE_BEFORE_GB} GB"
/bin/df -h "$DATA_VOLUME"

if (( ! FORCE_RUN && FREE_BEFORE_KB >= THRESHOLD_KB )); then
  log "At least ${THRESHOLD_GB} GB is available. No cleanup is needed."
  exit 0
fi

if (( FORCE_RUN )); then
  log "Force mode enabled; bypassing the ${THRESHOLD_GB} GB threshold."
else
  log "Available storage is below ${THRESHOLD_GB} GB; beginning conservative cleanup."
fi

if (( DRY_RUN )); then
  log "Dry-run mode enabled; no files will be deleted."
fi

if is_enabled "$ENABLE_GRADLE"; then
  if /usr/bin/pgrep -f "GradleDaemon|Android Studio" >/dev/null 2>&1; then
    log "Skipping Gradle caches because Gradle or Android Studio appears active."
  else
    remove_approved_path "Gradle caches" "$HOME/.gradle/caches"
  fi
else
  log "Gradle cleanup is disabled."
fi

if is_enabled "$ENABLE_NPM"; then
  remove_approved_path "npm package cache" "$HOME/.npm/_cacache"
else
  log "npm cleanup is disabled."
fi

if is_enabled "$ENABLE_PIP"; then
  remove_approved_path "pip cache directory" "$HOME/.cache/pip"

  if command_exists python3; then
    if (( DRY_RUN )); then
      log "DRY RUN: would request 'python3 -m pip cache purge'."
    else
      log "Requesting pip cache cleanup through Python 3."
      python3 -m pip cache purge 2>/dev/null || \
        log "pip cache purge returned a non-zero status; continuing."
    fi
  else
    log "Python 3 was not found; skipping pip's own cleanup command."
  fi
else
  log "pip cleanup is disabled."
fi

if is_enabled "$ENABLE_HOMEBREW"; then
  if command_exists brew; then
    if (( DRY_RUN )); then
      log "DRY RUN: asking Homebrew to preview obsolete downloads and package versions."
      brew cleanup -n 2>/dev/null || \
        log "Homebrew preview returned a non-zero status; continuing."
    else
      log "Running Homebrew cleanup."
      brew cleanup 2>/dev/null || \
        log "Homebrew cleanup returned a non-zero status; continuing."
    fi
  else
    log "Homebrew was not found; skipping Homebrew cleanup."
  fi
else
  log "Homebrew cleanup is disabled."
fi

if is_enabled "$ENABLE_CLAUDE_TEMP"; then
  if /usr/bin/pgrep -x "Claude" >/dev/null 2>&1; then
    log "Skipping Claude temporary data because Claude appears active."
  else
    remove_approved_path \
      "inactive Claude temporary data" \
      "/private/tmp/claude-$(/usr/bin/id -u)"
  fi
else
  log "Claude temporary cleanup is disabled."
fi

if (( ! DRY_RUN )); then
  /bin/sync
fi

FREE_AFTER_KB="$(free_kb)"
validate_nonnegative_integer "available storage after cleanup" "$FREE_AFTER_KB"

FREE_AFTER_GB=$(( FREE_AFTER_KB / 1024 / 1024 ))
RECOVERED_KB=$(( FREE_AFTER_KB - FREE_BEFORE_KB ))
(( RECOVERED_KB < 0 )) && RECOVERED_KB=0
RECOVERED_GB=$(( RECOVERED_KB / 1024 / 1024 ))

if (( DRY_RUN )); then
  log "Dry run completed. Available storage remains approximately ${FREE_AFTER_GB} GB."
else
  log "Cleanup completed. Approximately ${RECOVERED_GB} GB was recovered."
  log "Available after cleanup: approximately ${FREE_AFTER_GB} GB."
fi

/bin/df -h "$DATA_VOLUME"
