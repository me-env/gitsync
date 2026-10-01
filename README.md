# gitsync

Keeps your git repos in sync across several Macs without manual pulls.

- **Auto-pull:** at login, on wake and every 15 minutes, it fetches each repo and fast-forwards it — **only** if the working tree has no tracked changes and there are no local commits. It never merges, rebases or stashes.
- **"Forgot to push?" reminders:** if a repo has uncommitted changes, unpushed commits or a branch with no upstream, and nothing has changed for `IDLE_HOURS`, you get a macOS notification.
- **Safe alerts:** if a pull is blocked (local edits) or the branches have diverged, you get a notification instead. Every alert type is sent at most once per `REMIND_HOURS` for each repo.

## Install (on each Mac)

```bash
git clone <this repo> ~/gitsync && cd ~/gitsync
./install.sh
open -e ~/.config/gitsync/repos     # add ~/code, or individual repo paths
gitsync status                       # needs ~/.local/bin on PATH
```

The first notification may ask for permission (it comes from "Script Editor"/osascript). Allow it in System Settings → Notifications.

## Commands

| Command          | What it does                                  |
|------------------|-----------------------------------------------|
| `gitsync run`    | pull, then check (what launchd runs)          |
| `gitsync pull`   | fetch + fast-forward clean repos              |
| `gitsync check`  | send "forgot to push?" reminders              |
| `gitsync status` | one line per repo: dirty / ahead / behind     |
| `gitsync add .`  | track the repo containing `.` (closest `.git` parent) |

## Config

- `~/.config/gitsync/repos` lists one path per line: either a repo, or a folder whose direct subfolders are repos.
- `~/.config/gitsync/config` sets `IDLE_HOURS` (2), `REMIND_HOURS` (4) and `FETCH_TIMEOUT` (30 s).
- The log is at `~/.local/state/gitsync/gitsync.log`.

## Auth

Background runs can't prompt for anything. It works with:
- SSH remotes whose key is in the macOS keychain (`ssh-add --apple-use-keychain ~/.ssh/id_ed25519`), or
- HTTPS remotes with `gh auth setup-git` or the osxkeychain credential helper.

If a fetch fails, the log says `fetch failed`.

## Uninstall

`./uninstall.sh` removes the agent and the binary but keeps your config.

## Files

- `gitsync.sh` is the whole tool (bash 3.2, so it runs on stock macOS).
- `launchd/com.gitsync.agent.plist` is the LaunchAgent template, filled in by `install.sh`.
- `config.example` and `repos.example` are copied to `~/.config/gitsync` on first install.
