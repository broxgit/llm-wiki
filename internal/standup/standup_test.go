package standup

import "testing"

// Printed by Apple's bash 3.2 with LC_ALL=C: case "$name" in $pattern).
func TestCaseMatchLikeBash(t *testing.T) {
	cases := []struct {
		p, s string
		want bool
	}{
		{"*", "a/b/c", true},
		{"a*c", "a/b/c", true},
		{"*/c", "a/b/c", true},
		{"a/*", "a/b/c", true},
		{"?", "a", true},
		{"?", "ab", false},
		{"?", "/", true},
		{"a?c", "a/c", true},
		{"llm-*", "llm-wiki", true},
		{"llm-*", "my-llm-wiki", false},
		{"*wiki", "llm-wiki", true},
		{"*wiki*", "a-wiki-b", true},
		{"*", "", true},
		{"?", "", false},
		{"a", "a", true},
		{"a", "A", false},
		{"A*", "apple", false},
		{"*.md", ".md", true},
		{".*", ".hidden", true},
		{"*", ".hidden", true},
		{"**", "abc", true},
		{"a**c", "ac", true},
		{"*a*b*", "xxaybzb", true},
		{"*a*b", "xxaybzc", false},
		{"?*", "a", true},
		{"?*", "", false},
		{"*?", "", false},
		{"caf?", "caf\xc3\xa9", false},
		{"caf??", "caf\xc3\xa9", true},
		{"caf*", "caf\xc3\xa9", true},
	}
	for _, c := range cases {
		if got := caseMatch(c.p, c.s); got != c.want {
			t.Errorf("caseMatch(%q, %q) = %v, Bash gives %v", c.p, c.s, got, c.want)
		}
	}
}

// Brackets and backslashes are left to the Bash.
func TestFilterRefusesWhatItDoesNotMatch(t *testing.T) {
	for _, p := range []string{"[ab]*", `a\*`, "x[", "[[:alpha:]]"} {
		if _, err := newFilter(p, nil); err == nil {
			t.Errorf("--only %q was taken", p)
		}
		if _, err := newFilter("", []string{"ok", p}); err == nil {
			t.Errorf("--exclude %q was taken", p)
		}
	}
	if _, err := newFilter("a*", []string{"b?", "c"}); err != nil {
		t.Error(err)
	}
}

func TestExcluded(t *testing.T) {
	f, err := newFilter("a*", []string{"ab*", "*c"})
	if err != nil {
		t.Fatal(err)
	}
	for name, want := range map[string]bool{"ax": false, "b": true, "abx": true, "axc": true} {
		if got := f.excluded(name); got != want {
			t.Errorf("excluded(%q) = %v, want %v", name, got, want)
		}
	}
	none, _ := newFilter("", nil)
	if none.excluded("anything") {
		t.Error("no patterns should exclude nothing")
	}
}

// Printed by the expansions in wiki.sh's repo_name, on Apple's bash 3.2.
func TestRepoNameLikeBash(t *testing.T) {
	for url, want := range map[string]string{
		"git@github.com:a/b.git": "b",
		"https://x/y/z.git/":     "z",
		"https://x/y/z/":         "z",
		"foo":                    "foo",
		"host:foo.git":           "foo",
		"a.git.git":              "a.git",
	} {
		if got := repoName("/d/dir", url); got != want {
			t.Errorf("repoName(%q) = %q, Bash gives %q", url, got, want)
		}
	}
	if got := repoName("/d/dir", ""); got != "dir" {
		t.Errorf("with no remote: %q", got)
	}
}

// Printed by the expansions in cmd_standup: ${line#*[} then ${proj%%]*}.
func TestJournalProjectLikeBash(t *testing.T) {
	for line, want := range map[string]string{
		"- 10:00 [proj] did": "proj",
		"- no brackets":      "- no brackets",
		"- a]b[c]d":          "c",
		"- [x":               "x",
		"- x]":               "- x",
		"- [] y":             "",
	} {
		if got := journalProject(line); got != want {
			t.Errorf("journalProject(%q) = %q, Bash gives %q", line, got, want)
		}
	}
}
