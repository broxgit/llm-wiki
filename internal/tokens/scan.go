package tokens

import (
	"bufio"
	"bytes"
	"encoding/json"
	"io"
	"os"
	"regexp"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/broxgit/llm-wiki/internal/pyjson"
)

// What a transcript line holds, read loosely: any field may be missing or a type
// nobody expected, and a line like that is skipped, not fatal.
type rawRecord struct {
	Timestamp json.RawMessage `json:"timestamp"`
	Cwd       json.RawMessage `json:"cwd"`
	SessionID json.RawMessage `json:"sessionId"`
	Message   json.RawMessage `json:"message"`
}

type rawMessage struct {
	ID      json.RawMessage `json:"id"`
	Usage   json.RawMessage `json:"usage"`
	Content json.RawMessage `json:"content"`
}

type rawPart struct {
	Type      json.RawMessage `json:"type"`
	ID        json.RawMessage `json:"id"`
	Name      json.RawMessage `json:"name"`
	Input     json.RawMessage `json:"input"`
	ToolUseID json.RawMessage `json:"tool_use_id"`
	Content   json.RawMessage `json:"content"`
}

// A record of a transcript line, cut down to what the report counts.
type record struct {
	cwd     string
	inRange bool
	session string
	hasUse  bool // the message carries token counts
	msgID   string
	newIn   int64
	cached  int64
	out     int64
	parts   []part
}

type part struct {
	toolUse  bool
	id       string
	touches  bool     // a tool call that read or wrote a wiki
	size     int      // estimated tokens: of the call's input, or of a result's text
	pages    []string // wikis whose pages the call opened
	wikiRead string   // the wiki named by an MCP wiki_read call, when it read a page
	isRead   bool
}

type scanned struct {
	stem    string
	records []record
}

// Python's \s, which takes in more than ASCII space. A path in a command can't hold any.
const pySpace = `\t\n\x0b\f\r \x1c-\x1f\x{85}\x{a0}\x{1680}\x{2000}-\x{200a}\x{2028}\x{2029}\x{202f}\x{205f}\x{3000}`

var wikiCommand = regexp.MustCompile(`\A[` + pySpace + `]*wiki[` + pySpace + `]`)

type scanner struct {
	start, end string // days, as YYYY-MM-DD
	dayShift   time.Duration
	wikis      string
	wikisReal  string
	page       *regexp.Regexp
	real       sync.Map // path -> whether it is inside the wikis
}

func newScanner(start, end string, dayShift time.Duration, wikis string) *scanner {
	s := &scanner{start: start, end: end, dayShift: dayShift, wikis: wikis, wikisReal: realPath(wikis)}
	alts := []string{regexp.QuoteMeta(wikis)}
	for _, x := range []string{s.wikisReal, tilde(wikis)} {
		if q := regexp.QuoteMeta(x); !contains(alts, q) {
			alts = append(alts, q)
		}
	}
	s.page = regexp.MustCompile(`(?:` + strings.Join(alts, "|") + `)/([^/` + pySpace + `"']+)/wiki(?:/|\b)`)
	return s
}

func contains(xs []string, x string) bool {
	for _, y := range xs {
		if y == x {
			return true
		}
	}
	return false
}

// tilde is the path with the home folder written as ~, when it starts there.
func tilde(p string) string {
	if home, err := os.UserHomeDir(); err == nil {
		if i := strings.Index(p, home); i >= 0 {
			return p[:i] + "~" + p[i+len(home):]
		}
	}
	return p
}

// file reads one transcript. Lines that aren't a JSON object with a timestamp are
// skipped, as are ones whose timestamp can't be read.
func (s *scanner) file(path, stem string) (scanned, error) {
	f, err := os.Open(path)
	if err != nil {
		return scanned{}, err
	}
	defer f.Close()
	out := scanned{stem: stem}
	r := bufio.NewReaderSize(f, 1<<20)
	for {
		line, err := r.ReadBytes('\n')
		if len(bytes.TrimSpace(line)) > 0 {
			if rec, ok := s.line(line, stem); ok {
				out.records = append(out.records, rec)
			}
		}
		if err == io.EOF {
			return out, nil
		}
		if err != nil {
			return out, err
		}
	}
}

func (s *scanner) line(line []byte, stem string) (record, bool) {
	var raw rawRecord
	if json.Unmarshal(line, &raw) != nil {
		return record{}, false
	}
	ts, ok := asString(raw.Timestamp)
	if !ok || ts == "" {
		return record{}, false
	}
	t, ok := parseTime(ts)
	if !ok {
		return record{}, false
	}
	day := t.Local().Add(-s.dayShift).Format("2006-01-02")
	rec := record{inRange: day >= s.start && day <= s.end}
	rec.cwd, _ = asString(raw.Cwd)
	if !rec.inRange {
		return rec, true
	}
	rec.session = stem
	if raw.SessionID != nil {
		rec.session = pyStr(raw.SessionID)
	}
	var msg rawMessage
	if isObject(raw.Message) {
		_ = json.Unmarshal(raw.Message, &msg)
	}
	if u := decodeObject(msg.Usage); len(u) > 0 {
		rec.hasUse = true
		rec.msgID = key(msg.ID)
		rec.newIn = intOf(u["input_tokens"]) + intOf(u["cache_creation_input_tokens"])
		rec.cached = intOf(u["cache_read_input_tokens"])
		rec.out = intOf(u["output_tokens"])
	}
	var content []json.RawMessage
	if json.Unmarshal(msg.Content, &content) != nil {
		return rec, true
	}
	for _, c := range content {
		if !isObject(c) {
			continue
		}
		var p rawPart
		if json.Unmarshal(c, &p) != nil {
			continue
		}
		switch kind, _ := asString(p.Type); kind {
		case "tool_use":
			rec.parts = append(rec.parts, s.toolUse(p))
		case "tool_result":
			rec.parts = append(rec.parts, part{id: key(p.ToolUseID), size: resultSize(p.Content) / 4})
		}
	}
	return rec, true
}

