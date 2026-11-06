package find

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"unicode/utf8"
)

func write(t *testing.T, path, text string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(text), 0o644); err != nil {
		t.Fatal(err)
	}
}

// collection makes two wikis and a folder with no index: demo, whose index names one
// page, and zeta, which mentions the word only in a page.
func collection(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	write(t, root+"/demo/index.md", "# Index\n\n## Canary pages\n- [Deploy flow](wiki/howto/deploy.md): canary first, then the rest\n- [Other](wiki/other.md): nothing here")
	write(t, root+"/demo/wiki/howto/deploy.md", "---\ntitle: Deploy\n---\nThe canary goes first.\n")
	write(t, root+"/demo/wiki/other.md", "---\ntitle: Canary in the title only\n---\nNo mention.\n")
	write(t, root+"/demo/wiki/notes.md", "# Notes\n\n  \t The CANARY host is canary-1.\n")
	write(t, root+"/zeta/index.md", "# Index\n")
	write(t, root+"/zeta/wiki/a.md", "A canary here.\n")
	write(t, root+"/stray/readme.md", "canary, but no index\n")
	write(t, root+"/.hidden/index.md", "- canary in a hidden folder\n")
	write(t, root+"/stats.csv", "canary\n")
	return root
}

func TestSearch(t *testing.T) {
	root := collection(t)
	got, first, err := Search(Options{Wikis: root, Word: "Canary"})
	want := "demo:\n" +
		"  - [Deploy flow](wiki/howto/deploy.md): canary first, then the rest\n" +
		"  also in pages:\n" +
		"    wiki/notes.md: The CANARY host is canary-1.\n" +
		"zeta:\n" +
		"  also in pages:\n" +
		"    wiki/a.md: A canary here.\n"
	if err != nil || first != "demo" || got != want {
		t.Errorf("Search = %q, %q, %v\nwant %q", got, first, err, want)
	}
}

func TestSearchNothing(t *testing.T) {
	root := collection(t)
	got, first, err := Search(Options{Wikis: root, Word: "zzz (.*) [x"})
	if err != nil || first != "" || got != "no mentions in any index or page: zzz (.*) [x\n" {
		t.Errorf("Search = %q, %q, %v", got, first, err)
	}
	// A heading of an index is not an entry.
	if got, _, _ := Search(Options{Wikis: root, Word: "Index"}); got != "no mentions in any index or page: Index\n" {
		t.Errorf("a heading: %q", got)
	}
}

// The word is a fixed string: no character of a regular expression means anything.
func TestSearchFixedString(t *testing.T) {
	root := t.TempDir()
	write(t, root+"/w/index.md", "- has a.c in it\n- has abc in it\n- costs $5 (.*) [x] ^#\n")
	for word, want := range map[string]string{
		"a.c":  "w:\n  - has a.c in it\n",
		".*":   "w:\n  - costs $5 (.*) [x] ^#\n",
		"^#":   "w:\n  - costs $5 (.*) [x] ^#\n",
		"[x]":  "w:\n  - costs $5 (.*) [x] ^#\n",
		"$5 (": "w:\n  - costs $5 (.*) [x] ^#\n",
	} {
		if got, _, err := Search(Options{Wikis: root, Word: word}); err != nil || got != want {
			t.Errorf("Search(%q) = %q, %v, want %q", word, got, err, want)
		}
	}
}

// The letters of ASCII match whatever their case, in the word and in the text, and the
// text is shown as it is written.
func TestSearchCase(t *testing.T) {
	root := t.TempDir()
	write(t, root+"/w/index.md", "- Has UPPER and Mixed Case\n")
	write(t, root+"/w/wiki/p.md", "Some SHOUTING Here\n")
	for word, want := range map[string]string{
		"upper":         "w:\n  - Has UPPER and Mixed Case\n",
		"MIXED case":    "w:\n  - Has UPPER and Mixed Case\n",
		"shouting here": "w:\n  also in pages:\n    wiki/p.md: Some SHOUTING Here\n",
	} {
		if got, _, err := Search(Options{Wikis: root, Word: word}); err != nil || got != want {
			t.Errorf("Search(%q) = %q, %v, want %q", word, got, err, want)
		}
	}
}

