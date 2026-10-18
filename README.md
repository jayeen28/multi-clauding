# claude-account

Run several Claude Code accounts side by side, signed in to all of them at once,
sharing one set of settings, skills, commands and chat history.

Claude Code keeps everything in `~/.claude` and reads the location from
`CLAUDE_CONFIG_DIR`. Point that at a second folder and you get a second account —
but also a second, empty copy of all your settings and skills. This script makes
the second folder and symlinks the parts worth sharing back to your main one, so
every account sees the same configuration while keeping its own login.

## Install

Straight from the web, no download:

```bash
curl -fsSL https://raw.githubusercontent.com/jayeen28/multi-clauding/main/claude-account.sh | bash -s -- work research client
```

`-s --` is what passes your account names through the pipe to the script.

That makes the accounts and writes the aliases, but the alias will not work in
the terminal you typed it in until that shell reads its startup file again —
`bash` on the right of a pipe is a separate process and cannot reach back into
your shell. For a one-liner that leaves the alias ready to use, download first
and source it:

```bash
curl -fsSL https://raw.githubusercontent.com/jayeen28/multi-clauding/main/claude-account.sh -o /tmp/ca.sh \
  && source /tmp/ca.sh work research client
```

`source <(curl ...)` does **not** work — the script needs to re-read itself from
a real file, and it will tell you so rather than half-finish.

Or keep a copy, which is worth doing — the script is meant to be re-run:

```bash
curl -fsSLO https://raw.githubusercontent.com/jayeen28/multi-clauding/main/claude-account.sh
curl -fsSLO https://raw.githubusercontent.com/jayeen28/multi-clauding/main/claude-wipe.sh
chmod +x claude-account.sh claude-wipe.sh
```

Needs bash, and `~/.claude` to exist — start Claude Code once before running it.

## Use

```bash
./claude-account.sh work research client
```

For each name that creates `~/.claude-<name>`, links the shared parts back to
`~/.claude`, and appends an alias to your shell file. **The alias is the name you
gave, exactly** — nothing is prefixed to it:

```bash
alias work='CLAUDE_CONFIG_DIR=$HOME/.claude-work claude'
```

So `./claude-account.sh ct4` gives you the command `ct4`. Sign in to each account
the first time; the logins are independent and all stay valid.

### Using the alias without a new shell

A script runs in its own process, so it cannot add an alias to the shell that
started it — nothing can. Source the script instead of running it and the alias
is live immediately:

```bash
source ./claude-account.sh work     # alias ready now, no second step
```

Running it the ordinary way works too, it just leaves you one command short:

```bash
./claude-account.sh work
source ~/.zshrc && work             # or just open a new terminal
```

Either way the account itself is usable straight away:
`CLAUDE_CONFIG_DIR=$HOME/.claude-work claude`.

```
./claude-account.sh <name>...   make or repair accounts
  --no-alias                    folders and links only, leave the shell file alone
  --dry-run                     print what it would do, change nothing
  --list                        list the accounts you already have
  -h, --help                    usage
```

Set `CLAUDE_MAIN_DIR` to share from somewhere other than `~/.claude`.

If an alias line for the same account already exists under a different name — a
leftover `cwork` from an older version, say — the run replaces it, after copying
your shell file to `<file>.claude-account.bak`.

## Removing an account

```bash
./claude-wipe.sh work research
```

Takes the alias line out of your shell file and deletes `~/.claude-<name>`. Your
main `~/.claude` is never touched, and deleting the account folder removes the
links in it, not the things they point at. What is gone for good is that
account's own login and its own session cache, so you have to sign in again if
you make it anew.

It prints what it is about to remove and asks first. Source it to drop the alias
from the shell you are in as well:

```bash
source ./claude-wipe.sh work
```

```
./claude-wipe.sh <name>...      remove accounts
  --all                         every account it can find
  --keep-dir                    only take out the alias, leave the folder
  --backups                     also delete the ~/.claude-migration-backup-* folders
  --dry-run                     print what it would do, change nothing
  --yes, -y                     do not ask (required when piped)
  --list                        list the accounts you have
  -h, --help                    usage
```

## Run it again whenever

The script is idempotent. It skips anything already correct, and it restores any
link that Claude Code has replaced with a real file — which happens often enough
that re-running it is the normal way to fix an account that has drifted.

## What is shared

Symlinked into every account, so a change in one shows up in all of them:

| | |
|---|---|
| `projects/` | chat history, per-folder |
| `skills/` `agents/` `commands/` `output-styles/` `hooks/` `plugins/` | everything you have configured |
| `tasks/` `plans/` `file-history/` | work state |
| `settings.json` `CLAUDE.md` `history.jsonl` | settings, memory, prompt history |

Linked only if you already have one — no empty stand-in is created, because an
empty file here can stop Claude Code from starting:

`keybindings.json` · `memory.json` · `statusline.sh`

## What is not shared

Deliberately left per-account, because this is what keeps them separate accounts:

`.claude.json` (the login and per-folder state) · `sessions/` · `cache/` ·
`backups/` · `chrome/` · `shell-snapshots/` · `session-env/` · `ide/` ·
`todos/` · `daemon*` · `statsig/`

## If something is in the way

When a real file or folder already sits where a link needs to go, the script
moves it to `~/.claude-migration-backup-<timestamp>/<account>/<item>` and prints
the path. Nothing is deleted, and each run that has to move something gets its
own timestamped folder. Use `--dry-run` first if you want to see whether yours
would be touched.

## Plugins

Plugin manifests record absolute paths. If `plugins/installed_plugins.json` or
`known_marketplaces.json` still names a per-account folder, the script warns and
prints the offending lines — rerun `claude plugin install` from your main account
to rewrite them.

## Notes

- Aliases go to `~/.zshrc` on zsh, `~/.bash_profile` (macOS) or `~/.bashrc` on
  bash. On any other shell the script prints the line for you to add yourself.
- The name is the alias. `./claude-account.sh ct4` makes `~/.claude-ct4` and the
  command `ct4`. Names may hold letters, digits, `-`, `_` and `.`.
- `--list` shows the alias each account actually has in your shell file, or `-`
  when it has none, so an account made by an older version still reads true.
- Sharing `projects/` means every account reads and writes the same chat history.
  Pass names you are happy to have share a transcript.
