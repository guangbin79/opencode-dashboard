#!/bin/bash
# tmux helper functions for opencode-dashboard

DASH_SESSION_NAME="opencode-dashboard"
DASH_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Saved state for restore
_TMUX_SAVED_STATUS=""

tmux_init_session() {
  local name="${1:-$DASH_SESSION_NAME}"
  if tmux has-session -t "$name" 2>/dev/null; then
    tmux attach-session -t "$name"
    return $?
  fi
  tmux new-session -d -s "$name" -n "opencode-dashboard" \
    -x "$(tput cols 2>/dev/null || echo 80)" \
    -y "$(tput lines 2>/dev/null || echo 24)"

  tmux set-option -t "$name" window-style "bg=#2E3440"
  tmux set-option -t "$name" pane-border-style "fg=#4C566A"
  tmux set-option -t "$name" pane-active-border-style "fg=#88C0D0"
  tmux set-option -t "$name" message-style "bg=#3B4252,fg=#ECEFF4"
  tmux set-option -t "$name" mode-style "bg=#434C5E,fg=#ECEFF4"
  _TMUX_SAVED_STATUS="$(tmux show-option -t "$name" status 2>/dev/null | cut -d' ' -f2)"
  tmux set-option -t "$name" status off

  tmux attach-session -t "$name"
}

tmux_is_running() {
  [ -n "$TMUX" ]
}

tmux_get_width() {
  if [ -n "$COLUMNS" ] && [ "$COLUMNS" -gt 0 ] 2>/dev/null; then
    echo "$COLUMNS"
  elif tmux_is_running; then
    tmux display-message -p '#{pane_width}'
  else
    tput cols 2>/dev/null || echo 80
  fi
}

tmux_get_height() {
  if [ -n "$LINES" ] && [ "$LINES" -gt 0 ] 2>/dev/null; then
    echo "$LINES"
  elif tmux_is_running; then
    tmux display-message -p '#{pane_height}'
  else
    tput lines 2>/dev/null || echo 24
  fi
}

tmux_popup() {
  local cmd="$1"
  local w="${2:-80%}"
  local h="${3:-80%}"
  if ! tmux_is_running; then
    eval "$cmd"
    return $?
  fi
  if tmux -V | awk '{exit !($2 >= 3.2)}'; then
    tmux display-popup -w "$w" -h "$h" -B -b "rounded" \
      -s "bg=#2E3440,fg=#ECEFF4" -S "fg=#88C0D0" \
      -E "$cmd"
  else
    tmux split-window -h -p 50 "$cmd"
  fi
}

tmux_set_title() {
  local title="$1"
  if tmux_is_running; then
    printf '\033]0;%s\007' "$title"
    tmux set-option -w automatic-rename off 2>/dev/null
    tmux rename-window "$title" 2>/dev/null
  fi
}

tmux_clear() {
  printf '\033[48;5;236m\033[2J\033[H\033[m'
  clear
}

tmux_restore() {
  if [ -n "$_TMUX_SAVED_STATUS" ] && tmux_is_running; then
    local session="${TMUX_PANE:+$(tmux display-message -p '#{session_name}' 2>/dev/null)}"
    [ -n "$session" ] && tmux set-option -t "$session" status "$_TMUX_SAVED_STATUS" 2>/dev/null
  fi
  _TMUX_SAVED_STATUS=""
}
