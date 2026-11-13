# shellcheck shell=bash
# ui.sh: how the llm tools look at a terminal. Kit version 3, for docs/conventions.md version 4.
# llm-wiki keeps the original. Every other tool carries this file byte for byte, and a test holds
# the copies together, so change it in llm-wiki first and copy it in the same sitting. Bash 3.2.
#
# A tool sets three variables, then sources this file:
#   STYLE_OVERRIDE      the value of its own on/off variable, such as "${LLM_WIKI_STYLE:-}"
#   STYLE_PALETTE_FILE  a file that may hold a line palette=default or palette=colorblind
#   STYLE_THEME_FILE    a file that may hold a line theme=auto, theme=dark or theme=light
# LLM_PALETTE and LLM_THEME, which every llm tool reads, win over the files.
#
# Commands print through the pieces: ui_question, ui_keys and ui_prompt, ui_stage, ui_item,
# ui_detail, ui_table, ui_card, ui_turn, ui_step, ui_next, typed, ui_wait_start and
# ui_wait_stop, die. Never a colour code or an S_ variable:
# a lint test fails on one outside this file. Run it on its own to see every piece: bash ui.sh

: "${STYLE_OVERRIDE:=}" "${STYLE_PALETTE_FILE:=}" "${STYLE_THEME_FILE:=}"

