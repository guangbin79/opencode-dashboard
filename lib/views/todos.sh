#!/bin/bash
# Source: source lib/views/todos.sh

_VIEW_TODOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_VIEW_TODOS_SCRIPT_DIR="$(cd "$_VIEW_TODOS_DIR/../.." && pwd)"

# view_todos
# Returns: "quit" | "view:sessions" | "view:detail:<session_id>" | "view:agents"
view_todos() {
  local data
  data=$(python3 "$_VIEW_TODOS_SCRIPT_DIR/lib/data.py" todos --status all 2>/dev/null)
  if [[ $? -ne 0 ]]; then
    echo "quit"
    return 1
  fi

  if [[ -z "$data" ]]; then
    echo "quit"
    return 0
  fi

  local colored_data
  colored_data=$(while IFS=$'\t' read -r sid status priority content session_title position created_rel; do
    local status_icon
    case "$status" in
      completed)  status_icon="${N_GREEN}[v]${N_RESET}" ;;
      in_progress) status_icon="${N_YELLOW}[*]${N_RESET}" ;;
      pending)    status_icon="${N_DIM}[o]${N_RESET}" ;;
      cancelled)  status_icon="${N_RED}[x]${N_RESET}" ;;
      *)          status_icon="${N_DIM}[?]${N_RESET}" ;;
    esac

    local prio_icon
    case "$priority" in
      high)   prio_icon="${N_RED}!!!${N_RESET}" ;;
      medium) prio_icon="${N_YELLOW}!!${N_RESET}" ;;
      low)    prio_icon="${N_DIM}!${N_RESET}" ;;
      *)      prio_icon="${N_DIM}?${N_RESET}" ;;
    esac

    local content_display
    content_display="$(n_truncate "$content" 50)"

    local session_display
    session_display="${N_BLUE}$(n_truncate "$session_title" 25)${N_RESET}"

    local time_display
    time_display="${N_DIM}${created_rel}${N_RESET}"

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$sid" "$status" "$priority" "$content" "$session_title" "$position" "$created_rel" \
      "$status_icon" "$prio_icon" "${N_FG}${content_display}${N_RESET}" "$session_display" "$time_display"
  done <<< "$data")

  local preview_cmd
  preview_cmd="python3 '$_VIEW_TODOS_SCRIPT_DIR/lib/data.py' session-meta {1} 2>/dev/null | python3 -c \"
import sys, json
try:
    d = json.load(sys.stdin)
    if 'error' in d:
        print(d['error'])
    else:
        print(f'\\033[1mSession\\033[0m: {d.get(\\\"title\\\", \\\"\\\")}')
        print(f'\\033[38;2;129;161;193mProject\\033[0m: {d.get(\\\"project\\\", \\\"\\\")}')
        print(f'Messages: {d.get(\\\"message_count\\\", 0)}')
        agents = d.get(\\\"agents\\\", [])
        if agents:
            print(f'Agents: {\\\", \\\".join(agents)}')
        created = d.get(\\\"created\\\", \\\"\\\")
        updated = d.get(\\\"updated\\\", \\\"\\\")
        if created: print(f'Created: {created}')
        if updated: print(f'Updated: {updated}')
        tokens_in = d.get(\\\"tokens\\\", {}).get(\\\"input\\\", 0)
        tokens_out = d.get(\\\"tokens\\\", {}).get(\\\"output\\\", 0)
        if tokens_in or tokens_out:
            print(f'Tokens: {tokens_in} in / {tokens_out} out')
except: pass
\""

  local result
  result=$(printf '%s\n' "$colored_data" \
    | fzf \
      --ansi \
      --color="$FZF_NORD_COLORS" \
      --delimiter='\t' \
      --with-nth=8,9,10,11,12 \
      --expect=Enter,1,2,3,q \
      --preview="$preview_cmd" \
      --preview-window='right:55%:wrap' \
      --bind='j:down,k:up' \
      --header='[Enter] go to session  [1-4] views  [q] quit' \
      --no-multi \
      --reverse \
      --prompt='todos> ' \
      --height=100% \
    2>/dev/null) || true

  local key
  key=$(printf '%s' "$result" | head -1)
  local selection
  selection=$(printf '%s' "$result" | tail -n +2)

  case "$key" in
    Enter)
      if [[ -n "$selection" ]]; then
        local session_id
        session_id=$(printf '%s' "$selection" | head -1 | cut -f1)
        echo "view:detail:${session_id}"
      else
        echo "quit"
      fi
      ;;
    1) echo "view:sessions" ;;
    2) echo "view:sessions" ;;
    3) echo "view:agents" ;;
    *) echo "quit" ;;
  esac
}
