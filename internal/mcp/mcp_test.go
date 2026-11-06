package mcp

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
	"unicode/utf8"
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

func read(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil && !os.IsNotExist(err) {
		t.Fatal(err)
	}
	return string(data)
}

// fixture is a server over two collections, and a stand-in for wiki.sh that notes how
// it was run in calls.log and then does what $FAKE says.
func fixture(t *testing.T) (*Server, string) {
	t.Helper()
	root, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	home, work := root+"/home/wikis", root+"/home/wikis-work"
	write(t, home+"/demo/AGENTS.md", "# Handbook\n")
	write(t, home+"/demo/index.md", "# Index\n\n- [Deploy flow](wiki/deploy.md): canary first\n")
	write(t, home+"/demo/repos.md", "# Repositories\n\n- api\n- web\n")
	write(t, home+"/demo/wiki/deploy.md", "---\ntitle: Deploy\n---\nThe canary goes first.\n")
	write(t, home+"/demo/wiki/crlf.md", "one\r\ntwo\rthree\n")
	write(t, home+"/demo/wiki/latin.md", "caf\xe9 and a cut arrow \xe2\x86 here\n")
	write(t, home+"/demo/wiki/.hid/h.md", "hidden\n")
	write(t, home+"/demo/wiki/sub/deep.md", "deep\n")
	write(t, home+"/demo/wiki/notes.txt", "not a page\n")
	write(t, home+"/demo/data/x.sqlite", "bin")
	write(t, home+"/global/AGENTS.md", "# Handbook\n")
	write(t, home+"/global/index.md", "# Index\n")
	write(t, home+"/.hidden/AGENTS.md", "x")
	write(t, home+"/.hidden/index.md", "x")
	write(t, home+"/notes/index.md", "- an index and no handbook\n")
	write(t, work+"/jobapp/AGENTS.md", "# Handbook\n")
	write(t, work+"/jobapp/index.md", "# Index\n")
	write(t, work+"/jobapp/repos.md", "- jobs\n")
	write(t, work+"/jobapp/wiki/canary.md", "The work canary.\n")
	fake := root + "/wiki.sh"
	write(t, fake, `#!/bin/sh
{ printf 'args:'; for a in "$@"; do printf ' [%s]' "$a"; done; printf '\n'
  printf 'dir: %s\nwikis: %s\ncmd: %s\nextra: %s\nstdin: %s\n' "$(pwd -P)" "$WIKIS_DIR" "$LLM_WIKI_CMD" "$EXTRA" "$(cat)"; } >> "`+root+`/calls.log"
case "$FAKE" in
  fail) echo "error: it went wrong" >&2; exit 1 ;;
  quiet-fail) exit 3 ;;
  slow) sleep 5 ;;
  linger) sleep 5 & echo "gone" ;;
  bytes) printf 'caf\351 \342\206\r\nnext\r' ; printf ' err\n' >&2 ;;
  no-remote) case "$1" in sync) echo "committed: m"; echo "no remote, so nothing to pull or push" ;; *) echo "ran $1" ;; esac ;;
  unowned) case "$1" in sync) echo "~/wikis/demo isn't in a repo the wikis own, so there's nothing to sync. Commits are up to you there." ;; *) echo "ran $1" ;; esac ;;
  first-push) case "$1" in sync) echo "committed: m"; echo "synced: pushed ~/wikis to origin for the first time" ;; *) echo "ran $1" ;; esac ;;
  noisy-push) case "$1" in sync) echo "synced: pulled and pushed ~/wikis"; echo "remote: a hook said this" >&2 ;; *) echo "ran $1" ;; esac ;;
  *) case "$1" in which) [ "$2" = jobs ] && [ "${WIKIS_DIR##*/}" = wikis-work ] ;; sync) echo "committed: m"; echo "synced: pulled and pushed ~/wikis" ;; *) echo "ran $1" ;; esac ;;
esac
`)
	if err := os.Chmod(fake, 0o755); err != nil {
		t.Fatal(err)
	}
	return &Server{
		WikiSh:      fake,
		Collections: []Collection{{"default", home}, {"work", work}},
		Home:        root + "/home",
		Tips:        root + "/config/llm-wiki/tips",
		Env:         append(os.Environ(), "EXTRA=kept", "WIKIS_DIR=/overridden", "FAKE="),
		Timeout:     20 * time.Second,
		Log:         &bytes.Buffer{},
	}, root
}

// links adds links under demo's wiki/: one out of the wiki, one to a page, one to a
// folder and one to nowhere. A search leaves a wiki with links to wiki.sh.
func links(t *testing.T, root string) {
	t.Helper()
	wiki := root + "/home/wikis/demo/wiki"
	write(t, root+"/secret.md", "very secret\n")
	for name, to := range map[string]string{"link.md": root + "/secret.md", "inner.md": "deploy.md", "more.md": wiki + "/sub", "broken.md": "nowhere"} {
		if err := os.Symlink(to, wiki+"/"+name); err != nil {
			t.Fatal(err)
		}
	}
}

