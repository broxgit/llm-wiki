package pyjson

import (
	"bytes"
	"encoding/json"
	"strconv"
	"testing"
)

// The expected values were printed by Python 3.14: len(json.dumps(json.loads(s)))
// and repr(float(s)). They are what the Go has to agree with.

func TestDumpsLen(t *testing.T) {
	cases := []struct {
		in   string
		want int
	}{
		{`{}`, 2},
		{`[]`, 2},
		{`{"a":1}`, 8},
		{`{"a":[1,2,{"b":null}],"c":true,"d":false}`, 49},
		{`"plain"`, 7},
		{`"quote\" and \\ slash"`, 22},
		{`"tab\tnew\nline\r"`, 18},
		{`"café ☃ 😀"`, 31},
		{`"ctl\u0001\u001f del\u007f"`, 27},
		{`1.50`, 3},
		{`1E5`, 8},
		{`-0`, 1},
		{`-0.0`, 4},
		{`0.00001`, 5},
		{`0.0001`, 6},
		{`1e16`, 5},
		{`1e15`, 18},
		{`123456789012345678901234567890`, 30},
		{`1e-7`, 5},
		{`2.5e-10`, 7},
		{`1.7976931348623157e308`, 23},
		{`{"timeout":120000,"ratio":0.1,"xs":[1.0,2.25,3e3]}`, 60},
		{`"\b\f"`, 6},
		{`{"kéy":"v"}`, 17},
		{`[[],{},""]`, 12},
	}
	for _, c := range cases {
		d := json.NewDecoder(bytes.NewReader([]byte(c.in)))
		d.UseNumber()
		var v any
		if err := d.Decode(&v); err != nil {
			t.Fatalf("%s: %v", c.in, err)
		}
		if got := DumpsLen(v); got != c.want {
			t.Errorf("DumpsLen(%s) = %d, Python gives %d", c.in, got, c.want)
		}
	}
}

func TestFloatRepr(t *testing.T) {
	cases := [][2]string{
		{"1.5", "1.5"},
		{"100.0", "100.0"},
		{"1e16", "1e+16"},
		{"1e15", "1000000000000000.0"},
		{"123456789.123", "123456789.123"},
		{"0.0001", "0.0001"},
		{"0.00001", "1e-05"},
		{"1e-7", "1e-07"},
		{"-2.5e-10", "-2.5e-10"},
		{"0.1", "0.1"},
		{"1e22", "1e+22"},
		{"5e-324", "5e-324"},
		{"0.0", "0.0"},
		{"-0.0", "-0.0"},
		{"12345678901234567.0", "1.2345678901234568e+16"},
		{"9007199254740993.0", "9007199254740992.0"},
		{"1.0e100", "1e+100"},
	}
	for _, c := range cases {
		f, err := strconv.ParseFloat(c[0], 64)
		if err != nil {
			t.Fatalf("%s: %v", c[0], err)
		}
		if got := FloatRepr(f); got != c[1] {
			t.Errorf("FloatRepr(%s) = %s, Python gives %s", c[0], got, c[1])
		}
	}
}
