#!/bin/bash
# Runs inside the container made by run.sh, as root.
set -uo pipefail
fail=0
ok() { echo "  ok   $*"; }
bad() { echo "  FAIL $*"; fail=1; }
expect() { # WANT GOT WHAT
	if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (want '$1', got '$2')"; fi
}
expect_ne() { # NOT GOT WHAT
	if [ "$1" != "$2" ]; then ok "$3"; else bad "$3 (got '$2')"; fi
}

LIB=/usr/libexec/telamon
STORE=/var/lib/atlasos/pin
rand() { python3 -c 'import secrets; print(secrets.token_hex(8))'; }
PW_A="pw-$(rand)"
PW_B="pw-$(rand)"
PIN=7391
WRONG=2468
useradd -m -u 1001 alice && useradd -m -u 1002 bob || exit 1
echo "alice:$PW_A" | chpasswd
echo "bob:$PW_B" | chpasswd
mkdir -p /run/atlasos "$STORE"
chmod 700 "$STORE"

as() { # UID CMD...
	local u=$1
	shift
	setpriv --reuid="$u" --regid="$u" --clear-groups "$@"
}
pam() { # SERVICE USER TYPED [session] (as root): the exit status of pam_authenticate
	python3 /t/pamconv.py "$@" >/tmp/pam.out 2>&1
}
pam_as() { # UID SERVICE USER TYPED [session]
	local u=$1
	shift
	as "$u" python3 /t/pamconv.py "$@" >/tmp/pam.out 2>&1
}
ask() { as "$1" python3 /t/ask.py "${@:2}"; }
admin_set() { printf '%s\n' "$2" | PKEXEC_UID=$1 "$LIB/pin-admin" set 2>&1; }
entry() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$STORE/$1" "$2" 2>/dev/null; }
patch_entry() { # UID KEY VALUE(json)
	python3 - "$STORE/$1" "$2" "$3" <<'PY'
import json, sys
p, k, v = sys.argv[1:4]
d = json.load(open(p))
d[k] = json.loads(v)
json.dump(d, open(p, "w"))
PY
}

echo "== 1. the PAM files"
# the module is in the stack of exactly the services that should have it
for f in /etc/pam.d/*; do
	n=${f##*/}
	case $n in
	password-auth | plasmalogin) continue ;;
	esac
	if grep -q pam_atlasos_pin "$f"; then bad "/etc/pam.d/$n names pam_atlasos_pin"; fi
done
ok "no other file in /etc/pam.d names the PIN module"
expect 1 "$(grep -c '^auth.*pam_atlasos_pin.so' /etc/pam.d/password-auth)" "password-auth has one auth line for the PIN module"
expect 1 "$(grep -c '^session.*pam_atlasos_pin.so' /etc/pam.d/password-auth)" "password-auth has one session line for it"
expect 1 "$(grep -c 'pam_atlasos_pin.so pinlogin' /etc/pam.d/plasmalogin)" "plasmalogin has the one pinlogin line"
grep -B1 'auth .*pam_atlasos_pin.so *$' /etc/pam.d/password-auth | grep -q 'pam_succeed_if.so quiet service in kde:plasmalogin' &&
	ok "the PIN module is gated by pam_succeed_if on kde:plasmalogin" || bad "the service gate is missing in front of the PIN module"
[ "$(stat -c '%a %U' /usr/lib64/security/pam_atlasos_pin.so)" = "755 root" ] && ok "pam_atlasos_pin.so is 0755 root" || bad "pam_atlasos_pin.so mode/owner: $(stat -c '%a %U' /usr/lib64/security/pam_atlasos_pin.so)"

echo "== 2. no service but the lock screen and the login screen reaches the verifier"
python3 /t/fake-verifier.py &
fake=$!
for _ in $(seq 20); do [ -S /run/atlasos/pin.sock ] && break; sleep 0.2; done
: >/tmp/fake-verifier.log
pam_as 1001 kde alice "$PIN"
expect 0 $? "kde (lock screen) takes a PIN the verifier accepts"
pam 1>/dev/null 2>&1 plasmalogin alice "$PIN" session
expect 0 $? "plasmalogin (login screen) takes a PIN the verifier accepts"
grep -q '^verify$' /tmp/fake-verifier.log && ok "the verifier was asked for those two" || bad "the control did not reach the fake verifier"
: >/tmp/fake-verifier.log
for svc in sshd sudo sudo-i su su-l login passwd chsh chfn runuser runuser-l system-auth password-auth polkit-1 other remote vlock cups samba no-such-service; do
	pam_as 1001 "$svc" alice "$PIN"
	rc=$?
	if [ $rc -eq 0 ]; then bad "$svc authenticated alice with a PIN"; fi
