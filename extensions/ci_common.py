"""The parts of llm-wiki's CI extensions (wiki-github, wiki-gitlab, wiki-jenkins) that are not about one system.

Not an extension: it has no extension header and no `wiki-` name, so llm-wiki never lists or runs it. An
extension imports it from its own folder. Standard library only. Everything here is a function of its arguments,
and the paths that differ from one extension to the next (its settings file, its state and log folders) are passed in.

What is here: cleaning text that came from outside, cutting a long log down to an excerpt and finding the line that
names the error, keeping excerpts in a private folder, the settings file, the notice and desktop notification a new
failure leaves, the note in a wiki when a failure is fixed, which collection that wiki is in, the state file and the
list of watched folders.

Nothing here talks to GitHub, GitLab or Jenkins, and nothing here writes to them.
"""
import contextlib
import datetime
import hashlib
import json
import os
import re
import stat
import subprocess
import sys
import tempfile
import time
import unicodedata

try:
    import fcntl
except ImportError:  # not on this system: state is then written without a lock
    fcntl = None

CMD = os.environ.get("LLM_WIKI_CMD", "wiki")

KEEP_LINES = 120
KEEP_BYTES = 8000
KEEP_DAYS = 7
SIGNATURE_CHARS = 160
NOTICE_DAYS = 3
SYNC_SECONDS = 300
SEPARATORS = "\x0b\x0c\x1c\x1d\x1e\x85\u2028\u2029"


def die(msg, code=1):
    sys.stdout.flush()
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(code)


def die_usage(msg):
    """Called wrongly: an unknown command or option, a missing argument. Exits 2."""
    die(msg, 2)


def clean(text, limit=300):
    """Text from outside, safe to print and to save: no control character and no line separator,
    one line, cut at limit characters."""
    out = []
    for c in str(text):
        cat = unicodedata.category(c)
        if c in "\t\n\r":
            out.append(" ")
        elif c in SEPARATORS or cat[0] == "C" or cat in ("Zl", "Zp"):
            continue
        else:
            out.append(c)
    return " ".join("".join(out).split())[:limit]


def first_line(text):
    for line in text.splitlines():
        if line.strip():
            return clean(line, 200)
    return ""


def is_yes(value):
    return str(value).strip().lower() in ("yes", "true", "on", "1")


# ---- settings, as wiki-jira keeps them ------------------------------------------------------

def conf_lines(path):
    """The lines of a settings file, by the one rule everything that reads or writes it shares:
    a line ends at a newline, and a trailing carriage return is dropped. Nothing else splits one."""
    with open(path, encoding="utf-8", errors="surrogateescape", newline="") as f:
        text = f.read()
    lines = [l[:-1] if l.endswith("\r") else l for l in text.split("\n")]
    if lines and lines[-1] == "":
        lines.pop()
    return lines


def read_conf(path):
    conf = {}
    try:
        for line in conf_lines(path):
            line = line.split("#", 1)[0].strip()
            if "=" in line:
                k, v = line.split("=", 1)
                conf[k.strip()] = v.strip()
    except FileNotFoundError:
        pass
    return conf


def unfit(text):
    """Why a key or value can't be written to a settings file, in words that don't repeat it, or nothing."""
    try:
        text.encode("utf-8")
    except UnicodeEncodeError:
        return "isn't valid UTF-8"
    for c in text:
        cat = unicodedata.category(c)
        if c in SEPARATORS or cat[0] == "C" or cat in ("Zl", "Zp"):
            return "can't hold a control character or a line separator"
    return ""


def set_conf(path, key, value):
    """Set one `name = value` line in a settings file, or take it out when value is empty.
    Every other line stays as it is. The file is written beside itself and moved into place,
    so a write that fails leaves the old one."""
    why = unfit(key) or unfit(value) or ("is more than one line" if len(value.splitlines()) > 1 else "")
    if why:
        die_usage(f"the value of {key} {why}, so nothing was written")
    try:
        lines = conf_lines(path)
    except FileNotFoundError:
        lines = []
    kept = [l for l in lines if l.split("#", 1)[0].split("=", 1)[0].strip() != key or "=" not in l.split("#", 1)[0]]
    if value:
        kept.append(f"{key} = {value}")
    path = os.path.realpath(path)
    folder = os.path.dirname(path)
    tmp = None
    try:
        os.makedirs(folder, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=folder, prefix=".settings-")
        with os.fdopen(fd, "w", encoding="utf-8", errors="surrogateescape", newline="") as f:
            f.write("\n".join(kept) + ("\n" if kept else ""))
        try:
            mode = stat.S_IMODE(os.stat(path).st_mode)
        except FileNotFoundError:
            mask = os.umask(0)
            os.umask(mask)
            mode = 0o666 & ~mask
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except OSError as e:
        if tmp:
            try:
                os.unlink(tmp)
            except OSError:
                pass
        die(f"can't write {path}: {e.strerror or e}. The old file is as it was")


