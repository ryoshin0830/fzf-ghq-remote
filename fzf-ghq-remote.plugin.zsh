# fzf-ghq-remote.plugin.zsh
#
# Ctrl-] zsh widget that fuzzy-searches:
#   - the current repo's web page (if cwd is inside one), via gh browse
#   - local ghq main clones
#   - local git worktrees (via gwq, if installed)
#   - remote (un-cloned) repos on github.com
#   - remote (un-cloned) repos on a GHES host
# with Ctrl-T to toggle between repo-name search and code-content search,
# and Tab to toggle remote search on/off (prompt shows 🌐 when on).
#
# Remote results that already exist locally are suppressed from 🌐 rows
# (the local 🌳/🌿 row covers them). For 🔎 code hits, the row carries the
# local path as a 4th tab-separated field so Enter skips ghq get.
#
# Requirements: zsh, fzf >= 0.50, gh >= 2.0, ghq, awk
# Optional:     gwq + jq (for worktree-aware listing)
#
# Configuration — set in your ~/.zshrc BEFORE sourcing this file:
#   FZF_GHQ_GITHUB_OWNER  github.com login or org (e.g. "alice")
#   FZF_GHQ_GHES_HOST     GHES hostname (e.g. "git.example.com")
#   FZF_GHQ_GHES_OWNER    GHES owner/org (e.g. "my-org")
#   FZF_GHQ_KEY           keybind, default '^]'
#
# Either GITHUB_OWNER or GHES_* can be set; missing ones are skipped.

