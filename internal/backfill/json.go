package backfill

import (
	"bytes"
	"encoding/json"
	"errors"
	"strconv"
	"strings"
	"sync"
	"unicode/utf8"
)

// odd is an error for input the Python must judge: something it may read differently,
// or stop at.
func odd(what string) error { return errors.New("left to the Python: " + what) }

// lines splits a file as Python's text mode does, at \n, \r\n or \r. Bad UTF-8 Python
// replaces its own way, so a file with any is the Python's.
func lines(data []byte) ([][]byte, error) {
	if !utf8.Valid(data) {
		return nil, odd("not UTF-8")
	}
	return bytes.FieldsFunc(data, func(r rune) bool { return r == '\n' || r == '\r' }), nil
}

// object reads a line as json.loads does, into its fields exactly as named, the last
// of a repeated one. ok is false for a line json.loads refuses, which the Python skips.
// A line it reads that isn't an object is an error: the Python's r.get stops there.
func object(line []byte) (m map[string]json.RawMessage, ok bool, err error) {
	if m, err = asObject(line); err != nil {
		if json.Valid(line) {
			return nil, false, err
		}
		if bytes.Contains(line, []byte("NaN")) || bytes.Contains(line, []byte("Infinity")) {
			return nil, false, odd("NaN or Infinity, which Python's json reads")
		}
		return nil, false, nil
	}
	// encoding/json makes a lone surrogate U+FFFD. Python keeps it, and can't write it.
	if (bytes.Contains(line, []byte(`\ud`)) || bytes.Contains(line, []byte(`\uD`))) && loneSurrogate(line) {
		return nil, false, odd("a lone surrogate")
	}
	return m, true, nil
}

// eachLine runs parse on every line and keeps what it gives, in order. A long
// transcript is read in pieces side by side, since one file can be most of the work.
func eachLine[T any](ls [][]byte, parse func([]byte) (T, bool, error)) ([]T, error) {
	const chunk = 1000
	parts := make([][]T, (len(ls)+chunk-1)/chunk)
	errs := make([]error, len(parts))
	var wg sync.WaitGroup
	for c := range parts {
		wg.Add(1)
		go func(c int) {
			defer wg.Done()
			for _, line := range ls[c*chunk : min(len(ls), (c+1)*chunk)] {
				v, ok, err := parse(line)
				if err != nil {
					errs[c] = err
					return
				}
				if ok {
					parts[c] = append(parts[c], v)
				}
			}
		}(c)
	}
	wg.Wait()
	var out []T
	for c, p := range parts {
		if errs[c] != nil {
			return nil, errs[c]
		}
		out = append(out, p...)
	}
	return out, nil
}

func asObject(raw json.RawMessage) (map[string]json.RawMessage, error) {
	raw = bytes.TrimSpace(raw)
	var m map[string]json.RawMessage
	if len(raw) == 0 || raw[0] != '{' || json.Unmarshal(raw, &m) != nil {
		return nil, odd("not an object")
	}
	return m, nil
}

// loneSurrogate reports a \uD800-\uDFFF escape that isn't half of a pair.
func loneSurrogate(line []byte) bool {
	for i := 0; i < len(line); i++ {
		if line[i] != '\\' || i+1 >= len(line) {
			continue
		}
		if line[i+1] != 'u' {
			i++
			continue
		}
		u, ok := hex4(line, i+2)
		if !ok {
			continue
		}
		switch {
		case u >= 0xd800 && u < 0xdc00:
			if v, ok := hex4(line, i+8); !ok || line[i+6] != '\\' || line[i+7] != 'u' || v < 0xdc00 || v > 0xdfff {
				return true
			}
			i += 11
		case u >= 0xdc00 && u <= 0xdfff:
			return true
		default:
			i += 5
		}
	}
	return false
}

func hex4(b []byte, at int) (uint64, bool) {
	if at+4 > len(b) {
		return 0, false
	}
	u, err := strconv.ParseUint(string(b[at:at+4]), 16, 32)
	return u, err == nil
}

// truthy is Python's bool() of a JSON value; a missing one is None.
func truthy(raw json.RawMessage) bool {
	raw = bytes.TrimSpace(raw)
	if len(raw) == 0 {
		return false
	}
	switch raw[0] {
	case 'n', 'f':
		return false
	case 't':
		return true
	case '"':
		return len(raw) > 2
	case '[', '{':
		return len(bytes.TrimSpace(raw[1:len(raw)-1])) > 0
	}
	if !bytes.ContainsAny(raw, ".eE") {
		return strings.Trim(string(raw), "-0") != ""
	}
	f, _ := strconv.ParseFloat(string(raw), 64)
	return f != 0
}

// str reads a JSON string. ok is false for any other value.
func str(raw json.RawMessage) (string, bool) {
	raw = bytes.TrimSpace(raw)
	if len(raw) == 0 || raw[0] != '"' {
		return "", false
	}
	var s string
	if json.Unmarshal(raw, &s) != nil {
		return "", false
	}
	return s, true
}

// is says whether a JSON value is the string s, as Python's == does.
func is(raw json.RawMessage, s string) bool {
	v, ok := str(raw)
	return ok && v == s
}

// kind is the first byte of a JSON value, or 0 for a missing one.
func kind(raw json.RawMessage) byte {
	raw = bytes.TrimSpace(raw)
	if len(raw) == 0 {
		return 0
	}
	return raw[0]
}

// mentions is whether "git commit" is in str(v) for a tool call's command. Python's
// repr of a list or dict can hold the phrase only inside one of its strings, since it
// escapes nothing the phrase is made of, so this looks through them all.
func mentions(raw json.RawMessage, phrase string) bool {
	if s, ok := str(raw); ok {
		return strings.Contains(s, phrase)
	}
	var v any
	if json.Unmarshal(raw, &v) != nil {
		return false
	}
	var walk func(any) bool
	walk = func(v any) bool {
		switch x := v.(type) {
		case string:
			return strings.Contains(x, phrase)
		case []any:
			for _, e := range x {
				if walk(e) {
					return true
				}
			}
		case map[string]any:
			for k, e := range x {
				if strings.Contains(k, phrase) || walk(e) {
					return true
				}
			}
		}
		return false
	}
	return walk(v)
}
