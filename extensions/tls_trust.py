"""The certificate authorities the user chose to trust, for llm-wiki's extensions that talk HTTPS themselves.

Not an extension: it has no extension header and no `wiki-` name, so llm-wiki never lists or runs it as one.
wiki-jira, wiki-confluence and wiki-jenkins import it from their own folder, and `wiki extensions certs` runs it.
Standard library only.

Why it exists: a company proxy signs every site's certificate again with the company's own authority. The
operating system knows that authority, so a browser, curl, gh and glab work. Python knows only its own list, so
it refuses. The user names the address once, at a terminal, sees the authority by name, and says yes. From then
on the extensions trust Python's list and what the user chose, and nothing else.

What it never does: trust anything without that yes; take a certificate from the server it is checking; send a
sign-in (a check is one request with no Authorization header); or turn verification off.
"""
import binascii
import datetime
import hashlib
import http.client
import os
import re
import ssl
import stat
import subprocess
import sys
import tempfile
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request

CMD = os.environ.get("LLM_WIKI_CMD", "wiki")
CONFIG_DIR = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "llm-wiki")
FILE = os.path.join(CONFIG_DIR, "trusted-certs.pem")
KEYCHAIN = "/Library/Keychains/System.keychain"
SECURITY = os.environ.get("SECURITY_BIN") or "/usr/bin/security"
PEM = re.compile(r"-----BEGIN CERTIFICATE-----[A-Za-z0-9+/=\s]+?-----END CERTIFICATE-----")
ADDED = re.compile(r"^# added (\d{4}-\d{2}-\d{2}) for ([A-Za-z0-9.:\[\]-]{1,260})$")
ORIGIN = re.compile(r"^https://(?:[A-Za-z0-9](?:[A-Za-z0-9.-]{0,251}[A-Za-z0-9])?|\[[0-9A-Fa-f:.]{2,45}\])(?::[0-9]{1,5})?$")
MAX_BYTES = 2000000
MAX_SAVED = 50
MAX_CANDIDATES = 60
PROBE_SECONDS = 10
OFFER_SECONDS = 120
# OpenSSL's codes for "the chain ends at an authority that isn't on the list": an issuer that can't be found, of a
# certificate the server sent (2) or of its own (20), a self-signed certificate (18), one in the chain (19), a first
# certificate that can't be checked (21).
UNKNOWN_ISSUER = (2, 18, 19, 20, 21)
USAGE = f"""Usage: {CMD} extensions certs
       {CMD} extensions certs <https://address> [--from <file.pem>]
       {CMD} extensions certs --remove

Behind a company proxy, the Jira, Confluence and Jenkins extensions can't check a site's certificate: the proxy
signs it with the company's own authority, which Python doesn't know.

  With nothing   list the authorities you chose to trust.
  <address>      check that address. If its certificate is signed by an authority in this Mac's System keychain
                 that Python doesn't know, show the authority and ask whether to trust it. A question for you,
                 at a terminal. --from reads the authorities from a .pem file instead of the keychain.
  --remove       forget every authority you chose.

They are kept in {os.path.join("~/.config/llm-wiki", os.path.basename(FILE))} and used by llm-wiki's extensions only."""


class Problem(Exception):
    """The saved file can't be used. The words say why and what to do."""


def style_on(fd=1):
    o = os.environ.get("LLM_WIKI_STYLE", "")
    if o in ("on", "off"):
        return o == "on"
    return os.isatty(fd) and not os.environ.get("NO_COLOR") and os.environ.get("TERM", "dumb") != "dumb"


def sgr(code, text, fd=1):
    return "\033[%sm%s\033[0m" % (code, text) if style_on(fd) else text


def typed(text, fd=1):
    return sgr("36", text, fd)


def bold(text):
    return sgr("1", text)


def ok_mark():
    return sgr("32", "✓") + " " if style_on() else "- "


def die(msg, code=1):
    sys.stderr.write(sgr("31", "error:", 2) + " " + msg + "\n")
    sys.exit(code)


def tilde(path):
    home = os.path.expanduser("~")
    return "~" + path[len(home):] if home != "/" and (path == home or path.startswith(home + os.sep)) else path


