#!/bin/bash
# Session Agents view for OpenCode dashboard
# Provides view_session_agents() - fzf-based agent selector within a session

# view_session_agents
# Shows fzf agent list for a given session. Returns:
#   "view:agent:<session_id>:<agent_name>" - user selected an agent
#   "view:sessions" - user pressed b/h/Backspace/1 to go back
#   "view:agents" - user pressed 3 to switch to global agents view
#   "view:todos" - user pressed 4 to switch to todos view
#   "quit" - user pressed q
#   "back" - no agent data available
view_session_agents() {
  local SCRIPT_DIR
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  local data_py="$SCRIPT_DIR/lib/data.py"

  # shellcheck source=/dev/null
  [[ -f "$SCRIPT_DIR/lib/render.sh" ]] && source "$SCRIPT_DIR/lib/render.sh"

  local session_id="$1"
  local session_title="${2:-}"

  # Get agent data
  local agent_data
  agent_data=$(python3 "$data_py" session-agents "$session_id" 2>/dev/null)
  if [[ -z "$agent_data" ]]; then
    echo "back"
    return 0
  fi

  # fzf colors
  local fzf_colors
  if [[ -n "${FZF_NORD_COLORS:-}" ]]; then
    fzf_colors="$FZF_NORD_COLORS"
  else
    fzf_colors='fg:#D8DEE9,bg:#2E3440,hl:#88C0D0,fg+:#ECEFF4,bg+:#3B4252,hl+:#88C0D0,border:#434C5E,header:#5E81AC,gutter:#434C5E,spinner:#88C0D0,info:#81A1C1,pointer:#88C0D0,marker:#A3BE8C,prompt:#5E81AC,selected-bg:#434C5E'
  fi

  # Header
  local header
  header="$(n_header_bar "Session Agents")"$'\n'
  if [[ -n "$session_title" ]]; then
    header+="${N_DIM}${session_title}${N_RESET}"$'\n'
  fi
  header+="${N_BOLD}${N_FROST}── Select an agent ──${N_RESET}"

  # Format data with status icons and colors
  local colored_data=""
  while IFS=$'\t' read -r agent_name msg_count tok_in tok_out status; do
    [[ -z "$agent_name" ]] && continue

    local status_icon status_color
    case "$status" in
      running) status_icon="${N_GREEN}●${N_RESET}"; status_color="$N_GREEN" ;;
      waiting) status_icon="${N_YELLOW}●${N_RESET}"; status_color="$N_YELLOW" ;;
      *)       status_icon="${N_DIM}○${N_RESET}"; status_color="$N_DIM" ;;
    esac

    local display
    display=" ${status_icon}  ${N_CYAN}${agent_name}${N_RESET}  ${status_color}${status}${N_RESET}"

    # TSV: raw fields 1-5, display field 6
    colored_data+="$(printf '%s\t%s\t%s\t%s\t%s\t%s' \
      "$agent_name" "$msg_count" "$tok_in" "$tok_out" "$status" "$display")"$'\n'
  done <<< "$agent_data"

  local fzf_output
  fzf_output=$(printf '%s' "$colored_data" \
    | fzf \
      --ansi \
      --color="$fzf_colors" \
      --delimiter='\t' \
      --with-nth=6 \
      --expect=Enter,l,b,Backspace,h,1,3,4,q \
      --bind='j:down,k:up,Home:first,End:last,g:first,G:last' \
      --header="$header" \
      --no-multi \
      --reverse \
      --prompt="Agents> " \
      --height=100% \
      --no-preview \
    2>/dev/null) || true

  local key
  key=$(printf '%s' "$fzf_output" | head -1)
  local selection
  selection=$(printf '%s' "$fzf_output" | tail -n +2)

  case "$key" in
    Enter|l)
      if [[ -n "$selection" ]]; then
        local selected_agent
        selected_agent=$(printf '%s' "$selection" | head -1 | cut -f1)
        echo "view:agent:${session_id}:${selected_agent}"
      else
        echo "back"
      fi
      ;;
    b|Backspace|h|1) echo "view:sessions" ;;
    3) echo "view:agents" ;;
    4) echo "view:todos" ;;
    *) echo "quit" ;;
  esac
}
