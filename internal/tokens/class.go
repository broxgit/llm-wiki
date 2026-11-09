package tokens

import (
	"regexp"
	"strings"

	"github.com/broxgit/llm-wiki/internal/pyos"
)

// What a tool call that touches the wikis is: a lookup, or upkeep. The Python in
// wiki.sh's report_tokens and report_tokens_gemini has the same rule (wiki_kind), and
// the two are kept the same.
type kind int

const (
	kindNone kind = iota // the call doesn't touch the wikis
	kindLookup
	kindUpkeep
)

var (
	lookupTools = []string{"wiki_read", "wiki_search", "wiki_start", "wiki_list"}
	upkeepTools = []string{"wiki_capture", "wiki_status", "wiki_feedback"}
	editTools   = map[string]bool{
		"Edit": true, "Write": true, "MultiEdit": true, "NotebookEdit": true,
		"write_file": true, "write_to_file": true, "replace_file_content": true, "multi_replace_file_content": true,
	}
	lookupSubs = map[string]bool{
		"find": true, "start": true, "which": true, "news": true, "tips": true,
		"patterns": true, "stats": true, "report": true, "standup": true, "help": true,
	}

	// The word after wiki.sh, and after a wiki command that starts the line.
	subWord  = `[` + pyos.Space + `]+["']?([^` + pyos.Space + `;&|<>()"'` + "`" + `]+)`
	subAfter = regexp.MustCompile(`wiki\.sh` + subWord)
	subFirst = regexp.MustCompile(`\A[` + pyos.Space + `]*wiki` + subWord)
)

func endsWithAny(name string, suffixes []string) bool {
	for _, s := range suffixes {
		if strings.HasSuffix(name, s) {
			return true
		}
	}
	return false
}

// classify files a call by its tool's name, then by a path it touched, then by the wiki
// subcommands in its command. byPath and byCmd say how the call touches the wikis.
func classify(name string, byPath, byCmd bool, cmd string) kind {
	switch {
	case endsWithAny(name, lookupTools):
		return kindLookup
	case endsWithAny(name, upkeepTools):
		return kindUpkeep
	case byPath:
		if editTools[name] {
			return kindUpkeep
		}
		return kindLookup
	case byCmd:
		subs := subAfter.FindAllStringSubmatch(cmd, -1)
		if m := subFirst.FindStringSubmatch(cmd); m != nil {
			subs = append(subs, m)
		}
		for _, m := range subs {
			if !lookupSubs[m[1]] {
				return kindUpkeep
			}
		}
		return kindLookup
	}
	return kindNone
}
