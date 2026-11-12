package status

import (
	"errors"
	"os"
	"strings"

	"github.com/broxgit/llm-wiki/internal/routing"
)

// pending is `pending_files | wc -l`: how many notes in raw/ no compile has recorded.
// A note is compiled once log.md names it in a "- source: raw/" line, a page lists it
// on its sources: line, or wiki/sources has a summary page of its name. Names are
// compared without their extension. A raw/ or wiki/sources the Bash can't list is a
// "?" in its table, so here it is an error.
func pending(dir string) (int, error) {
	names, err := PendingNames(dir)
	return len(names), err
}

// PendingNames is pending_files: the names of the files in raw/ no compile has
// recorded, as the folder lists them. `wiki find` searches them, so that a note is
// found before it is compiled.
func PendingNames(dir string) ([]string, error) {
	done, err := compiled(dir)
	if err != nil {
		return nil, err
	}
	entries, err := readDir(dir + "/raw")
	if err != nil {
		return nil, err
	}
	var names []string
	for _, name := range entries {
		// The glob's * leaves out hidden names, and so does the case after it.
		if strings.HasPrefix(name, ".") {
			continue
		}
		// [ -f ] follows a link.
		if ok, err := routing.IsFile(dir + "/raw/" + name); err != nil {
			return nil, err
		} else if !ok {
			continue
		}
		// awk's sub(/\.[^.]*$/, ""): the last extension, whatever it is.
		stem := name
		if i := strings.LastIndexByte(name, '.'); i >= 0 {
			stem = name[:i]
		}
		if !done[stem] {
			names = append(names, name)
		}
	}
	return names, nil
}

// compiled is compiled_stems: the names of the notes already compiled.
func compiled(dir string) (map[string]bool, error) {
	done := map[string]bool{}
	add := func(stem string) error {
		// The awk after it reads this line as the end of the list.
		if stem == "//raw//" {
			return errors.New("a source for the Bash: " + stem)
		}
		done[stem] = true
		return nil
	}
	// sed -n 's#^- source: raw/##p' log.md, which is missing without an error.
	if ok, err := routing.IsFile(dir + "/log.md"); err != nil {
		return nil, err
	} else if ok {
		lines, err := readLines(dir + "/log.md")
		if err != nil {
			return nil, err
		}
		for _, line := range lines {
			if rest, ok := strings.CutPrefix(string(line), "- source: raw/"); ok {
				if err := add(stem(rest)); err != nil {
					return nil, err
				}
			}
		}
	}
	pages, sources, err := wikiFolder(dir)
	if err != nil {
		return nil, err
	}
	for _, page := range pages {
		lines, err := readLines(page)
		if err != nil {
			return nil, err
		}
		// The sources: line, and the list items under it when the list is one a line,
		// which is how Obsidian rewrites it: the awk in compiled_stems.
		inList := false
		for _, line := range lines {
			if strings.HasPrefix(string(line), "sources:") {
				inList = true
			} else if !inList || !listItem(string(line)) {
				inList = false
				continue
			}
			for _, name := range rawNames(string(line)) {
				if err := add(stem(name)); err != nil {
					return nil, err
				}
			}
		}
	}
	// ls wiki/sources | sed -n 's/\.md$//p'
	for _, name := range sources {
		if !strings.HasPrefix(name, ".") && strings.HasSuffix(name, ".md") {
			if err := add(strings.TrimSuffix(name, ".md")); err != nil {
				return nil, err
			}
		}
	}
	return done, nil
}

// wikiFolder is what compiled_stems reads under wiki/: every .md file grep -r finds,
// wiki/sources included, and the names in wiki/sources. GNU's and BSD's grep -r treat
// links differently, so a link anywhere in there is the Bash's.
func wikiFolder(dir string) (pages, sources []string, err error) {
	st, err := os.Lstat(dir + "/wiki")
	if routing.NotThere(err) {
		return nil, nil, nil
	}
	if err != nil {
		return nil, nil, err
	}
	if !st.IsDir() {
		return nil, nil, errors.New("not a folder, for the Bash: " + dir + "/wiki")
	}
	if err := pagesUnder(dir+"/wiki", &pages); err != nil {
		return nil, nil, err
	}
	if st, err := os.Lstat(dir + "/wiki/sources"); err == nil && st.IsDir() {
		if sources, err = readDir(dir + "/wiki/sources"); err != nil {
			return nil, nil, err
		}
	} else if err != nil && !routing.NotThere(err) {
		return nil, nil, err
	}
	return pages, sources, nil
}

// pagesUnder adds the files grep -r --include='*.md' reads under a folder.
func pagesUnder(dir string, pages *[]string) error {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return err
	}
	for _, e := range entries {
		path := dir + "/" + e.Name()
		switch {
		case e.IsDir():
			if err := pagesUnder(path, pages); err != nil {
				return err
			}
		case e.Type().IsRegular():
			if strings.HasSuffix(e.Name(), ".md") {
				*pages = append(*pages, path)
			}
		default:
			// A link, a pipe or a device: the greps don't agree on all of them.
			return errors.New("not a file or a folder, for the Bash: " + path)
		}
	}
	return nil
}

// readDir is the names in a folder, or none when it isn't there or isn't a folder, as
// a glob over it gives. One the shell can't list is an error. So is a name with a line
// break, which ls and the loop over the glob would read as two.
func readDir(dir string) ([]string, error) {
	st, err := os.Stat(dir)
	if routing.NotThere(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	if !st.IsDir() {
		return nil, nil
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	names := make([]string, 0, len(entries))
	for _, e := range entries {
		if strings.Contains(e.Name(), "\n") {
			return nil, errors.New("a name for the Bash: " + dir + "/" + e.Name())
		}
		names = append(names, e.Name())
	}
	return names, nil
}

// rawNames is grep -o 'raw/[^],"[:space:]]*' | sed 's#^raw/##' under LC_ALL=C: each
// raw/ in the line, and what follows it up to a bracket, a comma, a quote or a space.
// listItem is awk's /^[ \t]*- /.
func listItem(line string) bool {
	return strings.HasPrefix(strings.TrimLeft(line, " \t"), "- ")
}

func rawNames(line string) []string {
	var names []string
	for {
		i := strings.Index(line, "raw/")
		if i < 0 {
			return names
		}
		line = line[i+len("raw/"):]
		end := strings.IndexAny(line, "],\" \t\n\v\f\r")
		if end < 0 {
			end = len(line)
		}
		names = append(names, line[:end])
		line = line[end:]
	}
}

// stem is sed 's/\.[A-Za-z0-9]*$//' under LC_ALL=C: the name without an extension of
// ASCII letters and digits.
func stem(name string) string {
	i := strings.LastIndexByte(name, '.')
	if i < 0 {
		return name
	}
	for _, c := range []byte(name[i+1:]) {
		if !(c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' || c >= '0' && c <= '9') {
			return name
		}
	}
	return name[:i]
}