// fake sets what the stand-in for wiki.sh does next.
func fake(s *Server, how string) { s.Env = append(s.Env, "FAKE="+how) }

type reply struct {
	ID     any `json:"id"`
	Result *struct {
		Content []struct{ Type, Text string }
		IsError bool
		Tools   []struct {
			Name        string
			InputSchema struct {
				Type       string
				Properties map[string]any
				Required   []string
			}
		}
		ProtocolVersion any
		Instructions    string
	} `json:"result"`
	Error *struct {
		Code    int
		Message string
	} `json:"error"`
}

// serve sends lines to the server as a client does, and checks what any client needs
// of what comes back: every reply is one line of valid UTF-8 and valid JSON.
func serve(t *testing.T, s *Server, lines ...string) []reply {
	t.Helper()
	var out bytes.Buffer
	if err := s.Serve(strings.NewReader(strings.Join(lines, "\n")+"\n"), &out); err != nil {
		t.Fatalf("Serve: %v", err)
	}
	if out.Len() > 0 && !bytes.HasSuffix(out.Bytes(), []byte("\n")) {
		t.Fatalf("the output doesn't end with a line feed: %q", out.String())
	}
	var replies []reply
	for _, line := range strings.Split(strings.TrimSuffix(out.String(), "\n"), "\n") {
		if out.Len() == 0 {
			break
		}
		if !utf8.ValidString(line) || strings.ContainsAny(line, "\r\u2028\u2029") {
			t.Fatalf("a reply that isn't one line of UTF-8: %q", line)
		}
		var r reply
		if err := json.Unmarshal([]byte(line), &r); err != nil {
			t.Fatalf("a reply that isn't JSON: %v: %q", err, line)
		}
		if (r.Result == nil) == (r.Error == nil) {
			t.Fatalf("a reply needs a result or an error, and not both: %q", line)
		}
		replies = append(replies, r)
	}
	return replies
}

func request(id int, tool string, arguments any) string {
	a, _ := json.Marshal(arguments)
	return fmt.Sprintf(`{"jsonrpc":"2.0","id":%d,"method":"tools/call","params":{"name":%q,"arguments":%s}}`, id, tool, a)
}

// call is one tool call: its text, and whether the tool called it an error.
func call(t *testing.T, s *Server, tool string, arguments any) (string, bool) {
	t.Helper()
	r := serve(t, s, request(1, tool, arguments))
	if len(r) != 1 || r[0].Result == nil || len(r[0].Result.Content) != 1 || r[0].Result.Content[0].Type != "text" {
		t.Fatalf("%s(%v) gave no text: %+v", tool, arguments, r)
	}
	return r[0].Result.Content[0].Text, r[0].Result.IsError
}

type m = map[string]any

func TestProtocol(t *testing.T) {
	s, _ := fixture(t)
	r := serve(t, s,
		`{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{}}}`,
		`{"jsonrpc":"2.0","method":"notifications/initialized"}`,
		`not json`,
		``,
		`{"jsonrpc":"2.0","id":"two","method":"ping"}`,
		`{"jsonrpc":"2.0","id":3,"method":"nope"}`,
		`{"jsonrpc":"2.0","id":4,"method":"tools/list"}`,
		`{"jsonrpc":"2.0","id":5,"method":"initialize"}`,
		`{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"nope"}}`,
		`[1,2]`,
		`{"jsonrpc":"2.0","id":null,"method":"ping"}`,
	)
	if len(r) != 8 {
		t.Fatalf("%d replies, want 8: %+v", len(r), r)
	}
	if r[0].ID != 1.0 || r[0].Result.ProtocolVersion != "2025-03-26" || !strings.Contains(r[0].Result.Instructions, "wiki_start") {
		t.Errorf("initialize: %+v", r[0])
	}
	if r[1].ID != nil || r[1].Error == nil || r[1].Error.Code != parseError {
		t.Errorf("a line that isn't JSON: %+v", r[1])
	}
	if r[2].ID != "two" || r[2].Result == nil {
		t.Errorf("ping, with a string for an id: %+v", r[2])
	}
	if r[3].ID != 3.0 || r[3].Error == nil || r[3].Error.Code != methodNotFound {
		t.Errorf("an unknown method: %+v", r[3])
	}
	var names []string
	for _, tool := range r[4].Result.Tools {
		names = append(names, tool.Name)
		if tool.InputSchema.Type != "object" || tool.InputSchema.Properties == nil || tool.InputSchema.Required == nil {
			t.Errorf("%s: a schema needs a type, properties and a list of what is required: %+v", tool.Name, tool.InputSchema)
		}
	}
	if got := strings.Join(names, " "); got != "wiki_list wiki_start wiki_search wiki_read wiki_status wiki_capture wiki_feedback" {
		t.Errorf("tools: %s", got)
	}
	if r[5].Result.ProtocolVersion != defaultProtocol {
		t.Errorf("initialize with no version: %+v", r[5].Result.ProtocolVersion)
	}
	if r[6].ID != 6.0 || r[6].Error == nil || r[6].Error.Code != methodNotFound {
		t.Errorf("an unknown tool: %+v", r[6])
	}
	if r[7].ID != nil || r[7].Result == nil {
		t.Errorf("ping with a null id is still a request: %+v", r[7])
	}
}

