// Package tokens is the Claude Code token table of `wiki report`: tokens per project
// for a range of days, read from the session transcripts. It prints what the Python
// in wiki.sh's report_tokens prints, and that Python is the fallback where this
// program isn't built, so the two are kept the same and a smoke test compares them.
package tokens

import (
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/broxgit/llm-wiki/internal/pyos"
)

// Options are report_tokens' arguments.
type Options struct {
	Transcripts string // ~/.claude/projects
	Start, End  string // days, YYYY-MM-DD, both counted
	DayStarts   string // HH:MM, the local time a day starts
	Wikis       string // the collection
	Exclude     string // comma-separated globs of projects to leave out
	UsageFile   string // when set, "wiki<TAB>session" lines are added to it
}

type row struct {
	sessions           map[string]bool
	newIn, cached, out int64
	lookup, upkeep     int64 // wiki use, in tokens, by kind
}

// Run reads the transcripts and returns the table.
func Run(o Options) (string, error) {
	start, err := time.ParseInLocation("2006-01-02", o.Start, time.Local)
	if err != nil {
		return "", fmt.Errorf("start day: %w", err)
	}
	if _, err := time.ParseInLocation("2006-01-02", o.End, time.Local); err != nil {
		return "", fmt.Errorf("end day: %w", err)
	}
	shift, err := pyos.DayShift(o.DayStarts)
	if err != nil {
		return "", err
	}
	proj, err := newProjects(o.Wikis)
	if err != nil {
		return "", err
	}
	// A file not touched since the day before the range can't hold a line in it.
	cutoff := time.Date(start.Year(), start.Month(), start.Day()-1, 0, 0, 0, 0, time.Local)
	var files []string
	err = filepath.WalkDir(o.Transcripts, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() || !strings.HasSuffix(d.Name(), ".jsonl") {
			return nil
		}
		if st, err := os.Stat(p); err == nil && !st.ModTime().Before(cutoff) {
			files = append(files, p)
		}
		return nil
	})
	if err != nil {
		return "", err
	}
	// In a fixed order: a reply recorded in two files is counted where it is met first.
	sort.Slice(files, func(i, j int) bool { return pyos.LessByParts(files[i], files[j]) })

	sc := newScanner(o.Start, o.End, shift, o.Wikis)
	results := make([]scanned, len(files))
	errs := make([]error, len(files))
	var wg sync.WaitGroup
	slots := make(chan struct{}, runtime.NumCPU())
	for i, f := range files {
		wg.Add(1)
		go func(i int, f string) {
			defer wg.Done()
			slots <- struct{}{}
			base := filepath.Base(f)
			results[i], errs[i] = sc.file(f, strings.TrimSuffix(base, filepath.Ext(base)))
			<-slots
		}(i, f)
	}
	wg.Wait()
	// The Python stops at a transcript it can't read. Failing here hands the report to
	// it, so a file is never left out of the totals without a word.
	for _, err := range errs {
		if err != nil {
			return "", err
		}
	}

	var cwds []string
	for _, res := range results {
		for _, r := range res.records {
			cwds = append(cwds, r.cwd)
		}
	}
	proj.resolve(cwds)

	rows := map[string]*row{}
	var order []string
	seen := map[string]bool{}
	usage := map[[2]string]bool{}
	for _, res := range results {
		// A session started in a stray folder counts toward the project it mostly ran in.
		counts := map[string]int{}
		var first []string
		for _, r := range res.records {
			if x := proj.name(r.cwd); x != "" {
				if counts[x] == 0 {
					first = append(first, x)
				}
				counts[x]++
			}
		}
		mainProject := ""
		for _, x := range first {
			if mainProject == "" || counts[x] > counts[mainProject] {
				mainProject = x
			}
		}
		type owned struct {
			project string
			kind    kind
		}
		wikiUses := map[string]owned{}
		for _, r := range res.records {
			if !r.inRange {
				continue
			}
			p := proj.name(r.cwd)
			if p == "" {
				p = mainProject
			}
			if p == "" {
				p = "other folders"
			}
			rw := rows[p]
			if rw == nil {
				rw = &row{sessions: map[string]bool{}}
				rows[p] = rw
				order = append(order, p)
			}
			rw.sessions[r.session] = true
			if r.hasUse && !seen[r.msgID] {
				seen[r.msgID] = true
				rw.newIn += r.newIn
				rw.cached += r.cached
				rw.out += r.out
			}
			for _, c := range r.parts {
				if !c.toolUse {
					if o, ok := wikiUses[c.id]; ok {
						rows[o.project].add(o.kind, int64(c.size))
					}
					continue
				}
				if c.isRead {
					usage[[2]string{c.wikiRead, r.session}] = true
				}
				for _, w := range c.pages {
					usage[[2]string{w, r.session}] = true
				}
				if c.kind != kindNone {
					wikiUses[c.id] = owned{p, c.kind}
					rw.add(c.kind, int64(c.size))
				}
			}
		}
	}

	if o.UsageFile != "" {
		if err := writeUsage(o.UsageFile, o.Wikis, usage); err != nil {
			return "", err
		}
	}
	return table(rows, order, o.Exclude, tableWords{
		none: "No Claude Code sessions in this range.",
		unit: "Sessions",
		foot: func(t totals) string {
			return fmt.Sprintf("\n%s New input is what entered a session's context for the first time; cache reads are that context read again on later turns.\n", t.use())
		},
	}), nil
}

