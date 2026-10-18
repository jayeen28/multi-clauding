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

Or keep a copy, which is worth doing — the script is meant to be re-run:

```bash
curl -fsSLO https://raw.githubusercontent.com/jayeen28/multi-clauding/main/claude-account.sh
chmod +x claude-account.sh
```

Needs bash, and `~/.claude` to exist — start Claude Code once before running it.

## Use

```bash
./claude-account.sh work research client
```

For each name that creates `~/.claude-<name>`, links the shared parts back to
`~/.claude`, and appends an alias to your shell file:

```bash
alias cwork='CLAUDE_CONFIG_DIR=$HOME/.claude-work claude'
```

Then `source ~/.zshrc` once, and `cwork` starts Claude Code on that account.
Sign in to each the first time; the logins are independent and all stay valid.

```
./claude-account.sh <name>...   make or repair accounts
  --no-alias                    folders and links only, leave the shell file alone
  --dry-run                     print what it would do, change nothing
  --list                        list the accounts you already have
  -h, --help                    usage
```

Set `CLAUDE_MAIN_DIR` to share from somewhere other than `~/.claude`.

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
- Give the account name, not the alias: `work`, not `cwork`. The script catches
  that mix-up and tells you.
- Sharing `projects/` means every account reads and writes the same chat history.
  Pass names you are happy to have share a transcript.
