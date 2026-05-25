# fzf-ghq-remote

A `Ctrl-O` zsh widget that fuzzy-searches across **local ghq repos + remote (un-cloned) repos on GitHub / GHES**, and toggles into **code-content search** with `Ctrl-T`.

Selecting a remote repo runs `ghq get` and `cd` into it. Selecting a code-search hit also opens the matched file in `$EDITOR`.

## Why

- `ghq list` only shows what you've already cloned.
- `fzf` is a fuzzy filter — it doesn't know about remote repos.
- `gh` knows about GitHub and GHES — pipe its output through fzf and you get a unified picker.

This widget glues them together with sensible UX:

- Type → fzf filters whatever is already loaded (no API calls).
- `Tab` or `Enter` (when 0 matches) → fire one `gh search` call.
- `Ctrl-T` → flip between repo-name and file-content search.

## Requirements

| Tool | Version |
|---|---|
| zsh | any modern |
| [fzf](https://github.com/junegunn/fzf) | >= 0.50 (for `transform:` action) |
| [gh](https://cli.github.com/) | >= 2.0 |
| [ghq](https://github.com/x-motemen/ghq) | any |
| awk | any POSIX awk |

You must be authenticated with `gh auth login` for every host you want to search.

## Install

Clone wherever you like (e.g. with ghq):

```sh
ghq get https://github.com/ryoshin0830/fzf-ghq-remote
```

Then in your `~/.zshrc`:

```zsh
# Configure (set at least one host)
export FZF_GHQ_GITHUB_OWNER="your-github-login"
export FZF_GHQ_GHES_HOST="git.example.com"
export FZF_GHQ_GHES_OWNER="your-ghes-org"
# export FZF_GHQ_KEY='^O'   # default

source "$(ghq root)/github.com/ryoshin0830/fzf-ghq-remote/fzf-ghq-remote.plugin.zsh"
```

## Usage

Press **Ctrl-O** to launch.

### repo-name mode (default)

| key | action |
|---|---|
| type | filter currently-loaded candidates (local + already-fetched remote) |
| `Tab` | run `gh search repos` with the current query |
| `Enter` | if any item matches: `cd` (local) or `ghq get && cd` (remote); if 0 matches: run search |
| `Ctrl-T` | switch to code mode |
| `Esc` | abort |

Initial listing is `ghq list` (your local clones), shown instantly with no API call.

### code mode (after Ctrl-T)

| key | action |
|---|---|
| type | refine the query |
| `Tab` | run `gh search code` with the current query |
| `Enter` | if any item matches: `ghq get && cd && $EDITOR <path>`; if 0 matches: run search |
| `Ctrl-T` | back to repo mode |

The preview pane shows the first 60 lines of the matched file (fetched via `gh api repos/.../contents/...`), so you can confirm the hit before cloning.

## Rate limits

GitHub's search API is rate-limited:

- `gh search repos`: 30 requests / minute / user
- `gh search code`: 10 requests / minute / user

This widget intentionally avoids live-per-keystroke search — it only fires when you press `Tab`, or `Enter` on an empty result list. Typing alone is free.

## Customization

The widget hardcodes a few choices that you can edit in `fzf-ghq-remote.plugin.zsh`:

- `--limit 30` per host: bump up if you want more results per search
- `head -10` / `head -30` / `head -60` in the preview: adjust preview length
- emoji prefixes (`📦` / `🌐` / `🔎`): purely cosmetic, used for case-matching
- `${EDITOR:-less}` as the file opener after a code hit

## How it works

1. The widget writes a tiny shell-script generator to `$FZF_GHQ_GEN`, plus a mode flag file to `$FZF_GHQ_MODE_FILE`.
2. fzf is launched with an initial run of the generator (just `ghq list`, fast).
3. `Tab` and the 0-match `Enter` re-run the generator via `reload`, this time including remote results from `gh search repos` or `gh search code`.
4. `Ctrl-T` flips the mode flag, updates the prompt, clears the query, and re-runs the generator with the new mode.
5. On selection, the widget stuffs the right `cd` / `ghq get && cd` / `$EDITOR` command into `BUFFER` and accepts the line — so you see the command run in your shell history, not hidden inside the widget.

## License

MIT
