#!/usr/bin/env bash
#
# claude-account.sh - extra Claude Code accounts that all share one set of
# settings, skills, commands and chat history. Run with --help for the details.
#
# The alias is the name you give. `claude-account.sh ct4` gives you `ct4`.
#
# Safe to pipe:  curl -fsSL <url> | bash -s -- work research client
# Source it to get the alias in this shell straight away:
#                source ./claude-account.sh work

# ---- sourced? then do the work in bash and load the alias here --------------
# A script runs in its own process and cannot add an alias to the shell that
# started it. Sourcing is the way round that, so handle it before anything else.

_ca_sourced=0
if [ -n "${ZSH_VERSION:-}" ]; then
  case "${ZSH_EVAL_CONTEXT:-}" in *:file*) _ca_sourced=1 ;; esac
elif [ -n "${BASH_VERSION:-}" ]; then
  (return 0 2>/dev/null) && _ca_sourced=1
fi

if [ "$_ca_sourced" = 1 ]; then
  if [ -n "${ZSH_VERSION:-}" ]; then
    _ca_self="$(eval 'printf "%s" "${(%):-%x}"')"
    _ca_rc="$HOME/.zshrc"
  else
    _ca_self="${BASH_SOURCE[0]}"
    if [ -f "$HOME/.bash_profile" ] && [ "$(uname)" = "Darwin" ]
    then _ca_rc="$HOME/.bash_profile"; else _ca_rc="$HOME/.bashrc"; fi
  fi
  if [ ! -f "$_ca_self" ] || [ ! -r "$_ca_self" ]; then
    printf '%s\n' "Stopped: this was sourced from a pipe, so the script cannot" >&2
    printf '%s\n' "re-read itself. Save it to a file first:" >&2
    printf '%s\n' "  curl -fsSLO https://raw.githubusercontent.com/jayeen28/multi-clauding/main/claude-account.sh" >&2
    printf '%s\n' "  source ./claude-account.sh <names>" >&2
    unset _ca_sourced _ca_self _ca_rc
    return 1
  fi
  bash "$_ca_self" "$@" || return $?
  if [ -f "$_ca_rc" ]; then
    # shellcheck disable=SC1090
    . "$_ca_rc" && printf '  aliases are live in this shell\n'
  fi
  unset _ca_sourced _ca_self _ca_rc
  return 0
fi
unset _ca_sourced

set -uo pipefail

MAIN="${CLAUDE_MAIN_DIR:-$HOME/.claude}"

# Shared with every account. Folders first, then files.
SHARED_DIRS=(projects skills agents commands output-styles hooks plugins tasks plans file-history)
SHARED_FILES=(settings.json CLAUDE.md history.jsonl)

# Linked only if you already have one. No empty stand-in is made for these,
# because an empty file here can stop Claude Code from starting.
OPTIONAL=(keybindings.json memory.json statusline.sh)

# Deliberately NOT shared, so the accounts stay separate accounts:
#   .claude.json  the login and per-folder state
#   sessions/  cache/  backups/  chrome/  shell-snapshots/  session-env/
#   ide/  todos/  daemon*  statsig/

DRY=0
WRITE_ALIAS=1
NAMES=()
RC_BACKED_UP=0

say()  { printf '%s\n' "$*"; }
step() { printf '  %s\n' "$*"; }
die()  { printf 'Stopped: %s\n' "$*" >&2; exit 1; }
run()  { if [ "$DRY" = 1 ]; then printf '  would: %s\n' "$*"; else "$@"; fi; }
did()  { [ "$DRY" = 1 ] || step "$*"; }

usage() { cat <<'EOF'
claude-account.sh - give yourself extra Claude Code accounts that all share
one set of settings, skills, commands and chat history.

  ./claude-account.sh work research client

For each name it:
  1. makes the folder ~/.claude-<name>
  2. links the shared parts of it back to your main ~/.claude
  3. adds the alias  <name>  to your shell file

So `./claude-account.sh ct4` gives you the command `ct4`. The name you type is
the alias, nothing is added to it. Each account keeps its own login, so you can
be signed in to all of them at the same time.

To use the alias without opening a new shell, source the script instead of
running it:

  source ./claude-account.sh ct4

Run it again any time. It changes nothing that is already correct, and it puts
back any link that Claude Code has overwritten with a real file.

Options:
  --no-alias    just the folder and the links, do not touch the shell file
  --dry-run     show what it would do, change nothing
  --list        show the accounts you already have
  -h, --help    this text

Remove an account again with  ./claude-wipe.sh <name>
EOF
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
  local found=0 d name
  for d in "$HOME"/.claude-*; do
    case "$d" in *-migration-backup-*|*'*') continue ;; esac
    [ -d "$d" ] || continue
    found=1
    name="${d##*/.claude-}"
    printf '  %-24s alias: %s\n' "$(basename "$d")" "$(alias_for "$name")"
  done
  [ "$found" = 1 ] || say "  no extra accounts yet"
}

# ---- read the options -------------------------------------------------------

while [ $# -gt 0 ]; do
  case "$1" in
    --no-alias) WRITE_ALIAS=0 ;;
    --dry-run)  DRY=1 ;;
    --list)     say "Accounts:"; list_accounts; exit 0 ;;
    -h|--help)  usage; exit 0 ;;
    -*)         die "do not know the option $1. Run with --help." ;;
    *)          NAMES+=("$1") ;;
  esac
  shift
done

[ "${#NAMES[@]}" -gt 0 ] || { usage; exit 1; }
[ -d "$MAIN" ] || die "no main folder at $MAIN. Start Claude Code once first."

# ---- make the shared things that do not exist yet ---------------------------

