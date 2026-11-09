package feedback

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func options(t *testing.T, mode string) Options {
	t.Helper()
	home := t.TempDir()
	file := filepath.Join(home, "config", "feedback")
	if err := os.MkdirAll(filepath.Dir(file), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(file, []byte("# a comment\nmode="+mode+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	at := time.Date(2026, 1, 2, 23, 4, 5, 0, time.FixedZone("west", -7*3600))
	return Options{
		Dir: filepath.Join(home, "state", "feedback"), ModeFile: file, Wikis: filepath.Join(home, "wikis"), Home: home,
		Kinds: "bug friction docs idea", Version: "abc1234", Handbook: "30", System: "Linux 6, bash 5, git 2",
		Now: func() time.Time { return at },
	}
}

func TestSlug(t *testing.T) {
	for in, want := range map[string]string{
		"Sync: says 'name a wiki' & no more!": "sync-says-name-a-wiki-no-more",
		"?!":                                  "",
		"a summary that runs on well past what a name holds":   "a-summary-that-runs-on-well-past-what-a",
		"0123456789012345678901234567890123456789 and on":      "0123456789012345678901234567890123456789",
		"Caf\xc3\xa9 \xc3\x89COLE caf\xe9":                     "caf-cole-caf",
		"--x--":                                                "x",
		"012345678901234567890123456789012345678 9":            "012345678901234567890123456789012345678",
		"0123456789012345678901234567890123456789012345678901": "0123456789012345678901234567890123456789",
	} {
		if got := Slug(in); got != want {
			t.Errorf("Slug(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestAddSavesThenCounts(t *testing.T) {
	o := options(t, "share")
	o.Args, o.Stdin = []string{"bug", "It Broke", "--agent", "An agent, a model"}, strings.NewReader("what I ran\n\n\n")
	line, err := Add(o)
	if err != nil || line != "feedback: saved 20260103-060405-it-broke. The user can file it with: wiki feedback send" {
		t.Fatalf("Add = %q, %v", line, err)
	}
	path := filepath.Join(o.Dir, "20260103-060405-it-broke.md")
	want := "Kind: bug\nSummary: It Broke\nStatus: new\nAgent: An agent, a model\nCaptured: 2026-01-03 06:04 UTC\nllm-wiki: abc1234\nHandbook: v30\nSystem: Linux 6, bash 5, git 2\nSeen: 1\n\nwhat I ran\n"
	if got, _ := os.ReadFile(path); string(got) != want {
		t.Errorf("the note is %q", got)
	}
	// A note with no Seen line was seen once.
	if err := os.WriteFile(path, []byte(strings.Replace(want, "Seen: 1\n", "", 1)), 0o644); err != nil {
		t.Fatal(err)
	}
	o.Args, o.Stdin = []string{"idea", "it BROKE"}, strings.NewReader("again")
	line, err = Add(o)
	if err != nil || line != "feedback: seen again, 20260103-060405-it-broke (seen 2 times)" {
		t.Fatalf("Add again = %q, %v", line, err)
	}
	got, _ := os.ReadFile(path)
	if !strings.HasSuffix(string(got), "\nwhat I ran\n\n## Seen again 2026-01-03 06:04 UTC\n\nagain\n") {
		t.Errorf("the note is now %q", got)
	}
	// The same summary in the same second, once that note is dismissed, is a second note.
	if err := os.WriteFile(path, []byte(strings.Replace(want, "Status: new", "Status: dismissed 2026-01-03", 1)), 0o644); err != nil {
		t.Fatal(err)
	}
	o.Stdin = strings.NewReader("a third")
	if line, err = Add(o); err != nil || line != "feedback: saved 20260103-060405-it-broke-2. The user can file it with: wiki feedback send" {
		t.Errorf("Add a third = %q, %v", line, err)
	}
}

func TestAddWhenOffOrOnATerminal(t *testing.T) {
	o := options(t, "nope")
	o.Args, o.Stdin = []string{"bug", "a summary"}, strings.NewReader("details")
	if line, err := Add(o); err != nil || line != "feedback is off on this machine, so nothing was saved. Don't try again this session." {
		t.Errorf("off: %q, %v", line, err)
	}
	if _, err := os.Stat(o.Dir); err == nil {
		t.Error("off: it made the folder")
	}
	o = options(t, "notes")
	o.Args, o.Stdin, o.TTY = []string{"bug", "a summary"}, strings.NewReader("details"), true
	_, err := Add(o)
	var refused *Refused
	if !errors.As(err, &refused) || !strings.HasPrefix(refused.Msg, "feedback add: the details go in --file NOTE or on stdin") {
		t.Errorf("a terminal: %v", err)
	}
}

func TestAddANulByte(t *testing.T) {
	o := options(t, "notes")
	o.Args, o.Stdin = []string{"bug", "a summary"}, strings.NewReader("de\x00tails\n")
	if line, err := Add(o); err != nil || line != "feedback: saved 20260103-060405-a-summary" {
		t.Fatalf("Add = %q, %v", line, err)
	}
	got, _ := os.ReadFile(filepath.Join(o.Dir, "20260103-060405-a-summary.md"))
	if !strings.HasSuffix(string(got), "\n\ndetails\n") {
		t.Errorf("the note is %q", got)
	}
	o = options(t, "notes")
	o.Args, o.Stdin, o.StrictNul = []string{"bug", "a summary"}, strings.NewReader("de\x00tails\n"), true
	_, err := Add(o)
	var refused *Refused
	if err == nil || errors.As(err, &refused) {
		t.Errorf("strict: got %v, want an error that isn't a refusal", err)
	}
}
