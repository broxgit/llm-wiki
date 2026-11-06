// Package standup is the body of `wiki standup`: commits, journal entries, wiki notes,
// wiki log entries, work in progress and open callouts for a range of days. It prints
// what wiki.sh's standup_activity prints, and that Bash is the fallback where this
// program isn't built, so the two are kept the same and a smoke test compares them.
//
// wiki.sh keeps what has to stay shell: the options, the dates, the --save, and the
// expansion of its comma lists and the search for repositories, which it passes in
// their final form. What this can't be sure of, such as a file a grep would call binary,
// is an error, and the Bash answers.
package standup

import (
	"bytes"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/broxgit/llm-wiki/internal/routing"
)

// Options are what cmd_standup has worked out by the time it starts gathering.
type Options struct {
	Wikis, Journal, CodeDirs, WikiCmd string
	SinceFlag                         string // --since or --since-as-filter, by git's version
	Format                            string
	StartDate, EndDate                string // days, YYYY-MM-DD
	StartLocal, EndLocal, EndLabel    string
	StartUTC, EndUTC                  string // YYYYMMDDHHMMSS
	Max                               int
	Repos, Authors, Exclude           []string
	Only                              string
}

// Run gathers it all and returns the text.
func Run(o Options) (string, error) {
	if len(o.StartUTC) != 14 || len(o.EndUTC) != 14 {
		return "", errors.New("a time that isn't YYYYMMDDHHMMSS")
	}
	f, err := newFilter(o.Only, o.Exclude)
	if err != nil {
		return "", err
	}
	wikis, err := listWikis(o.Wikis, f)
	if err != nil {
		return "", err
	}
	var b strings.Builder
	fmt.Fprintf(&b, "# Activity: %s to %s (local time)\n\nReport format: %s. Agents: write it up as rules/journal.md says.\n\n## Commits\n", o.StartLocal, o.EndLabel, o.Format)
	done, err := commits(&b, o, f)
	if err != nil {
		return "", err
	}
	if err := journal(&b, o, f); err != nil {
		return "", err
	}
	if err := notes(&b, o, wikis); err != nil {
		return "", err
	}
	if err := wikiLog(&b, o, wikis); err != nil {
		return "", err
	}
	b.WriteString("\n## In progress\n")
	if done.inProgress == "" {
		b.WriteString("\nNone.\n")
	}
	b.WriteString(done.inProgress)
	if err := callouts(&b, wikis); err != nil {
		return "", err
	}
	fmt.Fprintf(&b, "\nTotals: %d commit(s) in %d repo(s).\n", done.nCommits, done.nRepos)
	return b.String(), nil
}

// ---- commits ----

type repoResult struct {
	skipRepo   bool // excluded by name, or under the wikis
	unreadable bool
	gitSaid    string
	noAuthor   bool
	name       string
	lines      []string
	inProgress string
	err        error
}

type commitsResult struct {
	inProgress       string
	nCommits, nRepos int
}

