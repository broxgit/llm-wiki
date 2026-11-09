package tokens

import "testing"

func TestClassify(t *testing.T) {
	for _, c := range []struct {
		what         string
		name         string
		byPath, byCm bool
		cmd          string
		want         kind
	}{
		// A tool's name decides first, whatever it was given.
		{"MCP search", "mcp__llm-wiki__wiki_search", false, false, "", kindLookup},
		{"MCP read", "mcp__llm-wiki__wiki_read", false, false, "", kindLookup},
		{"MCP start", "wiki_start", false, false, "", kindLookup},
		{"MCP list", "mcp__llm-wiki__wiki_list", false, false, "", kindLookup},
		{"MCP capture", "mcp__llm-wiki__wiki_capture", false, false, "", kindUpkeep},
		{"MCP status", "mcp__llm-wiki__wiki_status", false, false, "", kindUpkeep},
		{"MCP feedback", "mcp__llm-wiki__wiki_feedback", false, false, "", kindUpkeep},
		{"MCP name wins over a path", "mcp__llm-wiki__wiki_capture", true, false, "", kindUpkeep},
		{"a name that only contains one", "wiki_search_all", false, false, "", kindNone},
		// Then a path: the edit tools are upkeep, anything else a lookup.
		{"Edit", "Edit", true, false, "", kindUpkeep},
		{"Write", "Write", true, false, "", kindUpkeep},
		{"MultiEdit", "MultiEdit", true, false, "", kindUpkeep},
		{"NotebookEdit", "NotebookEdit", true, false, "", kindUpkeep},
		{"write_file", "write_file", true, false, "", kindUpkeep},
		{"write_to_file", "write_to_file", true, false, "", kindUpkeep},
		{"replace_file_content", "replace_file_content", true, false, "", kindUpkeep},
		{"multi_replace_file_content", "multi_replace_file_content", true, false, "", kindUpkeep},
		{"Read", "Read", true, false, "", kindLookup},
		{"Grep", "Grep", true, false, "", kindLookup},
		{"an unnamed call", "", true, false, "", kindLookup},
		{"a path beats the command", "Edit", true, true, "wiki.sh find x", kindUpkeep},
		// Then the wiki subcommands in a command.
		{"find", "Bash", false, true, "bash /x/wiki.sh find deploy", kindLookup},
		{"sync", "Bash", false, true, "/x/wiki.sh sync demo", kindUpkeep},
		{"capture", "Bash", false, true, "wiki.sh capture 'a note'", kindUpkeep},
		{"each lookup subcommand", "Bash", false, true, "wiki.sh start; wiki.sh which; wiki.sh news; wiki.sh tips; wiki.sh patterns; wiki.sh stats; wiki.sh report; wiki.sh standup; wiki.sh help", kindLookup},
		{"find then sync", "Bash", false, true, "wiki.sh find x && wiki.sh sync", kindUpkeep},
		{"sync then find", "Bash", false, true, "wiki.sh sync; wiki.sh find x", kindUpkeep},
		{"a subcommand joined to ;", "Bash", false, true, "wiki.sh find;ls", kindLookup},
		{"a subcommand joined to &&", "Bash", false, true, "wiki.sh sync&&ls", kindUpkeep},
		{"a quoted subcommand", "Bash", false, true, `wiki.sh "sync"`, kindUpkeep},
		{"a flag first is not a lookup subcommand", "Bash", false, true, "wiki.sh --root x find", kindUpkeep},
		{"a subcommand on the next line", "Bash", false, true, "wiki.sh\nlint", kindUpkeep},
		{"a subcommand not in the list", "Bash", false, true, "wiki.sh Find x", kindUpkeep},
		{"a command that starts with wiki", "Bash", false, true, "  wiki compile", kindUpkeep},
		{"a lookup that starts with wiki", "Bash", false, true, "wiki find x", kindLookup},
		{"wiki later in the line is not a wiki command", "Bash", false, true, "echo wiki sync", kindLookup},
		{"no subcommand, a cat", "Bash", false, true, "cat ~/wikis/demo/index.md", kindLookup},
		{"wiki.sh with nothing after it", "Bash", false, true, "less wiki.sh", kindLookup},
		{"wiki.sh and a path", "Bash", false, true, "grep -n x wiki.sh docs/using.md", kindUpkeep},
		// Not a wiki call at all.
		{"nothing touched", "Bash", false, false, "wiki.sh sync", kindNone},
		{"a plain read elsewhere", "Read", false, false, "", kindNone},
	} {
		if got := classify(c.name, c.byPath, c.byCm, c.cmd); got != c.want {
			t.Errorf("%s: classify(%q, path %v, cmd %v, %q) = %d, want %d", c.what, c.name, c.byPath, c.byCm, c.cmd, got, c.want)
		}
	}
}

func TestUseSentence(t *testing.T) {
	const tail = " Lookups are reads, searches and session starts; upkeep is captures, compiles, lints, syncs and status."
	for _, c := range []struct {
		t    totals
		want string
	}{
		{totals{}, "Wiki use is about 0.0% of new input: lookups 0.0%, upkeep 0.0%."},
		{totals{newIn: 2000, lookup: 1000}, "Wiki use is about 50.0% of new input: lookups 50.0%, upkeep 0.0%."},
		{totals{newIn: 2000, upkeep: 1000}, "Wiki use is about 50.0% of new input: lookups 0.0%, upkeep 50.0%."},
		// Each figure is rounded by itself, so the two can differ from the whole.
		{totals{newIn: 3000, lookup: 1, upkeep: 1}, "Wiki use is about 0.1% of new input: lookups 0.0%, upkeep 0.0%."},
		{totals{newIn: 1000, lookup: 5, upkeep: 5}, "Wiki use is about 1.0% of new input: lookups 0.5%, upkeep 0.5%."},
	} {
		if got := c.t.use(); got != c.want+tail {
			t.Errorf("%+v: %q, want %q", c.t, got, c.want+tail)
		}
	}
}
