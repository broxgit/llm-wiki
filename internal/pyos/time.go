// Package pyos reproduces what Python's os.path, pathlib, fnmatch and datetime do in the
// code wiki.sh ran before its port, and the git lookups the ports use to name a
// folder's project. Commands that read transcripts share it.
package pyos

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// Python's \s, which takes in more than ASCII space. A path in a command can't hold any.
const Space = `\t\n\x0b\f\r \x1c-\x1f\x{85}\x{a0}\x{1680}\x{2000}-\x{200a}\x{2028}\x{2029}\x{202f}\x{205f}\x{3000}`

// The Python's -C\s+(\S+).
var GitDirFlag = regexp.MustCompile(`-C[` + Space + `]+([^` + Space + `]+)`)

// DayShift reads the HH:MM a day starts as the time to take off a moment to get its day.
func DayShift(dayStarts string) (time.Duration, error) {
	hh, mm, ok := strings.Cut(dayStarts, ":")
	h, errH := strconv.Atoi(hh)
	m, errM := strconv.Atoi(mm)
	if !ok || errH != nil || errM != nil {
		return 0, fmt.Errorf("day start %q is not HH:MM", dayStarts)
	}
	return time.Duration(h)*time.Hour + time.Duration(m)*time.Minute, nil
}

// isoTime is the form of time this port is sure Python's datetime.fromisoformat reads
// the same way: a UTC or offset time, to the second, millisecond or microsecond.
var isoTime = regexp.MustCompile(`\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{3}|\.\d{6})?(Z|[+-]\d{2}:\d{2})\z`)

// Local is what the Python ports do with a transcript's time:
//
//	t = datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone()
//	day, hm = (t - timedelta(hours=h, minutes=m)).date(), t.strftime("%H:%M")
//
// astimezone gives a fixed offset, the one in force at that moment, so the day's start
// is taken off in that offset even across a clock change. ok is false for a time in a
// form isoTime doesn't take.
func Local(ts string, shift time.Duration) (day, hm string, ok bool) {
	if !isoTime.MatchString(ts) {
		return "", "", false
	}
	t, err := time.Parse(time.RFC3339Nano, ts)
	if err != nil {
		return "", "", false
	}
	name, offset := t.In(time.Local).Zone()
	zone := time.FixedZone(name, offset)
	return t.Add(-shift).In(zone).Format("2006-01-02"), t.In(zone).Format("15:04"), true
}
