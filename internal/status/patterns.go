package status

import (
	"errors"
	"regexp"
	"strconv"
	"strings"

	"github.com/broxgit/llm-wiki/internal/routing"
)

// patterns counts the entries of patterns.md that patterns_ledger flags: ready, with
// enough sightings to propose a fix, and regressed, accepted and then seen again.
// It is that awk, line by line, quirks included: an entry under a heading with no name
// is never printed, and what it gathered goes to the entry after it.
func patterns(path string) (ready, regressed int, err error) {
	ok, err := routing.IsFile(path)
	if err != nil || !ok {
		return 0, 0, err
	}
	lines, err := readLines(path)
	if err != nil {
		return 0, 0, err
	}
	var (
		name, kind, status string
		n                  int
		repos              = map[string]bool{}
		seen               []string
	)
	flush := func() error {
		if name == "" {
			return nil
		}
		flag := ""
		if strings.HasPrefix(status, "watching") && (n >= 3 || n >= 2 && (kind == "review" || len(repos) >= 2)) {
			flag = "ready"
		}
		if acceptedEntry.MatchString(status) {
			since := fields(status)[1]
			for _, s := range seen {
				later, err := after(s, since)
				if err != nil {
					return err
				}
				if later {
					flag = "regressed"
				}
			}
		}
		switch flag {
		case "ready":
			ready++
		case "regressed":
			regressed++
		}
		name, kind, status, n, repos, seen = "", "", "", 0, map[string]bool{}, nil
		return nil
	}
	for _, b := range lines {
		line := string(b)
		if strings.HasPrefix(line, "## ") {
			if err := flush(); err != nil {
				return 0, 0, err
			}
			name = line[3:]
			continue
		}
		f := fields(line)
		if strings.HasPrefix(line, "- kind:") {
			kind = field(f, 3)
		}
		if strings.HasPrefix(line, "- status:") {
			// sub() changes $0, and the patterns below then see the line without it.
			line = strings.TrimLeft(strings.TrimPrefix(line, "- status:"), " ")
			status = line
			f = fields(line)
		}
		if strings.HasPrefix(line, "- seen:") {
			c := 1
			if last := f[len(f)-1]; sightings.MatchString(last) {
				if len(last) > 10 {
					return 0, 0, errors.New("a count for the Bash: " + last)
				}
				c, _ = strconv.Atoi(last[1:])
			}
			n += c
			if r := field(f, 4); r != "-" {
				repos[r] = true
			}
			seen = append(seen, field(f, 3))
		}
	}
	if err := flush(); err != nil {
		return 0, 0, err
	}
	return ready, regressed, nil
}

var (
	acceptedEntry = regexp.MustCompile(`^accepted [0-9]`)
	sightings     = regexp.MustCompile(`^x[0-9]+$`)
	// Anything some awk might take for a number: the C library's strtod reads hex,
	// inf and nan too, and blanks around it.
	numeric = regexp.MustCompile(`(?i)^[ \t\n\v\f\r]*[+-]?(inf(inity)?|nan.*|0x[0-9a-f.]+(p[+-]?[0-9]+)?|([0-9]+\.?[0-9]*|\.[0-9]+)(e[+-]?[0-9]+)?)[ \t\n\v\f\r]*$`)
)

// after is awk's seen > since. Two values that both look like numbers are compared
// as numbers, and the awks don't agree on what looks like one, so that is the Bash's.
// Otherwise it is by byte, as under LC_ALL=C.
func after(seen, since string) (bool, error) {
	if numeric.MatchString(seen) && numeric.MatchString(since) {
		return false, errors.New("dates awk might read as numbers, for the Bash: " + seen + ", " + since)
	}
	return seen > since, nil
}

// fields is awk's default field splitting: runs of spaces and tabs.
func fields(line string) []string {
	return strings.FieldsFunc(line, func(r rune) bool { return r == ' ' || r == '\t' })
}

// field is awk's $i, which is "" past the last field.
func field(f []string, i int) string {
	if i > len(f) {
		return ""
	}
	return f[i-1]
}
