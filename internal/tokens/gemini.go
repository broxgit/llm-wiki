package tokens

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode/utf8"
)

// RunGemini is the Gemini token table of `wiki report`, from Antigravity's transcripts
// under o.Transcripts. It prints what the Python in wiki.sh's report_tokens_gemini
// prints.
//
// That Python assumes well-formed steps, and stops at the first one that isn't. So this
// reads only what it can be sure of. Anything else, such as a step that isn't an object
// or a count that isn't a whole number, is an error, wiki.sh runs the Python, and what
// the Python does with it is the answer.
func RunGemini(o Options) (string, error) {
	start, err := time.ParseInLocation("2006-01-02", o.Start, time.Local)
	if err != nil {
		return "", fmt.Errorf("start day: %w", err)
	}
	if _, err := time.ParseInLocation("2006-01-02", o.End, time.Local); err != nil {
		return "", fmt.Errorf("end day: %w", err)
	}
	shift, err := dayShift(o.DayStarts)
	if err != nil {
		return "", err
	}
	proj, err := newProjects(o.Wikis)
	if err != nil {
		return "", err
	}
	convs, err := geminiFiles(o.Transcripts, start)
	if err != nil {
		return "", err
	}

	results := make([][]geminiStep, len(convs))
	errs := make([]error, len(convs))
	var wg sync.WaitGroup
	slots := make(chan struct{}, runtime.NumCPU())
	for i, c := range convs {
		wg.Add(1)
		go func(i int, f string) {
			defer wg.Done()
			slots <- struct{}{}
			results[i], errs[i] = geminiRead(f, shift)
			<-slots
		}(i, c.file)
	}
	wg.Wait()
	var dirs []string
	for i := range convs {
		if errs[i] != nil {
			return "", errs[i]
		}
		for _, st := range results[i] {
			for _, c := range st.calls {
				dirs = append(dirs, c.dirs...)
			}
		}
	}
	proj.resolveWith(dirs, proj.lookupPath)

	sc := newScanner(o.Start, o.End, shift, o.Wikis)
	rows := map[string]*row{}
	var order []string
	usage := map[[2]string]bool{}
	for i, c := range convs {
		steps := results[i]
		// A conversation counts toward the project its folders point at most.
		counts := map[string]int{}
		var first []string
		for _, st := range steps {
			for _, tc := range st.calls {
				for _, d := range tc.dirs {
					if x := proj.name(d); x != "" && x != "wikis" {
						if counts[x] == 0 {
							first = append(first, x)
						}
						counts[x]++
					}
				}
			}
		}
		p := "other folders"
		if len(first) > 0 {
			p = first[0]
			for _, x := range first {
				if counts[x] > counts[p] {
					p = x
				}
			}
		}
		for j, st := range steps {
			if st.day == "" || st.day < o.Start || st.day > o.End {
				continue
			}
			rw := rows[p]
			if rw == nil {
				rw = &row{sessions: map[string]bool{}}
				rows[p] = rw
				order = append(order, p)
			}
			rw.sessions[c.name] = true
			rw.newIn += st.newIn
			rw.cached += st.cached
			rw.out += st.out
			for _, tc := range st.calls {
				if tc.name != "write_file" && tc.name != "edit_file" {
					pages, err := wikiPages(sc.page, tc.path+" "+tc.command)
					if err != nil {
						return "", err
					}
					for _, w := range pages {
						usage[[2]string{w, c.name}] = true
					}
				}
				if j+1 < len(steps) && geminiTouches(sc, tc, o.Wikis) {
					rw.wiki += int64(steps[j+1].size / 4)
				}
			}
		}
	}

	if o.UsageFile != "" {
		if err := writeUsage(o.UsageFile, o.Wikis, usage); err != nil {
			return "", err
		}
	}
	return table(rows, order, o.Exclude, tableWords{
		none: "No Gemini conversations in this range.",
		unit: "Conversations",
		foot: func(_, _ int64) string {
			return "\nGemini counts tokens its own way, so these don't add to Claude's.\n"
		},
	}), nil
}

type geminiConv struct{ name, file string }

