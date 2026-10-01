#!/bin/bash
# gitsync — keep git repos in sync across Macs.
#   gitsync pull    fetch + fast-forward clean repos that are behind
#   gitsync check   notify about uncommitted/unpushed work idle for IDLE_HOURS
#   gitsync run     pull, then check (what launchd calls)
#   gitsync status  print a one-line status per repo
# Bash 3.2 compatible (macOS default shell).

set -u

CONF_DIR="${GITSYNC_CONF_DIR:-$HOME/.config/gitsync}"
STATE_DIR="${GITSYNC_STATE_DIR:-$HOME/.local/state/gitsync}"
REPOS_FILE="$CONF_DIR/repos"
CONF_FILE="$CONF_DIR/config"

# Defaults (override in $CONF_FILE)
IDLE_HOURS=2        # dirty/unpushed and untouched for this long -> notify
REMIND_HOURS=4      # don't repeat the same reminder more often than this
FETCH_TIMEOUT=30    # seconds per repo fetch

[ -f "$CONF_FILE" ] && . "$CONF_FILE"

export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=10}"

mkdir -p "$STATE_DIR"
LOG="$STATE_DIR/gitsync.log"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"; }

notify() { # title, message
  if command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"${2//\"/\\\"}\" with title \"${1//\"/\\\"}\"" >/dev/null 2>&1
  else
    echo "[notify] $1: $2"
  fi
  log "NOTIFY $1: $2"
}

if [ "$(uname)" = Darwin ]; then mtime() { stat -f %m "$1" 2>/dev/null || echo 0; }; else mtime() { stat -c %Y "$1" 2>/dev/null || echo 0; }; fi

# notify at most once per REMIND_HOURS for a given repo+kind
notify_throttled() { # repo, kind, title, msg
  local f="$STATE_DIR/$(echo "$1" | tr '/' '_').$2" now; now="$(date +%s)"
  if [ -f "$f" ] && [ $(( now - $(cat "$f") )) -lt $(( REMIND_HOURS * 3600 )) ]; then return; fi
  notify "$3" "$4"; echo "$now" > "$f"
}

expand() { case "$1" in "~"*) echo "$HOME${1#\~}";; *) echo "$1";; esac; }

