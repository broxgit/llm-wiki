package tokens

import (
	"testing"
	"time"
)

func TestParseTime(t *testing.T) {
	for _, s := range []string{"2026-11-05T15:17:55.123Z", "2026-11-05T15:17:55Z", "2026-11-05T10:17:55-05:00", "2026-11-05T15:17:55.123456", "2026-11-05 15:17:55", "2026-11-05"} {
		if _, ok := parseTime(s); !ok {
			t.Errorf("parseTime(%q) failed", s)
		}
	}
	a, _ := parseTime("2026-11-05T15:17:55Z")
	b, _ := parseTime("2026-11-05T10:17:55-05:00")
	if !a.Equal(b) {
		t.Errorf("the same instant in two zones differs: %v and %v", a, b)
	}
	if _, ok := parseTime("yesterday"); ok {
		t.Error("parseTime accepted a word")
	}
	if got, _ := parseTime("2026-11-05T15:17:55"); got.Location() != time.Local {
		t.Errorf("a time with no zone should be local, got %v", got.Location())
	}
}

func TestShort(t *testing.T) {
	for n, want := range map[int64]string{0: "0", 999: "999", 1000: "1k", 1499: "1k", 1500: "2k", 2500: "2k", 999999: "1000k", 1000000: "1.0M", 1250000: "1.2M", 19152600000: "19152.6M"} {
		if got := short(n); got != want {
			t.Errorf("short(%d) = %s, want %s", n, got, want)
		}
	}
}
