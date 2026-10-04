# Shared by the PIN tools (see DEV.md, "PIN sign-in"): the rules for a PIN, the
# root-owned store, and the client side of the verifier's socket. Not run on
# its own.
import ctypes
import fcntl
import hashlib
import hmac
import json
import os
import pwd
import socket
import time

STORE = "/var/lib/atlasos/pin"
SOCKET = "/run/atlasos/pin.sock"
SHADOW = "/etc/shadow"
MAX_FAILS = 5
# Wrong PINs since the PIN was set. A password sign-in does not clear it; it
# falls by one per full day. At LIFETIME_MAX the PIN is retired (refused like
# a locked one) until a new PIN is set.
LIFETIME_MAX = 20
DAY = 86400
MAX_CREDIT = 7  # most days of decay credited per try
# Checked against when there is nothing to check (no PIN, locked, refused), so
# the answer takes as long either way and doesn't say who has a PIN.
DUMMY_HASH = "$y$jCT$6ywQF8MdojaGoYGxYFRveSSpnSnDvfqY/z04.APmSd.$3tQxZRrF2JfplGQd46WWvHvAuibRBYyH/qMwtS0G8O/"

_libcrypt = ctypes.CDLL("libcrypt.so.2")
_libcrypt.crypt.restype = ctypes.c_char_p
_libcrypt.crypt.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
_libcrypt.crypt_gensalt.restype = ctypes.c_char_p
_libcrypt.crypt_gensalt.argtypes = [
    ctypes.c_char_p, ctypes.c_ulong, ctypes.c_char_p, ctypes.c_int,
]


def is_pin_shaped(text):
    """4 to 8 ASCII digits. Anything else is a password, never a PIN."""
    return 4 <= len(text) <= 8 and text.isascii() and text.isdigit()


# The most common 4-digit PINs that the run and repeat rules don't already catch.
COMMON_PINS = frozenset((
    "1212", "1122", "1313", "1010", "2000", "2001", "1004", "6969", "2580",
    "0852", "1231", "1007", "1112", "1230", "1357", "2002", "1020", "0007",
    "1984", "2112", "1999", "5683", "0123", "1236", "1221", "4200",
))


