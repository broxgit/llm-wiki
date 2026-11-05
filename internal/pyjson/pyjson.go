// Package pyjson reproduces the few things Python's json module and str() do that
// wiki.sh's Python reports relied on. The reports estimate tokens from the length of
// json.dumps(x), so a port has to count the same characters to print the same table.
package pyjson

import (
	"encoding/json"
	"math"
	"strconv"
	"strings"
)

// DumpsLen is len(json.dumps(v)) with Python's defaults: ", " and ": " separators and
// ensure_ascii. v is a value decoded with json.Decoder.UseNumber.
func DumpsLen(v any) int {
	switch x := v.(type) {
	case nil:
		return 4
	case bool:
		if x {
			return 4
		}
		return 5
	case json.Number:
		return len(NumberRepr(string(x)))
	case string:
		return stringLen(x)
	case []any:
		if len(x) == 0 {
			return 2
		}
		n := 2 + 2*(len(x)-1)
		for _, e := range x {
			n += DumpsLen(e)
		}
		return n
	case map[string]any:
		if len(x) == 0 {
			return 2
		}
		n := 2 + 2*(len(x)-1)
		for k, e := range x {
			n += stringLen(k) + 2 + DumpsLen(e)
		}
		return n
	}
	return 0
}

// stringLen is the length of a string as json.dumps writes it: quoted, with
// everything outside printable ASCII as \uXXXX, and a surrogate pair for anything past U+FFFF.
func stringLen(s string) int {
	n := 2
	for _, r := range s {
		switch {
		case r == '"' || r == '\\' || r == '\n' || r == '\r' || r == '\t' || r == '\b' || r == '\f':
			n += 2
		case r < 0x20 || r == 0x7f:
			n += 6
		case r < 0x7f:
			n++
		case r < 0x10000:
			n += 6
		default:
			n += 12
		}
	}
	return n
}

// NumberRepr is how Python writes a JSON number after reading it: an integer keeps its
// digits, and anything with a fraction or exponent becomes a float and gets its repr.
func NumberRepr(lit string) string {
	if !strings.ContainsAny(lit, ".eE") {
		if lit == "-0" {
			return "0"
		}
		return lit
	}
	f, _ := strconv.ParseFloat(lit, 64)
	return FloatRepr(f)
}

// FloatRepr is repr(float) in Python, with json.dumps's spelling of infinity: the
// shortest digits that round-trip, in fixed notation unless the decimal point would
// sit more than 16 digits right or 4 or more places left of the first digit.
func FloatRepr(f float64) string {
	if math.IsInf(f, 1) {
		return "Infinity"
	}
	if math.IsInf(f, -1) {
		return "-Infinity"
	}
	s := strconv.FormatFloat(f, 'e', -1, 64)
	sign := ""
	if strings.HasPrefix(s, "-") {
		sign, s = "-", s[1:]
	}
	mant, expStr, _ := strings.Cut(s, "e")
	exp, _ := strconv.Atoi(expStr)
	digits := strings.Replace(mant, ".", "", 1)
	if strings.Trim(digits, "0") == "" {
		return sign + "0.0"
	}
	point := exp + 1
	if point > 16 || point <= -4 {
		out := sign + digits[:1]
		if len(digits) > 1 {
			out += "." + digits[1:]
		}
		e := point - 1
		es := "+"
		if e < 0 {
			es, e = "-", -e
		}
		if e < 10 {
			es += "0"
		}
		return out + "e" + es + strconv.Itoa(e)
	}
	switch {
	case point <= 0:
		return sign + "0." + strings.Repeat("0", -point) + digits
	case point >= len(digits):
		return sign + digits + strings.Repeat("0", point-len(digits)) + ".0"
	}
	return sign + digits[:point] + "." + digits[point:]
}
