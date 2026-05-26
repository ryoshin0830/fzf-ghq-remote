# fzf-ghq-remote

A `Ctrl-]` zsh widget that fuzzy-searches across **local ghq main clones + git worktrees + remote (un-cloned) repos on GitHub / GHES**, and toggles into **code-content search** with `Ctrl-T`.

When you launch it from inside a git repo with a web remote, the picker also surfaces a **`🌍 here`** entry at the top — selecting it opens that repo in your browser via `gh browse`.

Selecting a remote repo runs `ghq get` and `cd` into it. Selecting a code-search hit also opens the matched file in `$EDITOR`.

## Why

- `ghq list` only shows main clones, not worktrees.
- `gwq list` shows worktrees but not remote repos.
- `fzf` is a fuzzy filter — it doesn't know about any of them.
- `gh` knows about GitHub and GHES — pipe its output through fzf and you get one unified picker.

This widget glues them all together with sensible UX:

- Type → fzf filters whatever is already loaded (no API calls).
- `Tab` or `Enter` (when 0 matches) → fire one `gh search` call.
- `Ctrl-T` → flip between repo-name and file-content search.

## Requirements

| Tool | Required? | Version |
|---|---|---|
| zsh | yes | any modern |
| [fzf](https://github.com/junegunn/fzf) | yes | >= 0.50 (for `transform:` action) |
| [gh](https://cli.github.com/) | yes | >= 2.0 |
| [ghq](https://github.com/x-motemen/ghq) | yes | any |
| awk, paste | yes | any POSIX |
| [gwq](https://github.com/d-kuro/gwq) | optional | enables worktree-aware listing |
| jq | optional | required if gwq is used |

You must be authenticated with `gh auth login` for every host you want to search. Without `gwq`/`jq`, the widget falls back to `ghq list -p` (main clones only, no worktree visibility).

## Install

Clone wherever you like (e.g. with ghq):

```sh
ghq get https://github.com/ryoshin0830/fzf-ghq-remote
```

### Plain zsh

In your `~/.zshrc`:

```zsh
# Configure (set at least one host)
export FZF_GHQ_GITHUB_OWNER="your-github-login"
export FZF_GHQ_GHES_HOST="git.example.com"
export FZF_GHQ_GHES_OWNER="your-ghes-org"
# export FZF_GHQ_KEY='^]'   # default

source "$(ghq root)/github.com/ryoshin0830/fzf-ghq-remote/fzf-ghq-remote.plugin.zsh"
```

### Oh My Zsh

Symlink the cloned repo into `$ZSH_CUSTOM/plugins/` (defaults to `~/.oh-my-zsh/custom/plugins/`):

```sh
ln -s "$(ghq root)/github.com/ryoshin0830/fzf-ghq-remote" \
      "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/fzf-ghq-remote"
```

Then in your `~/.zshrc`, add the plugin name to the `plugins=()` array and export the config **before** `source $ZSH/oh-my-zsh.sh` (because Oh My Zsh sources plugins from inside that line, and `FZF_GHQ_KEY` is read at source time):

```zsh
plugins=(git fzf-ghq-remote)

# Configure (set at least one host) — must be before oh-my-zsh.sh is sourced
export FZF_GHQ_GITHUB_OWNER="your-github-login"
export FZF_GHQ_GHES_HOST="git.example.com"
export FZF_GHQ_GHES_OWNER="your-ghes-org"
# export FZF_GHQ_KEY='^]'   # default

source $ZSH/oh-my-zsh.sh
```

## Usage

Press **Ctrl-]** to launch.

### repo-name mode (default)

| key | action |
|---|---|
| type | filter currently-loaded candidates (local main + worktrees, plus remote when net is on) |
| `Tab` | toggle remote search on/off — prompt shows `repo🌐> ` when on, `repo> ` when off |
| `Enter` | if any item matches: `cd` (local) or `ghq get && cd` (remote); if 0 matches: flip net on and run search |
| `Ctrl-T` | switch to code mode |
| `Esc` | abort |

Initial listing is `gwq list -g` (your local main clones **and** worktrees, with branch info) — shown instantly with no API call. Falls back to `ghq list -p` if `gwq`/`jq` is unavailable.

Items are tagged with:

- `🌍 here` — the repo your cwd is in, opens in browser via `gh browse` (only when cwd is inside a git repo with a web remote)
- `🌳 main` — main ghq clone
- `🌿 worktree` — additional git worktree (only when gwq is installed)
- `🌐 gh.com` / `🌐 ghes` — remote repo found via `gh search repos`. **Remote hits that already exist locally are suppressed** so you pick the `🌳` row (= just `cd`) instead of re-`ghq get`-ing.

### code mode (after Ctrl-T)

| key | action |
|---|---|
| type | refine the query |
| `Tab` | re-fetch with the current query |
| `Enter` | if any item matches: `cd && $EDITOR <path>` (local) or `ghq get && cd && $EDITOR <path>` (remote); if 0 matches: run search |
| `Ctrl-T` | back to repo mode |

The preview pane shows the first 60 lines of the matched file. When the repo is already local, the file is read directly off disk; otherwise it's fetched via `gh api repos/.../contents/...`.

## Rate limits

GitHub's search API is rate-limited:

- `gh search repos`: 30 requests / minute / user
- `gh search code`: 10 requests / minute / user

This widget intentionally avoids live-per-keystroke search — it only fires when net is on (toggled by `Tab` in repo mode) or `Enter` on an empty result list. Typing alone is free.

## Customization

The widget hardcodes a few choices that you can edit in `fzf-ghq-remote.plugin.zsh`:

- `--limit 30` per host: bump up if you want more results per search
- `head -10` / `head -30` / `head -60` in the preview: adjust preview length
- emoji prefixes (`📦` / `🌐` / `🔎`): purely cosmetic, used for case-matching
- `${EDITOR:-less}` as the file opener after a code hit

## How it works

1. The widget writes a small shell-script generator to a temp file (`$FZF_GHQ_GEN_FILE`), a mode flag (`repo`/`code`) to `$FZF_GHQ_MODE_FILE`, a net flag (`off`/`on`) to `$FZF_GHQ_NET_FILE`, and a snapshot of `ghq list` to `$FZF_GHQ_LOCAL_SET_FILE` (used to dedup remote hits against local clones).
2. fzf is launched with an initial run of the generator (local main+worktree only, fast — net starts off).
3. `Tab` flips the net flag, updates the prompt (`repo> ` ⇄ `repo🌐> `), and reloads. When net is on and the query is ≥ 2 chars, the generator additionally calls `gh search repos`/`gh search code` and pipes the result through `awk` to drop any row whose `host/owner/repo` is already in the local set.
4. `Ctrl-T` flips the mode flag, updates the prompt, clears the query, and re-runs the generator with the new mode.
5. `Enter` on a 0-match list flips net to on and reloads (forced remote search).
6. On selection, the widget stuffs the right `cd` / `ghq get && cd` / `$EDITOR` command into `BUFFER` and accepts the line — so you see the command run in your shell history, not hidden inside the widget. For `🔎` rows that have a local-path 4th field, `ghq get` is skipped.

### Row format

Rows are tab-separated with 3 fields, plus an optional 4th field used by code-search hits whose repo is already local:

| icon | field 2 | field 3 | field 4 (optional) |
|---|---|---|---|
| 🌍 here | `owner/repo` of current cwd | web URL | — |
| 🌳 main / 🌿 worktree | branch | absolute path (used for `cd`) | — |
| 🌐 gh.com / 🌐 ghes | `owner/repo` | repo description | — (locally-existing repos are suppressed from this group entirely) |
| 🔎 gh.com / 🔎 ghes | `owner/repo` | file path inside the repo | absolute local path of the repo, if it's already cloned — when present, Enter skips `ghq get` and `cd`s directly |

## License

MIT