// commits writes the Commits section and returns what later sections say of it.
// Repositories are read side by side, and reported in the order given.
func commits(b *strings.Builder, o Options, f *filter) (commitsResult, error) {
	results := make([]repoResult, len(o.Repos))
	var wg sync.WaitGroup
	slots := make(chan struct{}, runtime.NumCPU())
	for i, r := range o.Repos {
		wg.Add(1)
		go func(i int, r string) {
			defer wg.Done()
			slots <- struct{}{}
			results[i] = readRepo(r, o, f)
			<-slots
		}(i, r)
	}
	wg.Wait()

	found, unreadable, skipped, nRepos, nCommits := 0, 0, 0, 0, 0
	gitSaid := ""
	var inProgress strings.Builder
	for _, r := range results {
		if r.err != nil {
			return commitsResult{}, r.err
		}
		if r.skipRepo {
			continue
		}
		found++
		switch {
		case r.unreadable:
			unreadable++
			if gitSaid == "" {
				gitSaid = r.gitSaid
			}
			continue
		case r.noAuthor:
			skipped++
			continue
		}
		if n := len(r.lines); n > 0 {
			nRepos++
			nCommits += n
			fmt.Fprintf(b, "\n### %s\n", r.name)
			if o.Max > 0 && n > o.Max {
				b.WriteString(strings.Join(r.lines[:o.Max], "\n"))
				fmt.Fprintf(b, "\n- (%d earlier commit(s) not listed)\n", n-o.Max)
			} else {
				b.WriteString(strings.Join(r.lines, "\n") + "\n")
			}
		}
		inProgress.WriteString(r.inProgress)
	}
	if nCommits == 0 {
		b.WriteString("\nNone found.\n")
	}
	if found == 0 {
		fmt.Fprintf(b, "\n(No git repositories found under %s. If this runs in an agent's sandbox, it may not be able to read that folder: run it outside the sandbox. Otherwise set code_dirs: %s journal set code_dirs <folders>)\n", o.CodeDirs, o.WikiCmd)
	} else if unreadable > 0 {
		if gitSaid == "" {
			gitSaid = "nothing"
		}
		fmt.Fprintf(b, "\n(%d of %d repo(s) couldn't be read, so their commits are missing. git said: %s. If this runs in an agent's sandbox, run it outside the sandbox, or allow the code folders and ~/.gitconfig* there.)\n", unreadable, found, gitSaid)
	}
	if skipped > 0 {
		fmt.Fprintf(b, "\n(%d repo(s) skipped: no user.email set and no authors configured.)\n", skipped)
	}
	return commitsResult{inProgress.String(), nCommits, nRepos}, nil
}

func readRepo(r string, o Options, f *filter) repoResult {
	var res repoResult
	if strings.HasPrefix(r+"/", o.Wikis+"/") {
		res.skipRepo = true
		return res
	}
	g := gitIn{dir: r}
	url, _, _ := g.run("config", "--get", "remote.origin.url")
	res.name = routing.RepoName(r, url)
	if g.err == nil && f.excluded(res.name) {
		res.skipRepo = true
		return res
	}
	if _, stderr, ok := g.run("log", "-1", "--format=%h"); !ok && g.err == nil {
		res.unreadable = true
		res.gitSaid, _, _ = strings.Cut(stderr, "\n")
		return res
	}
	var args []string
	if me, _, _ := g.run("config", "user.email"); me != "" {
		args = append(args, "--author="+me)
	}
	for _, a := range o.Authors {
		args = append(args, "--author="+a)
	}
	if len(args) == 0 && g.err == nil {
		res.noAuthor = true
		return res
	}
	logArgs := append([]string{"log", "--all", "--no-merges"}, args...)
	logArgs = append(logArgs, o.SinceFlag+"="+o.StartLocal, "--until="+o.EndLocal, "--date=format-local:%Y-%m-%d %H:%M", "--format=- %cd %h %s")
	log, _, _ := g.run(logArgs...)
	seen := map[string]bool{}
	for _, l := range strings.Split(log, "\n") {
		if l != "" && !seen[l] {
			seen[l] = true
			res.lines = append(res.lines, l)
		}
	}
	// Work in progress: uncommitted files, unpushed commits, a non-default branch.
	status, _, _ := g.run("status", "--porcelain")
	dirty := 0
	if status != "" {
		dirty = strings.Count(status, "\n") + 1
	}
	ahead, _, ok := g.run("rev-list", "--count", "@{u}..HEAD")
	if !ok {
		ahead = "0"
	}
	nAhead, err := strconv.Atoi(ahead)
	if err != nil {
		g.err = errors.New("unpushed count " + ahead)
	}
	br, _, ok := g.run("rev-parse", "--abbrev-ref", "HEAD")
	if !ok {
		br = strings.TrimLeft(br+"\n?", "\n")
	}
	if dirty > 0 || nAhead > 0 || (len(res.lines) > 0 && br != "main" && br != "master") {
		res.inProgress = fmt.Sprintf("- %s: branch %s, %d uncommitted file(s), %s unpushed commit(s)\n", res.name, br, dirty, ahead)
	}
	res.err = g.err
	return res
}

