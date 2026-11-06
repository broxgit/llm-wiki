// Package routing works out which wiki covers a repository. It answers `wiki which`:
// the wiki named after the repository, or the one whose repos.md lists it, and when
// there is none, the advice wiki.sh's which_miss gives. It prints what cmd_which
// prints, and that Bash is the fallback where this program isn't built, so the two are
// kept the same and a smoke test compares them.
//
// wiki.sh keeps the choice of collection, which every command makes before it starts,
// and passes the collection's folder. What this can't be sure of is an error, and the
// Bash answers: a folder or file it can't read, a repos.md a grep might read
// differently, two wikis that list one repository, and a name the shell would split.
package routing

import (
	"bytes"
	"errors"
	"io/fs"
	"os"
	"os/exec"
	"sort"
	"strings"
	"syscall"
	"unicode/utf8"
)

// Options are what wiki.sh has worked out by the time it asks.
type Options struct {
	Wikis   string // the collection's folder
	Home    string // $HOME, written as ~ in what is printed
	WikiCmd string // the command people type, for the advice
	Name    string // the repository, or "" for the one this runs in
}

// Which gives what `wiki which` prints, and whether a wiki covers the repository: the
// wiki's folder when one does, for stdout, and the advice when none does, for stderr.
func Which(o Options) (text string, covered bool, err error) {
	name := o.Name
	if name == "" {
		if name, err = here(); err != nil {
			return "", false, err
		}
	}
	// Bash's echo reads a backslash differently when it runs as sh, and a grep takes a
	// pattern with a line break as two.
	if name == "" || strings.ContainsAny(name, "\n\\") || strings.Contains(o.WikiCmd, `\`) || !utf8.ValidString(name) {
		return "", false, errors.New("a name for the Bash")
	}
	// The wiki named after it, which the Bash finds without looking at any other.
	w := name
	if ok, err := isWiki(o.Wikis + "/" + name); err != nil {
		return "", false, err
	} else if !ok {
		wikis, err := wikiNames(o.Wikis)
		if err != nil {
			return "", false, err
		}
		if w, err = listedIn(o.Wikis, name, wikis); err != nil {
			return "", false, err
		}
		if w == "" {
			text, err = miss(o, name, wikis)
			return text, false, err
		}
	}
	return tilde(o.Home, o.Wikis+"/"+w) + "\n", true, nil
}

// listedIn is the second half of wiki.sh's which_wiki: the wiki whose repos.md lists a
// repository, or "" when none does.
func listedIn(root, name string, wikis []string) (string, error) {
	var found []string
	for _, w := range wikis {
		repos := root + "/" + w + "/repos.md"
		if ok, err := isFile(repos); err != nil {
			return "", err
		} else if !ok {
			continue
		}
		data, err := os.ReadFile(repos)
		if err != nil {
			return "", err
		}
		// grep -x -F compares whole lines. A file it would call binary is the Bash's.
		if !utf8.Valid(data) || bytes.IndexByte(data, 0) >= 0 {
			return "", errors.New("not plain text: " + repos)
		}
		for _, line := range strings.Split(string(data), "\n") {
			if line == "- "+name {
				found = append(found, w)
				break
			}
		}
	}
	// The Bash takes the first in the shell's order, which follows the locale.
	if len(found) > 1 {
		return "", errors.New("more than one wiki lists " + name)
	}
	if len(found) == 1 {
		return found[0], nil
	}
	return "", nil
}

// miss is wiki.sh's which_miss: that nothing covers the repository, and the likely fix.
func miss(o Options, name string, wikis []string) (string, error) {
	// The words of the name, as tr -c 'A-Za-z0-9\n' ' ' and the shell's splitting leave them.
	words := strings.FieldsFunc(name, func(r rune) bool {
		return !(r >= 'A' && r <= 'Z' || r >= 'a' && r <= 'z' || r >= '0' && r <= '9')
	})
	var hits []string
	for _, w := range wikis {
		hit := false
		// Shares a word of three letters or more, or its index mentions the repository.
		for _, t := range words {
			if len(t) >= 3 && strings.Contains("-"+w+"-", t) {
				hit = true
				break
			}
		}
		if !hit {
			index, err := os.ReadFile(o.Wikis + "/" + w + "/index.md")
			if err != nil {
				return "", err
			}
			// grep -i -F under LC_ALL=C: letters of ASCII only, whatever the case.
			hit = bytes.Contains(lower(index), lower([]byte(name)))
		}
		if hit {
			// The Bash leaves its list unquoted, so the shell splits and expands a name.
			if !validName(w) {
				return "", errors.New("a wiki's name for the Bash: " + w)
			}
			hits = append(hits, w)
		}
	}
	var b strings.Builder
	b.WriteString("no wiki covers " + name + "\n")
	if len(hits) > 0 {
		// sort -u | head -n 5, whose first line is the empty one before the first name.
		sort.Strings(hits)
		if len(hits) > 4 {
			hits = hits[:4]
		}
		b.WriteString("Close matches: " + strings.Join(hits, " ") + "\n")
		b.WriteString("If " + name + " belongs to one of them: " + o.WikiCmd + " cover <wiki> " + name + "\n")
	}
	b.WriteString("If it's a project of its own, the first session with something to file creates its wiki: " + o.WikiCmd + " new " + name + "\n")
	return b.String(), nil
}

// wikiNames is the wikis of a collection, as the shell's "$WIKIS_DIR"/*/ and is_wiki
// find them: folders, or links to folders, whose names don't start with a dot. They
// come sorted by byte, which is the shell's order only under LC_ALL=C, so nothing here
// may depend on the order.
func wikiNames(root string) ([]string, error) {
	entries, err := os.ReadDir(root)
	if err != nil {
		if errors.Is(err, fs.ErrNotExist) {
			return nil, nil
		}
		return nil, err
	}
	var names []string
	for _, e := range entries {
		if strings.HasPrefix(e.Name(), ".") {
			continue
		}
		dir := root + "/" + e.Name()
		if !e.IsDir() {
			if e.Type()&fs.ModeSymlink == 0 {
				continue
			}
			st, err := os.Stat(dir)
			if notThere(err) || err == nil && !st.IsDir() {
				continue
			}
			if err != nil {
				return nil, err
			}
		}
		ok, err := isWiki(dir)
		if err != nil {
			return nil, err
		}
		if ok {
			names = append(names, e.Name())
		}
	}
	return names, nil
}

// isWiki is wiki.sh's is_wiki.
func isWiki(dir string) (bool, error) {
	if ok, err := isFile(dir + "/AGENTS.md"); err != nil || !ok {
		return false, err
	}
	return isFile(dir + "/index.md")
}

// isFile is the shell's [ -f path ], except that the shell calls a file it isn't
// allowed to look at missing. Here that is an error, so the Bash says what it says.
func isFile(path string) (bool, error) {
	st, err := os.Stat(path)
	if notThere(err) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return st.Mode().IsRegular(), nil
}

func notThere(err error) bool {
	return errors.Is(err, fs.ErrNotExist) || errors.Is(err, syscall.ENOTDIR)
}

// validName is wiki.sh's valid_name, without its rule for the first character.
func validName(s string) bool {
	for i := 0; i < len(s); i++ {
		c := s[i]
		if !(c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '.' || c == '_' || c == '-') {
			return false
		}
	}
	return s != ""
}

// lower lowers the letters of ASCII and leaves every other byte alone.
func lower(b []byte) []byte {
	out := make([]byte, len(b))
	for i, c := range b {
		if c >= 'A' && c <= 'Z' {
			c += 'a' - 'A'
		}
		out[i] = c
	}
	return out
}

// tilde is wiki.sh's tilde: the path with the home folder written as ~.
func tilde(home, p string) string {
	if rest, ok := strings.CutPrefix(p, home+"/"); ok {
		return "~/" + rest
	}
	return p
}

// here names the repository this process runs in, as `wiki which` does with no name:
// the top of the work tree, then repo_name. Outside a repository it is an error, and
// the Bash says so.
func here() (string, error) {
	top, err := git("", "rev-parse", "--show-toplevel")
	if err != nil {
		return "", err
	}
	if top == "" {
		return "", errors.New("git named no work tree")
	}
	url, err := git(top, "config", "--get", "remote.origin.url")
	var exit *exec.ExitError
	if errors.As(err, &exit) && exit.ExitCode() == 1 {
		url, err = "", nil // no such remote
	}
	if err != nil {
		return "", err
	}
	return RepoName(top, url), nil
}

// git runs one git command, in a folder when one is named, and gives its output as
// $( ) would: without the line ends at its end.
func git(dir string, args ...string) (string, error) {
	if dir != "" {
		args = append([]string{"-C", dir}, args...)
	}
	out, err := exec.Command("git", args...).Output()
	return strings.TrimRight(string(out), "\n"), err
}

// RepoName is wiki.sh's repo_name: the last part of a repository's remote URL, without
// .git, or its folder's name when it has no remote.
func RepoName(dir, url string) string {
	if url == "" {
		return dir[strings.LastIndex(dir, "/")+1:]
	}
	url = strings.TrimSuffix(url, "/")
	url = url[strings.LastIndex(url, "/")+1:]
	url = url[strings.LastIndex(url, ":")+1:]
	return strings.TrimSuffix(url, ".git")
}
