package tokens

import (
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"

	"github.com/broxgit/llm-wiki/internal/pyos"
)

// projects names the project a session's working folder belongs to, as the report
// does: the repository's name from its remote, or its folder, mapped to the wiki that
// covers it. A folder is looked up once, and lookups run side by side, because each
// one asks git and a week of sessions holds hundreds of folders.
type projects struct {
	wikis     string
	wikisReal string
	cover     map[string]string
	known     map[string]bool
	names     map[string]string
}

func newProjects(wikis string) (*projects, error) {
	p := &projects{wikis: wikis, wikisReal: pyos.RealPath(wikis), cover: map[string]string{}, known: map[string]bool{}, names: map[string]string{}}
	entries, err := os.ReadDir(wikis)
	if err != nil {
		return nil, err
	}
	// Sorted, so when two wikis list one repository the same one wins every run.
	sort.Slice(entries, func(i, j int) bool { return entries[i].Name() < entries[j].Name() })
	for _, e := range entries {
		dir := filepath.Join(wikis, e.Name())
		if st, err := os.Stat(dir); err != nil || !st.IsDir() {
			continue
		}
		if data, err := os.ReadFile(filepath.Join(dir, "repos.md")); err == nil {
			for _, line := range splitLines(string(data)) {
				if strings.HasPrefix(line, "- ") {
					p.cover[strings.TrimSpace(line[2:])] = e.Name()
				}
			}
		}
		if st, err := os.Stat(filepath.Join(dir, "AGENTS.md")); err == nil && st.Mode().IsRegular() {
			p.known[e.Name()] = true
		}
	}
	for repo, wiki := range p.cover {
		p.known[repo] = true
		p.known[wiki] = true
	}
	return p, nil
}

// splitLines is str.splitlines for the line ends a repos.md can hold.
func splitLines(s string) []string {
	return strings.FieldsFunc(strings.ReplaceAll(s, "\r\n", "\n"), func(r rune) bool { return r == '\n' || r == '\r' })
}

// resolve looks up every session folder not seen yet.
func (p *projects) resolve(cwds []string) {
	var dirs []string
	for _, c := range cwds {
		if c != "" {
			dirs = append(dirs, c)
		}
	}
	p.resolveWith(dirs, p.lookup)
}

// resolveWith runs a lookup on every folder not seen yet, several at a time.
func (p *projects) resolveWith(dirs []string, lookup func(string) string) {
	var todo []string
	for _, c := range dirs {
		if _, ok := p.names[c]; !ok {
			todo = append(todo, c)
			p.names[c] = ""
		}
	}
	out := make([]string, len(todo))
	var wg sync.WaitGroup
	slots := make(chan struct{}, 8)
	for i, c := range todo {
		wg.Add(1)
		go func(i int, c string) {
			defer wg.Done()
			slots <- struct{}{}
			out[i] = lookup(c)
			<-slots
		}(i, c)
	}
	wg.Wait()
	for i, c := range todo {
		p.names[c] = out[i]
	}
}

// name is the project for a folder resolve has seen, or "" for none.
func (p *projects) name(cwd string) string { return p.names[cwd] }

func (p *projects) lookup(cwd string) string {
	name := filepath.Base(strings.TrimRight(cwd, "/"))
	if strings.TrimRight(cwd, "/") == "" {
		name = cwd
	}
	if st, err := os.Stat(cwd); err == nil && st.IsDir() {
		if n, ok := pyos.RepoName(cwd); ok {
			name = n
		}
	}
	if pyos.RealPath(cwd) == p.wikisReal {
		name = "wikis"
	}
	if w, ok := p.cover[name]; ok {
		name = w
	}
	// A scratch folder inside a project, such as myapp/sweeps/b41, belongs to it.
	if !p.known[name] && name != "wikis" {
		parts := pyos.PathParts(cwd)
		name = ""
		for i := len(parts) - 2; i >= 0; i-- {
			if p.known[parts[i]] {
				name = parts[i]
				break
			}
		}
	}
	return name
}

// lookupPath names the project a folder a Gemini tool call pointed at belongs to: a
// wiki when it is inside the collection, and otherwise only a repository a wiki knows.
// A folder that names no project gets "".
func (p *projects) lookupPath(dir string) string {
	real := pyos.RealPath(dir)
	if real == p.wikisReal {
		return "wikis"
	}
	if rel, ok := strings.CutPrefix(real, p.wikisReal+"/"); ok {
		first, _, _ := strings.Cut(rel, "/")
		if p.known[first] {
			return first
		}
		return "wikis"
	}
	if st, err := os.Stat(dir); err != nil || !st.IsDir() {
		return ""
	}
	name, ok := pyos.RepoName(dir)
	if !ok {
		return ""
	}
	if w, ok := p.cover[name]; ok {
		name = w
	}
	if !p.known[name] {
		return ""
	}
	return name
}
