package mcp

import (
	"strings"
	"unicode"
	"unicode/utf8"
)

// The few things Python does to text that mcp/server.py's replies depend on. The two
// servers must give the same reply to the same request, so these are copied, not
// approximated.

// decode is bytes.decode("utf-8", "replace"): each run of bytes that could have started
// a character and didn't finish one becomes a single U+FFFD, and so does each byte
// that could start none. Go's own conversion gives one U+FFFD for every byte.
func decode(b []byte) string {
	if utf8.Valid(b) {
		return string(b)
	}
	var out strings.Builder
	for i := 0; i < len(b); {
		c := b[i]
		if c < 0x80 {
			out.WriteByte(c)
			i++
			continue
		}
		// How many more bytes the first one asks for, and what the next may be.
		need, lo, hi := 0, byte(0x80), byte(0xBF)
		switch {
		case c >= 0xC2 && c <= 0xDF:
			need = 1
		case c == 0xE0:
			need, lo = 2, 0xA0
		case c == 0xED:
			need, hi = 2, 0x9F
		case c >= 0xE1 && c <= 0xEF:
			need = 2
		case c == 0xF0:
			need, lo = 3, 0x90
		case c == 0xF4:
			need, hi = 3, 0x8F
		case c >= 0xF1 && c <= 0xF3:
			need = 3
		}
		n := 1
		for n <= need && i+n < len(b) && b[i+n] >= lo && b[i+n] <= hi {
			n++
			lo, hi = 0x80, 0xBF
		}
		if need > 0 && n == need+1 {
			out.Write(b[i : i+n])
		} else {
			out.WriteRune(utf8.RuneError)
		}
		i += n
	}
	return out.String()
}

// text is how Python reads bytes in text mode with errors="replace": decoded, and with
// every line end, \r\n or \r, turned into \n.
func text(b []byte) string {
	s := decode(b)
	if !strings.Contains(s, "\r") {
		return s
	}
	return strings.ReplaceAll(strings.ReplaceAll(s, "\r\n", "\n"), "\r", "\n")
}

// space is str.isspace for one character: Unicode's white space, and the four
// separators U+001C to U+001F, which Python counts and Go doesn't.
func space(r rune) bool {
	return unicode.IsSpace(r) || r >= 0x1C && r <= 0x1F
}

// strip is str.strip.
func strip(s string) string {
	return strings.TrimFunc(s, space)
}

// lastLine is s.splitlines()[-1] for text that doesn't end in a line end: what follows
// the last of the characters Python ends a line at.
func lastLine(s string) string {
	i := strings.LastIndexFunc(s, func(r rune) bool {
		switch r {
		case '\n', '\r', '\v', '\f', 0x1C, 0x1D, 0x1E, 0x85, 0x2028, 0x2029:
			return true
		}
		return false
	})
	if i < 0 {
		return s
	}
	_, size := utf8.DecodeRuneInString(s[i:])
	return s[i+size:]
}

// truthy is Python's bool() of a value read from JSON: nothing, false, zero, and an
// empty string, list or object are false. server.py writes `x or default` throughout,
// so `"path": null` and `"path": ""` both mean the default.
func truthy(v any) bool {
	switch x := v.(type) {
	case nil:
		return false
	case bool:
		return x
	case string:
		return x != ""
	case []any:
		return len(x) > 0
	case map[string]any:
		return len(x) > 0
	case interface{ Float64() (float64, error) }:
		f, err := x.Float64()
		// A number too big for a float is not zero.
		return err != nil || f != 0
	}
	return true
}