// Whatever a line holds, the server answers it or passes over it, and answers the next.
func TestNeverDies(t *testing.T) {
	s, _ := fixture(t)
	fake(s, "fail")
	lines := []string{
		"\xff\xfe not UTF-8",
		`{"jsonrpc":"2.0","id":1,"method":"ping","x":"` + "\xe2\x86" + `"}`,
		`{"jsonrpc":"2.0","id":NaN,"method":"ping"}`,
		`{"jsonrpc":"2.0","id":1,"method":"ping"} {"again":1}`,
		strings.Repeat("[", 20000) + strings.Repeat("]", 20000),
		`{"id":1,"method":"tools/call","params":"x"}`,
		`{"id":1,"method":"tools/call","params":{"name":"wiki_read","arguments":"x"}}`,
		`{"id":1,"method":"tools/call","params":{"name":"wiki_read","arguments":{"wiki":5}}}`,
		`{"id":1,"method":"tools/call","params":{"name":"wiki_read","arguments":{"wiki":"demo","path":["a"]}}}`,
		`{"id":1,"method":"tools/call","params":{"name":"wiki_read","arguments":{"wiki":"demo","path":"a\u0000b.md"}}}`,
		`{"id":1,"method":"tools/call","params":{"name":"wiki_search","arguments":{"word":"\ud800"}}}`,
		`{"id":1,"method":"tools/call","params":{"name":"wiki_search","arguments":{"word":"nul\u0000byte"}}}`,
		`{"id":1,"method":"tools/call","params":{"name":"wiki_search","arguments":{"word":"back\\slash"}}}`,
		`{"id":1,"method":"tools/call","params":{"name":"wiki_start","arguments":{"repository":{"a":1}}}}`,
		`{"id":1,"method":"tools/call","params":{"name":"wiki_start"}}`,
		`{"id":1,"method":"tools/call","params":{"name":"wiki_status","arguments":{"collection":"nope"}}}`,
		`{"id":1,"method":"tools/call","params":{"name":"wiki_capture","arguments":{"wiki":"demo","slug":"s","note":7}}}`,
		`{"id":1,"method":"tools/call","params":{"name":"wiki_feedback","arguments":{"kind":true}}}`,
		`{"id":1,"method":"tools/call","params":{"name":"wiki_feedback","arguments":{"kind":"a\u0000"}}}`,
		`{"id":1,"method":"initialize","params":7}`,
		`{"id":{"deep":[1,2,{"x":"\u2028"}]},"method":"ping"}`,
		`{"id":1,"method":"tools/call","params":{"name":"wiki_search","arguments":{"word":"` + strings.Repeat("long ", 400000) + `"}}}`,
		`{"jsonrpc":"2.0","id":"last","method":"ping"}`,
	}
	r := serve(t, s, lines...)
	if len(r) != len(lines) {
		t.Fatalf("%d replies to %d lines: every one of these is a request or a parse error", len(r), len(lines))
	}
	if last := r[len(r)-1]; last.ID != "last" || last.Result == nil {
		t.Errorf("the last request wasn't answered: %+v", last)
	}
	for i, want := range map[int]int{0: parseError, 1: parseError, 2: parseError, 3: parseError, 5: internalError, 6: internalError, 7: internalError, 8: internalError, 11: internalError, 13: internalError, 16: internalError, 17: internalError, 18: internalError, 19: internalError} {
		if r[i].Error == nil || r[i].Error.Code != want {
			t.Errorf("line %d: got %+v, want error %d", i, r[i], want)
		}
	}
	// A deep list is JSON, and not an object, so it is passed over or refused, never fatal.
	if r[4].Error == nil || r[4].Error.Code != parseError {
		t.Errorf("JSON nested too deep to read: %+v", r[4])
	}
}

// A tool that panics is an error reply, the trace goes to the log, and nothing but
// replies reaches the output.
func TestPanicIsAReply(t *testing.T) {
	s, _ := fixture(t)
	tools = append(tools, tool{name: "boom", run: func(*Server, args) (string, error) { panic("boom") }})
	defer func() { tools = tools[:len(tools)-1] }()
	r := serve(t, s, request(1, "boom", m{}), `{"id":2,"method":"ping"}`)
	if len(r) != 2 || r[0].Error == nil || r[0].Error.Code != internalError || r[1].Result == nil {
		t.Fatalf("a panic: %+v", r)
	}
	if log := s.Log.(*bytes.Buffer).String(); !strings.Contains(log, "boom") {
		t.Errorf("the log has no trace: %q", log)
	}
}

