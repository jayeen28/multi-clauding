#!/usr/bin/env bash
#
# claude-wipe.sh - remove extra Claude Code accounts made by claude-account.sh.
# Run with --help for the details.
#
# Your main ~/.claude is never touched. Deleting an account folder removes the
# links in it, not the things they point at.
#
# Source it to drop the alias from this shell too:
#                source ./claude-wipe.sh ct4

# ---- sourced? then do the work in bash and unalias here ---------------------

_cw_sourced=0
if [ -n "${ZSH_VERSION:-}" ]; then
  case "${ZSH_EVAL_CONTEXT:-}" in *:file*) _cw_sourced=1 ;; esac
elif [ -n "${BASH_VERSION:-}" ]; then
  (return 0 2>/dev/null) && _cw_sourced=1
fi

if [ "$_cw_sourced" = 1 ]; then
  if [ -n "${ZSH_VERSION:-}" ]; then
    _cw_self="$(eval 'printf "%s" "${(%):-%x}"')"
  else
    _cw_self="${BASH_SOURCE[0]}"
  fi
  if [ ! -f "$_cw_self" ] || [ ! -r "$_cw_self" ]; then
    printf '%s\n' "Stopped: this was sourced from a pipe, so the script cannot" >&2
    printf '%s\n' "re-read itself. Save it to a file first:" >&2
    printf '%s\n' "  curl -fsSLO https://raw.githubusercontent.com/jayeen28/multi-clauding/main/claude-wipe.sh" >&2
    printf '%s\n' "  source ./claude-wipe.sh <names>" >&2
    unset _cw_sourced _cw_self
    return 1
  fi
  bash "$_cw_self" "$@" || return $?
  for _cw_n in "$@"; do
    case "$_cw_n" in -*) continue ;; esac
    unalias "$_cw_n" 2>/dev/null && printf '  alias %s is gone from this shell\n' "$_cw_n"
  done
  unset _cw_sourced _cw_self _cw_n
  return 0
fi
unset _cw_sourced

set -uo pipefail

MAIN="${CLAUDE_MAIN_DIR:-$HOME/.claude}"

DRY=0
ALL=0
YES=0
KEEP_DIR=0
BACKUPS=0
NAMES=()
RC_BACKED_UP=0

say()  { printf '%s\n' "$*"; }
step() { printf '  %s\n' "$*"; }
die()  { printf 'Stopped: %s\n' "$*" >&2; exit 1; }
run()  { if [ "$DRY" = 1 ]; then printf '  would: %s\n' "$*"; else "$@"; fi; }
did()  { [ "$DRY" = 1 ] || step "$*"; }

usage() { cat <<'EOF'
claude-wipe.sh - remove extra Claude Code accounts made by claude-account.sh.

  ./claude-wipe.sh ct4 research

For each name it:
  1. takes the alias line for that account out of your shell file
  2. deletes the folder ~/.claude-<name>

Your main ~/.claude is never touched, and neither is anything the links in that
folder point at. What goes for good is that account's own login and its own
session history, so you will have to sign in again if you make it anew.

It asks before it deletes. Use --yes to skip the question, which you must do
when piping the script into bash.

Options:
  --all         every account it can find
  --keep-dir    only take out the alias, leave the folder where it is
  --backups     also delete the ~/.claude-migration-backup-* folders
  --dry-run     show what it would do, change nothing
  --yes, -y     do not ask
  --list        show the accounts you have
  -h, --help    this text

To drop the alias from the shell you are in as well:  source ./claude-wipe.sh ct4
EOF
}

accounts() {
  local d
  for d in "$HOME"/.claude-*; do
    case "$d" in *-migration-backup-*|*'*') continue ;; esac
    [ -d "$d" ] || continue
    printf '%s\n' "${d##*/.claude-}"
  done
}

# ---- which shell file holds the aliases -------------------------------------

shell_file() {
  case "${SHELL##*/}" in
    zsh)  printf '%s\n' "$HOME/.zshrc" ;;
    bash) if [ -f "$HOME/.bash_profile" ] && [ "$(uname)" = "Darwin" ]
          then printf '%s\n' "$HOME/.bash_profile"
          else printf '%s\n' "$HOME/.bashrc"; fi ;;
    *)    printf '' ;;
  esac
}

alias_for() {
  local name="$1" rc needle found
  rc="$(shell_file)"
  needle="CLAUDE_CONFIG_DIR=\$HOME/.claude-$name claude"
  found=""
  if [ -n "$rc" ] && [ -f "$rc" ]; then
    found="$(awk -v s="$needle" '
      index($0,s) && $0 ~ /^[[:space:]]*alias[[:space:]]/ {
        line = $0
        sub(/^[[:space:]]*alias[[:space:]]+/, "", line)
        p = index(line, "=")
        if (p > 1) { print substr(line, 1, p - 1); exit }
      }' "$rc")"
  fi
  if [ -n "$found" ]; then printf '%s\n' "$found"; else printf '%s\n' "-"; fi
}

list_accounts() {
  local found=0 n
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    found=1
    printf '  %-24s alias: %s\n' ".claude-$n" "$(alias_for "$n")"
  done <<< "$(accounts)"
  [ "$found" = 1 ] || say "  no extra accounts"
}

# ---- read the options -------------------------------------------------------

while [ $# -gt 0 ]; do
  case "$1" in
    --all)      ALL=1 ;;
    --keep-dir) KEEP_DIR=1 ;;
    --backups)  BACKUPS=1 ;;
    --dry-run)  DRY=1 ;;
    -y|--yes)   YES=1 ;;
    --list)     say "Accounts:"; list_accounts; exit 0 ;;
    -h|--help)  usage; exit 0 ;;
    -*)         die "do not know the option $1. Run with --help." ;;
    *)          NAMES+=("$1") ;;
  esac
  shift