# ---- the folders a tick looks at ---------------------------------------------------------------

def watched(config, conf=None):
    """The folders in the watch setting of a settings file, as written."""
    conf = conf if conf is not None else read_conf(config)
    return [os.path.expanduser(p.strip()) for p in conf.get("watch", "").split(",") if p.strip()]


def write_watch(config, paths):
    set_conf(config, "watch", ", ".join(paths))


def folder_arg(args, what, ext):
    if len(args) > 1 or any(a.startswith("-") for a in args):
        die_usage(f"{what} takes one folder, or none for the current one. Run: {CMD} {ext} --help")
    folder = os.path.abspath(os.path.expanduser(args[0])) if args else os.getcwd()
    if not os.path.isdir(folder):
        die_usage(f"{args[0] if args else folder} isn't a folder. Do: name a clone, or run it inside one")
    return folder


# What redirects git to another repository, another configuration or other objects: not passed to it.
# wiki.sh strips the same, and wiki-github keeps a copy: change them together.
GIT_STRIP = ("GIT_DIR", "GIT_WORK_TREE", "GIT_IMPLICIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR", "GIT_PREFIX",
             "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_QUARANTINE_PATH", "GIT_NAMESPACE",
             "GIT_CONFIG_COUNT", "GIT_CONFIG_PARAMETERS", "GIT_CONFIG", "GIT_CONFIG_SYSTEM", "GIT_REPLACE_REF_BASE",
             "GIT_GRAFT_FILE", "GIT_SHALLOW_FILE", "GIT_EXEC_PATH", "GIT_TEMPLATE_DIR")
