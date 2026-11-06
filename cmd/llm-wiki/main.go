// llm-wiki is the compiled half of wiki.sh. wiki.sh runs it for the commands that have
// been ported, when it has been built and speaks the protocol wiki.sh expects, and
// otherwise does the work itself as it always has. Build it with:
//
//	go build -o bin/llm-wiki ./cmd/llm-wiki
package main

import (
	"errors"
	"flag"
	"fmt"
	"os"
	"strconv"
	"strings"

	"github.com/broxgit/llm-wiki/internal/backfill"
	"github.com/broxgit/llm-wiki/internal/find"
	"github.com/broxgit/llm-wiki/internal/mcp"
	"github.com/broxgit/llm-wiki/internal/routing"
	"github.com/broxgit/llm-wiki/internal/standup"
	"github.com/broxgit/llm-wiki/internal/tokens"
)

// protocol is what wiki.sh checks before it trusts this program: the commands, their
// arguments and what they print. Raise it, and GO_PROTOCOL in wiki.sh with it, whenever
// one of those changes, so a binary left over from an older checkout is passed over.
const protocol = "9"

func main() {
	if len(os.Args) < 2 {
		fail("usage: llm-wiki protocol | report-tokens|report-tokens-gemini <transcripts> <start> <end> <day-starts> <wikis> <exclude> | standup-activity <options> | journal-backfill <transcripts> <start> <end> <day-starts> <wikis> <exclude> <out> <brain> | which <options> | find <options> | mcp")
	}
	switch os.Args[1] {
	case "protocol":
		fmt.Println(protocol)
	case "report-tokens":
		runTable(tokens.Run)
	case "report-tokens-gemini":
		runTable(tokens.RunGemini)
	case "standup-activity":
		out, err := runStandup(os.Args[2:])
		if err != nil {
			fail(err.Error())
		}
		fmt.Print(out)
	case "journal-backfill":
		// The digest is written whole or not at all, and the line about it printed after.
		if len(os.Args) != 10 {
			fail("journal-backfill takes: <transcripts> <start> <end> <day-starts> <wikis> <exclude> <out> <brain>")
		}
		a := os.Args[2:]
		out, err := backfill.Run(backfill.Options{
			Transcripts: a[0], Start: a[1], End: a[2], DayStarts: a[3], Wikis: a[4], Exclude: a[5], Out: a[6], Brain: a[7],
		})
		if err != nil {
			fail(err.Error())
		}
		fmt.Print(out)
	case "which":
		out, err := runWhich(os.Args[2:])
		if err != nil {
			fail(err.Error())
		}
		fmt.Print(out)
	case "find":
		out, err := runFind(os.Args[2:])
		if err != nil {
			fail(err.Error())
		}
		fmt.Print(out)
	case "mcp":
		// The one command that stays up: an MCP server on stdin and stdout, until the
		// input ends. wiki.sh passes what it worked out in the environment, as it does
		// for mcp/server.py.
		if len(os.Args) != 2 {
			fail("mcp takes no arguments")
		}
		if err := mcp.FromEnv().Serve(os.Stdin, os.Stdout); err != nil {
			fail(err.Error())
		}
	default:
		fail("unknown command: " + os.Args[1])
	}
}

// runStandup reads standup-activity's options. Each list is one item a line.
func runStandup(args []string) (string, error) {
	var o standup.Options
	var repos, authors, exclude, max string
	fs := flag.NewFlagSet("standup-activity", flag.ContinueOnError)
	for name, to := range map[string]*string{
		"wikis": &o.Wikis, "journal": &o.Journal, "code-dirs": &o.CodeDirs, "wiki-cmd": &o.WikiCmd,
		"since-flag": &o.SinceFlag, "format": &o.Format, "start-date": &o.StartDate, "end-date": &o.EndDate,
		"start-local": &o.StartLocal, "end-local": &o.EndLocal, "end-label": &o.EndLabel,
		"start-utc": &o.StartUTC, "end-utc": &o.EndUTC, "only": &o.Only, "max": &max,
		"repos": &repos, "authors": &authors, "exclude": &exclude,
	} {
		fs.StringVar(to, name, "", "")
	}
	if err := fs.Parse(args); err != nil {
		return "", err
	}
	var err error
	if o.Max, err = strconv.Atoi(max); err != nil {
		return "", err
	}
	o.Repos, o.Authors, o.Exclude = lines(repos), lines(authors), lines(exclude)
	return standup.Run(o)
}

// runWhich answers `wiki which`. Both answers leave by stdout, since anything else
// would look like a failure: a first line says which it is, covered or uncovered, and
// wiki.sh prints the rest, to stdout or to stderr.
func runWhich(args []string) (string, error) {
	var o routing.Options
	fs := flag.NewFlagSet("which", flag.ContinueOnError)
	for name, to := range map[string]*string{"wikis": &o.Wikis, "home": &o.Home, "wiki-cmd": &o.WikiCmd, "name": &o.Name} {
		fs.StringVar(to, name, "", "")
	}
	if err := fs.Parse(args); err != nil {
		return "", err
	}
	if fs.NArg() > 0 || o.Wikis == "" {
		return "", errors.New("which takes: --wikis <folder> --home <folder> --wiki-cmd <command> [--name <repository>]")
	}
	text, covered, err := routing.Which(o)
	if err != nil {
		return "", err
	}
	if covered {
		return "covered\n" + text, nil
	}
	return "uncovered\n" + text, nil
}

// runFind answers `wiki find`. A first line says how the search went, for wiki.sh to
// log: "found <wiki>", with the first wiki that had a result, or "none". wiki.sh prints
// the rest.
func runFind(args []string) (string, error) {
	var o find.Options
	fs := flag.NewFlagSet("find", flag.ContinueOnError)
	fs.StringVar(&o.Wikis, "wikis", "", "")
	fs.StringVar(&o.Word, "word", "", "")
	if err := fs.Parse(args); err != nil {
		return "", err
	}
	if fs.NArg() > 0 || o.Wikis == "" {
		return "", errors.New("find takes: --wikis <folder> --word <word>")
	}
	text, first, err := find.Search(o)
	if err != nil {
		return "", err
	}
	if first == "" {
		return "none\n" + text, nil
	}
	return "found " + first + "\n" + text, nil
}

func lines(s string) []string {
	return strings.FieldsFunc(s, func(r rune) bool { return r == '\n' })
}

// runTable runs one of the token tables on the command line's arguments. The table is
// printed only once it is all ready, so a failure leaves nothing on stdout and wiki.sh
// can fall back to its own code.
func runTable(run func(tokens.Options) (string, error)) {
	if len(os.Args) != 8 {
		fail(os.Args[1] + " takes: <transcripts> <start> <end> <day-starts> <wikis> <exclude>")
	}
	out, err := run(tokens.Options{
		Transcripts: os.Args[2], Start: os.Args[3], End: os.Args[4], DayStarts: os.Args[5],
		Wikis: os.Args[6], Exclude: os.Args[7], UsageFile: os.Getenv("REPORT_USAGE_FILE"),
	})
	if err != nil {
		fail(err.Error())
	}
	fmt.Print(out)
}

func fail(msg string) {
	fmt.Fprintln(os.Stderr, "llm-wiki: "+msg)
	os.Exit(1)
}
