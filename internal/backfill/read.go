package backfill

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/broxgit/llm-wiki/internal/pyos"
)

type reader struct {
	start, end string
	shift      time.Duration
}

// A Claude Code record the Python keeps: a user or assistant turn, not a side chain or
// meta, with a time. What it says is read only when its day is in the range.
type claudeRec struct {
	cwd     string // "" when it has none
	day, hm string
	inRange bool
	err     error // what would stop the Python once it reads this record's turn
	session string
	branch  string
	prompts []string
	end     string
	files   []string
	commit  bool
}

func (rd reader) claude(path string) ([]claudeRec, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	ls, err := lines(data)
	if err != nil {
		return nil, err
	}
	name := stem(filepath.Base(path))
	return eachLine(ls, func(line []byte) (claudeRec, bool, error) {
		var r claudeRec
		m, ok, err := object(line)
		if err != nil || !ok {
			return r, false, err
		}
		if !is(m["type"], "user") && !is(m["type"], "assistant") || truthy(m["isSidechain"]) || truthy(m["isMeta"]) || !truthy(m["timestamp"]) {
			return r, false, nil
		}
		if truthy(m["cwd"]) {
			if r.cwd, ok = str(m["cwd"]); !ok || strings.ContainsRune(r.cwd, 0) {
				return r, false, odd("cwd " + string(m["cwd"]))
			}
		}
		ts, ok := str(m["timestamp"])
		if !ok {
			return r, false, odd("timestamp " + string(m["timestamp"]))
		}
		if r.day, r.hm, ok = pyos.Local(ts, rd.shift); !ok {
			return r, false, odd("timestamp " + ts)
		}
		if r.inRange = r.day >= rd.start && r.day <= rd.end; r.inRange {
			r.err = r.read(m, name)
		}
		return r, true, nil
	})
}

// read takes what the Python takes from a turn in the range.
func (r *claudeRec) read(m map[string]json.RawMessage, stem string) error {
	// sessionId goes in a set, which a list or a number would upset or merge.
	switch kind(m["sessionId"]) {
	case 0:
		r.session = "s" + stem
	case 'n':
		r.session = "n"
	case '"':
		s, _ := str(m["sessionId"])
		r.session = "s" + s
	default:
		return odd("sessionId " + string(m["sessionId"]))
	}
	if truthy(m["gitBranch"]) {
		s, ok := str(m["gitBranch"])
		if !ok {
			return odd("gitBranch " + string(m["gitBranch"]))
		}
		if s != "HEAD" {
			r.branch = s
		}
	}
	var content json.RawMessage
	if truthy(m["message"]) {
		msg, err := asObject(m["message"])
		if err != nil {
			return err
		}
		content = msg["content"]
	}
	if is(m["type"], "user") {
		return r.user(content)
	}
	return r.assistant(content)
}

func (r *claudeRec) user(content json.RawMessage) error {
	var texts []string
	switch kind(content) {
	case '"':
		s, _ := str(content)
		texts = []string{s}
	case '[':
		var items []json.RawMessage
		if json.Unmarshal(content, &items) != nil {
			return odd("content")
		}
		for _, it := range items {
			if kind(it) != '{' {
				continue
			}
			c, err := asObject(it)
			if err != nil {
				return err
			}
			if !is(c["type"], "text") {
				continue
			}
			s, err := text(c)
			if err != nil {
				return err
			}
			texts = append(texts, s)
		}
	case '{':
		// A dict iterates as its keys, none of them a part.
	default:
		if truthy(content) {
			return odd("content " + string(content))
		}
	}
	for _, t := range texts {
		t = strip(t)
		if t == "" || hasPrefix(t, machine) {
			continue
		}
		if hasPrefix(t, brief) {
			if _, after, ok := strings.Cut(t, ":"); ok {
				t = after
			}
			t = "(side session brief) " + clean(t, 160)
		} else {
			t = clean(t, 240)
		}
		if t != "" {
			r.prompts = append(r.prompts, t)
		}
	}
	return nil
}

