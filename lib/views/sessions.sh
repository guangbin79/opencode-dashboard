#!/bin/bash
# Session List view for OpenCode dashboard
# Provides view_sessions() - fzf-based session browser with Nord colors

# _sessions_format_preview: $1=session_id, $2=path to data.py
_sessions_format_preview() {
  local session_id="$1"
  local data_py="$2"

  local json
  json=$(python3 "$data_py" session-meta "$session_id" 2>/dev/null)
  if [[ -z "$json" ]]; then
    printf '\033[38;2;191;97;106mNo data available\033[0m\n'
    return
  fi

  local err
  err=$(printf '%s' "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('error',''))" 2>/dev/null)
  if [[ -n "$err" ]]; then
    printf '\033[38;2;191;97;106mError: %s\033[0m\n' "$err"
    return
  fi

  local title project directory slug version created updated messages
  local tokens_in tokens_out cost agents_str

  title=$(printf '%s' "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('title',''))" 2>/dev/null)
  project=$(printf '%s' "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('project',''))" 2>/dev/null)
  directory=$(printf '%s' "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('directory',''))" 2>/dev/null)
  slug=$(printf '%s' "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('slug',''))" 2>/dev/null)
  version=$(printf '%s' "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('version',''))" 2>/dev/null)
  created=$(printf '%s' "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('created',''))" 2>/dev/null)
  updated=$(printf '%s' "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('updated',''))" 2>/dev/null)
  messages=$(printf '%s' "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('messages',0))" 2>/dev/null)
  tokens_in=$(printf '%s' "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); t=d.get('tokens_total',{}); print(t.get('input',0))" 2>/dev/null)
  tokens_out=$(printf '%s' "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); t=d.get('tokens_total',{}); print(t.get('output',0))" 2>/dev/null)
  cost=$(printf '%s' "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cost_total',0))" 2>/dev/null)
  agents_str=$(printf '%s' "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(', '.join(d.get('agents',[])))" 2>/dev/null)

  local tokens_in_f tokens_out_f
  if [[ "$tokens_in" -ge 1000 ]] 2>/dev/null; then
    tokens_in_f=$(printf '%d.%dk' $((tokens_in / 1000)) $(( (tokens_in % 1000) / 100 )))
  else
    tokens_in_f="$tokens_in"
  fi
  if [[ "$tokens_out" -ge 1000 ]] 2>/dev/null; then
    tokens_out_f=$(printf '%d.%dk' $((tokens_out / 1000)) $(( (tokens_out % 1000) / 100 )))
  else
    tokens_out_f="$tokens_out"
  fi

  local C=$'\033[38;2;136;192;208m'    # cyan
  local B=$'\033[1m'
  local D=$'\033[38;2;76;86;106m'       # dim
  local T=$'\033[38;2;143;188;187m'     # teal
  local BL=$'\033[38;2;129;161;193m'    # blue
  local G=$'\033[38;2;163;190;140m'     # green
  local Y=$'\033[38;2;235;203;139m'     # yellow
  local R=$'\033[0m'
  local S=$'\033[38;2;67;76;94m'        # separator

  printf '\n'
  printf '  %s%s%s%s\n' "$B" "$C" "$title" "$R"

  printf '  %s----------------------------------------%s\n' "$S" "$R"

  if [[ -n "$project" ]]; then
    printf '  %sproject%s   %s\n' "$D" "$R" "$project"
  fi
  if [[ -n "$directory" ]]; then
    printf '  %sdirectory%s %s%s%s\n' "$D" "$R" "$BL" "$directory" "$R"
  fi
  if [[ -n "$slug" ]]; then
    printf '  %sslug%s      %s\n' "$D" "$R" "$slug"
  fi

  printf '  %s----------------------------------------%s\n' "$S" "$R"

  if [[ -n "$created" ]]; then
    printf '  %screated%s   %s\n' "$D" "$R" "$created"
  fi
  if [[ -n "$updated" ]]; then
    printf '  %supdated%s   %s\n' "$D" "$R" "$updated"
  fi

  printf '  %s----------------------------------------%s\n' "$S" "$R"

  printf '  %smessages%s  %s%s%s\n' "$D" "$R" "$Y" "$messages" "$R"
  printf '  %sagents%s    %s%s%s\n' "$D" "$R" "$T" "$agents_str" "$R"

  printf '  %stokens%s    in: %s%s%s  out: %s%s%s\n' \
    "$D" "$R" "$G" "$tokens_in_f" "$R" "$G" "$tokens_out_f" "$R"

  if [[ -n "$cost" && "$cost" != "0" && "$cost" != "0.0" ]]; then
    printf '  %scost%s      %s$%s%s\n' "$D" "$R" "$Y" "$cost" "$R"
  fi

  printf '\n'
}

