#!/usr/bin/env bash

GITHUB_DIR="${GITHUB_DIR:-$HOME/Documents/github}"
STATE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/wezterm"
PINS_FILE="$STATE_ROOT/repo-pins.txt"
CUSTOM_MODES_FILE="$STATE_ROOT/custom-modes.tsv"
MODE_ORDER_FILE="$STATE_ROOT/mode-order.txt"
WINGET_LINKS="$HOME/AppData/Local/Microsoft/WinGet/Links"
LAUNCHER_PATH="${BASH_SOURCE[0]:-$HOME/.config/wezterm/repo-launcher.sh}"
PIN_MARK=$'\u25cf'
STATUS_MESSAGE=""

FZF_THEME=(
  --height=80%
  --reverse
  --border=rounded
  --padding=1,2
  --gap=1
  --no-info
  --no-separator
  --ansi
  --pointer='▸'
  --with-shell='bash -c'
  --header-border=bottom
  --color=bg:#11111b,bg+:#1e1e2e,fg:#cdd6f4,fg+:#ffffff,hl:#a6e3a1,hl+:#a6e3a1,pointer:#a6e3a1,prompt:#a6e3a1,header:#a6e3a1,footer:#6c7086,border:#585b70,header-border:#585b70,marker:#a6e3a1,spinner:#a6e3a1,info:#6c7086,separator:#585b70,preview-bg:#11111b,preview-fg:#cdd6f4,preview-border:#585b70,gutter:#11111b
)

fzf_safe() {
  MSYS_NO_PATHCONV=1 fzf "$@"
}

repo_preview() {
  local repo="$1"
  [[ -z "$repo" ]] && return 0
  local repo_path="$GITHUB_DIR/$repo"

  local green=$'\033[38;2;166;227;161m'
  local dim=$'\033[38;2;108;112;134m'
  local text=$'\033[38;2;205;214;244m'
  local peach=$'\033[38;2;250;179;135m'
  local red=$'\033[38;2;243;139;168m'
  local rst=$'\033[0m'

  printf '\n %s%s%s\n' "$green" "$repo" "$rst"
  printf ' %s%s%s\n\n' "$dim" "────────────────────" "$rst"

  if [[ ! -d "$repo_path" ]]; then
    printf ' %sdirectory missing%s\n' "$red" "$rst"
    return 0
  fi

  if [[ ! -e "$repo_path/.git" ]]; then
    printf ' %snot a git repo%s\n' "$dim" "$rst"
    return 0
  fi

  local branch msg when dirty
  branch="$(cd "$repo_path" && git branch --show-current 2>/dev/null)"
  [[ -z "$branch" ]] && branch='(detached)'

  msg="$(cd "$repo_path" && git log -1 --format='%s' 2>/dev/null)"
  when="$(cd "$repo_path" && git log -1 --format='%ar' 2>/dev/null)"
  dirty="$(cd "$repo_path" && git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"

  printf ' %sbranch%s   %s%s%s\n' "$dim" "$rst" "$green" "$branch" "$rst"
  printf ' %swhen%s     %s%s%s\n'   "$dim" "$rst" "$text"  "$when"   "$rst"
  printf ' %slast%s     %s%s%s\n'   "$dim" "$rst" "$text"  "$msg"    "$rst"

  if [[ "$dirty" == "0" ]]; then
    printf ' %sstatus%s   %sclean%s\n' "$dim" "$rst" "$green" "$rst"
  else
    printf ' %sstatus%s   %s%s modified%s\n' "$dim" "$rst" "$peach" "$dirty" "$rst"
  fi
}

ALL_REPOS=()
PINNED_REPOS=()
FZF_KEY=""
FZF_LINE=""
SELECTED_REPO=""
SELECTED_MODE=""
SELECTED_TARGET=""
MODE_LABEL=""
LAUNCH_ARGS=()

ensure_path() {
  case ":$PATH:" in
    *":$WINGET_LINKS:"*) ;;
    *) PATH="$PATH:$WINGET_LINKS" ;;
  esac
}

