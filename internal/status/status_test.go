package status

import (
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func write(t *testing.T, path, text string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(text), 0o644); err != nil {
		t.Fatal(err)
	}
}

// wiki makes a wiki with a handbook of a version ("" for none), an index and a log.
func wiki(t *testing.T, root, name, version string) string {
	t.Helper()
	dir := root + "/" + name
	hb := "# AGENTS.md\n"
	if version != "" {
		hb += "\nHandbook version " + version + ".\n"
	}
	write(t, dir+"/AGENTS.md", hb)
	write(t, dir+"/index.md", "# Index\n")
	write(t, dir+"/log.md", "# Log\n")
	return dir
}

// collection makes a wiki for each thing a row can show.
func collection(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	wiki(t, root, "alpha", "28")
	wiki(t, root, "Beta", "28")
	wiki(t, root, "behind", "27")
	wiki(t, root, "ahead", "29")
	wiki(t, root, "nover", "")
	d := wiki(t, root, "locked", "28")
	write(t, d+"/.compile-lock", "held by s-1 since 2026-01-01\nmore\n")
	d = wiki(t, root, "freelock", "28")
	write(t, d+"/.compile-lock", "released\n")
	d = wiki(t, root, "due", "028")
	for _, n := range []string{"a.md", "b.md", "c.txt", "d.md", "e.tar.gz", "f.md", "g.md", "h.md", "i.md", ".hidden.md"} {
		write(t, d+"/raw/.x.md", "x\n")
		write(t, d+"/raw/2026-01-01-"+n, "x\n")
	}
	if err := os.Mkdir(d+"/raw/folder.md", 0o755); err != nil {
		t.Fatal(err)
	}
	write(t, d+"/log.md", "# Log\n\n## 2026-01-01 ingest | a\n- source: raw/2026-01-01-a.md\n- source: raw/2026-01-01-e.tar.gz\n")
	write(t, d+"/wiki/p.md", "---\nsources: [raw/2026-01-01-b.md, \"raw/2026-01-01-c.txt\"]\n---\nsources: raw/2026-01-01-zz.md\n")
	write(t, d+"/wiki/sources/2026-01-01-d.md", "old summary page\n")
	d = wiki(t, root, "lint", "28")
	log := "# Log\n\n## 2026-01-01 ingest | old\n## 2026-01-02 lint | lint\n"
	for i := 0; i < 11; i++ {
		log += "## 2026-01-03 ingest | n\n"
	}
	write(t, d+"/log.md", log)
	d = wiki(t, root, "pat", "28")
	write(t, d+"/patterns.md", "# Patterns\n\n"+
		"## Ready by count\n- kind: correction\n- status: watching\n- seen: 2026-01-01 a raw/a.md x3\n"+
		"## Ready as a review\n- kind: review\n- status: watching\n- seen: 2026-01-01 a raw/a.md\n- seen: 2026-01-02 a raw/b.md\n"+
		"## Not yet\n- kind: correction\n- status: watching\n- seen: 2026-01-01 a raw/a.md\n"+
		"## Again\n- kind: correction\n- status: accepted 2026-01-05: a convention\n- seen: 2026-01-01 a raw/a.md\n- seen: 2026-01-06 b raw/b.md\n"+
		"## Holding\n- kind: correction\n- status: accepted 2026-01-05: a convention\n- seen: 2026-01-05 a raw/a.md\n")
	d = wiki(t, root, "covers", "28")
	write(t, d+"/repos.md", "# Repositories\n- web\n- api\r\nnot a line\n- last")
	d = wiki(t, root, "covers-nl", "28")
	write(t, d+"/repos.md", "- one\n- two\n")
	wiki(t, root, "caf\xc3\xa9-wiki", "28")
	wiki(t, root, "a-wiki-with-a-name-longer-than-the-column", "28")
	write(t, root+"/notawiki/index.md", "# Index\n")
	write(t, root+"/.hidden/AGENTS.md", "x\n")
	write(t, root+"/.hidden/index.md", "x\n")
	return root
}

