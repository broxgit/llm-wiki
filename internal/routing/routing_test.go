package routing

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// collection makes a home folder with a collection in it: demo, whose index mentions
// Payments-Svc, proj, which covers web and api, and a folder that isn't a wiki.
func collection(t *testing.T) Options {
	t.Helper()
	home := t.TempDir()
	o := Options{Wikis: home + "/wikis", Home: home, WikiCmd: "wiki"}
	wiki(t, o, "demo", "Mentions Payments-Svc here.\n")
	wiki(t, o, "proj", "")
	write(t, o.Wikis+"/proj/repos.md", "# Repositories\n- web\n- api\n- crlf\r\n- last")
	write(t, o.Wikis+"/notes/readme.md", "not a wiki\n")
	return o
}

func wiki(t *testing.T, o Options, name, index string) {
	t.Helper()
	write(t, o.Wikis+"/"+name+"/AGENTS.md", "# Handbook\n")
	write(t, o.Wikis+"/"+name+"/index.md", "# Index\n"+index)
}

func write(t *testing.T, path, text string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(text), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestWhichCovered(t *testing.T) {
	o := collection(t)
	for name, want := range map[string]string{
		"demo": "~/wikis/demo\n",
		"web":  "~/wikis/proj\n",
		"api":  "~/wikis/proj\n",
		"last": "~/wikis/proj\n", // a last line with no line end
	} {
		o.Name = name
		got, covered, err := Which(o)
		if err != nil || !covered || got != want {
			t.Errorf("Which(%q) = %q, %v, %v, want %q", name, got, covered, err, want)
		}
	}
	// Outside the home folder the path is printed whole.
	o.Name, o.Home = "demo", "/somewhere/else"
	if got, _, _ := Which(o); got != o.Wikis+"/demo\n" {
		t.Errorf("outside home: %q", got)
	}
}

func TestWhichUncovered(t *testing.T) {
	o := collection(t)
	const own = "If it's a project of its own, the first session with something to file creates its wiki: wiki new "
	for name, want := range map[string]string{
		"nothing": "no wiki covers nothing\n" + own + "nothing\n",
		// grep -x: a line that ends in a carriage return isn't the name.
		"crlf": "no wiki covers crlf\n" + own + "crlf\n",
		// A word of the name in a wiki's name.
		"demo-api": "no wiki covers demo-api\nClose matches: demo\nIf demo-api belongs to one of them: wiki cover <wiki> demo-api\n" + own + "demo-api\n",
		// The name in a wiki's index, whatever the case.
		"PAYMENTS-svc": "no wiki covers PAYMENTS-svc\nClose matches: demo\nIf PAYMENTS-svc belongs to one of them: wiki cover <wiki> PAYMENTS-svc\n" + own + "PAYMENTS-svc\n",
		// A word of two letters is too short to match a wiki's name on.
		"pr-oj": "no wiki covers pr-oj\n" + own + "pr-oj\n",
		// A folder that isn't a wiki covers nothing.
		"notes": "no wiki covers notes\n" + own + "notes\n",
	} {
		o.Name = name
		got, covered, err := Which(o)
		if err != nil || covered || got != want {
			t.Errorf("Which(%q) = %q, %v, %v, want %q", name, got, covered, err, want)
		}
	}
}

// The Bash's head -n 5 counts an empty first line, so four names are printed, sorted.
func TestWhichShowsFourCloseMatches(t *testing.T) {
	o := collection(t)
	for _, w := range []string{"demo5", "demo4", "Demo3", "demo2", "demo.1"} {
		wiki(t, o, w, "")
	}
	o.Name = "dem"
	got, _, err := Which(o)
	if err != nil || !strings.Contains(got, "\nClose matches: demo demo.1 demo2 demo4\n") {
		t.Errorf("Which(dem) = %q, %v", got, err)
	}
}

func TestWhichNoCollection(t *testing.T) {
	o := Options{Wikis: t.TempDir() + "/none", Home: "/h", WikiCmd: "wiki", Name: "web"}
	got, covered, err := Which(o)
	if err != nil || covered || !strings.HasPrefix(got, "no wiki covers web\nIf it's a project") {
		t.Errorf("Which = %q, %v, %v", got, covered, err)
	}
}

// What the helper isn't sure of is an error, so that the Bash answers.
func TestWhichLeavesToBash(t *testing.T) {
	for what, change := range map[string]func(t *testing.T, o *Options){
		"a name with a backslash":  func(t *testing.T, o *Options) { o.Name = `a\b` },
		"a name with a line break": func(t *testing.T, o *Options) { o.Name = "a\nb" },
		"a name that isn't UTF-8":  func(t *testing.T, o *Options) { o.Name = "a\xffb" },
		"two wikis that list one repository": func(t *testing.T, o *Options) {
			write(t, o.Wikis+"/demo/repos.md", "- web\n")
			o.Name = "web"
		},
		"a repos.md with a NUL in it": func(t *testing.T, o *Options) {
			write(t, o.Wikis+"/demo/repos.md", "- x\x00\n")
		},
		"a close match the shell would split": func(t *testing.T, o *Options) {
			wiki(t, *o, "nothing much", "")
		},
		"a repos.md that can't be read": func(t *testing.T, o *Options) {
			unreadable(t, o.Wikis+"/proj/repos.md")
		},
		"a wiki that can't be read": func(t *testing.T, o *Options) {
			unreadable(t, o.Wikis+"/proj")
		},
		"an index that can't be read": func(t *testing.T, o *Options) {
			unreadable(t, o.Wikis+"/proj/index.md")
		},
		"a collection that can't be read": func(t *testing.T, o *Options) {
			unreadable(t, o.Wikis)
		},
	} {
		t.Run(what, func(t *testing.T) {
			o := collection(t)
			o.Name = "nothing"
			change(t, &o)
			if got, _, err := Which(o); err == nil {
				t.Errorf("Which gave %q, want an error", got)
			}
		})
	}
}

func unreadable(t *testing.T, path string) {
	t.Helper()
	if os.Getuid() == 0 {
		t.Skip("root can read anything")
	}
	if err := os.Chmod(path, 0); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.Chmod(path, 0o755) })
}

