package backfill

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// Printed by the Python's clean(s, n) under Python 3.14.
func TestCleanLikePython(t *testing.T) {
	cases := []struct {
		in   string
		n    int
		want string
	}{
		{"  hello\n\n world  ", 240, "hello world"},
		{"<system-reminder>x</system-reminder>keep", 240, "keep"},
		{"a<command-name>/x</command-name> b <command-args></command-args>c", 240, "a b c"},
		{"<system-reminder>open only", 240, "<system-reminder>open only"},
		{"<command-name>a</command-other> z", 240, "<command-name>a</command-other> z"},
		{"<local-command-stdout>out</local-command-stdout>after<local-command-stdout>2</local-command-stdout>", 240, "after"},
		{"<command->x</command->", 240, "<command->x</command->"},
		{"<Command-x>y</Command-x>", 240, "<Command-x>y</Command-x>"},
		{"a<system-reminder>1</system-reminder><system-reminder>2</system-reminder>b", 240, "ab"},
		{"<system-reminder>a<command-x>b</command-x>c</system-reminder>d", 240, "d"},
		{"<command-x>a<system-reminder>b</command-x>c</system-reminder>", 240, "c</system-reminder>"},
		{"x\x1cy\x1f z w​v", 240, "x y z w​v"},
		{strings.Repeat("é", 20), 10, "ééééééé..."},
		{"ab😀cdefghij", 8, "ab😀cd..."},
		{"abcdefgh", 8, "abcdefgh"},
		{"abcdefghi", 8, "abcde..."},
	}
	for _, c := range cases {
		if got := clean(c.in, c.n); got != c.want {
			t.Errorf("clean(%q, %d) = %q, Python gives %q", c.in, c.n, got, c.want)
		}
	}
}

// Printed by Python's str.splitlines, Path.stem and os.path.basename.
func TestPythonStrings(t *testing.T) {
	if got := strings.Join(splitLines("a\r\nb\rc\nd\x0be\x1cf g\n\nh\n"), "|"); got != "a|b|c|d|e|f|g||h" {
		t.Errorf("splitLines = %q, Python gives a|b|c|d|e|f|g||h", got)
	}
	for in, want := range map[string]string{"a.jsonl": "a", ".jsonl": ".jsonl", "..jsonl": "..jsonl", "a.b.jsonl": "a.b", "x": "x"} {
		if got := stem(in); got != want {
			t.Errorf("stem(%q) = %q, Python gives %q", in, got, want)
		}
	}
	for in, want := range map[string]string{"/a/b.md": "b.md", "b.md": "b.md", "/a/": "", "": ""} {
		if got := basename(in); got != want {
			t.Errorf("basename(%q) = %q, Python gives %q", in, got, want)
		}
	}
}

// Printed by bool(json.loads(v)).
func TestTruthyLikePython(t *testing.T) {
	for v, want := range map[string]bool{
		"null": false, "false": false, "true": true, "0": false, "-0": false, "0.0": false, "-0.0": false,
		"1e-400": false, "0e5": false, "2": true, "-1": true, `""`: false, `" "`: true, "[]": false, "[ ]": false,
		"[0]": true, "{}": false, "{ }": false, `{"a":1}`: true, "1.5": true, "": false,
	} {
		if got := truthy(json.RawMessage(v)); got != want {
			t.Errorf("truthy(%s) = %v, Python gives %v", v, got, want)
		}
	}
}

// Printed by "git commit" in str(v): a list or dict holds it only in one of its strings.
func TestMentionsLikeStr(t *testing.T) {
	for v, want := range map[string]bool{
		`"git commit -m x"`:          true,
		`["git commit -m x"]`:        true,
		`{"git commit":1}`:           true,
		`{"a":["x","git commit"]}`:   true,
		`null`:                       false,
		`["git", "commit"]`:          false,
		`"git status; git  commit"`:  false,
		`"echo hi && git commit -a"`: true,
	} {
		if got := mentions(json.RawMessage(v), "git commit"); got != want {
			t.Errorf("mentions(%s) = %v, Python gives %v", v, got, want)
		}
	}
}

// max(seen, key=seen.get) gives the first of the most counted, in the order first met.
func TestTallyMostIsFirstMet(t *testing.T) {
	var c tally
	for _, x := range []string{"b", "a", "c", "a", "b"} {
		c.add(x)
	}
	if got, ok := c.most(); !ok || got != "b" {
		t.Errorf("most = %q, Python gives b", got)
	}
	var none tally
	if _, ok := none.most(); ok {
		t.Error("an empty tally named a project")
	}
}

