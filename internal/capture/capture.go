// Package capture is `wiki capture`: it saves a note, or a copy of a file, in a wiki's
// raw folder under a name that starts with the clock. It writes what cmd_capture's Bash
// writes and says what it says, the refusals included.
package capture

import (
	"bytes"
	"errors"
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
	// TTY says stdin is a terminal, where there is no note to read.
	TTY   bool
	Args  []string         // the command's own arguments
	Stdin io.Reader        // the note, when no --file or --copy names one
	Now   func() time.Time // the clock; nil means time.Now
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
	if !isFile(root+"/AGENTS.md") || !isFile(root+"/index.md") {
		return "", refuse(o.tilde(root) + " is not a wiki")
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
	for n := 2; exists(root + "/raw/" + name); n++ {
		name = stamp + "-" + slug + "-" + strconv.Itoa(n) + "." + ext
	}
	dest := root + "/raw/" + name
	if err := os.MkdirAll(root+"/raw", 0o777); err != nil {
		return "", refuse(o.cantWrite(root + "/raw"))
	}
	if copyFrom != "" {
		// cp gives the copy the file's own permissions, less the umask.
		info, err := os.Stat(copyFrom)
		if err != nil {
			return "", refuse(o.cantWrite(dest))
		}
		data, err := os.ReadFile(copyFrom)
		if err != nil || write(dest, data, info.Mode().Perm()) != nil {
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
		if write(dest, note, perm) != nil {
			return "", refuse(o.cantWrite(dest))
		}
	}
	return "captured: raw/" + name + " in " + o.tilde(root), nil
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

// write is cp onto a path: the file is made or emptied, a link followed.
func write(path string, data []byte, perm os.FileMode) error {
	f, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, perm)
	if err != nil {
		return err
	}
	if _, err := f.Write(data); err != nil {
		_ = f.Close()
		return err
	}
	return f.Close()
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
