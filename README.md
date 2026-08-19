# CacheWarden

**Threshold-aware storage maintenance for macOS development machines.**

CacheWarden is a conservative, `launchd`-powered utility that checks the free space on your Mac's Data volume and performs selected **rebuildable developer-cache cleanup** only when available storage falls below a configurable threshold.

It was created after a development Mac reached 98% capacity with only 5.2 GB available. A manual audit recovered roughly 27 GB; CacheWarden turns the repeatable portion of that cleanup into a small maintenance system.

> [!WARNING]
> CacheWarden performs destructive cleanup. Review the script and configuration before installing it, back up important work, and use `--dry-run --force` before your first real cleanup. The direct recursive-deletion paths are intentionally fixed in code and should never be expanded to include personal-data locations.

## What it does

- Checks `/System/Volumes/Data`, rather than relying only on the sealed macOS system volume.
- Runs automatically only when available storage is below `THRESHOLD_GB`.
- Directly removes a small hardcoded allowlist of rebuildable Gradle, npm, pip, and Claude temporary cache paths.
- Refuses direct cleanup when an allowlisted target is itself a symbolic link or resolves through a different physical parent path.
- Optionally delegates additional cleanup to `python3 -m pip cache purge` and `brew cleanup` when those tools are available.
- Skips Gradle cleanup while Gradle or Android Studio appears active.
- Skips Claude temporary cleanup while Claude appears active.
- Records standard output and errors in `~/Library/Logs`.
- Uses a per-user LaunchAgent; no `sudo` is required.

## Direct deletion boundary

CacheWarden's own recursive deletion is limited to these exact paths:

```text
~/.gradle/caches
~/.npm/_cacache
~/.cache/pip
/private/tmp/claude-<current-user-id>
```

Before calling `rm -rf`, CacheWarden verifies that the requested path matches that allowlist, refuses symbolic-link targets, and compares the target's physical parent path with the expected path. This is defense-in-depth against accidentally traversing a redirected cache path.

That allowlist applies only to CacheWarden's **direct** recursive deletion. Two optional cleanup actions are delegated to their owning package managers:

- `python3 -m pip cache purge`
- `brew cleanup`

Those commands determine their own cache-cleanup scope. They are not represented by the four direct paths above.

## What it does not intentionally target

CacheWarden does **not** intentionally target:

- Documents or Downloads
- Source repositories
- Application databases or settings
- Android virtual devices or SDK system images
- Downloaded AI models
- Xcode installations or archives
- Protected Apple system caches

The package-manager commands described above remain governed by pip and Homebrew themselves, so review their behavior on your machine if that distinction matters to your workflow.

## Requirements

- macOS
- Z shell (`/bin/zsh`, included with current macOS versions)
- `launchd` / `launchctl`
- Optional: Homebrew and Python 3

## Install

Clone the repository, review the files, and run the installer:

```bash
git clone https://github.com/JosephJMWalker-MBA/CacheWarden.git
cd CacheWarden
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

The configuration file is parsed as data; it is **not sourced or evaluated as shell code**. CacheWarden accepts only the six documented keys above. `THRESHOLD_GB` must be a non-negative whole number, cleanup toggles must be `0` or `1`, and unknown or malformed settings cause the run to fail closed.

The installer creates the configuration with user-only permissions (`600`). Keep it user-owned and do not use it as a general shell startup file.

## Run manually

Normal threshold-aware run:

```bash
~/.local/bin/cachewarden
```

Inspect the direct targets and requested delegated actions without deleting anything:

```bash
~/.local/bin/cachewarden --dry-run
```

For a first-run audit, bypass the storage threshold while still preventing deletion:

```bash
~/.local/bin/cachewarden --dry-run --force
```

Force a real cleanup even when free space is above the threshold:

```bash
~/.local/bin/cachewarden --force
```

### Dry-run boundary

In dry-run mode:

- direct allowlisted paths are measured and reported but not removed;
- pip cleanup is reported as the command that would be requested rather than enumerating every pip-managed target; and
- Homebrew is asked to preview cleanup with `brew cleanup -n`.

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

The uninstaller removes the LaunchAgent and installed executable. It preserves the configuration and logs unless you explicitly choose to remove them with `./uninstall.sh --purge`.

## Design principles

1. **Inspect before deleting.** The direct cleanup scope is visible and intentionally small.
2. **Thresholds over constant purging.** Caches improve development speed and should not be erased without a reason.
3. **User files are out of scope.** CacheWarden is designed around reproducible development artifacts, not creative work.
4. **Fail closed on ambiguous paths or configuration.** Unknown settings and redirected direct-delete paths are refused rather than guessed through.
5. **No elevated privileges.** A personal maintenance tool should not require system-wide authority.
6. **Reversible installation.** Every installed component has a documented removal path.

## Testing and verification status

This repository currently does **not** include an automated test suite for destructive behavior or cross-version macOS compatibility. The implementation should therefore be treated as an early public utility rather than a broadly validated storage-management product.

Before relying on it:

1. read `bin/cachewarden.zsh`;
2. inspect your configuration;
3. run `cachewarden --dry-run --force`;
4. review the reported direct paths and delegated commands; and
5. only then allow a real cleanup run.

Reports about unexpected behavior, additional safe cache targets, and macOS compatibility are welcome through GitHub Issues.