// geminiFiles lists the conversations that can hold a day in the range, in a fixed
// order: a tie in the table goes to the project met first.
func geminiFiles(brain string, start time.Time) ([]geminiConv, error) {
	entries, err := os.ReadDir(brain)
	if err != nil {
		return nil, err
	}
	sort.Slice(entries, func(i, j int) bool { return entries[i].Name() < entries[j].Name() })
	// A file not touched since the day before the range can't hold a line in it.
	cutoff := time.Date(start.Year(), start.Month(), start.Day()-1, 0, 0, 0, 0, time.Local)
	var convs []geminiConv
	for _, e := range entries {
		f := filepath.Join(brain, e.Name(), ".system_generated", "logs", "transcript_full.jsonl")
		if _, err := os.Lstat(f); err != nil {
			continue
		}
		st, err := os.Stat(f)
		if err != nil {
			return nil, err
		}
		if !st.ModTime().Before(cutoff) {
			convs = append(convs, geminiConv{e.Name(), f})
		}
	}
	return convs, nil
}

// A step of a conversation, cut down to what the table counts.
type geminiStep struct {
	day                string // its day, or "" for a step with no time
	newIn, cached, out int64
	size               int // characters of its content
	calls              []geminiCall
}

type geminiCall struct {
	name, path, command string
	dirs                []string // the folders it points at
}

// The Python's -C\s+(\S+).
var gitDirFlag = regexp.MustCompile(`-C[` + pySpace + `]+([^` + pySpace + `]+)`)

// Times as Antigravity writes them. Python reads more forms, and older Pythons fewer
// fraction lengths, so anything else goes to the Python.
var geminiTime = regexp.MustCompile(`\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{3}|\.\d{6})?(Z|[+-]\d{2}:\d{2})\z`)

var geminiInt = regexp.MustCompile(`\A-?\d+\z`)

func oddStep(what string) error { return errors.New("a step the Python must judge: " + what) }

func geminiRead(path string, shift time.Duration) ([]geminiStep, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	// Python would decode bad bytes its own way, which the counts can show.
	if !utf8.Valid(data) {
		return nil, oddStep("not UTF-8")
	}
	var steps []geminiStep
	// Python's text mode ends a line at \n, \r\n or \r. A blank line is one it skips too.
	for _, line := range strings.FieldsFunc(string(data), func(r rune) bool { return r == '\n' || r == '\r' }) {
		if !json.Valid([]byte(line)) {
			if strings.Contains(line, "NaN") || strings.Contains(line, "Infinity") {
				return nil, oddStep("NaN or Infinity, which Python's json reads")
			}
			continue
		}
		st, err := geminiParse(line, shift)
		if err != nil {
			return nil, err
		}
		steps = append(steps, st)
	}
	return steps, nil
}

func geminiParse(line string, shift time.Duration) (geminiStep, error) {
	var st geminiStep
	m, err := jsonObject(json.RawMessage(line))
	if err != nil {
		return st, err
	}
	if raw := m["created_at"]; !isEmptyValue(raw) {
		ts, ok := asString(raw)
		if !ok {
			return st, oddStep("created_at")
		}
		if st.day, err = geminiDay(ts, shift); err != nil {
			return st, err
		}
	}
	for _, f := range []struct {
		key string
		to  *int64
	}{{"input_tokens", &st.newIn}, {"cache_read_tokens", &st.cached}, {"output_tokens", &st.out}} {
		if *f.to, err = geminiCount(m[f.key]); err != nil {
			return st, err
		}
	}
	content, err := emptyOrString(m["content"])
	if err != nil {
		return st, err
	}
	st.size = utf8.RuneCountInString(content)
	st.calls, err = geminiCalls(m["tool_calls"])
	return st, err
}

