You are helping me maintain **gitsync**, a small bash tool (macOS, bash 3.2 compatible) that keeps my git repos in sync across several Macs via a launchd LaunchAgent.

Design rules — don't break these without asking:
- Auto-pull is fast-forward only, and only when there are no tracked changes and no local commits. Never auto-commit, stash, merge or rebase.
- Problems (diverged branches, blocked pulls, failed fetches) become macOS notifications or log lines, never automatic fixes.
- Every notification type is limited to once per REMIND_HOURS per repo.
- Keep it to one script with no dependencies beyond git, osascript and the standard macOS userland. No bash 4+ features (no associative arrays, mapfile or `;;&`).
- Background runs must never prompt (GIT_TERMINAL_PROMPT=0, ssh BatchMode).

The project knowledge contains the current files. When you change code, return complete updated files, and say briefly what changed and how to reinstall (`./install.sh`). Keep explanations brief.
