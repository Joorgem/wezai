#!/usr/bin/env bash
#
# terminal-setup installer
# Copies WezTerm + Claude statusline configs into the user's system.
# Backs up any existing files first (*.bak-YYYYMMDD-HHMMSS).
#
# Usage:
#   ./install.sh               # install everything
#   ./install.sh wezterm       # only wezterm
#   ./install.sh claude        # only claude statusline
#

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"

# Colors
GREEN=$'\033[38;2;166;227;161m'
YELLOW=$'\033[38;2;249;226;175m'
RED=$'\033[38;2;243;139;168m'
DIM=$'\033[38;2;108;112;134m'
RST=$'\033[0m'

log()   { printf ' %s▸%s %s\n' "$GREEN" "$RST" "$1"; }
warn()  { printf ' %s!%s %s\n' "$YELLOW" "$RST" "$1"; }
err()   { printf ' %s✗%s %s\n' "$RED" "$RST" "$1" >&2; }
info()  { printf '   %s%s%s\n' "$DIM" "$1" "$RST"; }

need() {
  command -v "$1" >/dev/null 2>&1 || {
    err "missing dependency: $1"
    return 1
  }
}

backup_if_exists() {
  local path="$1"
  if [[ -e "$path" && ! -L "$path" ]]; then
    local bak="${path}.bak-${STAMP}"
    cp -r "$path" "$bak"
    info "backup → $(basename "$bak")"
  fi
}

copy_file() {
  local src="$1"
  local dst="$2"
  mkdir -p "$(dirname "$dst")"
  backup_if_exists "$dst"
  cp "$src" "$dst"
  chmod +x "$dst" 2>/dev/null || true
  log "installed $dst"
}

install_wezterm() {
  log "installing WezTerm config"
  local target="$HOME/.config/wezterm"
  copy_file "$REPO_DIR/wezterm/wezterm.lua"        "$target/wezterm.lua"
  copy_file "$REPO_DIR/wezterm/bashrc.wezterm"     "$target/bashrc.wezterm"
  copy_file "$REPO_DIR/wezterm/repo-launcher.sh"   "$target/repo-launcher.sh"
  copy_file "$REPO_DIR/wezterm/repos"              "$target/repos"
  info "done"
}

install_claude() {
  log "installing Claude statusline"
  local target="$HOME/.claude"
  copy_file "$REPO_DIR/claude/statusline.sh" "$target/statusline.sh"
  info "done"
  warn "add the snippet from claude/settings.snippet.json to $target/settings.json"
  info "(merge the statusLine block if not already present)"
}

check_deps() {
  log "checking dependencies"
  local missing=()
  command -v fzf      >/dev/null 2>&1 || missing+=("fzf")
  command -v wezterm  >/dev/null 2>&1 || missing+=("wezterm")
  command -v git      >/dev/null 2>&1 || missing+=("git")
  command -v jq       >/dev/null 2>&1 || missing+=("jq (for statusline)")

  if ((${#missing[@]} > 0)); then
    warn "missing: ${missing[*]}"
    info "install via winget (Windows):"
    info "  winget install junegunn.fzf wez.wezterm jqlang.jq"
  else
    info "all required tools found"
  fi
}

main() {
  local what="${1:-all}"
  log "terminal-setup installer"
  info "repo: $REPO_DIR"
  info "home: $HOME"
  echo

  case "$what" in
    wezterm)   install_wezterm ;;
    claude)    install_claude ;;
    all|'')    install_wezterm; echo; install_claude ;;
    deps)      check_deps; exit 0 ;;
    *)
      err "unknown target: $what"
      echo
      info "usage: $0 [wezterm|claude|all|deps]"
      exit 1
      ;;
  esac

  echo
  check_deps
  echo
  log "installation complete"
  info "open a new WezTerm window and type 'repos' to test"
}

main "$@"
