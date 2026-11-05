package tokens

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// expandUser is os.path.expanduser for the forms transcripts hold: ~ and ~/path.
func expandUser(p string) string {
	if p == "~" || strings.HasPrefix(p, "~/") {
		if home, err := os.UserHomeDir(); err == nil {
			return home + p[1:]
		}
	}
	return p
}

// realPath is os.path.realpath as Python does it when the path may not exist: each
// part that is a symlink is followed, a part that doesn't exist is kept as written,
// and ".." drops the last part of what has been resolved so far.
func realPath(p string) string {
	if !filepath.IsAbs(p) {
		if cwd, err := os.Getwd(); err == nil {
			p = cwd + "/" + p
		}
	}
	out, _ := joinReal("", p, map[string]string{})
	return filepath.Clean(out)
}

func joinReal(path, rest string, seen map[string]string) (string, bool) {
	if strings.HasPrefix(rest, "/") {
		rest = rest[1:]
		path = "/"
	}
	for rest != "" {
		var name string
		name, rest, _ = strings.Cut(rest, "/")
		if name == "" || name == "." {
			continue
		}
		if name == ".." {
			if path != "" {
				dir, last := filepath.Split(path)
				path = strings.TrimRight(dir, "/")
				if dir != "" && path == "" {
					path = "/"
				}
				if last == ".." {
					path = pyJoin(pyJoin(path, ".."), "..")
				}
			} else {
				path = ".."
			}
			continue
		}
		next := pyJoin(path, name)
		st, err := os.Lstat(next)
		if err != nil || st.Mode()&os.ModeSymlink == 0 {
			path = next
			continue
		}
		if done, ok := seen[next]; ok {
			if done != "" {
				path = done
				continue
			}
			// A loop of links: give back what there is.
			return pyJoin(next, rest), false
		}
		seen[next] = ""
		target, err := os.Readlink(next)
		if err != nil {
			path = next
			continue
		}
		resolved, ok := joinReal(path, target, seen)
		if !ok {
			return pyJoin(resolved, rest), false
		}
		path = resolved
		seen[next] = path
	}
	return path, true
}

// pyJoin is os.path.join for two parts.
func pyJoin(a, b string) string {
	switch {
	case strings.HasPrefix(b, "/") || a == "":
		return b
	case strings.HasSuffix(a, "/"):
		return a + b
	}
	return a + "/" + b
}

// globToRegexp turns a shell pattern into a regexp the way Python's fnmatch does:
// * matches anything, slashes included, ? one character, and [..] a set.
func globToRegexp(glob string) *regexp.Regexp {
	var b strings.Builder
	b.WriteString(`(?s)\A(?:`)
	for i := 0; i < len(glob); i++ {
		c := glob[i]
		switch c {
		case '*':
			b.WriteString(".*")
		case '?':
			b.WriteString(".")
		case '[':
			j := i + 1
			if j < len(glob) && glob[j] == '!' {
				j++
			}
			if j < len(glob) && glob[j] == ']' {
				j++
			}
			for j < len(glob) && glob[j] != ']' {
				j++
			}
			if j >= len(glob) {
				b.WriteString(`\[`)
				continue
			}
			set := strings.ReplaceAll(glob[i+1:j], `\`, `\\`)
			if strings.HasPrefix(set, "!") {
				set = "^" + set[1:]
			} else if strings.HasPrefix(set, "^") {
				set = `\` + set
			}
			b.WriteString("[" + set + "]")
			i = j
		default:
			b.WriteString(regexp.QuoteMeta(string(c)))
		}
	}
	b.WriteString(`)\z`)
	re, err := regexp.Compile(b.String())
	if err != nil {
		return regexp.MustCompile(`\A` + regexp.QuoteMeta(glob) + `\z`)
	}
	return re
}

// lessByParts orders two paths as Python orders Path objects: part by part.
func lessByParts(a, b string) bool {
	pa, pb := strings.Split(a, "/"), strings.Split(b, "/")
	for i := 0; i < len(pa) && i < len(pb); i++ {
		if pa[i] != pb[i] {
			return pa[i] < pb[i]
		}
	}
	return len(pa) < len(pb)
}
