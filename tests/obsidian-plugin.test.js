// Tests for obsidian-plugin/main.js, with a stand-in for Obsidian's API and a stand-in
// wiki command that writes down how it was called. Run by tests/smoke.sh:
//   node tests/obsidian-plugin.test.js <a scratch folder>
"use strict";
const fs = require("fs");
const path = require("path");
const Module = require("module");

const scratch = process.argv[2];
if (!scratch) {
  console.error("usage: node tests/obsidian-plugin.test.js <scratch folder>");
  process.exit(2);
}
let failed = 0;
function check(name, ok, detail) {
  console.log((ok ? "ok    " : "FAIL  ") + name + (ok || detail === undefined ? "" : "\n        " + String(detail)));
  if (!ok) failed++;
}

// ---- a stand-in for Obsidian -------------------------------------------------------
const notices = [];
const modals = [];
function el() {
  return {
    text: "", children: [], style: {}, listeners: {},
    setText(t) { this.text = String(t); },
    empty() { this.children = []; },
    createEl(tag, opts) { const c = el(); c.tag = tag; c.opts = opts; this.children.push(c); return c; },
    addEventListener(k, f) { this.listeners[k] = f; },
    focus() {},
    set innerHTML(v) { throw new Error("innerHTML was set"); },
  };
}
class Modal {
  constructor(app) { this.app = app; this.titleEl = el(); this.contentEl = el(); }
  open() { modals.push(this); this.onOpen(); }
  close() {}
}
class FuzzySuggestModal extends Modal {
  setPlaceholder() {}
  open() { modals.push(this); }
}
class Plugin {
  constructor(app) { this.app = app; this.commands = []; this.saved = null; }
  addCommand(c) { this.commands.push(c); }
  addStatusBarItem() { this.status = el(); return this.status; }
  addRibbonIcon() {}
  addSettingTab() {}
  registerEvent() {}
  registerInterval() {}
  async loadData() { return this.data; }
  async saveData(d) { this.saved = d; }
}
class PluginSettingTab { constructor(app, plugin) { this.app = app; this.containerEl = el(); } }
class Setting { setName() { return this; } setDesc() { return this; } addText() { return this; } }
class Notice { constructor(text) { notices.push(String(text)); } }
const stub = { Modal, FuzzySuggestModal, Plugin, PluginSettingTab, Setting, Notice };
const realLoad = Module._load;
Module._load = function (request, ...rest) {
  return request === "obsidian" ? stub : realLoad.call(this, request, ...rest);
};
global.window = { setInterval: () => 0 };

const LlmWiki = require(path.join(__dirname, "..", "obsidian-plugin", "main.js"));

// ---- a vault on disk, and a wiki command that writes down its calls ----------------
// The plugin reads where the wiki command is from the home folder, never from the vault.
process.env.HOME = path.join(scratch, "home");
const commandFile = path.join(process.env.HOME, ".config", "llm-wiki", "obsidian-command");
fs.mkdirSync(path.dirname(commandFile), { recursive: true });
const vault = path.join(scratch, "vault with a space");
const calls = path.join(scratch, "calls");
fs.mkdirSync(calls, { recursive: true });
// Every call written down so far, oldest first.
function allCalls() {
  return fs
    .readdirSync(calls)
    .map((n) => ({ n, m: fs.statSync(path.join(calls, n)).mtimeMs }))
    .sort((a, b) => a.m - b.m || a.n.localeCompare(b.n))
    .map((x) => fs.readFileSync(path.join(calls, x.n), "utf8"));
}
const fake = path.join(scratch, "fake-wiki");
fs.mkdirSync(path.join(vault, "demo", "wiki"), { recursive: true });
fs.mkdirSync(path.join(vault, "notes"), { recursive: true });
fs.mkdirSync(path.join(vault, "-odd"), { recursive: true });
fs.writeFileSync(path.join(vault, "WIKIS.md"), "# Wikis\n");
for (const w of ["demo", "-odd"]) {
  fs.writeFileSync(path.join(vault, w, "AGENTS.md"), "x\n");
  fs.writeFileSync(path.join(vault, w, "index.md"), "# Index\n");
}
fs.writeFileSync(path.join(vault, "demo", "wiki", "My Page!.md"), "# Page\n\nwords; $(touch " + path.join(scratch, "pwned") + ")\n");
fs.writeFileSync(path.join(vault, "notes", "loose.md"), "a loose note\n");
fs.writeFileSync(
  fake,
  // Each call is written to a file of its own: two calls at once can't mix their lines.
  '#!/bin/sh\n{ echo "dir=$WIKIS_DIR"; echo "style=$LLM_WIKI_STYLE"; for a in "$@"; do echo "arg=$a"; done; echo "stdin=$(cat)"; } > "' + scratch + '/.call.$$"\nmv "' + scratch + '/.call.$$" "' + calls + '/$$"\n' +
    'case "$1" in pending) echo "demo: 2 waiting"; echo "global: 1 waiting" ;; status) printf "all \\033[31mred\\033[0m well\\n" ;; sync) echo "saved: a snapshot" ;; capture) [ "$2" = fails ] && { echo "error: no such wiki" >&2; exit 1; }; echo "captured: raw/x.md" ;; *) echo "ran $1" ;; esac\n'
);
fs.chmodSync(fake, 0o755);

