#!/bin/bash
# Session Detail view for OpenCode dashboard
# Provides view_detail() - fzf-based message browser with Nord colors

# _detail_format_preview
# Formats JSON from `data.py message-detail` into colored output for the preview pane.
# Args: $1 = message_id, $2 = path to data.py
_detail_format_preview() {
  local message_id="$1"
  local data_py="$2"

  local json
  json=$(python3 "$data_py" message-detail "$message_id" 2>/dev/null)
  if [[ -z "$json" ]]; then
    printf '\033[38;2;191;97;106mNo data available\033[0m\n'
    return
  fi

  # Check for error
  local err
  err=$(printf '%s' "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('error',''))" 2>/dev/null)
  if [[ -n "$err" ]]; then
    printf '\033[38;2;191;97;106mError: %s\033[0m\n' "$err"
    return
  fi

  # Extract fields via python3
  local role agent model provider tokens_in tokens_out tokens_reason
  local cost time_str duration_ms finish

  role=$(printf '%s' "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('role',''))" 2>/dev/null)
  agent=$(printf '%s' "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('agent',''))" 2>/dev/null)
  model=$(printf '%s' "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('model',''))" 2>/dev/null)
  provider=$(printf '%s' "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('provider',''))" 2>/dev/null)
  tokens_in=$(printf '%s' "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); t=d.get('tokens',{}); print(t.get('input',0))" 2>/dev/null)
  tokens_out=$(printf '%s' "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); t=d.get('tokens',{}); print(t.get('output',0))" 2>/dev/null)
  tokens_reason=$(printf '%s' "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); t=d.get('tokens',{}); print(t.get('reasoning',0))" 2>/dev/null)
  cost=$(printf '%s' "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cost',0))" 2>/dev/null)
  time_str=$(printf '%s' "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('time',''))" 2>/dev/null)
  duration_ms=$(printf '%s' "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('duration_ms',''))" 2>/dev/null)
  finish=$(printf '%s' "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('finish',''))" 2>/dev/null)

  # Format duration
  local duration_str=""
  if [[ -n "$duration_ms" && "$duration_ms" != "None" ]]; then
    local ms=${duration_ms%.*}
    if [[ "$ms" -ge 1000 ]] 2>/dev/null; then
      duration_str="$((ms / 1000)).$(( (ms % 1000) / 100 ))s"
    else
      duration_str="${ms}ms"
    fi
  fi

  # Format token counts
  _detail_fmt_tokens() {
    local count="$1"
    if [[ -z "$count" || "$count" == "0" ]]; then
      printf '0'
    elif [[ "$count" -ge 1000 ]] 2>/dev/null; then
      printf '%d.%dk' $((count / 1000)) $(( (count % 1000) / 100 ))
    else
      printf '%s' "$count"
    fi
  }

  local tokens_in_f tokens_out_f tokens_reason_f
  tokens_in_f=$(_detail_fmt_tokens "$tokens_in")
  tokens_out_f=$(_detail_fmt_tokens "$tokens_out")
  tokens_reason_f=$(_detail_fmt_tokens "$tokens_reason")

  # ANSI color codes
  local C=$'\033[38;2;136;192;208m'    # cyan - role/title
  local B=$'\033[1m'                    # bold
  local D=$'\033[38;2;76;86;106m'       # dim
  local T=$'\033[38;2;143;188;187m'     # teal - agent
  local BL=$'\033[38;2;129;161;193m'    # blue - model
  local G=$'\033[38;2;163;190;140m'     # green - tokens
  local Y=$'\033[38;2;235;203;139m'     # yellow - cost
  local P=$'\033[38;2;180;142;173m'     # purple - reasoning
  local FG=$'\033[38;2;216;222;233m'    # foreground
  local R=$'\033[0m'                    # reset
  local S=$'\033[38;2;67;76;94m'        # separator
  # Role icon
  local role_icon=""
  case "$role" in
    user)         role_icon="${Y}>${R}" ;;
    assistant)    role_icon="${C}<${R}" ;;
    tool)         role_icon="${D}#${R}" ;;
    *)            role_icon="${D}?${R}" ;;
  esac

  # Header
  printf '\n'
  printf '  %s%s%s %s%s%s' "$B" "$role_icon" "$R" "$B" "$role" "$R"
  if [[ -n "$agent" ]]; then
    printf '  %s%s%s' "$T" "$agent" "$R"
  fi
  printf '\n'

  # Separator
  printf '  %s----------------------------------------%s\n' "$S" "$R"

  # Model & provider
  if [[ -n "$model" ]]; then
    printf '  %smodel%s     %s%s%s' "$D" "$R" "$BL" "$model" "$R"
    if [[ -n "$provider" ]]; then
      printf '  %s(%s)%s' "$D" "$provider" "$R"
    fi
    printf '\n'
  fi

  # Time & duration
  if [[ -n "$time_str" ]]; then
    printf '  %stime%s      %s' "$D" "$R" "$time_str"
    if [[ -n "$duration_str" ]]; then
      printf '  %s(%s)%s' "$D" "$duration_str" "$R"
    fi
    printf '\n'
  fi

  # Tokens
  printf '  %stokens%s    in: %s%s%s' "$D" "$R" "$G" "$tokens_in_f" "$R"
  printf '  out: %s%s%s' "$G" "$tokens_out_f" "$R"
  if [[ -n "$tokens_reason" && "$tokens_reason" != "0" ]]; then
    printf '  reason: %s%s%s' "$P" "$tokens_reason_f" "$R"
  fi
  printf '\n'

  # Cost
  if [[ -n "$cost" && "$cost" != "0" && "$cost" != "0.0" && "$cost" != "None" ]]; then
    printf '  %scost%s      %s$%s%s\n' "$D" "$R" "$Y" "$cost" "$R"
  fi

  # Finish reason
  if [[ -n "$finish" ]]; then
    printf '  %sfinish%s    %s\n' "$D" "$R" "$finish"
  fi

  # Separator
  printf '  %s----------------------------------------%s\n' "$S" "$R"

  # Parts
  printf '%s' "$json" | python3 -c "
