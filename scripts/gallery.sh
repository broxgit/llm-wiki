#!/usr/bin/env bash
# gallery.sh: what every command a person reads prints at a terminal, kept as golden files, so a
# change to the look shows up in review and a command still on the old look stands out.
#
#   scripts/gallery.sh            render every command into tests/gallery/ and write its index
#   scripts/gallery.sh --check    render into a temp folder and fail on any difference
#
# Each command runs against fakes in a temp folder with its own HOME, at a UTF-8 terminal's
# settings with the 16 colours, 80 columns wide. Temp paths, dates and times, the handbook's
# version and the helper's release and platform are replaced by placeholders, so a file changes
# only when what the command prints does.
# ui.sh is drawn too, in each depth and theme. The index, tests/gallery/README.md, says which of
# the kit's pieces each command used: "kit" when it prints through them alone, "old look" when it
# uses version 2's helpers or codes of its own, "unstyled" when a person reads it and nothing in
# it is styled. Every command a person reads is to end up "kit". docs/conventions.md has the rules.
# Works with the bash that ships on macOS (3.2) and on Linux.
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
W="$REPO/wiki.sh"
OUT="$REPO/tests/gallery"
check=no
case "${1:-}" in
  "") ;;
  --check) check=yes ;;
  -h | --help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//' && exit 0 ;;
  *) printf 'error: no option %s. Run: scripts/gallery.sh --help\n' "$1" >&2 && exit 2 ;;
esac
T="$(mktemp -d)"
T="$(cd "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT
DEST="$OUT"
[ "$check" = no ] || DEST="$T/gallery"
rm -rf "$DEST.new" && mkdir -p "$DEST.new"

# The fakes: a collection with a project wiki that has notes waiting, and the shared wiki.
export HOME="$T/home" WIKIS_DIR="$T/wikis" TZ=UTC LANG=en_US.UTF-8 TERM=xterm COLUMNS=80
export LLM_WIKI_CMD=wiki LLM_WIKI_NO_GO=1 LLM_WIKI_NEWS_FILE="$T/NEWS.md" LLM_WIKI_HELPER_BASE="file://$T/release"
unset XDG_CONFIG_HOME XDG_STATE_HOME XDG_DATA_HOME XDG_CACHE_HOME LC_ALL LC_CTYPE COLORTERM COLORFGBG LLM_PALETTE LLM_THEME NO_COLOR CLAUDE_PLUGIN_ROOT
PATH="/usr/bin:/bin"
mkdir -p "$HOME"
cd "$T" || exit 1
printf '[user]\n\tname = Gallery\n\temail = gallery@example.test\n[init]\n\tdefaultBranch = main\n' >"$HOME/.gitconfig"
printf '# News\n\n## 2026-01-02: An entry\n\n- Something you would notice.\n- Do: run `wiki status`.\n' >"$LLM_WIKI_NEWS_FILE"
LLM_WIKI_STYLE=off "$W" new "$WIKIS_DIR/global" >/dev/null 2>&1
LLM_WIKI_STYLE=off "$W" new "$WIKIS_DIR/demo" >/dev/null 2>&1
for i in 1 2 3; do printf 'Captured: 2026-01-0%s\n\nnote %s\n' "$i" "$i" >"$WIKIS_DIR/demo/raw/2026-01-0$i-000000-n$i.md"; done
printf '# Open\n\n## Review of the parser\n- kind: waiting\n- who: a teammate\n- status: open\n- from: 2026-01-05 raw/2026-01-01-000000-n1.md\n' >"$WIKIS_DIR/demo/open.md"
LLM_WIKI_STYLE=off "$W" news >/dev/null 2>&1
TV="$(sed -n 's/^Handbook version \([0-9][0-9]*\).*/\1/p' "$REPO/template/AGENTS.md" | head -n 1)"

