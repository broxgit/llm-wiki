// Package status answers the slow half of `wiki status`: the table of a collection's
// wikis, with the handbook version, the notes waiting, the compile lock and what each
// row flags, the to-do lines those flags give, and the notes waiting in other
// collections. It prints what status_table and status_waiting in wiki.sh print, and
// that Bash is the fallback where this program isn't built, so the two are kept the
// same and a smoke test compares them. Everything after the table stays in wiki.sh:
// it reads the machine's setup, which only wiki.sh knows.
//
// The Bash runs under LC_ALL=C, so everything here is by byte, and the order of the
// wikis is byte order. What this can't be sure of is an error, and the Bash answers:
// a folder or file it can't read, a file with a NUL byte, a link under a wiki's wiki/
// folder, a name with a line break, a wiki with no log.md, and numbers or dates the
// shell or awk might read differently.
package status

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"regexp"
	"strconv"
	"strings"

	"github.com/broxgit/llm-wiki/internal/routing"
)

// Options are what wiki.sh has worked out by the time it asks.
type Options struct {
	Wikis           string   // the collection's folder
	TemplateVersion string   // the template's handbook version, or "" when unknown
	WikiCmd         string   // the command people type, for the to-do lines
	Plugin          bool     // wiki.sh runs from the plugin's folder
	Also            []string // other collections' folders, for their notes waiting
}

// Result is what wiki.sh prints of it, and what it needs to go on.
type Result struct {
	Rows  []string // the table: the header, then a row per wiki, or the line for none
	Todos []string // to-do lines, without the "- " they are listed with
	Ahead bool     // a wiki is ahead of this plugin's template
	Also  []int    // the notes waiting in each of Options.Also
}

// Run gives the table, its to-do lines, and the counts for the other collections.
func Run(o Options) (Result, error) {
	var r Result
	tv, err := number(o.TemplateVersion, true)
	if err != nil {
		return r, err
	}
	names, err := routing.Folders(o.Wikis)
	if err != nil {
		return r, err
	}
	r.Rows = append(r.Rows, row("WIKI", "HANDBOOK", "WAITING", "LOCK"))
	var behind []string
	found := false
	for _, w := range names {
		dir := o.Wikis + "/" + w
		if ok, err := isWiki(dir); err != nil {
			return r, err
		} else if !ok {
			continue
		}
		found = true
		if strings.Contains(w, "\n") {
			return r, errors.New("a wiki's name for the Bash: " + w)
		}
		v, err := version(dir + "/AGENTS.md")
		if err != nil {
			return r, err
		}
		waiting, err := pending(dir)
		if err != nil {
			return r, err
		}
		lock, err := lockLine(dir + "/.compile-lock")
		if err != nil {
			return r, err
		}
		note := ""
		if waiting >= 5 {
			note += "  <- compile due"
			r.Todos = append(r.Todos, fmt.Sprintf(`%s: %d notes waiting. Ask an agent: "compile %s" (in Claude Code: /llm-wiki:compile %s)`, w, waiting, w, w))
		}
		since, err := ingestsSinceLint(dir + "/log.md")
		if err != nil {
			return r, err
		}
		if since >= 10 {
			note += fmt.Sprintf("  <- lint due (%d ingests)", since)
			r.Todos = append(r.Todos, fmt.Sprintf(`%s: lint due, %d ingests since the last. Ask an agent: "lint %s"`, w, since, w))
		}
		ready, regressed, err := patterns(dir + "/patterns.md")
		if err != nil {
			return r, err
		}
		if ready > 0 {
			note += fmt.Sprintf("  <- %d pattern(s) ready", ready)
			r.Todos = append(r.Todos, fmt.Sprintf(`%s: %d repeated pattern(s) ready for a fix. Ask an agent: "propose the ready patterns in %s"`, w, ready, w))
		}
		if regressed > 0 {
			note += fmt.Sprintf("  <- %d accepted fix(es) not working", regressed)
			r.Todos = append(r.Todos, fmt.Sprintf(`%s: %d accepted fix(es) seen again, so not working. Ask an agent: "look again at the patterns marked AGAIN in %s"`, w, regressed, w))
		}
		// [ "${v:-0}" -lt "$tv" ]: no version line reads as 0.
		n := int64(0)
		if v != "" {
			n, _ = number(v, false)
		}
		if tv >= 0 && n < tv {
			note += fmt.Sprintf("  <- behind template v%d", tv)
			// The Bash lists these unquoted, so the shell would split and expand a name.
			if strings.ContainsAny(w, " \t*?[") {
				return r, errors.New("a wiki's name for the Bash: " + w)
			}
			behind = append(behind, w)
		}
		if tv >= 0 && n > tv {
			if o.Plugin {
				r.Ahead = true
				note += fmt.Sprintf("  <- ahead of this plugin's template v%d", tv)
			} else {
				note += fmt.Sprintf("  <- ahead of your template v%d", tv)
				r.Todos = append(r.Todos, w+": upgraded by a newer llm-wiki than this one. Run: "+o.WikiCmd+" update")
			}
		}
		covers, err := repos(dir + "/repos.md")
		if err != nil {
			return r, err
		}
		if covers != "" {
			note += "  covers: " + covers
		}
		if v == "" {
			v = "?"
		}
		r.Rows = append(r.Rows, row(w, "v"+v, strconv.Itoa(waiting), lock+note))
	}
	if !found {
		r.Rows = append(r.Rows, "(none yet. Run: "+o.WikiCmd+" init)")
	}
	switch len(behind) {
	case 0:
	case 1:
		r.Todos = append(r.Todos, fmt.Sprintf("%s: handbook behind template v%d. Run: %s upgrade %s", behind[0], tv, o.WikiCmd, behind[0]))
	default:
		r.Todos = append(r.Todos, fmt.Sprintf("%d wikis' handbooks behind template v%d (%s). Run: %s upgrade --all", len(behind), tv, strings.Join(behind, " "), o.WikiCmd))
	}
	for _, c := range o.Also {
		n, err := waitingIn(c)
		if err != nil {
			return r, err
		}
		r.Also = append(r.Also, n)
	}
	return r, nil
}