// gitIn runs git in one folder, and keeps the first failure to start it, which the Bash
// would report differently. After that it runs nothing.
type gitIn struct {
	dir string
	err error
}

// run gives the output, less its last newlines as $(...) does, and whether git said yes.
func (g *gitIn) run(args ...string) (out, stderr string, ok bool) {
	if g.err != nil {
		return "", "", false
	}
	var o, e bytes.Buffer
	cmd := exec.Command("git", append([]string{"-C", g.dir}, args...)...)
	cmd.Stdout, cmd.Stderr = &o, &e
	err := cmd.Run()
	var exit *exec.ExitError
	if err != nil && !errors.As(err, &exit) {
		g.err = err
	}
	return strings.TrimRight(o.String(), "\n"), e.String(), err == nil
}

// ---- journal ----

func journal(b *strings.Builder, o Options, f *filter) error {
	b.WriteString("\n## Journal entries\n")
	start, err := time.Parse("2006-01-02", o.StartDate)
	if err != nil {
		return err
	}
	end, err := time.Parse("2006-01-02", o.EndDate)
	if err != nil {
		return err
	}
	got := false
	for d := start; !d.After(end); d = d.AddDate(0, 0, 1) {
		day := d.Format("2006-01-02")
		path := filepath.Join(o.Journal, day+".md")
		if !isFile(path) {
			continue
		}
		text, err := readText(path)
		if err != nil {
			return err
		}
		for _, line := range strings.Split(text, "\n") {
			if !strings.HasPrefix(line, "- ") || f.excluded(journalProject(line)) {
				continue
			}
			fmt.Fprintf(b, "- %s %s\n", day, line[2:])
			got = true
		}
	}
	if !got {
		b.WriteString("\nNone.\n")
	}
	return nil
}

// journalProject is what wiki.sh takes as a journal line's project: from its first [ to
// the first ] after that, or as much of the line as those leave.
func journalProject(line string) string {
	if i := strings.Index(line, "["); i >= 0 {
		line = line[i+1:]
	}
	if i := strings.Index(line, "]"); i >= 0 {
		line = line[:i]
	}
	return line
}

// ---- wiki sections ----

type wiki struct{ name, dir string }