require_dependencies() {
  local missing=()

  if [[ -z "${WEZTERM_PANE:-}" ]]; then
    printf 'repos: run this command inside WezTerm.\n' >&2
    return 1
  fi

  if [[ ! -d "$GITHUB_DIR" ]]; then
    printf 'repos: directory not found: %s\n' "$GITHUB_DIR" >&2
    return 1
  fi

  command -v fzf >/dev/null 2>&1 || missing+=("fzf")
  command -v wezterm >/dev/null 2>&1 || missing+=("wezterm")

  if ((${#missing[@]} > 0)); then
    printf 'repos: missing dependency: %s\n' "${missing[*]}" >&2
    return 1
  fi
}

contains_repo() {
  local needle="$1"
  local item
  for item in "${@:2}"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

save_pins() {
  mkdir -p "$STATE_ROOT"
  : > "$PINS_FILE"

  local repo
  for repo in "${PINNED_REPOS[@]}"; do
    printf '%s\n' "$repo" >> "$PINS_FILE"
  done
}

load_repos() {
  mapfile -t ALL_REPOS < <(
    find "$GITHUB_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' |
      grep -v '\-agent\-' |
      grep -v '\.wt$' |
      LC_ALL=C sort
  )
}

load_pins() {
  PINNED_REPOS=()
  local changed=0
  local repo

  if [[ -f "$PINS_FILE" ]]; then
    while IFS= read -r repo; do
      [[ -n "$repo" ]] || continue
      contains_repo "$repo" "${ALL_REPOS[@]}" || {
        changed=1
        continue
      }
      contains_repo "$repo" "${PINNED_REPOS[@]}" && {
        changed=1
        continue
      }
      if ((${#PINNED_REPOS[@]} >= 3)); then
        changed=1
        continue
      fi
      PINNED_REPOS+=("$repo")
    done < "$PINS_FILE"
  fi

  ((changed)) && save_pins
}

toggle_pin() {
  local repo="$1"
  local updated=()
  local item

  if contains_repo "$repo" "${PINNED_REPOS[@]}"; then
    for item in "${PINNED_REPOS[@]}"; do
      [[ "$item" == "$repo" ]] || updated+=("$item")
    done
    PINNED_REPOS=("${updated[@]}")
    save_pins
    STATUS_MESSAGE="Unpinned $repo."
    return
  fi

  if ((${#PINNED_REPOS[@]} >= 3)); then
    STATUS_MESSAGE="Pin limit reached. Remove one of the 3 pinned repos first."
    return
  fi

  PINNED_REPOS+=("$repo")
  save_pins
  STATUS_MESSAGE="Pinned $repo."
}

parse_fzf_output() {
  local output="$1"
  local lines=()
  FZF_KEY=""
  FZF_LINE=""

  mapfile -t lines <<< "$output"
  if ((${#lines[@]} == 1)); then
    FZF_LINE="${lines[0]}"
  elif ((${#lines[@]} >= 2)); then
    FZF_KEY="${lines[0]}"
    FZF_LINE="${lines[1]}"
  fi
}

build_repo_items() {
  local -n _out=$1
  local repo
  local green=$'\033[38;2;166;227;161m'
  local rst=$'\033[0m'
  local pin="${green}${PIN_MARK}${rst}"
  _out=()

  for repo in "${PINNED_REPOS[@]}"; do
    _out+=($'repo\t'"$pin $repo"$'\t'"$repo")
  done

  for repo in "${ALL_REPOS[@]}"; do
    contains_repo "$repo" "${PINNED_REPOS[@]}" && continue
    _out+=($'repo\t'"  $repo"$'\t'"$repo")
  done
}

run_repo_nav() {
  local fzf_args=("${FZF_THEME[@]}")
  local items=()
  local c_green=$'\033[38;2;166;227;161m'
  local c_text=$'\033[38;2;205;214;244m'
  local c_dim=$'\033[38;2;108;112;134m'
  local c_sep=$'\033[38;2;88;91;112m'
  local c_red=$'\033[38;2;243;139;168m'
  local c_rst=$'\033[0m'

  build_repo_items items

  local total=${#ALL_REPOS[@]}
  local pinned=${#PINNED_REPOS[@]}
  local header
  printf -v header ' %sREPOS%s   %s%d%s repos   %s·%s   %s%d/3%s pinned' \
    "$c_green" "$c_rst" \
    "$c_text" "$total" "$c_rst" \
    "$c_sep" "$c_rst" \
    "$c_text" "$pinned" "$c_rst"

  if [[ -n "$STATUS_MESSAGE" ]]; then
    header+=$'\n '"${c_red}→${c_rst} ${c_dim}${STATUS_MESSAGE}${c_rst}"
  fi
  STATUS_MESSAGE=""

  local footer
  printf -v footer ' %senter%s %sopen%s   %s│%s   %s/%s %ssearch%s   %s│%s   %sp%s %spin%s   %s│%s   %sesc%s %sclose%s' \
    "$c_green" "$c_rst" "$c_dim" "$c_rst" "$c_sep" "$c_rst" \
    "$c_green" "$c_rst" "$c_dim" "$c_rst" "$c_sep" "$c_rst" \
    "$c_green" "$c_rst" "$c_dim" "$c_rst" "$c_sep" "$c_rst" \
    "$c_green" "$c_rst" "$c_dim" "$c_rst"

  local output
  output="$(
    printf '%s\n' "${items[@]}" | fzf_safe \
      "${fzf_args[@]}" \
      --delimiter=$'\t' \
      --with-nth=2 \
      --prompt=' ❯ ' \
      --header="$header" \
      --footer="$footer" \
      --no-input \
      --preview="bash '$LAUNCHER_PATH' --preview {3}" \
      --preview-window='right:45%:border-rounded' \
      --expect=p,/,esc
  )"
  local status=$?

  parse_fzf_output "$output"
  return "$status"
}

run_repo_search() {
  local items=()
  local c_green=$'\033[38;2;166;227;161m'
  local c_text=$'\033[38;2;205;214;244m'
  local c_dim=$'\033[38;2;108;112;134m'
  local c_sep=$'\033[38;2;88;91;112m'
  local c_red=$'\033[38;2;243;139;168m'
  local c_rst=$'\033[0m'

  build_repo_items items

  local header
  printf -v header ' %sSEARCH%s   %stype to filter across %d repos%s' \
    "$c_green" "$c_rst" "$c_dim" "${#ALL_REPOS[@]}" "$c_rst"

  if [[ -n "$STATUS_MESSAGE" ]]; then
    header+=$'\n '"${c_red}→${c_rst} ${c_dim}${STATUS_MESSAGE}${c_rst}"
  fi
  STATUS_MESSAGE=""

  local footer
  printf -v footer ' %senter%s %sselect%s   %s│%s   %sp%s %spin%s   %s│%s   %sesc%s %sback%s' \
    "$c_green" "$c_rst" "$c_dim" "$c_rst" "$c_sep" "$c_rst" \
    "$c_green" "$c_rst" "$c_dim" "$c_rst" "$c_sep" "$c_rst" \
    "$c_green" "$c_rst" "$c_dim" "$c_rst"

  local output
  output="$(
    printf '%s\n' "${items[@]}" | fzf_safe \
      "${FZF_THEME[@]}" \
      --delimiter=$'\t' \
      --with-nth=2 \
      --prompt='search ❯ ' \
      --header="$header" \
      --footer="$footer" \
      --preview="bash '$LAUNCHER_PATH' --preview {3}" \
      --preview-window='right:45%:border-rounded' \
      --expect=p,esc
  )"
  local status=$?

  parse_fzf_output "$output"
  return "$status"
}

select_repo() {
  local mode='nav'
  SELECTED_REPO=""

  while true; do
    if [[ "$mode" == 'nav' ]]; then
      run_repo_nav
      local status=$?
      case "$status" in
        0) ;;
        130) return 130 ;;
        *) continue ;;
      esac

      local action label repo
      IFS=$'\t' read -r action label repo <<< "$FZF_LINE"
      case "${FZF_KEY:-enter}" in
        p)
          [[ -n "$repo" ]] && toggle_pin "$repo"
          ;;
        /)
          mode='search'
          ;;
        esc)
          SELECTED_REPO='__EXIT__'
          return 0
          ;;
        *)
          if [[ "$action" == 'repo' && -n "$repo" ]]; then
            SELECTED_REPO="$repo"
            return 0
          fi
          ;;
      esac
    else
      run_repo_search
      local status=$?
      case "$status" in
        0) ;;
        130) return 130 ;;
        *) mode='nav'; continue ;;
      esac

      if [[ "$FZF_KEY" == 'esc' ]]; then
        mode='nav'
        continue
      fi

      local action label repo
      IFS=$'\t' read -r action label repo <<< "$FZF_LINE"
      if [[ "$FZF_KEY" == 'p' ]]; then
        [[ -n "$repo" ]] && toggle_pin "$repo"
        continue
      fi
      if [[ "$action" == 'repo' && -n "$repo" ]]; then
        SELECTED_REPO="$repo"
        return 0
      fi
    fi
  done
}

list_branches() {
  local repo_path="$1"
  (
    cd "$repo_path" || exit 1
    local current
    current="$(git branch --show-current 2>/dev/null)"

    git branch --format='%(refname:short)' 2>/dev/null | while IFS= read -r b; do
      [[ -z "$b" ]] && continue
      if [[ "$b" == "$current" ]]; then
        printf 'current\t%s\n' "$b"
      else
        printf 'local\t%s\n' "$b"
      fi
    done

    local local_branches
    local_branches="|$(git branch --format='%(refname:short)' 2>/dev/null | tr '\n' '|')|"
    git branch -r --format='%(refname:short)' 2>/dev/null | while IFS= read -r b; do
      [[ -z "$b" ]] && continue
      [[ "$b" != */* ]] && continue
      [[ "$b" == *"/HEAD" ]] && continue
      local bare="${b#*/}"
      [[ "$local_branches" == *"|$bare|"* ]] && continue
      printf 'remote\t%s\n' "$b"
    done
  )
}

resolve_worktree() {
  local repo_path="$1"
  local branch="$2"
  local type="$3"

  if [[ "$type" == 'current' ]]; then
    printf '%s' "$repo_path"
    return 0
  fi

  RESOLVE_ERROR=""

  # Windows/git-safe name check: no trailing dot, no leading dash, no shell-hostile chars
  if [[ "$branch" == *.  || "$branch" == *. || "$branch" == -* \
        || "$branch" == *..* || "$branch" == */. || "$branch" == *//* \
        || "$branch" =~ [[:space:]:\\\*\?\<\>\|\"] ]]; then
    RESOLVE_ERROR="invalid branch name: $branch"
    return 1
  fi

  local safe_branch="${branch//\//--}"
  local wt_dir="${repo_path}.wt"
  local wt_path="$wt_dir/$safe_branch"

  mkdir -p "$wt_dir" 2>/dev/null

  if [[ -e "$wt_path/.git" ]]; then
    printf '%s' "$wt_path"
    return 0
  fi

  local log_file="$STATE_ROOT/worktree.log"
  mkdir -p "$STATE_ROOT" 2>/dev/null
  local err
  case "$type" in
    local)
      err="$(cd "$repo_path" && git worktree add "$wt_path" "$branch" 2>&1)"
      ;;
    remote)
      local local_name="${branch#*/}"
      err="$(cd "$repo_path" && git worktree add "$wt_path" -b "$local_name" --track "$branch" 2>&1)"
      ;;
    new)
      err="$(cd "$repo_path" && git worktree add "$wt_path" -b "$branch" 2>&1)"
      ;;
  esac
  printf '[%s] resolve_worktree %s %s\n%s\n\n' "$(date)" "$type" "$branch" "$err" >> "$log_file"

  if [[ -e "$wt_path/.git" ]]; then
    printf '%s' "$wt_path"
    return 0
  fi

  RESOLVE_ERROR="${err%%$'\n'*}"
  [[ -z "$RESOLVE_ERROR" ]] && RESOLVE_ERROR="worktree add failed for $branch"

  # Cleanup: if the branch was created but worktree failed, delete the branch
  case "$type" in
    new)
      (cd "$repo_path" && git branch -D "$branch" >/dev/null 2>&1) || true
      ;;
    remote)
      local local_name="${branch#*/}"
      (cd "$repo_path" && git branch -D "$local_name" >/dev/null 2>&1) || true
      ;;
  esac
  rmdir "$wt_path" 2>/dev/null || true
  return 1
}

prompt_new_branch() {
  NEW_BRANCH_NAME=""
  local repo="$1"
  local c_green=$'\033[38;2;166;227;161m'
  local c_text=$'\033[38;2;205;214;244m'
  local c_dim=$'\033[38;2;108;112;134m'
  local c_sep=$'\033[38;2;88;91;112m'
  local c_rst=$'\033[0m'

  local header
  printf -v header '\n\n %sNEW BRANCH%s   %sREPO%s %s▸%s %s%s%s\n %screates worktree from current branch · type a name%s' \
    "$c_green" "$c_rst" \
    "$c_dim" "$c_rst" \
    "$c_sep" "$c_rst" \
    "$c_text" "$repo" "$c_rst" \
    "$c_dim" "$c_rst"

  local footer
  printf -v footer ' %senter%s %sconfirm%s   %s│%s   %sesc%s %scancel%s' \
    "$c_green" "$c_rst" "$c_dim" "$c_rst" \
    "$c_sep" "$c_rst" \
    "$c_green" "$c_rst" "$c_dim" "$c_rst"

  local output
  output="$(
    printf '' | fzf_safe \
      "${FZF_THEME[@]}" \
      --prompt='name ❯ ' \
      --header="$header" \
      --footer="$footer" \
      --print-query \
      --no-exit-0 \
      --expect=esc
  )"
  local status=$?
  [[ "$status" == 130 ]] && return 130

  local lines=()
  mapfile -t lines <<< "$output"
  local query="${lines[0]:-}"
  local key="${lines[1]:-}"

  if [[ "$key" == 'esc' ]] || [[ -z "$query" ]]; then
    return 1
  fi

  NEW_BRANCH_NAME="$query"
  return 0
}

build_branch_items() {
  local -n _out=$1
  local repo_path="$2"
  local c_green=$'\033[38;2;166;227;161m'
  local c_text=$'\033[38;2;205;214;244m'
  local c_dim=$'\033[38;2;108;112;134m'
  local c_rst=$'\033[0m'

  local type name
  local local_lines=()
  local remote_lines=()

  while IFS=$'\t' read -r type name; do
    [[ -z "$name" ]] && continue
    local safe="${name//\//--}"
    local wt_mark=''
    if [[ -e "${repo_path}.wt/${safe}/.git" ]]; then
      wt_mark=" ${c_dim}[worktree]${c_rst}"
    fi
    case "$type" in
      current)
        local_lines+=("current"$'\t'" ${c_green}●${c_rst} ${c_text}${name}${c_rst}  ${c_dim}(main worktree)${c_rst}"$'\t'"$name")
        ;;
      local)
        local_lines+=("local"$'\t'"   ${c_text}${name}${c_rst}${wt_mark}"$'\t'"$name")
        ;;
      remote)
        remote_lines+=("remote"$'\t'"   ${c_dim}↓ ${name}${c_rst}${wt_mark}"$'\t'"$name")
        ;;
    esac
  done < <(list_branches "$repo_path")

  _out=()
  _out+=("${local_lines[@]}")
  if ((${#remote_lines[@]} > 0)); then
    _out+=("_sep_"$'\t'"   ${c_dim}─────── remote ───────${c_rst}"$'\t'"")
    _out+=("${remote_lines[@]}")
  fi
}

run_branch_nav() {
  local repo="$1"
  local repo_path="$2"

  local c_green=$'\033[38;2;166;227;161m'
  local c_text=$'\033[38;2;205;214;244m'
  local c_dim=$'\033[38;2;108;112;134m'
  local c_sep=$'\033[38;2;88;91;112m'
  local c_red=$'\033[38;2;243;139;168m'
  local c_rst=$'\033[0m'

  local items=()
  build_branch_items items "$repo_path"

  local header
  printf -v header ' %sBRANCHES%s   %sREPO%s %s▸%s %s%s%s' \
    "$c_green" "$c_rst" \
    "$c_dim" "$c_rst" \
    "$c_sep" "$c_rst" \
    "$c_text" "$repo" "$c_rst"

  if [[ -n "$STATUS_MESSAGE" ]]; then
    header+=$'\n '"${c_red}→${c_rst} ${c_dim}${STATUS_MESSAGE}${c_rst}"
  fi
  STATUS_MESSAGE=""

  local footer
  printf -v footer ' %senter%s %scheckout%s   %s│%s   %s/%s %ssearch%s   %s│%s   %sn%s %snew branch%s   %s│%s   %sesc%s %sback%s' \
    "$c_green" "$c_rst" "$c_dim" "$c_rst" "$c_sep" "$c_rst" \
    "$c_green" "$c_rst" "$c_dim" "$c_rst" "$c_sep" "$c_rst" \
    "$c_green" "$c_rst" "$c_dim" "$c_rst" "$c_sep" "$c_rst" \
    "$c_green" "$c_rst" "$c_dim" "$c_rst"

  local output
  output="$(
    printf '%s\n' "${items[@]}" | fzf_safe \
      "${FZF_THEME[@]}" \
      --delimiter=$'\t' \
      --with-nth=2 \
      --prompt=' ❯ ' \
      --header="$header" \
      --footer="$footer" \
      --no-input \
      --preview="bash '$LAUNCHER_PATH' --preview $repo" \
      --preview-window='right:45%:border-rounded' \
      --expect=n,/,esc
  )"
  local status=$?

  parse_fzf_output "$output"
  return "$status"
}

run_branch_search() {
  local repo="$1"
  local repo_path="$2"

  local c_green=$'\033[38;2;166;227;161m'
  local c_text=$'\033[38;2;205;214;244m'
  local c_dim=$'\033[38;2;108;112;134m'
  local c_sep=$'\033[38;2;88;91;112m'
  local c_rst=$'\033[0m'

  local items=()
  build_branch_items items "$repo_path"

  local header
  printf -v header ' %sSEARCH%s   %sREPO%s %s▸%s %s%s%s %s▸%s %sbranches%s' \
    "$c_green" "$c_rst" \
    "$c_dim" "$c_rst" \
    "$c_sep" "$c_rst" \
    "$c_text" "$repo" "$c_rst" \
    "$c_sep" "$c_rst" \
    "$c_dim" "$c_rst"

  local footer
  printf -v footer ' %senter%s %scheckout%s   %s│%s   %sesc%s %sback%s' \
    "$c_green" "$c_rst" "$c_dim" "$c_rst" \
    "$c_sep" "$c_rst" \
    "$c_green" "$c_rst" "$c_dim" "$c_rst"

  local output
  output="$(
    printf '%s\n' "${items[@]}" | fzf_safe \
      "${FZF_THEME[@]}" \
      --delimiter=$'\t' \
      --with-nth=2 \
      --prompt='search ❯ ' \
      --header="$header" \
      --footer="$footer" \
      --preview="bash '$LAUNCHER_PATH' --preview $repo" \
      --preview-window='right:45%:border-rounded' \
      --expect=esc
  )"
  local status=$?

  parse_fzf_output "$output"
  return "$status"
}

select_branch() {
  local repo="$1"
  local repo_path="$GITHUB_DIR/$repo"
  SELECTED_WORKTREE_PATH=""

  (cd "$repo_path" && git worktree prune 2>/dev/null) || true

  local mode='nav'
  while true; do
    if [[ "$mode" == 'nav' ]]; then
      run_branch_nav "$repo" "$repo_path"
      local status=$?
      case "$status" in
        0) ;;
        130) return 130 ;;
        *) continue ;;
      esac

      case "${FZF_KEY:-enter}" in
        esc)
          return 1
          ;;
        /)
          mode='search'
          continue
          ;;
        n)
          if ! prompt_new_branch "$repo"; then
            continue
          fi
          local new_name="$NEW_BRANCH_NAME"
          [[ -z "$new_name" ]] && continue
          local path
          path="$(resolve_worktree "$repo_path" "$new_name" new)"
          if [[ -z "$path" ]]; then
            STATUS_MESSAGE="${RESOLVE_ERROR:-worktree add failed for $new_name}"
            continue
          fi
          SELECTED_WORKTREE_PATH="$path"
          return 0
          ;;
        *)
          local type label branch
          IFS=$'\t' read -r type label branch <<< "$FZF_LINE"
          if [[ "$type" == '_sep_' || -z "$branch" ]]; then
            continue
          fi
          local path
          path="$(resolve_worktree "$repo_path" "$branch" "$type")"
          if [[ -z "$path" ]]; then
            STATUS_MESSAGE="${RESOLVE_ERROR:-worktree add failed for $branch}"
            continue
          fi
          SELECTED_WORKTREE_PATH="$path"
          return 0
          ;;
      esac
    else
      run_branch_search "$repo" "$repo_path"
      local status=$?
      case "$status" in
        0) ;;
        130) return 130 ;;
        *) mode='nav'; continue ;;
      esac

      if [[ "$FZF_KEY" == 'esc' ]]; then
        mode='nav'
        continue
      fi

      local type label branch
      IFS=$'\t' read -r type label branch <<< "$FZF_LINE"
      if [[ "$type" == '_sep_' || -z "$branch" ]]; then
        mode='nav'
        continue
      fi
      local path
      path="$(resolve_worktree "$repo_path" "$branch" "$type")"
      if [[ -z "$path" ]]; then
        STATUS_MESSAGE="${RESOLVE_ERROR:-worktree add failed for $branch}"
        mode='nav'
        continue
      fi
      SELECTED_WORKTREE_PATH="$path"
      return 0
    fi
  done
}

