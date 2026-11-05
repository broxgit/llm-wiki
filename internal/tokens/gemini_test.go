package tokens

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// Printed by the Python's day_of under TZ=America/New_York. Across a clock change the
// day's start comes off in the offset in force at the moment itself.
func TestGeminiDay(t *testing.T) {
	ny, err := time.LoadLocation("America/New_York")
	if err != nil {
		t.Skip("no time zone data")
	}
	old := time.Local
	time.Local = ny
	defer func() { time.Local = old }()
	four := 4 * time.Hour
	cases := []struct {
		ts    string
		shift time.Duration
		want  string
	}{
		{"2026-11-01T08:30:00Z", four, "2026-10-31"},
		{"2026-11-01T07:30:00Z", four, "2026-10-31"},
		{"2026-11-05T15:17:55Z", four, "2026-11-05"},
		{"2026-11-05T03:59:59.123-05:00", four, "2026-11-04"},
		{"2026-03-08T08:30:00Z", four, "2026-03-08"},
		{"2026-11-05T08:59:59.000123Z", four, "2026-11-04"},
		{"2026-11-01T08:30:00Z", 0, "2026-11-01"},
	}
	for _, c := range cases {
		got, err := geminiDay(c.ts, c.shift)
		if err != nil || got != c.want {
			t.Errorf("geminiDay(%q) = %q, %v; Python gives %s", c.ts, got, err, c.want)
		}
	}
}

// What the Python might read differently, or stop at, is an error, so wiki.sh runs it.
func TestOddInputIsLeftToThePython(t *testing.T) {
	for _, line := range []string{
		`[1]`, `null`, `3`, `"text"`,
		`{"created_at":5}`,
		`{"created_at":"yesterday"}`,
		`{"created_at":"2026-11-05T15:17:55"}`,
		`{"created_at":"2026-11-05T15:17:55.1234Z"}`,
		`{"input_tokens":1.5}`,
		`{"input_tokens":"3"}`,
		`{"output_tokens":true}`,
		`{"cache_read_tokens":99999999999999999999}`,
		`{"content":["a"]}`,
		`{"content":{"a":1}}`,
		`{"tool_calls":{"a":1}}`,
		`{"tool_calls":[1]}`,
		`{"tool_calls":[{"args":[1]}]}`,
		`{"tool_calls":[{"args":{"Path":3}}]}`,
		`{"tool_calls":[{"args":{"CommandLine":3}}]}`,
		`{"tool_calls":[{"args":{"Path":"~nobody/x"}}]}`,
		`{"tool_calls":[{"args":{"CommandLine":"git -C ~nobody log"}}]}`,
	} {
		if _, err := geminiParse(line, 0); err == nil {
			t.Errorf("%s was read, not left to the Python", line)
		}
	}
	for _, line := range []string{
		`{}`,
		`{"created_at":null,"content":null,"tool_calls":null,"input_tokens":null}`,
		`{"created_at":"","content":"","tool_calls":[]}`,
		`{"tool_calls":[{"name":3}]}`,
		`{"tool_calls":[{"args":null}]}`,
		`{"tool_calls":[{"args":{"Path":"","CommandLine":null}}]}`,
	} {
		if _, err := geminiParse(line, 0); err != nil {
			t.Errorf("%s should be read: %v", line, err)
		}
	}
}

// A character is a code point: Python's len counts an emoji written as a surrogate pair
// once, and an unpaired surrogate once.
func TestGeminiContentSize(t *testing.T) {
	for line, want := range map[string]int{
		`{"content":"héllo"}`:        5,
		`{"content":"😀x"}`:           2,
		`{"content":"\ud800"}`:       1,
		`{"content":"\ud800\ud800"}`: 2,
		`{"content":"é"}`:            1,
	} {
		st, err := geminiParse(line, 0)
		if err != nil || st.size != want {
			t.Errorf("size of %s = %d, %v; Python gives %d", line, st.size, err, want)
		}
	}
}

func TestGeminiReadSplitsLinesAsPythonDoes(t *testing.T) {
	f := filepath.Join(t.TempDir(), "t.jsonl")
	body := "{\"content\":\"a\"}\r\n\nnot json\r{\"content\":\"bb\"}\r{\"content\":\"ccc\"}"
	if err := os.WriteFile(f, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
	steps, err := geminiRead(f, 0)
	if err != nil {
		t.Fatal(err)
	}
	if len(steps) != 3 || steps[0].size != 1 || steps[1].size != 2 || steps[2].size != 3 {
		t.Errorf("steps = %+v", steps)
	}
	for name, bad := range map[string]string{"bad bytes": "{\"content\":\"\xff\"}\n", "NaN": "{\"input_tokens\":NaN}\n", "Infinity": "{\"x\":-Infinity}\n"} {
		if err := os.WriteFile(f, []byte(bad), 0o600); err != nil {
			t.Fatal(err)
		}
		if _, err := geminiRead(f, 0); err == nil {
			t.Errorf("%s was read, not left to the Python", name)
		}
	}
}

// Fields are read by their exact names, unlike a struct, and a repeated one's last wins.
func TestJSONObjectExactNames(t *testing.T) {
	m, err := jsonObject(json.RawMessage(`{"Input_Tokens":9,"input_tokens":1,"input_tokens":2}`))
	if err != nil {
		t.Fatal(err)
	}
	if n, _ := geminiCount(m["input_tokens"]); n != 2 {
		t.Errorf("input_tokens = %d, Python gives 2", n)
	}
}

func TestLookupPath(t *testing.T) {
	dir, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	wikis := filepath.Join(dir, "wikis")
	for _, d := range []string{"demo/wiki", "notawiki", "plain"} {
		if err := os.MkdirAll(filepath.Join(wikis, d), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(filepath.Join(wikis, "demo", "AGENTS.md"), nil, 0o600); err != nil {
		t.Fatal(err)
	}
	p, err := newProjects(wikis)
	if err != nil {
		t.Fatal(err)
	}
	for d, want := range map[string]string{
		wikis:                                "wikis",
		filepath.Join(wikis, "demo", "wiki"): "demo",
		filepath.Join(wikis, "notawiki"):     "wikis",
		filepath.Join(wikis, "gone", "x"):    "wikis",
		filepath.Join(dir, "no", "such"):     "",
		dir:                                  "",
	} {
		if got := p.lookupPath(d); got != want {
			t.Errorf("lookupPath(%s) = %q, want %q", d, got, want)
		}
	}
}