done

if [ "$ALL" = 1 ]; then
  [ "${#NAMES[@]}" = 0 ] || die "use names or --all, not both."
  while IFS= read -r n; do [ -n "$n" ] && NAMES+=("$n"); done <<< "$(accounts)"
  [ "${#NAMES[@]}" -gt 0 ] || { say "No extra accounts to remove."; exit 0; }
fi

[ "${#NAMES[@]}" -gt 0 ] || { usage; exit 1; }

backup_rc_once() {
  local rc="$1"
  [ "$RC_BACKED_UP" = 0 ] || return 0
  [ -f "$rc" ] || return 0
  cp "$rc" "$rc.claude-wipe.bak" && RC_BACKED_UP=1
}

drop_alias() {
  local name="$1" rc needle lines tmp
  rc="$(shell_file)"
  needle="CLAUDE_CONFIG_DIR=\$HOME/.claude-$name claude"
  [ -n "$rc" ] && [ -f "$rc" ] || { step "no shell file to clean"; return 0; }

  lines="$(awk -v s="$needle" 'index($0,s) && $0 ~ /^[[:space:]]*alias[[:space:]]/' "$rc")"
  if [ -z "$lines" ]; then
    step "no alias line in $(basename "$rc")"
    return 0
  fi
  if [ "$DRY" = 1 ]; then
    printf '  would remove from %s: %s\n' "$(basename "$rc")" "$lines"
    return 0
  fi
  backup_rc_once "$rc"
  tmp="$rc.claude-wipe.tmp"
  awk -v s="$needle" '!(index($0,s) && $0 ~ /^[[:space:]]*alias[[:space:]]/)' "$rc" > "$tmp" \
    && cp "$tmp" "$rc" && rm -f "$tmp"
  step "removed from $(basename "$rc"): $lines"
}

# ---- what is in a folder ----------------------------------------------------

describe_dir() {
  local dir="$1" links reals size
  links="$(find "$dir" -maxdepth 1 -type l 2>/dev/null | wc -l | tr -d ' ')"
  reals="$(find "$dir" -maxdepth 1 ! -type l ! -path "$dir" 2>/dev/null | wc -l | tr -d ' ')"
  size="$(du -sh "$dir" 2>/dev/null | cut -f1 | tr -d ' ')"
  printf '  %s links back to the main folder, %s of its own, %s on disk\n' \
    "$links" "$reals" "${size:-?}"
}

# ---- check every name before touching anything ------------------------------

TARGETS=()
for name in "${NAMES[@]}"; do
  case "$name" in
    *[!A-Za-z0-9_.-]*|.*|"") die "bad name: $name" ;;
  esac
  dir="$HOME/.claude-$name"
  [ "$dir" != "$MAIN" ] || die "$dir is your main folder. Not removing that."
  [ "$dir" != "$HOME/.claude" ] || die "that is your main folder. Not removing that."
  [ "$dir" != "$HOME" ] && [ "$dir" != "/" ] || die "refusing $dir"
  TARGETS+=("$name")
done

BK=()
if [ "$BACKUPS" = 1 ]; then
  for d in "$HOME"/.claude-migration-backup-*; do
    [ -d "$d" ] || continue
    BK+=("$d")
  done
fi

# ---- show the plan and ask --------------------------------------------------

say "About to remove:"
for name in "${TARGETS[@]}"; do
  dir="$HOME/.claude-$name"
  if [ -d "$dir" ]; then
    say "  $dir"
    describe_dir "$dir"
  else
    say "  $dir  (not there, alias only)"
  fi
done
[ "$KEEP_DIR" = 1 ] && say "  --keep-dir: the folders stay, only the aliases go"
for d in "${BK[@]+"${BK[@]}"}"; do say "  $d  (migration backup)"; done
say "Your main folder $MAIN stays as it is."

if [ "$DRY" = 1 ]; then
  say ""
  say "Dry run. Nothing will change."
elif [ "$YES" != 1 ]; then
  if [ ! -t 0 ]; then
    die "not a terminal, so I cannot ask. Add --yes if you are sure."
  fi
  printf '\nRemove these? [y/N] '
  read -r answer
  case "$answer" in
    y|Y|yes|YES) ;;
    *) say "Left everything alone."; exit 0 ;;
  esac
fi

# ---- do it ------------------------------------------------------------------

for name in "${TARGETS[@]}"; do
  dir="$HOME/.claude-$name"
  say ""
  say "Account $name"
  drop_alias "$name"
  if [ "$KEEP_DIR" = 1 ]; then
    step "kept $dir"
  elif [ -d "$dir" ]; then
    run rm -rf "$dir"
    did "deleted $dir"
  else
    step "no folder at $dir"
  fi
done

for d in "${BK[@]+"${BK[@]}"}"; do
  run rm -rf "$d"
  did "deleted $d"
done

say ""
[ "$RC_BACKED_UP" = 1 ] && say "Your shell file was copied to $(shell_file).claude-wipe.bak first"
if [ "$DRY" = 1 ]; then
  say "Done."
else
  say "Done. The alias is out of your shell file, but this shell still has it"
  say "in memory until you tell it otherwise:"
  say ""
  say "  now:        unalias ${TARGETS[0]}"
  say "  next time:  source ./claude-wipe.sh ${TARGETS[0]}   (does that for you)"
fi
