package tokens

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"
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

var dotGit = regexp.MustCompile(`\.git$`)

func newProjects(wikis string) (*projects, error) {
	p := &projects{wikis: wikis, wikisReal: realPath(wikis), cover: map[string]string{}, known: map[string]bool{}, names: map[string]string{}}
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

// resolve looks up every folder not seen yet, several at a time.
func (p *projects) resolve(cwds []string) {
	var todo []string
	for _, c := range cwds {
		if _, ok := p.names[c]; !ok && c != "" {
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
			out[i] = p.lookup(c)
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
		if url := git(cwd, "config", "--get", "remote.origin.url"); url != "" {
			name = dotGit.ReplaceAllString(strings.TrimRight(url, "/"), "")
			name = name[strings.LastIndex(name, "/")+1:]
			name = name[strings.LastIndex(name, ":")+1:]
		} else if top := git(cwd, "rev-parse", "--show-toplevel"); top != "" {
			name = filepath.Base(top)
		}
	}
	if realPath(cwd) == p.wikisReal {
		name = "wikis"
	}
	if w, ok := p.cover[name]; ok {
		name = w
	}
	// A scratch folder inside a project, such as myapp/sweeps/b41, belongs to it.
	if !p.known[name] && name != "wikis" {
		parts := pathParts(cwd)
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

// pathParts is Path(p).parts: the root, then each folder.
func pathParts(p string) []string {
	var parts []string
	if strings.HasPrefix(p, "/") {
		parts = append(parts, "/")
	}
	for _, s := range strings.Split(p, "/") {
		if s != "" && s != "." {
			parts = append(parts, s)
		}
	}
	return parts
}

// git runs one git command in a folder and gives its trimmed output, or "".
func git(dir string, args ...string) string {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	out, _ := exec.CommandContext(ctx, "git", append([]string{"-C", dir}, args...)...).Output()
	return strings.TrimSpace(string(out))
}