# What every git these extensions run is given, in place of the configuration the environment held: a folder
# that only looks like a bare repository (HEAD, objects/ and refs/) is never read as one unless it is named.
# The environment's other entries are not kept: one such as core.fsmonitor or core.sshCommand makes git run a
# command, and nothing these extensions ask of git needs one.
GIT_SAFE = {"GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "safe.bareRepository", "GIT_CONFIG_VALUE_0": "explicit"}


def git_env():
    env = {k: v for k, v in os.environ.items()
           if k not in GIT_STRIP and not k.startswith(("GIT_CONFIG_KEY_", "GIT_CONFIG_VALUE_"))}
    env.update(GIT_SAFE)
    env["GIT_TERMINAL_PROMPT"] = "0"
    return env


def git(folder, *args, env=None):
    """A line from a local git command, or nothing. Never a failure, never a question."""
    env = dict(git_env() if env is None else env)
    env["GIT_TERMINAL_PROMPT"] = "0"
    try:
        r = subprocess.run(["git", "-C", folder] + list(args), capture_output=True, timeout=15, stdin=subprocess.DEVNULL, env=env)
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return r.stdout.decode("utf-8", "replace").strip() if r.returncode == 0 else ""


def clone_top(folder, env=None):
    """The top of the git work tree a folder is in, as a real path, or nothing."""
    top = git(folder, "rev-parse", "--show-toplevel", env=env)
    return os.path.realpath(top) if top else ""


def common_dir(folder):
    """The git folder a clone's work trees share, as a real path, or nothing."""
    d = git(folder, "rev-parse", "--git-common-dir") if os.path.isdir(folder) else ""
    return os.path.realpath(os.path.join(folder, d)) if d else ""


def watches(folders, args):
    """--wiki-watches <folder>: exit 0 when one of the watched folders is this folder's clone, or a work tree of it, and 1
    when none is. It reads the settings file and asks git, nothing else."""
    if len(args) != 1:
        return 2
    mine = common_dir(args[0])
    if not mine:
        return 1
    return 0 if any(common_dir(f) == mine for f in folders) else 1


# ---- the failing log, its excerpt, its signature ----------------------------------------------------

ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b[@-Z\\-_]")
STAMP = re.compile(r"^\ufeff?\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?Z ?")
ERRORISH = re.compile(r"(?i)error|fail|fatal|exception|panic|traceback|not ok|\u2717")
# A line that is a failure's own first line, as test runners and compilers write one. It
# leads the excerpt and the signature, ahead of a line that only has "fail" somewhere in it.
STRONG = re.compile(r"^\s*(?:FAIL(?:ED|URE)?\b|not ok\b|\u2717|(?:[\w./-]+:)?\s?(?:fatal |syntax )?[Ee]rror\b[: ]|ERROR\b|E   |panic:|fatal:|Traceback \(most recent call last\)|--- FAIL|AssertionError|Exception\b)")
# What a runner says after any failure at all: true, and no help in telling one from another.
GENERIC = re.compile(r"^##\[error\]Process completed with exit code \d+\.?$")
AROUND_BEFORE, AROUND_AFTER, TAIL_LINES, STRONG_MAX = 3, 14, 30, 6
TIME = re.compile(r"\b\d{4}-\d\d-\d\d[T ]\d\d:\d\d:\d\d(?:\.\d+)?(?:Z|[+-]\d\d:?\d\d)?|\b\d{1,2}:\d\d:\d\d(?:\.\d+)?\b")
TMPPATH = re.compile(r"(?:/private)?/(?:tmp|var/folders|var/tmp)/[^\s:'\"),]*|/[^\s:'\"),]*/_temp/[^\s:'\"),]*")
HEX = re.compile(r"\b0x[0-9a-fA-F]+\b|\b(?=[0-9a-fA-F]*\d)[0-9a-fA-F]{7,}\b")
DURATION = re.compile(r"\b\d+(?:\.\d+)?\s?(?:ms|\u00b5s|us|ns|sec|secs|seconds|min|s|m|h)\b")
BIGNUM = re.compile(r"\b\d{4,}\b")


def clean_keep(text):
    """Like clean, but keeps the spaces inside the line, which a log's indentation needs."""
    out = []
    for c in text:
        cat = unicodedata.category(c)
        if c == "\t":
            out.append("    ")
        elif c in SEPARATORS or cat[0] == "C" or cat in ("Zl", "Zp"):
            continue
        else:
            out.append(c)
    return "".join(out)


def tidy(line):
    """One line of a log with the escape codes, the timestamp and other control characters gone."""
    line = STAMP.sub("", ANSI.sub("", line))
    return clean_keep(line).rstrip()


def cut_bytes(text, limit):
    b = text.encode("utf-8")
    return text if len(b) <= limit else b[:limit].decode("utf-8", "ignore").rstrip()


def log_lines(raw, noise=None):
    """The lines of a log, as bytes, as text: what `noise` (a pattern for a system's own markers) matches is
    taken out first, a carriage return, which redraws a line, keeps only what was drawn last, and then
    tidy() takes the escape codes and the rest."""
    text = raw.decode("utf-8", "replace").replace("\r\n", "\n")
    if callable(noise):
        text = noise(text)
    elif noise is not None:
        text = noise.sub("", text)
    lines = []
    for line in text.split("\n"):
        parts = line.split("\r")
        if len(parts) > 1:
            parts = [p for p in parts if p.strip()]
        lines.append(parts[-1] if parts else "")
    return lines


def excerpt_lines(raw):
    """The lines of a log, already chosen, as the excerpt: tidied, cut around the first failures when long,
    and at most KEEP_BYTES. When the bytes are too many, the lines around the failures stay and the tail of the
    log gives way first, oldest line first; only a tail that is gone lets the oldest lines go."""
    lines = [tidy(r) for r in raw]
    while lines and not lines[-1]:
        lines.pop()
    lines, tail = _around(lines)

    def size():
        return sum(len(l.encode("utf-8")) + 1 for l in lines)
    while len(lines) > 1 and size() > KEEP_BYTES:
        if tail > 0:
            del lines[len(lines) - tail]
            tail -= 1
            if tail == 0 and lines and lines[-1] == "[...]":
                lines.pop()
        else:
            lines.pop(0)
    if lines and size() > KEEP_BYTES:
        lines = [lines[-1].encode("utf-8")[-(KEEP_BYTES - 1):].decode("utf-8", "ignore")]
    return lines


def around_failures(lines):
    """The lines worth keeping of a long log: a few around each of the first failures, and
    the end. A log's last lines alone often hold the summary and miss what failed."""
    return _around(lines)[0]


def _around(lines):
    """(the lines worth keeping, how many of the last of them are the tail: what comes after the last failure's lines)."""
    if len(lines) <= KEEP_LINES:
        return lines, len(lines)
    keep = set(range(max(0, len(lines) - TAIL_LINES), len(lines)))
    strong = [i for i, l in enumerate(lines) if STRONG.search(l) and not GENERIC.search(l.strip())][:STRONG_MAX]
    snippet_end = 0
    for i in strong:
        keep.update(range(max(0, i - AROUND_BEFORE), min(len(lines), i + AROUND_AFTER + 1)))
        snippet_end = max(snippet_end, min(len(lines), i + AROUND_AFTER + 1))
    if not strong:
        return lines[-KEEP_LINES:], KEEP_LINES
    out, last = [], None
    chosen = sorted(keep)[:KEEP_LINES]
    for i in chosen:
        if last is not None and i != last + 1:
            out.append("[...]")
        out.append(lines[i])
        last = i
    return out, sum(1 for i in chosen if i >= snippet_end)


def signature_of(lines, step, what="step", generic=None):
    """The first line that looks like the error, with the noise that changes from run to run
    folded away, or the last line that isn't empty, cut to a length. generic: a pattern for what the
    system says after any failure at all, which is no help, besides GENERIC."""
    def plain(l):
        return not GENERIC.search(l.strip()) and not (generic and generic.search(l.strip()))
    chosen = next((l for l in lines if STRONG.search(l) and plain(l)), "")
    if not chosen:
        chosen = next((l for l in lines if ERRORISH.search(l) and plain(l)), "")
    if not chosen:
        chosen = next((l for l in reversed(lines) if l.strip() and plain(l)), "")
    if not chosen:
        chosen = next((l for l in reversed(lines) if l.strip()), "")
    s = TIME.sub("<time>", chosen.strip())
    s = TMPPATH.sub("<tmp>", s)
    s = HEX.sub("<hex>", s)
    s = DURATION.sub("<dur>", s)
    s = BIGNUM.sub("<n>", s)
    s = " ".join(s.split())[:SIGNATURE_CHARS].rstrip()
    return s or clean(f'{what} "{step}" failed', SIGNATURE_CHARS)


def safe_part(text):
    s = re.sub(r"[^A-Za-z0-9._-]", "_", text)
    return ("_" + s) if s.startswith(".") else s


def under(path, folder):
    path, folder = os.path.realpath(path), os.path.realpath(folder)
    return path == folder or path.startswith(folder.rstrip(os.sep) + os.sep)


def private_dir(path):
    os.makedirs(path, mode=0o700, exist_ok=True)
    os.chmod(path, 0o700)


def prune_logs(log_dir):
    """Excerpts older than a week go."""
    cutoff = time.time() - KEEP_DAYS * 86400
    for root, dirs, files in os.walk(log_dir, topdown=False):
        for f in files:
            p = os.path.join(root, f)
            try:
                if f.endswith(".txt") and os.lstat(p).st_mtime < cutoff:
                    os.unlink(p)
            except OSError:
                pass
        if root != log_dir:
            try:
                os.rmdir(root)
            except OSError:
                pass


def save_excerpt(state_dir, log_dir, repo_key, filename, lines):
    """Write the excerpt where only this user reads it, and say where. Never in a wiki."""
    wikis = os.environ.get("WIKIS_DIR")
    if wikis and under(log_dir, wikis):
        die(f"the log folder {log_dir} is inside the wikis at {wikis}, and a log never goes in a wiki. Do: set XDG_STATE_HOME to a folder outside it")
    folder = os.path.join(log_dir, safe_part(repo_key))
    try:
        for d in (state_dir, log_dir, folder):
            private_dir(d)
        path = os.path.join(folder, filename)
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | getattr(os, "O_NOFOLLOW", 0), 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + ("\n" if lines else ""))
        os.chmod(path, 0o600)
        prune_logs(log_dir)
    except OSError as e:
        print(f"couldn't save the log excerpt in {folder}: {e.strerror or e}", file=sys.stderr)
        return ""
    return path


