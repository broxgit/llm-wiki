// Package backfill writes the digest of `wiki journal backfill`: past Claude Code
// sessions and Gemini's conversations in Antigravity, as one block per project per day
// with the user's prompts, the files changed, whether it committed, and the last reply.
// It writes what the Python in wiki.sh's journal_backfill writes.
//
// That Python stops at the first record it can't handle. So anything this port isn't
// sure it reads the same way is an error, wiki.sh runs the Python, and what the Python
// does is the answer.
package backfill

import (
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/broxgit/llm-wiki/internal/pyos"
)

// Options are the Python's arguments, in its order.
type Options struct {
	Transcripts string // Claude Code's projects folder
	Start, End  string // the first and last day, YYYY-MM-DD
	DayStarts   string // HH:MM
	Wikis       string // the collection
	Exclude     string // project patterns, comma separated
	Out         string // the digest
	Brain       string // Antigravity's brain folder
}

// Prompts written by tools, not the user. Side-session briefs are kept, marked.
var (
	machine = []string{"<task-notification", "<side-sessions-event", "<cross-session-message", "Caveat:",
		"[Request interrupted", "This session is being continued"}
	brief = []string{"Background (from the session that started this one)", "Task (from the session that started this one)"}
)

// Run writes the digest to o.Out and returns the line the Python prints. The digest
// goes to a temporary file first and is moved into place only when it is complete, so
// a failure leaves what was there.
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
	var excl []*regexp.Regexp
	for _, g := range strings.Split(o.Exclude, ",") {
		if g != "" {
			excl = append(excl, pyos.Glob(g))
		}
	}
	excluded := func(p string) bool {
		for _, re := range excl {
			if re.MatchString(p) {
				return true
			}
		}
		return false
	}
	nm, err := newNames(o.Wikis)
	if err != nil {
		return "", err
	}
	// A file not touched since the day before the range can't hold a line in it.
	cutoff := time.Date(start.Year(), start.Month(), start.Day()-1, 0, 0, 0, 0, time.Local)
	files, err := claudeFiles(o.Transcripts, cutoff)
	if err != nil {
		return "", err
	}
	convs, err := geminiFiles(o.Brain, cutoff)
	if err != nil {
		return "", err
	}

	rd := reader{start: o.Start, end: o.End, shift: shift}
	claude := make([][]claudeRec, len(files))
	gemini := make([][]geminiStep, len(convs))
	errs := make([]error, len(files)+len(convs))
	var wg sync.WaitGroup
	slots := make(chan struct{}, runtime.NumCPU())
	for i := range errs {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			slots <- struct{}{}
			if i < len(files) {
				claude[i], errs[i] = rd.claude(files[i])
			} else {
				gemini[i-len(files)], errs[i] = rd.gemini(convs[i-len(files)].file)
			}
			<-slots
		}(i)
	}
	wg.Wait()
	var dirs []string
	for i, err := range errs {
		if err != nil {
			return "", err
		}
		if i < len(files) {
			for _, r := range claude[i] {
				if r.cwd != "" {
					dirs = append(dirs, r.cwd)
				}
			}
			continue
		}
		for _, st := range gemini[i-len(files)] {
			for _, c := range st.calls {
				dirs = append(dirs, c.dirs...)
			}
		}
	}
	nm.resolve(dirs)

	work := map[[2]string]*block{}
	get := func(day, p, hm string) *block {
		k := [2]string{day, p}
		w := work[k]
		if w == nil {
			w = &block{first: hm, last: hm, sessions: map[string]bool{}}
			work[k] = w
		}
		w.first, w.last = min(w.first, hm), max(w.last, hm)
		return w
	}

	for i, f := range files {
		recs := claude[i]
		// A session started from a stray folder (/tmp, a memory folder) belongs to the
		// known project most of its records ran in, if there is one.
		var counts tally
		for _, r := range recs {
			if p := nm.project(r.cwd); nm.known[p] {
				counts.add(p)
			}
		}
		main, hasMain := counts.most()
		for _, r := range recs {
			if !r.inRange {
				continue
			}
			p := nm.project(r.cwd)
			if !nm.known[p] && hasMain && main != "" {
				p = main
			}
			if excluded(p) {
				continue
			}
			if r.err != nil {
				return "", fmt.Errorf("%s: %w", f, r.err)
			}
			w := get(r.day, p, r.hm)
			w.sessions[r.session] = true
			if r.branch != "" {
				w.branch = r.branch
			}
			for _, t := range r.prompts {
				w.prompts = append(w.prompts, prompt{r.hm, t})
			}
			w.addFiles(r.files)
			w.commit = w.commit || r.commit
			if r.end != "" {
				w.end = r.end
			}
		}
	}

	// Gemini conversations in Antigravity: one transcript per conversation, which
	// doesn't record its workspace. The project is the one its file paths and `git -C`
	// folders point at most often.
	for i, c := range convs {
		steps := gemini[i]
		var counts tally
		for _, st := range steps {
			for _, call := range st.calls {
				for _, d := range call.dirs {
					if p := nm.project(d); nm.known[p] {
						counts.add(p)
					}
				}
			}
		}
		p, ok := counts.most()
		if !ok {
			p = "gemini"
		}
		if excluded(p) {
			continue
		}
		for _, st := range steps {
			if !st.hasTime {
				continue
			}
			if st.err != nil {
				return "", fmt.Errorf("%s: %w", c.file, st.err)
			}
			if st.day < o.Start || st.day > o.End {
				continue
			}
			w := get(st.day, p, st.hm)
			if !w.sessions["s"+c.name] {
				w.gemini++
			}
			w.sessions["s"+c.name] = true
			switch {
			case st.user && st.isText:
				t := st.content
				if k := strings.LastIndex(t, "<USER_REQUEST>"); k >= 0 {
					t = t[k+len("<USER_REQUEST>"):]
				}
				t, _, _ = strings.Cut(t, "</USER_REQUEST>")
				if t = clean(t, 240); t != "" {
					w.prompts = append(w.prompts, prompt{st.hm, t})
				}
			case st.planner:
				for _, call := range st.calls {
					if call.write && call.path != "" {
						w.addFiles([]string{basename(call.path)})
					}
					if strings.Contains(call.cmd, "git commit") || strings.Contains(call.cmd, "wiki.sh sync") {
						w.commit = true
					}
				}
				if !st.toolCalls && st.isText {
					if t := clean(st.content, 400); t != "" {
						w.end = t
					}
				}
			}
		}
	}

	body, n := digest(o.Start, o.End, work)
	if err := writeFile(o.Out, body); err != nil {
		return "", err
	}
	return fmt.Sprintf("%d project-day(s) from %d Claude Code transcript(s) and %d Gemini conversation(s)\n", n, len(files), len(convs)), nil
}