import sys, json

D = '\033[38;2;76;86;106m'
T = '\033[38;2;143;188;187m'
FG = '\033[38;2;216;222;233m'
BL = '\033[38;2;129;161;193m'
R = '\033[0m'
S = '\033[38;2;67;76;94m'
DIM = '\033[2m'
C = '\033[38;2;136;192;208m'
Y = '\033[38;2;235;203;139m'

d = json.load(sys.stdin)
parts = d.get('parts', [])
for i, p in enumerate(parts):
    ptype = p.get('type', '')
    if ptype == 'text':
        text = p.get('text', '')
        if text:
            # Wrap text lines
            for line in text.split('\n'):
                print(f'  {FG}{line}{R}')
    elif ptype == 'reasoning':
        text = p.get('text', '')
        if text:
            print(f'  {D}--- reasoning ---{R}')
            for line in text.split('\n'):
                print(f'  {D}{line}{R}')
    elif ptype == 'tool':
        tool_name = p.get('tool', '')
        print(f'  {T}[tool] {tool_name}{R}')
        inp = p.get('input', {})
        if inp:
            inp_str = json.dumps(inp, indent=2, ensure_ascii=False)
            for line in inp_str.split('\n'):
                print(f'  {BL}{line}{R}')
        output = p.get('output', '')
        if output:
            out_str = str(output)
            if len(out_str) > 500:
                out_str = out_str[:500] + '...'
            print(f'  {D}--- output ---{R}')
            for line in out_str.split('\n'):
                print(f'  {DIM}{line}{R}')
    elif ptype == 'tool-result':
        output = p.get('output', '')
        if output:
            out_str = str(output)
            if len(out_str) > 500:
                out_str = out_str[:500] + '...'
            for line in out_str.split('\n'):
                print(f'  {DIM}{line}{R}')
    elif ptype == 'step-start':
        snap = p.get('snapshot', '')
        if snap:
            print(f'  {D}[step] {snap}{R}')
" 2>/dev/null

  printf '\n'
}

