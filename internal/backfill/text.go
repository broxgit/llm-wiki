package backfill

import (
	"strings"
	"unicode/utf8"
)

// isSpace is Python's str.isspace for one character, which takes in more than Go's
// unicode.IsSpace: the separators U+001C to U+001F count too.
func isSpace(r rune) bool {
	switch r {
	case '\t', '\n', '\v', '\f', '\r', ' ', 0x1c, 0x1d, 0x1e, 0x1f, 0x85, 0xa0, 0x1680,
		0x2028, 0x2029, 0x202f, 0x205f, 0x3000:
		return true
	}
	return r >= 0x2000 && r <= 0x200a
}

// strip is str.strip().
func strip(s string) string { return strings.TrimFunc(s, isSpace) }

// clean is the Python's clean(s, n): drop system reminders and command tags, fold
// runs of whitespace to one space, and cut to n characters, ending in "..." when cut.
func clean(s string, n int) string {
	s = strip(dropNoise(s))
	var b strings.Builder
	inSpace := false
	for _, r := range s {
		if isSpace(r) {
			if !inSpace {
				b.WriteByte(' ')
			}
			inSpace = true
			continue
		}
		inSpace = false
		b.WriteRune(r)
	}
	s = b.String()
	if utf8.RuneCountInString(s) <= n {
		return s
	}
	cut, i := 0, 0
	for i = range s {
		if cut == n-3 {
			break
		}
		cut++
	}
	return s[:i] + "..."
}

// dropNoise is re.sub(r"<(system-reminder|command-[a-z]+|local-command-[a-z]+)>.*?</\1>",
// "", s, flags=re.S). Go's regexp has no back references, so this walks the string the
// way Python's search does: at each "<" that opens one of those tags, the shortest
// stretch to its closing tag goes, and the search picks up after it.
func dropNoise(s string) string {
	var b strings.Builder
	i := 0
	for i < len(s) {
		j := strings.IndexByte(s[i:], '<')
		if j < 0 {
			break
		}
		at := i + j
		if name := noiseTag(s[at+1:]); name != "" {
			open := len(name) + 2
			if k := strings.Index(s[at+open:], "</"+name+">"); k >= 0 {
				b.WriteString(s[i:at])
				i = at + open + k + len(name) + 3
				continue
			}
		}
		b.WriteString(s[i : at+1])
		i = at + 1
	}
	b.WriteString(s[i:])
	return b.String()
}

// noiseTag is the tag name a noise tag opens with at the start of s, as far as its
// ">", or "" when s doesn't open one.
func noiseTag(s string) string {
	if strings.HasPrefix(s, "system-reminder>") {
		return "system-reminder"
	}
	for _, prefix := range []string{"command-", "local-command-"} {
		if !strings.HasPrefix(s, prefix) {
			continue
		}
		k := len(prefix)
		for k < len(s) && s[k] >= 'a' && s[k] <= 'z' {
			k++
		}
		if k > len(prefix) && k < len(s) && s[k] == '>' {
			return s[:k]
		}
	}
	return ""
}

// basename is os.path.basename: everything after the last slash.
func basename(p string) string { return p[strings.LastIndex(p, "/")+1:] }

// stem is Path(name).stem in Python 3.14, which takes no suffix from a name that is
// all dots before its last part, such as ".jsonl".
func stem(name string) string {
	rest := strings.TrimLeft(name, ".")
	i := strings.LastIndex(rest, ".")
	if i < 0 {
		return name
	}
	return name[:len(name)-len(rest)+i]
}

// splitLines is str.splitlines.
func splitLines(s string) []string {
	var out []string
	start := 0
	for i, r := range s {
		switch r {
		case '\n', '\r', '\v', '\f', 0x1c, 0x1d, 0x1e, 0x85, 0x2028, 0x2029:
		default:
			continue
		}
		if r == '\n' && i > 0 && s[i-1] == '\r' {
			start = i + 1
			continue
		}
		out = append(out, s[start:i])
		start = i + utf8.RuneLen(r)
	}
	if start < len(s) {
		out = append(out, s[start:])
	}
	return out
}
