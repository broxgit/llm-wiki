package tokens

import (
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"
	"time"
)

// Printed by Python 3.14's fnmatch.fnmatch(name, pattern).
func TestGlobLikeFnmatch(t *testing.T) {
	cases := []struct {
		glob, name string
		want       bool
	}{
		{"llm-*", "llm-wiki", true},
		{"llm-*", "my-llm-wiki", false},
		{"*", "a/b", true},
		{"a?c", "abc", true},
		{"a?c", "ac", false},
		{"[ab]x", "bx", true},
		{"[!ab]x", "cx", true},
		{"[!ab]x", "ax", false},
		{"a[", "a[", true},
		{"personal-*", "personal-", true},
		{"*.md", "x.MD", false},
		{"a.b", "aXb", false},
		{"[]]", "]", true},
		{"wikis", "wikis", true},
		{"wik", "wikis", false},
	}
	for _, c := range cases {
		if got := globToRegexp(c.glob).MatchString(c.name); got != c.want {
			t.Errorf("glob %q on %q = %v, Python gives %v", c.glob, c.name, got, c.want)
		}
	}
}

// Python sorts paths part by part, so "a/b" comes before "a.x/b" though "." sorts
// before "/".
func TestLessByParts(t *testing.T) {
	got := []string{"/p/a.x/b.jsonl", "/p/a/b.jsonl", "/p/a/b", "/p/B/z.jsonl", "/p/a"}
	sort.Slice(got, func(i, j int) bool { return lessByParts(got[i], got[j]) })
	want := []string{"/p/B/z.jsonl", "/p/a", "/p/a/b", "/p/a/b.jsonl", "/p/a.x/b.jsonl"}
	if strings.Join(got, " ") != strings.Join(want, " ") {
		t.Errorf("order = %v, want %v", got, want)
	}
}

func TestRealPathFollowsLinksAndKeepsWhatIsMissing(t *testing.T) {
	dir, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(dir, "real", "sub"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Join(dir, "real"), filepath.Join(dir, "link")); err != nil {
		t.Fatal(err)
	}
	cases := map[string]string{
		filepath.Join(dir, "link", "sub"):             filepath.Join(dir, "real", "sub"),
		filepath.Join(dir, "link", "gone", "x.md"):    filepath.Join(dir, "real", "gone", "x.md"),
		filepath.Join(dir, "link", "sub", "..", "y"):  filepath.Join(dir, "real", "y"),
		filepath.Join(dir, "real") + "//sub/./":       filepath.Join(dir, "real", "sub"),
		filepath.Join(dir, "nothing", "here", "a.md"): filepath.Join(dir, "nothing", "here", "a.md"),
	}
	for in, want := range cases {
		if got := realPath(in); got != want {
			t.Errorf("realPath(%s) = %s, want %s", in, got, want)
		}
	}
}

func TestParseTime(t *testing.T) {
	for _, s := range []string{"2026-11-05T15:17:55.123Z", "2026-11-05T15:17:55Z", "2026-11-05T10:17:55-05:00", "2026-11-05T15:17:55.123456", "2026-11-05 15:17:55", "2026-11-05"} {
		if _, ok := parseTime(s); !ok {
			t.Errorf("parseTime(%q) failed", s)
		}
	}
	a, _ := parseTime("2026-11-05T15:17:55Z")
	b, _ := parseTime("2026-11-05T10:17:55-05:00")
	if !a.Equal(b) {
		t.Errorf("the same instant in two zones differs: %v and %v", a, b)
	}
	if _, ok := parseTime("yesterday"); ok {
		t.Error("parseTime accepted a word")
	}
	if got, _ := parseTime("2026-11-05T15:17:55"); got.Location() != time.Local {
		t.Errorf("a time with no zone should be local, got %v", got.Location())
	}
}

func TestShort(t *testing.T) {
	for n, want := range map[int64]string{0: "0", 999: "999", 1000: "1k", 1499: "1k", 1500: "2k", 2500: "2k", 999999: "1000k", 1000000: "1.0M", 1250000: "1.2M", 19152600000: "19152.6M"} {
		if got := short(n); got != want {
			t.Errorf("short(%d) = %s, want %s", n, got, want)
		}
	}
}
