Conventions version 1. llm-wiki keeps the original. llm-relay holds a copy: change it here first, then change the copy in the same sitting.

# Conventions for commands

How llm-wiki's commands, and any tool that wants to look like them, talk to a person and to a program. Read it before you change what a command prints. Most of it describes what `wiki.sh` already does. Where a rule is for new work, it says so. It takes two minutes.

## Style

### When style is on

Colour and marks are on only when standard output is a terminal, `NO_COLOR` is unset, `TERM` isn't `dumb`, and the command isn't one an agent reads (below). An error's style is decided the same way, by standard error.

`LLM_WIKI_STYLE=on` or `off` overrides all of it, for a pager (`less -R`) and for tests. `on` wins over `NO_COLOR`: it is a request made for this one tool, and `NO_COLOR` is a standing preference for every tool. Each tool names its own variable: `LLM_RELAY_STYLE` in llm-relay.

Agents' shells can be pseudo-terminals, where "is a terminal" is true. So a command whose output an agent or a program reads calls `style_off` and stays plain whatever the terminal says, even with the variable set to `on`. In llm-wiki those are `start`, `capture`, `sync`, `find`, `which`, `pending`, `patterns`, `lint`, `index`, `log`, `lock`, `compile`, `mcp`, `journal`, `standup`, `tour`, `report`, `stats`, every command that begins `__`, and everything a hook or an extension event runs.

The compiled helper in `cmd/` and `internal/` always prints plain text. `wiki.sh` adds style on the way out.

### The words never change

Style goes around the text and never replaces it. A mark is added in front, and may take the place of a list's `- `, but never of a word. A state stays a word at a terminal too: `ready`, not only a tick. Agents and skills are told to expect the words, and people paste them into chats and issues. With the codes stripped, a terminal's output is its piped output, except for a mark where a `- ` was.

### The vocabulary