function fzf-ghq-remote () {
  emulate -L zsh
  local FZF_GHQ_GEN_FILE FZF_GHQ_MODE_FILE FZF_GHQ_NET_FILE FZF_GHQ_LOCAL_SET_FILE FZF_GHQ_ROOT
  FZF_GHQ_GEN_FILE=$(mktemp -t fzfghqgen.XXXXXX)         || return
  FZF_GHQ_MODE_FILE=$(mktemp -t fzfghqmode.XXXXXX)       || { rm -f "$FZF_GHQ_GEN_FILE"; return; }
  FZF_GHQ_NET_FILE=$(mktemp -t fzfghqnet.XXXXXX)         || { rm -f "$FZF_GHQ_GEN_FILE" "$FZF_GHQ_MODE_FILE"; return; }
  FZF_GHQ_LOCAL_SET_FILE=$(mktemp -t fzfghqlocal.XXXXXX) || { rm -f "$FZF_GHQ_GEN_FILE" "$FZF_GHQ_MODE_FILE" "$FZF_GHQ_NET_FILE"; return; }
  printf 'repo\n' > "$FZF_GHQ_MODE_FILE"
  printf 'off\n'  > "$FZF_GHQ_NET_FILE"
  ghq list 2>/dev/null > "$FZF_GHQ_LOCAL_SET_FILE"

  FZF_GHQ_ROOT=$(ghq root 2>/dev/null)
  export FZF_GHQ_GEN_FILE FZF_GHQ_MODE_FILE FZF_GHQ_NET_FILE FZF_GHQ_LOCAL_SET_FILE FZF_GHQ_ROOT
  export FZF_GHQ_GITHUB_OWNER FZF_GHQ_GHES_HOST FZF_GHQ_GHES_OWNER

  # Detect "current repo" once at launch so generator/preview can reuse it.
  local FZF_GHQ_HERE_URL="" FZF_GHQ_HERE_REPO=""
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    FZF_GHQ_HERE_URL=$(gh browse -n 2>/dev/null)
    if [ -n "$FZF_GHQ_HERE_URL" ]; then
      FZF_GHQ_HERE_REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
      [ -z "$FZF_GHQ_HERE_REPO" ] && FZF_GHQ_HERE_REPO="here"
    fi
  fi
  export FZF_GHQ_HERE_URL FZF_GHQ_HERE_REPO

  # Generator script — written to a temp file so awk programs can freely use
  # single quotes without zsh-level quote escaping.
  cat > "$FZF_GHQ_GEN_FILE" <<'GENEOF'
#!/bin/sh
q="$1"
mode=$(cat "$FZF_GHQ_MODE_FILE" 2>/dev/null || echo repo)
net=$(cat "$FZF_GHQ_NET_FILE" 2>/dev/null || echo off)
gh_owner="${FZF_GHQ_GITHUB_OWNER:-}"
ghes_host="${FZF_GHQ_GHES_HOST:-}"
ghes_owner="${FZF_GHQ_GHES_OWNER:-}"

emit_remote_repos() {
  _host="$1"; _owner="$2"; _tag="$3"
  GH_HOST="$_host" gh search repos --owner "$_owner" "$q" --limit 30 \
    --json fullName,description \
    -q '.[] | "\(.fullName)\t\(.description // "")"' 2>/dev/null \
  | awk -F'\t' -v host="$_host" -v tag="$_tag" -v local_file="$FZF_GHQ_LOCAL_SET_FILE" '
      BEGIN { while ((getline l < local_file) > 0) seen[l]=1 }
      !((host "/" $1) in seen) { print tag "\t" $1 "\t" $2 }
    '
}

emit_remote_code() {
  _host="$1"; _owner="$2"; _tag="$3"
  GH_HOST="$_host" gh search code --owner "$_owner" "$q" --limit 30 \
    --json path,repository \
    -q '.[] | "\(.repository.nameWithOwner)\t\(.path)"' 2>/dev/null \
  | awk -F'\t' -v host="$_host" -v tag="$_tag" -v root="$FZF_GHQ_ROOT" -v local_file="$FZF_GHQ_LOCAL_SET_FILE" '
      BEGIN { while ((getline l < local_file) > 0) seen[l]=1 }
      {
        key = host "/" $1
        if (key in seen) print tag "\t" $1 "\t" $2 "\t" root "/" key
        else             print tag "\t" $1 "\t" $2
      }
    '
}

if [ "$mode" = "repo" ]; then
  if [ -n "$FZF_GHQ_HERE_URL" ]; then
    printf "🌍 here\t%s\t%s\n" "$FZF_GHQ_HERE_REPO" "$FZF_GHQ_HERE_URL"
  fi
  if command -v gwq >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    gwq list -g --json 2>/dev/null \
      | jq -r '.[] | if .is_main then "🌳 main\t" + .branch + "\t" + .path else "🌿 worktree\t" + .branch + "\t" + .path end' 2>/dev/null || true
  else
    ghq list -p 2>/dev/null | awk '{print "🌳 main\t-\t" $0}' || true
  fi
  if [ "$net" = "on" ] && [ ${#q} -ge 2 ]; then
    [ -n "$gh_owner" ] && emit_remote_repos "github.com" "$gh_owner" "🌐 gh.com"
    [ -n "$ghes_host" ] && [ -n "$ghes_owner" ] && emit_remote_repos "$ghes_host" "$ghes_owner" "🌐 ghes"
  fi
else
  if [ ${#q} -ge 2 ]; then
    [ -n "$gh_owner" ] && emit_remote_code "github.com" "$gh_owner" "🔎 gh.com"
    [ -n "$ghes_host" ] && [ -n "$ghes_owner" ] && emit_remote_code "$ghes_host" "$ghes_owner" "🔎 ghes"
  fi
fi
exit 0
GENEOF

  local line type field2 field3 field4 root
  line=$(
    sh "$FZF_GHQ_GEN_FILE" "$LBUFFER" \
    | fzf --ansi --prompt="repo> " --delimiter=$'\t' \
        --query="$LBUFFER" \
        --header="Tab: net on⇄off  /  Enter: accept (search if 0 matches)  /  Ctrl-T: name ⇄ code" \
        --bind 'tab:execute-silent([ "$(cat "$FZF_GHQ_MODE_FILE")" = repo ] && { [ "$(cat "$FZF_GHQ_NET_FILE")" = on ] && echo off > "$FZF_GHQ_NET_FILE" || echo on > "$FZF_GHQ_NET_FILE"; })+transform-prompt(printf "%s%s> " "$(cat "$FZF_GHQ_MODE_FILE")" "$([ "$(cat "$FZF_GHQ_NET_FILE")" = on ] && printf 🌐)")+reload(sh "$FZF_GHQ_GEN_FILE" {q})' \
        --bind 'enter:transform:if [ "$FZF_MATCH_COUNT" -eq 0 ] && [ -n "$FZF_QUERY" ]; then echo on > "$FZF_GHQ_NET_FILE"; printf "reload(sh \"\$FZF_GHQ_GEN_FILE\" \"\$FZF_QUERY\")"; else printf "accept"; fi' \
        --bind 'ctrl-t:execute-silent([ "$(cat "$FZF_GHQ_MODE_FILE")" = repo ] && echo code > "$FZF_GHQ_MODE_FILE" || echo repo > "$FZF_GHQ_MODE_FILE")+transform-prompt(printf "%s%s> " "$(cat "$FZF_GHQ_MODE_FILE")" "$([ "$(cat "$FZF_GHQ_NET_FILE")" = on ] && printf 🌐)")+clear-query+reload(sh "$FZF_GHQ_GEN_FILE" "")' \
        --preview '
p3={3}; p4={4}
case {1} in
  "🌍 here") gh repo view 2>/dev/null | head -30 ;;
  "🌳 main"|"🌿 worktree") git -C "$p3" log --oneline -10 2>/dev/null ;;
  "🌐 gh.com") GH_HOST=github.com gh repo view {2} 2>/dev/null | head -30 ;;
  "🌐 ghes")   GH_HOST="$FZF_GHQ_GHES_HOST" gh repo view {2} 2>/dev/null | head -30 ;;
  "🔎 gh.com"|"🔎 ghes")
    if [ -n "$p4" ]; then
      head -60 "$p4/$p3" 2>/dev/null
    elif [ {1} = "🔎 gh.com" ]; then
      GH_HOST=github.com gh api "repos/{2}/contents/{3}" -q .content 2>/dev/null | base64 -d 2>/dev/null | head -60
    else
      GH_HOST="$FZF_GHQ_GHES_HOST" gh api "repos/{2}/contents/{3}" -q .content 2>/dev/null | base64 -d 2>/dev/null | head -60
    fi
    ;;
esac' \
        --preview-window='right:55%:wrap'
  )
  rm -f "$FZF_GHQ_GEN_FILE" "$FZF_GHQ_MODE_FILE" "$FZF_GHQ_NET_FILE" "$FZF_GHQ_LOCAL_SET_FILE"
  unset FZF_GHQ_GEN_FILE FZF_GHQ_MODE_FILE FZF_GHQ_NET_FILE FZF_GHQ_LOCAL_SET_FILE FZF_GHQ_ROOT FZF_GHQ_HERE_URL FZF_GHQ_HERE_REPO
  if [ -z "$line" ]; then
    zle reset-prompt
    return
  fi
  type=$(printf '%s' "$line" | awk -F'\t' '{print $1}')
  field2=$(printf '%s' "$line" | awk -F'\t' '{print $2}')
  field3=$(printf '%s' "$line" | awk -F'\t' '{print $3}')
  field4=$(printf '%s' "$line" | awk -F'\t' '{print $4}')
  root=$(ghq root)
  local ghes_host="${FZF_GHQ_GHES_HOST:-}"
  case "$type" in
    "🌍 here") BUFFER="gh browse" ;;
    "🌳 main"|"🌿 worktree") BUFFER="cd $field3" ;;
    "🌐 gh.com") BUFFER="ghq get https://github.com/$field2 && cd $root/github.com/$field2" ;;
    "🌐 ghes")   BUFFER="ghq get https://$ghes_host/$field2 && cd $root/$ghes_host/$field2" ;;
    "🔎 gh.com")
      if [ -n "$field4" ]; then
        BUFFER="cd $field4 && \${EDITOR:-less} $field3"
      else
        BUFFER="ghq get https://github.com/$field2 && cd $root/github.com/$field2 && \${EDITOR:-less} $field3"
      fi ;;
    "🔎 ghes")
      if [ -n "$field4" ]; then
        BUFFER="cd $field4 && \${EDITOR:-less} $field3"
      else
        BUFFER="ghq get https://$ghes_host/$field2 && cd $root/$ghes_host/$field2 && \${EDITOR:-less} $field3"
      fi ;;
  esac
  zle accept-line
}
zle -N fzf-ghq-remote
bindkey "${FZF_GHQ_KEY:-^]}" fzf-ghq-remote