# style_wanted <fd>: style on? The tool's variable, on or off, decides; else a terminal, no NO_COLOR, TERM not dumb.
style_wanted() {
  case "$STYLE_OVERRIDE" in on) return 0 ;; off) return 1 ;; esac
  [ -t "$1" ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]
}
style_utf8() {
  case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in *[Uu][Tt][Ff]-8* | *[Uu][Tt][Ff]8*) return 0 ;; esac
  return 1
}
# _ui_read <file> <key>: sets _UI_V to the last value of key= in the file, or to nothing.
_ui_read() {
  local l
  _UI_V=""
  [ -n "$1" ] && [ -r "$1" ] || return 0
  while IFS= read -r l || [ -n "$l" ]; do case "$l" in "$2="*) _UI_V="${l#"$2"=}" ;; esac; done <"$1"
}
# style_palette: sets PALETTE. LLM_PALETTE, then the tool's setting, then default. A value that
# is no palette's name is passed over, so the next one decides.
style_palette() {
  PALETTE="${LLM_PALETTE:-}"
  case "$PALETTE" in default | colorblind) return 0 ;; esac
  _ui_read "$STYLE_PALETTE_FILE" palette
  PALETTE="$_UI_V"
  case "$PALETTE" in colorblind) ;; *) PALETTE=default ;; esac
}
# style_theme: sets THEME (auto, dark or light) and UI_DARK (yes or no). LLM_THEME, then the
# tool's setting, then auto. auto reads COLORFGBG where the terminal sets it, and is dark otherwise.
style_theme() {
  THEME="${LLM_THEME:-}"
  case "$THEME" in auto | dark | light) ;; *)
    _ui_read "$STYLE_THEME_FILE" theme
    THEME="$_UI_V"
    ;;
  esac
  case "$THEME" in dark | light) ;; *) THEME=auto ;; esac
  UI_DARK=yes
  case "$THEME" in
    light) UI_DARK=no ;;
    auto) case "${COLORFGBG:-}" in *";7" | *";9" | *";1"[0-5]) UI_DARK=no ;; esac ;;
  esac
}
# _ui_roles: the 24-bit colour of each role, by palette and theme: ok, warn, error, typed, muted,
# the four stage accents, the ink on a label, and a card's ground and text.
_ui_roles() {
  case "$PALETTE.$UI_DARK" in
    default.yes) set -- 80,220,140 255,200,60 255,95,95 90,210,255 140,145,160 110,150,255 230,110,255 80,220,140 255,110,170 20,20,30 32,34,46 220,222,235 ;;
    default.no) set -- 0,135,60 170,110,0 200,40,40 0,115,175 105,110,125 50,90,220 160,60,200 0,135,60 200,50,120 255,255,255 234,236,242 30,32,40 ;;
    colorblind.yes) set -- 86,140,255 230,159,0 225,120,200 120,220,230 140,145,160 86,180,233 230,159,0 0,158,115 204,121,167 20,20,30 32,34,46 220,222,235 ;;
    *) set -- 0,114,178 190,120,0 170,60,130 0,130,140 105,110,125 0,114,178 213,94,0 0,158,115 204,121,167 255,255,255 234,236,242 30,32,40 ;;
  esac
  _R_OK=$1 _R_WARN=$2 _R_ERR=$3 _R_TYPED=$4 _R_MUTED=$5 _R_A1=$6 _R_A2=$7 _R_A3=$8 _R_A4=$9 _R_INK=${10} _R_CARD=${11} _R_CARDFG=${12}
  # The nearest of the terminal's 16 colours, for a terminal that doesn't say it has more.
  case "$PALETTE" in
    colorblind) set -- 34 33 35 36 34 33 36 35 ;;
    *) set -- 32 33 31 36 34 35 32 36 ;;
  esac
  _C_OK=$1 _C_WARN=$2 _C_ERR=$3 _C_TYPED=$4 _C_A1=$5 _C_A2=$6 _C_A3=$7 _C_A4=$8
}
# _ui_fg <var> <r,g,b> <code>: a role's colour as a code: 24-bit, or one of the 16.
_ui_fg() {
  if [ "$UI_TRUE" = yes ]; then printf -v "$1" '\033[38;2;%sm' "${2//,/;}"; else printf -v "$1" '\033[%sm' "$3"; fi
}
# _ui_pill <var> <r,g,b> <code>: a label's ground in a role's colour, with ink that reads on it.
_ui_pill() {
  if [ "$UI_TRUE" = yes ]; then
    printf -v "$1" '\033[1m\033[48;2;%sm\033[38;2;%sm' "${2//,/;}" "${_R_INK//,/;}"
  else
    case "$3" in 32 | 33 | 36 | 37) printf -v "$1" '\033[1m\033[%sm\033[30m' "$(($3 + 10))" ;; *) printf -v "$1" '\033[1m\033[%sm\033[97m' "$(($3 + 10))" ;; esac
  fi
}
# style_set: every code, for the palette, theme and colours in force. Empty when style is off.
style_set() {
  S_BOLD="" S_DIM="" S_OFF="" S_OK="" S_WARN="" S_ERR="" S_TYPED="" M_OK="" M_WARN=""
  S_GREEN="" S_YELLOW="" S_CYAN="" # version 2's names for ok, warn and typed
  _P_A1="" _P_A2="" _P_A3="" _P_A4="" _P_WARN="" _P_ERR="" _P_TYPED="" _P_MUTED="" _U_CARD="" _U_A1="" _U_A2="" _U_A3="" _U_A4=""
  style_palette
  style_theme
  UI_TRUE=no
  case "${COLORTERM:-}" in truecolor | 24bit) UI_TRUE=yes ;; esac
  if style_utf8; then
    _G_OK="✓" _G_ERR="✗" _G_RAIL="│" _G_DOT="●" _G_TURN="◆" _G_BUL="•" _G_SEP=" · " _G_PROMPT="›" _G_ARROW="→"
  else
    _G_OK="+" _G_ERR="x" _G_RAIL="|" _G_DOT="*" _G_TURN="*" _G_BUL="-" _G_SEP=" - " _G_PROMPT=">" _G_ARROW="->"
  fi
  _ui_roles
  # Standard error is styled on its own terms, so its codes are made whatever standard output is.
  _ui_fg _E_ERR "$_R_ERR" "$_C_ERR"
  _ui_fg _E_WARN "$_R_WARN" "$_C_WARN"
  _ui_fg _E_TYPED "$_R_TYPED" "$_C_TYPED"
  [ "$STYLE" = yes ] || return 0
  S_BOLD=$'\033[1m' S_OFF=$'\033[0m'
  _ui_fg S_OK "$_R_OK" "$_C_OK"
  _ui_fg S_WARN "$_R_WARN" "$_C_WARN"
  _ui_fg S_ERR "$_R_ERR" "$_C_ERR"
  _ui_fg S_TYPED "$_R_TYPED" "$_C_TYPED"
  _ui_fg S_DIM "$_R_MUTED" 2
  _ui_fg _U_A1 "$_R_A1" "$_C_A1"
  _ui_fg _U_A2 "$_R_A2" "$_C_A2"
  _ui_fg _U_A3 "$_R_A3" "$_C_A3"
  _ui_fg _U_A4 "$_R_A4" "$_C_A4"
  _ui_pill _P_A1 "$_R_A1" "$_C_A1"
  _ui_pill _P_A2 "$_R_A2" "$_C_A2"
  _ui_pill _P_A3 "$_R_A3" "$_C_A3"
  _ui_pill _P_A4 "$_R_A4" "$_C_A4"
  _ui_pill _P_WARN "$_R_WARN" "$_C_WARN"
  _ui_pill _P_ERR "$_R_ERR" "$_C_ERR"
  _ui_pill _P_TYPED "$_R_TYPED" "$_C_TYPED"
  _ui_pill _P_MUTED "$_R_MUTED" 90
  if [ "$UI_TRUE" = yes ]; then
    printf -v _U_CARD '\033[48;2;%sm\033[38;2;%sm' "${_R_CARD//,/;}" "${_R_CARDFG//,/;}"
  elif [ "$UI_DARK" = yes ]; then
    _U_CARD=$'\033[100m\033[97m'
  else
    _U_CARD=$'\033[47m\033[30m'
  fi
  # shellcheck disable=SC2034 # read by commands still on version 2's names
  S_GREEN="$S_OK" S_YELLOW="$S_WARN" S_CYAN="$S_TYPED"
  M_OK="${S_OK}${_G_OK}${S_OFF} "
  M_WARN="${S_BOLD}${S_WARN}!${S_OFF} "
}
STYLE=no STYLE_ERR=no
# _UI_LIVE: whether a wait may draw at a terminal with style off. style_off says no: an agent's
# shell can be a pseudo-terminal, and it reads every byte.
_UI_LIVE=yes
if style_wanted 1; then STYLE=yes; fi
if style_wanted 2; then STYLE_ERR=yes; fi
_UI_RAIL=no _UI_ACC=0
style_set
# style_off: for a command whose output an agent or a program reads. Nothing is styled, errors included.
style_off() {
  STYLE=no STYLE_ERR=no _UI_LIVE=no
  style_set
}
# UI_TRACE names a file each piece appends its name to, so the gallery can tell a command on the
# kit from one on the old look. Unset, it costs one test.
_ui_t() { [ -z "${UI_TRACE:-}" ] || printf '%s\n' "$1" >>"$UI_TRACE"; }
# _ui_rail: what goes in front of a line under a stage: the rail at a terminal, spaces otherwise.
_ui_rail() {
  _UI_PRE=""
  [ "$_UI_RAIL" = yes ] || return 0
  if [ "$STYLE" = yes ]; then _UI_PRE="$S_DIM$_G_RAIL$S_OFF   "; else _UI_PRE="    "; fi
}
# _ui_width: sets _UI_W, the width of a card: the terminal's, from 40 to 88 columns.
_ui_width() {
  local c="${COLUMNS:-}"
  case "$c" in '' | *[!0-9]*) c="$(tput cols 2>/dev/null || true)" ;; esac
  case "$c" in '' | *[!0-9]*) c=80 ;; esac
  [ "$c" -le 88 ] || c=88
  [ "$c" -ge 40 ] || c=40
  _UI_W=$c
}

