package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// gitSafe adds safe.bareRepository=explicit after whatever the environment carries, once.
func TestGitSafe(t *testing.T) {
	tests := []struct {
		name string
		env  map[string]string
		want map[string]string
	}{
		{
			name: "nothing set",
			env:  map[string]string{},
			want: map[string]string{"GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "safe.bareRepository", "GIT_CONFIG_VALUE_0": "explicit"},
		},
		{
			name: "another setting stays, and ours follows it",
			env:  map[string]string{"GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "user.name", "GIT_CONFIG_VALUE_0": "someone"},
			want: map[string]string{"GIT_CONFIG_COUNT": "2", "GIT_CONFIG_KEY_0": "user.name", "GIT_CONFIG_VALUE_0": "someone", "GIT_CONFIG_KEY_1": "safe.bareRepository", "GIT_CONFIG_VALUE_1": "explicit"},
		},
		{
			name: "already there, so not added again",
			env:  map[string]string{"GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "safe.barerepository", "GIT_CONFIG_VALUE_0": "explicit"},
			want: map[string]string{"GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_1": ""},
		},
		{
			name: "one that lets any folder pass is overridden",
			env:  map[string]string{"GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "safe.bareRepository", "GIT_CONFIG_VALUE_0": "all"},
			want: map[string]string{"GIT_CONFIG_COUNT": "2", "GIT_CONFIG_KEY_1": "safe.bareRepository", "GIT_CONFIG_VALUE_1": "explicit"},
		},
		{
			name: "ours, then one that undoes it",
			env: map[string]string{"GIT_CONFIG_COUNT": "2", "GIT_CONFIG_KEY_0": "safe.bareRepository", "GIT_CONFIG_VALUE_0": "explicit",
				"GIT_CONFIG_KEY_1": "safe.bareRepository", "GIT_CONFIG_VALUE_1": "all"},
			want: map[string]string{"GIT_CONFIG_COUNT": "3", "GIT_CONFIG_KEY_2": "safe.bareRepository", "GIT_CONFIG_VALUE_2": "explicit"},
		},
		{
			name: "ours, then an include that could undo it",
			env: map[string]string{"GIT_CONFIG_COUNT": "2", "GIT_CONFIG_KEY_0": "safe.bareRepository", "GIT_CONFIG_VALUE_0": "explicit",
				"GIT_CONFIG_KEY_1": "include.path", "GIT_CONFIG_VALUE_1": "/somewhere/else"},
			want: map[string]string{"GIT_CONFIG_COUNT": "3", "GIT_CONFIG_KEY_2": "safe.bareRepository", "GIT_CONFIG_VALUE_2": "explicit"},
		},
		{
			name: "a count that isn't a number starts again",
			env:  map[string]string{"GIT_CONFIG_COUNT": "many"},
			want: map[string]string{"GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "safe.bareRepository", "GIT_CONFIG_VALUE_0": "explicit"},
		},
	}
	keys := []string{"GIT_CONFIG_COUNT", "GIT_CONFIG_KEY_0", "GIT_CONFIG_VALUE_0", "GIT_CONFIG_KEY_1", "GIT_CONFIG_VALUE_1", "GIT_CONFIG_KEY_2", "GIT_CONFIG_VALUE_2"}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			for _, k := range keys {
				t.Setenv(k, tt.env[k])
			}
			gitSafe()
			for k, want := range tt.want {
				if got := os.Getenv(k); got != want {
					t.Errorf("%s = %q, want %q", k, got, want)
				}
			}
		})
	}
}

// gitClean leaves git no variable that names another repository, and keeps the rest.
func TestGitClean(t *testing.T) {
	for _, k := range gitRepoVars {
		t.Setenv(k, "/somewhere/else")
	}
	t.Setenv("GIT_CONFIG_COUNT", "1")
	t.Setenv("GIT_CONFIG_KEY_0", "safe.bareRepository")
	t.Setenv("GIT_CONFIG_VALUE_0", "explicit")
	t.Setenv("GIT_CEILING_DIRECTORIES", "/ceiling")
	t.Setenv("GIT_SSH_COMMAND", "ssh -o BatchMode=yes")
	t.Setenv("GIT_AUTHOR_NAME", "someone")
	gitClean()
	for _, k := range gitRepoVars {
		if v, set := os.LookupEnv(k); set {
			t.Errorf("%s is still %q", k, v)
		}
	}
	for k, want := range map[string]string{"GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "safe.bareRepository", "GIT_CONFIG_VALUE_0": "explicit",
		"GIT_CEILING_DIRECTORIES": "/ceiling", "GIT_SSH_COMMAND": "ssh -o BatchMode=yes", "GIT_AUTHOR_NAME": "someone"} {
		if got := os.Getenv(k); got != want {
			t.Errorf("%s = %q, want %q", k, got, want)
		}
	}
}

// The list is git's own: every variable `git rev-parse --local-env-vars` names is on it,
// but for the ones kept on purpose.
func TestGitRepoVarsCoverGit(t *testing.T) {
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("no git here")
	}
	out, err := exec.Command("git", "rev-parse", "--local-env-vars").Output()
	if err != nil {
		t.Skipf("git rev-parse --local-env-vars: %v", err)
	}
	kept := map[string]bool{"GIT_CONFIG_COUNT": true, "GIT_NO_REPLACE_OBJECTS": true}
	have := map[string]bool{}
	for _, k := range gitRepoVars {
		have[k] = true
	}
	for _, k := range strings.Fields(string(out)) {
		if !have[k] && !kept[k] {
			t.Errorf("git names %s, which is neither cleared nor kept on purpose", k)
		}
	}
}

// With GIT_DIR and GIT_WORK_TREE naming another repository, git asked about a folder after
// gitClean answers for the folder.
func TestGitCleanFindsTheFolder(t *testing.T) {
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("no git here")
	}
	dir := t.TempDir()
	mine, other := filepath.Join(dir, "mine"), filepath.Join(dir, "other")
	for _, d := range []string{mine, other} {
		if out, err := exec.Command("git", "init", "-q", d).CombinedOutput(); err != nil {
			t.Fatalf("git init %s: %v: %s", d, err, out)
		}
	}
	t.Setenv("GIT_DIR", filepath.Join(other, ".git"))
	t.Setenv("GIT_WORK_TREE", other)
	gitClean()
	out, err := exec.Command("git", "-C", mine, "rev-parse", "--show-toplevel").Output()
	if err != nil {
		t.Fatalf("git rev-parse: %v", err)
	}
	got, _ := filepath.EvalSymlinks(strings.TrimSpace(string(out)))
	want, _ := filepath.EvalSymlinks(mine)
	if got != want {
		t.Errorf("top = %q, want %q", got, want)
	}
}
