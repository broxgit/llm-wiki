#!/usr/bin/env python3
"""tty_run.py: run a command at a pseudo-terminal, as a person at a terminal would, and type its answers.

    tests/tty_run.py [--timeout SECONDS] [--] COMMAND [ARG]...

The answers are what comes on this script's standard input, when that is not a terminal itself:
    printf 'y\\n' | tests/tty_run.py wiki feedback send <id>
Give </dev/null for none. A last line with no line break is a whole line. At most 1 MiB is taken.

An answer is typed when the command is waiting for it, the way a person answers a prompt they can
see: once the line before it has been read, and the command has printed a prompt (output that ends
without a line break, in a space, a colon, a question mark or a >) and gone quiet. A command that
reads with no prompt gets its answer once it has been quiet for a second. An answer typed that way
can come early, and a command that empties the terminal's input before it asks, as getpass does,
would lose it: the terminal is in packet mode, which reports that, and the answer is typed again at
the next prompt. When every answer has been read, the next prompt gets the end of input (Ctrl-D),
as a pipe would give it, so a question nobody answers ends the command instead of hanging it.

The command gets the pseudo-terminal as standard input, output and error, and as its controlling
terminal, so `[ -t 0 ]`, `[ -t 1 ]`, `isatty()` and opening /dev/tty all find a terminal. It runs
in its own process group, in the foreground, under a session leader of this script's that takes
the terminal back when the command ends: a job it left in the background is not sent a hangup,
as at a person's shell, and is not waited for.

The terminal is 80 columns by 24 lines, with echo off, so what the command prints is all that
comes back: the answers typed don't appear. Its line ends are turned back from \\r\\n to \\n. The
environment is passed on as it is, so colour follows the command's own rule (LLM_WIKI_STYLE,
NO_COLOR, TERM); the smoke tests keep LLM_WIKI_STYLE=off unless a test turns it on.

The exit code is the command's, or 128 plus the signal that ended it. After --timeout seconds
(default 20), or when this script is sent INT, TERM or HUP, the command's process group is killed,
what it printed so far is printed, and this exits 124 (128 plus the signal) with a message on
standard error saying so.
Standard library only, for Python 3.9 and later on macOS and Linux.
"""
import errno
import fcntl
import math
import os
import select
import signal
import struct
import sys
import termios
import time

ROWS, COLS = 24, 80
# A prompt is taken to be drawn when the command has printed one and then gone quiet this long.
QUIET = 0.05
# With no prompt, the next answer is typed once the command has been quiet this long.
IDLE = 1.0
# What ends a prompt: the last byte printed, with no line break after it.
PROMPT_ENDS = b" :?>"
MAX_INPUT = 1 << 20
# The end of input is typed this many times at most, so a command that reads on and on stops.
MAX_EOFS = 50
# Packet mode on the master side: each read starts with a byte that says what it is. The values
# are the same on Linux and the BSDs; the ioctl's number is not, so it comes from termios.
TIOCPKT = getattr(termios, "TIOCPKT", 0x5420 if sys.platform.startswith("linux") else 0x80047470)
PKT_DATA = 0
PKT_FLUSHREAD = getattr(termios, "TIOCPKT_FLUSHREAD", 1)


def usage(msg):
    sys.stderr.write("tty_run.py: %s\nusage: tests/tty_run.py [--timeout SECONDS] [--] COMMAND [ARG]...\n" % msg)
    sys.exit(2)


def parse(argv):
    timeout = 20.0
    while argv:
        if argv[0] == "--":
            argv = argv[1:]
            break
        if argv[0] == "--timeout":
            if len(argv) < 2:
                usage("--timeout takes a number of seconds")
            try:
                timeout = float(argv[1])
            except ValueError:
                timeout = -1
            if not (timeout > 0 and math.isfinite(timeout)):
                usage("--timeout takes a number of seconds above 0, not %s" % argv[1])
            argv = argv[2:]
            continue
        if argv[0].startswith("--"):
            usage("no option %s" % argv[0])
        break
    if not argv:
        usage("no command given")
    return timeout, argv


def answers(timeout):
    """The lines to type: this script's standard input, unless that is a terminal or closed. It
    has to end, within the time limit and within MAX_INPUT bytes: anything else is a mistake in
    the test. A last line with no line break gets one, so it is a whole line."""
    try:
        if os.isatty(0):
            return []
    except OSError:
        return []
    chunks, size = [], 0
    end = time.monotonic() + timeout
    while True:
        left = end - time.monotonic()
        try:
            r, _, _ = select.select([0], [], [], max(left, 0))
        except (OSError, ValueError):
            return []
        if not r:
            sys.stderr.write(
                "tty_run.py: standard input was still open after %gs. Give the answers through a pipe, "
                "or </dev/null for none.\n" % timeout
            )
            sys.exit(2)
        try:
            data = os.read(0, 1 << 16)
        except OSError:
            break
        if not data:
            break
        size += len(data)
        if size > MAX_INPUT:
            sys.stderr.write("tty_run.py: more than %d bytes of answers on standard input, so nothing was run.\n" % MAX_INPUT)
            sys.exit(2)
        chunks.append(data)
    lines = b"".join(chunks).splitlines(True)
    if lines and not lines[-1].endswith(b"\n"):
        lines[-1] += b"\n"
    return lines


