// Package capture is `wiki capture`: it saves a note, or a copy of a file, in a wiki's
// raw folder under a name that starts with the clock. It writes what cmd_capture's Bash
// writes and says what it says, the refusals included.
package capture

import (
	"bytes"
	"errors"
	"github.com/broxgit/llm-wiki/internal/routing"
	"io"
	"os"
	"strconv"
	"strings"
	"time"
)

// Options is what wiki.sh, or the MCP server, worked out before the call.
type Options struct {
	Wikis string // the collection, $WIKIS_DIR
	Home  string // $HOME
	Pwd   string // $PWD, for a wiki named by a relative path
	// WikiCmd is how the person runs wiki.sh, for the lines that name a command to run.
	WikiCmd string
	// TTY says stdin is a terminal, where there is no note to read.
	TTY   bool
	Args  []string         // the command's own arguments
	Stdin io.Reader        // the note, when no --file or --copy names one
	Now   func() time.Time // the clock; nil means time.Now
	// Warn, when it is set, is given each warning about the saved note, as Lint says them.
	Warn func(string)
}

// Refused is an answer, not a failure: what the Bash would die with, after "error: ".
type Refused struct{ Msg string }

func (r *Refused) Error() string { return r.Msg }

func refuse(msg string) error { return &Refused{msg} }

