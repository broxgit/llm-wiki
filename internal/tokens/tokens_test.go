package tokens

import (
	"os"
	"path/filepath"
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

// Printed by Python 3.14 with TZ=America/New_York:
//
//	(datetime.fromisoformat(ts).astimezone() - timedelta(hours=4)).date()
//
// The clocks went back at 06:00Z on 1 November 2026 and forward at 07:00Z on 8 March.
func TestDayOfAcrossAClockChange(t *testing.T) {
	loc, err := time.LoadLocation("America/New_York")
	if err != nil {
		t.Skip("no time zone data here")
	}
	old := time.Local
	time.Local = loc
	defer func() { time.Local = old }()
	for ts, want := range map[string]string{
		"2026-07-01T07:59:00Z": "2026-06-30",
		"2026-07-01T08:00:00Z": "2026-07-01",
		"2026-11-01T08:30:00Z": "2026-10-31", // 03:30 EST, four hours after 23:30 the night before
		"2026-11-01T09:00:00Z": "2026-11-01",
		"2026-03-08T07:30:00Z": "2026-03-07",
		"2026-03-08T08:10:00Z": "2026-03-08", // 04:10 EDT, though four hours earlier was 23:10 EST
		"2026-11-01T03:30:00":  "2026-10-31",
	} {
		at, ok := parseTime(ts)
		if !ok {
			t.Fatalf("parseTime(%q) failed", ts)
		}
		if got := dayOf(at, 4*time.Hour); got != want {
			t.Errorf("dayOf(%s) = %s, want %s", ts, got, want)
		}
	}
}

// The Python stops at a transcript it can't open, so the port must not answer for it
// with that file left out.
func TestRunFailsOnATranscriptItCannotRead(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("root can read anything")
	}
	dir := t.TempDir()
	wikis := t.TempDir()
	today := time.Now().Format("2006-01-02")
	opts := Options{Transcripts: dir, Start: today, End: today, DayStarts: "04:00", Wikis: wikis}
	p := filepath.Join(dir, "proj", "a.jsonl")
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte("{}\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := Run(opts); err != nil {
		t.Fatalf("Run with a readable transcript: %v", err)
	}
	if err := os.Chmod(p, 0); err != nil {
		t.Fatal(err)
	}
	if out, err := Run(opts); err == nil {
		t.Errorf("Run left an unreadable transcript out and printed:\n%s", out)
	}
}
