# fzf-ghq-remote.plugin.zsh
#
# Ctrl-] zsh widget that fuzzy-searches:
#   - local ghq main clones
#   - local git worktrees (via gwq, if installed)
#   - remote (un-cloned) repos on github.com
#   - remote (un-cloned) repos on a GHES host
# with Ctrl-T to toggle between repo-name search and code-content search.
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
  local FZF_GHQ_GEN FZF_GHQ_MODE_FILE
  FZF_GHQ_MODE_FILE=$(mktemp -t fzfghq.XXXXXX) || return
  printf 'repo\n' > "$FZF_GHQ_MODE_FILE"

  local gh_owner="${FZF_GHQ_GITHUB_OWNER:-}"
  local ghes_host="${FZF_GHQ_GHES_HOST:-}"
  local ghes_owner="${FZF_GHQ_GHES_OWNER:-}"

  FZF_GHQ_GEN='q="$1"
mode=$(cat "$FZF_GHQ_MODE_FILE" 2>/dev/null || echo repo)
gh_owner="'$gh_owner'"
ghes_host="'$ghes_host'"
ghes_owner="'$ghes_owner'"
if [ "$mode" = "repo" ]; then
  if command -v gwq >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    gwq list -g --json 2>/dev/null \
      | jq -r ".[] | if .is_main then \"🌳 main\t\" + .branch + \"\t\" + .path else \"🌿 worktree\t\" + .branch + \"\t\" + .path end" 2>/dev/null
  else
    paste <(ghq list 2>/dev/null) <(ghq list -p 2>/dev/null) \
      | awk -F"\t" "{print \"🌳 main\t-\t\" \$2}"
  fi
  if [ ${#q} -ge 2 ]; then
    if [ -n "$gh_owner" ]; then
      GH_HOST=github.com gh search repos --owner "$gh_owner" "$q" --limit 30 \
        --json fullName,description \
        -q ".[] | \"🌐 gh.com\t\" + .fullName + \"\t\" + (.description // \"\")" 2>/dev/null
    fi
    if [ -n "$ghes_host" ] && [ -n "$ghes_owner" ]; then
      GH_HOST="$ghes_host" gh search repos --owner "$ghes_owner" "$q" --limit 30 \
        --json fullName,description \
        -q ".[] | \"🌐 ghes\t\" + .fullName + \"\t\" + (.description // \"\")" 2>/dev/null
    fi
  fi
else
  if [ ${#q} -ge 2 ]; then
    if [ -n "$gh_owner" ]; then
      GH_HOST=github.com gh search code --owner "$gh_owner" "$q" --limit 30 \
        --json path,repository \
        -q ".[] | \"🔎 gh.com\t\" + .repository.nameWithOwner + \"\t\" + .path" 2>/dev/null
    fi
    if [ -n "$ghes_host" ] && [ -n "$ghes_owner" ]; then
      GH_HOST="$ghes_host" gh search code --owner "$ghes_owner" "$q" --limit 30 \
        --json path,repository \
        -q ".[] | \"🔎 ghes\t\" + .repository.nameWithOwner + \"\t\" + .path" 2>/dev/null
    fi
  fi
fi'
  export FZF_GHQ_GEN FZF_GHQ_MODE_FILE

  local line type field2 field3 root
  line=$(
    sh -c "$FZF_GHQ_GEN" _ "$LBUFFER" \
    | fzf --ansi --prompt="repo> " --delimiter=$'\t' \
        --query="$LBUFFER" \
        --header="Tab: search  /  Enter: accept (search if 0 matches)  /  Ctrl-T: name ⇄ code" \
        --bind 'tab:reload(sh -c "$FZF_GHQ_GEN" _ {q})' \
        --bind 'enter:transform:if [ "$FZF_MATCH_COUNT" -eq 0 ] && [ -n "$FZF_QUERY" ]; then printf "reload(sh -c \"\$FZF_GHQ_GEN\" _ \"\$FZF_QUERY\")"; else printf "accept"; fi' \
        --bind 'ctrl-t:execute-silent([ "$(cat $FZF_GHQ_MODE_FILE)" = repo ] && echo code > $FZF_GHQ_MODE_FILE || echo repo > $FZF_GHQ_MODE_FILE)+transform-prompt(printf "%s> " "$(cat $FZF_GHQ_MODE_FILE)")+clear-query+reload(sh -c "$FZF_GHQ_GEN" _ "")' \
        --preview 'host=github.com; case {1} in *ghes*) host="'$ghes_host'" ;; esac
case {1} in
  "🌳 main"|"🌿 worktree") git -C {3} log --oneline -10 2>/dev/null ;;
  "🌐"*) GH_HOST=$host gh repo view {2} 2>/dev/null | head -30 ;;
  "🔎"*) GH_HOST=$host gh api "repos/{2}/contents/{3}" -q .content 2>/dev/null | base64 -d 2>/dev/null | head -60 ;;
esac' \
        --preview-window='right:55%:wrap'
  )
  rm -f "$FZF_GHQ_MODE_FILE"
  unset FZF_GHQ_GEN FZF_GHQ_MODE_FILE
  if [ -z "$line" ]; then
    zle reset-prompt
    return
  fi
  type=$(printf '%s' "$line" | awk -F'\t' '{print $1}')
  field2=$(printf '%s' "$line" | awk -F'\t' '{print $2}')
  field3=$(printf '%s' "$line" | awk -F'\t' '{print $3}')
  root=$(ghq root)
  case "$type" in
    "🌳 main"|"🌿 worktree") BUFFER="cd $field3" ;;
    "🌐 gh.com") BUFFER="ghq get https://github.com/$field2 && cd $root/github.com/$field2" ;;
    "🌐 ghes")   BUFFER="ghq get https://$ghes_host/$field2 && cd $root/$ghes_host/$field2" ;;
    "🔎 gh.com") BUFFER="ghq get https://github.com/$field2 && cd $root/github.com/$field2 && \${EDITOR:-less} $field3" ;;
    "🔎 ghes")   BUFFER="ghq get https://$ghes_host/$field2 && cd $root/$ghes_host/$field2 && \${EDITOR:-less} $field3" ;;
  esac
  zle accept-line
}
zle -N fzf-ghq-remote
bindkey "${FZF_GHQ_KEY:-^]}" fzf-ghq-remote