func (r *row) add(k kind, n int64) {
	if k == kindLookup {
		r.lookup += n
	} else {
		r.upkeep += n
	}
}

func writeUsage(path, wikis string, usage map[[2]string]bool) error {
	keys := make([][2]string, 0, len(usage))
	for k := range usage {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool {
		if keys[i][0] != keys[j][0] {
			return keys[i][0] < keys[j][0]
		}
		return keys[i][1] < keys[j][1]
	})
	var b strings.Builder
	for _, k := range keys {
		// A path can hold a glob or a variable, such as ~/wikis/*/wiki/.
		if st, err := os.Stat(filepath.Join(wikis, k[0], "AGENTS.md")); err == nil && st.Mode().IsRegular() {
			b.WriteString(k[0] + "\t" + k[1] + "\n")
		}
	}
	f, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = f.WriteString(b.String())
	return err
}

// What the two token tables say differently.
type tableWords struct {
	none string // when no project has anything to show
	unit string // the second column's heading
	foot func(t totals) string
}

// totals are the table's last row, as far as the sentence under it needs.
type totals struct{ newIn, lookup, upkeep int64 }

// use is the sentence on how much of the new input the wikis took.
func (t totals) use() string {
	pct := func(n int64) float64 {
		if t.newIn == 0 {
			return 0
		}
		return 100 * float64(n) / float64(t.newIn)
	}
	return fmt.Sprintf("Wiki use is about %.1f%% of new input: lookups %.1f%%, upkeep %.1f%%. Lookups are reads, searches and session starts; upkeep is captures, compiles, lints, syncs and status.",
		pct(t.lookup+t.upkeep), pct(t.lookup), pct(t.upkeep))
}

func table(rows map[string]*row, order []string, exclude string, words tableWords) string {
	var globs []interface{ MatchString(string) bool }
	for _, g := range strings.Split(exclude, ",") {
		if g != "" {
			globs = append(globs, pyos.Glob(g))
		}
	}
	var kept []string
	for _, p := range order {
		r := rows[p]
		if r.newIn == 0 && r.out == 0 {
			continue
		}
		excluded := false
		for _, g := range globs {
			if g.MatchString(p) {
				excluded = true
			}
		}
		if !excluded {
			kept = append(kept, p)
		}
	}
	if len(kept) == 0 {
		return words.none + "\n"
	}
	sort.SliceStable(kept, func(i, j int) bool {
		a, b := rows[kept[i]], rows[kept[j]]
		return a.newIn+a.cached > b.newIn+b.cached
	})
	var b strings.Builder
	fmt.Fprintf(&b, "| Project | %s | New input | Cache reads | Output | Wiki reads (est.) |\n", words.unit)
	b.WriteString("|---|---|---|---|---|---|\n")
	var sessions int
	var newIn, cached, out, lookup, upkeep int64
	for _, p := range kept {
		r := rows[p]
		fmt.Fprintf(&b, "| %s | %d | %s | %s | %s | %s |\n", p, len(r.sessions), short(r.newIn), short(r.cached), short(r.out), short(r.lookup+r.upkeep))
		sessions += len(r.sessions)
		newIn += r.newIn
		cached += r.cached
		out += r.out
		lookup += r.lookup
		upkeep += r.upkeep
	}
	fmt.Fprintf(&b, "| all | %d | %s | %s | %s | %s |\n", sessions, short(newIn), short(cached), short(out), short(lookup+upkeep))
	b.WriteString(words.foot(totals{newIn, lookup, upkeep}))
	return b.String()
}

// short writes a count as the report does: 1.2M, 34k, or the number.
func short(n int64) string {
	switch {
	case n >= 1_000_000:
		return fmt.Sprintf("%.1fM", float64(n)/1e6)
	case n >= 1_000:
		return fmt.Sprintf("%.0fk", float64(n)/1e3)
	}
	return strconv.FormatInt(n, 10)
}