// Run saves the note and returns the line to print. A *Refused error is the command's
// own refusal. Any other error means this port isn't sure, nothing was read from Stdin
// or written, and the Bash should answer.
func Run(o Options) (string, error) {
	for _, a := range o.Args {
		// A line break in a name: sed and $( ) treat it their own way.
		if strings.ContainsAny(a, "\n\x00") {
			return "", errors.New("an argument with a line break")
		}
	}
	var wiki, slug, copyFrom, file string
	for i := 0; i < len(o.Args); {
		a := o.Args[i]
		switch {
		case a == "--copy" || a == "--file":
			if i+1 >= len(o.Args) {
				return "", refuse(a + " needs a value")
			}
			if a == "--copy" {
				copyFrom = o.Args[i+1]
			} else {
				file = o.Args[i+1]
			}
			i += 2
		case strings.HasPrefix(a, "-"):
			return "", refuse("capture options: --file NOTE, --copy FILE")
		default:
			if wiki == "" {
				wiki = a
			} else if slug == "" {
				slug = a
			} else {
				return "", refuse("capture takes a wiki and a slug")
			}
			i++
		}
	}
	if copyFrom != "" && file != "" {
		return "", refuse("capture takes --file NOTE or --copy FILE, not both")
	}
	if wiki == "" {
		return "", refuse("name a wiki")
	}
	root := o.resolve(wiki)
	// The words are not_wiki's in wiki.sh.
	switch st, err := routing.WikiState(root); {
	case err == nil && st == routing.Linked:
		link, _ := routing.WikiLink(root)
		return "", refuse(o.tilde(root) + " is not a wiki: its " + link + " is a link, so llm-wiki does not use it. Nothing was changed. Run: " + o.WikiCmd + " status")
	case err != nil || st == routing.Missing:
		return "", refuse(o.tilde(root) + " is not a wiki. Run: " + o.WikiCmd + " status")
	case st == routing.NotHandbook:
		return "", refuse(o.tilde(root) + " is not a wiki: its AGENTS.md is not the llm-wiki handbook. Nothing was changed. Run: " + o.WikiCmd + " status")
	}
	ext := "md"
	if copyFrom != "" {
		if !isFile(copyFrom) {
			return "", refuse("no file at " + copyFrom)
		}
		base := copyFrom[strings.LastIndex(copyFrom, "/")+1:]
		stem := base
		// A dot with something before it: "notes.txt", not ".env".
		if dot := strings.LastIndex(base, "."); dot >= 1 {
			ext, stem = base[dot+1:], base[:dot]
		} else {
			ext = "txt"
		}
		if slug == "" {
			slug = stem
		}
	} else {
		if slug == "" {
			return "", refuse("capture needs a short slug for the name, such as decided-postgres")
		}
		if file != "" {
			if !isFile(file) {
				return "", refuse("no file at " + file)
			}
		} else if o.TTY {
			return "", refuse("capture reads the note from stdin, or from a file with --file NOTE")
		}
	}
	if slug = Slug(slug); slug == "" {
		return "", refuse("that slug has no letters or digits")
	}
	now := time.Now
	if o.Now != nil {
		now = o.Now
	}
	// The clock, to the second, in UTC. The name sets ingest order, so never round it.
	stamp := now().UTC().Format("2006-01-02-150405")
	name := stamp + "-" + slug + "." + ext
	n := 2
	for ; exists(root + "/raw/" + name); n++ {
		name = stamp + "-" + slug + "-" + strconv.Itoa(n) + "." + ext
	}
	dest := root + "/raw/" + name
	// A raw that is a file, not a folder, is said as such: the failure read as a sandbox.
	if st, err := os.Stat(root + "/raw"); err == nil && !st.IsDir() {
		return "", refuse("raw in " + root[strings.LastIndex(root, "/")+1:] + " is a file, not a folder, so no note was saved. Do: move that file away, then capture again")
	}
	if err := os.MkdirAll(root+"/raw", 0o777); err != nil {
		return "", refuse(o.cantWrite(root + "/raw"))
	}
	// place writes the note under a name nothing has. The name above was free when it was
	// looked at, and another capture may take it before this one writes: two sessions, the
	// same second, the same slug. So the file is made only if it isn't there, and when it
	// is, the next name is tried. Looking first and writing after let one note write over
	// another.
	place := func(data []byte, perm os.FileMode) error {
		for tries := 0; tries < 1000; tries++ {
			err := write(dest, data, perm)
			if err == nil {
				return nil
			}
			if !errors.Is(err, os.ErrExist) {
				return err
			}
			name = stamp + "-" + slug + "-" + strconv.Itoa(n) + "." + ext
			dest = root + "/raw/" + name
			n++
		}
		return os.ErrExist
	}
	if copyFrom != "" {
		// cp gives the copy the file's own permissions, less the umask.
		info, err := os.Stat(copyFrom)
		if err != nil {
			return "", refuse(o.cantWrite(dest))
		}
		data, err := os.ReadFile(copyFrom)
		if err != nil || place(data, info.Mode().Perm()) != nil {
			return "", refuse(o.cantWrite(dest))
		}
	} else {
		var note []byte
		var err error
		if file != "" {
			note, err = os.ReadFile(file)
		} else if o.Stdin != nil {
			note, err = io.ReadAll(o.Stdin)
		}
		if err != nil {
			// The Bash stops at its cat, with cat's own words.
			return "", err
		}
		if len(note) == 0 {
			return "", refuse("capture got an empty note")
		}
		// The Bash copies a temporary file, and the copy takes its permissions: mktemp's
		// 0600 for a note that came with its Captured line, and a redirect's for one that
		// got the line here.
		perm := os.FileMode(0o600)
		if !bytes.HasPrefix(note, []byte("Captured: ")) {
			note = append([]byte("Captured: "+now().UTC().Format("2006-01-02")+"\n\n"), note...)
			perm = 0o666
		}
		if place(note, perm) != nil {
			return "", refuse(o.cantWrite(dest))
		}
		// A copy is a document as it came, not a note: its lines are not looked at.
		if o.Warn != nil {
			for _, w := range Lint(note, name) {
				o.Warn(w)
			}
		}
	}
	return "captured: raw/" + name + " in " + o.tilde(root), nil
}