// listWikis is `for w in "$WIKIS_DIR"/*/`, in byte order, cut down by is_wiki and the
// filter. Hidden folders aren't in a glob.
func listWikis(root string, f *filter) ([]wiki, error) {
	entries, err := os.ReadDir(root)
	if err != nil {
		return nil, nil // the glob matches nothing
	}
	var out []wiki
	for _, e := range entries {
		name := e.Name()
		dir := filepath.Join(root, name)
		st, err := os.Stat(dir)
		if strings.HasPrefix(name, ".") || err != nil || !st.IsDir() {
			continue
		}
		if !isFile(filepath.Join(dir, "AGENTS.md")) || !isFile(filepath.Join(dir, "index.md")) || f.excluded(name) {
			continue
		}
		// The Bash puts the name in a sed replacement, where these mean something.
		if strings.ContainsAny(name, `&\`) {
			return nil, errors.New("wiki name " + name)
		}
		out = append(out, wiki{name, dir})
	}
	return out, nil
}

var (
	noteName  = regexp.MustCompile(`\A20\d\d-\d\d-\d\d`)
	noteStamp = regexp.MustCompile(`\A(\d{4})-(\d{2})-(\d{2})-(\d{6})`)
	logEntry  = regexp.MustCompile(`\A## \d{4}-\d{2}-\d{2} `)
	callout   = regexp.MustCompile(`\A> \*\*(Check|Conflict):\*\*`)
)

func notes(b *strings.Builder, o Options, wikis []wiki) error {
	b.WriteString("\n## Wiki notes captured\n")
	any := false
	for _, w := range wikis {
		entries, err := os.ReadDir(filepath.Join(w.dir, "raw"))
		if err != nil {
			continue
		}
		var lines strings.Builder
		for _, e := range entries {
			base := e.Name()
			path := filepath.Join(w.dir, "raw", base)
			if !noteName.MatchString(base) || !isFile(path) {
				continue
			}
			stamp := strings.ReplaceAll(base[:10], "-", "") + "000000"
			if m := noteStamp.FindStringSubmatch(base); m != nil {
				stamp = m[1] + m[2] + m[3] + m[4]
			}
			if stamp < o.StartUTC || stamp >= o.EndUTC {
				continue
			}
			text, err := readText(path)
			if err != nil {
				return err
			}
			title := "(no title)"
			for _, l := range strings.Split(text, "\n") {
				if strings.HasPrefix(l, "# ") {
					if l[2:] != "" {
						title = l[2:]
					}
					break
				}
			}
			stem := base
			if i := strings.LastIndex(base, "."); i >= 0 {
				stem = base[:i]
			}
			fmt.Fprintf(&lines, "- %s: %s\n", stem, title)
		}
		if lines.Len() > 0 {
			any = true
			fmt.Fprintf(b, "\n### %s\n%s", w.name, lines.String())
		}
	}
	if !any {
		b.WriteString("\nNone.\n")
	}
	return nil
}

// wikiLog is the awk in wiki.sh: rebuilding a line splits it on spaces and tabs only,
// and joins the fields with one space.
func wikiLog(b *strings.Builder, o Options, wikis []wiki) error {
	b.WriteString("\n## Wiki changes\n")
	sDay := o.StartUTC[:4] + "-" + o.StartUTC[4:6] + "-" + o.StartUTC[6:8]
	eDay := o.EndUTC[:4] + "-" + o.EndUTC[4:6] + "-" + o.EndUTC[6:8]
	any := false
	for _, w := range wikis {
		path := filepath.Join(w.dir, "log.md")
		if !isFile(path) {
			continue
		}
		text, err := readText(path)
		if err != nil {
			return err
		}
		for _, l := range strings.Split(text, "\n") {
			if !logEntry.MatchString(l) {
				continue
			}
			fields := strings.FieldsFunc(l, func(r rune) bool { return r == ' ' || r == '\t' })
			if fields[1] >= sDay && fields[1] <= eDay {
				any = true
				fmt.Fprintf(b, "- %s: %s\n", w.name, strings.Join(fields[1:], " "))
			}
		}
	}
	if !any {
		b.WriteString("\nNone.\n")
	}
	return nil
}

// callouts writes each wiki's first five open callouts, its files in byte order.
func callouts(b *strings.Builder, wikis []wiki) error {
	b.WriteString("\n## Open checks and conflicts\n")
	any := false
	for _, w := range wikis {
		var files []string
		err := filepath.WalkDir(filepath.Join(w.dir, "wiki"), func(p string, d fs.DirEntry, err error) error {
			if err == nil && d.Type().IsRegular() && strings.HasSuffix(d.Name(), ".md") {
				files = append(files, p)
			}
			return nil
		})
		if err != nil {
			return err
		}
		sort.Strings(files)
		n := 0
		for _, p := range files {
			// The Bash cuts each line at the first colon, meant to end the path.
			if strings.Contains(p, ":") {
				return errors.New("a colon in " + p)
			}
			text, err := readText(p)
			if err != nil {
				return err
			}
			fence := false
			for _, l := range strings.Split(text, "\n") {
				if strings.HasPrefix(l, "```") {
					fence = !fence
					continue
				}
				if !fence && n < 5 && callout.MatchString(l) {
					n++
					any = true
					fmt.Fprintf(b, "- %s: %s\n", w.name, l[2:])
				}
			}
		}
	}
	if !any {
		b.WriteString("\nNone.\n")
	}
	return nil
}

func isFile(p string) bool {
	st, err := os.Stat(p)
	return err == nil && st.Mode().IsRegular()
}

// readText reads a file the Bash reads with grep and awk. What they would treat as
// binary, or read differently by locale, is left to the Bash.
func readText(p string) (string, error) {
	data, err := os.ReadFile(p)
	if err != nil {
		return "", err
	}
	if !utf8.Valid(data) || bytes.IndexByte(data, 0) >= 0 {
		return "", errors.New("not plain text: " + p)
	}
	return string(data), nil
}