function app(base, active) {
  const rel = (p) => path.join(base, p);
  return {
    vault: {
      adapter: {
        getBasePath: () => base,
        exists: async (p) => fs.existsSync(rel(p)),
        list: async (p) => ({ folders: fs.readdirSync(rel(p), { withFileTypes: true }).filter((d) => d.isDirectory()).map((d) => d.name), files: [] }),
        read: async (p) => fs.readFileSync(rel(p), "utf8"),
      },
      read: async (f) => fs.readFileSync(rel(f.path), "utf8"),
    },
    workspace: {
      handlers: {},
      on(name, f) { this.handlers[name] = f; return {}; },
      onLayoutReady: (cb) => cb(),
      getActiveFile: () => active.file,
      get activeEditor() { return active.editor || null; },
    },
  };
}
function file(p) {
  return { path: p, basename: path.basename(p, ".md"), extension: path.extname(p).slice(1) };
}
function lastCall() {
  const all = allCalls();
  return all.length ? all[all.length - 1] : "";
}
// Whether any call written down so far matches: an action is followed by a count for the status bar.
function called(re) {
  return allCalls().some((c) => re.test(c));
}
// Wait for a call to be written down, for up to ten seconds: a loaded machine is slow, not wrong.
async function seen(re) {
  for (let i = 0; i < 200; i++) {
    if (called(re)) return true;
    await new Promise((r) => setTimeout(r, 50));
  }
  return false;
}
// How many calls were made, leaving out the count for the status bar, which follows an
// action a moment later and would make a before-and-after comparison a matter of luck.
function callCount() {
  return allCalls().filter((c) => !/\narg=pending\n/.test(c)).length;
}

