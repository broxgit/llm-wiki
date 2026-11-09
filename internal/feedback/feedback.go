// Package feedback is `wiki feedback add`: it keeps an agent's note about llm-wiki
// itself, or counts a note with the same summary as seen again. It writes what
// feedback_add's Bash writes and says what it says, the refusals included.
package feedback

import (
	"bytes"
	"errors"
	"io"
	"os"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"
)

// Options is what wiki.sh worked out before the call.
type Options struct {
	Dir      string // where the notes are kept, $FEEDBACK_DIR
	ModeFile string // the file that says off, notes or share, $FEEDBACK_FILE
	Wikis    string // the collection, named in a refusal
	Home     string // $HOME, written as ~
	Kinds    string // the kinds a note can be, with spaces between
	Version  string // the commit this llm-wiki runs
	Handbook string // the template handbook's version
	System   string // the note's System line: the system, bash and git
	// TTY says stdin is a terminal, where there are no details to read.
	TTY bool
	// StrictNul makes a NUL byte in the details an error. The Bash drops them, and
	// newer ones say so on stderr, which a caller that reads stderr would show.
	StrictNul bool
	Args      []string         // what follows "feedback add"
	Stdin     io.Reader        // the details, when no --file names them
	Now       func() time.Time // the clock; nil means time.Now
}

// Refused is an answer, not a failure: what the Bash would die with, after "error: ".
type Refused struct{ Msg string }

func (r *Refused) Error() string { return r.Msg }

func refuse(msg string) error { return &Refused{msg} }

const usage = `feedback add <kind> "<summary>" [--agent "<agent, model>"] [--file NOTE]`

var count = regexp.MustCompile(`\A(0|[1-9][0-9]{0,8})\z`)

// Add keeps the note and returns the line to print. A *Refused error is the command's
// own refusal. Any other error means this port isn't sure, nothing was read from Stdin
// or written, and the Bash should answer.
func Add(o Options) (string, error) {
	for _, a := range o.Args {
		// A line break in a summary or an agent's name: sed and $( ) treat it their way.
		if strings.ContainsAny(a, "\n\x00") {
			return "", errors.New("an argument with a line break")
		}
	}
	var kind, sum, agent, file string
	rest := o.Args
	if len(rest) > 0 {
		kind = rest[0]
	}
	if len(rest) >= 2 {
		sum, rest = rest[1], rest[2:]
	}
	for i := 0; i < len(rest); i += 2 {
		if rest[i] != "--agent" && rest[i] != "--file" {
			return "", refuse(usage)
		}
		if i+1 >= len(rest) {
			return "", refuse(rest[i] + " needs a value")
		}
		if rest[i] == "--agent" {
			agent = rest[i+1]
		} else {
			file = rest[i+1]
		}
	}
	if !strings.Contains(" "+o.Kinds+" ", " "+kind+" ") {
		return "", refuse("feedback add: the kind is one of: " + o.Kinds)
	}
	if sum == "" {
		return "", refuse("feedback add: give a one-line summary")
	}
	mode := o.mode()
	if mode == "off" {
		return "feedback is off on this machine, so nothing was saved. Don't try again this session.", nil
	}

	// Everything that might send this to the Bash is looked at here, before stdin is
	// read: after that there is no going back.
	again, seen, err := o.sameSummary(sum)
	if err != nil {
		return "", err
	}
	var body []byte
	if file != "" {
		// The Bash says what its cat says.
		if body, err = os.ReadFile(file); err != nil {
			return "", err
		}
		if bytes.IndexByte(body, 0) >= 0 {
			return "", errors.New("a NUL byte in the details")
		}
	} else if !o.TTY && o.Stdin != nil {
		if body, err = io.ReadAll(o.Stdin); err != nil {
			return "", err
		}
		if bytes.IndexByte(body, 0) >= 0 {
			if o.StrictNul {
				return "", errors.New("a NUL byte in the details")
			}
			body = bytes.ReplaceAll(body, []byte{0}, nil)
		}
	}
	// $( ) drops the line breaks at the end.
	body = bytes.TrimRight(body, "\n")
	if len(body) == 0 {
		return "", refuse("feedback add: the details go in --file NOTE or on stdin: what you ran, what it printed, what you expected, what would have helped")
	}
	if err := os.MkdirAll(o.Dir, 0o777); err != nil {
		return "", refuse(o.cantWrite(o.Dir))
	}
	now := time.Now
	if o.Now != nil {
		now = o.Now
	}
	at := now().UTC()
	if again != "" {
		// The same summary again: count it, and keep the new details under it.
		data, err := os.ReadFile(again)
		if err != nil {
			return "", refuse(o.cantWrite(again))
		}
		lines := strings.Split(string(data), "\n")
		for i, l := range lines {
			if strings.HasPrefix(l, "Seen: ") {
				lines[i] = "Seen: " + strconv.Itoa(seen+1)
			}
		}
		by := ""
		if agent != "" {
			by = ", by " + agent
		}
		text := strings.Join(lines, "\n") + "\n## Seen again " + at.Format("2006-01-02 15:04 UTC") + by + "\n\n" + string(body) + "\n"
		// The Bash writes a new file over the old one, then adds to it.
		if os.WriteFile(again+".tmp", []byte(text), 0o666) != nil || os.Rename(again+".tmp", again) != nil {
			return "", refuse(o.cantWrite(again))
		}
		return "feedback: seen again, " + base(again) + " (seen " + strconv.Itoa(seen+1) + " times)", nil
	}
	slug := Slug(sum)
	stamp := at.Format("20060102-150405")
	path := o.Dir + "/" + stamp + "-" + slug + ".md"
	// Two summaries can share a slug, and the same second.
	for n := 2; exists(path); n++ {
		path = o.Dir + "/" + stamp + "-" + slug + "-" + strconv.Itoa(n) + ".md"
	}
	if agent == "" {
		agent = "unknown"
	}
	text := "Kind: " + kind + "\nSummary: " + sum + "\nStatus: new\nAgent: " + agent + "\nCaptured: " + at.Format("2006-01-02 15:04 UTC") +
		"\nllm-wiki: " + o.Version + "\nHandbook: v" + o.Handbook + "\nSystem: " + o.System + "\nSeen: 1\n\n" + string(body) + "\n"
	if os.WriteFile(path, []byte(text), 0o666) != nil {
		return "", refuse(o.cantWrite(path))
	}
	line := "feedback: saved " + base(path)
	if mode == "share" {
		line += ". The user can file it with: wiki feedback send"
	}
	return line, nil
}

