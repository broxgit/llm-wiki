/*
 * llm-wiki for Obsidian: buttons for the wiki command.
 *
 * Plain JavaScript, with nothing to build: Obsidian loads this file as it is. `wiki obsidian
 * --plugin` copies it into the wikis' vault and writes where the wiki command is.
 *
 * Where the command is, is kept in your home folder (~/.config/llm-wiki/obsidian-command),
 * never in the vault: a vault is a folder a sync service writes to, and what runs on this
 * computer must not be something that can arrive from another one.
 *
 * What it does, and nothing more:
 * - It runs the wiki command, with its arguments as a list and never through a shell, and
 *   always with WIKIS_DIR set to this vault's folder, so it acts on this vault only.
 * - It does that only when you choose a command, except for one read-only count of the
 *   notes that wait, for the status bar.
 * - It does nothing in a vault that isn't a wiki collection (no WIKIS.md at the top).
 * - What a command prints is shown as text, never as HTML or markdown.
 * - It reads no file outside the vault, and sends nothing anywhere itself.
 */
"use strict";

const obsidian = require("obsidian");

const TIMEOUT_MS = 120000;
const MAX_OUTPUT = 200000;
const POLL_MS = 5 * 60 * 1000;
const SLUG_MAX = 60;

// A file name's words as a note's name: lower case, letters and digits, dashes between.
function slugOf(name) {
  const s = String(name || "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, SLUG_MAX).replace(/-+$/g, "");
  return s || "note";
}

// A wiki's name is letters, digits, dots, dashes and underscores, and never starts with a dash or a dot.
// The PATH a wiki command gets: this app's own, then the folders tools are installed in,
// where they aren't in it already. They go last, so nothing the PATH already finds changes.
const TOOL_FOLDERS = ["/opt/homebrew/bin", "/usr/local/bin"];
function withToolFolders(current) {
  if (process.platform === "win32") return current;
  // With no PATH at all the system picks its own, which a PATH of only these would take away.
  if (!current) return current;
  const have = String(current).split(":").filter(Boolean);
  for (const f of TOOL_FOLDERS) if (!have.includes(f)) have.push(f);
  return have.join(":");
}

function isWikiName(name) {
  return /^[A-Za-z0-9_][A-Za-z0-9._-]{0,99}$/.test(String(name || ""));
}

// Text from a command, fit to show: no control characters but line breaks and tabs, and not endless.
function clean(text) {
  // eslint-disable-next-line no-control-regex
  let s = String(text || "").replace(/\u001b\[[0-9;?]*[ -/]*[@-~]/g, "").replace(/[\u0000-\u0008\u000b-\u001f\u007f\u0080-\u009f‪-‮⁦-⁩]/g, "");
  if (s.length > MAX_OUTPUT) s = s.slice(0, MAX_OUTPUT) + "\n… (cut here)";
  return s.trim();
}

class OutputModal extends obsidian.Modal {
  constructor(app, title, text) {
    super(app);
    this.title = title;
    this.text = text;
  }
  onOpen() {
    this.titleEl.setText(this.title);
    // Wide enough for a table from the command not to wrap, where the window allows.
    if (this.modalEl && this.modalEl.style) this.modalEl.style.width = "min(960px, 92vw)";
    const pre = this.contentEl.createEl("pre");
    pre.style.whiteSpace = "pre-wrap";
    pre.style.userSelect = "text";
    pre.setText(this.text || "Nothing to show.");
  }
  onClose() {
    this.contentEl.empty();
  }
}

class AskModal extends obsidian.Modal {
  constructor(app, title, placeholder, onSubmit) {
    super(app);
    this.title = title;
    this.placeholder = placeholder;
    this.onSubmit = onSubmit;
  }
  onOpen() {
    this.titleEl.setText(this.title);
    const input = this.contentEl.createEl("input", { type: "text" });
    input.placeholder = this.placeholder;
    input.style.width = "100%";
    input.addEventListener("keydown", (e) => {
      if (e.key === "Enter") {
        const v = input.value.trim();
        this.close();
        if (v) this.onSubmit(v);
      }
    });
    input.focus();
  }
  onClose() {
    this.contentEl.empty();
  }
}

class WikiPicker extends obsidian.FuzzySuggestModal {
  constructor(app, names, onPick) {
    super(app);
    this.names = names;
    this.onPick = onPick;
    this.setPlaceholder("Which wiki is this note for?");
  }
  getItems() {
    return this.names;
  }
  getItemText(name) {
    return name;
  }
  onChooseItem(name) {
    this.onPick(name);
  }
}

const NO_COMMAND = "The wiki command for this computer isn't set. In a terminal, run: wiki obsidian --plugin";

class LlmWikiPlugin extends obsidian.Plugin {
  async onload() {
    this.running = new Set();
    this.polling = false;
    this.statusEl = this.addStatusBarItem();

    this.addCommand({ id: "save-note", name: "Save this note to a wiki", callback: () => this.saveNote() });
    this.addCommand({ id: "take-inbox", name: "Take in the inbox now", callback: () => this.show("Inbox", ["inbox", "--now"]) });
    this.addCommand({ id: "attention", name: "What needs attention", callback: () => this.show("What needs attention", ["status"]) });
    this.addCommand({ id: "find", name: "Find across every wiki", callback: () => this.find() });
    this.addCommand({ id: "compile", name: "Compile this wiki's waiting notes", callback: () => this.compile() });
    this.addCommand({ id: "sync", name: "Sync: save and share this wiki", callback: () => this.sync() });
    this.addRibbonIcon("inbox", "llm-wiki: what needs attention", () => this.show("What needs attention", ["status"]));

    this.registerEvent(this.app.workspace.on("file-open", (file) => this.warnIfCompiling(file)));
    this.registerInterval(window.setInterval(() => this.refresh(), POLL_MS));
    this.app.workspace.onLayoutReady(() => this.refresh());
  }

  // The vault's folder on disk, or "" where there is none (a phone).
  base() {
    const a = this.app.vault.adapter;
    return a && typeof a.getBasePath === "function" ? a.getBasePath() : "";
  }

  // Whether this vault is a wiki collection. In any other vault the plugin does nothing.
  async isCollection() {
    return !!this.base() && (await this.app.vault.adapter.exists("WIKIS.md"));
  }

  // The wikis in this vault: top-level folders with a handbook and an index.
  async wikis() {
    const out = [];
    const listing = await this.app.vault.adapter.list("");
    for (const dir of listing.folders || []) {
      const name = dir.split("/").pop();
      if (!isWikiName(name)) continue;
      if ((await this.app.vault.adapter.exists(dir + "/AGENTS.md")) && (await this.app.vault.adapter.exists(dir + "/index.md"))) out.push(name);
    }
    return out.sort();
  }

  // The wiki a file is in, or "".
  async wikiOf(file) {
    if (!file || !file.path) return "";
    const top = file.path.split("/")[0];
    return (await this.wikis()).includes(top) ? top : "";
  }

  // Where the wiki command is on this computer: one line in a file in the home folder, which
  // `wiki obsidian --plugin` writes. It must be a full path, and never a file inside the vault.
  command() {
    let c = "";
    try {
      const os = require("os");
      const fs = require("fs");
      const path = require("path");
      c = fs.readFileSync(path.join(os.homedir(), ".config", "llm-wiki", "obsidian-command"), "utf8").split("\n")[0].trim();
      const base = this.base();
      if (!path.isAbsolute(c) || /[\u0000-\u001f\u007f]/.test(c)) return "";
      const rel = base ? path.relative(base, c) : "..";
      if (!rel || (!rel.startsWith("..") && !path.isAbsolute(rel))) return "";
    } catch (e) {
      return "";
    }
    return c;
  }

  // Run the wiki command. Arguments are a list, there is no shell, and WIKIS_DIR is this vault.
  run(args, input) {
    return new Promise((resolve) => {
      const base = this.base();
      if (!base) return resolve({ code: 1, text: "This vault has no folder on this device, so the wiki command can't run here." });
      const command = this.command();
      if (!command) return resolve({ code: 127, text: NO_COMMAND });
      // An app started from the Dock or Finder gets a short PATH, without Homebrew's folders.
      // There the secret scan wouldn't be found, and a sync would go through unscanned.
      const env = Object.assign({}, process.env, { WIKIS_DIR: base, LLM_WIKI_STYLE: "off", NO_COLOR: "1", PATH: withToolFolders(process.env.PATH) });
      let child = null;
      let settled = false;
      let timer = null;
      const finish = (r) => {
        if (settled) return;
        settled = true;
        if (timer) clearTimeout(timer);
        if (child) this.running.delete(child);
        resolve(r);
      };
      try {
        child = require("child_process").execFile(command, args, { cwd: base, env, timeout: TIMEOUT_MS, killSignal: "SIGKILL", maxBuffer: MAX_OUTPUT * 4, windowsHide: true }, (err, stdout, stderr) => {
          const text = clean([stdout, stderr].filter(Boolean).join("\n"));
          if (err && err.code === "ENOENT") return finish({ code: 127, text: `The wiki command wasn't found at "${clean(command)}". In a terminal, run: wiki obsidian --plugin` });
          if (err && err.code === "ERR_CHILD_PROCESS_STDIO_MAXBUFFER") return finish({ code: 1, text: (text ? text + "\n\n" : "") + "It printed more than can be shown here, and was stopped." });
          if (err && err.killed) return finish({ code: 124, text: (text ? text + "\n\n" : "") + "It took more than two minutes and was stopped." });
          finish({ code: err ? (typeof err.code === "number" ? err.code : 1) : 0, text });
        });
      } catch (e) {
        return finish({ code: 1, text: "The wiki command couldn't be started: " + clean(e && e.message) });
      }
      this.running.add(child);
      // Something it started may hold its output open after it is stopped: don't wait for that.
      timer = setTimeout(() => {
        try {
          child.kill("SIGKILL");
        } catch (e) {
          // already gone
        }
        finish({ code: 124, text: "It took more than two minutes and was stopped." });
      }, TIMEOUT_MS + 3000);
      if (child.stdin) {
        child.stdin.on("error", () => {});
        child.stdin.end(input || "");
      }
    });
  }

  // Turned off or Obsidian closing: nothing it started is left running.
  onunload() {
    for (const child of this.running) {
      try {
        child.kill("SIGKILL");
      } catch (e) {
        // already gone
      }
    }
    this.running.clear();
  }

  async guard() {
    if (await this.isCollection()) return true;
    new obsidian.Notice("llm-wiki: this vault isn't a wiki collection (it has no WIKIS.md), so nothing was run.");
    return false;
  }

  async show(title, args) {
    if (!(await this.guard())) return;
    const r = await this.run(args);
    new OutputModal(this.app, title, r.text).open();
    this.refresh();
  }

  async find() {
    if (!(await this.guard())) return;
    new AskModal(this.app, "Find across every wiki", "a word or a phrase", (words) => {
      // A word that starts with a dash would be read as an option of the command.
      const w = words.replace(/^[-\s]+/, "");
      if (w) this.show("Found: " + w, ["find", w]);
    }).open();
  }

  // The note in view becomes a waiting note of a wiki: the wiki it is in, or the one you pick.
  async saveNote() {
    if (!(await this.guard())) return;
    const file = this.app.workspace.getActiveFile();
    if (!file || file.extension !== "md") {
      new obsidian.Notice("llm-wiki: open a note first.");
      return;
    }
    // What is in the editor, which Obsidian may not have written to disk yet.
    const ed = this.app.workspace.activeEditor;
    const text = ed && ed.file === file && ed.editor && typeof ed.editor.getValue === "function" ? ed.editor.getValue() : await this.app.vault.read(file);
    if (!text.trim()) {
      new obsidian.Notice("llm-wiki: this note is empty, so there is nothing to save.");
      return;
    }
    const save = async (wiki) => {
      if (!isWikiName(wiki)) return;
      const r = await this.run(["capture", wiki, slugOf(file.basename)], text);
      if (r.code === 0) new obsidian.Notice(`llm-wiki: saved to ${wiki}. An agent's next compile works it into the pages.`);
      else new OutputModal(this.app, "The note wasn't saved", r.text).open();
      this.refresh();
    };
    const own = await this.wikiOf(file);
    if (own) return save(own);
    const names = await this.wikis();
    if (!names.length) {
      new obsidian.Notice("llm-wiki: there is no wiki in this vault yet.");
      return;
    }
    new WikiPicker(this.app, names, save).open();
  }

  async activeWiki() {
    const own = await this.wikiOf(this.app.workspace.getActiveFile());
    if (own) return own;
    new obsidian.Notice("llm-wiki: open a page of the wiki you mean first.");
    return "";
  }

  async compile() {
    if (!(await this.guard())) return;
    const wiki = await this.activeWiki();
    if (!wiki) return;
    new obsidian.Notice(`llm-wiki: asking for a compile of ${wiki}…`);
    const r = await this.run(["compile", wiki, "--background"]);
    new OutputModal(this.app, "Compile " + wiki, r.text).open();
    this.refresh();
  }

  async sync() {
    if (!(await this.guard())) return;
    const wiki = await this.activeWiki();
    if (!wiki) return;
    const r = await this.run(["sync", wiki]);
    // A line that starts "note:" is a warning, such as a commit that went through with no
    // scan for secrets. It is never the last line, so the whole of what sync said is shown.
    const warned = r.text.split("\n").some((line) => line.startsWith("note:"));
    if (r.code === 0 && !warned) new obsidian.Notice("llm-wiki: " + (r.text.split("\n").pop() || "synced").slice(0, 300));
    else new OutputModal(this.app, "Sync " + wiki, r.text).open();
    this.refresh();
  }

  // A page that an agent is rewriting right now: say so, so nobody types into it.
  async warnIfCompiling(file) {
    try {
      if (!(await this.isCollection())) return;
      const wiki = await this.wikiOf(file);
      if (!wiki) return;
      const lock = wiki + "/.compile-lock";
      if (!(await this.app.vault.adapter.exists(lock))) return;
      const first = (await this.app.vault.adapter.read(lock)).split("\n")[0] || "";
      if (first.startsWith("held ")) new obsidian.Notice(`llm-wiki: ${wiki} is being compiled right now. What you type into its pages may be overwritten.`, 8000);
    } catch (e) {
      // Reading the lock is a courtesy: never an error for the person.
    }
  }

  // The status bar: how many notes wait, from one command that changes nothing. Without
  // --keep-inbox the count would first take the notes in every inbox, a note still open here included.
  async refresh() {
    // One count at a time: a slow one must not pile up, or write an old number over a new one.
    if (this.polling) return;
    this.polling = true;
    try {
      if (!(await this.isCollection())) {
        this.statusEl.setText("");
        return;
      }
      const r = await this.run(["pending", "--keep-inbox"]);
      if (r.code !== 0) {
        this.statusEl.setText(r.code === 127 ? "wiki: command not set up" : "");
        return;
      }
      let n = 0;
      for (const line of r.text.split("\n")) {
        const m = /^[^:]+: (\d+) waiting\b/.exec(line.trim());
        if (m) n += parseInt(m[1], 10);
      }
      this.statusEl.setText(n > 0 ? `wiki: ${n} waiting` : "wiki: nothing waiting");
    } catch (e) {
      this.statusEl.setText("");
    } finally {
      this.polling = false;
    }
  }
}

module.exports = LlmWikiPlugin;
module.exports.slugOf = slugOf;
module.exports.isWikiName = isWikiName;
module.exports.clean = clean;
module.exports.withToolFolders = withToolFolders;