# ---------------------------------------------------------------------
# Launch modes: built-ins, custom modes, and reorder editor
# ---------------------------------------------------------------------
# BUILTIN_MODE_IDS must stay in sync with prepare_launch_mode's case.
# Order here is the default order for a fresh install.
BUILTIN_MODE_IDS=(terminal claude claude-resume codex claude-danger)
BUILTIN_MODE_LABELS=('shell' 'claude' 'claude --resume' 'codex' 'claude UNSAFE')

CUSTOM_MODE_LABELS=()
CUSTOM_MODE_COMMANDS=()
MODE_ORDER=()
CURRENT_REPO=""

is_builtin_mode_id() {
  local id="$1" b
  for b in "${BUILTIN_MODE_IDS[@]}"; do
    [[ "$b" == "$id" ]] && return 0
  done
  return 1
}

is_builtin_label() {
  local label="$1" b
  for b in "${BUILTIN_MODE_LABELS[@]}"; do
    [[ "$b" == "$label" ]] && return 0
  done
  return 1
}

builtin_label_for_id() {
  local id="$1" i
  for ((i=0; i<${#BUILTIN_MODE_IDS[@]}; i++)); do
    if [[ "${BUILTIN_MODE_IDS[$i]}" == "$id" ]]; then
      printf '%s' "${BUILTIN_MODE_LABELS[$i]}"
      return 0
    fi
  done
  printf '%s' "$id"
  return 1
}

load_custom_modes() {
  CUSTOM_MODE_LABELS=()
  CUSTOM_MODE_COMMANDS=()
  [[ -f "$CUSTOM_MODES_FILE" ]] || return 0
  local label command seen_labels=()
  while IFS=$'\t' read -r label command || [[ -n "$label" ]]; do
    label="${label%$'\r'}"
    command="${command%$'\r'}"
    [[ -z "$label" || -z "$command" ]] && continue
    # dedup: skip if label already seen (file corruption safeguard)
    local s dup=0
    for s in "${seen_labels[@]}"; do
      [[ "$s" == "$label" ]] && { dup=1; break; }
    done
    ((dup)) && continue
    seen_labels+=("$label")
    CUSTOM_MODE_LABELS+=("$label")
    CUSTOM_MODE_COMMANDS+=("$command")
  done < "$CUSTOM_MODES_FILE"
}

save_custom_modes() {
  mkdir -p "$STATE_ROOT"
  : > "$CUSTOM_MODES_FILE"
  local i
  for ((i=0; i<${#CUSTOM_MODE_LABELS[@]}; i++)); do
    printf '%s\t%s\n' "${CUSTOM_MODE_LABELS[$i]}" "${CUSTOM_MODE_COMMANDS[$i]}" >> "$CUSTOM_MODES_FILE"
  done
}

find_custom_command() {
  local label="$1" i
  for ((i=0; i<${#CUSTOM_MODE_LABELS[@]}; i++)); do
    if [[ "${CUSTOM_MODE_LABELS[$i]}" == "$label" ]]; then
      printf '%s' "${CUSTOM_MODE_COMMANDS[$i]}"
      return 0
    fi
  done
  return 1
}

load_mode_order() {
  MODE_ORDER=()
  local default_order=("${BUILTIN_MODE_IDS[@]}")
  local label
  for label in "${CUSTOM_MODE_LABELS[@]}"; do
    default_order+=("custom:$label")
  done

  if [[ ! -f "$MODE_ORDER_FILE" ]]; then
    MODE_ORDER=("${default_order[@]}")
    return 0
  fi

  local seen=() line
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ -z "$line" ]] && continue
    # dedup: skip if already seen (file corruption safeguard)
    local s dup=0
    for s in "${seen[@]}"; do
      [[ "$s" == "$line" ]] && { dup=1; break; }
    done
    ((dup)) && continue
    if is_builtin_mode_id "$line"; then
      MODE_ORDER+=("$line")
      seen+=("$line")
    elif [[ "$line" == custom:* ]]; then
      local custom_label="${line#custom:}"
      if find_custom_command "$custom_label" >/dev/null; then
        MODE_ORDER+=("$line")
        seen+=("$line")
      fi
    fi
  done < "$MODE_ORDER_FILE"

  # Append any defaults that weren't in the saved order (new built-ins, new customs)
  local d found s
  for d in "${default_order[@]}"; do
    found=0
    for s in "${seen[@]}"; do
      [[ "$s" == "$d" ]] && { found=1; break; }
    done
    ((found)) || MODE_ORDER+=("$d")
  done
}

save_mode_order() {
  mkdir -p "$STATE_ROOT"
  : > "$MODE_ORDER_FILE"
  local id
  for id in "${MODE_ORDER[@]}"; do
    printf '%s\n' "$id" >> "$MODE_ORDER_FILE"
  done
}

render_mode_meta() {
  local id="$1"
  local c_green=$'\033[38;2;166;227;161m'
  local c_text=$'\033[38;2;205;214;244m'
  local c_dim=$'\033[38;2;108;112;134m'
  local c_red=$'\033[38;2;243;139;168m'
  local c_blue=$'\033[38;2;137;180;250m'
  local c_rst=$'\033[0m'

  case "$id" in
    terminal)
      printf '  %sshell%s            %sshell only, no assistant%s' \
        "$c_text" "$c_rst" "$c_dim" "$c_rst" ;;
    claude)
      printf '  %sclaude%s           %snew session%s' \
        "$c_text" "$c_rst" "$c_dim" "$c_rst" ;;
    claude-resume)
      printf '  %sclaude --resume%s  %sresume last session%s' \
        "$c_text" "$c_rst" "$c_dim" "$c_rst" ;;
    codex)
      printf '  %scodex%s            %sOpenAI Codex CLI%s' \
        "$c_text" "$c_rst" "$c_dim" "$c_rst" ;;
    claude-danger)
      printf '%s! claude UNSAFE%s    %sskips permissions%s' \
        "$c_text" "$c_rst" "$c_dim" "$c_rst" ;;
    custom:*)
      local label="${id#custom:}"
      local cmd
      cmd=$(find_custom_command "$label") || cmd=''
      local display_cmd="$cmd"
      if ((${#display_cmd} > 40)); then
        display_cmd="${display_cmd:0:37}..."
      fi
      local pad=$((17 - ${#label}))
      ((pad < 2)) && pad=2
      printf '  %s%s%s%*s%s%s%s' \
        "$c_blue" "$label" "$c_rst" \
        "$pad" "" \
        "$c_dim" "$display_cmd" "$c_rst" ;;
  esac
}

edit_modes_screen() {
  local c_green=$'\033[38;2;166;227;161m'
  local c_text=$'\033[38;2;205;214;244m'
  local c_dim=$'\033[38;2;108;112;134m'
  local c_sep=$'\033[38;2;88;91;112m'
  local c_rst=$'\033[0m'

  local working=("${MODE_ORDER[@]}")
  local cursor=0
  local n=${#working[@]}

  if ((n == 0)); then
    return 1
  fi

  while true; do
    clear
    printf '\n %sEDIT MODES%s   %sREPO%s %s▸%s %s%s%s\n' \
      "$c_green" "$c_rst" \
      "$c_dim" "$c_rst" \
      "$c_sep" "$c_rst" \
      "$c_text" "$CURRENT_REPO" "$c_rst"
    printf ' %s%s%s\n\n' "$c_sep" "───────────────────────────────────────" "$c_rst"

    local i meta
    for ((i=0; i<n; i++)); do
      meta=$(render_mode_meta "${working[$i]}")
      if ((i == cursor)); then
        printf '  %s▸%s %s\n' "$c_green" "$c_rst" "$meta"
      else
        printf '    %s\n' "$meta"
      fi
    done

    printf '\n %s↑↓%s %smove%s   %s│%s   %senter%s %ssave%s   %s│%s   %sesc%s %scancel%s\n' \
      "$c_green" "$c_rst" "$c_dim" "$c_rst" \
      "$c_sep" "$c_rst" \
      "$c_green" "$c_rst" "$c_dim" "$c_rst" \
      "$c_sep" "$c_rst" \
      "$c_green" "$c_rst" "$c_dim" "$c_rst"

    local key k2 k3 tmp
    IFS= read -rsn1 key
    case "$key" in
      $'\n'|$'\r')
        MODE_ORDER=("${working[@]}")
        save_mode_order
        clear
        STATUS_MESSAGE="Order saved."
        return 0
        ;;
      $'\e')
        IFS= read -rsn1 -t 0.01 k2 || k2=''
        if [[ -z "$k2" ]]; then
          clear
          STATUS_MESSAGE="Reorder cancelled."
          return 1
        fi
        IFS= read -rsn1 -t 0.01 k3 || k3=''
        if [[ "$k2" == '[' ]]; then
          case "$k3" in
            A)  # up arrow: swap with previous
              if ((cursor > 0)); then
                tmp="${working[$cursor]}"
                working[$cursor]="${working[$((cursor-1))]}"
                working[$((cursor-1))]="$tmp"
                ((cursor--))
              fi
              ;;
            B)  # down arrow: swap with next
              if ((cursor < n-1)); then
                tmp="${working[$cursor]}"
                working[$cursor]="${working[$((cursor+1))]}"
                working[$((cursor+1))]="$tmp"
                ((cursor++))
              fi
              ;;
          esac
        fi
        ;;
      k|K)  # vim-style alt: k moves up
        if ((cursor > 0)); then
          tmp="${working[$cursor]}"
          working[$cursor]="${working[$((cursor-1))]}"
          working[$((cursor-1))]="$tmp"
          ((cursor--))
        fi
        ;;
      j|J)  # vim-style alt: j moves down
        if ((cursor < n-1)); then
          tmp="${working[$cursor]}"
          working[$cursor]="${working[$((cursor+1))]}"
          working[$((cursor+1))]="$tmp"
          ((cursor++))
        fi
        ;;
    esac
  done
}

add_custom_mode() {
  local c_green=$'\033[38;2;166;227;161m'
  local c_dim=$'\033[38;2;108;112;134m'
  local c_sep=$'\033[38;2;88;91;112m'
  local c_rst=$'\033[0m'

  clear
  printf '\n %sADD CUSTOM MODE%s\n' "$c_green" "$c_rst"
  printf ' %s%s%s\n\n' "$c_sep" "─────────────────" "$c_rst"

  local label command
  printf ' %slabel%s %s(max 20 chars, no tabs)%s\n ❯ ' \
    "$c_green" "$c_rst" "$c_dim" "$c_rst"
  IFS= read -r label
  label="${label%$'\r'}"

  if [[ -z "$label" ]]; then
    STATUS_MESSAGE="label cannot be empty"
    clear
    return 1
  fi
  if ((${#label} > 20)); then
    STATUS_MESSAGE="label too long (max 20 chars)"
    clear
    return 1
  fi
  if [[ "$label" == *$'\t'* ]]; then
    STATUS_MESSAGE="label cannot contain tabs"
    clear
    return 1
  fi
  if is_builtin_label "$label" || is_builtin_mode_id "$label"; then
    STATUS_MESSAGE="'$label' is reserved (built-in)"
    clear
    return 1
  fi

  load_custom_modes
  if find_custom_command "$label" >/dev/null; then
    STATUS_MESSAGE="'$label' already exists"
    clear
    return 1
  fi

  printf '\n %scommand%s %s(bash, runs in worktree cwd)%s\n ❯ ' \
    "$c_green" "$c_rst" "$c_dim" "$c_rst"
  IFS= read -r command
  command="${command%$'\r'}"

  if [[ -z "$command" ]]; then
    STATUS_MESSAGE="command cannot be empty"
    clear
    return 1
  fi

  CUSTOM_MODE_LABELS+=("$label")
  CUSTOM_MODE_COMMANDS+=("$command")
  save_custom_modes

  # load_mode_order rebuilds MODE_ORDER using CUSTOM_MODE_LABELS (which now
  # contains the new label), appending it via the "defaults not in saved order"
  # fallback — so no explicit append needed. Explicit append would duplicate.
  load_mode_order
  save_mode_order

  clear
  STATUS_MESSAGE="added '$label'"
}

# Inline y/N confirmation: same MODE view, prompt appended to the target
# item's line, cursor starts on that item. Captures y/n via --expect.
confirm_delete_inline() {
  local repo="$1"
  local mode="$2"
  local label="${mode#custom:}"

  # Find target index in MODE_ORDER (0-based; fzf pos() is 1-based)
  local target_idx=-1 i
  for ((i=0; i<${#MODE_ORDER[@]}; i++)); do
    if [[ "${MODE_ORDER[$i]}" == "$mode" ]]; then
      target_idx=$i
      break
    fi
  done
  if ((target_idx < 0)); then
    STATUS_MESSAGE="item not found"
    return 1
  fi

  local c_green=$'\033[38;2;166;227;161m'
  local c_text=$'\033[38;2;205;214;244m'
  local c_dim=$'\033[38;2;108;112;134m'
  local c_sep=$'\033[38;2;88;91;112m'
  local c_red=$'\033[38;2;243;139;168m'
  local c_rst=$'\033[0m'

  # Header + footer identical to select_launch_mode
  local header
  printf -v header ' %sMODE%s   %sREPO%s %s▸%s %s%s%s' \
    "$c_green" "$c_rst" \
    "$c_dim" "$c_rst" \
    "$c_sep" "$c_rst" \
    "$c_text" "$repo" "$c_rst"

  local footer
  printf -v footer ' %senter%s %sselect%s   %s│%s   %sn%s %snew%s   %s│%s   %sd%s %sdelete%s   %s│%s   %se%s %sreorder%s   %s│%s   %sesc%s %sback%s' \
    "$c_green" "$c_rst" "$c_dim" "$c_rst" \
    "$c_sep" "$c_rst" \
    "$c_green" "$c_rst" "$c_dim" "$c_rst" \
    "$c_sep" "$c_rst" \
    "$c_green" "$c_rst" "$c_dim" "$c_rst" \
    "$c_sep" "$c_rst" \
    "$c_green" "$c_rst" "$c_dim" "$c_rst" \
    "$c_sep" "$c_rst" \
    "$c_green" "$c_rst" "$c_dim" "$c_rst"

  # Build items; append [y/N?] only to the target item's label
  local items=() id meta
  for ((i=0; i<${#MODE_ORDER[@]}; i++)); do
    id="${MODE_ORDER[$i]}"
    meta=$(render_mode_meta "$id")
    if ((i == target_idx)); then
      meta+="   ${c_red}[y/N to delete?]${c_rst}"
    fi
    items+=("$id"$'\t'"$meta")
  done

  local output
  output="$(
    printf '%s\n' "${items[@]}" | fzf_safe \
      "${FZF_THEME[@]}" \
      --delimiter=$'\t' \
      --with-nth=2 \
      --prompt=' ❯ ' \
      --header="$header" \
      --footer="$footer" \
      --preview="bash '$LAUNCHER_PATH' --preview $repo" \
      --preview-window='right:45%:border-rounded' \
      --no-input \
      --bind="start:pos($((target_idx+1)))" \
      --expect=y,Y,n,N,esc
  )"

  parse_fzf_output "$output"
  case "${FZF_KEY:-n}" in
    y|Y) return 0 ;;
    *)
      STATUS_MESSAGE="cancelled"
      return 1
      ;;
  esac
}

# Delete a custom mode by ID (format: custom:<label>). Pure operation —
# caller must have confirmed. Updates both state files.
delete_custom_mode() {
  local mode="$1"
  local label="${mode#custom:}"

  load_custom_modes
  local new_labels=() new_commands=() i
  for ((i=0; i<${#CUSTOM_MODE_LABELS[@]}; i++)); do
    if [[ "${CUSTOM_MODE_LABELS[$i]}" != "$label" ]]; then
      new_labels+=("${CUSTOM_MODE_LABELS[$i]}")
      new_commands+=("${CUSTOM_MODE_COMMANDS[$i]}")
    fi
  done
  CUSTOM_MODE_LABELS=("${new_labels[@]}")
  CUSTOM_MODE_COMMANDS=("${new_commands[@]}")
  save_custom_modes

  load_mode_order
  local new_order=() id
  for id in "${MODE_ORDER[@]}"; do
    [[ "$id" == "$mode" ]] && continue
    new_order+=("$id")
  done
  MODE_ORDER=("${new_order[@]}")
  save_mode_order

  STATUS_MESSAGE="deleted '$label'"
}

confirm_unsafe() {
  local repo="$1"
  local c_red=$'\033[38;2;243;139;168m'
  local c_dim=$'\033[38;2;108;112;134m'
  local c_text=$'\033[38;2;205;214;244m'
  local c_sep=$'\033[38;2;88;91;112m'
  local c_rst=$'\033[0m'

  local header
  printf -v header ' %s! DANGER%s   %sclaude --dangerously-skip-permissions%s\n %s%s%s\n %s%sAll tool use is pre-approved for %s%s%s%s.%s' \
    "$c_red" "$c_rst" \
    "$c_text" "$c_rst" \
    "$c_dim" "────────────────────────────────────────" "$c_rst" \
    "$c_dim" "" "$c_rst" "$c_red" "$repo" "$c_rst" "$c_dim"

  local footer
  printf -v footer ' %sy%s confirm   %s│%s   %sn / esc%s cancel' \
    "$c_red" "$c_rst" "$c_sep" "$c_rst" "$c_red" "$c_rst"

  local output
  output="$(
    printf '%s\n' $'no\tcancel' $'yes\tproceed' | fzf_safe \
      "${FZF_THEME[@]}" \
      --delimiter=$'\t' \
      --with-nth=2 \
      --prompt=' ❯ ' \
      --header="$header" \
      --footer="$footer" \
      --no-input \
      --expect=y,n,esc
  )"
  local status=$?

  parse_fzf_output "$output"
  if [[ "$status" -ne 0 ]]; then
    return 1
  fi
  case "${FZF_KEY:-enter}" in
    y)
      return 0
      ;;
    n|esc)
      return 1
      ;;
  esac

  local choice label
  IFS=$'\t' read -r choice label <<< "$FZF_LINE"
  [[ "$choice" == 'yes' ]] && return 0
  return 1
}

select_launch_mode() {
  local repo="$1"
  SELECTED_MODE=""
  CURRENT_REPO="$repo"

  local c_green=$'\033[38;2;166;227;161m'
  local c_text=$'\033[38;2;205;214;244m'
  local c_dim=$'\033[38;2;108;112;134m'
  local c_sep=$'\033[38;2;88;91;112m'
  local c_red=$'\033[38;2;243;139;168m'
  local c_rst=$'\033[0m'

  while true; do
    load_custom_modes
    load_mode_order

    local header
    printf -v header ' %sMODE%s   %sREPO%s %s▸%s %s%s%s' \
      "$c_green" "$c_rst" \
      "$c_dim" "$c_rst" \
      "$c_sep" "$c_rst" \
      "$c_text" "$repo" "$c_rst"

    if [[ -n "$STATUS_MESSAGE" ]]; then
      header+=$'\n '"${c_red}→${c_rst} ${c_dim}${STATUS_MESSAGE}${c_rst}"
    fi
    STATUS_MESSAGE=""

    local footer
    printf -v footer ' %senter%s %sselect%s   %s│%s   %sn%s %snew%s   %s│%s   %sd%s %sdelete%s   %s│%s   %se%s %sreorder%s   %s│%s   %sesc%s %sback%s' \
      "$c_green" "$c_rst" "$c_dim" "$c_rst" \
      "$c_sep" "$c_rst" \
      "$c_green" "$c_rst" "$c_dim" "$c_rst" \
      "$c_sep" "$c_rst" \
      "$c_green" "$c_rst" "$c_dim" "$c_rst" \
      "$c_sep" "$c_rst" \
      "$c_green" "$c_rst" "$c_dim" "$c_rst" \
      "$c_sep" "$c_rst" \
      "$c_green" "$c_rst" "$c_dim" "$c_rst"

    local items=() id meta
    for id in "${MODE_ORDER[@]}"; do
      meta=$(render_mode_meta "$id")
      items+=("$id"$'\t'"$meta")
    done

    local output
    output="$(
      printf '%s\n' "${items[@]}" | fzf_safe \
        "${FZF_THEME[@]}" \
        --delimiter=$'\t' \
        --with-nth=2 \
        --prompt=' ❯ ' \
        --header="$header" \
        --footer="$footer" \
        --preview="bash '$LAUNCHER_PATH' --preview $repo" \
        --preview-window='right:45%:border-rounded' \
        --no-input \
        --expect=esc,n,d,e
    )"
    local status=$?

    parse_fzf_output "$output"
    if [[ "$status" -ne 0 && "$status" -ne 130 ]]; then
      return "$status"
    fi

    local mode label
    IFS=$'\t' read -r mode label <<< "$FZF_LINE"

    case "${FZF_KEY:-enter}" in
      esc)
        return 1
        ;;
      n)
        add_custom_mode
        continue
        ;;
      d)
        if [[ -z "$mode" ]]; then
          continue
        fi
        if is_builtin_mode_id "$mode"; then
          local disp
          disp=$(builtin_label_for_id "$mode")
          STATUS_MESSAGE="'$disp' is built-in and can't be removed"
        elif confirm_delete_inline "$repo" "$mode"; then
          delete_custom_mode "$mode"
        fi
        continue
        ;;
      e)
        edit_modes_screen
        continue
        ;;
    esac

    if [[ "$mode" == 'claude-danger' ]]; then
      if ! confirm_unsafe "$repo"; then
        STATUS_MESSAGE="UNSAFE mode cancelled."
        return 1
      fi
    fi

    SELECTED_MODE="$mode"
    return 0
  done
}

prepare_launch_mode() {
  local mode="$1"
  MODE_LABEL=""
  LAUNCH_ARGS=()

  case "$mode" in
    terminal)
      MODE_LABEL='shell'
      ;;
    claude|claude-resume|claude-danger)
      if ! command -v claude >/dev/null 2>&1; then
        STATUS_MESSAGE="claude CLI not found on PATH."
        return 1
      fi
      case "$mode" in
        claude)        MODE_LABEL='claude'; LAUNCH_ARGS=(claude) ;;
        claude-resume) MODE_LABEL='claude --resume'; LAUNCH_ARGS=(claude --resume) ;;
        claude-danger) MODE_LABEL='claude UNSAFE'; LAUNCH_ARGS=(claude --dangerously-skip-permissions) ;;
      esac
      ;;
    codex)
      if ! command -v codex >/dev/null 2>&1; then
        STATUS_MESSAGE="codex CLI not found on PATH."
        return 1
      fi
      MODE_LABEL='codex'
      LAUNCH_ARGS=(codex)
      ;;
    custom:*)
      local label="${mode#custom:}"
      load_custom_modes
      local cmd
      if ! cmd=$(find_custom_command "$label"); then
        STATUS_MESSAGE="Custom mode '$label' not found."
        return 1
      fi
      MODE_LABEL="$label"
      LAUNCH_ARGS=(bash -c "$cmd")
      ;;
    *)
      printf 'repos: unknown mode: %s\n' "$mode" >&2
      return 1
      ;;
  esac
}