type prompt struct{ hm, text string }

// block is one project on one day.
type block struct {
	first, last string
	sessions    map[string]bool
	prompts     []prompt
	files       []string
	commit      bool
	end         string
	branch      string
	gemini      int
}

func (w *block) addFiles(names []string) {
	for _, b := range names {
		if !contains(w.files, b) {
			w.files = append(w.files, b)
		}
	}
}

func contains(xs []string, x string) bool {
	for _, y := range xs {
		if y == x {
			return true
		}
	}
	return false
}

// tally counts names in the order they are first met, as a Python dict keeps them.
type tally struct {
	order []string
	n     map[string]int
}

func (t *tally) add(name string) {
	if t.n == nil {
		t.n = map[string]int{}
	}
	if t.n[name] == 0 {
		t.order = append(t.order, name)
	}
	t.n[name]++
}

// most is max(seen, key=seen.get): the first of the most counted.
func (t *tally) most() (string, bool) {
	if len(t.order) == 0 {
		return "", false
	}
	best := t.order[0]
	for _, x := range t.order[1:] {
		if t.n[x] > t.n[best] {
			best = x
		}
	}
	return best, true
}

// digest is the file the Python writes, and the number of blocks in it.
func digest(start, end string, work map[[2]string]*block) (string, int) {
	keys := make([][2]string, 0, len(work))
	for k := range work {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool {
		if keys[i][0] != keys[j][0] {
			return keys[i][0] < keys[j][0]
		}
		return keys[i][1] < keys[j][1]
	})
	var b strings.Builder
	fmt.Fprintf(&b, "# Session digest %s to %s\n\n", start, end)
	b.WriteString("Written by `wiki.sh journal backfill` from Claude Code transcripts and Gemini's Antigravity conversations. An agent turns this into journal entries, then this file can go.\n")
	b.WriteString("Times are local. Each block is one project on one day: the user's prompts, files changed, and the last thing the agent said.\n")
	day, n := "", 0
	for _, k := range keys {
		w := work[k]
		if len(w.prompts) == 0 {
			continue
		}
		n++
		if k[0] != day {
			fmt.Fprintf(&b, "\n## %s\n", k[0])
			day = k[0]
		}
		meta := []string{w.first + "-" + w.last, strconv.Itoa(len(w.sessions)) + " session(s)"}
		if w.gemini > 0 {
			meta = append(meta, strconv.Itoa(w.gemini)+" in Gemini")
		}
		if w.branch != "" {
			meta = append(meta, "branch "+w.branch)
		}
		if w.commit {
			meta = append(meta, "ran git commit")
		}
		fmt.Fprintf(&b, "\n### [%s] %s\n", k[1], strings.Join(meta, ", "))
		ps := append([]prompt(nil), w.prompts...)
		sort.SliceStable(ps, func(i, j int) bool { return ps[i].hm < ps[j].hm })
		if len(ps) > 14 {
			more := prompt{"", fmt.Sprintf("... %d more prompts ...", len(ps)-14)}
			ps = append(append(ps[:9:9], more), ps[len(ps)-5:]...)
		}
		for _, p := range ps {
			if p.hm != "" {
				fmt.Fprintf(&b, "- %s %s\n", p.hm, p.text)
			} else {
				fmt.Fprintf(&b, "- %s\n", p.text)
			}
		}
		if len(w.files) > 0 {
			files, more := w.files, ""
			if len(files) > 12 {
				files, more = files[:12], " ..."
			}
			fmt.Fprintf(&b, "- files changed: %s%s\n", strings.Join(files, ", "), more)
		}
		if w.end != "" {
			fmt.Fprintf(&b, "- last reply: %s\n", w.end)
		}
	}
	return b.String(), n
}

