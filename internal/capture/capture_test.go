package capture

import (
	"errors"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"
)

func wiki(t *testing.T) (Options, string) {
	t.Helper()
	home := t.TempDir()
	root := filepath.Join(home, "wikis", "demo")
	if err := os.MkdirAll(root, 0o755); err != nil {
		t.Fatal(err)
	}
	for _, f := range []string{"AGENTS.md", "index.md"} {
		if err := os.WriteFile(filepath.Join(root, f), []byte("Handbook version 1.\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	at := time.Date(2026, 1, 2, 23, 4, 5, 999, time.FixedZone("west", -7*3600))
	return Options{Wikis: filepath.Join(home, "wikis"), Home: home, Pwd: home, WikiCmd: "wiki", Now: func() time.Time { return at }}, root
}

func TestSlug(t *testing.T) {
	for in, want := range map[string]string{
		"Decided: Postgres, v2!":   "decided-postgres-v2",
		"--a--":                    "a",
		"!!!":                      "",
		"":                         "",
		"Caf\xc3\xa9 \xc3\x89cole": "caf-cole",
		"caf\xe9":                  "caf",
		"a_b.C":                    "a-b-c",
		"9":                        "9",
	} {
		if got := Slug(in); got != want {
			t.Errorf("Slug(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestRunNamesByTheClockInUTC(t *testing.T) {
	o, root := wiki(t)
	o.Args = []string{"demo", "A Note"}
	for i, want := range []string{"2026-01-03-060405-a-note.md", "2026-01-03-060405-a-note-2.md", "2026-01-03-060405-a-note-3.md"} {
		o.Stdin = strings.NewReader("body\n")
		line, err := Run(o)
		if err != nil {
			t.Fatal(err)
		}
		if line != "captured: raw/"+want+" in ~/wikis/demo" {
			t.Errorf("run %d printed %q", i, line)
		}
		got, err := os.ReadFile(filepath.Join(root, "raw", want))
		if err != nil || string(got) != "Captured: 2026-01-03\n\nbody\n" {
			t.Errorf("run %d wrote %q, %v", i, got, err)
		}
	}
}

// Two captures can pick the same free name at once: two sessions, the same second, the
// same slug. Neither may write over the other.
func TestRunNeverWritesOverANoteThatAppearsAfterTheNameWasChosen(t *testing.T) {
	o, root := wiki(t)
	o.Args = []string{"demo", "raced"}
	const runs = 40
	errs := make(chan error, runs)
	for i := 0; i < runs; i++ {
		go func(i int) {
			p := o
			p.Stdin = strings.NewReader("body " + strconv.Itoa(i) + "\n")
			_, err := Run(p)
			errs <- err
		}(i)
	}
	for i := 0; i < runs; i++ {
		if err := <-errs; err != nil {
			t.Fatal(err)
		}
	}
	files, err := filepath.Glob(filepath.Join(root, "raw", "*-raced*.md"))
	if err != nil || len(files) != runs {
		t.Fatalf("%d notes in raw/ after %d captures: %v", len(files), runs, err)
	}
	seen := map[string]bool{}
	for _, f := range files {
		got, err := os.ReadFile(f)
		if err != nil {
			t.Fatal(err)
		}
		seen[string(got)] = true
	}
	if len(seen) != runs {
		t.Errorf("%d different notes after %d captures: one wrote over another", len(seen), runs)
	}
}

// A name that is a link, even to nowhere, is taken: the note goes under the next name and
// nothing is written through the link.
func TestRunTakesTheNextNameWhenTheNameIsALink(t *testing.T) {
	o, root := wiki(t)
	o.Args = []string{"demo", "linked"}
	if err := os.MkdirAll(filepath.Join(root, "raw"), 0o777); err != nil {
		t.Fatal(err)
	}
	outside := filepath.Join(t.TempDir(), "outside.md")
	if err := os.Symlink(outside, filepath.Join(root, "raw", "2026-01-03-060405-linked.md")); err != nil {
		t.Skip("no links here")
	}
	o.Stdin = strings.NewReader("body\n")
	line, err := Run(o)
	if err != nil || line != "captured: raw/2026-01-03-060405-linked-2.md in ~/wikis/demo" {
		t.Errorf("printed %q, %v", line, err)
	}
	if _, err := os.Stat(outside); err == nil {
		t.Error("the note was written through the link")
	}
}

func TestRunKeepsADatedNote(t *testing.T) {
	o, root := wiki(t)
	o.Args, o.Stdin = []string{"demo", "dated"}, strings.NewReader("Captured: 2020-01-01\n\nold\n")
	if _, err := Run(o); err != nil {
		t.Fatal(err)
	}
	got, _ := os.ReadFile(filepath.Join(root, "raw", "2026-01-03-060405-dated.md"))
	if string(got) != "Captured: 2020-01-01\n\nold\n" {
		t.Errorf("wrote %q", got)
	}
}

func TestRunRefuses(t *testing.T) {
	for _, c := range []struct {
		name string
		args []string
		tty  bool
		want string
	}{
		{"a terminal", []string{"demo", "slug"}, true, "capture reads the note from stdin, or from a file with --file NOTE"},
		{"no wiki", nil, false, "name a wiki"},
		{"not a wiki", []string{"other", "slug"}, false, "~/wikis/other is not a wiki. Run: wiki status"},
		{"no slug", []string{"demo"}, false, "capture needs a short slug for the name, such as decided-postgres"},
		{"an empty note", []string{"demo", "slug"}, false, "capture got an empty note"},
		{"no value", []string{"demo", "--copy"}, false, "--copy needs a value"},
		{"an option", []string{"demo", "-x"}, false, "capture options: --file NOTE, --copy FILE"},
		{"three names", []string{"demo", "a", "b"}, false, "capture takes a wiki and a slug"},
	} {
		o, _ := wiki(t)
		o.Args, o.TTY, o.Stdin = c.args, c.tty, strings.NewReader("")
		_, err := Run(o)
		var refused *Refused
		if !errors.As(err, &refused) || refused.Msg != c.want {
			t.Errorf("%s: got %v, want the refusal %q", c.name, err, c.want)
		}
	}
}

func TestRunLeavesALineBreakToTheBash(t *testing.T) {
	o, root := wiki(t)
	o.Args, o.Stdin = []string{"demo", "two\nlines"}, strings.NewReader("body")
	_, err := Run(o)
	var refused *Refused
	if err == nil || errors.As(err, &refused) {
		t.Errorf("got %v, want an error that isn't a refusal", err)
	}
	if _, err := os.Stat(filepath.Join(root, "raw")); err == nil {
		t.Error("it wrote before it gave up")
	}
}

func TestLint(t *testing.T) {
	head := func(n int, kind string) string {
		return "warning: line " + strconv.Itoa(n) + " of raw/n.md is " + kind + ", so compile can't read it. Do: edit it to read "
	}
	waiting := `a Waiting: line with no " | " between who and what`
	dueSep := `a Due: line with no " | " between the date and what`
	dueDate := "a Due: line whose date is not YYYY-MM-DD"
	feedback := "a Feedback: line not in the form the handbook gives"
	fbFix := "Feedback: <kind> | <scope> | <rule>, where kind is review, correction, lesson, ask, procedure or toil, and scope is here, everywhere or a wiki's name"
	for _, c := range []struct {
		line string
		want string // the start of the warning, or "" for none
	}{
		{"Waiting: Dana | Reply to the vendor", ""},
		{"Waiting:user|x", head(1, waiting)},
		{"Waiting: user check it", head(1, waiting)},
		{"Waiting:  | Reply", head(1, waiting)},
		{"Waiting: user | \t", head(1, waiting)},
		{" Waiting: indented", ""},
		{"waiting: lower case", ""},
		{"Due: 2026-12-01 | Read", ""},
		{"Due: 2026-12-01 | Read\r", ""},
		{"Due: 2026-12-01 Read", head(1, dueSep)},
		{"Due: next week | Read", head(1, dueDate)},
		{"Due: 2026-1-2 | Read", head(1, dueDate)},
		{"Feedback: review | here | Wrap errors.", ""},
		{"Feedback: toil | go-common | a | b", ""},
		{"Feedback: nit | here | x", head(1, feedback)},
		{"Feedback: review | two words | x", head(1, feedback)},
		{"Feedback: review | here |", head(1, feedback)},
		{"Feedback: lesson here", head(1, feedback)},
	} {
		got := Lint([]byte(c.line+"\n"), "n.md")
		switch {
		case c.want == "" && len(got) != 0:
			t.Errorf("%q: got %q, want no warning", c.line, got)
		case c.want != "" && (len(got) != 1 || !strings.HasPrefix(got[0], c.want)):
			t.Errorf("%q: got %q, want one that starts %q", c.line, got, c.want)
		}
	}
	if got := Lint([]byte("Feedback: x"), "n.md"); len(got) != 1 || got[0] != head(1, feedback)+fbFix {
		t.Errorf("a last line with no line break: got %q", got)
	}
	got := Lint([]byte("Captured: 2026-01-01\n\nWaiting: a\nDue: b\n"), "n.md")
	if len(got) != 2 || !strings.HasPrefix(got[0], head(3, waiting)) || !strings.HasPrefix(got[1], head(4, dueSep)) {
		t.Errorf("line numbers: got %q", got)
	}
}

func TestRunWarnsAboutANoteNotACopy(t *testing.T) {
	o, root := wiki(t)
	var warned []string
	o.Warn = func(w string) { warned = append(warned, w) }
	o.Args, o.Stdin = []string{"demo", "note"}, strings.NewReader("Waiting: nobody\n")
	line, err := Run(o)
	if err != nil || len(warned) != 1 || !strings.HasPrefix(warned[0], "warning: line 3 of raw/2026-01-03-060405-note.md is a Waiting: line") {
		t.Errorf("a note: %q, %v, warned %q", line, err, warned)
	}
	copied := filepath.Join(root, "copy.md")
	if err := os.WriteFile(copied, []byte("Waiting: nobody\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	warned = nil
	o.Args, o.Stdin = []string{"demo", "--copy", copied}, nil
	if _, err := Run(o); err != nil || len(warned) != 0 {
		t.Errorf("a copy: %v, warned %q", err, warned)
	}
}

// From a session, --copy and --file take a file only from inside one of From, compared by
// real path, and never from the home folder or one that holds it. At a terminal, or without
// OnlyFrom, any file is taken.
func TestRunTakesASessionsFileOnlyFromTheProjectOrTheWikis(t *testing.T) {
	o, _ := wiki(t)
	home := o.Home
	repo := filepath.Join(home, "repo")
	out := filepath.Join(home, "outside")
	for _, d := range []string{filepath.Join(repo, "sub"), out} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	write := func(p string) {
		if err := os.WriteFile(p, []byte("x\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	write(filepath.Join(repo, "sub", "in.txt"))
	write(filepath.Join(out, "o.txt"))
	write(filepath.Join(home, "at-home.txt"))
	write(filepath.Join(repo, "tab\there.txt"))
	write(filepath.Join(o.Wikis, "demo", "kept.txt"))
	if err := os.Symlink(filepath.Join(out, "o.txt"), filepath.Join(repo, "link.txt")); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Join(repo, "sub", "in.txt"), filepath.Join(repo, "inner.txt")); err != nil {
		t.Fatal(err)
	}
	o.OnlyFrom, o.From, o.Pwd = true, []string{repo, o.Wikis}, repo
	outside := "takes a file only from the repository it runs in, or from a wikis folder, when no one is at a terminal. "
	for _, c := range []struct {
		args []string
		want string // "" when it is taken, or a piece of the refusal
	}{
		// Taken ones are named in full: the copy itself reads a path from the process's folder.
		{[]string{"demo", "--copy", filepath.Join(repo, "sub", "in.txt")}, ""},
		{[]string{"demo", "--copy", filepath.Join(repo, "inner.txt")}, ""},
		{[]string{"demo", "--copy", filepath.Join(o.Wikis, "demo", "kept.txt")}, ""},
		{[]string{"demo", "s", "--file", filepath.Join(repo, "sub", "in.txt")}, ""},
		{[]string{"demo", "--copy", filepath.Join(out, "o.txt")}, "capture --copy " + outside + "~/outside/o.txt is in neither"},
		{[]string{"demo", "s", "--file", "../outside/o.txt"}, "capture --file " + outside + "../outside/o.txt is in neither"},
		{[]string{"demo", "--copy", "sub/../../outside/o.txt"}, "is in neither"},
		{[]string{"demo", "--copy", "link.txt"}, "link.txt is in neither"},
		{[]string{"demo", "--copy", "tab\there.txt"}, "capture --copy takes no path with a control character in it"},
		// A file that isn't there is refused further on, in its own words.
		{[]string{"demo", "--copy", "gone.txt"}, "no file at gone.txt"},
	} {
		_, err := Run(withArgs(o, c.args))
		var r *Refused
		switch {
		case c.want == "" && err != nil:
			t.Errorf("%q was refused: %v", c.args, err)
		case c.want != "" && (!errors.As(err, &r) || !strings.Contains(r.Msg, c.want)):
			t.Errorf("%q: got %v, want a refusal with %q", c.args, err, c.want)
		}
	}
	// The home folder, a repository whose top is the home folder, and a folder that holds it are no project.
	h := o
	h.Pwd, h.From = home, []string{home, "/", o.Wikis}
	if _, err := Run(withArgs(h, []string{"demo", "--copy", "at-home.txt"})); err == nil || !strings.Contains(err.Error(), "at-home.txt is in neither") {
		t.Errorf("a copy from the home folder: %v", err)
	}
	// At a terminal, and for a caller that doesn't ask for the check, any file is taken.
	for _, p := range []Options{{OnlyFrom: true, TTY: true}, {}} {
		q := o
		q.OnlyFrom, q.TTY = p.OnlyFrom, p.TTY
		if _, err := Run(withArgs(q, []string{"demo", "--copy", filepath.Join(out, "o.txt")})); err != nil {
			t.Errorf("OnlyFrom %v, TTY %v: %v", p.OnlyFrom, p.TTY, err)
		}
	}
}

// From a review of the check: what the kernel opens decides, the path checked is the path
// read, and an option given twice, an empty name, a line break and an unusable home are
// each refused or handled as wiki.sh does.
func TestRunChecksWhatThePathOpens(t *testing.T) {
	o, _ := wiki(t)
	home := o.Home
	repo := filepath.Join(home, "repo")
	for _, d := range []string{filepath.Join(repo, "sub"), filepath.Join(repo, "deep", "dir"), filepath.Join(home, "outside")} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	write := func(p, s string) {
		if err := os.WriteFile(p, []byte(s), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	link := func(to, at string) {
		if err := os.Symlink(to, at); err != nil {
			t.Fatal(err)
		}
	}
	write(filepath.Join(home, "o.txt"), "beside\n")
	write(filepath.Join(repo, "deep", "in.txt"), "deep\n")
	write(filepath.Join(repo, "here.txt"), "here\n")
	link(filepath.Join(home, "outside"), filepath.Join(repo, "sub", "out"))
	link(filepath.Join(home, "o.txt"), filepath.Join(repo, "sub", "o.txt"))
	link("deep/dir", filepath.Join(repo, "sublink"))
	o.OnlyFrom, o.From, o.Pwd = true, []string{repo, o.Wikis}, repo
	refused := func(args []string, want string) {
		t.Helper()
		_, err := Run(withArgs(o, args))
		var r *Refused
		if !errors.As(err, &r) || r.Msg != want {
			t.Errorf("%q: got %v, want %q", args, err, want)
		}
	}
	refused([]string{"demo", "--copy", "sub/out/../o.txt"}, "capture --copy takes a file only from the repository it runs in, or from a wikis folder, when no one is at a terminal. sub/out/../o.txt is in neither, so nothing was saved. This keeps a session from copying the wrong file in by mistake, and guards nothing: a note on stdin is taken from anywhere. Do: ask the user to run the command in a terminal, where any file is taken")
	refused([]string{"demo", "s", "--file", "a\nb"}, "capture --file takes no path with a control character in it when no one is at a terminal, so nothing was saved. Do: ask the user to run the command in a terminal")
	refused([]string{"demo", "s", "--file", "--file", "x"}, "capture takes --file NOTE once")
	refused([]string{"demo", "--copy", "a", "--copy", "a"}, "capture takes --copy FILE once")
	refused([]string{"demo", "--copy", ""}, "--copy needs a value")
	refused([]string{"demo", "s", "--file", ""}, "--file needs a value")
	// sublink/../in.txt opens deep/in.txt, in the repository. The process's own folder is
	// elsewhere: what is checked and what is read is the path from Pwd.
	if _, err := Run(withArgs(o, []string{"demo", "--copy", "sublink/../in.txt"})); err != nil {
		t.Errorf("a link in the repository followed by ..: %v", err)
	}
	if _, err := Run(withArgs(o, []string{"demo", "--copy", "here.txt"})); err != nil {
		t.Errorf("a name from Pwd, read from Pwd: %v", err)
	}
	// With no home named in full, the root is still no project.
	for _, h := range []string{"", "rel"} {
		p := o
		p.Home, p.From = h, []string{"/"}
		_, err := Run(withArgs(p, []string{"demo", "--copy", filepath.Join(home, "o.txt")}))
		var r *Refused
		if !errors.As(err, &r) || !strings.Contains(r.Msg, "is in neither") {
			t.Errorf("home %q, the root as a folder: %v", h, err)
		}
	}
	// A home spelled in another case, where the disk ignores case, still holds no project.
	up := strings.ToUpper(home)
	if up != home && sameFile(up, home) {
		p := o
		p.Home, p.From, p.Pwd = up, []string{home}, home
		if _, err := Run(withArgs(p, []string{"demo", "--copy", filepath.Join(home, "o.txt")})); err == nil {
			t.Errorf("a home in capitals let the home folder through")
		}
	}
}

func withArgs(o Options, args []string) Options {
	o.Args, o.Stdin = args, nil
	return o
}
