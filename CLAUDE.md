# AgentSessionNotifier

Menu bar app for macOS 14+ that tracks Claude Code sessions and sends notifications when Claude needs approval or finishes. Swift Package, SwiftUI, no Xcode project. Repo: agent-session-notifier (folder is still called SessionNotifier).

## Build

- `swift build` to check that it compiles (must pass before committing).
- `./build.sh` builds `build/AgentSessionNotifier.app`; `./build.sh --install` installs to /Applications, refreshes the notification icon cache and launches it.
- Ad-hoc signed unless `SIGN_IDENTITY` is set.

## How it works

Claude Code hook → `hook.sh` → `~/Library/Application Support/AgentSessionNotifier/events/*.json` → app. The hook only drops a file and exits; it must never slow Claude down.

- `HookInstaller`: adds/removes the global hooks in `~/.claude/settings.json`, leaves other hooks alone, backs the file up first.
- `EventInbox`: watches the events folder, processes in order, deletes processed files.
- `SessionStore` / `Session`: session state; `Transcript`: reads names and the last reply from transcripts.
- `Notifier`, `TerminalApp` (bring the right terminal to the front), `MenuView`, `MenuBarIcon`.

## Conventions

- English UI and file names (`Install.command`). Plain, descriptive names; the product must not look like an official Anthropic app.
- Watch CPU and energy: no busy loops or tight polling.

## Git

Base branch `dev`, remote `origin`. `dev` → `main` is the release step.