# ---- llm-wiki's own commands ------------------------------------------------------------------------

def run_llm_wiki(*args, **kw):
    """(what llm-wiki's own command did, why it couldn't be run): run as the contract says, through $LLM_WIKI. The
    answer is read as UTF-8 with what isn't replaced, so a note that holds a stray byte can't end the run."""
    exe = os.environ.get("LLM_WIKI")
    if not exe:
        return None, "LLM_WIKI isn't set"
    timeout = kw.pop("timeout", 120)
    try:
        return subprocess.run([exe] + list(args), capture_output=True, text=True, encoding="utf-8", errors="replace",
                              timeout=timeout, stdin=subprocess.DEVNULL, **kw), ""
    except subprocess.TimeoutExpired:
        return None, f"it didn't answer within {timeout} seconds"
    except OSError as e:
        return None, f"it couldn't be run: {e.strerror or e}"


def llm_wiki(*args, **kw):
    """Run llm-wiki's own command, as the contract says: through $LLM_WIKI. None when it couldn't be run."""
    return run_llm_wiki(*args, **kw)[0]


# ---- which collection a wiki is in ------------------------------------------------------------------
# A machine can have several collections, folders of wikis, and every one has a wiki called global. A tick
# starts in whichever collection the session or the schedule was in, so the wiki that covers a repository
# is asked of every collection, and a call about a wiki of another collection runs with WIKIS_DIR set to
# that collection's folder. llm-wiki hands every call LLM_WIKI_COLLECTION and LLM_WIKI_COLLECTIONS, worked
# out from the collections file each time. wiki-confluence keeps the same rules. A run in a folder that no
# collection names (a sandbox, a test, a one-off WIKIS_DIR) asks that folder alone.

COLLECTION_OK = re.compile(r"[A-Za-z0-9_-]+\Z")
# What llm-wiki calls a folder that no collection is listed for, such as a test's WIKIS_DIR.
UNNAMED = "(unnamed)"
DEFAULT = "default"