func TestDecode(t *testing.T) {
	// What Python 3.14 gives for bytes.decode("utf-8", "replace").
	for _, c := range [][2]string{
		{"\xe2\x86\x61", "\ufffda"},
		{"\xff\xff", "\ufffd\ufffd"},
		{"\xf0\x9f\x98", "\ufffd"},
		{"\xe0\x80\x61", "\ufffd\ufffda"},
		{"\xed\xa0\x80", "\ufffd\ufffd\ufffd"},
		{"\x63\x61\x66\xe9", "caf\ufffd"},
		{"\xc0\xaf", "\ufffd\ufffd"},
		{"\xf4\x90\x80\x80", "\ufffd\ufffd\ufffd\ufffd"},
		{"\x61\xe2\x86", "a\ufffd"},
		{"\xf0\x9f\x98\xe2\x86\x92", "\ufffd\u2192"},
		{"\xf0\x9f\x41", "\ufffdA"},
		{"\xe0\x80", "\ufffd\ufffd"},
		{"\xc3", "\ufffd"},
		{"\xc3\xa9", "\u00e9"},
		{"\xf0\x9f\x98\x80", "\U0001f600"},
		{"\xf8\x88\x80\x80\x80", "\ufffd\ufffd\ufffd\ufffd\ufffd"},
		{"\x80", "\ufffd"},
		{"\xed\x9f\xbf", "\ud7ff"},
		{"\xf4\x8f\xbf\xbf", "\U0010ffff"},
		{"\xe1\x80\xe1\x80\x80", "\ufffd\u1000"},
		{"\xf1\x80\x80\xc3\xa9", "\ufffd\u00e9"},
		{"\x6f\x6b", "ok"},
		{"\xc3\x86\x80", "\u00c6\ufffd"},
		{"\x80\x90\xe2\x80\xbf", "\ufffd\ufffd\u203f"},
		{"\x92\xbf\xed\xbf", "\ufffd\ufffd\ufffd\ufffd"},
		{"\x92\x80\xc2\xed\x80", "\ufffd\ufffd\ufffd\ufffd"},
		{"\x86\x80\xed\x80\x8f", "\ufffd\ufffd\ud00f"},
		{"\xc3\xf4\x92\xc3\x8f\xc2\xf4", "\ufffd\ufffd\ufffd\u00cf\ufffd\ufffd"},
		{"\xe0\xc2\xe2\xff\xc2", "\ufffd\ufffd\ufffd\ufffd\ufffd"},
		{"\xbf\x80\xe2\x9f\x8f", "\ufffd\ufffd\u27cf"},
		{"\xf5\xa0\xa0\xff", "\ufffd\ufffd\ufffd\ufffd"},
		{"\xed\xe0\xed", "\ufffd\ufffd\ufffd"},
		{"\x9f\xf5\xa0\xf4\xbf", "\ufffd\ufffd\ufffd\ufffd\ufffd"},
	} {
		if got := decode([]byte(c[0])); got != c[1] {
			t.Errorf("decode(%q) = %q, want %q", c[0], got, c[1])
		}
	}
}

func TestPythonText(t *testing.T) {
	if got := text([]byte("a\r\nb\rc\n\r\n")); got != "a\nb\nc\n\n" {
		t.Errorf("text mode's line ends: %q", got)
	}
	if got := strip("\x1c\u2028 \t a b \u0085\u00a0\x1f\n"); got != "a b" {
		t.Errorf("strip: %q", got)
	}
	for in, want := range map[string]string{"one": "one", "a\nb": "b", "a\x1cb\u0085c\u2028d\x1ee\x1ff": "e\x1ff", "a\r\nb\vc\fd": "d"} {
		if got := lastLine(in); got != want {
			t.Errorf("lastLine(%q) = %q, want %q", in, got, want)
		}
	}
	for _, v := range []any{nil, false, "", json.Number("0"), json.Number("-0.0"), json.Number("0e9"), []any{}, m{}} {
		if truthy(v) {
			t.Errorf("truthy(%#v) is true", v)
		}
	}
	for _, v := range []any{true, "0", json.Number("1"), json.Number("1e999"), []any{nil}, m{"a": nil}} {
		if !truthy(v) {
			t.Errorf("truthy(%#v) is false", v)
		}
	}
}

func TestList(t *testing.T) {
	s, root := fixture(t)
	links(t, root)
	// Python stops the whole listing at a repos.md that isn't UTF-8.
	write(t, root+"/home/wikis-work/jobapp/repos.md", "- caf\xe9\n- jobs\n")
	got, isErr := call(t, s, "wiki_list", m{})
	// Pages: deploy, crlf, latin, .hid/h, sub/deep, the two links to files, and the broken
	// link. Not notes.txt, and not the link to a folder or what is under it again.
	want := "demo (collection default): 8 page(s), covers: api web\n" +
		"global (collection default): 0 page(s)\n" +
		"jobapp (collection work): 1 page(s), covers: caf\ufffd jobs"
	if isErr || got != want {
		t.Errorf("wiki_list = %q\nwant        %q", got, want)
	}
	s.Collections = nil
	if got, _ := call(t, s, "wiki_list", nil); got != "No wikis yet. Run: wiki setup" {
		t.Errorf("with no collections: %q", got)
	}
}

