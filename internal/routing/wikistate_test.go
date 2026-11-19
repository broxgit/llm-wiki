package routing

import (
	"os"
	"testing"
)

// WikiState has to answer as wiki.sh's is_wiki does, which the smoke test also runs
// against the same kinds of folder.
func TestWikiState(t *testing.T) {
	root := t.TempDir()
	make := func(name, agents string, index bool) string {
		dir := root + "/" + name
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
		if agents != "-" {
			if err := os.WriteFile(dir+"/AGENTS.md", []byte(agents), 0o644); err != nil {
				t.Fatal(err)
			}
		}
		if index {
			if err := os.WriteFile(dir+"/index.md", []byte("# Index\n"), 0o644); err != nil {
				t.Fatal(err)
			}
		}
		return dir
	}
	tests := []struct {
		name   string
		agents string
		index  bool
		want   int
	}{
		{"the handbook", "# AGENTS.md\n\nHandbook version 39.\n", true, Wiki},
		{"version 0, as a wiki being adopted has it", "Handbook version 0.\n", true, Wiki},
		{"windows line ends", "# AGENTS.md\r\n\r\nHandbook version 4.\r\n", true, Wiki},
		{"no final newline", "Handbook version 7", true, Wiki},
		{"a version of twenty digits", "Handbook version 12345678901234567890.\n", true, Wiki},
		{"a NUL byte before the line", "x\x00\nHandbook version 3.\n", true, Wiki},
		{"a NUL byte after the number", "Handbook version 3\x004.\n", true, Wiki},
		{"a NUL byte inside the words, where bash 3.2 ends the line", "Handbook\x00 version 3.\n", true, NotHandbook},
		{"a NUL byte in front of the words", "\x00Handbook version 5.\n", true, NotHandbook},
		{"bytes that aren't UTF-8", "caf\xe9\nHandbook version 3.\n", true, Wiki},
		{"a project's own instructions", "# AGENTS.md\n\nRun the tests before you commit.\n", true, NotHandbook},
		{"the words with no number", "Handbook version next.\n", true, NotHandbook},
		{"the words not at the start of a line", " Handbook version 3.\n", true, NotHandbook},
		{"an empty file", "", true, NotHandbook},
		{"no index", "Handbook version 3.\n", false, Missing},
		{"no handbook", "-", true, Missing},
		{"neither", "-", false, Missing},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			dir := make(tt.name, tt.agents, tt.index)
			got, err := WikiState(dir)
			if err != nil {
				t.Fatalf("WikiState: %v", err)
			}
			if got != tt.want {
				t.Errorf("WikiState = %d, want %d", got, tt.want)
			}
			ok, _ := IsWiki(dir)
			if ok != (tt.want == Wiki) {
				t.Errorf("IsWiki = %v", ok)
			}
		})
	}
	t.Run("a handbook that can't be read counts as a wiki", func(t *testing.T) {
		if os.Getuid() == 0 {
			t.Skip("root can read anything")
		}
		dir := make("closed", "Run the tests.\n", true)
		if err := os.Chmod(dir+"/AGENTS.md", 0); err != nil {
			t.Fatal(err)
		}
		got, err := WikiState(dir)
		if err != nil || got != CantTell {
			t.Errorf("WikiState = %d, %v, want CantTell", got, err)
		}
		if ok, _ := IsWiki(dir); !ok {
			t.Error("IsWiki = false")
		}
	})
}
