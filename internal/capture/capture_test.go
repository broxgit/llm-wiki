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
		if err := os.WriteFile(filepath.Join(root, f), nil, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	at := time.Date(2026, 1, 2, 23, 4, 5, 999, time.FixedZone("west", -7*3600))
	return Options{Wikis: filepath.Join(home, "wikis"), Home: home, Pwd: home, Now: func() time.Time { return at }}, root
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
		{"not a wiki", []string{"other", "slug"}, false, "~/wikis/other is not a wiki"},
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
