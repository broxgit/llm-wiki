Conventions version 4. llm-wiki keeps the original. llm-relay holds a copy: change it here first, then change the copy in the same sitting.

# Conventions for commands

How the llm tools (llm-wiki, llm-relay, and any tool that joins them) talk to a person and to a program. Read it before you change what a command prints. It takes three minutes.

Every command looks the same way: a timeline. A question at the top when there is one, then the work as stages on a rail, then what the user does now. The look lives in one file, `ui.sh`, the kit, and commands print through its pieces. No command writes a colour code.

## When style is on

Colour and marks are on only when standard output is a terminal, `NO_COLOR` is unset, `TERM` isn't `dumb`, and the command isn't one an agent reads (below). An error's style is decided the same way, by standard error.

`LLM_WIKI_STYLE=on` or `off` overrides all of it, for a pager (`less -R`) and for tests. `on` wins over `NO_COLOR`: it is a request made for this one tool, and `NO_COLOR` is a standing preference for every tool. Each tool names its own variable: `LLM_RELAY_STYLE` in llm-relay.

Agents' shells can be pseudo-terminals, where "is a terminal" is true. So a command whose output an agent or a program reads calls `style_off` and stays plain whatever the terminal says, even with the variable set to `on`. In llm-wiki those are `start`, `capture`, `sync`, `find`, `which`, `pending`, `patterns`, `lint`, `index`, `log`, `lock`, `compile`, `mcp`, `journal`, `standup`, `tour`, `report`, `stats`, every command that begins `__`, and everything a hook or an extension event runs.

A tool whose every command may be run by an assistant, as llm-relay's can, has a second way to apply the same rule: it calls `style_off` whenever standard input isn't a terminal, whatever the variable says.

The compiled helper in `cmd/` and `internal/` always prints plain text, and knows nothing of the kit. Where a ported command's output has parts that a person sees, the helper already hands them to `wiki.sh` as tagged lines (the `row` and `todo` lines of `status`), and `wiki.sh` prints each through a piece. A new port does the same: tag what each line is, never style it, and never add a tag for looks alone.

## The pieces

A command is made of these, in this order. Each is a function in `ui.sh`.

| Piece | Call | At a terminal | Plain |
|---|---|---|---|
| question | `ui_question "<question>" "<detail>"...`, then `ui_keys yes no` | a yellow `?` label, the question in bold, the details indented, a detail that starts `- ` as a bullet. Then the answers: `[y]es` in the ok colour, `[n]o` in the error colour, any other key in typed's, and a `›` prompt | `? <question>`, the details, `[y]es  [n]o  ›` |
| stage | `ui_stage [--ok\|--warn\|--error] LABEL "<summary>" "<more>"...` | a dot on a rail and a label in capitals on a coloured ground, such as CHECKS, PACKED or SENT. Then one line: the summary in bold, the rest muted, joined by ` · `. Each stage takes the next accent. `--error` makes the dot and label the error colour, and `--ok` and `--warn` colour the summary | `LABEL  <summary> · <more>`, a blank line between stages |
| item | `ui_item ok\|warn\|error "<text>" "<aside>"` | on the stage's rail, a `✓` `!` or `✗`, the text, and the aside, such as a time, muted and right-aligned in a column | `- <text>  <aside>`, indented |
| detail | `ui_detail "<part>"...` | a line of facts under a stage or an item, parts joined by a muted ` · ` | the same, indented |
| card | `ui_card "<text>"` | text to paste somewhere, on a tinted card as wide as the terminal (up to 88 columns). It wraps at spaces only, so a URL or a path is never split: a word longer than the line runs past the card's edge | the text as it is |
| your turn | `ui_turn`, then `ui_step [--optional] [--done] [--emoji E] N "<title>" "<aside>"` | the rail ends at `◆ YOUR TURN`. Each step has its number on a label, the title in bold, and an aside: muted, or in the ok colour with `--done`, for what the tool already did. `--optional` greys the number. Emoji are allowed here, in a step's aside, and nowhere else | `YOUR TURN`, then `  N  <title>  <aside>`, no emoji |
| next | `ui_next "<step>"` | `Next:` in bold, in typed's colour, and the one step, as the command's last line | `Next: <step>` |

Three more, for inside a line and for the edges:

- `typed "<words>"`: something the user can type. Nothing else takes typed's colour. `typed_err` for a line on standard error.
- `ui_wait <tick> "<what>" "<aside>"`: one line kept up to date during a wait, with a spinner, at a terminal only. `ui_wait_clear` takes it away.
- `die "<words>"`, `die_usage "<words>"`, `say_warn_err "<words>"`: an error, a usage error, a warning, on standard error, styled as standard error is.

What the pieces look like, with the codes left out, at a terminal:

