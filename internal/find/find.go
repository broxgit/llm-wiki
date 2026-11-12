// Package find searches a collection's wikis for a word. It answers `wiki find`: for
// each wiki, the lines of its index that mention the word, then the pages whose text
// mentions it and whose index line doesn't, then the notes in raw/ that mention it and
// aren't compiled yet. It prints what find_search in wiki.sh
// prints, and that Bash is the fallback where this program isn't built, so the two are
// kept the same and a smoke test compares them.
//
// The Bash runs its grep, awk, sed, cut and sort under LC_ALL=C, so everything here is
// by byte: only the letters of ASCII match whatever their case, an excerpt is cut at a
// byte and then loses a UTF-8 character the cut left unfinished, and the order is byte
// order. What this can't be sure of is an error, and the
// Bash answers: a folder or file it can't read, a word awk or grep would read
// differently, a file with a NUL byte, and a link under wiki/.
package find

import (
	"bytes"
	"errors"
	"io/fs"
	"os"
	"sort"
	"strings"

	"github.com/broxgit/llm-wiki/internal/routing"
	"github.com/broxgit/llm-wiki/internal/status"
)

const (
	maxPages   = 5   // FIND_PAGES in wiki.sh: the pages shown for one wiki
	excerptLen = 120 // cut -c 1-120: the bytes shown of a page's line
)

// Options are what wiki.sh has worked out by the time it asks.
type Options struct {
	Wikis string // the collection's folder
	Word  string // what to look for
}

// Search gives what `wiki find` prints, and the first wiki with a result, which is the
// one wiki.sh logs the search against. With no result anywhere, first is "".
func Search(o Options) (text, first string, err error) {
	// awk -v reads a backslash as the start of an escape, and grep takes a word with a
	// line break as two.
	if o.Word == "" || strings.ContainsAny(o.Word, "\n\\\x00") {
		return "", "", errors.New("a word for the Bash")
	}
	word := routing.Lower([]byte(o.Word))
	names, err := routing.Folders(o.Wikis)
	if err != nil {
		return "", "", err
	}
	var b strings.Builder
	for _, name := range names {
		dir := o.Wikis + "/" + name
		if ok, err := routing.IsFile(dir + "/index.md"); err != nil {
			return "", "", err
		} else if !ok {
			continue
		}
		// Bash's echo reads a backslash differently when it runs as sh.
		if strings.ContainsAny(name, "\n\\") {
			return "", "", errors.New("a wiki's name for the Bash: " + name)
		}
		hits, err := indexHits(dir+"/index.md", word)
		if err != nil {
			return "", "", err
		}
		pages, err := pageHits(dir, word, hits)
		if err != nil {
			return "", "", err
		}
		notes, err := noteHits(dir, word)
		if err != nil {
			return "", "", err
		}
		if len(hits) == 0 && len(pages) == 0 && len(notes) == 0 {
			continue
		}
		if first == "" {
			first = name
		}
		b.WriteString(name + ":\n")
		for _, line := range hits {
			b.WriteString("  " + line + "\n")
		}
		if len(pages) > 0 {
			b.WriteString("  also in pages:\n")
			for _, line := range pages {
				b.WriteString("    " + line + "\n")
			}
		}
		if len(notes) > 0 {
			b.WriteString("  waiting to be compiled:\n")
			for _, line := range notes {
				b.WriteString("    " + line + "\n")
			}
		}
	}
	if first == "" {
		return "no mentions in any index or page: " + o.Word + "\n", "", nil
	}
	return b.String(), first, nil
}

// indexHits is grep -v '^#' | grep -i -F on an index: its lines that mention the word,
// headings like "# Index" and "## Concepts" aside.
func indexHits(path string, word []byte) ([]string, error) {
	lines, err := readLines(path)
	if err != nil {
		return nil, err
	}
	var hits []string
	for _, line := range lines {
		if !bytes.HasPrefix(line, []byte("#")) && mentions(line, word) {
			hits = append(hits, string(line))
		}
	}
	return hits, nil
}