def clean(text, limit=80):
    """Text from a certificate or an error, fit to print: one line, nothing that isn't a visible character."""
    out = "".join(c if c == " " or unicodedata.category(c)[0] not in "CZ" else " " for c in str(text))
    out = " ".join(out.split())
    return out[:limit] + ("…" if len(out) > limit else "")


def pems_in(text):
    """Each certificate in a text, as PEM written one way, without repeats. What isn't base64 is passed over."""
    out, seen = [], set()
    for m in PEM.finditer(text):
        try:
            der = ssl.PEM_cert_to_DER_cert(m.group())
        except (ValueError, binascii.Error):
            continue
        if der and der not in seen:
            seen.add(der)
            out.append(ssl.DER_cert_to_PEM_cert(der))
    return out


def about(pem):
    """What an authority's certificate says of itself, or None for one that is not a certificate authority.
    Only an authority is ever offered: get_ca_certs leaves out a certificate that can't sign others."""
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    try:
        ctx.load_verify_locations(cadata=pem)
        found = ctx.get_ca_certs()
    except (ssl.SSLError, ValueError):
        return None
    if len(found) != 1:
        return None

    def part(field, key):
        for rdn in found[0].get(field, ()):
            for k, v in rdn:
                if k == key:
                    return clean(v)
        return ""

    try:
        ends = datetime.datetime.fromtimestamp(ssl.cert_time_to_seconds(found[0]["notAfter"]), datetime.timezone.utc).strftime("%Y-%m-%d")
    except (KeyError, ValueError):
        ends = "unknown"
    print_ = hashlib.sha256(ssl.PEM_cert_to_DER_cert(pem)).hexdigest().upper()
    return {
        "name": part("subject", "commonName") or part("subject", "organizationName") or part("subject", "organizationalUnitName") or "(no name)",
        "org": part("subject", "organizationName"),
        "issuer": part("issuer", "commonName") or part("issuer", "organizationName"),
        "ends": ends,
        "print": " ".join(print_[i:i + 2] for i in range(0, len(print_), 2)),
    }


def saved():
    """[(pem, "added <day> for <host>" or "")] from the saved file. Nothing when there is no file. The file is
    used only when it is a plain file of the user's own that nobody else can write: anything else is a Problem."""
    fix = f"Do: look at it, then run {CMD} extensions certs --remove and add what you need again"
    try:
        fd = os.open(FILE, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0))
    except FileNotFoundError:
        return []
    except OSError as e:
        raise Problem(f"{tilde(FILE)}, the certificate authorities you chose, can't be opened ({clean(e.strerror or e)}), so nothing was sent. {fix}")
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            raise Problem(f"{tilde(FILE)} isn't a plain file, so it isn't used and nothing was sent. {fix}")
        if hasattr(os, "geteuid") and (st.st_uid != os.geteuid() or st.st_mode & 0o022):
            raise Problem(f"{tilde(FILE)} can be written by someone else, so it isn't used and nothing was sent. {fix}")
        if st.st_size > MAX_BYTES:
            raise Problem(f"{tilde(FILE)} is too big to be what llm-wiki wrote, so it isn't used and nothing was sent. {fix}")
        with os.fdopen(fd, "rb") as f:
            fd = -1
            text = f.read(MAX_BYTES + 1).decode("ascii", "replace")
    finally:
        if fd >= 0:
            os.close(fd)
    # Only what llm-wiki writes there: comments, and certificates of authorities. Anything else, and none of it is used.
    odd = Problem(f"{tilde(FILE)} holds something that isn't a certificate authority, so it isn't used and nothing was sent. {fix}")
    if len(text) > MAX_BYTES or any(l.strip() and not l.startswith("#") for l in PEM.sub("", text).split("\n")):
        raise odd
    out, seen = [], set()
    for m in PEM.finditer(text):
        got = pems_in(m.group())
        if not got or not about(got[0]):
            raise odd
        if got[0] in seen:
            continue
        seen.add(got[0])
        before = text[:m.start()].rstrip("\n").rsplit("\n", 1)[-1]
        note = ADDED.match(before)
        out.append((got[0], f"added {note.group(1)} for {note.group(2)}" if note else ""))
    if len(out) > MAX_SAVED:
        raise Problem(f"{tilde(FILE)} holds more than {MAX_SAVED} certificates, so it isn't used and nothing was sent. {fix}")
    return out


