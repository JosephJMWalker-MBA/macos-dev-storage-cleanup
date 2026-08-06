# CacheWarden

**Threshold-aware storage maintenance for macOS development machines.**

CacheWarden is a conservative, `launchd`-powered utility that checks the free space on your Mac's Data volume and clears selected **rebuildable developer caches** only when available storage falls below a configurable threshold.

It was created after a development Mac reached 98% capacity with only 5.2 GB available. A manual audit recovered roughly 27 GB; CacheWarden turns the repeatable portion of that cleanup into a small maintenance system.

> [!WARNING]
> CacheWarden uses recursive deletion for explicitly listed cache directories. Read the script before installing it. Back up important work, and never add personal-data paths to the cleanup list.

## What it does

- Checks `/System/Volumes/Data`, rather than relying only on the sealed macOS system volume.
- Runs only when available storage is below `THRESHOLD_GB`.
- Clears selected npm, pip, Gradle, Homebrew, and Claude temporary caches.
- Skips Gradle cleanup while Gradle or Android Studio appears active.
- Skips Claude temporary cleanup while Claude appears active.
- Records standard output and errors in `~/Library/Logs`.
- Uses a per-user LaunchAgent; no `sudo` is required.

## What it does not delete

CacheWarden does **not** target:

- Documents or Downloads
- Source repositories
- Application databases or settings
- Android virtual devices or SDK system images
- Downloaded AI models
- Xcode installations or archives
- Protected Apple system caches

## Requirements

- macOS
- Z shell (`/bin/zsh`, included with current macOS versions)
- `launchd` / `launchctl`
- Optional: Homebrew and Python 3

## Install

Clone the repository, review the files, and run the installer:

```bash
git clone https://github.com/JosephJMWalker-MBA/macos-dev-storage-cleanup.git
cd macos-dev-storage-cleanup
less bin/cachewarden.zsh
./install.sh
```

The installer creates:

```text
~/.local/bin/cachewarden
~/.config/cachewarden/config
~/Library/LaunchAgents/com.cachewarden.storage-cleanup.plist
~/Library/Logs/cachewarden.log
~/Library/Logs/cachewarden-error.log
```

By default, the LaunchAgent checks storage every Sunday at 4:00 a.m. and performs cleanup only when less than 30 GB is available.

## Configuration

Edit:

```bash
nano ~/.config/cachewarden/config
```

Default configuration:

```bash
THRESHOLD_GB=30
ENABLE_GRADLE=1
ENABLE_NPM=1
ENABLE_PIP=1
ENABLE_HOMEBREW=1
ENABLE_CLAUDE_TEMP=1
```

Set any cleanup toggle to `0` to disable it.

## Run manually

Normal threshold-aware run:

```bash
~/.local/bin/cachewarden
```

Inspect what CacheWarden would target without deleting anything:

```bash
~/.local/bin/cachewarden --dry-run
```

Force a cleanup even when free space is above the threshold:

```bash
~/.local/bin/cachewarden --force
```

## Inspect the logs

```bash
tail -50 ~/Library/Logs/cachewarden.log
tail -50 ~/Library/Logs/cachewarden-error.log
```

Check the LaunchAgent:

```bash
launchctl print "gui/$(id -u)/com.cachewarden.storage-cleanup"
```

Trigger the registered job immediately:

```bash
launchctl kickstart -k "gui/$(id -u)/com.cachewarden.storage-cleanup"
```

## Uninstall

```bash
./uninstall.sh
```

The uninstaller removes the LaunchAgent and installed executable. It preserves the configuration and logs unless you explicitly choose to remove them.

## Design principles

1. **Inspect before deleting.** The cleanup scope is visible and intentionally small.
2. **Thresholds over constant purging.** Caches improve development speed and should not be erased without a reason.
3. **User files are out of scope.** CacheWarden cleans reproducible artifacts, not creative work.
4. **No elevated privileges.** A personal maintenance tool should not require system-wide authority.
5. **Reversible installation.** Every installed component has a documented removal path.

## Development status

CacheWarden is an early public utility. Review the current implementation before relying on it in a production workflow. Reports about unexpected behavior, additional safe cache targets, and macOS compatibility are welcome through GitHub Issues.