```
 ?  Run this branch's code on your Mac?
   !20 at c5f91b7 by a teammate · git hooks off
   • go build, vet, test and mod tidy

   [y]es  [n]o  › y

●  CHECKS   5 passed · 0 failed · 64s
│   ✓ go build                          17s
│   ✗ pre-commit, 10 files              31s
│
●  SENT   OneDrive · Documents/Cowork/relay/mrs/camera-events-20
│
◆ YOUR TURN

   1   Paste into Copilot Cowork  📋 already on your clipboard

  Use remote-pair-run to review this merge request, following its section on
  merge requests.

Next: back in Copilot Cowork, reply done
```

`bash ui.sh` draws every piece in the terminal it runs in, with the palette and theme in force.

## The words never change

Style goes around the text and never replaces it. A label is a word, such as CHECKS or YOUR TURN, never only a colour or a glyph, and it is the same word in plain output. A mark is added in front, and takes the place of a list's `- `, but never of a word. A state stays a word too: `5 passed · 0 failed`, not only a tick. Agents and skills are told to expect the words, and people paste them into chats and issues.

So a terminal's output and its plain output have the same words. Strip the codes, drop the glyphs that are only decoration (`│ ● ◆ · ›`, the marks `✓ ! ✗ •`, and a step's emoji), and the words are the plain words, in order, though the spacing and the line breaks differ. `ui_words` does that, and the tests hold each command to it.

## Colours are roles

Code names a role, never a colour. The kit decides the colour of each role from the palette, the theme and what the terminal can show.

| Role | What takes it | `default`, dark | `colorblind`, dark |
|---|---|---|---|
| ok | a `✓`, a summary that went well, `[y]` | green | blue |
| warn | a `!`, the question's label, YOUR TURN | yellow | orange |
| error | a `✗`, `error:`, a stage that failed, `[n]` | red | reddish purple |
| accent | each stage's dot and label, in turn: four of them | blue, magenta, green, pink | Okabe-Ito sky blue, orange, bluish green, reddish purple |
| typed | something the user can type, `Next:`, a step's number | cyan | cyan |
| muted | an aside: a time, a size, a path, the rail. Never the fix, and never anything the reader needs to act | grey | grey |

A card's ground is a tint of the terminal's background, and a label's ink is chosen to read on its ground.

- **Depth.** 24-bit colour where `COLORTERM` is `truecolor` or `24bit`. Anywhere else, the nearest of the terminal's 16 colours: green 32, yellow 33, red 31, cyan 36, dim for muted, and blue, magenta, green and cyan for the accents (blue 34, yellow, magenta 35 and cyan in `colorblind`). No 256-colour codes, and no dependency.
- **Palette.** `default` or `colorblind`, which follows Okabe-Ito in spirit. `LLM_PALETTE` decides, read by every llm tool, then the tool's own setting, `palette` (`wiki setup palette` in llm-wiki), then `default`. Marks and words don't change: they already carry the meaning without colour.
- **Theme.** `auto`, `dark` or `light`, so cards and labels read on a light background too. `LLM_THEME` decides, then the tool's own setting, `theme` (`wiki setup theme`), then `auto`. `auto` reads `COLORFGBG` where the terminal sets it, and is dark otherwise.

A value that isn't one of a setting's names is passed over, so the next one decides. Each tool keeps its settings where it keeps its others, and asks about them in its setup.

## What never gets style

A file, a report, the clipboard, a log, anything an agent or another program reads, and text that came from somewhere else. A card is drawn at a terminal only: what goes on the clipboard is the text as it is. A `NEWS.md` entry is printed as written: its backticks stay backticks, and only the line around it may be bold. Text from elsewhere that is shown at a terminal goes between muted rules, so nothing in it can pass for the tool's own words.

## Layout

A blank line between groups. Marks in front, not words at the end. A column as wide as its longest label. A table row gets no mark, since that would shift the columns. A table stays a table: its header may be bold and a note in it may take a role, but its rows don't become items.

## Beyond style