# normalize: the parts of a run that change from one run to the next.
normalize() {
  LC_ALL=C sed -E -e "s#$T#<tmp>#g" -e "s#$REPO#<repo>#g" -e "s#$HOME#<home>#g" \
    -e 's/[0-9]{4}-[0-9]{2}-[0-9]{2}/YYYY-MM-DD/g' -e 's/[0-9]{2}:[0-9]{2}(:[0-9]{2})?/HH:MM/g' \
    -e "s/(v|version )$TV([^0-9]|\$)/\1<handbook>\2/g" \
    -e 's/release [0-9a-f]{12}, protocol [0-9]+, for [a-z0-9]+-[a-z0-9_]+/release <release>, protocol <n>, for <platform>/g'
}
# look <trace> <output>: from the pieces the run called. kit: the kit's pieces and nothing else.
# old look: version 2's helpers, or codes of its own. mixed: both. unstyled: nothing at all,
# though a person reads it. typed and an error alone don't make a command's look.
look() {
  local kit=no v2=no
  grep -qv -e '^ui_typed$' -e '^ui_error$' -e '^v2$' "$1" 2>/dev/null && kit=yes
  grep -q '^v2$' "$1" 2>/dev/null && v2=yes
  if [ "$kit" = yes ] && [ "$v2" = yes ]; then echo mixed
  elif [ "$kit" = yes ]; then echo kit
  elif [ "$v2" = yes ] || grep -q "$(printf '\033')" "$2"; then echo "old look"
  else echo unstyled; fi
}
INDEX="$T/index"
: >"$INDEX"
# render <name> <stdin> <args...>: run one command and keep what it printed, and its look.
render() {
  local name="$1" input="$2" tr="$T/trace" pieces
  shift 2
  : >"$tr"
  printf '%b' "$input" | UI_TRACE="$tr" LLM_WIKI_STYLE=on LLM_WIKI_TEST_TTY=1 "$W" "$@" 2>&1 | normalize >"$DEST.new/wiki-$name.txt"
  pieces="$(grep '^ui_' "$tr" | sort -u | sed 's/^ui_//' | paste -sd ' ' -)"
  printf '%s\t%s\t%s\t%s\n' "wiki $*" "$(look "$tr" "$DEST.new/wiki-$name.txt")" "${pieces:--}" "wiki-$name.txt" >>"$INDEX"
}

# Every command a person reads. Those an agent or a program reads are plain by design, and are
# listed below the table, not rendered. Answers to questions come from the second field.
render usage "" --help
render status "" status
render open "" open
render pages "" pages demo
render news "" news --all
render setup-list "" setup --list
render setup-feedback 'notes\n' setup feedback
render setup-delegation '\n\n' setup delegation
render delegation "" delegation
render feedback "" feedback
render helper "" helper
render extensions "" extensions
render skills "" skills
render tips "" tips
render list "" list
render collections "" collections
render deps "" deps --all
render workflows "" workflows
render stale "" stale 30
render upgrade "" upgrade demo
render unlock "" unlock demo
render claude "" claude --print
render update "" update --wikis-only
render relay "" relay

# The kit itself, in each depth and theme, and plain.
kit() {
  local name="$1"
  shift
  env "$@" STYLE_OVERRIDE=on bash "$REPO/ui.sh" 2>&1 | normalize >"$DEST.new/kit-$name.txt"
}
kit 16-dark LLM_THEME=dark
kit 16-light LLM_THEME=light
kit 24-dark COLORTERM=truecolor LLM_THEME=dark
kit 24-light COLORTERM=truecolor LLM_THEME=light
kit 24-colorblind COLORTERM=truecolor LLM_THEME=dark LLM_PALETTE=colorblind
env STYLE_OVERRIDE=off bash "$REPO/ui.sh" 2>&1 | normalize >"$DEST.new/kit-plain.txt"

{
  echo "# Gallery"
  echo
  echo "What each command a person reads prints at a terminal, made by \`scripts/gallery.sh\`. Don't edit these files: run it again. \`cat\` a file at a terminal to see the look. \`kit-*.txt\` are \`ui.sh\`'s own pieces, in each depth and theme."
  echo
  echo "| Command | Look | Pieces | File |"
  echo "|---|---|---|---|"
  awk -F '\t' '{ printf "| `%s` | %s | %s | [%s](%s) |\n", $1, $2, $3, $4, $4 }' "$INDEX"
  echo
  echo "Plain by design, since an agent or a program reads them: \`start\`, \`capture\`, \`sync\`, \`find\`, \`which\`, \`pending\`, \`patterns\`, \`lint\`, \`index\`, \`log\`, \`lock\`, \`compile\`, \`mcp\`, \`journal\`, \`standup\`, \`tour\`, \`report\`, \`stats\`, \`completion\`, and every command that begins \`__\`."
} >"$DEST.new/README.md"

if [ "$check" = yes ]; then
  if diff -r "$OUT" "$DEST.new" >"$T/diff" 2>&1; then
    echo "gallery: every command prints what its file in tests/gallery has."
    exit 0
  fi
  echo "gallery: what these commands print has changed. Look at the difference, then run: scripts/gallery.sh"
  grep -E '^(diff|Only in)' "$T/diff" | sed -e "s#$T/gallery.new#new#g" -e "s#$REPO/##g"
  exit 1
fi
rm -rf "$OUT"
mv "$DEST.new" "$OUT"
old="$(awk -F '\t' '$2 != "kit" { n++ } END { print n + 0 }' "$INDEX")"
echo "gallery: $(wc -l <"$INDEX" | tr -d ' ') commands in tests/gallery/, $old of them not yet on the kit."
