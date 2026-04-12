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

view_agents() {
  local data
  data=$(python3 "${SCRIPT_DIR}/lib/data.py" agent-stats --sort count 2>/dev/null)
  if [[ -z "$data" ]]; then
    echo "No agent data available." >&2
    echo "quit"
    return 0
  fi

  local formatted=""
  while IFS=$'\t' read -r agent_name count input_tokens output_tokens avg sessions; do
    [[ -z "$agent_name" ]] && continue

    local short_name="${agent_name%% (*}"
    [[ ${#short_name} -gt 20 ]] && short_name="${short_name:0:17}..."
    local visible_len=${#short_name}
    local pad_spaces=$((20 - visible_len))

    local display
    display=" $(_agent_color_name "$short_name")$(printf '%*s' $pad_spaces '') ${N_BRIGHT}$(printf '%6s' "$count")${N_RESET}  ${N_DIM}$(printf '%12s' "$input_tokens")${N_RESET}  ${N_DIM}$(printf '%12s' "$output_tokens")${N_RESET} ${N_DIM}$(printf '%5s' "$sessions")${N_RESET}"

    formatted+="$(printf '%s\t%s' "$agent_name" "$display")"$'\n'
  done <<< "$data"

  local result key
  result=$(printf '%s' "$formatted" \
    | fzf \
      --ansi \
      --color="$FZF_NORD_COLORS" \
      --delimiter='\t' \
      --with-nth=2 \
      --expect=Enter,l,1,2,4,q \
      --preview="python3 '${SCRIPT_DIR}/lib/views/_agent_preview.py' {1} '${SCRIPT_DIR}/lib/data.py'" \
      --preview-window='right:60%:wrap' \
      --bind='j:down,k:up' \
      --header="$(n_header_bar "Agents")"$'\n'"$(n_help_bar agents)"$'\n'"$(n_column_header " Agent                    Msgs        Input        Output Sess")" \
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
    Enter|l) echo "view:agents" ;;
    *) echo "quit" ;;
  esac
  return 0
}