def context(extra=()):
    """What an extension checks a server against: Python's own list, and what the user chose. Never less strict."""
    try:
        ctx = ssl.create_default_context()
    except (ssl.SSLError, OSError, ValueError) as e:
        raise Problem(f"Python's own list of certificate authorities can't be loaded ({clean(e, 120)}), so nothing was sent. "
                      "Do: check what SSL_CERT_FILE and SSL_CERT_DIR name, if they are set")
    pems = [p for p, _ in saved()] + list(extra)
    if pems:
        try:
            ctx.load_verify_locations(cadata="\n".join(pems))
        except (ssl.SSLError, ValueError):
            raise Problem(f"{tilde(FILE)} holds something that isn't a certificate, so nothing was sent. "
                          f"Do: run {CMD} extensions certs --remove and add what you need again")
    return ctx


def https_handler():
    """For urllib's build_opener. Raises Problem when the saved file can't be used."""
    return urllib.request.HTTPSHandler(context=context())


def verify_failure(e):
    """The certificate failure inside an error from urllib, or None when it failed for another reason."""
    for x in (e, getattr(e, "reason", None)):
        if isinstance(x, ssl.SSLCertVerificationError):
            return x
    return None


def origin_of(url):
    """https://host[:port] of an address, or "" when it isn't an https address this can name in a command."""
    try:
        u = urllib.parse.urlsplit(url)
        port = u.port
    except ValueError:
        return ""
    if u.scheme != "https" or not u.hostname or u.username is not None or u.password is not None:
        return ""
    host = f"[{u.hostname}]" if ":" in u.hostname else u.hostname
    o = f"https://{host}" + (f":{port}" if port and port != 443 else "")
    return o if ORIGIN.match(o) else ""


def hint(e, url):
    """What to say when a request failed on the server's certificate, or None when it failed on something else.
    It names the command only for the failure that command fixes."""
    v = verify_failure(e)
    if v is None:
        return None
    o = origin_of(url)
    where = o or "the server"
    if getattr(v, "verify_code", 0) in UNKNOWN_ISSUER:
        return (f"can't check the certificate of {where}: it is signed by an authority Python doesn't know, as it is behind a company proxy. "
                f"Run, in a terminal: {CMD} extensions certs {o or '<its https:// address>'}")
    return (f"the certificate of {where} was refused: {clean(getattr(v, 'verify_message', '') or v, 120)}. "
            "Do: check the address, and that this machine's clock is right")


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def probe(origin, ctx):
    """One request to an address, with no sign-in. ("ok", None) when its certificate was accepted, whatever the
    server then answered; ("verify", the failure) when it wasn't; ("other", the error) for anything else."""
    opener = urllib.request.build_opener(urllib.request.HTTPSHandler(context=ctx), NoRedirect())
    req = urllib.request.Request(origin + "/", headers={"User-Agent": "llm-wiki", "Accept": "*/*"}, method="GET")
    try:
        opener.open(req, timeout=PROBE_SECONDS).close()
    except urllib.error.HTTPError as e:
        e.close()
    except (urllib.error.URLError, http.client.HTTPException, TimeoutError, OSError, ValueError) as e:
        v = verify_failure(e)
        return ("verify", v) if v is not None else ("other", e)
    return ("ok", None)


def keychain_pems():
    """The certificates in this Mac's System keychain, which only an administrator can add to."""
    try:
        out = subprocess.run([SECURITY, "find-certificate", "-a", "-p", KEYCHAIN], stdin=subprocess.DEVNULL,
                             capture_output=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if out.returncode != 0 or len(out.stdout) > MAX_BYTES * 5:
        return None
    return pems_in(out.stdout.decode("ascii", "replace"))


def write_saved(entries):
    """Write the whole file, whole or not at all, readable and writable by the user only."""
    os.makedirs(CONFIG_DIR, mode=0o700, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".trusted-certs.", dir=CONFIG_DIR)
    try:
        with os.fdopen(fd, "w", encoding="ascii") as f:
            os.fchmod(f.fileno(), 0o600)
            f.write("# Certificate authorities you chose to trust, for llm-wiki's extensions only.\n")
            f.write("# Written by: wiki extensions certs. Don't edit it: run that to add, list or remove.\n")
            for pem, note in entries:
                f.write(f"\n# {note}\n" if note else "\n")
                f.write(pem if pem.endswith("\n") else pem + "\n")
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, FILE)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def show(info, note=""):
    print("  " + bold(info["name"]))
    if info["org"] and info["org"] != info["name"]:
        print(f"    from     {info['org']}")
    if info["issuer"] and info["issuer"] != info["name"]:
        print(f"    signed by {info['issuer']}")
    print(f"    expires  {info['ends']}")
    print(f"    SHA-256  {info['print']}")
    if note:
        print(f"    {note}")