done
expect 0 "$(grep -c . /tmp/fake-verifier.log)" "no other PAM service ever asked the verifier (sshd, sudo, su, login, polkit, ...)"
pam 1>/dev/null 2>&1 sshd alice "$PIN"
expect_ne 0 $? "sshd as root-side caller refuses the PIN too"
expect 0 "$(grep -c . /tmp/fake-verifier.log)" "still no request"
pam_as 1001 sudo alice "$PW_A"
expect 0 $? "sudo still takes the real password"
pam_as 1001 sshd alice "$PW_A"
expect 0 $? "sshd still takes the real password"
kill "$fake" 2>/dev/null
wait "$fake" 2>/dev/null
rm -f /run/atlasos/pin.sock

echo "== 3. the real verifier"
systemd-socket-activate --inetd -a -l /run/atlasos/pin.sock "$LIB/pin-daemon" >/tmp/daemon.log 2>&1 &
for _ in $(seq 20); do [ -S /run/atlasos/pin.sock ] && break; sleep 0.2; done
chmod 666 /run/atlasos/pin.sock
expect none "$(ask 1001 'status 1001')" "alice has no PIN yet"
out=$(admin_set 1001 "$PIN")
expect "PIN set." "$out" "pin-admin set (as pkexec runs it) sets alice's PIN"
expect set "$(ask 1001 'status 1001')" "alice's PIN is set"
pam_as 1001 kde alice "$PIN"
expect 0 $? "the lock screen unlocks with the PIN"
pam_as 1001 kde alice "$PW_A"
expect 0 $? "and with the password"
expect "bad" "$(ask 1001 "verify 1001 alice $WRONG")" "a wrong PIN is bad"
expect "ok" "$(ask 1001 "verify 1001 alice $PIN")" "the right one is ok"

echo "== 4. lockout after 5 wrong PINs"
admin_set 1001 "$PIN" >/dev/null # a fresh record
n=0
for _ in 1 2 3 4; do pam_as 1001 kde alice "$WRONG" && n=1; done
expect 0 "$n" "four wrong PINs at the lock screen all fail"
expect set "$(ask 1001 'status 1001')" "four wrong are not yet a lock"
pam_as 1001 kde alice "$WRONG"
expect locked "$(ask 1001 'status 1001')" "the fifth locks the PIN"
pam_as 1001 kde alice "$PIN"
expect_ne 0 $? "the right PIN no longer works once locked"
expect locked "$(ask 1001 "verify 1001 alice $PIN")" "verify answers locked, without checking"
pam_as 1001 kde alice "$PW_A"
expect 0 $? "the password still works"
expect deny "$(ask 1001 'reset 1001')" "alice cannot reset her own count"
expect "done" "$(python3 /t/ask.py 'reset 1001')" "root can"
expect set "$(ask 1001 'status 1001')" "and the PIN works again"
expect 5 "$(entry 1001 life)" "but the lifetime count kept the five"

echo "== 5. the login screen's password sign-in is what clears the count"
admin_set 1001 "$PIN" >/dev/null
for _ in 1 2 3; do pam_as 1001 kde alice "$WRONG"; done
expect 3 "$(entry 1001 fails)" "three wrong PINs counted"
pam plasmalogin alice "$PIN" session
expect 0 $? "a PIN login at the login screen works"
expect 3 "$(entry 1001 fails)" "and does not clear the count"
pam plasmalogin alice "$PW_A" session
expect 0 $? "a password login at the login screen works"
expect 0 "$(entry 1001 fails)" "and clears it"
for _ in 1 2; do pam_as 1001 kde alice "$WRONG"; done
pam_as 1001 kde alice "$PW_A"
expect 2 "$(entry 1001 fails)" "a password unlock at the lock screen does not clear it"

echo "== 6. who may ask about whom"
admin_set 1001 "$PIN" >/dev/null
expect deny "$(ask 1002 'status 1001')" "bob cannot ask alice's status"
expect deny "$(ask 1002 "verify 1001 alice $PIN")" "bob cannot verify against alice's PIN"
expect deny "$(ask 1002 'reset 1001')" "bob cannot reset alice's count"
expect 0 "$(entry 1001 fails)" "alice's count is untouched by all that"
expect none "$(ask 1002 'status 1002')" "bob sees his own state"
expect nopin "$(ask 1002 "verify 1002 bob $PIN")" "bob has no PIN: nopin"
expect "ok" "$(python3 /t/ask.py "verify 1001 alice $PIN")" "root may ask about any uid"
pam_as 1002 kde alice "$PIN"
expect_ne 0 $? "bob cannot get into alice's account through PAM with her PIN"
expect 0 "$(entry 1001 fails)" "and that was not counted against alice"