func TestObjectLeavesWhatItDoubtsToThePython(t *testing.T) {
	for line, want := range map[string]string{
		`{"a":1}`:         "ok",
		`not json`:        "skip",
		``:                "skip",
		`[1,2]`:           "error",
		`"text"`:          "error",
		`{"a":NaN}`:       "error",
		`{"a":"😀"}`:       "ok",
		`{"a":"\ud83d"}`:  "error",
		`{"a":"\ude00"}`:  "error",
		`{"a":"\\ud83d"}`: "ok",
		`{"a":"\\😀"}`:     "ok",
	} {
		_, ok, err := object([]byte(line))
		got := "skip"
		if err != nil {
			got = "error"
		} else if ok {
			got = "ok"
		}
		if got != want {
			t.Errorf("object(%s) = %s, want %s", line, got, want)
		}
	}
}

func TestLookupLikeProject(t *testing.T) {
	dir, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	wikis := filepath.Join(dir, "wikis")
	for _, d := range []string{"app", "big", "half", "app/sweeps/b41"} {
		if err := os.MkdirAll(filepath.Join(wikis, d), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	write := func(p, s string) {
		if err := os.WriteFile(filepath.Join(wikis, p), []byte(s), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	write("app/AGENTS.md", "")
	write("app/index.md", "")
	write("big/AGENTS.md", "")
	write("big/index.md", "")
	write("big/repos.md", "- svc-a\n- svc-b \n-svc-c\n")
	write("half/AGENTS.md", "") // no index.md, so not a project
	n, err := newNames(wikis)
	if err != nil {
		t.Fatal(err)
	}
	for cwd, want := range map[string]string{
		filepath.Join(wikis, "app", "sweeps", "b41"): "app",
		filepath.Join(dir, "code", "svc-b"):          "big",
		filepath.Join(dir, "code", "svc-b", "x"):     "big",
		filepath.Join(dir, "code", "svc-c"):          "svc-c",
		filepath.Join(wikis, "half", "x"):            "x",
		wikis:                                        "wikis",
		"/":                                          "/",
	} {
		if got := n.lookup(cwd); got != want {
			t.Errorf("lookup(%s) = %q, want %q", cwd, got, want)
		}
	}
	if got := n.project(""); got != "unknown" {
		t.Errorf("project of no folder = %q, want unknown", got)
	}
}

// A failure leaves the old digest as it was, and a success replaces it whole.
func TestRunWritesWholeOrNothing(t *testing.T) {
	dir := t.TempDir()
	wikis := filepath.Join(dir, "wikis")
	sessions := filepath.Join(dir, "projects", "p")
	for _, d := range []string{wikis, sessions} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	out := filepath.Join(dir, "backfill.md")
	if err := os.WriteFile(out, []byte("old\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	o := Options{Transcripts: filepath.Join(dir, "projects"), Start: "2026-11-01", End: "2026-11-05",
		DayStarts: "04:00", Wikis: wikis, Out: out, Brain: filepath.Join(dir, "none")}
	rec := `{"type":"user","timestamp":"2026-11-03T15:00:00.000Z","cwd":"/x/demo","sessionId":"s1","message":{"role":"user","content":"hello there"}}`
	// A line that is JSON but not an object stops the Python.
	if err := os.WriteFile(filepath.Join(sessions, "a.jsonl"), []byte(rec+"\n[1]\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := Run(o); err == nil {
		t.Fatal("Run took a line the Python stops at")
	}
	if b, _ := os.ReadFile(out); string(b) != "old\n" {
		t.Fatalf("a failed run changed the digest to %q", b)
	}
	if err := os.WriteFile(filepath.Join(sessions, "a.jsonl"), []byte(rec+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	line, err := Run(o)
	if err != nil {
		t.Fatal(err)
	}
	if line != "1 project-day(s) from 1 Claude Code transcript(s) and 0 Gemini conversation(s)\n" {
		t.Errorf("Run printed %q", line)
	}
	b, _ := os.ReadFile(out)
	if !strings.Contains(string(b), "### [demo] ") || !strings.Contains(string(b), " hello there\n") {
		t.Errorf("digest = %q", b)
	}
	if st, _ := os.Stat(out); st.Mode().Perm() != 0o644 {
		t.Errorf("digest mode = %v, want the old digest's 0644", st.Mode().Perm())
	}
	if left, _ := filepath.Glob(filepath.Join(dir, ".backfill.md.tmp-*")); len(left) > 0 {
		t.Errorf("left behind %v", left)
	}
}
