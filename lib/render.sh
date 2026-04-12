#!/bin/bash
# Nord ANSI color theme and formatting helpers
# Source this file: source /path/to/render.sh

# --- Foreground colors (Nord palette) ---
N_FG=$'\033[38;2;216;222;233m'       # nord4 - primary text
N_BRIGHT=$'\033[38;2;236;239;244m'   # nord6 - bright/emphasis
N_DIM=$'\033[38;2;76;86;106m'        # nord3 - muted text
N_CYAN=$'\033[38;2;136;192;208m'     # nord8 - titles, highlights
N_BLUE=$'\033[38;2;129;161;193m'     # nord9 - paths, links
N_TEAL=$'\033[38;2;143;188;187m'     # nord7 - agent names
N_GREEN=$'\033[38;2;163;190;140m'    # nord14 - success/completed
N_YELLOW=$'\033[38;2;235;203;139m'   # nord13 - pending
N_ORANGE=$'\033[38;2;208;135;112m'   # nord12 - warnings
N_RED=$'\033[38;2;191;97;106m'       # nord11 - errors
N_PURPLE=$'\033[38;2;180;142;173m'   # nord15 - special
N_FROST=$'\033[38;2;94;129;172m'     # nord10 - subtle accent

# --- Background ---
N_BG=$'\033[48;2;46;52;64m'          # nord0
N_BG_DIM=$'\033[48;2;59;66;82m'      # nord1

# --- Modifiers ---
N_BOLD=$'\033[1m'
N_DIM_MOD=$'\033[2m'
N_ITALIC=$'\033[3m'
N_UNDERLINE=$'\033[4m'
N_RESET=$'\033[0m'

# --- fzf Nord color string ---
FZF_NORD_COLORS='fg:#D8DEE9,bg:#2E3440,hl:#88C0D0,fg+:#ECEFF4,bg+:#3B4252,hl+:#88C0D0,border:#434C5E,header:#5E81AC,gutter:#434C5E,spinner:#88C0D0,info:#81A1C1,pointer:#88C0D0,marker:#A3BE8C,prompt:#5E81AC,selected-bg:#434C5E'

# --- Helper functions ---

# Wrap text in color + reset
# Usage: n_color N_CYAN "hello"
n_color() {
  local color_var="${1}"
  local text="${2}"
  local color
  eval "color=\"\${${color_var}}\""
  printf '%s%s%s' "${color}" "${text}" "${N_RESET}"
}

# Bold text
n_bold() {
  printf '%s%s%s' "${N_BOLD}" "${1}" "${N_RESET}"
}

# Dimmed text
n_dim() {
  printf '%s%s%s' "${N_DIM_MOD}" "${1}" "${N_RESET}"
}

# Truncate text with ellipsis
# Usage: n_truncate "some long text" 10
n_truncate() {
  local text="${1}"
  local max_len="${2}"
  local len=${#text}
  if (( len <= max_len )); then
    printf '%s' "${text}"
  else
    printf '%s...' "${text:0:$((max_len - 3))}"
  fi
}

# Convert epoch_ms to relative time string
# Usage: n_relative_time 1712836800000
n_relative_time() {
  local epoch_ms="${1}"
  local epoch_s=$((epoch_ms / 1000))
  local now
  now=$(date +%s)
  local diff=$((now - epoch_s))

  if ((diff < 60)); then
    printf 'just now'
  elif ((diff < 3600)); then
    printf '%dm ago' $((diff / 60))
  elif ((diff < 86400)); then
    printf '%dh ago' $((diff / 3600))
  elif ((diff < 604800)); then
    printf '%dd ago' $((diff / 86400))
  elif ((diff < 31536000)); then
    date -d "@${epoch_s}" '+%b %d' 2>/dev/null || printf '%dd ago' $((diff / 86400))
  else
    date -d "@${epoch_s}" '+%Y-%m-%d' 2>/dev/null || printf '%dd ago' $((diff / 86400))
  fi
}

# Format token count
# Usage: n_format_tokens 12400  ->  "12.4k"
n_format_tokens() {
  local count="${1}"
  if ((count >= 1000)); then
    local thousands=$((count / 1000))
    local hundreds=$(( (count % 1000) / 100 ))
    printf '%d.%dk' "${thousands}" "${hundreds}"
  else
    printf '%d' "${count}"
  fi
}

# Return colored status icon
# Usage: n_status_icon completed
n_status_icon() {
  local status="${1}"
  case "${status}" in
    completed)
      printf '%s%s%s' "${N_GREEN}" "[v]" "${N_RESET}"
      ;;
    in_progress)
      printf '%s%s%s' "${N_YELLOW}" "[*]" "${N_RESET}"
      ;;
    pending)
      printf '%s%s%s' "${N_DIM}" "[o]" "${N_RESET}"
      ;;
    cancelled)
      printf '%s%s%s' "${N_RED}" "[x]" "${N_RESET}"
      ;;
    *)
      printf '%s%s%s' "${N_DIM}" "[?]" "${N_RESET}"
      ;;
  esac
}

# Return colored priority indicator
# Usage: n_priority_icon high
n_priority_icon() {
  local priority="${1}"
  case "${priority}" in
    high)
      printf '%s%s%s' "${N_RED}" "!!!" "${N_RESET}"
      ;;
    medium)
      printf '%s%s%s' "${N_YELLOW}" "!!" "${N_RESET}"
      ;;
    low)
      printf '%s%s%s' "${N_DIM}" "!" "${N_RESET}"
      ;;
    *)
      printf '%s%s%s' "${N_DIM}" "?" "${N_RESET}"
      ;;
  esac
}

# Return colored role indicator
# Usage: n_role_icon user
n_role_icon() {
  local role="${1}"
  case "${role}" in
    user)
      printf '%s%s%s' "${N_YELLOW}" ">" "${N_RESET}"
      ;;
    assistant)
      printf '%s%s%s' "${N_CYAN}" "<" "${N_RESET}"
      ;;
    tool)
      printf '%s%s%s' "${N_DIM}" "#" "${N_RESET}"
      ;;
    *)
      printf '%s%s%s' "${N_DIM}" "?" "${N_RESET}"
      ;;
  esac
}

# Print horizontal separator line
# Usage: n_separator 80
n_separator() {
  local width="${1:-80}"
  local sep
  sep=$(printf '%*s' "${width}" '' | tr ' ' '-')
  printf '%s%s%s' $'\033[38;2;67;76;94m' "${sep}" "${N_RESET}"
}

# Print top navigation header bar
# Usage: n_header_bar "Sessions" "Sessions" "Detail" "Agents" "Todos"
n_header_bar() {
  local active_view="${1}"
  shift
  local i=1
  local tab
  for tab in "$@"; do
    if [[ "${tab}" == "${active_view}" ]]; then
      printf '%s%s%s[%d %s]%s' "${N_BG}" "${N_BOLD}" "${N_CYAN}" "${i}" "${tab}" "${N_RESET}"
    else
      printf '%s[%d %s]%s' "${N_DIM}" "${i}" "${tab}" "${N_RESET}"
    fi
    printf '  '
    i=$((i + 1))
  done
}