def here_collection():
    """The name of the collection this run is in, as llm-wiki hands it over."""
    return os.environ.get("LLM_WIKI_COLLECTION") or UNNAMED


def collections():
    """[(name, folder)]: the collections a question about the wikis can go to, the one this run is in first, at
    the folder in WIKIS_DIR, then the others as LLM_WIKI_COLLECTIONS lists them. Run in a folder no collection
    names, by an older llm-wiki or by hand, only that one. A line whose name no collection can have is left out."""
    here, folder = here_collection(), os.environ.get("WIKIS_DIR", "")
    out = [(here, folder)]
    if not COLLECTION_OK.match(here):
        return out
    real = os.path.realpath(folder) if folder else ""
    for line in os.environ.get("LLM_WIKI_COLLECTIONS", "").split("\n"):
        name, tab, path = line.partition("\t")
        if not tab or not path or not COLLECTION_OK.match(name) or any(n == name for n, _ in out):
            continue
        # One folder is one collection: this run's, under another name, is not asked twice.
        if real and os.path.realpath(path) == real:
            continue
        out.append((name, path))
    return out


def in_collection(coll, folder):
    """What a call into llm-wiki about a wiki of that collection runs with: (environment, folder to run in).
    For the collection this run is in, both as they are, so a machine with one collection sees no change."""
    if coll == here_collection():
        return None, os.environ.get("WIKIS_DIR") or os.getcwd()
    env = dict(os.environ)
    env["WIKIS_DIR"] = folder
    return env, folder


def asked():
    """The collections a question about the wikis goes to: this run's, and each other one whose folder is there."""
    return [(c, f) for i, (c, f) in enumerate(collections()) if i == 0 or os.path.isdir(f)]


def qualified(coll):
    """Whether a command about a wiki of that collection needs --collection to work from any folder: for every
    named collection but the default one, and for the default one too when another collection is there. Never
    for a folder no collection names, which no --collection can pick."""
    return bool(COLLECTION_OK.match(coll)) and (coll != DEFAULT or len(asked()) > 1)


def label(coll, wiki):
    """A wiki as a person reads it: collection/wiki where a command needs --collection for it, else its name.
    As it is on a machine with one collection."""
    return f"{coll}/{wiki}" if qualified(coll) else wiki


def wiki_cmd(coll, *words):
    """A wiki command to print, which does the same from any folder: with --collection where it needs one."""
    return " ".join([CMD] + (["--collection", coll] if qualified(coll) else []) + list(words))


def ask(coll, folder, *args):
    """(what llm-wiki's own command did in that collection, why it couldn't be run)."""
    env, _ = in_collection(coll, folder)
    return run_llm_wiki(*args) if env is None else run_llm_wiki(*args, env=env)


def which_in(coll, folder, cover):
    """What that collection says covers the name: ("wiki", its name), ("none", "") when `wiki which` there says
    no wiki covers it, or ("error", why) when the answer couldn't be had: no answer in time, or a failure, such as
    a folder it can't read. `wiki which` exits 1 for both of the last two, so "none" is only its own words."""
    r, why = ask(coll, folder, "which", cover)
    if r is None:
        return "error", why
    out = r.stdout.strip()
    if r.returncode == 0 and out:
        return "wiki", os.path.basename(out.rstrip("/"))
    if r.returncode == 1 and f"no wiki covers {cover}" in r.stderr.splitlines():
        return "none", ""
    return "error", first_line(r.stderr) or f"it ended with exit {r.returncode} and said nothing"


def covering(cover):
    """([(collection, folder, wiki)], [(collection, why)]): each collection's wiki that covers the name, as `wiki
    which` there says, this run's collection first, and each collection that couldn't be asked."""
    found, failed = [], []
    for coll, folder in asked():
        what, it = which_in(coll, folder, cover)
        if what == "wiki":
            found.append((coll, folder, it))
        elif what == "error":
            failed.append((coll, it))
    return found, failed


def parse_find(out, mark="no mentions"):
    """The first page or note `wiki find` names, as "<wiki>: <path>", or nothing."""
    wiki = ""
    for line in out.splitlines():
        if line.startswith(mark):
            return ""
        if line and not line[0].isspace() and line.endswith(":"):
            wiki = line[:-1]
            continue
        m = re.match(r"^ {4}(\S+\.md):", line) or re.search(r"\]\(([^)\s]+)\)", line)
        if wiki and m:
            return f"{wiki}: {clean(m.group(1), 200)}"
        if wiki and line.startswith("  ") and not line.strip().endswith(":") and not line.strip().startswith("also in"):
            return f"{wiki}: index.md"
    return ""


