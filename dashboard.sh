#!/bin/bash
set -euo pipefail

# --- Determine script directory ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Source libraries ---
source "$SCRIPT_DIR/lib/render.sh"
source "$SCRIPT_DIR/lib/tmux.sh"
source "$SCRIPT_DIR/lib/views/sessions.sh"
source "$SCRIPT_DIR/lib/views/detail.sh"
source "$SCRIPT_DIR/lib/views/agents.sh"
source "$SCRIPT_DIR/lib/views/todos.sh"

# --- Common fzf base options (views append their own) ---
FZF_BASE_OPTS=(
  --ansi
  --color="$FZF_NORD_COLORS"
  --bind='j:down'
  --bind='k:up'
  --no-multi
  --reverse
  --height=100%
  --border=none
)
export FZF_BASE_OPTS

# --- Usage ---
usage() {
  cat <<'EOF'
opencode-dashboard - Terminal UI for OpenCode session management

Usage:
  dashboard.sh [options]

Options:
  --help    Show this help message

Keys (inside views):
  1-4       Switch between views
  q         Quit
  Enter     Select / open detail

Views:
  [1] Sessions   Browse and search sessions
  [2] Detail     View session messages and metadata
  [3] Agents     Agent usage overview
  [4] Todos      Session todo lists
EOF
}

# --- Main loop ---
dash_main() {
  tmux_clear
  tmux_set_title "opencode-dashboard"

  local CURRENT_VIEW="sessions"
  local CURRENT_SESSION_ID=""
  local CURRENT_SESSION_TITLE=""
  local CURRENT_SESSION_PROJECT=""
  local result=""

  while true; do
    case "$CURRENT_VIEW" in
      sessions)
        result=$(view_sessions "" "$CURRENT_SESSION_PROJECT")
        ;;
      sessions_project)
        result=$(view_sessions "$CURRENT_SESSION_PROJECT" "$CURRENT_SESSION_ID")
        ;;
      detail)
        result=$(view_detail "$CURRENT_SESSION_ID" "$CURRENT_SESSION_TITLE")
        ;;
      agents)
        result=$(view_agents)
        ;;
      todos)
        result=$(view_todos)
        ;;
      *)
        result="view:sessions"
        ;;
    esac

    case "$result" in
      quit)
        break
        ;;
      noop)
        ;;
      view:sessions)
        CURRENT_VIEW="sessions"
        ;;
      view:sessions:*)
        CURRENT_SESSION_PROJECT="${result#view:sessions:}"
        CURRENT_VIEW="sessions_project"
        ;;
      view:detail)
        if [[ -n "$CURRENT_SESSION_ID" ]]; then
          CURRENT_VIEW="detail"
        else
          CURRENT_VIEW="sessions"
        fi
        ;;
      view:detail:*)
        CURRENT_SESSION_ID="${result#view:detail:}"
        CURRENT_VIEW="detail"
        ;;
      view:agents)
        CURRENT_VIEW="agents"
        ;;
      view:todos)
        CURRENT_VIEW="todos"
        ;;
      back)
        if [[ "$CURRENT_VIEW" == "detail" && -n "$CURRENT_SESSION_PROJECT" ]]; then
          CURRENT_VIEW="sessions_project"
        else
          CURRENT_VIEW="sessions"
          CURRENT_SESSION_PROJECT=""
        fi
        ;;
    esac
  done
}

# --- Cleanup ---
cleanup() {
  tmux_restore
}
trap cleanup EXIT

# --- Signal handling ---
trap 'exit 0' INT

# --- Entry point ---
if [[ "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if ! tmux_is_running; then
  printf '%sStarting opencode-dashboard in tmux...%s\n' '\033[38;2;136;192;208m' '\033[0m'
  tmux_init_session "$DASH_SESSION_NAME"
  # After attach, this script re-executes inside tmux
  # If tmux_init_session fails or user detaches, exit cleanly
  exit 0
fi

dash_main