// Slug is the name a note gets from its summary: ASCII letters lowered, each run of
// other bytes one dash, none at either end, cut at 40. The Bash's tr, sed and cut,
// under LC_ALL=C.
func Slug(s string) string {
	var b strings.Builder
	dash := false
	for i := 0; i < len(s); i++ {
		c := lower(s[i])
		if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') {
			if dash && b.Len() > 0 {
				b.WriteByte('-')
			}
			dash = false
			b.WriteByte(c)
		} else {
			dash = true
		}
	}
	out := b.String()
	if len(out) > 40 {
		out = out[:40]
	}
	return strings.TrimSuffix(out, "-")
}

func lower(c byte) byte {
	if c >= 'A' && c <= 'Z' {
		return c + 'a' - 'A'
	}
	return c
}

func lowered(s string) string {
	b := []byte(s)
	for i, c := range b {
		b[i] = lower(c)
	}
	return string(b)
}

// mode is feedback_mode: what the first mode= line of the file says, or off.
func (o Options) mode() string {
	data, _ := os.ReadFile(o.ModeFile)
	for _, l := range strings.Split(string(data), "\n") {
		if strings.HasPrefix(l, "mode=") {
			if m := l[len("mode="):]; m == "notes" || m == "share" {
				return m
			}
			break
		}
	}
	return "off"
}

// field is feedback_field: what follows "<name>: " on the first line that starts so.
func field(lines []string, name string) string {
	for _, l := range lines {
		if strings.HasPrefix(l, name+": ") {
			return l[len(name)+2:]
		}
	}
	return ""
}

// sameSummary finds the first new note, by name, whose summary is this one, whatever
// the case of its ASCII letters, and how many times it was seen. It returns an error
// for anything the Bash would handle in a way of its own: a note it can't read, and a
// match it couldn't count or rewrite as sed and the shell do.
func (o Options) sameSummary(sum string) (string, int, error) {
	entries, err := os.ReadDir(o.Dir)
	if err != nil {
		if os.IsNotExist(err) {
			return "", 0, nil
		}
		return "", 0, err
	}
	// A folder that can't be written in: the shell says so in words of its own.
	if syscall.Access(o.Dir, 2) != nil {
		return "", 0, errors.New("a folder that can't be written in")
	}
	var names []string
	for _, e := range entries {
		// The shell's *.md: no hidden files.
		if n := e.Name(); strings.HasSuffix(n, ".md") && !strings.HasPrefix(n, ".") {
			names = append(names, n)
		}
	}
	sort.Strings(names)
	for _, n := range names {
		path := o.Dir + "/" + n
		info, err := os.Stat(path)
		if err != nil || !info.Mode().IsRegular() {
			continue
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return "", 0, err
		}
		if bytes.IndexByte(data, 0) >= 0 {
			return "", 0, errors.New("a note with a NUL byte")
		}
		lines := strings.Split(string(data), "\n")
		isNew := false
		for _, l := range lines {
			if strings.HasPrefix(l, "Status: new") {
				isNew = true
				break
			}
		}
		if !isNew || lowered(field(lines, "Summary")) != lowered(sum) {
			continue
		}
		seen := field(lines, "Seen")
		if seen == "" {
			seen = "1"
		}
		switch {
		case !count.MatchString(seen):
			return "", 0, errors.New("a Seen count the shell would read its own way")
		case !bytes.HasSuffix(data, []byte("\n")):
			return "", 0, errors.New("a note that doesn't end its last line")
		case syscall.Access(path, 2) != nil:
			return "", 0, errors.New("a note that might not be rewritten")
		}
		n, _ := strconv.Atoi(seen)
		return path, n, nil
	}
	return "", 0, nil
}

func base(path string) string {
	return strings.TrimSuffix(path[strings.LastIndex(path, "/")+1:], ".md")
}

func exists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func (o Options) tilde(path string) string {
	if strings.HasPrefix(path, o.Home+"/") {
		return "~/" + path[len(o.Home)+1:]
	}
	return path
}

func (o Options) cantWrite(path string) string {
	return "can't write " + o.tilde(path) + ". If this runs inside an agent's sandbox, allow " + o.tilde(o.Wikis) +
		" there, or run the command outside the sandbox. Nothing was saved."
}