func TestRead(t *testing.T) {
	s, root := fixture(t)
	links(t, root)
	stats := root + "/home/wikis/stats.csv"
	for _, c := range []struct {
		args m
		want string
		err  bool
	}{
		{m{"wiki": "demo"}, "# Index\n\n- [Deploy flow](wiki/deploy.md): canary first\n", false},
		{m{"wiki": "demo", "path": ""}, "# Index\n\n- [Deploy flow](wiki/deploy.md): canary first\n", false},
		{m{"wiki": "demo", "path": nil}, "# Index\n\n- [Deploy flow](wiki/deploy.md): canary first\n", false},
		{m{"wiki": "demo", "path": "wiki/notes.txt"}, "not a page\n", false},
		{m{"wiki": "demo", "path": "./wiki/../wiki/sub/deep.md"}, "deep\n", false},
		{m{"wiki": "demo", "path": "wiki/inner.md"}, "---\ntitle: Deploy\n---\nThe canary goes first.\n", false},
		{m{"wiki": "demo", "path": "wiki/crlf.md"}, "one\ntwo\nthree\n", false},
		{m{"wiki": "demo", "path": "wiki/latin.md"}, "caf\ufffd and a cut arrow \ufffd here\n", false},
		{m{"wiki": "jobapp", "path": "wiki/canary.md"}, "The work canary.\n", false},
		{m{"wiki": "demo", "path": "../global/index.md"}, "that path is outside the wiki.", true},
		{m{"wiki": "demo", "path": "wiki/link.md"}, "that path is outside the wiki.", true},
		{m{"wiki": "demo", "path": "wiki/.hid/h.md"}, "that path is outside the wiki.", true},
		{m{"wiki": "demo", "path": "."}, "that path is outside the wiki.", true},
		{m{"wiki": "demo", "path": "/etc/hosts"}, "give a path inside the wiki, such as index.md or wiki/conventions.md.", true},
		{m{"wiki": "demo", "path": "~/x.md"}, "give a path inside the wiki, such as index.md or wiki/conventions.md.", true},
		{m{"wiki": "demo", "path": "data/x.sqlite"}, "only .md, .csv and .txt files can be read.", true},
		{m{"wiki": "demo", "path": "wiki"}, "only .md, .csv and .txt files can be read.", true},
		{m{"wiki": "demo", "path": "wiki/nope.md"}, "no file wiki/nope.md in that wiki. Its index.md lists the pages.", true},
		{m{"wiki": "demo", "path": "wiki/deploy.md/x.md"}, "no file wiki/deploy.md/x.md in that wiki. Its index.md lists the pages.", true},
		{m{"wiki": "../demo"}, "that isn't a wiki name. wiki_list lists them.", true},
		{m{}, "that isn't a wiki name. wiki_list lists them.", true},
		{m{"wiki": "notes"}, "no wiki called notes. wiki_list lists them.", true},
		{m{"wiki": "jobapp", "collection": "default"}, "no wiki called jobapp. wiki_list lists them.", true},
		{m{"wiki": "demo", "collection": "nope"}, "no collection called nope. Collections: default, work", true},
	} {
		got, isErr := call(t, s, "wiki_read", c.args)
		if got != c.want || isErr != c.err {
			t.Errorf("wiki_read(%v) = %q, error %v\nwant %q, error %v", c.args, got, isErr, c.want, c.err)
		}
	}
	// Reading pages is one hit for the wiki, however many pages. The index isn't a page.
	if got, today := read(t, stats), time.Now().UTC().Format("2006-01-02"); got != "date,wiki,result\n"+today+",demo,hit\n" {
		t.Errorf("stats.csv after the reads: %q", got)
	}
	if got := read(t, root+"/home/wikis-work/stats.csv"); !strings.HasSuffix(got, ",jobapp,hit\n") {
		t.Errorf("the other collection's stats.csv: %q", got)
	}
}

func TestReadCutsALongFile(t *testing.T) {
	s, root := fixture(t)
	// Characters, not bytes: 200,000 of two bytes each fit, and one more doesn't.
	write(t, root+"/home/wikis/demo/wiki/fits.md", strings.Repeat("\u00e9", maxRead))
	write(t, root+"/home/wikis/demo/wiki/big.md", strings.Repeat("\u00e9", maxRead)+"x and more")
	if got, _ := call(t, s, "wiki_read", m{"wiki": "demo", "path": "wiki/fits.md"}); got != strings.Repeat("\u00e9", maxRead) {
		t.Errorf("a file of exactly the limit: %d bytes, ends %q", len(got), got[len(got)-40:])
	}
	got, _ := call(t, s, "wiki_read", m{"wiki": "demo", "path": "wiki/big.md"})
	if want := strings.Repeat("\u00e9", maxRead) + "\n\n[cut off at 200000 characters]"; got != want {
		t.Errorf("a file over the limit: %d bytes, ends %q", len(got), got[len(got)-40:])
	}
}