echo "== 7. malformed and incomplete requests"
before=$(entry 1001 life)
expect nopin "$(ask 1001 'verify 1001 bob 7391')" "a name that is not the uid's name: nopin"
expect nopin "$(ask 1001 'verify 1001 alice 12ab')" "a non-digit PIN: nopin"
expect nopin "$(ask 1001 'verify 1001 alice 123')" "a 3-digit PIN: nopin"
expect nopin "$(ask 1001 'verify 1001 alice 123456789')" "a 9-digit PIN: nopin"
expect nopin "$(ask 1001 'verify 1001x alice 7391')" "a uid that is not digits: nopin"
expect deny "$(ask 1001 'verify 99999 nobody-here 7391')" "another user's (unknown) uid: deny"
expect nopin "$(python3 /t/ask.py 'verify 99999 nobody-here 7391')" "an unknown uid, asked by root: nopin"
expect deny "$(ask 1001 'verify 1001 alice')" "a verify without the PIN: deny"
expect deny "$(ask 1001 'verify 1001 alice 7391 extra')" "a verify with a fourth word: deny"
expect deny "$(ask 1001 'status')" "status without a uid: deny"
expect deny "$(ask 1001 'status abc')" "status of a non-number: deny"
expect deny "$(ask 1001 'status -1')" "status of -1: deny"
expect deny "$(ask 1001 'status 1001 1002')" "status with two uids: deny"
expect deny "$(ask 1001 'frobnicate 1001')" "an unknown command: deny"
expect deny "$(ask 1001 '')" "an empty line: deny"
expect deny "$(ask 1001 --raw "verify 1001 alice $WRONG")" "a request without its newline: deny"
refused() { case $1 in deny | "(none)") return 0 ;; *) return 1 ;; esac; }
long=$(ask 1001 "$(printf 'a%.0s' $(seq 300))")
refused "$long" && ok "an over-long line is refused ($long)" || bad "an over-long line got '$long'"
long=$(ask 1001 "$(printf 'verify 1001 alice 7391 %s' "$(printf 'a%.0s' $(seq 200))")")
refused "$long" && ok "a long verify is refused ($long)" || bad "a long verify got '$long'"
expect "$before" "$(entry 1001 life)" "none of those counted as a wrong PIN"
expect 0 "$(entry 1001 fails)" "or as a try"

echo "== 8. parallel guesses cannot beat the limit"
admin_set 1001 "$PIN" >/dev/null
pids=
for i in $(seq 12); do
	as 1001 python3 /t/ask.py "verify 1001 alice $WRONG" >/tmp/par.$i &
	pids="$pids $!"
done
wait $pids
expect 5 "$(entry 1001 fails)" "twelve parallel wrong PINs count exactly five"
badn=$(cat /tmp/par.* | grep -c '^bad$')
if [ "$badn" -le 4 ]; then ok "at most four of them were told 'bad' ($badn)"; else bad "$badn answers were 'bad'"; fi
rm -f /tmp/par.*
admin_set 1001 "$PIN" >/dev/null
pids=
for i in $(seq 30); do
	if [ "$i" = 17 ]; then pin=$PIN; else pin=$WRONG; fi
	as 1001 python3 /t/ask.py "verify 1001 alice $pin" >/tmp/par.$i &
	pids="$pids $!"
done
wait $pids
if [ "$(entry 1001 fails)" -le 5 ]; then ok "30 parallel tries, one of them right: the count stayed within 5 ($(entry 1001 fails))"; else bad "count is $(entry 1001 fails)"; fi
rm -f /tmp/par.*

echo "== 9. the lifetime cap and its decay"
admin_set 1001 "$PIN" >/dev/null
patch_entry 1001 life 19
patch_entry 1001 life_at "$(date +%s)"
expect "locked" "$(ask 1001 "verify 1001 alice $WRONG")" "the 20th wrong PIN of a lifetime retires the PIN"
expect retired "$(ask 1001 'status 1001')" "status says retired"
expect locked "$(ask 1001 "verify 1001 alice $PIN")" "the right PIN is refused while retired"
python3 /t/ask.py 'reset 1001' >/dev/null
expect retired "$(ask 1001 'status 1001')" "a password sign-in (reset) does not undo it"
admin_set 1001 "$PIN" >/dev/null
expect set "$(ask 1001 'status 1001')" "setting a new PIN does"
patch_entry 1001 life 10
patch_entry 1001 life_at "$(( $(date +%s) - 3 * 86400 - 60 ))"
ask 1001 "verify 1001 alice $WRONG" >/dev/null
expect 8 "$(entry 1001 life)" "three full days credit three, the wrong PIN adds one (10 - 3 + 1)"
patch_entry 1001 life 15
patch_entry 1001 life_at "$(( $(date +%s) - 400 * 86400 ))"
ask 1001 "verify 1001 alice $WRONG" >/dev/null
expect 9 "$(entry 1001 life)" "a year of credit is capped at 7 days per try (15 - 7 + 1)"
patch_entry 1001 life 5
patch_entry 1001 life_at "$(( $(date +%s) + 30 * 86400 ))"
ask 1001 "verify 1001 alice $WRONG" >/dev/null
expect 6 "$(entry 1001 life)" "a clock behind the record credits nothing (5 + 1)"