select_target() {
  local repo="$1"
  local mode_label="$2"
  local repo_path="${3:-$GITHUB_DIR/$repo}"
  SELECTED_TARGET=""

  local c_green=$'\033[38;2;166;227;161m'
  local c_text=$'\033[38;2;205;214;244m'
  local c_dim=$'\033[38;2;108;112;134m'
  local c_sep=$'\033[38;2;88;91;112m'
  local c_rst=$'\033[0m'
  local c_border=$'\033[38;2;88;91;112m'

  local branch=''
  if [[ -e "$repo_path/.git" ]]; then
    branch="$(cd "$repo_path" && git branch --show-current 2>/dev/null)"
    [[ -z "$branch" ]] && branch='(detached)'
  fi

  # Clear and draw the target selection screen
  clear
  printf '\n'
  printf ' %sTARGET%s   %sREPO%s %s▸%s %s%s%s %s▸%s %s%s%s\n' \
    "$c_green" "$c_rst" \
    "$c_dim" "$c_rst" \
    "$c_sep" "$c_rst" \
    "$c_text" "$repo" "$c_rst" \
    "$c_sep" "$c_rst" \
    "$c_text" "$mode_label" "$c_rst"
  printf ' %s%s%s\n' "$c_border" "────────────────────────────────────────────────────────────" "$c_rst"
  printf '\n\n'

  printf '                      %s▲%s %stop%s\n\n\n' \
    "$c_green" "$c_rst" "$c_dim" "$c_rst"
  printf '    %s◀%s %sleft%s            %s●%s %shere%s            %sright%s %s▶%s\n\n\n' \
    "$c_green" "$c_rst" "$c_dim" "$c_rst" \
    "$c_green" "$c_rst" "$c_text" "$c_rst" \
    "$c_dim" "$c_rst" "$c_green" "$c_rst"
  printf '                      %s▼%s %sbottom%s\n' \
    "$c_green" "$c_rst" "$c_dim" "$c_rst"

  if [[ -n "$branch" ]]; then
    printf '\n\n'
    printf ' %sbranch%s   %s%s%s\n' "$c_dim" "$c_rst" "$c_green" "$branch" "$c_rst"
  fi

  printf '\n\n'
  printf ' %s%s%s\n' "$c_border" "────────────────────────────────────────────────────────────" "$c_rst"
  printf ' %s← ↑ ↓ →%s %ssplit%s   %s│%s   %senter%s %shere%s   %s│%s   %sesc%s %sback%s\n' \
    "$c_green" "$c_rst" "$c_dim" "$c_rst" \
    "$c_sep" "$c_rst" \
    "$c_green" "$c_rst" "$c_dim" "$c_rst" \
    "$c_sep" "$c_rst" \
    "$c_green" "$c_rst" "$c_dim" "$c_rst"

  # Read a single key (handle arrow escape sequences)
  local key
  IFS= read -rsn1 key
  if [[ "$key" == $'\e' ]]; then
    local rest=''
    IFS= read -rsn2 -t 0.05 rest
    key+="$rest"
  fi

  clear

  local status=0
  case "$key" in
    $'\e[A') FZF_KEY='up' ;;
    $'\e[B') FZF_KEY='down' ;;
    $'\e[D') FZF_KEY='left' ;;
    $'\e[C') FZF_KEY='right' ;;
    '')      FZF_KEY='enter' ;;
    $'\e')   FZF_KEY='esc' ;;
    *)       FZF_KEY='enter' ;;
  esac

  case "$FZF_KEY" in
    up)    SELECTED_TARGET='up' ;;
    down)  SELECTED_TARGET='down' ;;
    left)  SELECTED_TARGET='left' ;;
    right) SELECTED_TARGET='right' ;;
    esc)   return 1 ;;
    *)     SELECTED_TARGET='current' ;;
  esac

  return 0
}