// row is printf '%-26s %-9s %-8s %s' under LC_ALL=C, which pads by byte.
func row(name, version, waiting, rest string) string {
	return pad(name, 26) + " " + pad(version, 9) + " " + pad(waiting, 8) + " " + rest
}

func pad(s string, n int) string {
	if len(s) >= n {
		return s
	}
	return s + strings.Repeat(" ", n-len(s))
}

// waitingIn is status_waiting: the notes waiting in all of a collection's wikis.
func waitingIn(root string) (int, error) {
	names, err := routing.Folders(root)
	if routing.NotThere(err) {
		return 0, nil
	}
	if err != nil {
		return 0, err
	}
	total := 0
	for _, w := range names {
		if ok, err := isWiki(root + "/" + w); err != nil {
			return 0, err
		} else if !ok {
			continue
		}
		n, err := pending(root + "/" + w)
		if err != nil {
			return 0, err
		}
		total += n
	}
	return total, nil
}

// isWiki is wiki.sh's is_wiki.
func isWiki(dir string) (bool, error) {
	if ok, err := routing.IsFile(dir + "/AGENTS.md"); err != nil || !ok {
		return false, err
	}
	return routing.IsFile(dir + "/index.md")
}

// number reads a version as the shell's test does, or -1 for "" when that is allowed.
// One too long for the shell's integers is the Bash's.
func number(s string, empty bool) (int64, error) {
	if s == "" && empty {
		return -1, nil
	}
	if s == "" || len(s) > 18 || strings.Trim(s, "0123456789") != "" {
		return 0, errors.New("a number for the Bash: " + s)
	}
	return strconv.ParseInt(s, 10, 64)
}

// version is version_of: the digits after "Handbook version " on the first line that
// has them, or "".
func version(path string) (string, error) {
	lines, err := readLines(path)
	if err != nil {
		return "", err
	}
	for _, line := range lines {
		rest, ok := bytes.CutPrefix(line, []byte("Handbook version "))
		if !ok {
			continue
		}
		n := 0
		for n < len(rest) && rest[n] >= '0' && rest[n] <= '9' {
			n++
		}
		if n > 0 {
			v := string(rest[:n])
			if _, err := number(v, false); err != nil {
				return "", err
			}
			return v, nil
		}
	}
	return "", nil
}

// lockLine is the LOCK column: the lock file's first line when it says the lock is
// held, and "free" otherwise.
func lockLine(path string) (string, error) {
	ok, err := routing.IsFile(path)
	if err != nil || !ok {
		return "free", err
	}
	data, err := readText(path)
	if err != nil {
		return "", err
	}
	line, _, _ := bytes.Cut(data, []byte("\n"))
	if bytes.HasPrefix(line, []byte("held")) {
		return string(line), nil
	}
	return "free", nil
}

var (
	lintEntry   = regexp.MustCompile(`^## [0-9-]+ lint`)
	ingestEntry = regexp.MustCompile(`^## [0-9-]+ ingest`)
)

// ingestsSinceLint is the awk that counts ingest entries since the last lint entry.
// Without a log.md that awk fails, and under set -e the Bash stops there, so that is
// the Bash's to show.
func ingestsSinceLint(path string) (int, error) {
	if ok, err := routing.IsFile(path); err != nil {
		return 0, err
	} else if !ok {
		return 0, errors.New("no log.md, which the Bash stops at: " + path)
	}
	lines, err := readLines(path)
	if err != nil {
		return 0, err
	}
	n := 0
	for _, line := range lines {
		if lintEntry.Match(line) {
			n = 0
		}
		if ingestEntry.Match(line) {
			n++
		}
	}
	return n, nil
}

// repos is what status shows after "covers:": the repositories repos.md lists, each
// with the space tr makes of its line feed. A last line with none gets none, as sed
// prints it without one.
func repos(path string) (string, error) {
	ok, err := routing.IsFile(path)
	if err != nil || !ok {
		return "", err
	}
	data, err := readText(path)
	if err != nil {
		return "", err
	}
	var b strings.Builder
	for len(data) > 0 {
		line, rest, ended := bytes.Cut(data, []byte("\n"))
		data = rest
		if item, ok := bytes.CutPrefix(line, []byte("- ")); ok {
			b.Write(item)
			if ended {
				b.WriteByte(' ')
			}
		}
	}
	return b.String(), nil
}

// readText reads a file a grep, sed or awk reads. One with a NUL byte is read
// differently by GNU's and BSD's tools, so it is the Bash's.
func readText(path string) ([]byte, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	if bytes.IndexByte(data, 0) >= 0 {
		return nil, errors.New("not plain text: " + path)
	}
	return data, nil
}

// readLines is readText as lines that end at a line feed, the last one with or
// without it.
func readLines(path string) ([][]byte, error) {
	data, err := readText(path)
	if err != nil {
		return nil, err
	}
	if len(data) == 0 {
		return nil, nil
	}
	return bytes.Split(bytes.TrimSuffix(data, []byte("\n")), []byte("\n")), nil
}