# view_detail <session_id> <session_title>
# Shows messages for a session. Returns:
#   "back" - user pressed b/Backspace to go back to session list
#   "quit" - user pressed q
#   "view:sessions" - user pressed 1
#   "view:agents" - user pressed 3
#   "view:todos" - user pressed 4
view_detail() {
  local session_id="$1"
  local session_title="${2:-}"

  local SCRIPT_DIR
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  local data_py="$SCRIPT_DIR/lib/data.py"

  # Source render helpers if available
  # shellcheck source=/dev/null
  [[ -f "$SCRIPT_DIR/lib/render.sh" ]] && source "$SCRIPT_DIR/lib/render.sh"

  # Fetch message data
  local message_data
  message_data=$(python3 "$data_py" messages "$session_id" --limit 200 2>/dev/null)
  if [[ $? -ne 0 || -z "$message_data" ]]; then
    echo "back"
    return 0
  fi

  local header
  header="$(n_header_bar "Detail")"$'\n'"  ${session_title:-$session_id}"$'\n'"$(n_column_header "  Role  Agent                  Time         Tokens  Summary")"

  local fzf_colors
  if [[ -n "${FZF_NORD_COLORS:-}" ]]; then
    fzf_colors="$FZF_NORD_COLORS"
  else
    fzf_colors='fg:#D8DEE9,bg:#2E3440,hl:#88C0D0,fg+:#ECEFF4,bg+:#3B4252,hl+:#88C0D0,border:#434C5E,header:#5E81AC,gutter:#434C5E,spinner:#88C0D0,info:#81A1C1,pointer:#88C0D0,marker:#A3BE8C,prompt:#5E81AC,selected-bg:#434C5E'
  fi

  # Preview command
  local escaped_data_py
  escaped_data_py=$(printf '%s' "$data_py" | sed "s/'/'\\\\''/g")
  local preview_cmd
  preview_cmd="$SCRIPT_DIR/lib/views/detail.sh _preview {1} '$escaped_data_py'"

  # Build display lines with fixed-width printf padding
  local formatted=""
  while IFS=$'\t' read -r mid role agent time_str tok_in tok_out model preview_text; do
    [[ -z "$mid" ]] && continue

    local role_icon agent_color preview_color
    case "$role" in
      user)
        role_icon="${N_YELLOW}▶${N_RESET}"
        agent_color="$N_YELLOW"
        preview_color=""
        ;;
      assistant)
        role_icon="${N_CYAN}◀${N_RESET}"
        agent_color="$N_CYAN"
        preview_color=""
        ;;
      *)
        role_icon="${N_DIM}◆${N_RESET}"
        agent_color="$N_DIM"
        preview_color="$N_DIM"
        ;;
    esac

    local short_agent="${agent%% (*}"
    [[ ${#short_agent} -gt 20 ]] && short_agent="${short_agent:0:17}..."
    local agent_visible_len=${#short_agent}
    local agent_pad=$((20 - agent_visible_len))

    local tokens_val
    if [[ "$tok_in" -ge 1000 ]] 2>/dev/null; then
      tokens_val="$((tok_in / 1000)).$(( (tok_in % 1000) / 100 ))k"
    elif [[ "$role" == "user" ]]; then
      tokens_val="-"
    else
      tokens_val="$tok_in"
    fi

    local trunc_preview="$preview_text"
    [[ ${#trunc_preview} -gt 50 ]] && trunc_preview="${trunc_preview:0:47}..."

    local display
    display=" ${role_icon}  ${agent_color}${short_agent}${N_RESET}$(printf '%*s' $agent_pad '') ${N_DIM}$(printf '%-12s' "$time_str")${N_RESET} ${N_DIM}$(printf '%6s' "$tokens_val")${N_RESET}  ${preview_color}${trunc_preview}${N_RESET}"

    formatted+="$(printf '%s\t%s' "$mid" "$display")"$'\n'
  done <<< "$message_data"

  local fzf_output exit_code
  fzf_output=$(printf '%s' "$formatted" \
    | fzf \
      --ansi \
      --color="$fzf_colors" \
      --delimiter='\t' \
      --with-nth=2 \
      --expect=Enter,l,b,Backspace,h,1,2,3,4,q \
      --preview="$preview_cmd" \
      --preview-window='right:65%:wrap' \
      --bind='j:down' \
      --bind='k:up' \
      --header="$header" \
      --no-multi \
      --reverse \
      --prompt='detail> ' \
      --height=100% \
    2>/dev/null) || true

  local key
  key=$(printf '%s' "$fzf_output" | head -1)

  case "$key" in
    Enter) echo "back" ;;
    l) echo "back" ;;
    b|Backspace|h) echo "back" ;;
    1) echo "view:sessions" ;;
    2) echo "noop" ;;
    3) echo "view:agents" ;;
    4) echo "view:todos" ;;
    *) echo "quit" ;;
  esac
}

# _detail_preview_entry
# Standalone preview entry point - called by fzf's --preview
# Args: $1 = action ("_preview"), $2 = message_id, $3 = path to data.py
_detail_preview_entry() {
  local action="$1"
  local message_id="$2"
  local data_py="$3"

  if [[ "$action" == "_preview" ]]; then
    _detail_format_preview "$message_id" "$data_py"
  fi
}

# If called with _preview as first arg, run the preview function
# This allows the script to be used as a preview command
if [[ "${1:-}" == "_preview" ]]; then
  _detail_preview_entry "$1" "${2:-}" "${3:-}"
fi
