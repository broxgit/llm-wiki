package pyos

import (
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"
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
		if got := Glob(c.glob).MatchString(c.name); got != c.want {
			t.Errorf("glob %q on %q = %v, Python gives %v", c.glob, c.name, got, c.want)
		}
	}
}

// Python sorts paths part by part, so "a/b" comes before "a.x/b" though "." sorts
// before "/".
func TestLessByParts(t *testing.T) {
	got := []string{"/p/a.x/b.jsonl", "/p/a/b.jsonl", "/p/a/b", "/p/B/z.jsonl", "/p/a"}
	sort.Slice(got, func(i, j int) bool { return LessByParts(got[i], got[j]) })
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
		if got := RealPath(in); got != want {
			t.Errorf("RealPath(%s) = %s, want %s", in, got, want)
		}
	}
}

// Printed by Python 3.14's os.path.dirname.
func TestPyDirname(t *testing.T) {
	cases := map[string]string{
		"a": "", "a/b": "a", "/a": "/", "/a/": "/a", "/a/b/": "/a/b", "//a": "//", "//": "//", "/": "/",
		"": "", "a//b": "a", "./x": ".", "~/x/y.md": "~/x", "a/b//": "a/b",
	}
	for in, want := range cases {
		if got := Dirname(in); got != want {
			t.Errorf("Dirname(%q) = %q, Python gives %q", in, got, want)
		}
	}
}

// Printed by Python 3.14's re.findall(r"-C\s+(\S+)", s).
func TestGitDirFlag(t *testing.T) {
	cases := map[string]string{
		"git -C /x log":      "/x",
		"git -C  ~/a -C\t/b": "~/a /b",
		"x-C /y":             "/y",
		"-C":                 "",
		"-C ":                "",
		"a -C /z b":          "/z",
		"-C /p q":            "/p",
	}
	for in, want := range cases {
		var got []string
		for _, m := range GitDirFlag.FindAllStringSubmatch(in, -1) {
			got = append(got, m[1])
		}
		if strings.Join(got, " ") != want {
			t.Errorf("dirs in %q = %v, Python gives %q", in, got, want)
		}
	}
}