// pageHits is the "also in pages" lines of one wiki: for the first few pages under
// wiki/ that mention the word, in the order of their paths, "<path>: <the line>". A
// page an index hit already names is left out, and so is one that mentions the word
// only in its frontmatter. Neither counts toward the few.
func pageHits(dir string, word []byte, hits []string) ([]string, error) {
	// The shell's [ -d ] follows a link and the two greps then differ: GNU's reads a
	// folder named on its command line through a link, and BSD's doesn't.
	st, err := os.Lstat(dir + "/wiki")
	if routing.NotThere(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	if st.Mode()&fs.ModeSymlink != 0 {
		return nil, errors.New("a link for the Bash: " + dir + "/wiki")
	}
	if !st.IsDir() {
		return nil, nil
	}
	var paths []string
	if err := pagesUnder(dir, "wiki", &paths); err != nil {
		return nil, err
	}
	// sort under LC_ALL=C, on whole paths: wiki/a-b/x.md comes before wiki/a/x.md.
	sort.Strings(paths)
	shown := strings.Join(hits, "\n")
	var out []string
	for _, rel := range paths {
		// The Bash takes a line from no page after its fifth, so none is read here.
		if len(out) == maxPages {
			break
		}
		if strings.Contains(shown, "("+rel+")") {
			continue
		}
		lines, err := readLines(dir + "/" + rel)
		if err != nil {
			return nil, err
		}
		if line := excerpt(lines, word); line != "" {
			out = append(out, rel+": "+line)
		}
	}
	return out, nil
}

// noteHits is the "waiting to be compiled" lines of one wiki: for the newest few notes
// in raw/ that no compile has recorded and that mention the word, "raw/<name>: <the
// line>". A note is saved the moment something is learned and compiled later, and one
// nobody compiles would otherwise never be found again. Only .md notes are read: raw/
// also holds PDFs and the like. Newest first is by name, which starts with the date.
func noteHits(dir string, word []byte) ([]string, error) {
	// The notes that mention the word, before asking which are compiled: that reads
	// every page of the wiki, and most searches find no note at all.
	entries, err := os.ReadDir(dir + "/raw")
	if routing.NotThere(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	type hit struct{ name, line string }
	var found []hit
	for _, e := range entries {
		name := e.Name()
		// The glob raw/*.md leaves out hidden names.
		if strings.HasPrefix(name, ".") || !strings.HasSuffix(name, ".md") {
			continue
		}
		if strings.Contains(name, "\n") {
			return nil, errors.New("a note's name for the Bash: " + name)
		}
		if ok, err := routing.IsFile(dir + "/raw/" + name); err != nil {
			return nil, err
		} else if !ok {
			continue
		}
		lines, err := readLines(dir + "/raw/" + name)
		if err != nil {
			return nil, err
		}
		if line := excerpt(lines, word); line != "" {
			found = append(found, hit{name, line})
		}
	}
	if len(found) == 0 {
		return nil, nil
	}
	names, err := status.PendingNames(dir)
	if err != nil {
		return nil, err
	}
	waiting := map[string]bool{}
	for _, name := range names {
		waiting[name] = true
	}
	// sort -r under LC_ALL=C.
	sort.Slice(found, func(i, j int) bool { return found[i].name > found[j].name })
	var out []string
	for _, h := range found {
		if len(out) == maxPages {
			break
		}
		if waiting[h.name] {
			out = append(out, "raw/"+h.name+": "+h.line)
		}
	}
	return out, nil
}

// pagesUnder adds the pages grep -r --include='*.md' --exclude-dir=sources would read
// under a folder, as paths from the wiki's root. Hidden files and folders count.
func pagesUnder(root, rel string, paths *[]string) error {
	entries, err := os.ReadDir(root + "/" + rel)
	if err != nil {
		return err
	}
	for _, e := range entries {
		name := rel + "/" + e.Name()
		switch {
		case strings.Contains(e.Name(), "\n"):
			return errors.New("a file's name for the Bash: " + name)
		case e.IsDir():
			if e.Name() == "sources" {
				continue
			}
			if err := pagesUnder(root, name, paths); err != nil {
				return err
			}
		case e.Type().IsRegular():
			if strings.HasSuffix(e.Name(), ".md") {
				*paths = append(*paths, name)
			}
		default:
			// A link, a pipe or a device: the greps don't agree on all of them.
			return errors.New("not a file or a folder: " + name)
		}
	}
	return nil
}

// excerpt is the awk, sed and cut of find_search: the first line outside the
// frontmatter that mentions the word, without the space it starts with, cut to 120
// bytes and never inside a character. It is "" when no line does, or when nothing of
// the line is left.
func excerpt(lines [][]byte, word []byte) string {
	frontmatter := false
	for i, line := range lines {
		rule := string(line) == "---"
		switch {
		case i == 0 && rule:
			frontmatter = true
		case frontmatter && rule:
			frontmatter = false
		case !frontmatter && mentions(line, word):
			// sed's [[:space:]] under LC_ALL=C.
			line = bytes.TrimLeft(line, " \t\n\v\f\r")
			if len(line) > excerptLen {
				line = line[:excerptLen]
			}
			return string(Whole(line))
		}
	}
	return ""
}

// Whole is the sed of FIND_CUT in wiki.sh: the text without the start of a UTF-8
// character at its end, which is what a cut at a byte leaves of one. It goes by byte,
// as that sed does under LC_ALL=C: a first byte of a character of two, three or four
// bytes, followed to the end by fewer bytes than it needs. Text that isn't UTF-8 gets
// the same, so a Latin-1 letter at the end of a line goes too.
func Whole(text []byte) []byte {
	// At most one end fits: a longer one would need the shorter one's first byte to
	// continue a character, and it starts one.
	for n := 3; n >= 1; n-- {
		if len(text) < n {
			continue
		}
		end := text[len(text)-n:]
		var needs int
		switch c := end[0]; {
		case c >= 0xC0 && c <= 0xDF:
			needs = 2
		case c >= 0xE0 && c <= 0xEF:
			needs = 3
		case c >= 0xF0 && c <= 0xF7:
			needs = 4
		}
		if n >= needs {
			continue
		}
		rest := true
		for _, c := range end[1:] {
			rest = rest && c >= 0x80 && c <= 0xBF
		}
		if rest {
			return text[:len(text)-n]
		}
	}
	return text
}

// mentions is grep -i -F, and awk's index of two tolowers, under LC_ALL=C. The word
// comes lowered already.
func mentions(line, word []byte) bool {
	return bytes.Contains(routing.Lower(line), word)
}

// readLines reads a file as grep and awk see it: lines that end at a line feed. A file
// with a NUL byte is one grep calls binary and awk cuts short, so it is the Bash's.
func readLines(path string) ([][]byte, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	if bytes.IndexByte(data, 0) >= 0 {
		return nil, errors.New("not plain text: " + path)
	}
	return bytes.Split(data, []byte("\n")), nil
}