func TestRun(t *testing.T) {
	root := collection(t)
	r, err := Run(Options{Wikis: root, TemplateVersion: "28", WikiCmd: "wiki"})
	if err != nil {
		t.Fatal(err)
	}
	rows := map[string]string{}
	for _, line := range r.Rows[1:] {
		rows[strings.Fields(line)[0]] = line
	}
	for name, want := range map[string]string{
		"Beta":      "Beta                       v28       0        free",
		"behind":    "behind                     v27       0        free  <- behind template v28",
		"ahead":     "ahead                      v29       0        free  <- ahead of your template v28",
		"nover":     "nover                      v?        0        free  <- behind template v28",
		"locked":    "locked                     v28       0        held by s-1 since 2026-01-01",
		"freelock":  "freelock                   v28       0        free",
		"due":       "due                        v028      5        free  <- compile due",
		"lint":      "lint                       v28       0        free  <- lint due (11 ingests)",
		"pat":       "pat                        v28       0        free  <- 2 pattern(s) ready  <- 1 accepted fix(es) not working",
		"covers":    "covers                     v28       0        free  covers: web api\r last",
		"covers-nl": "covers-nl                  v28       0        free  covers: one two ",
		// Padded by byte: the é is two.
		"caf\xc3\xa9-wiki":                          "caf\xc3\xa9-wiki                 v28       0        free",
		"a-wiki-with-a-name-longer-than-the-column": "a-wiki-with-a-name-longer-than-the-column v28       0        free",
	} {
		if rows[name] != want {
			t.Errorf("row %s:\n got %q\nwant %q", name, rows[name], want)
		}
	}
	// By byte, capitals first, and as the shell's glob of "*/" sorts: with the slash,
	// so covers-nl/ comes before covers/.
	var order []string
	for _, line := range r.Rows[1:] {
		order = append(order, strings.Fields(line)[0])
	}
	if want := "Beta a-wiki-with-a-name-longer-than-the-column ahead alpha behind caf\xc3\xa9-wiki covers-nl covers due freelock lint locked nover pat"; strings.Join(order, " ") != want {
		t.Errorf("order: %q", order)
	}
	if _, ok := rows["notawiki"]; ok {
		t.Error("a folder with no handbook got a row")
	}
	want := []string{
		"ahead: upgraded by a newer llm-wiki than this one. Run: wiki update",
		`due: 5 notes waiting. Ask an agent: "compile due" (in Claude Code: /llm-wiki:compile due)`,
		`lint: lint due, 11 ingests since the last. Ask an agent: "lint lint"`,
		`pat: 2 repeated pattern(s) ready for a fix. Ask an agent: "propose the ready patterns in pat"`,
		`pat: 1 accepted fix(es) seen again, so not working. Ask an agent: "look again at the patterns marked AGAIN in pat"`,
		"2 wikis' handbooks behind template v28 (behind nover). Run: wiki upgrade --all",
	}
	if !reflect.DeepEqual(r.Todos, want) {
		t.Errorf("todos:\n%q\nwant\n%q", r.Todos, want)
	}
	if r.Ahead {
		t.Error("ahead outside the plugin")
	}
}

func TestRunPlugin(t *testing.T) {
	root := t.TempDir()
	wiki(t, root, "ahead", "29")
	wiki(t, root, "behind", "27")
	r, err := Run(Options{Wikis: root, TemplateVersion: "28", WikiCmd: "wiki", Plugin: true})
	if err != nil {
		t.Fatal(err)
	}
	if !r.Ahead || !strings.HasSuffix(r.Rows[1], "<- ahead of this plugin's template v28") {
		t.Errorf("plugin: %v %q", r.Ahead, r.Rows)
	}
	if want := []string{"behind: handbook behind template v28. Run: wiki upgrade behind"}; !reflect.DeepEqual(r.Todos, want) {
		t.Errorf("todos: %q", r.Todos)
	}
	// With no template version, nothing is behind or ahead.
	r, err = Run(Options{Wikis: root, WikiCmd: "wiki", Plugin: true})
	if err != nil || r.Ahead || len(r.Todos) != 0 {
		t.Errorf("no template version: %v %v %q", err, r.Ahead, r.Todos)
	}
}

func TestRunNone(t *testing.T) {
	root := t.TempDir()
	r, err := Run(Options{Wikis: root, TemplateVersion: "28", WikiCmd: "wk"})
	if err != nil || !reflect.DeepEqual(r.Rows[1:], []string{"(none yet. Run: wk init)"}) {
		t.Errorf("none: %q, %v", r.Rows, err)
	}
}

