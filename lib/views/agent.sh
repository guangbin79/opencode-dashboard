#!/bin/bash
# Agent Interaction view for OpenCode dashboard
# Provides view_agent() - tmux split with message stream and input

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/lib/render.sh"
source "${SCRIPT_DIR}/lib/tmux.sh"

AGENT_POLL_INTERVAL="${AGENT_POLL_INTERVAL:-1}"
AGENT_MAX_MESSAGES="${AGENT_MAX_MESSAGES:-100}"
AGENT_API_BASE="${AGENT_API_BASE:-http://localhost:13284}"

_agent_show_header() {
  local session_id="$1"
  local data_py="$SCRIPT_DIR/lib/data.py"

  local json status="idle" agent=""
  json=$(python3 "$data_py" agent-status "$session_id" 2>/dev/null)
  if [[ -n "$json" ]]; then
    status=$(printf '%s' "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status','idle'))" 2>/dev/null)
    agent=$(printf '%s' "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('agent',''))" 2>/dev/null)
  fi

  local model
  model=$(python3 "$data_py" messages "$session_id" --limit 200 2>/dev/null | tail -1 | cut -f7)

  local status_color status_icon
  case "$status" in
    running) status_color="$N_GREEN"; status_icon="●" ;;
    waiting) status_color="$N_YELLOW"; status_icon="●" ;;
    *)       status_color="$N_DIM"; status_icon="○" ;;
  esac

  tmux_clear
  printf ' %s%s%s %s%s%s' \
    "$status_color" "$status_icon" "$N_RESET" \
    "$N_BOLD$N_CYAN" "${agent:-agent}" "$N_RESET"
  if [[ -n "$model" ]]; then
    printf '  %s%s%s' "$N_DIM" "$model" "$N_RESET"
  fi
  printf '  %s[%s]%s\n' "$N_DIM" "$status" "$N_RESET"
  n_separator "$(tmux_get_width)"
  printf '\n'
}