# ---- the pieces ----------------------------------------------------------------------------

# ui_question <question> [<detail>...]: a question to answer at the keyboard. A yellow ? label,
# the question in bold, then each detail indented; a detail that starts "- " is a bullet. Then
# ui_keys for the answers.
ui_question() {
  local d
  _ui_t ui_question
  if [ "$STYLE" = yes ]; then
    printf '%s ? %s %s%s%s%s\n' "$_P_WARN" "$S_OFF" "$S_BOLD" "$S_WARN" "$1" "$S_OFF"
  else
    printf '? %s\n' "$1"
  fi
  shift
  for d in "$@"; do
    case "$d" in
      "- "*) if [ "$STYLE" = yes ]; then printf '   %s%s%s %s\n' "$S_WARN" "$_G_BUL" "$S_OFF" "${d#- }"; else printf '   %s\n' "$d"; fi ;;
      *) printf '   %s\n' "$d" ;;
    esac
  done
  echo
}
# ui_keys <word>...: the answers a question takes, then the prompt, with no line end. Each
# word's first letter is its key, so yes gives [y]es; key=words names another, as Enter=finish
# gives [Enter] finish. [y] takes the ok colour, [n] the error colour, any other key typed's.
ui_keys() {
  local w k rest c out="   "
  _ui_t ui_keys
  for w in "$@"; do
    case "$w" in
      *=*) k="${w%%=*}" rest=" ${w#*=}" ;;
      *) rest="${w#?}" k="${w%"$rest"}" ;;
    esac
    case "$k" in y) c="$S_OK" ;; n) c="$S_ERR" ;; *) c="$S_TYPED" ;; esac
    out="$out$S_BOLD${c}[$k]$S_OFF$rest  "
  done
  printf '%s%s%s%s ' "$out" "$S_BOLD$S_WARN" "$_G_PROMPT" "$S_OFF"
}
# ui_prompt <question> [<default>]: a question answered by typing a line: the question, the
# default in brackets, and the prompt, with no line end, on the rail under a stage. The caller
# reads the line.
ui_prompt() {
  _ui_t ui_prompt
  _ui_rail
  printf '%s%s%s%s%s %s%s%s ' "$_UI_PRE" "$S_BOLD" "$1" "$S_OFF" "${2:+ [$2]}" "$S_BOLD$S_WARN" "$_G_PROMPT" "$S_OFF"
}
# ui_stage [--ok|--warn|--error] <LABEL> <summary> [<more>...]: a step of the command's work, as
# a dot on a rail with a coloured label, then one line: the summary, and the rest muted, joined
# by " · ". Each stage takes the next accent; --error takes the error colour, and --ok and --warn
# colour the summary. Items and details after it sit on its rail.
ui_stage() {
  local state="" label first rest="" p dot pill lead
  case "${1:-}" in --ok | --warn | --error) state="${1#--}" && shift ;; esac
  label="$1" first="${2:-}"
  shift
  [ $# -eq 0 ] || shift
  for p in "$@"; do rest="$rest$_G_SEP$p"; done
  _ui_t ui_stage
  if [ "$STYLE" != yes ]; then
    [ "$_UI_RAIL" != yes ] || echo
    _UI_RAIL=yes
    printf '%s  %s%s\n' "$label" "$first" "$rest"
    return 0
  fi
  [ "$_UI_RAIL" != yes ] || printf '%s%s%s\n' "$S_DIM" "$_G_RAIL" "$S_OFF"
  _UI_RAIL=yes
  if [ "$state" = error ]; then
    dot="$S_ERR" pill="$_P_ERR"
  else
    _UI_ACC=$((_UI_ACC % 4 + 1))
    case "$_UI_ACC" in 1) dot="$_U_A1" pill="$_P_A1" ;; 2) dot="$_U_A2" pill="$_P_A2" ;; 3) dot="$_U_A3" pill="$_P_A3" ;; *) dot="$_U_A4" pill="$_P_A4" ;; esac
  fi
  case "$state" in ok) lead="$S_BOLD$S_OK" ;; warn) lead="$S_BOLD$S_WARN" ;; error) lead="$S_BOLD$S_ERR" ;; *) lead="$S_BOLD" ;; esac
  printf '%s%s%s %s %s %s  %s%s%s%s\n' "$dot" "$_G_DOT" "$S_OFF" "$pill" "$label" "$S_OFF" "$lead" "$first" "$S_OFF" "${rest:+$S_DIM$rest$S_OFF}"
}
# ui_item ok|warn|error <text> [<aside>]: one thing that was done, with its mark: ✓ ! or ✗. The
# aside, such as a time, is muted and right-aligned in a column. Plain, the mark is "- ".
ui_item() {
  local kind="$1" text="$2" aside="${3:-}" m c n pad=""
  _ui_t ui_item
  case "$kind" in
    ok) m="$_G_OK" c="$S_OK" ;;
    warn) m="!" c="$S_BOLD$S_WARN" ;;
    error) m="$_G_ERR" c="$S_BOLD$S_ERR" ;;
    *) m="-" c="" ;;
  esac
  [ "$STYLE" = yes ] || m="-"
  _ui_rail
  if [ -n "$aside" ]; then
    n=$((32 - ${#text}))
    [ "$n" -ge 1 ] || n=1
    printf -v pad '%*s%5s' "$n" "" "$aside"
    pad="$S_DIM$pad$S_OFF"
  fi
  printf '%s%s%s%s %s%s\n' "$_UI_PRE" "$c" "$m" "$S_OFF" "$text" "$pad"
}
# ui_detail <part>...: a line of facts under a stage or an item, its parts joined by a muted " · ".
ui_detail() {
  local p out=""
  _ui_t ui_detail
  for p in "$@"; do
    if [ -z "$out" ]; then out="$p"; else out="$out$S_DIM$_G_SEP$S_OFF$p"; fi
  done
  _ui_rail
  printf '%s  %s\n' "${_UI_PRE:-}" "$out"
}
# ui_table [--no-head]: a table, read from standard input with its columns already lined up. A
# table stays a table: the first line is its header, in bold, unless --no-head, and a note at the
# end of a row, from "  <- " on, takes the warn colour. Plain, it is printed as it is.
ui_table() {
  local l head=yes
  [ "${1:-}" != --no-head ] || head=no
  _ui_t ui_table
  while IFS= read -r l || [ -n "$l" ]; do
    if [ "$STYLE" != yes ]; then
      printf '%s\n' "$l"
    elif [ "$head" = yes ]; then
      printf '%s%s%s\n' "$S_BOLD" "$l" "$S_OFF"
      head=no
    else
      case "$l" in
        *"  <- "*) printf '%s%s  <- %s%s\n' "${l%%  <- *}" "$S_WARN" "${l#*  <- }" "$S_OFF" ;;
        *) printf '%s\n' "$l" ;;
      esac
    fi
  done
}
# _ui_card_line <text> <inner>: one line of a card, padded to the card's width.
_ui_card_line() {
  local n=$(($2 - ${#1}))
  [ "$n" -ge 0 ] || n=0
  printf '%s  %s%*s  %s\n' "$_U_CARD" "$1" "$n" "" "$S_OFF"
}
# ui_card <text>: text for the user to paste somewhere, on a tinted card as wide as the terminal
# (up to 88). It wraps at spaces only, so a URL or a path is never split: a word longer than a
# line runs past the edge. Each line of the text starts a line; one that starts "- " wraps under
# its words. Plain, the text is printed as it is.
ui_card() {
  local inner line ind body hang word cur
  local -a ws
  _ui_t ui_card
  if [ "$STYLE" != yes ]; then
    printf '%s\n' "$1"
    return 0
  fi
  _ui_width
  inner=$((_UI_W - 4))
  printf '%s%*s%s\n' "$_U_CARD" "$_UI_W" "" "$S_OFF"
  while IFS= read -r line || [ -n "$line" ]; do
    ind="${line%%[! ]*}"
    body="${line#"$ind"}"
    hang="$ind"
    case "$body" in "- "*) hang="$ind  " ;; esac
    cur=""
    if [ -n "$body" ]; then
      IFS=' ' read -r -a ws <<<"$body"
      for word in "${ws[@]}"; do
        if [ -z "$cur" ]; then
          cur="$ind$word"
        elif [ $((${#cur} + 1 + ${#word})) -le "$inner" ]; then
          cur="$cur $word"
        else
          _ui_card_line "$cur" "$inner"
          cur="$hang$word"
        fi
      done
    fi
    _ui_card_line "$cur" "$inner"
  done <<EOF
$1
EOF
  printf '%s%*s%s\n' "$_U_CARD" "$_UI_W" "" "$S_OFF"
}
# ui_turn: the end of the rail, and the start of what the user does now: ◆ YOUR TURN.
ui_turn() {
  _ui_t ui_turn
  if [ "$STYLE" = yes ]; then
    [ "$_UI_RAIL" != yes ] || printf '%s%s%s\n' "$S_DIM" "$_G_RAIL" "$S_OFF"
    printf '%s%s%s %sYOUR TURN%s\n\n' "$S_WARN" "$_G_TURN" "$S_OFF" "$S_BOLD$S_WARN" "$S_OFF"
  else
    printf '\nYOUR TURN\n\n'
  fi
  _UI_RAIL=no
}
# ui_step [--optional] [--done] [--emoji <emoji>] <n> <title> [<aside>]: a numbered step of the
# user's turn. --optional greys its number; --done gives the aside the ok colour, for what the
# tool already did, such as filling the clipboard. The emoji, the one place one is allowed, goes
# before the aside, at a UTF-8 terminal only.
ui_step() {
  local optional=no done=no emoji="" pill ac
  while :; do
    case "${1:-}" in
      --optional) optional=yes && shift ;;
      --done) done=yes && shift ;;
      --emoji) emoji="$2" && shift 2 ;;
      *) break ;;
    esac
  done
  _ui_t ui_step
  if [ "$STYLE" != yes ]; then
    printf '  %s  %s%s\n\n' "$1" "$2" "${3:+  $3}"
    return 0
  fi
  pill="$_P_TYPED"
  [ "$optional" = no ] || pill="$_P_MUTED"
  ac="$S_DIM"
  [ "$done" = no ] || ac="$S_OK"
  style_utf8 || emoji=""
  printf '  %s %s %s  %s%s%s' "$pill" "$1" "$S_OFF" "$S_BOLD" "$2" "$S_OFF"
  [ -z "${3:-}" ] || printf '  %s%s%s%s' "$ac" "${emoji:+$emoji }" "$3" "$S_OFF"
  printf '\n\n'
}
# ui_next <words>: the one thing to do next, as the command's last line: Next: and the step.
ui_next() {
  _ui_t ui_next
  [ "$_UI_RAIL" != yes ] || echo
  _UI_RAIL=no
  printf '%sNext:%s %s\n' "$S_BOLD$S_TYPED" "$S_OFF" "$*"
}
# typed <words>: something the user can type, inside a line. typed_err for a line on standard error.
typed() {
  _ui_t ui_typed
  printf '%s%s%s' "$S_TYPED" "$*" "$S_OFF"
}
typed_err() {
  if [ "$STYLE_ERR" = yes ]; then printf '%s%s\033[0m' "$_E_TYPED" "$*"; else printf '%s' "$*"; fi
}
# _ui_live: whether a wait draws. With style on, it does. With style off, only at a terminal, as
# plain words, so a long wait never looks like a hang; in a pipe or a file, and after style_off,
# never.
_ui_live() {
  [ "$STYLE" = yes ] && return 0
  [ "$_UI_LIVE" = yes ] && [ -t 1 ]
}
# ui_wait <tick> <what> [<aside>]: draws the one line a wait keeps up to date, once, with the
# spinner's frame for the tick. For a loop that redraws it itself. ui_wait_clear takes it away.
ui_wait() {
  local f
  _ui_live || return 0
  if style_utf8; then
    case $(($1 % 4)) in 0) f="⠋" ;; 1) f="⠙" ;; 2) f="⠸" ;; *) f="⠴" ;; esac
  else
    case $(($1 % 4)) in 0) f="|" ;; 1) f="/" ;; 2) f="-" ;; *) f="\\" ;; esac
  fi
  printf '\r\033[K%s%s%s %s  %s%s%s' "$S_TYPED" "$f" "$S_OFF" "$2" "$S_DIM" "${3:-}" "$S_OFF"
}
ui_wait_clear() { _ui_live || return 0; printf '\r\033[K'; }
# ui_wait_start <what> [<aside>]: a wait for something that runs in the foreground, such as a
# check: the same line, with a spinner that turns and a clock, redrawn by a ticker in the
# background five times a second. ui_wait_stop ends it and takes the line away. The ticker stops
# by itself if the tool exits first.
ui_wait_start() {
  local what="$1" aside="${2:-}" parent=$$ start=$SECONDS i=0
  _ui_t ui_wait
  _UI_WAIT_PID=""
  _ui_live || return 0
  (
    trap 'exit 0' TERM
    while kill -0 "$parent" 2>/dev/null; do
      ui_wait "$i" "$what" "$((SECONDS - start))s${aside:+$_G_SEP$aside}"
      i=$((i + 1))
      sleep 0.2
    done
  ) &
  _UI_WAIT_PID=$!
}
ui_wait_stop() {
  [ -n "${_UI_WAIT_PID:-}" ] || return 0
  kill "$_UI_WAIT_PID" 2>/dev/null || true
  wait "$_UI_WAIT_PID" 2>/dev/null || true
  _UI_WAIT_PID=""
  ui_wait_clear
}
# _ui_error <words>: error: and the words, on standard error, styled as standard error is.
_ui_error() {
  _ui_t ui_error
  if [ "$STYLE_ERR" = yes ]; then printf '%serror:\033[0m %s\n' "$_E_ERR" "$1" >&2; else printf 'error: %s\n' "$1" >&2; fi
}
# die <words>: the tool tried and failed. Exits 1.
die() {
  _ui_error "$*"
  exit 1
}
# die_usage <words>: the tool was called wrongly: an unknown command or option, a missing argument. Exits 2.
die_usage() {
  _ui_error "$*"
  exit 2
}
# say_warn_err <words>: a warning on standard error, styled as standard error is, whatever standard output is.
say_warn_err() {
  _ui_t ui_error
  if [ "$STYLE_ERR" = yes ]; then printf '\033[1m%s!\033[0m %s\n' "$_E_WARN" "$*" >&2; else printf '%s\n' "$*" >&2; fi
}