func TestAlso(t *testing.T) {
	root := collection(t)
	other := t.TempDir()
	d := wiki(t, other, "w", "28")
	write(t, d+"/raw/a.md", "x\n")
	write(t, d+"/raw/b.md", "x\n")
	// No log.md is fine here: only the table stops at it.
	d = wiki(t, other, "nolog", "28")
	os.Remove(d + "/log.md")
	write(t, d+"/raw/c.md", "x\n")
	r, err := Run(Options{Wikis: root, TemplateVersion: "28", WikiCmd: "wiki", Also: []string{other, root, t.TempDir() + "/gone"}})
	if err != nil {
		t.Fatal(err)
	}
	if want := []int{3, 5, 0}; !reflect.DeepEqual(r.Also, want) {
		t.Errorf("also: %v, want %v", r.Also, want)
	}
}

func TestStem(t *testing.T) {
	for in, want := range map[string]string{
		"a.md": "a", "a.tar.gz": "a.tar", "a": "a", "a.b-c": "a.b-c", "a.": "a", "a.m\xc3\xa9": "a.m\xc3\xa9", "a.md\r": "a.md\r",
	} {
		if got := stem(in); got != want {
			t.Errorf("stem(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestRawNames(t *testing.T) {
	got := rawNames("sources: [raw/a.md, \"raw/b.md\"] raw/c\xe9.md\traw/raw/d raw/e]f raw/")
	want := []string{"a.md", "b.md", "c\xe9.md", "raw/d", "e", ""}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("rawNames = %q, want %q", got, want)
	}
}

// What awk does that a reading of patterns.md wouldn't: a heading with no name gives
// its sightings to the next entry, a status line is read again as a sighting once
// "- status:" is cut from it, and a sighting with no repository counts "" as one.
func TestPatternsQuirks(t *testing.T) {
	dir := t.TempDir()
	for text, want := range map[string][2]int{
		"## \n- seen: 1 a\n- seen: 2 a\n## X\n- status: watching\n- seen: 3 a\n":               {1, 0},
		"## X\n- status: - seen: 2026 a\n- seen: 2026 a\n":                                     {0, 0},
		"## X\n- kind: review\n- status: watching x\n- seen: a\n- seen: b\n":                   {1, 0},
		"## X\n- status: watching\n- seen: d\n- seen: d b\n":                                   {1, 0},
		"## X\n- status: watching\n- seen: d a\n- seen: d -\n":                                 {0, 0},
		"## X\n- status: watching\n- seen: d - raw/a.md x1\n- seen: d - x\n":                   {0, 0},
		"## X\n- status:   accepted 2026-01-01\n- seen: 2026-01-01x a\n":                       {0, 1},
		"## X\n- status: accepted 2026-01-01:\n- seen: 2026-01-01 a\n":                         {0, 0},
		"## X\n- kind: review\r\n- status: watching\r\n- seen: d a\r\n- seen: d a\r\n":         {0, 0},
		"## X\n- status: watching\n- seen: d a x2\n## Y\n- status: watching\n- seen: d a x3\n": {1, 0},
	} {
		write(t, dir+"/patterns.md", text)
		ready, regressed, err := patterns(dir + "/patterns.md")
		if err != nil || [2]int{ready, regressed} != want {
			t.Errorf("patterns(%q) = %d, %d, %v, want %v", text, ready, regressed, err, want)
		}
	}
}

// Each thing the Bash might read differently is an error, so the Bash answers.
func TestUnsure(t *testing.T) {
	for name, make := range map[string]func(root string){
		"NUL in patterns.md": func(root string) { write(t, root+"/w/patterns.md", "## X\x00\n") },
		"NUL in a page":      func(root string) { write(t, root+"/w/wiki/a.md", "a\x00\n") },
		"NUL in the lock":    func(root string) { write(t, root+"/w/.compile-lock", "held\x00\n") },
		"a link under wiki/": func(root string) { os.Symlink(root+"/w/index.md", root+"/w/wiki/l.md") },
		"wiki/ is a link":    func(root string) { os.RemoveAll(root + "/w/wiki"); os.Symlink(root, root+"/w/wiki") },
		"no log.md":          func(root string) { os.Remove(root + "/w/log.md") },
		"a name with a line break": func(root string) {
			wiki(t, root, "two\nlines", "28")
		},
		"a raw note with a line break": func(root string) { write(t, root+"/w/raw/a\nb.md", "x\n") },
		"a behind name with a space": func(root string) {
			wiki(t, root, "old one", "27")
		},
		"a version too long": func(root string) {
			write(t, root+"/w/AGENTS.md", "Handbook version 1234567890123456789.\n")
		},
		"dates awk may read as numbers": func(root string) {
			write(t, root+"/w/patterns.md", "## X\n- status: accepted 20260105\n- seen: 20260106 a\n")
		},
		"a count too long": func(root string) {
			write(t, root+"/w/patterns.md", "## X\n- status: watching\n- seen: d a x12345678901\n")
		},
		"a source named like the awk's marker": func(root string) {
			write(t, root+"/w/log.md", "- source: raw///raw//\n")
		},
	} {
		root := t.TempDir()
		write(t, wiki(t, root, "w", "28")+"/wiki/p.md", "page\n")
		make(root)
		if _, err := Run(Options{Wikis: root, TemplateVersion: "28", WikiCmd: "wiki"}); err == nil {
			t.Errorf("%s: no error", name)
		}
	}
	if _, err := Run(Options{Wikis: t.TempDir(), TemplateVersion: "2x", WikiCmd: "wiki"}); err == nil {
		t.Error("a template version that isn't a number: no error")
	}
}

func TestUnreadable(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("root reads everything")
	}
	for _, sub := range []string{"raw", "wiki/sources", "wiki"} {
		root := t.TempDir()
		d := wiki(t, root, "w", "28")
		write(t, d+"/"+sub+"/a.md", "x\n")
		os.Chmod(d+"/"+sub, 0)
		_, err := Run(Options{Wikis: root, TemplateVersion: "28", WikiCmd: "wiki"})
		os.Chmod(d+"/"+sub, 0o755)
		if err == nil {
			t.Errorf("an unreadable %s: no error", sub)
		}
	}
}

// The table is what wiki.sh's own table prints for the same collection, when bash is
// here to run it.
func TestSameAsTheBash(t *testing.T) {
	bash, err := exec.LookPath("bash")
	if err != nil {
		t.Skip("no bash")
	}
	script, err := filepath.Abs("../../wiki.sh")
	if err != nil {
		t.Fatal(err)
	}
	root := collection(t)
	home := t.TempDir()
	tv := "28"
	for _, plugin := range []bool{false} {
		cmd := exec.Command(bash, script, "status")
		cmd.Env = []string{"HOME=" + home, "PATH=/usr/bin:/bin", "WIKIS_DIR=" + root, "LLM_WIKI_NO_GO=1", "LLM_WIKI_CMD=wiki", "XDG_CONFIG_HOME=" + home + "/c", "XDG_STATE_HOME=" + home + "/s"}
		out, err := cmd.Output()
		if err != nil {
			t.Fatalf("wiki.sh status: %v", err)
		}
		// Against this checkout's template version, whatever it is.
		tvOut, _ := exec.Command("sed", "-n", `s/^Handbook version \([0-9][0-9]*\).*/\1/p`, "../../template/AGENTS.md").Output()
		tv = strings.TrimSpace(string(tvOut))
		r, err := Run(Options{Wikis: root, TemplateVersion: tv, WikiCmd: "wiki", Plugin: plugin})
		if err != nil {
			t.Fatal(err)
		}
		text := string(out)
		table := strings.Join(r.Rows, "\n") + "\n"
		if !strings.HasPrefix(text, table) {
			t.Errorf("the table:\n%s\nthe Bash's:\n%s", table, text)
		}
		var todo string
		for _, line := range r.Todos {
			todo += "    - " + line + "\n"
		}
		// wiki.sh prints them as the kit's TO DO stage, a line with their count, then an item each.
		_, rest, ok := strings.Cut(text, "\nTO DO  ")
		if ok {
			_, rest, ok = strings.Cut(rest, "\n")
		}
		if !ok || !strings.HasPrefix(rest, todo) {
			t.Errorf("the to-do lines:\n%s\nthe Bash's:\n%s", todo, rest)
		}
	}
}