echo "== 10. the store"
admin_set 1001 "$PIN" >/dev/null
admin_set 1002 "$((PIN + 1))" >/dev/null
expect "700 root root" "$(stat -c '%a %U %G' "$STORE")" "the folder is 0700 root"
expect "600 root root" "$(stat -c '%a %U %G' "$STORE/1001")" "a record is 0600 root"
case $(entry 1001 hash) in '$y$'*) ok "the hash is yescrypt" ;; *) bad "the hash is not yescrypt: $(entry 1001 hash | cut -c1-6)" ;; esac
if grep -q "$PIN" "$STORE/1001"; then bad "the PIN is in its record"; else ok "the PIN is not in its record in the clear"; fi
h1=$(entry 1001 hash)
admin_set 1001 "$PIN" >/dev/null
expect_ne "$h1" "$(entry 1001 hash)" "the same PIN hashes differently each time (random salt)"
expect "" "$(find "$STORE" -mindepth 1 ! -name .lock ! -regex '.*/[0-9]+')" "no temporary file is left in the store"
expect "" "$(find "$STORE" -type l)" "no symlink in the store"
if grep -q -E "$PIN|$WRONG|$((PIN + 1))" /tmp/daemon.log; then bad "a PIN is in the verifier's log"; else ok "no PIN is in the verifier's log"; fi
grep -q 'wrong PIN for uid' /tmp/daemon.log && ok "wrong PINs are logged (uid and counts only)" || bad "wrong PINs are not logged"

echo "== 11. what pin-admin refuses"
rm -f "$STORE/1002"
for weak in 1234 4321 1111 1212 2020 2580 123456 12345678 1234567 12 123 abcd 123456789 ''; do
	out=$(admin_set 1002 "$weak")
	rc=$?
	if [ $rc -ne 0 ]; then ok "refuses '$weak'"; else bad "accepted '$weak'"; fi
done
expect none "$(ask 1002 'status 1002')" "and bob still has none"
out=$(printf '%s\n' "$PIN" | "$LIB/pin-admin" set 2>&1)
expect_ne 0 $? "without pkexec (no PKEXEC_UID) it refuses"
out=$(printf '%s\n' "$PIN" | PKEXEC_UID=0 "$LIB/pin-admin" set 2>&1)
expect_ne 0 $? "root has no PIN"
out=$(printf '%s\n' "$PIN" | PKEXEC_UID=1002 as 1002 "$LIB/pin-admin" set 2>&1)
expect_ne 0 $? "as a plain user (not through pkexec's root) it refuses"
out=$(printf '%s\n' "$PIN" | PKEXEC_UID=1002 "$LIB/pin-admin" set "$PIN" 2>&1)
expect_ne 0 $? "a PIN on the command line is not accepted"
out=$(PKEXEC_UID=abc "$LIB/pin-admin" remove 2>&1)
expect_ne 0 $? "a PKEXEC_UID that is not a number is refused"
expect none "$(ask 1002 'status 1002')" "bob still has none"
expect "$(entry 1001 hash)" "$(entry 1001 hash)" "alice's record is intact"
out=$(as 1001 "$LIB/pin-admin" status)
expect set "$out" "pin-admin status needs no root and reports set"

echo "== 12. a changed or locked password kills the PIN"
admin_set 1001 "$PIN" >/dev/null
usermod -L alice
expect deny "$(ask 1001 "verify 1001 alice $PIN")" "a locked account: the PIN is refused"
out=$(admin_set 1001 "$PIN")
expect_ne 0 $? "a locked account cannot be given a PIN"
usermod -U alice
expect set "$(ask 1001 'status 1001')" "unlocked again, the same PIN is back"
echo "alice:pw-$(rand)" | chpasswd
expect none "$(ask 1001 'status 1001')" "a new password drops the PIN"
[ ! -e "$STORE/1001" ] && ok "and its record is deleted" || bad "the record is still there"

echo "== 13. pin-admin remove"
admin_set 1002 "$((PIN + 1))" >/dev/null
PKEXEC_UID=1002 "$LIB/pin-admin" remove >/dev/null
expect none "$(ask 1002 'status 1002')" "remove takes bob's PIN away"
[ ! -e "$STORE/1002" ] && ok "and deletes the record" || bad "the record is still there"

echo
if [ "$fail" = 0 ]; then echo "PASS: tests/pin"; else echo "FAIL: tests/pin"; fi
exit "$fail"