def weakness(pin):
    """Why a PIN is refused as a new PIN, or None."""
    if not is_pin_shaped(pin):
        return "A PIN is 4 to 8 digits."
    if len(set(pin)) == 1:
        return "A PIN can't be one digit repeated."
    steps = {int(b) - int(a) for a, b in zip(pin, pin[1:])}
    if steps in ({1}, {-1}):
        return "A PIN can't be a straight run of digits."
    if any(len(pin) % d == 0 and pin == pin[:d] * (len(pin) // d)
           for d in range(2, len(pin) // 2 + 1)):
        return "A PIN can't be a short group of digits repeated."
    if pin in COMMON_PINS:
        return "That PIN is one of the most common ones. Choose another."
    if len(pin) == 4 and 1900 <= int(pin) <= 2099:
        return "A PIN can't be a year. Choose another."
    return None


def hash_pin(pin):
    # yescrypt, cost 8 (the default is 5): well under a second, and the 5
    # tries a PIN gets make the online side the limit anyway.
    setting = _libcrypt.crypt_gensalt(b"$y$", 8, os.urandom(32), 32)
    if not setting:
        raise OSError("crypt_gensalt failed")
    out = _libcrypt.crypt(pin.encode(), setting)
    if not out or out.startswith(b"*"):
        raise OSError("crypt failed")
    return out.decode()


def check_pin(pin, stored):
    out = _libcrypt.crypt(pin.encode(), stored.encode())
    if not out:
        return False
    return hmac.compare_digest(out, stored.encode())


def lifetime(entry, now=None):
    """The entry's lifetime count after decay, and the time it counts from:
    one off per full day since "life_at", at most MAX_CREDIT days per call
    (so a clock that jumps forward can't wipe the count in one go; the rest
    follows on later tries). life_at only moves forward, and only by the days
    actually credited; a clock that is behind it changes nothing. Records
    from before these fields count as 0. Pure; decay() applies it."""
    now = int(time.time() if now is None else now)
    life, at = entry.get("life", 0), entry.get("life_at", now)
    if not isinstance(life, int) or isinstance(life, bool) or life < 0:
        life = 0
    if not isinstance(at, int) or isinstance(at, bool):
        at = now
    if at > now:
        return life, at
    days = min((now - at) // DAY, MAX_CREDIT)
    life = max(0, life - days)
    at = now if life == 0 else at + days * DAY
    return life, at


def decay(entry, now=None):
    """Apply the decay to entry in place; returns the count. A retired
    entry doesn't decay."""
    if retired(entry):
        return entry.get("life", 0)
    entry["life"], entry["life_at"] = lifetime(entry, now)
    return entry["life"]


def retired(entry):
    """A latch: once set (at LIFETIME_MAX wrong PINs) only a new PIN's fresh
    record clears it; decay never does. A record at LIFETIME_MAX or more
    without the latch (written by hand, or by an older build) counts too."""
    life = entry.get("life", 0)
    return entry.get("retired") is True or (
        isinstance(life, int) and not isinstance(life, bool) and life >= LIFETIME_MAX)


class Store:
    """One JSON file per uid in STORE: {"hash": ..., "fails": n, "stamp": ...,
    "life": n, "life_at": epoch seconds, "retired": true once retired}.
    Hold the lock (with Store() as s) across a read and the write that
    follows, and only that: never across a hash."""

    def __enter__(self):
        self._lock = os.open(os.path.join(STORE, ".lock"),
                             os.O_RDWR | os.O_CREAT, 0o600)
        fcntl.flock(self._lock, fcntl.LOCK_EX)
        return self

    def __exit__(self, *exc):
        os.close(self._lock)

    def _path(self, uid):
        return os.path.join(STORE, str(int(uid)))

    def get(self, uid):
        try:
            with open(self._path(uid)) as f:
                data = json.load(f)
            if isinstance(data.get("hash"), str) and isinstance(data.get("fails"), int):
                return data
        except (OSError, ValueError, AttributeError):
            pass
        return None

    def put(self, uid, data):
        path = self._path(uid)
        tmp = path + ".tmp"
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        try:
            with os.fdopen(fd, "w") as f:
                json.dump(data, f)
                f.flush()
                os.fsync(f.fileno())
            os.rename(tmp, path)
        except BaseException:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            raise
        self._sync_dir()

    def remove(self, uid):
        try:
            os.unlink(self._path(uid))
        except FileNotFoundError:
            return
        self._sync_dir()

    def _sync_dir(self):
        """Make the rename or unlink durable, so a power cut right after a
        wrong PIN can't roll its count back. Errors propagate like a failed
        write: the caller must not answer as if it was stored."""
        fd = os.open(STORE, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)


def account_stamp(uid):
    """Ties a PIN to the account it was set for: a digest of the user name,
    uid and the shadow password hash. None when the password can't sign in
    (a shadow hash that is empty or locked, starting with ! or *): a PIN must
    not open an account that its password does not. A changed password, or a
    uid given to someone else later, changes the stamp, and the PIN dies."""
    try:
        name = pwd.getpwuid(int(uid)).pw_name
        with open(SHADOW) as f:
            for line in f:
                fields = line.rstrip("\n").split(":")
                if len(fields) > 1 and fields[0] == name:
                    if fields[1] == "" or fields[1][0] in "!*":
                        return None
                    text = "%s:%d:%s" % (name, int(uid), fields[1])
                    return hashlib.sha256(text.encode()).hexdigest()
    except (OSError, KeyError, ValueError):
        pass
    return None


def ask(line, timeout=3):
    """Send one request to the verifier; its one-line answer, or None."""
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(timeout)
            s.connect(SOCKET)
            s.sendall(line.encode() + b"\n")
            s.shutdown(socket.SHUT_WR)
            data = b""
            while len(data) < 256:
                chunk = s.recv(256)
                if not chunk:
                    break
                data += chunk
        return data.decode().strip() or None
    except (OSError, UnicodeError):
        return None
