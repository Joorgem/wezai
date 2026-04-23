#!/bin/bash
# Custom Claude Code Status Line — Jorge David
# Powerline style with Nerd Font arrows, 2-line layout

export LC_NUMERIC=C

input=$(cat)

# Parse fields
MODEL=$(echo "$input" | jq -r '.model.display_name // "—"' | sed 's/ (1M context)//; s/ (1M)//; s/ (200K)//')
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0')
REMAINING=$(echo "$input" | jq -r '.context_window.remaining_percentage // 100')
TOKENS=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
DIR=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // "?"')
FOLDER=$(basename "$DIR")
WORKTREE=$(echo "$input" | jq -r '.workspace.git_worktree // .worktree.name // empty')

# Cost
COST_FMT=$(printf '$%.2f' "$COST" 2>/dev/null || echo '$0.00')

# Rate limit 5h
RATE_5H=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null)
RATE_RESETS=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty' 2>/dev/null)
if [ -n "$RATE_5H" ]; then
  RATE_INT=${RATE_5H%.*}
  RATE_INT=${RATE_INT:-0}
  RATE_LEFT=$((100 - RATE_INT))
else
  RATE_LEFT=""
fi

# Countdown to reset
RATE_COUNTDOWN=""
if [ -n "$RATE_RESETS" ]; then
  NOW=$(date +%s)
  SECS_LEFT=$((RATE_RESETS - NOW))
  if [ "$SECS_LEFT" -gt 0 ] 2>/dev/null; then
    RL_H=$((SECS_LEFT / 3600))
    RL_M=$(((SECS_LEFT % 3600) / 60))
    RATE_COUNTDOWN="${RL_H}h${RL_M}m"
  else
    RATE_COUNTDOWN="resetting"
  fi
fi

# Nerd Font icons (using $'...' to ensure proper encoding)
ARROW=$'\uE0B0'
BRANCH_ICON=$'\uE0A0'
MODEL_ICON='✱'

# ANSI helpers
R=$'\033[0m'

# Segment colors (tracewell.ai style)
FD=$'\033[38;5;0m'
FL=$'\033[38;5;255m'

BG1=$'\033[48;5;114m';  FA1=$'\033[38;5;114m'   # green — project
BG2=$'\033[48;5;80m';   FA2=$'\033[38;5;80m'     # teal — branch
BG3=$'\033[48;5;68m';   FA3=$'\033[38;5;68m'     # blue — model
BG4=$'\033[48;5;133m';  FA4=$'\033[38;5;133m'    # mauve — cost
BG5=$'\033[48;5;236m';  FA5=$'\033[38;5;236m'    # dark gray — context
BG6=$'\033[48;5;58m';   FA6=$'\033[38;5;58m'     # olive — rate limit

# Context color
PCT_INT=${PCT%.*}
PCT_INT=${PCT_INT:-0}
if [ "$PCT_INT" -ge 80 ] 2>/dev/null; then
  CTX=$'\033[31m'
elif [ "$PCT_INT" -ge 50 ] 2>/dev/null; then
  CTX=$'\033[33m'
else
  CTX=$'\033[32m'
fi

# Git info
WORK_DIR=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // "."')
HAS_GIT=false
if [ -d "$WORK_DIR/.git" ] || git -C "$WORK_DIR" rev-parse --git-dir &>/dev/null; then
  HAS_GIT=true
  BRANCH=$(git -C "$WORK_DIR" branch --show-current 2>/dev/null || echo "detached")

  # Fallback: detect worktree via .git being a file (linked worktree) vs dir (main)
  if [ -z "$WORKTREE" ] && [ -f "$WORK_DIR/.git" ]; then
    WORKTREE=$(basename "$WORK_DIR")
  fi
  if [ -n "$WORKTREE" ]; then
    WT_ICON='🌿 '
  else
    WT_ICON=''
  fi
  DIRTY=$(git -C "$WORK_DIR" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  AHEAD=$(git -C "$WORK_DIR" rev-list --count @{u}..HEAD 2>/dev/null || echo "0")

  SYNC=""
  if [ "$AHEAD" -gt 0 ] 2>/dev/null; then
    SYNC=" ↑${AHEAD}"
  fi

  if [ "$DIRTY" -gt 0 ] 2>/dev/null; then
    DOT=$'\033[33m●\033[38;5;0m'
  else
    DOT=$'\033[32m●\033[38;5;0m'
  fi
fi

# --- SINGLE LINE: Project + Branch + Model + Tokens + Cost + Context ---
L="${BG1}${FD} ${FOLDER} "
if [ "$HAS_GIT" = true ]; then
  L="${L}${BG2}${FA1}${ARROW}${FD} ${WT_ICON}${BRANCH_ICON} ${BRANCH}${SYNC} ${DOT} "
  L="${L}${BG3}${FA2}${ARROW}"
else
  L="${L}${BG3}${FA1}${ARROW}"
fi
# Model
L="${L}${FL} ${MODEL_ICON} ${MODEL} "
# Cost
L="${L}${BG4}${FA3}${ARROW}${FL} ${COST_FMT} "
# End line 1
L="${L}${R}${FA4}${ARROW}${R}"

# --- LINE 2: Context + Rate limit ---
L2="${BG5}${FL} ${CTX}○${FL} ${PCT}% (${REMAINING}%) "
if [ -n "$RATE_LEFT" ]; then
  if [ "$RATE_INT" -ge 80 ] 2>/dev/null; then
    RLCOL=$'\033[31m'
  elif [ "$RATE_INT" -ge 50 ] 2>/dev/null; then
    RLCOL=$'\033[33m'
  else
    RLCOL=$'\033[32m'
  fi
  RATE_TEXT="${RATE_LEFT}%"
  if [ -n "$RATE_COUNTDOWN" ]; then
    RATE_TEXT="${RATE_LEFT}% ⏱ ${RATE_COUNTDOWN}"
  fi
  L2="${L2}${BG6}${FA5}${ARROW}${FL} ${RLCOL}${RATE_TEXT}${FL} "
  L2="${L2}${R}${FA6}${ARROW}${R}"
else
  L2="${L2}${R}${FA5}${ARROW}${R}"
fi

printf '%s\n%s\n' "$L" "$L2"