// Lint is a warning for each Waiting:, Due: or Feedback: line of a saved note that compile
// can't read, with its line number in the note. It says what capture_lint in wiki.sh says,
// byte for byte: change both together.
func Lint(note []byte, name string) []string {
	var out []string
	say := func(n int, what, fix string) {
		out = append(out, "warning: line "+strconv.Itoa(n)+" of raw/"+name+" is "+what+", so compile can't read it. Do: edit it to read "+fix)
	}
	trim := func(s string) string { return strings.Trim(s, " \t") }
	// sides splits at the first " | ", and says whether both sides have something.
	sides := func(s string) (string, bool) {
		left, right, found := strings.Cut(s, " | ")
		return trim(left), found && trim(left) != "" && trim(right) != ""
	}
	// awk reads a last line with no line break too, and nothing after a final one.
	text := strings.TrimSuffix(string(note), "\n")
	for i, line := range strings.Split(text, "\n") {
		n := i + 1
		line = strings.TrimSuffix(line, "\r")
		switch {
		case strings.HasPrefix(line, "Waiting:"):
			if _, ok := sides(line[len("Waiting:"):]); !ok {
				say(n, `a Waiting: line with no " | " between who and what`, "Waiting: <who> | <what>")
			}
		case strings.HasPrefix(line, "Due:"):
			date, ok := sides(line[len("Due:"):])
			if !ok {
				say(n, `a Due: line with no " | " between the date and what`, "Due: <YYYY-MM-DD> | <what>")
			} else if !isDate(date) {
				say(n, "a Due: line whose date is not YYYY-MM-DD", "Due: <YYYY-MM-DD> | <what>")
			}
		case strings.HasPrefix(line, "Feedback:"):
			good := false
			if kind, rest, found := strings.Cut(line[len("Feedback:"):], " | "); found {
				if scope, rule, found := strings.Cut(rest, " | "); found {
					scope = trim(scope)
					switch trim(kind) {
					case "review", "correction", "lesson", "ask", "procedure", "toil":
						good = scope != "" && !strings.ContainsAny(scope, " \t") && trim(rule) != ""
					}
				}
			}
			if !good {
				say(n, "a Feedback: line not in the form the handbook gives",
					"Feedback: <kind> | <scope> | <rule>, where kind is review, correction, lesson, ask, procedure or toil, and scope is here, everywhere or a wiki's name")
			}
		}
	}
	return out
}

// isDate is YYYY-MM-DD in digits, as the Bash's pattern has it: the date itself isn't checked.
func isDate(s string) bool {
	if len(s) != 10 || s[4] != '-' || s[7] != '-' {
		return false
	}
	for i := 0; i < len(s); i++ {
		if i != 4 && i != 7 && (s[i] < '0' || s[i] > '9') {
			return false
		}
	}
	return true
}

// Slug is the name a note gets: ASCII letters lowered, and every run of other bytes one
// dash, with none at either end. The Bash's tr and sed, under LC_ALL=C.
func Slug(s string) string {
	var b strings.Builder
	dash := false
	for i := 0; i < len(s); i++ {
		c := s[i]
		if c >= 'A' && c <= 'Z' {
			c += 'a' - 'A'
		}
		if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') {
			if dash {
				b.WriteByte('-')
				dash = false
			}
			b.WriteByte(c)
		} else {
			dash = true
		}
	}
	out := b.String()
	if dash {
		out += "-"
	}
	// One run at the start became one dash, written before the first letter.
	return strings.TrimSuffix(strings.TrimPrefix(out, "-"), "-")
}

// write makes the file and fills it. It fails, with os.ErrExist, when the path is there
// already, a link included: nothing is ever emptied or written over.
func write(path string, data []byte, perm os.FileMode) error {
	f, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, perm)
	if err != nil {
		return err
	}
	if _, err := f.Write(data); err != nil {
		_ = f.Close()
		// The file was made here, a moment ago, and holds part of a note at most.
		_ = os.Remove(path)
		return err
	}
	if err := f.Close(); err != nil {
		_ = os.Remove(path)
		return err
	}
	return nil
}

func isFile(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.Mode().IsRegular()
}

func exists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

// resolve is wiki.sh's: a bare name is a wiki of the collection, anything else a path.
func (o Options) resolve(name string) string {
	switch {
	case strings.HasPrefix(name, "/"):
		return normalize(name)
	case strings.HasPrefix(name, "~/"):
		return normalize(o.Home + "/" + name[2:])
	case strings.Contains(name, "/"):
		return normalize(o.Pwd + "/" + name)
	}
	return o.Wikis + "/" + name
}

// normalize drops . and .. from an absolute path without touching the disk.
func normalize(path string) string {
	out := ""
	for _, part := range strings.Split(path, "/") {
		switch part {
		case "", ".":
		case "..":
			if i := strings.LastIndex(out, "/"); i >= 0 {
				out = out[:i]
			}
		default:
			out += "/" + part
		}
	}
	if out == "" {
		return "/"
	}
	return out
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