def known_in_wikis(signature):
    """Whether any wiki already holds this signature: "<wiki>: <page>", "" for none, None for not asked."""
    query = signature.lstrip("- ").strip()
    if not query:
        return None
    # Every collection, this run's first: a note saved in another collection's wiki is known too.
    answered = False
    for coll, folder in asked():
        env, _ = in_collection(coll, folder)
        r = llm_wiki("find", query) if env is None else llm_wiki("find", query, env=env)
        if r is None or r.returncode != 0:
            continue
        answered = True
        hit = parse_find(r.stdout)
        if hit:
            wiki, _, path = hit.partition(": ")
            return f"{label(coll, wiki)}: {path}"
    return "" if answered else None


# ---- the state file --------------------------------------------------------------------------------

def load_state(state_file):
    try:
        with open(state_file, encoding="utf-8") as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError, RecursionError):
        return {}


@contextlib.contextmanager
def state_lock(state_dir, lock_file):
    """One writer of the state file at a time. Yields whether the lock is held: it isn't when the lock file can't
    be opened or locked within ten seconds. A caller that decides something from the state does nothing when it isn't held."""
    fd = None
    held = False
    try:
        private_dir(state_dir)
        fd = os.open(lock_file, os.O_WRONLY | os.O_CREAT, 0o600)
        if fcntl:
            deadline = time.time() + 10
            while True:
                try:
                    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    held = True
                    break
                except OSError:
                    if time.time() > deadline:
                        break
                    time.sleep(0.05)
    except OSError:
        pass
    try:
        yield held
    finally:
        if fd is not None:
            os.close(fd)


def write_state(state_dir, state_file, state):
    try:
        private_dir(state_dir)
        fd, tmp = tempfile.mkstemp(dir=state_dir, prefix=".state-")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(state, f, indent=1, sort_keys=True)
        os.chmod(tmp, 0o600)
        os.replace(tmp, state_file)
    except OSError as e:
        print(f"couldn't save {state_file}: {e.strerror or e}")


def record_workflow(state_dir, state_file, lock_file, repo, key, entry):
    """Set one entry of a project's workflows in the state file: under the lock, reading the file fresh inside it, so
    another writer's entries are kept. False, with a line, and nothing written, when the lock can't be taken."""
    with state_lock(state_dir, lock_file) as held:
        if not held:
            print(f"couldn't lock {state_file}, so nothing was written for {repo}.")
            return False
        state = load_state(state_file)
        repos = state.get("repos")
        if not isinstance(repos, dict):
            repos = state["repos"] = {}
        book = repos.get(repo)
        if not isinstance(book, dict):
            book = repos[repo] = {}
        flows = book.get("workflows")
        if not isinstance(flows, dict):
            flows = book["workflows"] = {}
        flows[key] = entry
        write_state(state_dir, state_file, state)
        return True


def loads(text):
    """json.loads, or None for what can't be read, as JSON that is nested too deep is."""
    try:
        return json.loads(text)
    except (ValueError, RecursionError):
        return None


# ---- what a new failure leaves: a notice for a session, a desktop notification -------------------------

def cap(text, limit=80):
    """Text that may be long, cut to limit characters with ... where it was cut."""
    text = clean(text, 100000)
    return text if len(text) <= limit else text[:limit - 3] + "..."


def notice_text(prefix, inner, suffix, limit=590):
    """A notice's words around text that came from outside or from an agent: that text sits inside double quotes (a double
    quote in it becomes a single one), so the next session can tell the program's words from quoted ones. It is cut by
    bytes, with the quotes kept, so the whole is at most `limit` bytes. The fixed words never use up the limit: when
    prefix and suffix alone are too long the prefix gives way, and the suffix, which ends with where to look, is kept."""
    inner = clean(inner, 2000).replace('"', "'")
    prefix, suffix = str(prefix), str(suffix)
    if len(suffix.encode("utf-8")) > limit - 2:
        suffix = suffix.encode("utf-8")[-(limit - 2):].decode("utf-8", "ignore")
    if len(prefix.encode("utf-8")) + len(suffix.encode("utf-8")) + 2 > limit:
        prefix = cut_bytes(prefix, max(0, limit - 2 - len(suffix.encode("utf-8"))))
    room = limit - len((prefix + suffix).encode("utf-8")) - 2
    if len(inner.encode("utf-8")) > room:
        inner = (cut_bytes(inner, room - 3) + "...") if room >= 3 else ""
    return clean(prefix + '"' + inner + '"' + suffix, limit)


def put_notice(nid, folder, branch, text):
    """Leave one line for the next session in this repository on this branch."""
    r = llm_wiki("__notice", "put", nid, folder, branch, text)
    if r is None or r.returncode != 0:
        print(f"couldn't leave a notice for {folder}: {first_line((r.stderr if r else '') or 'no wiki command to ask')}")
        return False
    print(f"left a notice for {folder} on {branch}")
    return True


