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

  # --- Build header ---
  local header
  header="$(n_header_bar "Todos")"$'\n'"$(n_help_bar todos)"

  # --- Count todos per status ---
  local ip_count=0 p_count=0 c_count=0 x_count=0
  while IFS=$'\t' read -r _sid _status _rest; do
    [[ -z "$_sid" ]] && continue
    case "$_status" in
      in_progress) ((ip_count++)) ;;
      pending)     ((p_count++)) ;;
      completed)   ((c_count++)) ;;
      cancelled)   ((x_count++)) ;;
    esac
  done <<< "$data"

  # --- Process with grouping and fixed-width columns ---
  local colored_data=""
  local last_status=""

  while IFS=$'\t' read -r sid status priority content session_title position created_rel; do
    [[ -z "$sid" ]] && continue

    if [[ "$status" != "$last_status" ]]; then
      case "$status" in
        in_progress) colored_data+="${N_DIM}-- In Progress (${ip_count}) --${N_RESET}"$'\n' ;;
        pending)     colored_data+="${N_DIM}-- Pending (${p_count}) --${N_RESET}"$'\n' ;;
        completed)   colored_data+="${N_DIM}-- Completed (${c_count}) --${N_RESET}"$'\n' ;;
        cancelled)   colored_data+="${N_DIM}-- Cancelled (${x_count}) --${N_RESET}"$'\n' ;;
      esac
      last_status="$status"
    fi

    local sicon
    case "$status" in
      in_progress) sicon="${N_YELLOW}[~]${N_RESET}" ;;
      pending)     sicon="${N_DIM}[ ]${N_RESET}" ;;
      completed)   sicon="${N_GREEN}[x]${N_RESET}" ;;
      cancelled)   sicon="${N_RED}[!]${N_RESET}" ;;
      *)           sicon="${N_DIM}[?]${N_RESET}" ;;
    esac

    local picon
    case "$priority" in
      high)   picon="${N_RED}!!!${N_RESET}" ;;
      medium) picon="${N_YELLOW}!! ${N_RESET}" ;;
      low)    picon="${N_DIM}!  ${N_RESET}" ;;
      *)      picon="${N_DIM}?  ${N_RESET}" ;;
    esac

    local c_trunc
    c_trunc="$(n_truncate "$content" 45)"
    local t_trunc
    t_trunc="$(n_truncate "$session_title" 15)"

    # TSV: raw fields 1-7, display fields 8-12
    colored_data+="$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
      "$sid" "$status" "$priority" "$content" "$session_title" "$position" "$created_rel" \
      "$sicon" "$picon" "${N_FG}${c_trunc}${N_RESET}" \
      "${N_BLUE}${t_trunc}${N_RESET}" "${N_DIM}${created_rel}${N_RESET}")"$'\n'
  done <<< "$data"

  # --- Preview command ---
  local preview_cmd
  preview_cmd="'$_VIEW_TODOS_SCRIPT_DIR/lib/views/todos.sh' _preview {1} '$_VIEW_TODOS_SCRIPT_DIR/lib/data.py'"

  # --- FZF selection ---
  local result
  result=$(printf '%s' "$colored_data" \
    | fzf \
      --ansi \
      --color="$FZF_NORD_COLORS" \
      --delimiter='\t' \
      --with-nth=8,9,10,11,12 \
      --expect=Enter,1,2,3,q \
      --preview="$preview_cmd" \
      --preview-window='right:55%:wrap' \
      --bind='j:down,k:up' \
      --header="$header" \
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
    2) echo "view:detail" ;;
    3) echo "view:agents" ;;
    *) echo "quit" ;;
  esac
}

# _todos_format_preview: formats session metadata for preview pane
# Args: $1=session_id, $2=path to data.py
_todos_format_preview() {
  local session_id="$1"
  local data_py="$2"

  # Source render.sh for Nord colors when running as preview subprocess
  # shellcheck source=/dev/null
  [[ -z "${N_CYAN:-}" ]] && source "$_VIEW_TODOS_DIR/../render.sh"

  # Guard: skip preview for separator lines (not valid session IDs)
  if [[ -z "$session_id" || "$session_id" != ses_* ]]; then
    printf '\n'
    printf '  %sSelect a todo item to see session details%s\n' "$N_DIM" "$N_RESET"
    return
  fi

  local json
  json=$(python3 "$data_py" session-meta "$session_id" 2>/dev/null)
  if [[ -z "$json" ]]; then
    printf '%sNo data available%s\n' "$N_DIM" "$N_RESET"
    return
  fi

  local err
  err=$(printf '%s' "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('error',''))" 2>/dev/null)
  if [[ -n "$err" ]]; then
    printf '%sError: %s%s\n' "$N_RED" "$err" "$N_RESET"
    return
  fi

  local title project messages created updated agents_str
  title=$(printf '%s' "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('title',''))" 2>/dev/null)
  project=$(printf '%s' "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('project',''))" 2>/dev/null)
  messages=$(printf '%s' "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('messages',0))" 2>/dev/null)
  created=$(printf '%s' "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('created',''))" 2>/dev/null)
  updated=$(printf '%s' "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('updated',''))" 2>/dev/null)
  agents_str=$(printf '%s' "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(', '.join(d.get('agents',[])))" 2>/dev/null)

  local tokens_in tokens_out
  tokens_in=$(printf '%s' "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); t=d.get('tokens_total',{}); print(t.get('input',0))" 2>/dev/null)
  tokens_out=$(printf '%s' "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); t=d.get('tokens_total',{}); print(t.get('output',0))" 2>/dev/null)

  local S=$'\033[38;2;67;76;94m'
  printf '\n'
  printf '  %s%s%s%s\n' "$N_BOLD" "$N_CYAN" "$title" "$N_RESET"
  printf '  %s----------------------------------------%s\n' "$S" "$N_RESET"

  [[ -n "$project" ]] && printf '  %sproject%s   %s\n' "$N_DIM" "$N_RESET" "$project"
  printf '  %smessages%s  %s%s%s\n' "$N_DIM" "$N_RESET" "$N_YELLOW" "$messages" "$N_RESET"
  [[ -n "$agents_str" ]] && printf '  %sagents%s    %s%s%s\n' "$N_DIM" "$N_RESET" "$N_TEAL" "$agents_str" "$N_RESET"

  printf '  %s----------------------------------------%s\n' "$S" "$N_RESET"
  [[ -n "$created" ]] && printf '  %screated%s   %s\n' "$N_DIM" "$N_RESET" "$created"
  [[ -n "$updated" ]] && printf '  %supdated%s   %s\n' "$N_DIM" "$N_RESET" "$updated"

  if [[ -n "$tokens_in" && "$tokens_in" != "0" ]]; then
    printf '  %stokens%s    in: %s  out: %s\n' "$N_DIM" "$N_RESET" "$tokens_in" "$tokens_out"
  fi
  printf '\n'
}

# _todos_preview_entry: dispatches preview from fzf --preview
_todos_preview_entry() {
  local action="$1"
  local session_id="$2"
  local data_py="$3"

  if [[ "$action" == "_preview" ]]; then
    _todos_format_preview "$session_id" "$data_py"
  fi
}

# If called with _preview as first arg, run the preview function
if [[ "${1:-}" == "_preview" ]]; then
  _todos_preview_entry "$1" "${2:-}" "${3:-}"
fi
