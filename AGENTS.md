# Repository Guidelines

This repository is a small macOS shell automation project for syncing Android
photos into the macOS Photos app. Keep changes narrow, observable, and easy to
audit.

## Think Before Coding

- State assumptions before editing when behavior is ambiguous.
- If multiple interpretations exist, present them instead of choosing silently.
- Prefer the simplest working path. Push back on speculative features,
  configurability, or abstractions that are not needed for the request.
- If something cannot be inferred from `README.md`, `install.sh`, or
  `sync_photos.sh`, ask before changing behavior that affects devices, Photos,
  launchd, or user files.

## Project Shape

- `sync_photos.sh` is the runtime Zsh pipeline. It discovers Android devices on
  port `5566`, uses ADB to pull files from Android camera folders, imports them
  into Photos through AppleScript, logs synced remote paths, and disconnects.
- `install.sh` is the Bash installer. It checks or installs ADB, configures
  wireless debugging, downloads `sync_photos.sh`, and creates a user LaunchAgent.
- `README.md` is the user-facing setup and product explanation.

## Surgical Change Rules

- Touch only files required by the task. Do not rewrite adjacent comments,
  formatting, or messaging unless that line is part of the requested change.
- Match the current script style: explicit sections, straightforward shell, and
  readable status output.
- Remove imports, variables, or helper functions only if your own change made
  them unused. Mention unrelated dead code instead of deleting it.
- Do not add new runtime dependencies unless explicitly requested. The current
  design is macOS built-ins plus Homebrew ADB.

## Verification

- For shell syntax, run:
  - `zsh -n sync_photos.sh`
  - `bash -n install.sh`
- For installer changes, inspect generated paths and LaunchAgent behavior
  carefully. Avoid running `install.sh` unless the user asked for an end-to-end
  install, because it can install packages, prompt for USB setup, write
  `~/Scripts`, and load `launchd` jobs.
- For sync changes, prefer dry inspection and targeted command checks first.
  Running the full script may connect to a real Android device, import into
  Photos, modify `~/Scripts/synced_photos.log`, and delete temp files.

## Goal-Driven Execution

For non-trivial work, use a short plan with explicit checks:

1. Identify the behavior to change and the affected script.
2. Make the smallest patch that implements only that behavior.
3. Verify with syntax checks and any safe targeted command the repo supports.

Every changed line should trace directly to the user's request.