# ---- version 2's pieces, until every command has moved -------------------------------------
# The old look: a mark in front of a line, a bold heading, a dim aside. The gallery lists the
# commands that still use them, and the lint fails on them once it is switched on.
say_ok() { _ui_t v2; printf '%s%s\n' "$M_OK" "$*"; }
say_warn() { _ui_t v2; printf '%s%s\n' "$M_WARN" "$*"; }
say_head() { _ui_t v2; printf '%s%s%s\n' "$S_BOLD" "$*" "$S_OFF"; }
say_dim() { _ui_t v2; printf '%s%s%s\n' "$S_DIM" "$*" "$S_OFF"; }
say_next() { _ui_t v2; printf '%sNext:%s %s\n' "$S_BOLD$S_TYPED" "$S_OFF" "$*"; }

# ---- for tests --------------------------------------------------------------------------------
# ui_words: the words of what a command printed, one a line, so a terminal's output can be held
# to its plain output. Codes go; so does every token made only of glyphs (│ ● ◆ · › and the
# marks), and a "-", "+", "!", ">", "|" or "*" standing alone: the plain marks, and the glyphs
# where the locale isn't UTF-8.
ui_words() {
  LC_ALL=C sed -e "s/$(printf '\033')\\[[0-9;]*[mK]//g" -e "s/$(printf '\r')//g" | LC_ALL=C tr -s ' \t' '\n\n' |
    LC_ALL=C grep -v -x -e '[^[:print:]]*' -e '-' -e '+' -e '!' -e '>' -e '|' -e '\*' || true
}