- **Every problem ends with its fix.** A line that says something is wrong ends with what to do: `Run: <command>` for something to type, `Ask an agent: "<request>"` for something to say, `Do: <steps>` for what a person does by hand. For new messages this is the rule, and a warning with no fix is a bug. Some older errors, such as an unknown option, only say what happened.
- **Errors** go to standard error as `error: <what happened>. <what to do>`. No stack traces for a mistake a person made. A warning that goes to standard error is styled as standard error is, with `say_warn_err`, and a command inside it with `typed_err`: otherwise `2>errors.log` at a terminal puts colour codes in the file.
- **Exit codes.** 0 done. 1 failed: the tool tried and couldn't. 2 called wrongly: an unknown command or option, or an argument that is missing, so a script can tell "you called me wrong" from "I tried and failed"; `die_usage` is for those. `wiki.sh` exits 2 for its own commands. Two that the compiled helper also answers, `capture` and `feedback add`, and a flag given no value, still exit 1 for a refusal of any kind. 75 "not now, try later". `wiki.sh` itself never exits 75. An extension does, such as Jira or Confluence when a site can't be reached during an event, and the event runner reads it as "ask again at the next event", not a failure. A new command that can be retried later should use it.
- **Flag names mean the same everywhere.** `--dry-run` says what would change and changes nothing. `--yes` answers the question in advance. `--help` and `-h` print the usage. `--all` is every one rather than the named one. A new flag takes an existing name when the meaning matches. The names are for when a tool has such a flag, not a promise that it does: a tool may have no `--yes` where the question is the safeguard. llm-relay's `run`, `review`, `apply` and `answer` have none, because nothing from the cloud lands on the Mac without a keypress there.
- **A program's input is plain and stable.** Output another program reads has no style, no mark, no wrapping and no wording that changes between versions. For new work, give it a flag of its own, so the words for people can change without breaking a caller.
- **Voice.** Plain words, in the present tense. Say what happened, then what to do. Don't apologise and don't shout.

## The kit: `ui.sh`

Kit version 1. sha256 `0e7fb98accc3f4d4b8232e7a8fd89819440c3465275730b09a6519bb8e96bc1a`.

`ui.sh` is in Bash 3.2 and has no dependency. llm-wiki keeps the original. Every other tool carries it byte for byte, beside its script, and sources it after setting three variables, which are all a tool changes:

```bash
STYLE_OVERRIDE="${LLM_WIKI_STYLE:-}"  # the tool's own on/off variable
STYLE_PALETTE_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/llm-wiki/palette"  # a file that may hold palette=
STYLE_THEME_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/llm-wiki/theme"  # a file that may hold theme=
. "$REPO/ui.sh"
```

llm-relay points both files at its settings file. A tool must work with no other llm tool installed, which is why each carries its own copy rather than sourcing another's.

Three checks hold it together:

- **The copies.** The line above gives the kit's sha256. Each tool's smoke test fails when its `ui.sh` doesn't have it. Since every tool keeps a copy of this guide, every copy of the kit is the same. When the other tool's checkout sits beside this one, the test compares the two files as well.
- **The lint.** `tests/ui-lint.sh` fails on a colour code (`\033[`, `\e[`, `\x1b[`), an `S_` or `M_` variable, or a call to version 2's pieces (`say_ok`, `say_warn`, `say_head`, `say_dim`, `say_next`) anywhere outside `ui.sh`, and names the function each is in. Until every command has moved to the pieces, the smoke test runs it as a report, which lists what is left, and doesn't fail on it.
- **The gallery.** `scripts/gallery.sh` runs every command a person reads against fakes, at a terminal's settings, and keeps what each printed in `tests/gallery/`, with an index that says which pieces each used. A command on the old look shows there as `old look`. Run it after changing what a command prints, look at the difference, and commit it. `scripts/gallery.sh --check` fails when what a command prints no longer matches its file, and the smoke test runs that.

Version 2's helpers, `say_ok`, `say_warn`, `say_head`, `say_dim` and `say_next`, are still in the kit until every command has moved, and print as they did. Don't use them in new work.

A Python tool follows the same rules, with the 16 colours:

```python
import os, sys
def style_on(fd=1):
    o = os.environ.get("LLM_WIKI_STYLE", "")
    if o in ("on", "off"):
        return o == "on"
    return os.isatty(fd) and not os.environ.get("NO_COLOR") and os.environ.get("TERM", "dumb") != "dumb"
def sgr(code, text, fd=1):
    return "\033[%sm%s\033[0m" % (code, text) if style_on(fd) else text
def typed(t, fd=1): return sgr("36", t, fd)
def warn_mark(fd=1): return sgr("1;33", "!", fd) + " "
def error(msg, code=1): sys.stderr.write(sgr("31", "error:", 2) + " " + msg + "\n"); sys.exit(code)
def usage_error(msg): error(msg, 2)
def warn_err(msg): sys.stderr.write(warn_mark(2) + msg + "\n")
```

Pass `2` as `fd` for anything inside a line that goes to standard error: `typed("wiki status", 2)`. An extension run for an event writes to a log and is never styled: don't call these there.

## Changing this guide

Raise the version on the first line, and change the copy in llm-relay in the same sitting, so the two never disagree. A change to `ui.sh` raises the kit's version and its sha256 above, and is copied to llm-relay in the same sitting. Don't make a third copy of the kit's code inside a script: a new tool copies `ui.sh` and this file, and sets its own three variables.
