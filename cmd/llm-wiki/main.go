// llm-wiki is the compiled half of wiki.sh. wiki.sh runs it for the commands that have
// been ported, when it has been built and speaks the protocol wiki.sh expects, and
// otherwise does the work itself as it always has. Build it with:
//
//	go build -o bin/llm-wiki ./cmd/llm-wiki
package main

import (
	"fmt"
	"os"

	"github.com/broxgit/llm-wiki/internal/tokens"
)

// protocol is what wiki.sh checks before it trusts this program: the commands, their
// arguments and what they print. Raise it, and GO_PROTOCOL in wiki.sh with it, whenever
// one of those changes, so a binary left over from an older checkout is passed over.
const protocol = "1"

func main() {
	if len(os.Args) < 2 {
		fail("usage: llm-wiki protocol | report-tokens <transcripts> <start> <end> <day-starts> <wikis> <exclude>")
	}
	switch os.Args[1] {
	case "protocol":
		fmt.Println(protocol)
	case "report-tokens":
		if len(os.Args) != 8 {
			fail("report-tokens takes: <transcripts> <start> <end> <day-starts> <wikis> <exclude>")
		}
		// Printed only once the whole table is ready, so a failure leaves nothing on
		// stdout and wiki.sh can fall back to its own code.
		out, err := tokens.Run(tokens.Options{
			Transcripts: os.Args[2], Start: os.Args[3], End: os.Args[4], DayStarts: os.Args[5],
			Wikis: os.Args[6], Exclude: os.Args[7], UsageFile: os.Getenv("REPORT_USAGE_FILE"),
		})
		if err != nil {
			fail(err.Error())
		}
		fmt.Print(out)
	default:
		fail("unknown command: " + os.Args[1])
	}
}

func fail(msg string) {
	fmt.Fprintln(os.Stderr, "llm-wiki: "+msg)
	os.Exit(1)
}
