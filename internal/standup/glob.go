package standup

import (
	"errors"
	"strings"
)

// filter is wiki.sh's excluded: --only, when given, and the patterns to leave out.
type filter struct {
	only    string
	exclude []string
}

// newFilter refuses a pattern with a bracket or a backslash. Bash's rules for those are
// long, these patterns are rare, and the Bash takes them when this fails.
func newFilter(only string, exclude []string) (*filter, error) {
	for _, p := range append([]string{only}, exclude...) {
		if strings.ContainsAny(p, `[\`) {
			return nil, errors.New("a pattern for the Bash: " + p)
		}
	}
	return &filter{only: only, exclude: exclude}, nil
}

func (f *filter) excluded(name string) bool {
	if f.only != "" && !caseMatch(f.only, name) {
		return true
	}
	for _, p := range f.exclude {
		if caseMatch(p, name) {
			return true
		}
	}
	return false
}

// caseMatch is Bash's case pattern under LC_ALL=C, which cmd_standup sets, for patterns
// newFilter lets through: * matches anything, slashes and a leading dot included, and ?
// one byte.
func caseMatch(p, s string) bool {
	star, mark := -1, 0
	pi, si := 0, 0
	for si < len(s) {
		switch {
		case pi < len(p) && p[pi] == '*':
			star, mark = pi, si
			pi++
		case pi < len(p) && (p[pi] == '?' || p[pi] == s[si]):
			pi++
			si++
		case star >= 0:
			mark++
			si = mark
			pi = star + 1
		default:
			return false
		}
	}
	return strings.Trim(p[pi:], "*") == ""
}