# _ui_demo: every piece, in the look of the terminal it runs in, then the settings in force, on
# standard error. bash ui.sh
_ui_demo() {
  ui_question "Run this branch's code on your Mac?" "!20 at c5f91b7 by a teammate$_G_SEP${S_DIM}git hooks off$S_OFF" "- go build, vet, test and mod tidy" "- pre-commit, on the 10 changed files"
  ui_keys yes no
  echo y
  echo
  ui_stage --ok CHECKS "5 passed" "0 failed" "64s"
  ui_item ok "go build" 17s
  ui_item ok "go vet" 6s
  ui_item warn "go test, 1 skipped" 8s
  ui_item error "pre-commit, 10 files" 31s
  ui_stage PACKED "camera-events !20" "3.5 MB"
  ui_detail "$(typed feature/clip-people) $_G_ARROW master" "@ c5f91b7"
  ui_detail "13 Go modules" "your earlier review" "check logs"
  ui_stage SENT "OneDrive" "Documents/Cowork/relay/mrs/camera-events-20"
  ui_turn
  ui_step --done --emoji "📋" 1 "Paste into Copilot Cowork" "already on your clipboard"
  ui_card "Use remote-pair-run to review this merge request, following its section on merge requests. With no attachment, read these notes from my OneDrive:
- Documents/Cowork/relay/mrs/camera-events-20.txt
A link is never split: https://gitlab.com/example/group/platform/camera-detection-event-aggregator/-/merge_requests/20"
  echo
  ui_step --optional 2 "Ask Slackbot" "then paste its answer into Copilot Cowork"
  ui_next "back in Copilot Cowork, reply $(typed "done")"
  echo
  echo "palette $PALETTE, theme $THEME ($([ "$UI_DARK" = yes ] && echo dark || echo light)), $([ "$UI_TRUE" = yes ] && echo 24-bit || echo 16) colours" >&2
}
if [ "${BASH_SOURCE[0]:-}" = "$0" ]; then _ui_demo; fi
