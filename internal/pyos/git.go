package pyos

import (
	"context"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

var dotGit = regexp.MustCompile(`\.git$`)

// RepoName is a folder's repository name: from its remote, or its top folder. It says
// false when git knows neither.
func RepoName(dir string) (string, bool) {
	if url := Git(dir, "config", "--get", "remote.origin.url"); url != "" {
		name := dotGit.ReplaceAllString(strings.TrimRight(url, "/"), "")
		name = name[strings.LastIndex(name, "/")+1:]
		return name[strings.LastIndex(name, ":")+1:], true
	}
	if top := Git(dir, "rev-parse", "--show-toplevel"); top != "" {
		return filepath.Base(top), true
	}
	return "", false
}

// Git runs one git command in a folder and gives its trimmed output, or "".
func Git(dir string, args ...string) string {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	out, _ := exec.CommandContext(ctx, "git", append([]string{"-C", dir}, args...)...).Output()
	return strings.TrimSpace(string(out))
}

// PathParts is Path(p).parts: the root, then each folder.
func PathParts(p string) []string {
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