func TestSearchInProcess(t *testing.T) {
	s, root := fixture(t)
	today := time.Now().UTC().Format("2006-01-02")
	got, isErr := call(t, s, "wiki_search", m{"word": "  CANARY "})
	want := "Collection default:\ndemo:\n  - [Deploy flow](wiki/deploy.md): canary first\n\n" +
		"Collection work:\njobapp:\n  also in pages:\n    wiki/canary.md: The work canary."
	if isErr || got != want {
		t.Errorf("wiki_search = %q\nwant          %q", got, want)
	}
	if calls := read(t, root+"/calls.log"); calls != "" {
		t.Errorf("a plain search ran wiki.sh:\n%s", calls)
	}
	// Logged once for each collection searched, as cmd_find logs it.
	if got := read(t, root+"/home/wikis/stats.csv"); got != "date,wiki,result,word\n"+today+",demo,search-found,CANARY\n" {
		t.Errorf("stats.csv: %q", got)
	}
	if got := read(t, root+"/home/wikis-work/stats.csv"); got != "date,wiki,result,word\n"+today+",jobapp,search-found,CANARY\n" {
		t.Errorf("the other collection's stats.csv: %q", got)
	}
	if got := read(t, s.Tips); got != "# Commands used, and tips shown or muted, on this machine. Written by wiki.sh.\nused:find "+today+"\n" {
		t.Errorf("the tips file: %q", got)
	}

	got, isErr = call(t, s, "wiki_search", m{"word": "zzz,absent" + strings.Repeat("\u00e9", 70), "collection": "work"})
	if isErr || got != "no mentions in any index or page: zzz,absent"+strings.Repeat("\u00e9", 70) {
		t.Errorf("a word found nowhere: %q", got)
	}
	// Against the shared wiki, without its commas, cut at 60 bytes and not inside the
	// character the 60th falls in: nine letters, then 25 of two bytes each.
	if got := read(t, root+"/home/wikis-work/stats.csv"); !strings.HasSuffix(got, "\n"+today+",global,search-none,zzzabsent"+strings.Repeat("\u00e9", 25)+"\n") {
		t.Errorf("stats.csv after a miss: %q", got)
	}
	// An older date for find is replaced, and other lines stay.
	write(t, s.Tips, "# heading\nused:find 2020-01-01\nused:stats 2020-01-02\n")
	call(t, s, "wiki_search", m{"word": "canary", "collection": "work"})
	if got := read(t, s.Tips); got != "# heading\nused:stats 2020-01-02\nused:find "+today+"\n" {
		t.Errorf("the tips file, rewritten: %q", got)
	}

	// Pages are bytes. What reaches a client is text, as Python reads it.
	write(t, root+"/home/wikis/demo/wiki/bytes.md", "odd caf\xe9 and \xe2\x86\r\n")
	if got, _ := call(t, s, "wiki_search", m{"word": "odd", "collection": "default"}); got != "demo:\n  also in pages:\n    wiki/bytes.md: odd caf\ufffd and \ufffd" {
		t.Errorf("a page that isn't UTF-8: %q", got)
	}

	for _, c := range []struct {
		args m
		want string
	}{
		{m{}, "give a word to search for."},
		{m{"word": " \t"}, "give a word to search for."},
		{m{"word": "-x"}, "give a word to search for."},
		{m{"word": "x", "collection": "nope"}, "no collection called nope. Collections: default, work"},
	} {
		if got, isErr := call(t, s, "wiki_search", c.args); !isErr || got != c.want {
			t.Errorf("wiki_search(%v) = %q, error %v, want %q", c.args, got, isErr, c.want)
		}
	}
	s.Collections = []Collection{{"gone", root + "/nowhere"}}
	if got, isErr := call(t, s, "wiki_search", m{"word": "x"}); !isErr || got != "error: no wikis at "+root+"/nowhere" {
		t.Errorf("a collection that isn't there: %q", got)
	}
	s.Collections = []Collection{{"gone", root + "/home/nowhere"}}
	if got, _ := call(t, s, "wiki_search", m{"word": "x"}); got != "error: no wikis at ~/nowhere" {
		t.Errorf("a collection that isn't there, under home: %q", got)
	}
}

// Where the search isn't sure, wiki.sh does all of it: the search and the logging.
func TestSearchFallsBack(t *testing.T) {
	s, root := fixture(t)
	got, isErr := call(t, s, "wiki_search", m{"word": `back\slash`, "collection": "work"})
	if isErr || got != "ran find" {
		t.Errorf("wiki_search = %q, error %v", got, isErr)
	}
	want := "args: [find] [back\\slash]\ndir: " + realTemp(t) + "\nwikis: " + root + "/home/wikis-work\ncmd: wiki.sh\nextra: kept\nstdin: \n"
	if calls := read(t, root+"/calls.log"); calls != want {
		t.Errorf("wiki.sh was run as:\n%s\nwant:\n%s", calls, want)
	}
	if got := read(t, root+"/home/wikis-work/stats.csv") + read(t, s.Tips); got != "" {
		t.Errorf("the server logged a search wiki.sh logs itself: %q", got)
	}
}

func realTemp(t *testing.T) string {
	t.Helper()
	dir, err := filepath.EvalSymlinks(tempDir())
	if err != nil {
		t.Fatal(err)
	}
	return dir
}