# List repos: each line in $REPOS_FILE is a repo, or a folder whose direct
# children are scanned for repos. Blank lines and # comments ignored.
list_repos() {
  [ -f "$REPOS_FILE" ] || { echo "No repo list at $REPOS_FILE" >&2; return 1; }
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"; line="$(echo "$line" | sed 's/[[:space:]]*$//;s/^[[:space:]]*//')"
    [ -z "$line" ] && continue
    p="$(expand "$line")"
    if [ -e "$p/.git" ]; then echo "$p"
    elif [ -d "$p" ]; then
      for c in "$p"/*; do [ -e "$c/.git" ] && echo "$c"; done
    else log "WARN missing path: $p"
    fi
  done < "$REPOS_FILE"
}

name_of() { basename "$1"; }

has_upstream() { git -C "$1" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; }

# tracked changes (staged or unstaged); untracked files don't block a pull
is_dirty_tracked() { ! git -C "$1" diff --quiet 2>/dev/null || ! git -C "$1" diff --cached --quiet 2>/dev/null; }

has_any_changes() { [ -n "$(git -C "$1" status --porcelain 2>/dev/null)" ]; }

ahead_behind() { # prints "ahead behind"
  git -C "$1" rev-list --left-right --count 'HEAD...@{u}' 2>/dev/null | awk '{print $1, $2}'
}

with_timeout() { # secs, cmd...
  local s="$1"; shift
  "$@" & local pid=$!
  ( sleep "$s"; kill "$pid" 2>/dev/null ) & local w=$!
  wait "$pid" 2>/dev/null; local rc=$?
  kill "$w" 2>/dev/null; wait "$w" 2>/dev/null
  return $rc
}

pull_repo() {
  local r="$1" n; n="$(name_of "$r")"
  has_upstream "$r" || { log "SKIP $n: no upstream"; return; }
  if ! with_timeout "$FETCH_TIMEOUT" git -C "$r" fetch --quiet --prune; then
    log "FAIL $n: fetch failed (offline or auth?)"; return
  fi
  set -- $(ahead_behind "$r"); local ahead="${1:-0}" behind="${2:-0}"
  [ "$behind" -eq 0 ] && { log "OK   $n: up to date"; rm -f "$STATE_DIR/$(echo "$r" | tr '/' '_')".{diverged,blocked}; return; }
  if [ "$ahead" -gt 0 ]; then
    notify_throttled "$r" diverged "gitsync: $n diverged" "$ahead local / $behind remote commits — merge or rebase manually."
    return
  fi
  if is_dirty_tracked "$r"; then
    notify_throttled "$r" blocked "gitsync: $n not pulled" "$behind new commit(s) on remote, but you have uncommitted changes."
    return
  fi
  if git -C "$r" merge --ff-only --quiet '@{u}' >/dev/null 2>&1; then
    log "PULL $n: fast-forwarded $behind commit(s)"
    PULLED="$PULLED $n"
  else
    notify "gitsync: $n pull failed" "Fast-forward failed (untracked file conflict?)."
  fi
}

# Last activity = newest mtime among changed/untracked files, else last commit time.
last_activity() {
  local r="$1" newest=0 t f
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    t="$(mtime "$r/$f")"; [ "$t" -gt "$newest" ] && newest="$t"
  done <<EOF
$(git -C "$r" ls-files -m -o --exclude-standard 2>/dev/null; git -C "$r" diff --cached --name-only 2>/dev/null)
EOF
  t="$(git -C "$r" log -1 --format=%ct 2>/dev/null || echo 0)"
  [ "$t" -gt "$newest" ] && newest="$t"
  echo "$newest"
}

check_repo() {
  local r="$1" n reason="" ahead=0
  n="$(name_of "$r")"
  has_any_changes "$r" && reason="uncommitted changes"
  if has_upstream "$r"; then
    set -- $(ahead_behind "$r"); ahead="${1:-0}"
    [ "$ahead" -gt 0 ] && reason="${reason:+$reason + }$ahead unpushed commit(s)"
  elif [ -n "$(git -C "$r" symbolic-ref -q HEAD 2>/dev/null)" ]; then
    reason="${reason:+$reason + }branch has no upstream"
  fi
  local key="$STATE_DIR/$(echo "$r" | tr '/' '_').idle"
  [ -z "$reason" ] && { rm -f "$key"; return; }
  local now idle; now="$(date +%s)"
  idle=$(( (now - $(last_activity "$r")) / 3600 ))
  [ "$idle" -lt "$IDLE_HOURS" ] && return
  notify_throttled "$r" idle "gitsync: forgot to push $n?" "$reason, idle ${idle}h."
}

status_repo() {
  local r="$1" n s=""; n="$(name_of "$r")"
  has_any_changes "$r" && s="dirty"
  if has_upstream "$r"; then
    set -- $(ahead_behind "$r")
    [ "${1:-0}" -gt 0 ] && s="$s ahead:$1"
    [ "${2:-0}" -gt 0 ] && s="$s behind:$2"
  else s="$s no-upstream"; fi
  printf '%-30s %s\n' "$n" "${s:-clean}"
}

cmd="${1:-run}"
REPOS="$(list_repos)" || exit 1
PULLED=""

do_each() { # fn
  while IFS= read -r r; do [ -n "$r" ] && "$1" "$r"; done <<EOF
$REPOS
EOF
  return 0
}
do_pull() {
  do_each pull_repo
  [ -n "$PULLED" ] && notify "gitsync: pulled" "Updated:$PULLED"
  return 0
}

case "$cmd" in
  pull)   do_pull ;;
  check)  do_each check_repo ;;
  run)    do_pull; do_each check_repo ;;
  status) do_each status_repo ;;
  *) sed -n '2,7p' "$0"; exit 1 ;;
esac