def notify_desktop(title, text):
    """A desktop notification for a run that started failing. Everything in it is from outside, so
    it is cleaned, cut, and handed to llm-wiki as two arguments, never joined into a command."""
    title = cut_bytes(clean(title, 80), 80)
    text = clean(text, 240)
    if text.startswith("-"):
        text = "failure: " + text
    text = cut_bytes(text, 240)
    r = llm_wiki("__notify", title, text)
    if r is None or r.returncode != 0:
        print(f"couldn't show a desktop notification: {first_line((r.stderr if r else '') or 'no wiki command to ask')}")


def clear_notice(nid):
    llm_wiki("__notice", "clear", nid)


def stale(created):
    """Whether a run began too long ago to be news. A run with no readable time is fresh."""
    try:
        then = datetime.datetime.strptime(created or "", "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
    except ValueError:
        return False
    return (datetime.datetime.now(datetime.timezone.utc) - then).days >= NOTICE_DAYS


# A note that no single wiki could take yet, because wikis in more than one collection cover the repository, is
# kept in the extension's own state folder, on this machine, and tried again at each tick until one wiki covers it.
HELD_FILE = "notes-held.json"
HELD_LOCK = "notes-held.lock"
HELD_MAX = 20


def unasked_words(repo, cover, failed):
    """The line for collections that couldn't be asked which wiki covers the name."""
    parts = []
    for coll, why in failed:
        where = f"the {coll} collection" if COLLECTION_OK.match(coll) else f"the wikis at {os.environ.get('WIKIS_DIR', '')}"
        parts.append(f"couldn't ask {where} which wiki covers {cover}: {clean(why, 200).rstrip('.')}")
    return (f"{repo}: " + "; ".join(parts) + ". No note was saved, and the next tick tries again. "
            f"Run: {wiki_cmd(failed[0][0], 'which', cover)} to see why")


def several_words(repo, cover, found):
    """The line for a name that wikis in more than one collection cover."""
    named = ", ".join(f"{c}/{w}" for c, _, w in found)
    listed = [f"{c}/{w}" for c, _, w in found if w != cover]
    fix = (f"{CMD} --collection <collection> uncover {cover} takes it out of one that lists it ({', '.join(listed)})" if listed
           else f"rename or move all but one of the wikis called {cover}")
    return (f"{repo}: wikis in {len(found)} collections cover {cover}: {named}, so no note was saved rather than guess which. "
            f"It is kept, and saved at a tick once one wiki covers it. Do: leave one of them covering it: {fix}")


def write_note(repo, coll, folder, wiki, what, lines, flaky):
    """Capture the note in that collection's wiki, then sync it there. True once the capture worked, whatever the
    sync did: a sync that fails is said, with the command that does it, and never makes the note be taken again."""
    exe = os.environ.get("LLM_WIKI")
    env, wikis_dir = in_collection(coll, folder)
    name = label(coll, wiki)
    slug = "ci-flaky" if flaky else "ci-fixed"
    try:
        # From the wikis' folder, so a note taken in a ticket's folder gets no Ticket: line of that ticket.
        c = subprocess.run([exe, "capture", wiki, slug], input="\n".join(lines) + "\n", text=True, encoding="utf-8",
                           errors="replace", capture_output=True, cwd=wikis_dir, env=env, timeout=120)
    except (OSError, subprocess.TimeoutExpired) as e:
        print(f"{repo}: couldn't save the note in {name}: {e}")
        return False
    if c.returncode != 0:
        print(f"{repo}: couldn't save the note in {name}: {first_line(c.stderr)}")
        return False
    try:
        s = subprocess.run([exe, "sync", wiki, "-m", f"{wiki}: CI failure {'was flaky' if flaky else 'fixed'}"],
                           capture_output=True, text=True, encoding="utf-8", errors="replace", env=env,
                           timeout=SYNC_SECONDS, stdin=subprocess.DEVNULL)
        synced = s.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        synced = False
    if not synced:
        print(f"{repo}: saved the note in {name}, but the sync failed. Run: {wiki_cmd(coll, 'sync', wiki)}")
    else:
        print(f"{repo}: noted in {name} that {what} " + ("was flaky." if flaky else "is fixed."))
    return True


def held_notes(path):
    book = load_state(path)
    notes = book.get("notes")
    return notes if isinstance(notes, dict) else {}


def hold_note(state_dir, entry):
    """Keep a note for a later tick. False, with a line, when it couldn't be kept."""
    path = os.path.join(state_dir, HELD_FILE)
    with state_lock(state_dir, os.path.join(state_dir, HELD_LOCK)) as held:
        if not held:
            print(f"{entry['repo']}: couldn't lock {path}, so the note wasn't kept for a later tick.")
            return False
        notes = held_notes(path)
        nid = hashlib.sha256("\n".join(entry["lines"]).encode("utf-8", "replace")).hexdigest()[:16]
        notes[nid] = entry
        while len(notes) > HELD_MAX:
            old = min(notes, key=lambda k: str((notes[k] or {}).get("since", "")) if isinstance(notes[k], dict) else "")
            gone = notes[old] if isinstance(notes[old], dict) else {}
            print(f"{clean(gone.get('repo', '?'), 100)}: more than {HELD_MAX} notes were waiting for one wiki to cover "
                  f"their repository, so the oldest, kept since {clean(gone.get('since', '?'), 30)}, was let go.")
            del notes[old]
        write_state(state_dir, path, {"notes": notes})
    return True


def good_entry(e):
    return (isinstance(e, dict) and all(isinstance(e.get(k), str) for k in ("repo", "cover", "what", "since"))
            and isinstance(e.get("said", ""), str) and isinstance(e.get("lines"), list)
            and all(isinstance(l, str) for l in e["lines"]) and not e["cover"].startswith("-"))


def retry_held(state_dir):
    """At a tick: each kept note is saved once one wiki covers its repository. What still stops one is said when
    it first stops it and when that changes, not at every tick. True unless a save failed and should be tried again."""
    path = os.path.join(state_dir, HELD_FILE)
    if not os.path.exists(path) or not os.environ.get("LLM_WIKI"):
        return True
    ok = True
    with state_lock(state_dir, os.path.join(state_dir, HELD_LOCK)) as held:
        if not held:
            print(f"couldn't lock {path}, so the notes kept there wait for the next tick.")
            return False
        notes = held_notes(path)
        changed = False
        for nid, e in list(notes.items()):
            if not good_entry(e):
                del notes[nid]
                changed = True
                continue
            repo, cover = e["repo"], e["cover"]
            found, failed = covering(cover)
            if failed:
                answer, words = "unasked:" + ",".join(c for c, _ in failed), unasked_words(repo, cover, failed)
            elif len(found) == 1:
                coll, folder, wiki = found[0]
                if write_note(repo, coll, folder, wiki, e["what"], e["lines"], bool(e.get("flaky"))):
                    del notes[nid]
                    changed = True
                else:
                    ok = False
                continue
            elif found:
                answer, words = "several:" + ",".join(f"{c}/{w}" for c, _, w in found), several_words(repo, cover, found)
            else:
                answer = "none"
                words = (f"{repo}: no wiki covers {cover} now, so the note kept since {e['since']} still waits. "
                         f"Run: {CMD} --collection <collection> cover <wiki> {cover}")
            if answer != e.get("said"):
                print(words)
                e["said"] = answer
                changed = True
        if changed:
            write_state(state_dir, path, {"notes": notes})
    return ok


def save_note(folder, repo, cover, ext, what, body, flaky, state_dir=None):
    """The note about a failure that ended: saved with capture, then synced. True when it is saved, kept for a
    later tick, or when there is nothing to save it in; False when a save failed, or a collection couldn't be
    asked, and the failure should be tried again.
    repo is how the system names the project, cover what a wiki is asked to cover (the project's last name),
    ext the extension's name, what the failure's own words ("CI on main"), body the lines between the
    heading and the Ticket line, and state_dir the extension's own state folder, where a note is kept.
    The wiki is the one that covers cover in whichever collection it is in, and the capture and the sync run
    in that collection. Every collection has to answer: one that couldn't be asked could hold a second wiki
    that covers it. When wikis in two collections cover it, no note is saved in either: which one is meant is
    the user's to say, and a note in the other could reach a remote it was never meant for. The note is kept,
    and saved at a tick once one wiki covers it."""
    if not os.environ.get("LLM_WIKI"):
        print(f"{repo}: LLM_WIKI isn't set, so no note was saved. Run this as: {CMD} {ext}")
        return True
    word = "flaky" if flaky else "fixed"
    lines = [f"# CI {word}: {what} ({repo})", ""] + list(body) + ["", "Ticket: none"]
    found, failed = ([], []) if cover.startswith("-") else covering(cover)
    if failed:
        print(unasked_words(repo, cover, failed))
        return False
    if not found:
        colls = asked()
        where = "" if len(colls) < 2 else f" in any of the {len(colls)} collections ({', '.join(c for c, _ in colls)})"
        how = f"{CMD} cover <wiki> {cover}" if len(colls) < 2 else f"{CMD} --collection <collection> cover <wiki> {cover}"
        print(f"{repo}: no wiki covers {cover}{where}, so no note was saved. Run: {how}")
        return True
    if len(found) > 1:
        print(several_words(repo, cover, found))
        if state_dir:
            since = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")
            hold_note(state_dir, {"repo": repo, "cover": cover, "what": what, "flaky": bool(flaky), "lines": lines,
                                  "since": since, "said": "several:" + ",".join(f"{c}/{w}" for c, _, w in found)})
        return True
    coll, folder, wiki = found[0]
    return write_note(repo, coll, folder, wiki, what, lines, flaky)