(async () => {
  // Pure helpers.
  check("a note's name becomes a slug of letters, digits and dashes", LlmWiki.slugOf("My Page! (v2)") === "my-page-v2" && LlmWiki.slugOf("---") === "note" && LlmWiki.slugOf("x".repeat(200)).length <= 60);
  check("a wiki's name never starts with a dash or a dot", LlmWiki.isWikiName("demo") && LlmWiki.isWikiName("My-Repo.v2") && !LlmWiki.isWikiName("-odd") && !LlmWiki.isWikiName(".obsidian") && !LlmWiki.isWikiName("a/b") && !LlmWiki.isWikiName(""));
  const cleaned = LlmWiki.clean("a\u001b[31mred\u001b[0m\u0007b‮c\n\td");
  check("what a command prints loses its escape codes and control characters, and keeps its lines", cleaned === "aredbc\n\td", JSON.stringify(cleaned));

  const active = { file: file("demo/wiki/My Page!.md") };
  const p = new LlmWiki(app(vault, active));
  // A command planted in the vault's own settings for the plugin is never read.
  fs.writeFileSync(path.join(scratch, "planted"), '#!/bin/sh\ntouch "' + path.join(scratch, "planted-ran") + '"\n');
  fs.chmodSync(path.join(scratch, "planted"), 0o755);
  p.data = { command: path.join(scratch, "planted") };
  let r0 = await p.run(["status"]);
  check("with no command set for this computer, nothing runs, and it says what to do", r0.code === 127 && r0.text.includes("wiki obsidian --plugin") && callCount() === 0, JSON.stringify(r0));
  fs.writeFileSync(commandFile, "fake-wiki\n");
  r0 = await p.run(["status"]);
  check("a command that isn't a full path is not run", r0.code === 127 && callCount() === 0, JSON.stringify(r0));
  fs.copyFileSync(fake, path.join(vault, "wiki-in-vault"));
  fs.chmodSync(path.join(vault, "wiki-in-vault"), 0o755);
  fs.writeFileSync(commandFile, path.join(vault, "wiki-in-vault") + "\n");
  r0 = await p.run(["status"]);
  check("nor one that is a file inside the vault", r0.code === 127 && callCount() === 0, JSON.stringify(r0));
  fs.writeFileSync(commandFile, fake + "\n");
  await p.onload();
  check("a command in the vault's own plugin settings was never run", !fs.existsSync(path.join(scratch, "planted-ran")));
  check("the count for the status bar was asked for once Obsidian was ready", await seen(/arg=pending\n/));
  check("it adds six commands", p.commands.length === 6, p.commands.map((c) => c.id).join(" "));
  check("every command has a name a person can read", p.commands.every((c) => c.name && typeof c.callback === "function"));
  const cmd = (id) => p.commands.find((c) => c.id === id).callback();

  check("only real wikis are found: a folder with a handbook and an index, and a proper name", JSON.stringify(await p.wikis()) === '["demo"]', JSON.stringify(await p.wikis()));

  await p.refresh();
  check("the status bar counts the notes that wait, across wikis", p.status.text === "wiki: 3 waiting", p.status.text);
  check("with one read-only command, on this vault, with style off", await seen(/dir=.*vault with a space\nstyle=off\narg=pending\n/), lastCall());

  await cmd("save-note");
  let c = lastCall();
  check("saving the note in view captures it into the wiki it is in", /arg=capture\narg=demo\narg=my-page\n/.test(c), c);
  check("its text goes in on standard input, as it is", c.includes("stdin=# Page") && c.includes("$(touch "), c);
  check("and nothing in the note was run by a shell", !fs.existsSync(path.join(scratch, "pwned")));
  check("it says the note was saved", notices.some((n) => n.includes("saved to demo")), notices.join(" | "));

  active.file = file("notes/loose.md");
  modals.length = 0;
  await cmd("save-note");
  check("a note outside any wiki asks which wiki, offering only real ones", modals.length === 1 && JSON.stringify(modals[0].getItems()) === '["demo"]');
  modals[0].onChooseItem("demo");
  check("and the choice is where it is captured", await seen(/arg=capture\narg=demo\narg=loose\n/), lastCall());
  let n = callCount();
  await modals[0].onPick("-rf");
  await modals[0].onPick("../x");
  check("a wiki name that isn't one is never passed to the command", callCount() === n);

  active.file = null;
  notices.length = 0;
  n = callCount();
  await cmd("save-note");
  check("with no note open it says so and runs nothing", callCount() === n && notices.some((x) => x.includes("open a note first")));

  modals.length = 0;
  await cmd("attention");
  check("what needs attention shows what status printed, as text, without its colour codes", modals.length === 1 && modals[0].contentEl.children[0].text === "all red well", JSON.stringify(modals[0] && modals[0].contentEl.children[0]));

  modals.length = 0;
  await cmd("find");
  modals[0].contentEl.children[0].value = "  --all; rm -rf ~ ";
  modals[0].contentEl.children[0].listeners.keydown({ key: "Enter" });
  check("find passes the words as one argument, with no leading dash to be read as an option", await seen(/arg=find\narg=all; rm -rf ~\nstdin=/), lastCall());

  active.file = file("demo/wiki/My Page!.md");
  await cmd("compile");
  check("compile asks for a background compile of the wiki in view", await seen(/arg=compile\narg=demo\narg=--background\n/), lastCall());
  notices.length = 0;
  await cmd("sync");
  check("sync runs for the wiki in view and says what it said", await seen(/arg=sync\narg=demo\n/) && notices.some((x) => x.includes("saved: a snapshot")), notices.join(" | "));
  active.file = file("notes/loose.md");
  n = callCount();
  await cmd("sync");
  check("sync and compile need a page of a wiki in view, and run nothing without one", callCount() === n);

  // A page being compiled.
  fs.writeFileSync(path.join(vault, "demo", ".compile-lock"), "held abc someone 2026-11-18T00:00:00Z\n");
  notices.length = 0;
  await p.warnIfCompiling(file("demo/wiki/My Page!.md"));
  check("opening a page of a wiki that is being compiled says so", notices.some((x) => x.includes("demo is being compiled right now")));
  fs.writeFileSync(path.join(vault, "demo", ".compile-lock"), "free\n");
  notices.length = 0;
  await p.warnIfCompiling(file("demo/wiki/My Page!.md"));
  check("and says nothing once the lock is free", notices.length === 0);

  // A command that fails, and one that isn't there.
  let r = await p.run(["capture", "fails", "x"], "text");
  check("a command that fails gives its exit code and what it said", r.code === 1 && r.text.includes("no such wiki"), JSON.stringify(r));
  fs.writeFileSync(commandFile, path.join(scratch, "nowhere", "wiki") + "\n");
  r = await p.run(["status"]);
  check("a command that isn't there says how to fix it", r.code === 127 && r.text.includes("wiki obsidian --plugin"), JSON.stringify(r));
  await p.refresh();
  check("and the status bar says the command isn't set up", p.status.text === "wiki: command not set up", p.status.text);
  fs.writeFileSync(commandFile, fake + "\n");

  // What is in the editor is what is saved, even before Obsidian writes it to disk.
  active.file = file("demo/wiki/My Page!.md");
  active.editor = { file: active.file, editor: { getValue: () => "typed a moment ago\n" } };
  await cmd("save-note");
  check("saving takes the text in the editor, not an older copy on disk", await seen(/arg=my-page\nstdin=typed a moment ago/), lastCall());
  active.editor = null;

  // Turning the plugin off stops what it started.
  const slow = path.join(scratch, "slow-wiki");
  fs.writeFileSync(slow, "#!/bin/sh\nexec sleep 30\n");
  fs.chmodSync(slow, 0o755);
  fs.writeFileSync(commandFile, slow + "\n");
  const started = Date.now();
  const pendingRun = p.run(["status"]);
  await new Promise((r) => setTimeout(r, 200));
  p.onunload();
  const stopped = await pendingRun;
  check("turning the plugin off stops a command still running", Date.now() - started < 10000 && stopped.code !== 0, JSON.stringify(stopped));
  fs.writeFileSync(commandFile, fake + "\n");

  // A vault that isn't a wiki collection: nothing runs.
  const other = path.join(scratch, "other vault");
  fs.mkdirSync(other, { recursive: true });
  fs.writeFileSync(path.join(other, "CREDS.md"), "secret\n");
  const otherApp = app(other, { file: file("CREDS.md") });
  const q = new LlmWiki(otherApp);
  await q.onload();
  // A folder there that looks like a wiki being compiled: still not this plugin's business.
  fs.mkdirSync(path.join(other, "looks"), { recursive: true });
  for (const f of ["AGENTS.md", "index.md"]) fs.writeFileSync(path.join(other, "looks", f), "x\n");
  fs.writeFileSync(path.join(other, "looks", ".compile-lock"), "held abc someone\n");
  fs.writeFileSync(path.join(other, "looks", "p.md"), "x\n");
  notices.length = 0;
  await otherApp.workspace.handlers["file-open"](file("looks/p.md"));
  check("opening a file there says nothing, whatever the folder looks like", notices.length === 0, notices.join(" | "));
  n = callCount();
  notices.length = 0;
  for (const c2 of q.commands) await c2.callback();
  await q.refresh();
  check("in a vault that isn't a wiki collection, no command runs the wiki command", callCount() === n);
  check("and each says why", notices.length >= 6 && notices.every((x) => x.includes("isn't a wiki collection")), notices.join(" | "));
  check("and the status bar stays empty", q.status.text === "");
  check("not even the count for it was asked for there", !allCalls().some((c) => c.includes("other vault")));

  const src = fs.readFileSync(path.join(__dirname, "..", "obsidian-plugin", "main.js"), "utf8");
  check("the plugin never builds HTML from text, and never uses a shell", !/innerHTML|outerHTML|insertAdjacentHTML|MarkdownRenderer|shell:\s*true|execSync|spawn\(|\.exec\(["'`]/.test(src) && src.includes(".execFile(command, args,"));
  check("it asks the network for nothing", !/\bfetch\(|requestUrl|XMLHttpRequest|require\("https?"\)|WebSocket/.test(src));
  const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "obsidian-plugin", "manifest.json"), "utf8"));
  check("the manifest names it, and says it is for a computer only", manifest.id === "llm-wiki" && manifest.isDesktopOnly === true && /^\d+\.\d+\.\d+$/.test(manifest.version));

  console.log(failed ? `${failed} failed` : "all passed");
  process.exit(failed ? 1 : 0);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