// A wiki named after the repository is found without looking at the others, as in the
// Bash, so one that can't be read doesn't get in the way.
func TestWhichByNameLooksNoFurther(t *testing.T) {
	o := collection(t)
	unreadable(t, o.Wikis+"/proj")
	o.Name = "demo"
	if got, covered, err := Which(o); err != nil || !covered || got != "~/wikis/demo\n" {
		t.Errorf("Which(demo) = %q, %v, %v", got, covered, err)
	}
}

// With no name, the repository this runs in: by its remote, or else by its folder.
func TestWhichHere(t *testing.T) {
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("no git")
	}
	o := collection(t)
	repo := o.Home + "/code/renamed-checkout"
	if err := os.MkdirAll(repo+"/sub", 0o755); err != nil {
		t.Fatal(err)
	}
	run := func(args ...string) {
		t.Helper()
		if out, err := exec.Command("git", append([]string{"-C", repo}, args...)...).CombinedOutput(); err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
	}
	run("init", "-q")
	chdir(t, repo+"/sub")
	got, covered, err := Which(o)
	if err != nil || covered || !strings.HasPrefix(got, "no wiki covers renamed-checkout\n") {
		t.Errorf("by folder: %q, %v, %v", got, covered, err)
	}
	run("remote", "add", "origin", "git@example.com:acme/web.git")
	if got, covered, err := Which(o); err != nil || !covered || got != "~/wikis/proj\n" {
		t.Errorf("by remote: %q, %v, %v", got, covered, err)
	}
	// Outside a repository the Bash has the message.
	chdir(t, t.TempDir())
	t.Setenv("GIT_CEILING_DIRECTORIES", "/")
	if got, _, err := Which(o); err == nil {
		t.Errorf("outside a repository: %q, want an error", got)
	}
}

// chdir is testing.T.Chdir, which the module's Go version doesn't have yet.
func chdir(t *testing.T, dir string) {
	t.Helper()
	was, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Chdir(dir); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.Chdir(was) })
}

// Printed by the expansions in wiki.sh's repo_name, on Apple's bash 3.2.
func TestRepoNameLikeBash(t *testing.T) {
	for url, want := range map[string]string{
		"git@github.com:a/b.git": "b",
		"https://x/y/z.git/":     "z",
		"https://x/y/z/":         "z",
		"foo":                    "foo",
		"host:foo.git":           "foo",
		"a.git.git":              "a.git",
	} {
		if got := RepoName("/d/dir", url); got != want {
			t.Errorf("RepoName(%q) = %q, Bash gives %q", url, got, want)
		}
	}
	if got := RepoName("/d/dir", ""); got != "dir" {
		t.Errorf("with no remote: %q", got)
	}
}

// Printed by wiki.sh's tilde, on Apple's bash 3.2.
func TestTildeLikeBash(t *testing.T) {
	for _, c := range []struct{ home, p, want string }{
		{"/h/me", "/h/me/wikis/demo", "~/wikis/demo"},
		{"/h/me", "/h/me", "/h/me"},
		{"/h/me", "/h/me/", "~/"},
		{"/h/me", "/h/meow/wikis", "/h/meow/wikis"},
		{"/h/me", "/x/h/me/wikis", "/x/h/me/wikis"},
		{"", "/wikis/demo", "~/wikis/demo"},
	} {
		if got := tilde(c.home, c.p); got != c.want {
			t.Errorf("tilde(%q, %q) = %q, Bash gives %q", c.home, c.p, got, c.want)
		}
	}
}

// The shell sorts "$WIKIS_DIR"/*/ with the slash each match ends in, so a name that
// continues with a dash comes before the shorter one: covers-nl/ before covers/.
func TestFoldersOrder(t *testing.T) {
	root := t.TempDir()
	for _, name := range []string{"llm-wiki", "covers", "llm", "covers-nl", "Zed", ".hidden", "covers.old", "covers_x"} {
		write(t, root+"/"+name+"/index.md", "# Index\n")
	}
	write(t, root+"/a-file", "not a folder\n")
	got, err := Folders(root)
	if err != nil {
		t.Fatal(err)
	}
	// "Zed/" is below the lower case names, "-" below "." below "/", and "_" above all.
	want := []string{"Zed", "covers-nl", "covers.old", "covers", "covers_x", "llm-wiki", "llm"}
	if strings.Join(got, " ") != strings.Join(want, " ") {
		t.Errorf("Folders = %q, want %q", got, want)
	}
}