func TestStart(t *testing.T) {
	s, root := fixture(t)
	for _, c := range []struct {
		args  m
		calls string
	}{
		// Named after the repository, or listed in a repos.md: no wiki.sh to find out.
		{m{"repository": "demo"}, "args: [start] [demo]|wikis: " + root + "/home/wikis"},
		{m{"repository": "web"}, "args: [start] [web]|wikis: " + root + "/home/wikis"},
		{m{"repository": "jobapp"}, "args: [start] [jobapp]|wikis: " + root + "/home/wikis-work"},
		{m{"repository": "jobs"}, "args: [start] [jobs]|wikis: " + root + "/home/wikis-work"},
		// Nobody's: the default.
		{m{"repository": "nosuch"}, "args: [start] [nosuch]|wikis: " + root + "/home/wikis"},
		{m{"repository": "jobapp", "collection": "default"}, "args: [start] [jobapp]|wikis: " + root + "/home/wikis"},
		{m{"collection": "work"}, "args: [start]|wikis: " + root + "/home/wikis-work"},
		{m{}, "args: [start]|wikis: " + root + "/home/wikis"},
	} {
		os.Remove(root + "/calls.log")
		got, isErr := call(t, s, "wiki_start", c.args)
		calls := strings.Split(read(t, root+"/calls.log"), "\n")
		if isErr || got != "ran start" || len(calls) != 7 || calls[0]+"|"+calls[2] != c.calls {
			t.Errorf("wiki_start(%v) = %q, error %v, and ran:\n%s\nwant %s", c.args, got, isErr, strings.Join(calls, "\n"), c.calls)
		}
	}
	// A repos.md that isn't UTF-8 is one routing isn't sure of, so wiki.sh which says:
	// asked of each collection in turn, until one covers it.
	write(t, root+"/home/wikis-work/jobapp/repos.md", "- caf\xe9\n- jobs\n")
	os.Remove(root + "/calls.log")
	call(t, s, "wiki_start", m{"repository": "jobs"})
	calls := read(t, root+"/calls.log")
	if n := strings.Count(calls, "args: [which] [jobs]"); n != 1 || !strings.Contains(calls, "args: [start] [jobs]\ndir: "+realTemp(t)+"\nwikis: "+root+"/home/wikis-work\n") {
		t.Errorf("wiki_start for a repository routing can't place ran:\n%s", calls)
	}
	if got, isErr := call(t, s, "wiki_start", m{"repository": "../x"}); !isErr || got != "that isn't a repository name." {
		t.Errorf("a repository that is a path: %q", got)
	}
	s.Collections = nil
	if got, isErr := call(t, s, "wiki_start", m{"repository": "web"}); !isErr || got != "no wiki collections are set up. Run: wiki setup" {
		t.Errorf("with no collections: %q", got)
	}
}

func TestWrappedTools(t *testing.T) {
	s, root := fixture(t)
	got, isErr := call(t, s, "wiki_status", m{"collection": "work"})
	if isErr || got != "ran status" {
		t.Errorf("wiki_status = %q, error %v", got, isErr)
	}

	os.Remove(root + "/calls.log")
	note := "We chose Postgres.\nBecause \u2192 reasons.\n"
	got, isErr = call(t, s, "wiki_capture", m{"wiki": "demo", "slug": "pg", "note": note})
	if isErr || got != "ran capture\nPushed. A later session with file access compiles it into pages." {
		t.Errorf("wiki_capture = %q, error %v", got, isErr)
	}
	calls := read(t, root+"/calls.log")
	if !strings.Contains(calls, "args: [capture] [demo] [pg]\n") || !strings.Contains(calls, "stdin: We chose Postgres.\nBecause \u2192 reasons.\n") ||
		!strings.Contains(calls, "args: [sync] [demo] [-m] [demo: capture pg]\n") {
		t.Errorf("wiki_capture ran:\n%s", calls)
	}
	for _, c := range []struct {
		args m
		want string
	}{
		{m{"wiki": "demo", "slug": "../x", "note": "n"}, "the slug is a short name: letters, digits, dashes."},
		{m{"wiki": "demo", "slug": "x", "note": " \n"}, "the note is empty."},
		{m{"wiki": "demo", "slug": "x", "note": strings.Repeat("\u00e9", maxNote+1)}, "the note is over 200000 characters. Save the main points."},
		{m{"wiki": "nosuch", "slug": "x", "note": "n"}, "no wiki called nosuch. wiki_list lists them."},
	} {
		if got, isErr := call(t, s, "wiki_capture", c.args); !isErr || got != c.want {
			t.Errorf("wiki_capture = %q, error %v, want %q", got, isErr, c.want)
		}
	}
	if _, isErr := call(t, s, "wiki_capture", m{"wiki": "demo", "slug": "x", "note": strings.Repeat("\u00e9", maxNote)}); isErr {
		t.Errorf("a note of exactly the limit was refused")
	}

	os.Remove(root + "/calls.log")
	call(t, s, "wiki_feedback", m{"kind": "bug", "summary": "It broke", "details": "What I ran."})
	if calls := read(t, root+"/calls.log"); !strings.Contains(calls, "args: [feedback] [add] [bug] [It broke] [--agent] [unknown, through MCP]\n") ||
		!strings.Contains(calls, "wikis: "+root+"/home/wikis\n") || !strings.Contains(calls, "stdin: What I ran.\n") {
		t.Errorf("wiki_feedback ran:\n%s", calls)
	}

	// What wiki.sh prints when it fails is the tool's error, and what it prints is read
	// as Python reads it: stdout then stderr, bad bytes as U+FFFD, \r as \n, trimmed.
	fake(s, "fail")
	if got, isErr := call(t, s, "wiki_status", m{}); !isErr || got != "error: it went wrong" {
		t.Errorf("a wiki.sh that fails: %q, error %v", got, isErr)
	}
	if got, _ := call(t, s, "wiki_capture", m{"wiki": "demo", "slug": "x", "note": "n"}); got != "error: it went wrong" {
		t.Errorf("a capture that fails: %q", got)
	}
	fake(s, "quiet-fail")
	if got, isErr := call(t, s, "wiki_status", m{}); !isErr || got != "wiki.sh status failed." {
		t.Errorf("a wiki.sh that fails and says nothing: %q, error %v", got, isErr)
	}
	fake(s, "bytes")
	if got, isErr := call(t, s, "wiki_status", m{}); isErr || got != "caf\ufffd \ufffd\nnext\n err" {
		t.Errorf("output that isn't UTF-8: %q, error %v", got, isErr)
	}
	s.WikiSh = root + "/missing.sh"
	if got, isErr := call(t, s, "wiki_status", m{}); !isErr || !strings.HasPrefix(got, "couldn't run wiki.sh: ") {
		t.Errorf("no wiki.sh to run: %q, error %v", got, isErr)
	}
}

