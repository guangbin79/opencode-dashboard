#!/bin/bash
# view_agents - fzf-based agent usage browser
# Returns: "quit" | "view:sessions" | "view:todos"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/lib/render.sh"

_agent_color_name() {
  case "${1}" in
    Sisyphus|Sisyphus-Junior|Ultraworker) printf '%s%s%s' "${N_PURPLE}"  "${1}" "${N_RESET}" ;;
    explore|librarian)                     printf '%s%s%s' "${N_TEAL}"    "${1}" "${N_RESET}" ;;
    oracle)                                printf '%s%s%s' "${N_FROST}"   "${1}" "${N_RESET}" ;;
    build)                                 printf '%s%s%s' "${N_GREEN}"   "${1}" "${N_RESET}" ;;
    Prometheus|Atlas|Metis|Momus)          printf '%s%s%s' "${N_BLUE}"    "${1}" "${N_RESET}" ;;
    compaction)                            printf '%s%s%s' "${N_DIM_MOD}" "${1}" "${N_RESET}" ;;
    *)                                     printf '%s%s%s' "${N_FG}"      "${1}" "${N_RESET}" ;;
  esac
}

# TSV input: agent(1) msgs(2) in_tok(3) out_tok(4) avg(5) sessions(6)
_agent_format_line() {
  local IFS=$'\t'
  read -r c1 c2 c3 c4 _c5 c6 <<< "$1"
  local colored_name
  colored_name="$(_agent_color_name "$c1")"
  printf '%s\t%s\t%s%s%s\t%s%s%s\t%s%s%s\t%s%s%s\n' \
    "${c1}" \
    "${colored_name}" \
    "${N_BRIGHT}" "$(printf '%6s' "${c2}")" "${N_RESET}" \
    "${N_BLUE}"   "$(printf '%8s' "${c3}")" "${N_RESET}" \
    "${N_TEAL}"   "$(printf '%8s' "${c4}")" "${N_RESET}" \
    "${N_DIM}"    "$(printf '%4s' "${c6}")" "${N_RESET}"
}

view_agents() {
  local data
  data=$(python3 "${SCRIPT_DIR}/lib/data.py" agent-stats --sort count 2>/dev/null)
  if [[ -z "$data" ]]; then
    echo "No agent data available." >&2
    echo "quit"
    return 0
  fi

  local header_line separator_line
  header_line=$'\t'"$(n_column_header "Agent")"$'\t'"$(n_column_header "  Msgs")"$'\t'"$(n_column_header "   Input")"$'\t'"$(n_column_header "  Output")"$'\t'"$(n_column_header "Sess")"
  separator_line=$'\t'"${N_DIM}──────────────────${N_RESET}"$'\t'"${N_DIM}──────${N_RESET}"$'\t'"${N_DIM}────────${N_RESET}"$'\t'"${N_DIM}────────${N_RESET}"$'\t'"${N_DIM}────${N_RESET}"

  local formatted=""
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    formatted="${formatted}$(_agent_format_line "$line")"$'\n'
  done <<< "$data"

  local result key
  result=$(printf '%s' "$formatted" \
    | fzf \
      --ansi \
      --color="$FZF_NORD_COLORS" \
      --delimiter='\t' \
      --with-nth=2.. \
      --expect=Enter,1,2,4,q \
      --preview="python3 '${SCRIPT_DIR}/lib/views/_agent_preview.py' {1} '${SCRIPT_DIR}/lib/data.py'" \
      --preview-window='right:60%:wrap' \
      --bind='j:down,k:up' \
      --header="$(n_header_bar "Agents")"$'\n'"$(n_help_bar agents)"$'\n'"${header_line}"$'\n'"${separator_line}" \
      --no-multi \
      --reverse \
      --prompt='agents> ' \
      --height=100% \
    ) || true

  key=$(head -1 <<< "$result")
  case "$key" in
    1) echo "view:sessions" ;;
    2) echo "view:detail" ;;
    4) echo "view:todos" ;;
    Enter) echo "view:agents" ;;
    *) echo "quit" ;;
  esac
  return 0
}