def cmd_list():
    try:
        have = saved()
    except Problem as e:
        die(str(e))
    if not have:
        print("No certificate authority is trusted beyond Python's own list.")
        print(f"If an extension can't check a site's certificate, it names the command to run: {CMD} extensions certs <https://address>")
        return 0
    print(f"llm-wiki's extensions trust Python's own list and {len(have)} you chose:")
    for pem, note in have:
        print()
        info = about(pem)
        if info:
            show(info, note)
        else:
            print("  (not a certificate authority: it is never used to sign in anywhere)" + (f"  {note}" if note else ""))
    print()
    print(f"They are in {tilde(FILE)}. To forget them all: {typed(CMD + ' extensions certs --remove')}")
    return 0


def cmd_remove():
    try:
        n = len(saved())
    except Problem:
        n = -1
    try:
        os.unlink(FILE)
    except FileNotFoundError:
        print("Nothing to remove: no certificate authority was trusted beyond Python's own list.")
        return 0
    except OSError as e:
        die(f"{tilde(FILE)} can't be removed ({clean(e.strerror or e)}). Do: remove it by hand")
    print(ok_mark() + ("Removed " + (f"{n} certificate authorit{'y' if n == 1 else 'ies'}" if n >= 0 else tilde(FILE))
                       + ". The extensions trust only Python's own list again."))
    return 0


