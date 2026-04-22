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
[[ -f "$SCRIPT_DIR/lib/views/agent.sh" ]] && source "$SCRIPT_DIR/lib/views/agent.sh"

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
  1-5       Switch between views
  q         Quit
  Enter     Select / drill down
  b/h/Backspace  Go back one level

Navigation (3-level hierarchy):
  L1 [1] Projects   Browse projects (default view)
  L2 [2] Sessions   Project-scoped session list
  L3     Agent      Interactive agent view (tmux split)

Additional views:
  [3] Detail     View session messages and metadata
  [4] Agents     Agent usage overview
  [5] Todos      Session todo lists
EOF
}

# --- Main loop ---
dash_main() {
  tmux_clear
  tmux_set_title "opencode-dashboard"

  local CURRENT_VIEW="projects"
  local CURRENT_PROJECT=""
  local CURRENT_SESSION_ID=""
  local CURRENT_SESSION_TITLE=""
  local result=""

  while true; do
    case "$CURRENT_VIEW" in
      projects)
        result=$(view_sessions "" "$CURRENT_PROJECT")
        ;;
      sessions)
        result=$(view_sessions "$CURRENT_PROJECT" "$CURRENT_SESSION_ID")
        ;;
      agent)
        if declare -f view_agent >/dev/null 2>&1; then
          result=$(view_agent "$CURRENT_SESSION_ID" "$CURRENT_SESSION_TITLE")
        else
          result="back"
        fi
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
        result="view:projects"
        ;;
    esac

    case "$result" in
      quit)
        break
        ;;
      noop)
        ;;
      view:projects)
        CURRENT_VIEW="projects"
        ;;
      view:sessions)
        CURRENT_VIEW="sessions"
        ;;
      view:sessions:*)
        CURRENT_PROJECT="${result#view:sessions:}"
        CURRENT_VIEW="sessions"
        ;;
      view:agent:*)
        CURRENT_SESSION_ID="${result#view:agent:}"
        CURRENT_VIEW="agent"
        ;;
      view:detail)
        if [[ -n "$CURRENT_SESSION_ID" ]]; then
          CURRENT_VIEW="detail"
        else
          CURRENT_VIEW="projects"
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
        case "$CURRENT_VIEW" in
          agent)
            CURRENT_VIEW="sessions"
            ;;
          detail)
            if [[ -n "$CURRENT_PROJECT" ]]; then
              CURRENT_VIEW="sessions"
            else
              CURRENT_VIEW="projects"
            fi
            ;;
          sessions)
            CURRENT_VIEW="projects"
            CURRENT_PROJECT=""
            ;;
          agents|todos)
            if [[ -n "$CURRENT_PROJECT" ]]; then
              CURRENT_VIEW="sessions"
            else
              CURRENT_VIEW="projects"
            fi
            ;;
          *)
            CURRENT_VIEW="projects"
            ;;
        esac
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