func (r *claudeRec) assistant(content json.RawMessage) error {
	switch kind(content) {
	case '[':
	case '"', '{':
		// A string iterates as characters and a dict as keys: no parts.
		return nil
	default:
		if truthy(content) {
			return odd("content " + string(content))
		}
		return nil
	}
	var items []json.RawMessage
	if json.Unmarshal(content, &items) != nil {
		return odd("content")
	}
	for _, it := range items {
		if kind(it) != '{' {
			continue
		}
		c, err := asObject(it)
		if err != nil {
			return err
		}
		switch {
		case is(c["type"], "text"):
			s, err := text(c)
			if err != nil {
				return err
			}
			if t := clean(s, 400); t != "" {
				r.end = t
			}
		case is(c["type"], "tool_use"):
			var in map[string]json.RawMessage
			if truthy(c["input"]) {
				if in, err = asObject(c["input"]); err != nil {
					return err
				}
			}
			fp := in["file_path"]
			if !truthy(fp) {
				fp = in["notebook_path"]
			}
			if truthy(fp) && (is(c["name"], "Edit") || is(c["name"], "Write") || is(c["name"], "MultiEdit") || is(c["name"], "NotebookEdit")) {
				s, ok := str(fp)
				if !ok {
					return odd("file_path " + string(fp))
				}
				if b := basename(s); !contains(r.files, b) {
					r.files = append(r.files, b)
				}
			}
			if cmd, ok := in["command"]; ok && mentions(cmd, "git commit") {
				r.commit = true
			}
		}
	}
	return nil
}

// text is c.get("text", "") where the Python goes on to treat it as a string.
func text(c map[string]json.RawMessage) (string, error) {
	raw, ok := c["text"]
	if !ok {
		return "", nil
	}
	s, ok := str(raw)
	if !ok {
		return "", odd("text " + string(raw))
	}
	return s, nil
}

func hasPrefix(s string, prefixes []string) bool {
	for _, p := range prefixes {
		if strings.HasPrefix(s, p) {
			return true
		}
	}
	return false
}

// A step of an Antigravity conversation, cut down to what the digest uses.
type geminiStep struct {
	hasTime   bool // created_at is set
	err       error
	day, hm   string
	user      bool // a USER_INPUT step
	planner   bool // a PLANNER_RESPONSE step
	content   string
	isText    bool // content is a string, or empty
	toolCalls bool // it has tool calls
	calls     []geminiCall
}

type geminiCall struct {
	write bool   // write_file or edit_file
	path  string // its Path
	cmd   string // its CommandLine
	dirs  []string
}

func (rd reader) gemini(path string) ([]geminiStep, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	ls, err := lines(data)
	if err != nil {
		return nil, err
	}
	return eachLine(ls, func(line []byte) (geminiStep, bool, error) {
		var st geminiStep
		m, ok, err := object(line)
		if err != nil || !ok {
			return st, false, err
		}
		if st.calls, err = geminiCalls(m["tool_calls"]); err != nil {
			return st, false, err
		}
		st.toolCalls = truthy(m["tool_calls"])
		if st.hasTime = truthy(m["created_at"]); st.hasTime {
			ts, ok := str(m["created_at"])
			if ok {
				st.day, st.hm, ok = pyos.Local(ts, rd.shift)
			}
			if !ok {
				st.err = odd("created_at " + string(m["created_at"]))
			}
		}
		st.user, st.planner = is(m["type"], "USER_INPUT"), is(m["type"], "PLANNER_RESPONSE")
		// c = e.get("content") or "": anything false is the empty string.
		st.isText = true
		if truthy(m["content"]) {
			st.content, st.isText = str(m["content"])
		}
		return st, true, nil
	})
}