func (s *scanner) toolUse(p rawPart) part {
	input := decodeObject(p.Input)
	out := part{toolUse: true, id: key(p.ID), size: 2 / 4}
	if len(input) > 0 {
		out.size = pyjson.DumpsLen(map[string]any(input)) / 4
	}
	for _, k := range []string{"file_path", "notebook_path", "path"} {
		if v, ok := input[k].(string); ok && s.inWikis(v) {
			out.touches = true
		}
	}
	if !out.touches {
		cmd := text(input, "command")
		out.touches = strings.Contains(cmd, s.wikis) || strings.Contains(cmd, s.wikisReal) ||
			strings.Contains(cmd, "~/wikis") || strings.Contains(cmd, "wiki.sh") || wikiCommand.MatchString(cmd)
	}
	name, _ := asString(p.Name)
	if strings.HasSuffix(name, "wiki_read") && strings.HasPrefix(text(input, "path"), "wiki/") {
		out.isRead = true
		out.wikiRead = "None"
		if v, ok := input["wiki"]; ok && v != nil {
			out.wikiRead = text(input, "wiki")
		}
	}
	if name == "Edit" || name == "Write" {
		return out
	}
	for _, k := range []string{"file_path", "path", "command"} {
		for _, m := range s.page.FindAllStringSubmatch(text(input, k), -1) {
			out.pages = append(out.pages, m[1])
		}
	}
	return out
}

func (s *scanner) inWikis(p string) bool {
	if v, ok := s.real.Load(p); ok {
		return v.(bool)
	}
	in := strings.HasPrefix(realPath(expandUser(p)), s.wikisReal+"/")
	s.real.Store(p, in)
	return in
}

// resultSize is len(str(body or "")) for a tool result: its text, or the text of its
// parts joined by spaces.
func resultSize(raw json.RawMessage) int {
	raw = bytes.TrimSpace(raw)
	if len(raw) == 0 {
		return 0
	}
	switch raw[0] {
	case '"':
		s, _ := asString(raw)
		return utf8.RuneCountInString(s)
	case '[':
		var items []json.RawMessage
		if json.Unmarshal(raw, &items) != nil {
			return 0
		}
		n, parts := 0, 0
		for _, it := range items {
			if !isObject(it) {
				continue
			}
			var o struct {
				Text json.RawMessage `json:"text"`
			}
			_ = json.Unmarshal(it, &o)
			t, _ := asString(o.Text)
			n += utf8.RuneCountInString(t)
			parts++
		}
		if parts > 1 {
			n += parts - 1
		}
		return n
	case 'n', 'f':
		return 0
	case 't':
		return 4
	case '{':
		return pyjson.DumpsLen(map[string]any(decodeObject(raw)))
	}
	if string(raw) == "0" {
		return 0
	}
	return len(pyjson.NumberRepr(string(raw)))
}

func isObject(raw json.RawMessage) bool {
	raw = bytes.TrimSpace(raw)
	return len(raw) > 0 && raw[0] == '{'
}

func asString(raw json.RawMessage) (string, bool) {
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

// decodeObject reads a JSON object, keeping numbers as written. Anything else is empty.
func decodeObject(raw json.RawMessage) map[string]any {
	if !isObject(raw) {
		return nil
	}
	d := json.NewDecoder(bytes.NewReader(raw))
	d.UseNumber()
	var m map[string]any
	if d.Decode(&m) != nil {
		return nil
	}
	return m
}

// text is str(input.get(k, "")) for the values a tool call's input holds.
func text(input map[string]any, k string) string {
	switch v := input[k].(type) {
	case string:
		return v
	case nil:
		if _, ok := input[k]; ok {
			return "None"
		}
		return ""
	case json.Number:
		return pyjson.NumberRepr(string(v))
	case bool:
		if v {
			return "True"
		}
		return "False"
	default:
		b, _ := json.Marshal(v)
		return string(b)
	}
}

// pyStr is str(x) for a JSON value used as a name: a string as it is, null as None.
func pyStr(raw json.RawMessage) string {
	if s, ok := asString(raw); ok {
		return s
	}
	if t := string(bytes.TrimSpace(raw)); t != "null" {
		return t
	}
	return "None"
}

// key makes a JSON value comparable: a missing one and null are the same, as
// dict.get gives None for both.
func key(raw json.RawMessage) string {
	if s, ok := asString(raw); ok {
		return "s" + s
	}
	t := string(bytes.TrimSpace(raw))
	if t == "" || t == "null" {
		return "n"
	}
	return "o" + t
}

func intOf(v any) int64 {
	n, ok := v.(json.Number)
	if !ok {
		return 0
	}
	if i, err := n.Int64(); err == nil {
		return i
	}
	f, _ := n.Float64()
	return int64(f)
}

var timeLayouts = []string{
	time.RFC3339Nano,
	"2006-01-02T15:04:05.999999999",
	"2006-01-02 15:04:05.999999999Z07:00",
	"2006-01-02 15:04:05.999999999",
	"2006-01-02",
}

// parseTime reads an ISO time. One with no zone is local time, as Python has it.
func parseTime(s string) (time.Time, bool) {
	for i, layout := range timeLayouts {
		var t time.Time
		var err error
		if i == 0 || i == 2 {
			t, err = time.Parse(layout, s)
		} else {
			t, err = time.ParseInLocation(layout, s, time.Local)
		}
		if err == nil {
			return t, true
		}
	}
	return time.Time{}, false
}