| What | How it looks |
|---|---|
| Done, or ready | a green `✓` in front (`+` where the locale isn't UTF-8) |
| Needs something | a bold yellow `!` in front. What it needs is normal weight, with the command in cyan |
| An error | `error:` in red, on standard error |
| A heading for a group | bold |
| Context, an aside such as a size or a path | dim. Never the fix, and never anything the reader needs to act |
| Something the user can type | cyan, and nothing else is cyan |
| The one next step | `Next:` in bold cyan, as the command's last line, when there is exactly one. A list of several to-dos has no `Next:` |
| A wait | one line kept up to date, with a spinner and a clock. llm-wiki doesn't use one yet |

The terminal's own 16 colours, so they follow the user's theme. No 256-colour or true-colour codes, and no dependency.

### What never gets style

A file, a report, the clipboard, a log, anything an agent or another program reads, and text that came from somewhere else. A `NEWS.md` entry is printed as written: its backticks stay backticks, and only the line around it may be bold. Text from elsewhere that is shown at a terminal goes between dim rules, so nothing in it can pass for the tool's own words.

### Layout

A blank line between groups. Marks in front, not words at the end. A column as wide as its longest label. A table row gets no mark, since that would shift the columns.

## Beyond style

- **Every problem ends with its fix.** A line that says something is wrong ends with what to do: `Run: <command>` for something to type, `Ask an agent: "<request>"` for something to say, `Do: <steps>` for what a person does by hand. For new messages this is the rule, and a warning with no fix is a bug. Some older errors, such as an unknown option, only say what happened.
- **Errors** go to standard error as `error: <what happened>. <what to do>`, and exit 1. No stack traces for a mistake a person made.
- **Exit codes.** 0 done. 1 failed. 75 "not now, try later". `wiki.sh` itself never exits 75. An extension does, such as Jira or Confluence when a site can't be reached during an event, and the event runner reads it as "ask again at the next event", not a failure. A new command that can be retried later should use it.
- **Flag names mean the same everywhere.** `--dry-run` says what would change and changes nothing. `--yes` answers the question in advance. `--help` and `-h` print the usage. `--all` is every one rather than the named one. A new flag takes an existing name when the meaning matches.
- **A program's input is plain and stable.** Output another program reads has no style, no mark, no wrapping and no wording that changes between versions. For new work, give it a flag of its own, so the words for people can change without breaking a caller.
- **Voice.** Plain words, in the present tense. Say what happened, then what to do. Don't apologise and don't shout.

## The helpers to copy

Bash 3.2 compatible. Change only the first line, `STYLE_OVERRIDE`, to the tool's own variable. A smoke test in llm-wiki checks that this block is the one in `wiki.sh`.

```bash
# --- style helpers: docs/conventions.md, version 1. Copy, don't edit. ---
STYLE_OVERRIDE="${LLM_WIKI_STYLE:-}" # the one line a tool changes: its own variable
# style_wanted <fd>: style on? LLM_<TOOL>_STYLE=on or off decides; else a terminal, no NO_COLOR, TERM not dumb.
style_wanted() {
  case "$STYLE_OVERRIDE" in on) return 0 ;; off) return 1 ;; esac
  [ -t "$1" ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]
}
style_utf8() {
  case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in *[Uu][Tt][Ff]-8* | *[Uu][Tt][Ff]8*) return 0 ;; esac
  return 1
}
style_set() {
  S_BOLD="" S_DIM="" S_GREEN="" S_YELLOW="" S_CYAN="" S_OFF="" M_OK="" M_WARN=""
  [ "$STYLE" = yes ] || return 0
  S_BOLD=$'\033[1m' S_DIM=$'\033[2m' S_GREEN=$'\033[32m' S_YELLOW=$'\033[33m' S_CYAN=$'\033[36m' S_OFF=$'\033[0m'
  if style_utf8; then M_OK="${S_GREEN}✓${S_OFF} "; else M_OK="${S_GREEN}+${S_OFF} "; fi
  M_WARN="${S_BOLD}${S_YELLOW}!${S_OFF} "
}
STYLE=no STYLE_ERR=no
if style_wanted 1; then STYLE=yes; fi
if style_wanted 2; then STYLE_ERR=yes; fi
style_set
# style_off: for a command whose output an agent or a program reads. Nothing is styled, errors included.
style_off() { STYLE=no STYLE_ERR=no; style_set; }
say_ok() { printf '%s%s\n' "$M_OK" "$*"; }
say_warn() { printf '%s%s\n' "$M_WARN" "$*"; }
say_head() { printf '%s%s%s\n' "$S_BOLD" "$*" "$S_OFF"; }
say_dim() { printf '%s%s%s\n' "$S_DIM" "$*" "$S_OFF"; }
say_next() { printf '%sNext:%s %s\n' "$S_BOLD$S_CYAN" "$S_OFF" "$*"; }
typed() { printf '%s%s%s' "$S_CYAN" "$*" "$S_OFF"; }
die() {
  if [ "$STYLE_ERR" = yes ]; then printf '\033[31merror:\033[0m %s\n' "$*" >&2; else echo "error: $*" >&2; fi
  exit 1
}
# --- end of style helpers ---
```

In Python, the same rules:

```python
import os, sys
def style_on(fd=1):
    o = os.environ.get("LLM_WIKI_STYLE", "")
    if o in ("on", "off"):
        return o == "on"
    return os.isatty(fd) and not os.environ.get("NO_COLOR") and os.environ.get("TERM", "dumb") != "dumb"
def sgr(code, text, fd=1):
    return "\033[%sm%s\033[0m" % (code, text) if style_on(fd) else text
def bold(t): return sgr("1", t)
def dim(t): return sgr("2", t)
def typed(t): return sgr("36", t)
def warn_mark(): return sgr("1;33", "!") + " "
def error(msg): sys.stderr.write(sgr("31", "error:", 2) + " " + msg + "\n"); sys.exit(1)
```

An extension run for an event writes to a log and is never styled: don't call these there.

## Before and after: `wiki status`

Piped, and what an agent gets:

```
WIKI                       HANDBOOK  WAITING  LOCK
demo                       v33       6        free  <- compile due

To do:
- demo: 6 notes waiting. Ask an agent: "compile demo"
- open: 8 item(s) waiting on someone or a date. Run: wiki open
```

At a terminal, with the codes left out. The header and `To do:` are bold, the `<-` note is yellow, each `!` is bold yellow, and `"compile demo"` and `wiki open` are cyan:

```
WIKI                       HANDBOOK  WAITING  LOCK
demo                       v33       6        free  <- compile due

To do:
! demo: 6 notes waiting. Ask an agent: "compile demo"
! open: 8 item(s) waiting on someone or a date. Run: wiki open
```

Every word is the same.

## Changing this guide

Raise the version on the first line, and change the copy in llm-relay in the same sitting, so the two never disagree. A change to the helper block changes it in both scripts too. Don't make a third copy: a new tool copies this file and names its own `STYLE_OVERRIDE`.