def pending_input(fd):
    """Bytes typed that the command has not read yet, or 0 when that can't be told."""
    try:
        return struct.unpack("i", fcntl.ioctl(fd, termios.FIONREAD, b"\0\0\0\0"))[0]
    except OSError:
        return 0


def write_all(fd, data):
    """All of it, however many writes that takes. False when the other end is gone."""
    while data:
        try:
            n = os.write(fd, data)
        except InterruptedError:
            continue
        except OSError:
            return False
        data = data[n:]
    return True


def leader(slave, master, argv, report):
    """The session leader: makes the pseudo-terminal its controlling terminal, starts the command in
    the foreground, waits for it, takes the terminal back and exits with its code. Never returns."""
    try:
        os.close(master)
        for s in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP, signal.SIGPIPE):
            signal.signal(s, signal.SIG_DFL)
        os.setsid()
        try:
            fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
        except OSError:
            # Linux also makes a terminal opened by a session leader its controlling one.
            os.close(os.open(os.ttyname(slave), os.O_RDWR))
        pid = os.fork()
        if pid == 0:
            try:
                os.close(report)
                os.setpgid(0, 0)
                signal.signal(signal.SIGTTOU, signal.SIG_IGN)
                os.tcsetpgrp(slave, os.getpid())
                signal.signal(signal.SIGTTOU, signal.SIG_DFL)
                for fd in (0, 1, 2):
                    os.dup2(slave, fd)
                if slave > 2:
                    os.close(slave)
                os.execvp(argv[0], argv)
            except OSError as e:
                os.write(2, ("tty_run.py: can't run %s: %s\n" % (argv[0], e.strerror)).encode())
                os._exit(127)
            os._exit(127)
        try:
            os.setpgid(pid, pid)
        except OSError:
            pass
        os.write(report, b"%d\n" % pid)
        os.close(report)
        while True:
            try:
                _, status = os.waitpid(pid, 0)
                break
            except InterruptedError:
                continue
        code = os.waitstatus_to_exitcode(status)
        if code < 0:
            code = 128 - code
        # Take the terminal back, so the hangup this leader's exit sends goes to nobody else.
        signal.signal(signal.SIGTTOU, signal.SIG_IGN)
        try:
            os.tcsetpgrp(slave, os.getpgrp())
        except OSError:
            pass
        os._exit(code)
    except BaseException as e:  # noqa: B902: nothing may return into the parent's code
        try:
            os.write(2, ("tty_run.py: the session leader failed: %s\n" % e).encode())
        finally:
            os._exit(125)


class Output:
    """What the command printed, written out as it comes, with \\r\\n turned back to \\n."""

    def __init__(self):
        self.held = b""

    def add(self, data):
        data = self.held + data
        self.held = b""
        if data.endswith(b"\r"):
            data, self.held = data[:-1], b"\r"
        write_all(1, data.replace(b"\r\n", b"\n"))

    def end(self):
        write_all(1, self.held)
        self.held = b""


class Stop(Exception):
    """A signal to this script: stop the command and go."""

    def __init__(self, signum):
        Exception.__init__(self)
        self.signum = signum


def on_signal(signum, _frame):
    raise Stop(signum)


def command_pid(rd, wait):
    """The command's process id, which is its process group's, as the leader reports it."""
    try:
        r, _, _ = select.select([rd], [], [], wait)
        if r:
            got = os.read(rd, 64)
            return int(got) if got.strip() else -1
    except (OSError, ValueError):
        return -1
    return None