func geminiCalls(raw json.RawMessage) ([]geminiCall, error) {
	if isEmptyValue(raw) {
		return nil, nil
	}
	var items []json.RawMessage
	if json.Unmarshal(raw, &items) != nil {
		return nil, oddStep("tool_calls")
	}
	var calls []geminiCall
	for _, it := range items {
		c, err := jsonObject(it)
		if err != nil {
			return nil, err
		}
		var a map[string]json.RawMessage
		if !isEmptyValue(c["args"]) {
			if a, err = jsonObject(c["args"]); err != nil {
				return nil, err
			}
		}
		var tc geminiCall
		tc.name, _ = asString(c["name"])
		if tc.path, err = emptyOrString(a["Path"]); err != nil {
			return nil, err
		}
		if tc.command, err = emptyOrString(a["CommandLine"]); err != nil {
			return nil, err
		}
		if tc.path != "" {
			p, err := geminiExpand(tc.path)
			if err != nil {
				return nil, err
			}
			tc.dirs = append(tc.dirs, pyDirname(p))
		}
		for _, m := range gitDirFlag.FindAllStringSubmatch(tc.command, -1) {
			d, err := geminiExpand(m[1])
			if err != nil {
				return nil, err
			}
			tc.dirs = append(tc.dirs, d)
		}
		calls = append(calls, tc)
	}
	return calls, nil
}

// geminiExpand is expanduser for the paths this port is sure of. ~name needs a lookup
// of that user, and a NUL can make Python's path functions raise.
func geminiExpand(p string) (string, error) {
	if strings.ContainsRune(p, 0) || (strings.HasPrefix(p, "~") && p != "~" && !strings.HasPrefix(p, "~/")) {
		return "", oddStep("path " + p)
	}
	return expandUser(p), nil
}

// geminiDay is the Python's day_of. astimezone gives a fixed offset, the one in force
// at that moment, so the day's start is taken off in that offset even across a clock
// change.
func geminiDay(ts string, shift time.Duration) (string, error) {
	if !geminiTime.MatchString(ts) {
		return "", oddStep("time " + ts)
	}
	t, err := time.Parse(time.RFC3339Nano, ts)
	if err != nil {
		return "", oddStep("time " + ts)
	}
	_, offset := t.In(time.Local).Zone()
	return t.Add(-shift).In(time.FixedZone("", offset)).Format("2006-01-02"), nil
}

func geminiCount(raw json.RawMessage) (int64, error) {
	if len(raw) == 0 || string(raw) == "null" {
		return 0, nil
	}
	if !geminiInt.Match(raw) {
		return 0, oddStep("a count of " + string(raw))
	}
	n, err := strconv.ParseInt(string(raw), 10, 64)
	if err != nil {
		return 0, oddStep("a count of " + string(raw))
	}
	return n, nil
}

// geminiTouches is the Python's touches_wiki.
func geminiTouches(sc *scanner, tc geminiCall, wikis string) bool {
	return (tc.path != "" && sc.inWikis(tc.path)) || strings.Contains(tc.command, wikis) ||
		strings.Contains(tc.command, "~/wikis") || strings.Contains(tc.command, "wiki.sh")
}

// wikiPages finds the wikis a tool call's text opens. Python's \b takes any letter as
// part of a word and Go's only ASCII, so a match with a non-ASCII byte after it is
// left to the Python.
func wikiPages(page *regexp.Regexp, s string) ([]string, error) {
	var out []string
	for _, m := range page.FindAllStringSubmatchIndex(s, -1) {
		if m[1] < len(s) && s[m[1]] >= utf8.RuneSelf && s[m[1]-1] != '/' {
			return nil, oddStep("a path " + s)
		}
		out = append(out, s[m[2]:m[3]])
	}
	return out, nil
}

// jsonObject reads a JSON object's fields exactly as named, the last of a repeated one.
// Anything else is for the Python.
func jsonObject(raw json.RawMessage) (map[string]json.RawMessage, error) {
	var m map[string]json.RawMessage
	if !isObject(raw) || json.Unmarshal(raw, &m) != nil {
		return nil, oddStep("not an object")
	}
	return m, nil
}

// isEmptyValue is true for a field that's missing, or null, or the empty string or
// list. Other values Python treats as false are left to the Python.
func isEmptyValue(raw json.RawMessage) bool {
	switch string(raw) {
	case "", "null", `""`, "[]":
		return true
	}
	return false
}

func emptyOrString(raw json.RawMessage) (string, error) {
	if isEmptyValue(raw) {
		return "", nil
	}
	s, ok := asString(raw)
	if !ok {
		return "", oddStep("not a string: " + string(raw))
	}
	return s, nil
}
