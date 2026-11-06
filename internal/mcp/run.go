package mcp

import (
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
	"syscall"
	"time"
)

// run is server.py's run: wiki.sh against one collection, and whether it succeeded
// with what it printed, stdout then stderr. It gets what the Python gave it: this
// server's environment with WIKIS_DIR and LLM_WIKI_CMD set, the temp folder to run in,
// stdin that ends at once unless there is a note, and the same time limit.
//
// The limit covers the run and its output both, as subprocess.run's does: a wiki.sh
// that has exited but left something holding its stdout is still running. When the
// time is up wiki.sh is killed, and what it started is left alone.
func (s *Server) run(folder, stdin string, args ...string) (bool, string) {
	cmd := exec.Command(s.WikiSh, args...)
	cmd.Env = append(append([]string{}, s.Env...), "WIKIS_DIR="+folder, "LLM_WIKI_CMD=wiki.sh")
	// Not in the collection or a project: start would take that for the repository.
	cmd.Dir = tempDir()

	// Pipes of our own, not exec's: Wait would otherwise block for as long as anything
	// holds one open, with no way to stop at the limit.
	inR, inW, err := os.Pipe()
	if err != nil {
		return false, "couldn't run wiki.sh: " + err.Error()
	}
	outR, outW, err := os.Pipe()
	if err != nil {
		closeAll(inR, inW)
		return false, "couldn't run wiki.sh: " + err.Error()
	}
	errR, errW, err := os.Pipe()
	if err != nil {
		closeAll(inR, inW, outR, outW)
		return false, "couldn't run wiki.sh: " + err.Error()
	}
	cmd.Stdin, cmd.Stdout, cmd.Stderr = inR, outW, errW
	err = cmd.Start()
	closeAll(inR, outW, errW)
	if err != nil {
		closeAll(inW, outR, errR)
		return false, "couldn't run wiki.sh: " + err.Error()
	}

	go func() {
		// A wiki.sh that doesn't read its stdin ends this with an error, which is fine.
		_, _ = io.WriteString(inW, stdin)
		_ = inW.Close()
	}()
	read := func(f *os.File) <-chan []byte {
		ch := make(chan []byte, 1)
		go func() {
			data, _ := io.ReadAll(f)
			ch <- data
		}()
		return ch
	}
	stdoutCh, stderrCh := read(outR), read(errR)
	exited := make(chan error, 1)
	go func() { exited <- cmd.Wait() }()

	limit := time.NewTimer(s.Timeout)
	defer limit.Stop()
	var stdout, stderr []byte
	var waitErr error
	for got := 0; got < 3; got++ {
		select {
		case stdout = <-stdoutCh:
		case stderr = <-stderrCh:
		case waitErr = <-exited:
		case <-limit.C:
			_ = cmd.Process.Kill()
			// Closing our ends lets the readers and the writer go, whoever holds the others.
			closeAll(inW, outR, errR)
			return false, fmt.Sprintf("wiki.sh %s took more than %d seconds.", args[0], int(s.Timeout/time.Second))
		}
	}
	closeAll(outR, errR)
	return waitErr == nil, strip(text(stdout) + text(stderr))
}

// must is server.py's must: what wiki.sh printed, or that as the tool's error.
func (s *Server) must(folder, stdin string, args ...string) (string, error) {
	// No program can be given a NUL byte in an argument. Python stops the call there,
	// and so the answer is a JSON-RPC error with its text, not the tool's own error.
	// Only a search word or a feedback note's words can hold one: names can't.
	for _, arg := range args {
		if strings.Contains(arg, "\x00") {
			return "", errors.New("embedded null byte")
		}
	}
	ok, out := s.run(folder, stdin, args...)
	if !ok {
		if out == "" {
			out = "wiki.sh " + args[0] + " failed."
		}
		return "", toolError(out)
	}
	return out, nil
}

func closeAll(files ...*os.File) {
	for _, f := range files {
		_ = f.Close()
	}
}

// tempDir is tempfile.gettempdir: the first of $TMPDIR, $TEMP, $TMP, /tmp, /var/tmp and
// /usr/tmp that is a folder this process can write in, or else the folder it is in.
func tempDir() string {
	for _, dir := range []string{os.Getenv("TMPDIR"), os.Getenv("TEMP"), os.Getenv("TMP"), "/tmp", "/var/tmp", "/usr/tmp"} {
		if dir == "" {
			continue
		}
		const writeAndEnter = 0x2 | 0x1 // W_OK | X_OK
		if st, err := os.Stat(dir); err == nil && st.IsDir() && syscall.Access(dir, writeAndEnter) == nil {
			return dir
		}
	}
	return "."
}