def main():
    timeout, argv = parse(sys.argv[1:])
    lines = answers(timeout)
    master, slave = os.openpty()
    attrs = termios.tcgetattr(slave)
    attrs[3] &= ~(termios.ECHO | termios.ECHONL)
    termios.tcsetattr(slave, termios.TCSANOW, attrs)
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, 0, 0))
    fcntl.ioctl(master, TIOCPKT, struct.pack("i", 1))
    eof = attrs[6][termios.VEOF]
    eof = eof if isinstance(eof, bytes) else bytes([eof])
    rd, wr = os.pipe()
    sys.stdout.flush()
    sys.stderr.flush()
    lead = os.fork()
    if lead == 0:
        os.close(rd)
        leader(slave, master, argv, wr)
    os.close(wr)
    # The parent keeps the slave side open, to ask how much typed input is still unread. So the
    # master never reports a hang-up while the command runs, on Linux or macOS: the command's end
    # is noticed from the leader's exit, looked for every 20ms, not from the master.
    signal.signal(signal.SIGPIPE, signal.SIG_IGN)
    for s in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(s, on_signal)
    fl = fcntl.fcntl(master, fcntl.F_GETFL)
    fcntl.fcntl(master, fcntl.F_SETFL, fl | os.O_NONBLOCK)

    out = Output()
    start = time.monotonic()
    last_out = typed_at = start
    tail = b""  # the last byte printed since the last answer, or nothing
    to_type = b""
    typed = None  # the last answer typed, as (bytes, how): how is "prompt" or "idle"
    unread = False  # it was typed, and not yet seen read
    eofs = 0
    command = None
    code = None
    stopped = None
    try:
        while code is None:
            now = time.monotonic()
            if now - start > timeout:
                break
            if command is None:
                command = command_pid(rd, 0)
            want_write = [master] if to_type else []
            try:
                r, w, _ = select.select([master], want_write, [], 0.02)
            except InterruptedError:
                continue
            now = time.monotonic()
            if r:
                try:
                    data = os.read(master, 65536)
                except OSError as e:
                    data = b""
                    if e.errno not in (errno.EAGAIN, errno.EIO):
                        raise
                if data[:1] == bytes([PKT_DATA]):
                    if len(data) > 1:
                        out.add(data[1:])
                        last_out = now
                        tail = data[-1:]
                elif data and data[0] & PKT_FLUSHREAD:
                    # The command emptied the terminal's input. An answer typed with no prompt
                    # to answer, and not read, was lost: it is typed again at the next prompt.
                    if unread and typed and typed[1] == "idle" and not to_type:
                        if typed[0] == eof:
                            eofs = max(eofs - 1, 0)
                        else:
                            lines.insert(0, typed[0])
                    unread = False
            if w and to_type:
                try:
                    n = os.write(master, to_type)
                    to_type = to_type[n:]
                except OSError as e:
                    if e.errno != errno.EAGAIN:
                        to_type = b""
            if unread and not to_type and pending_input(slave) == 0:
                unread = False
            if not to_type and not unread and pending_input(slave) == 0:
                quiet = now - last_out
                prompt = bool(tail) and tail != b"\n" and tail in PROMPT_ENDS and quiet >= QUIET
                idle = not prompt and quiet >= IDLE and now - typed_at >= IDLE
                if prompt or idle:
                    if lines:
                        to_type = lines.pop(0)
                    elif eofs < MAX_EOFS and (eofs == 0 or tail):
                        to_type = eof
                        eofs += 1
                    if to_type:
                        typed = (to_type, "prompt" if prompt else "idle")
                        unread = True
                        typed_at = now
                        tail = b""
            try:
                pid, status = os.waitpid(lead, os.WNOHANG)
            except ChildProcessError:
                pid, status = lead, 0
            if pid == lead:
                code = os.waitstatus_to_exitcode(status)
                if code < 0:
                    code = 128 - code
    except Stop as e:
        stopped = e.signum
    for s in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(s, signal.SIG_IGN)
    if code is None:
        # Out of time, or told to stop: the command and everything in its process group, then the leader.
        if command is None:
            command = command_pid(rd, 1.0)
        if command and command > 0:
            try:
                os.killpg(command, signal.SIGKILL)
            except OSError:
                pass
        try:
            os.kill(lead, signal.SIGKILL)
        except OSError:
            pass
        try:
            os.waitpid(lead, 0)
        except OSError:
            pass
    # What is left to read. A job left in the background may hold the terminal and go on
    # writing to it, so this stops when it goes quiet, or after a second at most.
    end = time.monotonic() + 1.0
    while time.monotonic() < end:
        try:
            r, _, _ = select.select([master], [], [], 0.05)
        except InterruptedError:
            continue
        if not r:
            break
        try:
            data = os.read(master, 65536)
        except OSError:
            break
        if not data:
            break
        if data[:1] == bytes([PKT_DATA]):
            out.add(data[1:])
    out.end()
    if code is None:
        if stopped:
            why = "this script was sent signal %d" % stopped
            code = 128 + stopped
        else:
            why = "it was still running after %gs. It may be waiting for an answer the test didn't give" % timeout
            code = 124
        sys.stderr.write("\ntty_run.py: %s was stopped: %s.\n" % (" ".join(argv), why))
        sys.stderr.flush()
    os._exit(code)


if __name__ == "__main__":
    main()