// Under LC_ALL=C only the letters of ASCII match whatever their case, and a byte that
// isn't UTF-8 is a byte like any other.
func TestSearchBytes(t *testing.T) {
	root := t.TempDir()
	write(t, root+"/w/index.md", "- École normale\n- caf\xe9 in Latin-1\n")
	for word, want := range map[string]string{
		"École":   "w:\n  - École normale\n",
		"éCOLE":   "no mentions in any index or page: éCOLE\n",
		"ÉCOLE":   "w:\n  - École normale\n",
		"CAF\xe9": "w:\n  - caf\xe9 in Latin-1\n",
	} {
		if got, _, err := Search(Options{Wikis: root, Word: word}); err != nil || got != want {
			t.Errorf("Search(%q) = %q, %v, want %q", word, got, err, want)
		}
	}
}

func TestPages(t *testing.T) {
	root := t.TempDir()
	write(t, root+"/w/index.md", "# Index\n")
	// The 120th byte is the second of the arrow's three.
	long := strings.Repeat("x", 112) + " word → " + strings.Repeat("y", 100)
	for path, text := range map[string]string{
		"wiki/a-b/x.md":         "word in a-b\n",
		"wiki/a/x.md":           "word in a\n",
		"wiki/.hid/h.md":        "word in a hidden folder\n",
		"wiki/.dot.md":          "\r\n\v\f word after odd space\r\n",
		"wiki/b.md":             "---\nsummary: word\n---\n---\n" + long + "\n",
		"wiki/c.md":             "---\nword: all of it is frontmatter\n",
		"wiki/d.md":             "no line end, word",
		"wiki/e.md":             "word sixth, so never shown\n",
		"wiki/sub/sources/s.md": "word under sources\n",
		"wiki/sources.md":       "word in a page named sources\n",
		"wiki/upper.MD":         "word in .MD\n",
		"wiki/notes.txt":        "word in .txt\n",
	} {
		write(t, root+"/w/"+path, text)
	}
	got, first, err := Search(Options{Wikis: root, Word: "WORD"})
	// The order is that of whole paths by byte. The long line is cut before the arrow,
	// which the 120 bytes would end inside.
	want := "w:\n  also in pages:\n" +
		"    wiki/.dot.md: word after odd space\r\n" +
		"    wiki/.hid/h.md: word in a hidden folder\n" +
		"    wiki/a-b/x.md: word in a-b\n" +
		"    wiki/a/x.md: word in a\n" +
		"    wiki/b.md: " + long[:118] + "\n"
	if err != nil || first != "w" || got != want {
		t.Errorf("Search = %q, %q, %v\nwant %q", got, first, err, want)
	}
	// A page that mentions the word only in its frontmatter doesn't count toward the five.
	got, _, err = Search(Options{Wikis: root, Word: "sixth"})
	if want := "w:\n  also in pages:\n    wiki/e.md: word sixth, so never shown\n"; err != nil || got != want {
		t.Errorf("Search(sixth) = %q, %v, want %q", got, err, want)
	}
	if got, _, _ := Search(Options{Wikis: root, Word: "frontmatter"}); got != "no mentions in any index or page: frontmatter\n" {
		t.Errorf("frontmatter that never ends: %q", got)
	}
	// A line of nothing but space is the first to mention a space, and shows nothing.
	write(t, root+"/v/index.md", "#\n")
	write(t, root+"/v/wiki/p.md", " \nreal text\n")
	if got, _, _ := Search(Options{Wikis: root + "/v/..", Word: " "}); strings.Contains(got, "v:") {
		t.Errorf("a line of space: %q", got)
	}
}

// A cut at a byte never leaves the start of a character. The cases and what they give
// are those of the sed in wiki.sh, run under LC_ALL=C with BSD sed and with GNU sed.
func TestWhole(t *testing.T) {
	for text, want := range map[string]string{
		"ab":                   "ab",
		"":                     "",
		"ab\xc3\xa9":           "ab\xc3\xa9",         // a whole character of two bytes
		"ab\xc3":               "ab",                 // its first byte
		"ab\xe2\x86\x92":       "ab\xe2\x86\x92",     // a whole one of three
		"ab\xe2\x86":           "ab",                 // two of three
		"ab\xe2":               "ab",                 // one of three
		"ab\xf0\x9f\x98\x80":   "ab\xf0\x9f\x98\x80", // a whole one of four
		"ab\xf0\x9f\x98":       "ab",                 // three of four
		"ab\xf0\x9f":           "ab",                 // two of four
		"ab\xf0":               "ab",                 // one of four
		"ab\xe2\xc3":           "ab\xe2",             // two starts: only the last goes
		"caf\xe9":              "caf",                // Latin-1, which reads as a start
		"caf\xe9 au":           "caf\xe9 au",         // and is left alone inside a line
		"ab\x86\x92":           "ab\x86\x92",         // bytes that continue nothing
		"ab\xff":               "ab\xff",             // no start of anything
		"\xe2":                 "",                   // nothing left
		"ab\xc3\xa9\xe2\x86":   "ab\xc3\xa9",         // a whole character stays before the cut one
		"\xf0\x9f\x98\x80\xf0": "\xf0\x9f\x98\x80",
	} {
		if got := string(whole([]byte(text))); got != want {
			t.Errorf("whole(%q) = %q, want %q", text, got, want)
		}
	}
}