// geminiCalls reads a step's tool calls and the folders they point at that exist: a
// file's folder, and each `-C` folder in a command.
func geminiCalls(raw json.RawMessage) ([]geminiCall, error) {
	if !truthy(raw) {
		return nil, nil
	}
	if kind(raw) != '[' {
		return nil, odd("tool_calls " + string(raw))
	}
	var items []json.RawMessage
	if json.Unmarshal(raw, &items) != nil {
		return nil, odd("tool_calls")
	}
	var calls []geminiCall
	for _, it := range items {
		c, err := asObject(it)
		if err != nil {
			return nil, err
		}
		var a map[string]json.RawMessage
		if truthy(c["args"]) {
			if a, err = asObject(c["args"]); err != nil {
				return nil, err
			}
		}
		var call geminiCall
		var dirs []string
		if truthy(a["Path"]) {
			p, ok := str(a["Path"])
			if !ok {
				return nil, odd("Path " + string(a["Path"]))
			}
			call.path = p
			dirs = append(dirs, pyos.Dirname(p))
		}
		if truthy(a["CommandLine"]) {
			cmd, ok := str(a["CommandLine"])
			if !ok {
				return nil, odd("CommandLine " + string(a["CommandLine"]))
			}
			call.cmd = cmd
			for _, m := range pyos.GitDirFlag.FindAllStringSubmatch(cmd, -1) {
				dirs = append(dirs, m[1])
			}
		}
		for _, d := range dirs {
			// ~name needs a lookup of that user.
			if strings.HasPrefix(d, "~") && d != "~" && !strings.HasPrefix(d, "~/") {
				return nil, odd("path " + d)
			}
			// isdir is false for a path with a NUL, which Python can't stat.
			if d = pyos.ExpandUser(d); !strings.ContainsRune(d, 0) && isDir(d) {
				call.dirs = append(call.dirs, d)
			}
		}
		call.write = is(c["name"], "write_file") || is(c["name"], "edit_file")
		calls = append(calls, call)
	}
	return calls, nil
}

// names gives a folder its project as the Python's project() does: the repository's
// name from its remote, or its folder, or a known project it sits inside, mapped to
// the wiki that covers it. Lookups run side by side, since each asks git.
type names struct {
	wikisReal string
	cover     map[string]string
	known     map[string]bool
	done      map[string]string
}

func newNames(wikis string) (*names, error) {
	entries, err := os.ReadDir(wikis)
	if err != nil {
		return nil, err
	}
	n := &names{wikisReal: pyos.RealPath(wikis), cover: map[string]string{}, known: map[string]bool{}, done: map[string]string{}}
	// Sorted, so when two wikis list one repository the same one wins every run.
	sort.Slice(entries, func(i, j int) bool { return entries[i].Name() < entries[j].Name() })
	for _, e := range entries {
		dir := filepath.Join(wikis, e.Name())
		rp := filepath.Join(dir, "repos.md")
		if _, err := os.Lstat(rp); err == nil {
			data, err := os.ReadFile(rp)
			if err != nil || !utf8.Valid(data) {
				return nil, odd("can't read " + rp)
			}
			for _, line := range splitLines(string(data)) {
				if strings.HasPrefix(line, "- ") {
					n.cover[strip(line[2:])] = e.Name()
				}
			}
		}
		if isFile(filepath.Join(dir, "AGENTS.md")) && isFile(filepath.Join(dir, "index.md")) {
			n.known[e.Name()] = true
		}
	}
	for repo := range n.cover {
		n.known[repo] = true
	}
	return n, nil
}

// resolve looks up every folder not seen yet.
func (n *names) resolve(dirs []string) {
	var todo []string
	for _, d := range dirs {
		if _, ok := n.done[d]; !ok {
			n.done[d] = ""
			todo = append(todo, d)
		}
	}
	out := make([]string, len(todo))
	var wg sync.WaitGroup
	slots := make(chan struct{}, 8)
	for i, d := range todo {
		wg.Add(1)
		go func(i int, d string) {
			defer wg.Done()
			slots <- struct{}{}
			out[i] = n.lookup(d)
			<-slots
		}(i, d)
	}
	wg.Wait()
	for i, d := range todo {
		n.done[d] = out[i]
	}
}

// project is the project of a folder resolve has seen, and "unknown" for no folder.
func (n *names) project(cwd string) string {
	if cwd == "" {
		return "unknown"
	}
	return n.done[cwd]
}

func (n *names) lookup(cwd string) string {
	name := basename(strings.TrimRight(cwd, "/"))
	if name == "" {
		name = cwd
	}
	if isDir(cwd) {
		if r, ok := pyos.RepoName(cwd); ok {
			name = r
		}
	}
	if pyos.RealPath(cwd) == n.wikisReal {
		name = "wikis"
	}
	// A scratch folder inside a project, such as myapp/sweeps/b41, belongs to that project.
	if !n.known[name] {
		parts := pyos.PathParts(cwd)
		for i := len(parts) - 2; i >= 0; i-- {
			if n.known[parts[i]] {
				name = parts[i]
				break
			}
		}
	}
	if w, ok := n.cover[name]; ok {
		return w
	}
	return name
}