// A capture that saved and couldn't push says so, with the last line of why.
func TestCaptureNotPushed(t *testing.T) {
	s, root := fixture(t)
	write(t, s.WikiSh, "#!/bin/sh\n[ \"$1\" = capture ] && { echo saved; exit 0; }\necho 'first line'; echo 'error: no remote' >&2; exit 1\n")
	if err := os.Chmod(s.WikiSh, 0o755); err != nil {
		t.Fatal(err)
	}
	_ = root
	if got, isErr := call(t, s, "wiki_capture", m{"wiki": "demo", "slug": "x", "note": "n"}); isErr || got != "saved\nSaved on this machine, but not pushed: error: no remote" {
		t.Errorf("wiki_capture = %q, error %v", got, isErr)
	}
}

// sync ends well in four ways, and only two of them pushed. A capture is called pushed
// only when sync says "synced: ", wherever in its output that line is.
func TestCapturePushedOnlyWhenSyncPushed(t *testing.T) {
	const pushed = "ran capture\nPushed. A later session with file access compiles it into pages."
	for how, want := range map[string]string{
		"no-remote":  "ran capture\nSaved on this machine, but not pushed: no remote, so nothing to pull or push",
		"unowned":    "ran capture\nSaved on this machine, but not pushed: ~/wikis/demo isn't in a repo the wikis own, so there's nothing to sync. Commits are up to you there.",
		"first-push": pushed,
		"noisy-push": pushed,
	} {
		s, _ := fixture(t)
		fake(s, how)
		if got, isErr := call(t, s, "wiki_capture", m{"wiki": "demo", "slug": "x", "note": "n"}); isErr || got != want {
			t.Errorf("with a sync that ends as %s, wiki_capture = %q, error %v", how, got, isErr)
		}
	}
}

// The time limit holds for a wiki.sh that hangs, and for one that has exited but left
// something holding its output. The server answers the next request either way.
func TestTimeout(t *testing.T) {
	for _, how := range []string{"slow", "linger"} {
		s, _ := fixture(t)
		s.Timeout = 300 * time.Millisecond
		fake(s, how)
		start := time.Now()
		r := serve(t, s, request(1, "wiki_status", m{}), `{"id":2,"method":"ping"}`)
		if took := time.Since(start); took > 3*time.Second {
			t.Errorf("%s: the calls took %v with a limit of %v", how, took, s.Timeout)
		}
		if len(r) != 2 || r[0].Result == nil || !r[0].Result.IsError || r[0].Result.Content[0].Text != "wiki.sh status took more than 0 seconds." || r[1].ID != 2.0 {
			t.Errorf("%s: %+v", how, r)
		}
	}
}

func TestFromEnv(t *testing.T) {
	t.Setenv("LLM_WIKI_COLLECTIONS", "default\t/a/wikis\t\nwork\t/b/wikis\t*gitlab*\n\nbroken\nempty\t\n")
	t.Setenv("LLM_WIKI_SH", "/x/wiki.sh")
	s := FromEnv()
	if got := fmt.Sprint(s.Collections); got != "[{default /a/wikis} {work /b/wikis}]" || s.WikiSh != "/x/wiki.sh" || s.Timeout != 90*time.Second {
		t.Errorf("FromEnv: %s, %q, %v", got, s.WikiSh, s.Timeout)
	}
}