def cmd_offer(address, source):
    o = "" if any(unicodedata.category(c)[0] in "CZ" for c in address) else origin_of(address)
    if not o:
        die(f"{clean(address)} isn't an https:// address this can check. Do: give the site's address, such as https://jira.example.com", 2)
    host = urllib.parse.urlsplit(o).netloc
    try:
        have = saved()
        base = context()
    except Problem as e:
        die(str(e))
    state, err = probe(o, base)
    if state == "ok":
        print(ok_mark() + f"{o} already checks out. Nothing to add.")
        return 0
    if state == "other":
        die(f"can't reach {o}: {clean(getattr(err, 'reason', err), 120)}. Do: check the network and the address")
    if getattr(err, "verify_code", 0) not in UNKNOWN_ISSUER:
        die(hint(err, o))
    if not (sys.stdin.isatty() and sys.stdout.isatty()):
        die(f"{o} is signed by an authority Python doesn't know. Trusting one is a question for a person, at a terminal, and an agent never answers it. "
            f"Do: run it yourself, in a terminal: {CMD} extensions certs {o}")

    if source:
        try:
            fd = os.open(source, os.O_RDONLY | getattr(os, "O_NONBLOCK", 0))
            with os.fdopen(fd, "rb") as f:
                st = os.fstat(f.fileno())
                if not stat.S_ISREG(st.st_mode) or st.st_size > MAX_BYTES * 5:
                    die(f"{clean(source)} isn't a .pem file of a size this reads. Do: give a .pem file that holds your company's root certificate")
                found = pems_in(f.read(MAX_BYTES * 5).decode("ascii", "replace"))
        except OSError as e:
            die(f"{clean(source)} can't be read ({clean(e.strerror or e)}). Do: give a .pem file that holds your company's root certificate")
        place = "the file " + clean(source)
    elif (os.environ.get("LLM_WIKI_TEST_OS") or sys.platform) == "darwin":  # LLM_WIKI_TEST_OS: the tests see both answers
        found = keychain_pems()
        # Said as it is: with SECURITY_BIN set, what was read is whatever that command printed.
        place = "this Mac's System keychain" if SECURITY == "/usr/bin/security" else "what the command in SECURITY_BIN printed"
        if found is None:
            die(f"the System keychain can't be read. Do: get your company's root certificate as a .pem file, then run {CMD} extensions certs {o} --from <file.pem>")
    else:
        die(f"{o} is signed by an authority Python doesn't know. "
            f"Do: get your company's root certificate as a .pem file, then run {CMD} extensions certs {o} --from <file.pem>")

    known = {p for p, _ in have}
    cands = [p for p in found if p not in known and about(p)]
    more = len(cands) > MAX_CANDIDATES
    cands = cands[:MAX_CANDIDATES]
    nothing = (f"none of the {'first ' if more else ''}{len(cands)} certificate authorit{'y' if len(cands) == 1 else 'ies'} in {place} signs {o}, so there is nothing to offer. "
               f"Do: ask whoever runs your network for its root certificate as a .pem file, then run {CMD} extensions certs {o} --from <file.pem>")

    deadline = time.time() + OFFER_SECONDS

    def works(pems):
        if time.time() > deadline:
            die(f"checking {o} took more than {OFFER_SECONDS} seconds, so nothing was offered. Do: check the network, then run it again")
        try:
            state, err = probe(o, context(pems))
        except Problem as e:
            die(str(e))
        if state == "other":
            die(f"can't reach {o} any more: {clean(getattr(err, 'reason', err), 120)}. Do: check the network, then run it again")
        return state == "ok"

    if not cands or not works(cands):
        die(nothing)
    # The fewest that are needed: drop each in turn, and keep it only when the check fails without it.
    need = list(cands)
    for p in cands:
        rest = [x for x in need if x != p]
        if works(rest):
            need = rest
    if not need or len(need) > 3:
        die(nothing)

    one = len(need) == 1
    print(f"{o} is signed by {'an authority' if one else str(len(need)) + ' authorities'} that Python doesn't know, found in {place}:")
    print()
    for p in need:
        show(about(p))
        print()
    print("Whoever holds " + ("it" if one else "them") + " can read and change what llm-wiki's Jira, Confluence and Jenkins extensions send")
    print("to any address, your API tokens included. A company proxy already does that for your browser.")
    print("Say yes only if you know the name" + ("" if one else "s") + ".")
    sys.stdout.write(bold(f"Trust {'it' if one else 'them'} for llm-wiki's extensions?") + " [y/N] › ")
    sys.stdout.flush()
    try:
        answer = sys.stdin.readline().strip().lower()
    except (UnicodeDecodeError, OSError):
        answer = ""
    if answer not in ("y", "yes"):
        print("Nothing was changed.")
        return 0
    day = datetime.date.today().isoformat()
    try:
        # Read again: another terminal may have added one while the question waited.
        have = saved()
        known = {p for p, _ in have}
        new = [(p, f"added {day} for {host}") for p in need if p not in known]
        if len(have) + len(new) > MAX_SAVED:
            die(f"{tilde(FILE)} would hold more than {MAX_SAVED} certificates, so nothing was changed. "
                f"Do: run {CMD} extensions certs --remove, then add what you still need")
        write_saved(have + new)
        context()
    except Problem as e:
        die(str(e))
    except OSError as e:
        die(f"{tilde(FILE)} can't be written ({clean(e.strerror or e)}). Do: check that {tilde(CONFIG_DIR)} is yours to write")
    print(ok_mark() + f"Trusted, for llm-wiki's extensions only. {o} checks out now.")
    print(f"  To see what is trusted: {typed(CMD + ' extensions certs')}. To forget it: {typed(CMD + ' extensions certs --remove')}")
    return 0


def main(argv):
    if not argv:
        return cmd_list()
    if argv[0] in ("--help", "-h"):
        print(USAGE)
        return 0
    if argv[0] == "--remove":
        if len(argv) != 1:
            die(f"usage: {CMD} extensions certs --remove", 2)
        return cmd_remove()
    source = ""
    if len(argv) == 3 and argv[1] == "--from":
        source = argv[2]
    elif len(argv) != 1 or argv[0].startswith("-"):
        die(f"usage: {CMD} extensions certs [<https://address> [--from <file.pem>] | --remove]", 2)
    return cmd_offer(argv[0], source)


if __name__ == "__main__":
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(errors="replace")  # a terminal that can't show a mark shows ? and never a traceback
        except (AttributeError, ValueError):
            pass
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        sys.stderr.write("\nStopped. Nothing was changed.\n")
        sys.exit(130)