// Wherever the 120th byte falls in a character, the excerpt of a page that is UTF-8 is
// UTF-8, and as long as it can be.
func TestExcerptIsWholeCharacters(t *testing.T) {
	for _, char := range []string{"é", "→", "😀"} {
		for at := 114; at <= 121; at++ {
			line := strings.Repeat("x", at-5) + "word " + char + strings.Repeat("y", 20)
			got := excerpt([][]byte{[]byte(line)}, []byte("word"))
			want := line[:120]
			if at < 120 && at+len(char) > 120 {
				want = line[:at]
			}
			if !utf8.ValidString(got) || got != want {
				t.Errorf("%q at byte %d: got %q, want %q", char, at, got, want)
			}
		}
	}
	// A line that is nothing but the start of a character shows nothing, like one of space.
	if got := excerpt([][]byte{[]byte("  \xe2")}, []byte("\xe2")); got != "" {
		t.Errorf("an unfinished character alone: %q", got)
	}
}

// What this can't be sure of is an error, so that the Bash answers.
func TestSearchLeavesToBash(t *testing.T) {
	for _, word := range []string{"", `back\slash`, "two\nlines"} {
		if _, _, err := Search(Options{Wikis: collection(t), Word: word}); err == nil {
			t.Errorf("Search(%q) gave no error", word)
		}
	}
	if _, _, err := Search(Options{Wikis: t.TempDir() + "/missing", Word: "canary"}); err == nil {
		t.Error("a missing collection gave no error")
	}
	breaks := map[string]func(root string) error{
		"a NUL in an index": func(root string) error { return os.WriteFile(root+"/demo/index.md", []byte("- canary\x00\n"), 0o644) },
		"a NUL in a page":   func(root string) error { return os.WriteFile(root+"/zeta/wiki/a.md", []byte("canary\x00\n"), 0o644) },
		"a linked page":     func(root string) error { return os.Symlink(root+"/stray/readme.md", root+"/zeta/wiki/link.md") },
		"a linked folder":   func(root string) error { return os.Symlink(root+"/stray", root+"/zeta/wiki/more") },
		"a linked wiki/": func(root string) error {
			if err := os.Rename(root+"/zeta/wiki", root+"/zeta-pages"); err != nil {
				return err
			}
			return os.Symlink(root+"/zeta-pages", root+"/zeta/wiki")
		},
		"a wiki's name with a backslash": func(root string) error { return os.Rename(root+"/zeta", root+`/ze\ta`) },
		"a page's name with a line break": func(root string) error {
			return os.WriteFile(root+"/zeta/wiki/two\nlines.md", []byte("canary\n"), 0o644)
		},
	}
	if os.Getuid() != 0 {
		breaks["an index that can't be read"] = func(root string) error { return os.Chmod(root+"/zeta/index.md", 0) }
		breaks["a page that can't be read"] = func(root string) error { return os.Chmod(root+"/zeta/wiki/a.md", 0) }
		breaks["a folder of pages that can't be read"] = func(root string) error { return os.Chmod(root+"/zeta/wiki", 0) }
		breaks["a wiki that can't be read"] = func(root string) error { return os.Chmod(root+"/zeta", 0) }
		breaks["a collection that can't be read"] = func(root string) error { return os.Chmod(root, 0) }
	}
	for name, breakIt := range breaks {
		root := collection(t)
		if err := breakIt(root); err != nil {
			t.Fatal(name, err)
		}
		got, _, err := Search(Options{Wikis: root, Word: "canary"})
		// So the test's folder can be removed.
		for _, p := range []string{root, root + "/zeta", root + "/zeta/wiki"} {
			os.Chmod(p, 0o755)
		}
		if err == nil {
			t.Errorf("%s: no error, and %q", name, got)
		}
	}
	// A page past the last one shown is never read, by the Bash or by this.
	root := collection(t)
	for _, name := range []string{"b", "c", "d", "e", "f"} {
		write(t, root+"/zeta/wiki/"+name+".md", "canary\n")
	}
	write(t, root+"/zeta/wiki/z.md", "canary\x00\n")
	if _, _, err := Search(Options{Wikis: root, Word: "canary"}); err != nil {
		t.Errorf("a NUL in a page past the fifth: %v", err)
	}
}
