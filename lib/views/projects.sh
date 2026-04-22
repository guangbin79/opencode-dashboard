#!/bin/bash
# Projects view (L1) for OpenCode dashboard
# Shows all projects with session counts and status
# Provides view_projects() - fzf-based project browser with Nord colors

_projects_format_line() {
  local name="$1" count="$2" running="$3" waiting="$4" updated="$5"

  local status_str
  if [[ "$running" -gt 0 ]] 2>/dev/null; then
    status_str="${N_GREEN}● ${running} running${N_RESET}"
  elif [[ "$waiting" -gt 0 ]] 2>/dev/null; then
    status_str="${N_YELLOW}● ${waiting} waiting${N_RESET}"
  else
    status_str="${N_DIM}○ idle${N_RESET}"
  fi

  local p_padded c_padded u_padded
  p_padded="${N_CYAN}$(printf '%-28s' "$(n_truncate "$name" 28)")${N_RESET}"
  c_padded="${N_BRIGHT}$(printf '%5s' "$count")${N_RESET}"
  u_padded="${N_DIM}$(printf '%-14s' "$updated")${N_RESET}"

  printf ' %s %s  %s  %s' "$p_padded" "$c_padded" "$status_str" "$u_padded"
}

view_projects() {
  local SCRIPT_DIR
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  local data_py="$SCRIPT_DIR/lib/data.py"
  local last_project="${1:-}"

  # shellcheck source=/dev/null
  [[ -f "$SCRIPT_DIR/lib/render.sh" ]] && source "$SCRIPT_DIR/lib/render.sh"

  local project_data
  project_data=$(python3 "$data_py" project-stats 2>/dev/null)
  if [[ $? -ne 0 || -z "$project_data" ]]; then
    echo "quit"
    return 0
  fi

  local fzf_colors
  if [[ -n "${FZF_NORD_COLORS:-}" ]]; then
    fzf_colors="$FZF_NORD_COLORS"
  else
    fzf_colors='fg:#D8DEE9,bg:#2E3440,hl:#88C0D0,fg+:#ECEFF4,bg+:#3B4252,hl+:#88C0D0,border:#434C5E,header:#5E81AC,gutter:#434C5E,spinner:#88C0D0,info:#81A1C1,pointer:#88C0D0,marker:#A3BE8C,prompt:#5E81AC,selected-bg:#434C5E'
  fi

  local header
  header="$(n_header_bar "Projects")"$'\n'"$(n_column_header "  Project                        Sessions  Status          Updated")"

  local colored_data=""
  while IFS=$'\t' read -r pname count running waiting updated latest; do
    [[ -z "$pname" ]] && continue
    local display
    display=$(_projects_format_line "$pname" "$count" "$running" "$waiting" "$updated")
    colored_data+="$(printf '%s\t%s' "$pname" "$display")"$'\n'
  done <<< "$project_data"

  if [[ -n "$last_project" && -n "$colored_data" ]]; then
    local all_lines before_lines after_lines
    all_lines=$(printf '%s' "$colored_data" | grep -n -F "$last_project" | head -1 | cut -d: -f1) || true
    if [[ -n "$all_lines" ]]; then
      local selected_line
      selected_line=$(printf '%s' "$colored_data" | sed -n "${all_lines}p") || true
      before_lines=$(printf '%s' "$colored_data" | head -n $((all_lines - 1))) || true
      after_lines=$(printf '%s' "$colored_data" | tail -n +"$((all_lines + 1))") || true
      colored_data="${selected_line}"$'\n'
      [[ -n "$after_lines" ]] && colored_data+="${after_lines}"$'\n'
      [[ -n "$before_lines" ]] && colored_data+="${before_lines}"$'\n'
    fi
  fi

  local fzf_output
  fzf_output=$(printf '%s' "$colored_data" \
    | fzf \
      --ansi \
      --color="$fzf_colors" \
      --delimiter='\t' \
      --with-nth=2 \
      --expect=Enter,l,1,2,3,4,q \
      --preview="echo '${N_DIM}Press Enter/l to browse sessions in this project${N_RESET}'" \
      --preview-window='right:50%:wrap' \
      --bind='j:down,k:up,gg:first,G:last' \
      --header="$header" \
      --no-multi \
      --reverse \
      --prompt='projects> ' \
      --height=100% \
    2>/dev/null) || true

  local key
  key=$(printf '%s' "$fzf_output" | head -1)
  local selection
  selection=$(printf '%s' "$fzf_output" | tail -n +2)

  case "$key" in
    Enter|l)
      if [[ -n "$selection" ]]; then
        local selected_project
        selected_project=$(printf '%s' "$selection" | head -1 | cut -f1)
        echo "view:sessions:${selected_project}"
      else
        echo "quit"
      fi
      ;;
    1) echo "view:projects" ;;
    2) echo "view:sessions" ;;
    3) echo "view:agents" ;;
    4) echo "view:todos" ;;
    *) echo "quit" ;;
  esac
}
