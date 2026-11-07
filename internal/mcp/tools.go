package mcp

import (
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/broxgit/llm-wiki/internal/find"
	"github.com/broxgit/llm-wiki/internal/pyos"
	"github.com/broxgit/llm-wiki/internal/routing"
)

const (
	maxRead      = 200_000          // characters of a file wiki_read returns
	maxNote      = 200_000          // characters of a note wiki_capture takes
	lookupWindow = 10 * time.Minute // several reads for one question count once
	shared       = "global"         // SHARED in wiki.sh: the wiki a search that found nothing is logged against
)

// name is what a wiki, a repository or a slug may be. Python's $ also matches before a
// line feed at the very end, so one is let through here too, and wiki.sh or the lookup
// then refuses the name in both servers alike.
var name = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._-]*\n?$`)

// readable is the files wiki_read gives out.
var readable = []string{".md", ".csv", ".txt"}

// toolError is server.py's ToolError: an answer the tool meant to give, marked as an
// error. Any other error from a tool is a JSON-RPC error, as an exception is there.
type toolError string

func (e toolError) Error() string { return string(e) }

// args is a call's arguments.
type args map[string]any

// text is `args.get(key) or ""`. Python then uses the value as a string and fails on
// anything else that isn't empty: here that is the same error code, with a message
// that names the argument.
func (a args) text(key string) (string, error) {
	v := a[key]
	if !truthy(v) {
		return "", nil
	}
	s, ok := v.(string)
	if !ok {
		return "", fmt.Errorf("%s must be a string", key)
	}
	return s, nil
}

type tool struct {
	name     string
	run      func(*Server, args) (string, error)
	desc     string
	props    map[string]any
	required []string
	readOnly bool
}

func str(desc string) map[string]any {
	if desc == "" {
		return map[string]any{"type": "string"}
	}
	return map[string]any{"type": "string", "description": desc}
}

var collectionProp = str("Only when wiki_list shows the name in more than one collection.")

// tools is server.py's TOOLS, in its order.
var tools = []tool{
	{"wiki_list", (*Server).wikiList, "List the wikis: name, collection, page count, and the repositories each covers.",
		map[string]any{}, []string{}, true},
	{"wiki_start", (*Server).wikiStart, "Start here for any question about the user's rules, preferences, decisions, projects or past work, before memory or past chats, which can be out of date. Pull the wikis, and return the index of the project's wiki and the shared wiki, plus the agreements every session follows. With no repository, the shared wiki's.",
		map[string]any{"repository": str("The project or repository, if there is one."), "collection": collectionProp}, []string{}, false},
	{"wiki_search", (*Server).wikiSearch, "Search the user's own wikis, their current record of rules, decisions and past work, by a word: a topic, an identifier, an error string, a name. Use it before memory or past chats.",
		map[string]any{"word": str(""), "collection": collectionProp}, []string{"word"}, true},
	{"wiki_read", (*Server).wikiRead, "Read a file in a wiki: a page its index names, such as wiki/conventions.md. Defaults to index.md.",
		map[string]any{"wiki": str(""), "path": str("Relative to the wiki's folder."), "collection": collectionProp}, []string{"wiki"}, true},
	{"wiki_status", (*Server).wikiStatus, "What needs attention across the wikis, each item with its fix.",
		map[string]any{"collection": collectionProp}, []string{}, true},
	{"wiki_capture", (*Server).wikiCapture, "Save a note in a wiki, for a later session to compile: a decision and its reason, a correction, a finding with its source. Plain markdown. It commits and pushes that wiki.",
		map[string]any{"wiki": str(""), "slug": str("A short name, such as postgres-over-sqlite."), "note": str(""), "collection": collectionProp}, []string{"wiki", "slug", "note"}, false},
	{"wiki_feedback", (*Server).wikiFeedback, "Keep one note about llm-wiki itself when it got in your way, if wiki_start shows a Feedback section. Nothing is sent anywhere; the user reads it.",
		map[string]any{
			"kind":    map[string]any{"type": "string", "enum": []string{"bug", "friction", "docs", "idea"}},
			"summary": str(""),
			"details": str("What you ran, what it returned, what you expected, what would have helped."),
			"agent":   str("Your app and model."),
		}, []string{"kind", "summary", "details"}, false},
}

func toolList() []map[string]any {
	list := make([]map[string]any, 0, len(tools))
	for _, t := range tools {
		list = append(list, map[string]any{
			"name":        t.name,
			"description": t.desc,
			"inputSchema": map[string]any{"type": "object", "properties": t.props, "required": t.required},
			"annotations": map[string]any{"readOnlyHint": t.readOnly},
		})
	}
	return list
}

// callTool is server.py's call_tool: the tool's text, or its error as text, or nothing
// for a tool there isn't.
func (s *Server) callTool(params map[string]any) (any, error) {
	called, _ := params["name"].(string)
	for _, t := range tools {
		if t.name != called {
			continue
		}
		a, err := object(params["arguments"], "arguments")
		// wiki_list takes none, so in Python nothing looks at what was sent.
		if err != nil && t.name != "wiki_list" {
			return nil, err
		}
		out, err := t.run(s, a)
		var failed toolError
		if errors.As(err, &failed) {
			return map[string]any{"content": []map[string]any{{"type": "text", "text": string(failed)}}, "isError": true}, nil
		}
		if err != nil {
			return nil, err
		}
		return map[string]any{"content": []map[string]any{{"type": "text", "text": out}}}, nil
	}
	return nil, &rpcError{methodNotFound, "unknown method or tool"}
}

// isFile is os.path.isfile: a file, or a link to one. What can't be looked at isn't one.
func isFile(path string) bool {
	st, err := os.Stat(path)
	return err == nil && st.Mode().IsRegular()
}

func isWiki(dir string) bool {
	return isFile(dir+"/AGENTS.md") && isFile(dir+"/index.md")
}

// wikisIn is the wikis of a collection, by name, in the order of their bytes.
func wikisIn(folder string) []string {
	entries, err := os.ReadDir(folder)
	if err != nil {
		return nil
	}
	var names []string
	for _, e := range entries {
		if !strings.HasPrefix(e.Name(), ".") && isWiki(folder+"/"+e.Name()) {
			names = append(names, e.Name())
		}
	}
	return names
}

func (s *Server) pickCollection(called string) (Collection, error) {
	if len(s.Collections) == 0 {
		return Collection{}, toolError("no wiki collections are set up. Run: wiki setup")
	}
	if called == "" {
		return s.Collections[0], nil
	}
	var names []string
	for _, c := range s.Collections {
		if c.Name == called {
			return c, nil
		}
		names = append(names, c.Name)
	}
	return Collection{}, toolError("no collection called " + called + ". Collections: " + strings.Join(names, ", "))
}

// findWiki is server.py's find_wiki: the collection and folder of a wiki by name, in
// the named collection, or the first that has it.
func (s *Server) findWiki(a args) (wiki string, in Collection, root string, err error) {
	if wiki, err = a.text("wiki"); err != nil {
		return "", in, "", err
	}
	if !name.MatchString(wiki) {
		return "", in, "", toolError("that isn't a wiki name. wiki_list lists them.")
	}
	called, err := a.text("collection")
	if err != nil {
		return "", in, "", err
	}
	among := s.Collections
	if called != "" {
		c, err := s.pickCollection(called)
		if err != nil {
			return "", in, "", err
		}
		among = []Collection{c}
	}
	for _, c := range among {
		if isWiki(c.Folder + "/" + wiki) {
			return wiki, c, c.Folder + "/" + wiki, nil
		}
	}
	return "", in, "", toolError("no wiki called " + wiki + ". wiki_list lists them.")
}

func (s *Server) wikiList(args) (string, error) {
	var lines []string
	for _, c := range s.Collections {
		for _, w := range wikisIn(c.Folder) {
			dir := c.Folder + "/" + w
			line := fmt.Sprintf("%s (collection %s): %d page(s)", w, c.Name, countPages(dir+"/wiki"))
			if repos := reposIn(dir + "/repos.md"); len(repos) > 0 {
				line += ", covers: " + strings.Join(repos, " ")
			}
			lines = append(lines, line)
		}
	}
	if len(lines) == 0 {
		return "No wikis yet. Run: wiki setup", nil
	}
	return strings.Join(lines, "\n"), nil
}

// countPages is the .md files os.walk finds under a folder: in every folder below it,
// hidden ones too, but not through a link to a folder. What can't be listed counts
// nothing. A link to a file counts, and so does one that leads nowhere.
func countPages(dir string) int {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return 0
	}
	n := 0
	for _, e := range entries {
		path := dir + "/" + e.Name()
		switch {
		case e.IsDir():
			n += countPages(path)
		case e.Type()&fs.ModeSymlink != 0 && isDir(path):
		case strings.HasSuffix(e.Name(), ".md"):
			n++
		}
	}
	return n
}

func isDir(path string) bool {
	st, err := os.Stat(path)
	return err == nil && st.IsDir()
}

// reposIn is the repositories a repos.md lists: what follows "- " on each such line.
// Python stops the whole listing at a repos.md that isn't UTF-8. This reads it.
func reposIn(path string) []string {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	var repos []string
	for _, line := range strings.Split(text(data), "\n") {
		if rest, ok := strings.CutPrefix(line, "- "); ok {
			repos = append(repos, strip(rest))
		}
	}
	return repos
}

// covers is whether `wiki.sh which <repository>` succeeds in a collection. Where
// routing isn't sure, wiki.sh says.
func (s *Server) covers(folder, repo string) bool {
	_, covered, err := routing.Which(routing.Options{Wikis: folder, Home: s.Home, WikiCmd: "wiki.sh", Name: repo})
	if err != nil {
		ok, _ := s.run(folder, "", "which", repo)
		return ok
	}
	return covered
}

func (s *Server) wikiStart(a args) (string, error) {
	repo, err := a.text("repository")
	if err != nil {
		return "", err
	}
	if repo != "" && !name.MatchString(repo) {
		return "", toolError("that isn't a repository name.")
	}
	called, err := a.text("collection")
	if err != nil {
		return "", err
	}
	var folder string
	if repo != "" && called == "" {
		// The first collection with a wiki for this repository, or the default.
		for _, c := range s.Collections {
			if s.covers(c.Folder, repo) {
				folder = c.Folder
				break
			}
		}
	}
	if folder == "" {
		c, err := s.pickCollection(called)
		if err != nil {
			return "", err
		}
		folder = c.Folder
	}
	if repo != "" {
		return s.must(folder, "", "start", repo)
	}
	return s.must(folder, "", "start")
}

func (s *Server) wikiSearch(a args) (string, error) {
	word, err := a.text("word")
	if err != nil {
		return "", err
	}
	word = strip(word)
	if word == "" || strings.HasPrefix(word, "-") {
		return "", toolError("give a word to search for.")
	}
	called, err := a.text("collection")
	if err != nil {
		return "", err
	}
	chosen := s.Collections
	if called != "" {
		c, err := s.pickCollection(called)
		if err != nil {
			return "", err
		}
		chosen = []Collection{c}
	}
	var parts []string
	for _, c := range chosen {
		out, err := s.find(c.Folder, word)
		if err != nil {
			return "", err
		}
		if len(chosen) > 1 {
			out = "Collection " + c.Name + ":\n" + out
		}
		parts = append(parts, out)
	}
	return strings.Join(parts, "\n\n"), nil
}

// find is what `wiki.sh find <word>` gives the Python for one collection, without
// running it: the search, and the two things cmd_find and record_use write besides,
// the line in stats.csv and the note that find has been used. Each is written once,
// here or by wiki.sh. Where the search isn't sure, wiki.sh does all of it.
func (s *Server) find(folder, word string) (string, error) {
	if !isDir(folder) {
		s.tipUsed("find")
		return "", toolError("error: no wikis at " + tilde(s.Home, folder))
	}
	out, first, err := find.Search(find.Options{Wikis: folder, Word: word})
	if err != nil {
		return s.must(folder, "", "find", word)
	}
	s.tipUsed("find")
	if first == "" {
		s.statsLog(folder, shared, "search-none", word)
	} else {
		s.statsLog(folder, first, "search-found", word)
	}
	// Pages are read as bytes. Python reads what wiki.sh prints of them as text.
	return strip(text([]byte(out))), nil
}

// tilde is wiki.sh's tilde: the path with the home folder written as ~.
func tilde(home, p string) string {
	if rest, ok := strings.CutPrefix(p, home+"/"); ok {
		return "~/" + rest
	}
	return p
}

// statsLog is wiki.sh's stats_log: one line in the collection's stats.csv, under a
// heading when the file is new or empty. The word loses its commas and is cut at 60
// bytes, less a character the cut left unfinished. It must never fail a search, such
// as where the file can't be written.
func (s *Server) statsLog(folder, wiki, result, word string) {
	f, err := os.OpenFile(folder+"/stats.csv", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o666)
	if err != nil {
		return
	}
	defer f.Close()
	line := ""
	if st, err := f.Stat(); err == nil && st.Size() == 0 {
		line = "date,wiki,result,word\n"
	}
	word = strings.NewReplacer(",", "", "\n", "").Replace(word)
	if len(word) > 60 {
		word = string(find.Whole([]byte(word[:60])))
	}
	line += time.Now().UTC().Format("2006-01-02") + "," + wiki + "," + result + "," + word + "\n"
	_, _ = io.WriteString(f, line)
}

// tipUsed is wiki.sh's record_use for one command: today's date against used:<command>
// in the tips file, in place of an older one, so the tip about that command stops.
// Bookkeeping only: nothing may fail because it can't be written.
func (s *Server) tipUsed(command string) {
	if s.Tips == "" {
		return
	}
	key := "used:" + command
	_ = os.MkdirAll(filepath.Dir(s.Tips), 0o777)
	data, err := os.ReadFile(s.Tips)
	if errors.Is(err, fs.ErrNotExist) {
		data, err = []byte("# Commands used, and tips shown or muted, on this machine. Written by wiki.sh.\n"), nil
	}
	if err != nil {
		return
	}
	var b strings.Builder
	for _, line := range strings.Split(strings.TrimSuffix(string(data), "\n"), "\n") {
		if len(data) == 0 {
			break
		}
		// awk's $1 != k.
		if f := strings.FieldsFunc(line, func(r rune) bool { return r == ' ' || r == '\t' }); len(f) > 0 && f[0] == key {
			continue
		}
		b.WriteString(line + "\n")
	}
	b.WriteString(key + " " + time.Now().UTC().Format("2006-01-02") + "\n")
	tmp := s.Tips + ".tmp"
	if os.WriteFile(tmp, []byte(b.String()), 0o666) != nil {
		return
	}
	_ = os.Rename(tmp, s.Tips)
}

func (s *Server) wikiRead(a args) (string, error) {
	wiki, in, root, err := s.findWiki(a)
	if err != nil {
		return "", err
	}
	rel, err := a.text("path")
	if err != nil {
		return "", err
	}
	if rel == "" {
		rel = "index.md"
	}
	if strings.HasPrefix(rel, "/") || strings.HasPrefix(rel, "~") {
		return "", toolError("give a path inside the wiki, such as index.md or wiki/conventions.md.")
	}
	// The real path first, so neither .. nor a link gets out of the wiki.
	full := pyos.RealPath(root + "/" + rel)
	inside, err := filepath.Rel(pyos.RealPath(root), full)
	if err != nil {
		return "", toolError("that path is outside the wiki.")
	}
	for _, part := range strings.Split(inside, "/") {
		if strings.HasPrefix(part, ".") {
			return "", toolError("that path is outside the wiki.")
		}
	}
	ok := false
	for _, end := range readable {
		ok = ok || strings.HasSuffix(full, end)
	}
	if !ok {
		return "", toolError("only .md, .csv and .txt files can be read.")
	}
	out, err := readText(full)
	if err != nil {
		return "", toolError("no file " + rel + " in that wiki. Its index.md lists the pages.")
	}
	if strings.HasPrefix(inside, "wiki/") {
		s.logLookup(in.Folder, wiki)
	}
	return out, nil
}

// readText is a file's first maxRead characters as Python's text mode reads them, with
// a line saying so when there were more. Only a file is read: opening a pipe would
// never return.
func readText(path string) (string, error) {
	if st, err := os.Stat(path); err != nil {
		return "", err
	} else if !st.Mode().IsRegular() {
		return "", errors.New("not a file")
	}
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	// A character is four bytes at most, so this holds one character more than is
	// returned, however the file is written.
	data, err := io.ReadAll(io.LimitReader(f, 4*(maxRead+1)+4))
	if err != nil {
		return "", err
	}
	out := text(data)
	n := 0
	for i := range out {
		if n == maxRead {
			return out[:i] + fmt.Sprintf("\n\n[cut off at %d characters]", maxRead), nil
		}
		n++
	}
	return out, nil
}

// logLookup is server.py's log_lookup for a page that was read: one "hit" line in the
// collection's stats.csv, as the handbook asks of sessions with a shell. Chat can't
// append to a file, so the server does it. It must never fail a read.
func (s *Server) logLookup(folder, wiki string) {
	now := time.Now()
	key := [2]string{folder, wiki}
	// Several reads for one question count once.
	if last, ok := s.lookups[key]; ok && now.Sub(last) < lookupWindow {
		return
	}
	if s.lookups == nil {
		s.lookups = map[[2]string]time.Time{}
	}
	s.lookups[key] = now
	path := folder + "/stats.csv"
	line := now.UTC().Format("2006-01-02") + "," + wiki + ",hit\n"
	if _, err := os.Stat(path); err != nil {
		line = "date,wiki,result\n" + line
	}
	f, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o666)
	if err != nil {
		return
	}
	defer f.Close()
	_, _ = io.WriteString(f, line)
}

func (s *Server) wikiStatus(a args) (string, error) {
	called, err := a.text("collection")
	if err != nil {
		return "", err
	}
	c, err := s.pickCollection(called)
	if err != nil {
		return "", err
	}
	return s.must(c.Folder, "", "status")
}

func (s *Server) wikiCapture(a args) (string, error) {
	wiki, in, _, err := s.findWiki(a)
	if err != nil {
		return "", err
	}
	slug, err := a.text("slug")
	if err != nil {
		return "", err
	}
	if !name.MatchString(slug) {
		return "", toolError("the slug is a short name: letters, digits, dashes.")
	}
	note, err := a.text("note")
	if err != nil {
		return "", err
	}
	if strip(note) == "" {
		return "", toolError("the note is empty.")
	}
	if utf8.RuneCountInString(note) > maxNote {
		return "", toolError(fmt.Sprintf("the note is over %d characters. Save the main points.", maxNote))
	}
	out, err := s.must(in.Folder, note, "capture", wiki, slug)
	if err != nil {
		return "", err
	}
	ok, synced := s.run(in.Folder, "", "sync", wiki, "-m", wiki+": capture "+slug)
	// sync also ends well with nothing pushed: no remote, or a folder that isn't in a
	// repository the wikis own. Only its "synced: " line says the note left this machine.
	if ok && (strings.HasPrefix(synced, "synced: ") || strings.Contains(synced, "\nsynced: ")) {
		return out + "\nPushed. A later session with file access compiles it into pages.", nil
	}
	why := "sync failed"
	if synced != "" {
		why = lastLine(synced)
	}
	return out + "\nSaved on this machine, but not pushed: " + why, nil
}

func (s *Server) wikiFeedback(a args) (string, error) {
	c, err := s.pickCollection("")
	if err != nil {
		return "", err
	}
	var got [4]string
	for i, key := range []string{"kind", "summary", "agent", "details"} {
		if got[i], err = a.text(key); err != nil {
			return "", err
		}
	}
	kind, summary, agent, details := got[0], got[1], got[2], got[3]
	if agent == "" {
		agent = "unknown, through MCP"
	}
	return s.must(c.Folder, details, "feedback", "add", kind, summary, "--agent", agent)
}