prepare_main() {
  local item
  for item in "${SHARED_DIRS[@]}"; do
    [ -e "$MAIN/$item" ] || { run mkdir -p "$MAIN/$item"; did "made $MAIN/$item"; }
  done
  for item in "${SHARED_FILES[@]}"; do
    [ -e "$MAIN/$item" ] || { run touch "$MAIN/$item"; did "made $MAIN/$item"; }
  done
}

# ---- link one item ----------------------------------------------------------
# target already there and correct -> leave it
# real file or folder in the way   -> move it to the backup folder, then link

BACKUP=""
backup_dir() {
  [ -n "$BACKUP" ] || BACKUP="$HOME/.claude-migration-backup-$(date +%Y%m%d%H%M%S)"
  printf '%s\n' "$BACKUP"
}

link_item() {
  local dir="$1" name="$2" item="$3"
  local target="$MAIN/$item" link="$dir/$item"
  [ -e "$target" ] || return 0

  if [ -L "$link" ]; then
    [ "$(readlink "$link")" = "$target" ] && return 0
    run rm "$link"
  elif [ -e "$link" ]; then
    local bk; bk="$(backup_dir)/$name"
    run mkdir -p "$bk"
    run mv "$link" "$bk/$item"
    did "moved your own $item to $bk/$item"
  fi

  run ln -s "$target" "$link"
  did "linked $item"
}

# ---- the alias line ---------------------------------------------------------
# One alias per account, named exactly as you asked. If an older line points at
# the same folder under a different alias, that line is replaced.

alias_line() {
  printf "alias %s='CLAUDE_CONFIG_DIR=\$HOME/.claude-%s claude'" "$1" "$1"
}

backup_rc_once() {
  local rc="$1"
  [ "$RC_BACKED_UP" = 0 ] || return 0
  [ -f "$rc" ] || return 0
  cp "$rc" "$rc.claude-account.bak" && RC_BACKED_UP=1
}

add_alias() {
  local name="$1" rc want needle old tmp
  rc="$(shell_file)"
  want="$(alias_line "$name")"
  needle="CLAUDE_CONFIG_DIR=\$HOME/.claude-$name claude"

  if [ -z "$rc" ]; then
    say "  add this line to your shell file yourself:"
    say "    $want"
    return 0
  fi

  if [ -f "$rc" ] && grep -qxF "$want" "$rc"; then
    step "alias $name is already in $(basename "$rc")"
    return 0
  fi

  # any alias line for this same account, under any name
  old=""
  if [ -f "$rc" ]; then
    old="$(awk -v s="$needle" 'index($0,s) && $0 ~ /^[[:space:]]*alias[[:space:]]/' "$rc")"
  fi

  if [ "$DRY" = 1 ]; then
    [ -n "$old" ] && step "would replace: $old"
    step "would add alias $name to $(basename "$rc")"
    return 0
  fi

  if [ -n "$old" ]; then
    backup_rc_once "$rc"
    tmp="$rc.claude-account.tmp"
    awk -v s="$needle" '!(index($0,s) && $0 ~ /^[[:space:]]*alias[[:space:]]/)' "$rc" > "$tmp" \
      && cp "$tmp" "$rc" && rm -f "$tmp"
    step "dropped the old line: $old"
  fi

  printf '%s\n' "$want" >> "$rc"
  step "added alias $name to $(basename "$rc")"
}

# ---- check the plugin paths -------------------------------------------------

check_plugins() {
  local f bad=0
  for f in "$MAIN/plugins/installed_plugins.json" "$MAIN/plugins/known_marketplaces.json"; do
    [ -f "$f" ] || continue
    if grep -o '"/[^"]*/\.claude-[^"]*"' "$f" >/dev/null 2>&1; then
      bad=1
      say "Warning: $f still names a per-account folder."
      grep -o '"/[^"]*/\.claude-[^"]*"' "$f" | sort -u | sed 's|^|    |'
    fi
  done
  [ "$bad" = 0 ] || say "  Fix: run  claude plugin install  again from your main account."
}

# ---- do it ------------------------------------------------------------------

say "Main folder: $MAIN"
[ "$DRY" = 1 ] && say "Dry run. Nothing will change."
prepare_main

for name in "${NAMES[@]}"; do
  case "$name" in
    *[!A-Za-z0-9_.-]*|.*|"") die "bad name: $name. Use letters, digits, - _ ." ;;
  esac

  dir="$HOME/.claude-$name"
  say ""
  say "Account $name  ->  $dir"
  [ -d "$dir" ] || { run mkdir -p "$dir"; did "made the folder"; }

  for item in "${SHARED_DIRS[@]}" "${SHARED_FILES[@]}" "${OPTIONAL[@]}"; do
    link_item "$dir" "$name" "$item"
  done

  [ "$WRITE_ALIAS" = 1 ] && add_alias "$name"
done

say ""
check_plugins
[ -n "$BACKUP" ] && [ "$DRY" = 0 ] && say "Your old files are kept in $BACKUP"
[ "$RC_BACKED_UP" = 1 ] && say "Your shell file was copied to $(shell_file).claude-account.bak first"

first="${NAMES[0]}"
if [ "$DRY" = 1 ] || [ "$WRITE_ALIAS" = 0 ]; then
  say "Done."
else
  rc="$(shell_file)"
  say "Done. The alias is in $rc, but this shell has not read it yet:"
  say "a script runs in its own process and cannot change the shell around it."
  say ""
  say "  now:        source $rc && $first"
  say "  or anyway:  CLAUDE_CONFIG_DIR=\$HOME/.claude-$first claude"
  say "  next time:  source ./claude-account.sh $first   (alias live right away)"
fi