// writeFile puts the digest in place whole: a temporary file in the same folder,
// renamed over the old digest once it is written. It keeps an old digest's mode.
func writeFile(path, body string) error {
	old, err := os.Lstat(path)
	if err == nil && !old.Mode().IsRegular() {
		return odd(path + " is not a plain file")
	}
	tmp := filepath.Join(filepath.Dir(path), "."+filepath.Base(path)+".tmp-"+strconv.Itoa(os.Getpid()))
	f, err := os.OpenFile(tmp, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o666)
	if err != nil {
		return err
	}
	_, err = f.WriteString(body)
	if cerr := f.Close(); err == nil {
		err = cerr
	}
	if err == nil && old != nil {
		err = os.Chmod(tmp, old.Mode().Perm())
	}
	if err == nil {
		err = os.Rename(tmp, path)
	}
	if err != nil {
		os.Remove(tmp)
	}
	return err
}

// claudeFiles is the Python's sorted(Path(root).rglob("*.jsonl")), less the files not
// touched since cutoff. A folder that matches and passes would stop the Python.
func claudeFiles(root string, cutoff time.Time) ([]string, error) {
	if !isDir(root) {
		return nil, nil
	}
	var files []string
	err := filepath.WalkDir(root, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			// rglob passes over a folder it can't read.
			return nil
		}
		if p == root || !strings.HasSuffix(d.Name(), ".jsonl") {
			return nil
		}
		st, err := os.Stat(p)
		if err != nil {
			return odd("can't read " + p)
		}
		if st.ModTime().Before(cutoff) {
			return nil
		}
		if st.IsDir() {
			return odd(p + " is a folder")
		}
		files = append(files, p)
		return nil
	})
	sort.Slice(files, func(i, j int) bool { return pyos.LessByParts(files[i], files[j]) })
	return files, err
}

type conv struct{ name, file string }

// geminiFiles is the Python's sorted(Path(brain).glob("*/.system_generated/logs/transcript_full.jsonl")),
// less the files not touched since cutoff.
func geminiFiles(brain string, cutoff time.Time) ([]conv, error) {
	if !isDir(brain) {
		return nil, nil
	}
	entries, err := os.ReadDir(brain)
	if err != nil {
		return nil, err
	}
	sort.Slice(entries, func(i, j int) bool { return entries[i].Name() < entries[j].Name() })
	var convs []conv
	for _, e := range entries {
		f := filepath.Join(brain, e.Name(), ".system_generated", "logs", "transcript_full.jsonl")
		if _, err := os.Lstat(f); err != nil {
			continue
		}
		st, err := os.Stat(f)
		if err != nil {
			return nil, odd("can't read " + f)
		}
		if st.ModTime().Before(cutoff) {
			continue
		}
		if st.IsDir() {
			return nil, odd(f + " is a folder")
		}
		convs = append(convs, conv{e.Name(), f})
	}
	return convs, nil
}

func isDir(p string) bool {
	st, err := os.Stat(p)
	return err == nil && st.IsDir()
}

func isFile(p string) bool {
	st, err := os.Stat(p)
	return err == nil && st.Mode().IsRegular()
}