# view_sessions
# Shows fzf session list. Returns:
#   "quit" - user pressed q
#   "view:detail:<session_id>" - user selected a session to view detail
#   "view:agents" - user pressed 3 to switch to agents view
#   "view:todos" - user pressed 4 to switch to todos view
view_sessions() {
  local SCRIPT_DIR
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  local data_py="$SCRIPT_DIR/lib/data.py"

  # shellcheck source=/dev/null
  [[ -f "$SCRIPT_DIR/lib/render.sh" ]] && source "$SCRIPT_DIR/lib/render.sh"

  local session_data
  session_data=$(python3 "$data_py" sessions --limit 100 --active --sort updated 2>/dev/null)
  if [[ $? -ne 0 || -z "$session_data" ]]; then
    echo "quit"
    return 0
  fi

  local CYAN=$'\033[38;2;136;192;208m'
  local BRIGHT=$'\033[38;2;236;239;244m'
  local TEAL=$'\033[38;2;143;188;187m'
  local DIM=$'\033[38;2;76;86;106m'
  local RESET=$'\033[0m'

  # TSV: 1=session_id 2=title 3=project_name 4=directory 5=msg_count 6=agents 7=updated_relative 8=slug

  local fzf_colors
  if [[ -n "${FZF_NORD_COLORS:-}" ]]; then
    fzf_colors="$FZF_NORD_COLORS"
  else
    fzf_colors='fg:#D8DEE9,bg:#2E3440,hl:#88C0D0,fg+:#ECEFF4,bg+:#3B4252,hl+:#88C0D0,border:#434C5E,header:#5E81AC,gutter:#434C5E,spinner:#88C0D0,info:#81A1C1,pointer:#88C0D0,marker:#A3BE8C,prompt:#5E81AC,selected-bg:#434C5E'
  fi

  local preview_cmd
  local escaped_data_py
  escaped_data_py=$(printf '%s' "$data_py" | sed "s/'/'\\\\''/g")
  preview_cmd="$SCRIPT_DIR/lib/views/sessions.sh _preview {1} '$escaped_data_py'"

  local fzf_output
  fzf_output=$(printf '%s\n' "$session_data" \
    | awk -F'\t' -v cyan="$CYAN" -v bright="$BRIGHT" -v teal="$TEAL" -v dim="$DIM" -v reset="$RESET" '
      BEGIN { OFS="\t" }
      {
        title = $2
        if (length(title) > 40) title = substr(title, 1, 37) "..."
        agents = $6
        if (length(agents) > 30) agents = substr(agents, 1, 27) "..."
        $2 = cyan title reset
        $5 = bright $5 reset
        $6 = teal agents reset
        $7 = dim $7 reset
        print
      }
    ' \
    | fzf \
      --ansi \
      --color="$fzf_colors" \
      --delimiter='\t' \
      --with-nth='2,5,6,7' \
      --expect=Enter,1,3,4,q \
      --preview="$preview_cmd" \
      --preview-window='right:60%:wrap' \
      --bind='j:down' \
      --bind='k:up' \
      --header='[Enter] detail  [1-4] views  [q] quit  [/] search' \
      --no-multi \
      --reverse \
      --prompt='sessions> ' \
      --height=100% \
    2>/dev/null) || true

  local key
  key=$(printf '%s' "$fzf_output" | head -1)
  local selection
  selection=$(printf '%s' "$fzf_output" | tail -n +2)

  case "$key" in
    Enter)
      if [[ -n "$selection" ]]; then
        local selected_id
        selected_id=$(printf '%s' "$selection" | head -1 | cut -f1)
        echo "view:detail:${selected_id}"
      else
        echo "quit"
      fi
      ;;
    1) echo "view:sessions" ;;
    3) echo "view:agents" ;;
    4) echo "view:todos" ;;
    *) echo "quit" ;;
  esac
}

# _sessions_preview_entry: dispatches preview from fzf --preview
_sessions_preview_entry() {
  local action="$1"
  local session_id="$2"
  local data_py="$3"

  if [[ "$action" == "_preview" ]]; then
    _sessions_format_preview "$session_id" "$data_py"
  fi
}

if [[ "${1:-}" == "_preview" ]]; then
  _sessions_preview_entry "$1" "${2:-}" "${3:-}"
fi
