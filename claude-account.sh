#!/usr/bin/env bash
#
# claude-account.sh - give yourself extra Claude Code accounts that all share
# one set of settings, skills, commands and chat history.
#
#   ./claude-account.sh work research client
#
# For each name it:
#   1. makes the folder ~/.claude-<name>
#   2. links the shared parts of it back to your main ~/.claude
#   3. adds the alias  c<name>  to your shell file
#
# Then `cwork` starts Claude Code on that account. Each account keeps its own
# login, so you can be signed in to all of them at the same time.
#
# Run it again any time. It changes nothing that is already correct, and it puts
# back any link that Claude Code has overwritten with a real file.
#
# Options:
#   --no-alias    just the folder and the links, do not touch the shell file
#   --dry-run     show what it would do, change nothing
#   --list        show the accounts you already have
#   -h, --help    this text

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

say()  { printf '%s\n' "$*"; }
step() { printf '  %s\n' "$*"; }
die()  { printf 'Stopped: %s\n' "$*" >&2; exit 1; }
run()  { if [ "$DRY" = 1 ]; then printf '  would: %s\n' "$*"; else "$@"; fi; }

usage() { sed -n '3,23p' "$0" | sed 's|^# \{0,1\}||'; }

list_accounts() {
  local found=0 d
  for d in "$HOME"/.claude-*; do
    case "$d" in *-migration-backup-*) continue ;; esac
    [ -d "$d" ] || continue
    found=1
    printf '  %-28s alias: c%s\n' "$(basename "$d")" "${d##*/.claude-}"
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

# ---- which shell file gets the alias ----------------------------------------

shell_file() {
  case "${SHELL##*/}" in
    zsh)  printf '%s\n' "$HOME/.zshrc" ;;
    bash) if [ -f "$HOME/.bash_profile" ] && [ "$(uname)" = "Darwin" ]
          then printf '%s\n' "$HOME/.bash_profile"
          else printf '%s\n' "$HOME/.bashrc"; fi ;;
    *)    printf '' ;;
  esac
}

# ---- make the shared things that do not exist yet ---------------------------

prepare_main() {
  local item
  for item in "${SHARED_DIRS[@]}"; do
    [ -e "$MAIN/$item" ] || { run mkdir -p "$MAIN/$item"; step "made $MAIN/$item"; }
  done
  for item in "${SHARED_FILES[@]}"; do
    [ -e "$MAIN/$item" ] || { run touch "$MAIN/$item"; step "made $MAIN/$item"; }
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
    step "moved your own $item to $bk/$item"
  fi

  run ln -s "$target" "$link"
  step "linked $item"
}

# ---- the alias line ---------------------------------------------------------

add_alias() {
  local name="$1" rc; rc="$(shell_file)"
  if [ -z "$rc" ]; then
    say "  add this line to your shell file yourself:"
    say "    alias c$name='CLAUDE_CONFIG_DIR=\$HOME/.claude-$name claude'"
    return 0
  fi
  if [ -f "$rc" ] && grep -q "^[[:space:]]*alias c$name=" "$rc"; then
    step "alias c$name is already in $(basename "$rc")"
    return 0
  fi
  if [ "$DRY" = 1 ]; then
    step "would add alias c$name to $(basename "$rc")"
    return 0
  fi
  printf "alias c%s='CLAUDE_CONFIG_DIR=\$HOME/.claude-%s claude'\n" "$name" "$name" >> "$rc"
  step "added alias c$name to $(basename "$rc")"
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
    */*|.*|"") die "bad name: $name" ;;
  esac

  # "cwork" is the alias; "work" is the name. Catch the mix-up.
  if [ ! -d "$HOME/.claude-$name" ] && [ -d "$HOME/.claude-${name#c}" ] && [ "$name" != "${name#c}" ]; then
    say ""
    say "Skipped $name. You already have .claude-${name#c}."
    say "  Give the name, not the alias:  $(basename "$0") ${name#c}"
    continue
  fi

  dir="$HOME/.claude-$name"
  say ""
  say "Account $name  ->  $dir"
  [ -d "$dir" ] || { run mkdir -p "$dir"; step "made the folder"; }

  for item in "${SHARED_DIRS[@]}" "${SHARED_FILES[@]}" "${OPTIONAL[@]}"; do
    link_item "$dir" "$name" "$item"
  done

  [ "$WRITE_ALIAS" = 1 ] && add_alias "$name"
done

say ""
check_plugins
[ -n "$BACKUP" ] && [ "$DRY" = 0 ] && say "Your old files are kept in $BACKUP"
if [ "$DRY" = 0 ] && [ "$WRITE_ALIAS" = 1 ]; then
  rc="$(shell_file)"
  [ -n "$rc" ] && say "Done. Run  source $rc  once, then start with  c${NAMES[0]}"
else
  say "Done."
fi
