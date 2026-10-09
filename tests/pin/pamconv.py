#!/usr/bin/python3
"""A tiny libpam client: pamconv.py SERVICE USER ANSWER [session]

Answers every password prompt with ANSWER, calls pam_authenticate (and, when
it succeeds, pam_setcred and, with "session", pam_open_session), prints one
line per call and exits 0 only if authentication succeeded. This is what a
greeter or lock screen does, without the screen."""
import ctypes
import ctypes.util
import sys

libpam = ctypes.CDLL(ctypes.util.find_library("pam"))
libc = ctypes.CDLL(ctypes.util.find_library("c"))
libc.calloc.restype = ctypes.c_void_p
libc.strdup.restype = ctypes.c_void_p
libc.strdup.argtypes = [ctypes.c_char_p]
libpam.pam_strerror.restype = ctypes.c_char_p


class Msg(ctypes.Structure):
    _fields_ = [("msg_style", ctypes.c_int), ("msg", ctypes.c_char_p)]


class Resp(ctypes.Structure):
    _fields_ = [("resp", ctypes.c_void_p), ("resp_retcode", ctypes.c_int)]


CONV = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_int, ctypes.POINTER(ctypes.POINTER(Msg)),
                        ctypes.POINTER(ctypes.POINTER(Resp)), ctypes.c_void_p)


class Conv(ctypes.Structure):
    _fields_ = [("conv", CONV), ("data", ctypes.c_void_p)]


service, user, answer = sys.argv[1:4]
want_session = len(sys.argv) > 4
prompts = 0


def conv(n, msgs, resp, _data):
    global prompts
    arr = libc.calloc(n, ctypes.sizeof(Resp))
    resp[0] = ctypes.cast(arr, ctypes.POINTER(Resp))
    for i in range(n):
        if msgs[i][0].msg_style in (1, 2):  # a prompt
            prompts += 1
            resp[0][i].resp = libc.strdup(answer.encode())
    return 0


callback = CONV(conv)
handle = ctypes.c_void_p()
c = Conv(callback, None)
if libpam.pam_start(service.encode(), user.encode(), ctypes.byref(c), ctypes.byref(handle)) != 0:
    print("pam_start failed")
    sys.exit(2)


def call(name, rc):
    print(f"{name}={rc}")
    return rc


auth = call("authenticate", libpam.pam_authenticate(handle, 0))
if auth == 0:
    call("setcred", libpam.pam_setcred(handle, 2))  # PAM_ESTABLISH_CRED
    if want_session:
        call("open_session", libpam.pam_open_session(handle, 0))
print(f"prompts={prompts}")
libpam.pam_end(handle, auth)
sys.exit(0 if auth == 0 else 1)