build_launch_text() {
  if ((${#LAUNCH_ARGS[@]} == 0)); then
    printf ''
    return
  fi

  local text=''
  printf -v text '%q ' "${LAUNCH_ARGS[@]}"
  printf '%s\n' "${text% }"
}

open_split_pane() {
  local repo_path="$1"
  local target="$2"
  local cmd=(wezterm cli split-pane --pane-id "$WEZTERM_PANE" --cwd "$repo_path")

  case "$target" in
    right) cmd+=(--right) ;;
    left) cmd+=(--left) ;;
    up) cmd+=(--top) ;;
    down) cmd+=(--bottom) ;;
    *)
      printf 'repos: unknown split target: %s\n' "$target" >&2
      return 1
      ;;
  esac

  "${cmd[@]}"
}

launch_in_current_pane() {
  local repo_path="$1"

  if ! cd "$repo_path"; then
    printf 'repos: failed to cd into %s\n' "$repo_path" >&2
    return 1
  fi

  clear
  if ((${#LAUNCH_ARGS[@]} == 0)); then
    return 0
  fi

  "${LAUNCH_ARGS[@]}"
}

launch_in_split() {
  local repo="$1"
  local repo_path="$2"
  local target="$3"

  local pane_id
  if ! pane_id="$(open_split_pane "$repo_path" "$target")"; then
    STATUS_MESSAGE="Failed to open $repo."
    return 1
  fi
  pane_id="${pane_id//$'\r'/}"
  pane_id="${pane_id//$'\n'/}"

  local launch_text
  launch_text="$(build_launch_text)"
  if [[ -n "$launch_text" ]]; then
    if ! wezterm cli send-text --pane-id "$pane_id" --no-paste "${launch_text}"$'\n' >/dev/null; then
      STATUS_MESSAGE="Opened $repo, but failed to start $MODE_LABEL."
      return 1
    fi
  fi

  wezterm cli activate-pane --pane-id "$WEZTERM_PANE" >/dev/null 2>&1 || true
  STATUS_MESSAGE="Opened $repo."
}

repo_launcher_main() {
  ensure_path
  require_dependencies || return $?

  clear
  load_repos
  load_pins

  while true; do
    if ! select_repo; then
      local status=$?
      clear
      return "$status"
    fi

    local repo="$SELECTED_REPO"
    if [[ "$repo" == '__EXIT__' ]]; then
      clear
      return 0
    fi

    if ! select_branch "$repo"; then
      local status=$?
      if [[ "$status" -eq 130 ]]; then
        clear
        return "$status"
      fi
      continue
    fi

    local work_path="$SELECTED_WORKTREE_PATH"
    [[ -z "$work_path" ]] && work_path="$GITHUB_DIR/$repo"

    if ! select_launch_mode "$repo"; then
      local status=$?
      if [[ "$status" -eq 130 ]]; then
        clear
        return "$status"
      fi
      continue
    fi

    local mode="$SELECTED_MODE"
    if ! prepare_launch_mode "$mode"; then
      clear
      return 1
    fi

    if ! select_target "$repo" "$MODE_LABEL" "$work_path"; then
      local status=$?
      if [[ "$status" -eq 130 ]]; then
        clear
        return "$status"
      fi
      continue
    fi

    local target="$SELECTED_TARGET"
    if [[ "$target" == 'current' ]]; then
      launch_in_current_pane "$work_path"
      return $?
    fi

    launch_in_split "$repo" "$work_path" "$target" >/dev/null
    load_repos
    load_pins
  done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  if [[ "${1:-}" == "--preview" ]]; then
    repo_preview "$2"
    exit 0
  fi
  repo_launcher_main "$@"
fi