_agent_show_messages() {
  local session_id="$1"
  local data_py="$SCRIPT_DIR/lib/data.py"
  local width
  width=$(tmux_get_width)

  local message_data
  message_data=$(python3 "$data_py" messages "$session_id" --limit "$AGENT_MAX_MESSAGES" 2>/dev/null)
  [[ -z "$message_data" ]] && return

  local total
  total=$(printf '%s' "$message_data" | wc -l)
  local height
  height=$(tmux_get_height)
  local usable=$((height - 4))
  local skip=0
  (( total > usable )) && skip=$((total - usable))

  local n=0
  while IFS=$'\t' read -r mid role msg_agent time_str tok_in tok_out model preview_text; do
    [[ -z "$mid" ]] && continue
    n=$((n + 1))
    (( skip > 0 && n <= skip )) && continue

    local role_icon role_color
    case "$role" in
      user)      role_icon="${N_YELLOW}>${N_RESET}"; role_color="$N_YELLOW" ;;
      assistant) role_icon="${N_CYAN}<${N_RESET}"; role_color="$N_CYAN" ;;
      *)         role_icon="${N_DIM}#${N_RESET}"; role_color="$N_DIM" ;;
    esac

    local short_agent="${msg_agent%% (*}"
    [[ ${#short_agent} -gt 12 ]] && short_agent="${short_agent:0:9}..."

    local preview="$preview_text"
    local pw=$((width - 18 - ${#short_agent}))
    (( pw < 10 )) && pw=10
    [[ ${#preview} -gt $pw ]] && preview="${preview:0:$((pw - 3))}..."

    printf ' %s %s%-12s%s %s\n' "$role_icon" "$role_color" "$short_agent" "$N_RESET" "$preview"
  done <<< "$message_data"
}

_agent_send_message() {
  local session_id="$1"
  local message="$2"

  local escaped
  escaped=$(printf '%s' "$message" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))" 2>/dev/null)

  if ! curl -sf -X POST \
    -H "Content-Type: application/json" \
    -d "{\"content\":$escaped}" \
    "${AGENT_API_BASE}/session/${session_id}/message" 2>/dev/null; then
    printf '%sFailed to send message%s\n' "$N_RED" "$N_RESET"
    return 1
  fi
  return 0
}

_agent_abort() {
  local session_id="$1"

  if ! curl -sf -X POST "${AGENT_API_BASE}/session/${session_id}/abort" 2>/dev/null; then
    printf '%sFailed to abort agent%s\n' "$N_RED" "$N_RESET"
    return 1
  fi
  printf '%sAgent aborted%s\n' "$N_YELLOW" "$N_RESET"
  return 0
}

agent_stream_pane() {
  local session_id="$1"
  local data_py="$SCRIPT_DIR/lib/data.py"
  local last_count=0

  _agent_show_header "$session_id"
  last_count=$(python3 "$data_py" message-count "$session_id" 2>/dev/null || echo 0)
  _agent_show_messages "$session_id"

  while true; do
    if [[ -n "$AGENT_PANE_BOTTOM" ]]; then
      if ! tmux display-message -t "$AGENT_PANE_BOTTOM" -p '#{pane_id}' >/dev/null 2>&1; then
        break
      fi
    fi

    local count
    count=$(python3 "$data_py" message-count "$session_id" 2>/dev/null || echo "$last_count")

    if [[ "$count" != "$last_count" ]]; then
      _agent_show_header "$session_id"
      _agent_show_messages "$session_id"
      last_count="$count"
    fi

    sleep "$AGENT_POLL_INTERVAL"
  done
}

agent_input_pane() {
  local session_id="$1"

  tmux_clear
  printf '%s── Agent Input ──%s\n\n' "$N_BOLD$N_FROST" "$N_RESET"
  printf '%s[i] Input  [q] Quit  [a] Abort  [Esc Esc] Abort%s\n' "$N_DIM" "$N_RESET"
  n_separator "$(tmux_get_width)"
  printf '\n'

  local prev_was_esc=0

  while true; do
    local ch
    IFS= read -rsn1 ch 2>/dev/null || continue

    case "$ch" in
      i|I)
        prev_was_esc=0
        printf '%s> %s' "$N_CYAN" "$N_RESET"
        local input=""
        IFS= read -r input
        if [[ -n "$input" ]]; then
          _agent_send_message "$session_id" "$input"
        fi
        printf '\n'
        ;;
      q|Q)
        break
        ;;
      a|A)
        _agent_abort "$session_id"
        break
        ;;
      $'\x1b')
        local seq=""
        IFS= read -rsn1 -t 0.1 seq 2>/dev/null || true
        if [[ -z "$seq" ]]; then
          if [[ "$prev_was_esc" -eq 1 ]]; then
            _agent_abort "$session_id"
            break
          fi
          prev_was_esc=1
        elif [[ "$seq" == $'\x1b' ]]; then
          _agent_abort "$session_id"
          break
        else
          prev_was_esc=0
        fi
        ;;
      *)
        prev_was_esc=0
        ;;
    esac
  done
}

view_agent() {
  local session_id="$1"
  local session_title="${2:-}"
  local agent_script="${BASH_SOURCE[0]}"
  local data_py="$SCRIPT_DIR/lib/data.py"

  if ! tmux_is_running; then
    echo "back"
    return 0
  fi

  local count
  count=$(python3 "$data_py" message-count "$session_id" 2>/dev/null)
  if [[ -z "$count" ]]; then
    echo "back"
    return 0
  fi

  AGENT_PANE_BOTTOM=$(tmux split-window -v -p 30 -P -F '#{pane_id}' \
    -c "#{pane_current_path}" \
    "bash -c 'source \"$agent_script\"; agent_input_pane \"$session_id\"'")
  AGENT_PANE_TOP="$TMUX_PANE"
  AGENT_VIEW_ACTIVE="1"

  agent_stream_pane "$session_id"

  tmux_agent_close
  echo "back"
}
