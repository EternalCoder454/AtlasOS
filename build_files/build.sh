#!/usr/bin/env bash
# Turns stock Fedora Kinoite into AtlasOS, part 3 of 4: services, settings and
# branding, after packages.sh and apps.sh. Runs in the Containerfile's third
# RUN step, with the repo's build context at /ctx and the rendered branding at
# /branding. The image's version goes into os-release last, in a step of its
# own (version.sh), so a new date alone doesn't rerun this.
set -euxo pipefail
: >/tmp/atlasos-step-start # (see cleanup.sh, "Times")

### Services

# dnf can't change an image-based system, so refreshing its metadata in the
# background only costs memory, disk and bandwidth.
systemctl disable dnf-makecache.timer

# Background update checks stage an update and never apply it:
# atlasos-update-stage.timer runs `bootc upgrade` (download and stage, no
# reboot). The two timers that apply or reboot by themselves stay off.
systemctl disable bootc-fetch-apply-updates.timer rpm-ostreed-automatic.timer

# Power profiles come from power-profiles-daemon (swapped in by packages.sh).
[ "$(systemctl is-enabled power-profiles-daemon.service)" = enabled ]
for p in tuned tuned-ppd xwaylandvideobridge kunifiedpush mariadb-server; do
	if rpm -q "$p" >/dev/null 2>&1; then
		echo "build.sh: $p must not be installed" >&2
		exit 1
	fi
done

### Branding

# Modes come from the checkout: a file a local checkout made private would
# ship private, so that fails the build.
unreadable=$(find /ctx/system_files ! -type l ! -perm -o=r)
[ -z "$unreadable" ] || {
	echo "build.sh: not readable by everyone: $unreadable" >&2
	exit 1
}
cp -a /ctx/system_files/. /

# Atlas Updater is the only update notifier and the only OS updater.
# Discover's notifier and OS backend (removed by packages.sh) and every other
# background updater stay out, and Discover never updates on its own.
[ ! -e /usr/libexec/DiscoverNotifier ]
[ -z "$(find /etc/xdg/autostart /usr/share/applications -iname '*discover*notifier*' -print -quit)" ]
for p in plasma-discover-notifier plasma-discover-rpm-ostree PackageKit; do
	if rpm -q "$p" >/dev/null 2>&1; then
		echo "build.sh: $p must not be installed" >&2
		exit 1
	fi
done
grep -qx 'UseUnattendedUpdates=false' /etc/xdg/PlasmaDiscoverUpdates

# Image signatures. CI signs every AtlasOS image with cosign (the key pair's
# public half is cosign.pub in the repo); bootc, rpm-ostree and Podman accept
# ghcr.io/eternalcoder454/atlasos and atlasos-nvidia only with a signature
# from it, found as a sigstore attachment beside the image
# (/etc/containers/registries.d/atlasos.yaml). That holds for every pull,
# whatever an install's origin says; the update stager also records it in
# the origin (libexec/atlasos/update-stage). Every other image is accepted as
# before:
# bootc --enforce-container-sigpolicy wants a default that rejects, so each
# transport accepts anything instead. Built on Fedora's policy, whose own
# entries stay. keyPaths takes a list: a new key goes in beside the old one
# (DEV.md) before images are signed with it.
install -Dpm0644 /ctx/cosign.pub /etc/pki/containers/atlasos.pub
policy=/etc/containers/policy.json
jq --arg key /etc/pki/containers/atlasos.pub '
	{type: "sigstoreSigned", keyPaths: [$key], signedIdentity: {type: "matchRepository"}} as $signed
	| .default = [{type: "reject"}]
	| reduce ("docker", "docker-archive", "docker-daemon", "oci", "oci-archive",
		"dir", "containers-storage", "sif", "tarball") as $t
		(.; .transports[$t][""] //= [{type: "insecureAcceptAnything"}])
	| .transports.docker["ghcr.io/eternalcoder454/atlasos"] = [$signed]
	| .transports.docker["ghcr.io/eternalcoder454/atlasos-nvidia"] = [$signed]
' "$policy" >"$policy.new"
mv "$policy.new" "$policy"
chmod 0644 "$policy"
jq -e '.transports.docker[""][0].type == "insecureAcceptAnything"
	and .transports.docker["ghcr.io/eternalcoder454/atlasos"][0].type == "sigstoreSigned"' "$policy" >/dev/null
grep -q 'use-sigstore-attachments: true' /etc/containers/registries.d/atlasos.yaml

# `atlas`, the command menu: the file it runs has to parse.
just --justfile /usr/share/atlasos/atlas.just --list >/dev/null
[ -x /usr/bin/atlas ]
[ -x /usr/lib/systemd/user-environment-generators/20-atlasos-hybrid-gpu ]

# The kernel sizes the inotify watch limit by RAM; this raises it to 524288
# where it is lower (IDEs and file watchers run out), and never lowers it.
systemctl enable atlasos-inotify-watches.service
systemctl enable atlasos-update-stage.timer
# The man page index waits until 10 minutes after boot instead of holding up
# multi-user.target, and is only made again when the packages changed (see
# the unit's drop-in). After an update, the library cache is only rebuilt
# when it differs from the image's (ldconfig.service.d).
systemctl disable fedora-atomic-desktop-mandb-update.service
systemctl enable atlasos-mandb.timer
[ -x /usr/libexec/atlasos/ldconfig-needed ]
[ -x /usr/libexec/atlasos/mandb-needed ]
# systemd-homed manages portable home folders, which AtlasOS doesn't use
# (accounts are ordinary ones in /etc/passwd), so it doesn't run all the time.
systemctl disable systemd-homed.service systemd-homed-activate.service
for u in fedora-atomic-desktop-mandb-update.service systemd-homed.service; do
	[ "$(systemctl is-enabled "$u")" = disabled ] || {
		echo "build.sh: $u must be disabled" >&2
		exit 1
	}
done
[ "$(systemctl is-enabled atlasos-mandb.timer)" = enabled ]
# zstd compression on a btrfs system disk (see the script).
systemctl enable atlasos-btrfs-compress.service
[ "$(systemctl is-enabled atlasos-btrfs-compress.service)" = enabled ]
# Records each newly booted image in /var/lib/atlas-core/history.jsonl. The
# system helper is D-Bus activated and must stay that way: nothing runs at idle.
systemctl enable atlas-record-boot.service
[ "$(systemctl is-enabled atlas-record-boot.service)" = enabled ]
[ "$(systemctl is-enabled atlas-system-helper.service 2>&1 || true)" != enabled ]
[ -f /usr/share/dbus-1/system-services/net.eterneon.atlas.SystemHelper.service ]
# greenboot's units. The package's scriptlets enable nothing while building.
# The boot counter in GRUB reaches existing installs through
# atlasos-grub-greenboot.service (see the README).
systemctl enable greenboot-healthcheck.service greenboot-set-rollback-trigger.service
systemctl enable atlasos-grub-greenboot.service
for u in greenboot-healthcheck.service greenboot-set-rollback-trigger.service atlasos-grub-greenboot.service; do
	[ "$(systemctl is-enabled "$u")" = enabled ] || {
		echo "build.sh: $u must be enabled" >&2
		exit 1
	}
done
grep -qx 'GREENBOOT_MAX_BOOT_ATTEMPTS=3' /etc/greenboot/greenboot.conf
# Still ending in the newline packages.sh added (see there).
snippet=/usr/lib/bootupd/grub2-static/configs.d/08_greenboot.cfg
[ -f "$snippet" ]
[ -z "$(tail -c1 "$snippet")" ]
# The AtlasOS checks are image-owned, in /usr/lib/greenboot (greenboot reads it
# before /etc/greenboot); each must run, and each helper script must parse.
for f in /usr/lib/greenboot/check/required.d/*.sh /usr/lib/greenboot/red.d/*.sh /usr/lib/greenboot/green.d/*.sh; do
	[ -x "$f" ] && bash -n "$f"
done
[ "$(find /usr/lib/greenboot/check/required.d -name '*.sh' | wc -l)" -eq 3 ]
[ -f /usr/lib/systemd/system/greenboot-healthcheck.service.d/atlasos.conf ]
# Flathub as a system remote (system_files/usr/share/flatpak/remotes.d), and
# the Flatpaks in preinstall.d installed in the background after boot.
systemctl enable atlasos-flatpak-preinstall.timer
# kconf_update runs AtlasOS's settings updates at each Plasma login (kded6's
# own run skips them: ostree's mtime 0 looks unchanged).
systemctl --global enable atlasos-kconf-update.service
[ -x /usr/libexec/kf6/kconf_update ] || {
	echo "build.sh: /usr/libexec/kf6/kconf_update is missing" >&2
	exit 1
}
# kconf_update scripts and helpers must keep their execute bit.
for f in /usr/share/kconf_update/atlasos-*.sh /usr/libexec/atlasos/*; do
	# Python modules the helpers import (pinlib.py) aren't run themselves
	case $f in *.py) continue ;; esac
	[ -x "$f" ] || {
		echo "build.sh: $f is not executable" >&2
		exit 1
	}
done
# Application style: Kvantum (installed by packages.sh) with the AtlasOS
# themes; kvantum-sync picks one at login and when kdeglobals or atlasrc change.
[ -f /usr/lib64/qt6/plugins/styles/libkvantum.so ] || {
	echo "build.sh: the Kvantum Qt6 style plugin is missing" >&2
	exit 1
}
for t in AtlasOS AtlasOSDark AtlasOSSolid AtlasOSDarkSolid; do
	[ -f "/usr/share/Kvantum/$t/$t.kvconfig" ]
	[ -f "/usr/share/Kvantum/$t/$t.svg" ]
done
# The service runs once at login, the path unit on every change after that.
systemctl --global enable atlasos-kvantum-sync.service atlasos-kvantum-sync.path
[ -x /usr/libexec/atlasos/kvantum-sync ]
# Meta+M: menubar-toggle talks to Plasma through qdbus-qt6, and kglobalaccel
# reads the shortcut from the link to its desktop file.
command -v qdbus-qt6 >/dev/null || {
	echo "build.sh: qdbus-qt6 (used by menubar-toggle) is missing" >&2
	exit 1
}
[ -f /usr/share/kglobalaccel/org.atlasos.menubar-toggle.desktop ]
# Notifications drop down at the top centre of the screen, just under the
# clock island; KWin's built-in Sliding Notifications effect slides them down
# from the top edge. Left "near the notification icon" (Plasma's default),
# they get only the width of the panel the icon is on: the tray island is
# narrower than a notification, so Plasma centres it on the island and a
# third of it is off the screen. Added to plasma-workspace's own file, which
# keeps its other defaults. (A user's choice in System Settings,
# Notifications, still wins.)
if grep -q '^\[Notifications\]' /etc/xdg/plasmanotifyrc; then
	echo "build.sh: plasmanotifyrc now has a [Notifications] group; set PopupPosition in it" >&2
	exit 1
fi
printf '\n# AtlasOS (build.sh): see there.\n[Notifications]\nPopupPosition=TopCenter\n' >>/etc/xdg/plasmanotifyrc

# KRunner, Plasma's separate search bar (Alt+Space), is retired: the
# launcher's search is the one search. Andromeda runs KRunner's plugins in its
# own process through the KRunner library, which stays, with the plugins.
# Without its global-shortcuts file kglobalaccel gives KRunner no keys
# (Alt+Space, Alt+F2, Search, Alt+Shift+F2); without the program, its D-Bus
# activation and its user unit (masked), nothing can start it. A plain rm:
# the build fails if plasma-workspace moves one of them.
rm /usr/bin/krunner /usr/share/kglobalaccel/org.kde.krunner.desktop \
	/usr/share/dbus-1/services/org.kde.krunner.service /usr/share/zsh/site-functions/_krunner
systemctl --global mask plasma-krunner.service
# (Settings' Plasma Search page, kcm_krunnersettings, stays: it picks the
# launcher's search plugins.)
# Nothing else may start it or bind keys to it. (An assignment, so a find
# error, such as a folder gone, fails the build too.)
krunner_left=$(find /usr/share/kglobalaccel /usr/share/applications /etc/xdg/autostart \
	/usr/share/dbus-1/services -iname 'org.kde.krunner*' -print -quit)
[ -z "$krunner_left" ]
[ "$(systemctl --global is-enabled plasma-krunner.service)" = masked ]
# Every script in the .upd has to exist, and every Id has to be unique.
while IFS=, read -r script _; do
	[ -x "/usr/share/kconf_update/${script#Script=}" ]
done < <(grep '^Script=' /usr/share/kconf_update/atlasos.upd)
dup=$(grep '^Id=' /usr/share/kconf_update/atlasos.upd | sort | uniq -d)
[ -z "$dup" ]
[ -f /usr/share/flatpak/remotes.d/flathub.flatpakrepo ]
[ -f /usr/share/flatpak/preinstall.d/atlasos.preinstall ]
# Nothing may apply an update or reboot unattended (bootc-fetch-apply-updates
# runs `bootc upgrade --apply`; rpm-ostreed-automatic can stage and reboot).
for t in bootc-fetch-apply-updates.timer rpm-ostreed-automatic.timer; do
	[ "$(systemctl is-enabled "$t")" = disabled ] || {
		echo "build.sh: $t must stay disabled" >&2
		exit 1
	}
done
[ "$(systemctl is-enabled atlasos-update-stage.timer)" = enabled ]
grep -qx 'ExecStart=/usr/libexec/atlasos/update-stage' /usr/lib/systemd/system/atlasos-update-stage.service
# rpm-ostree upgrades (and the stager checks) a system with local rpm-ostree changes
rpm -q rpm-ostree skopeo >/dev/null

# Fingerprint readers: fprintd and libfprint ship in the image, so the only
# switch is authselect's with-fingerprint (as on Fedora Workstation). It puts
# pam_fprintd first in system-auth (sudo, polkit) and in fingerprint-auth (the
# lock screen's kde-fingerprint, which runs beside its password check).
# pam_fprintd gives up at once with no reader, or with no finger enrolled for
# the user, so the password prompt is unchanged there. password-auth stays
# without it: the login screen (the wallet unlocks with the password) and the
# lock screen's password check (kde), which would otherwise wait for a finger
# before asking for the password.
# fprintd is D-Bus activated, so nothing runs at idle. The first-login prompt
# is atlasos-fingerprint-setup (see DEV.md).
authselect enable-feature with-fingerprint
authselect check
grep -q 'pam_fprintd.so' /etc/pam.d/system-auth
grep -q 'pam_fprintd.so' /etc/pam.d/fingerprint-auth
if grep -q 'pam_fprintd.so' /etc/pam.d/password-auth; then
	echo "build.sh: password-auth must not use pam_fprintd" >&2
	exit 1
fi
rpm -q fprintd fprintd-pam >/dev/null
# Firewall: the AtlasOS zone (system_files/usr/lib/firewalld/zones) is the
# default in place of Fedora Workstation's, which accepts anything on ports
# 1025-65535. firewalld.conf is a link to the workstation file; an install
# that never changed it gets this on its next update.
conf=$(readlink -f /etc/firewalld/firewalld.conf)
sed -i 's/^DefaultZone=.*/DefaultZone=AtlasOS/' "$conf"
grep -qx 'DefaultZone=AtlasOS' "$conf"
firewall-offline-cmd --check-config >/dev/null
[ "$(firewall-offline-cmd --get-default-zone)" = AtlasOS ]
firewall-offline-cmd --zone=AtlasOS --list-ports | grep -q . && {
	echo "build.sh: the AtlasOS firewall zone must open no port ranges" >&2
	exit 1
}
# LLMNR off (system_files/usr/lib/systemd/resolved.conf.d)
grep -qx 'LLMNR=no' /usr/lib/systemd/resolved.conf.d/50-atlasos.conf

# The rule update-stage and its condition use to refuse an older image
# (a tag that went back): it has to load and answer right
[ "$(jq -n "$(cat /usr/share/atlasos/image-age.jq)"'
	[older({version: "44.20261001"}; {version: "44.20261002-1"}),
	 older({version: "44.20261003"}; {version: "44.20261002"})]' -c)" = '[true,false]' ]
# Smart cards: readers work (pcscd starts on first use through its socket,
# opensc supplies the drivers for browsers, ssh and gpg). Logging in with one
# needs authselect's sssd profile and pam_pkcs11, which the local profile
# lacks and a home PC has no use for, so smartcard-auth stays unavailable.
rpm -q pcsc-lite pcsc-lite-ccid opensc >/dev/null
[ "$(systemctl is-enabled pcscd.socket)" = enabled ]
[ -x /usr/libexec/atlasos/fingerprint-setup ]
[ -f /etc/xdg/autostart/atlasos-fingerprint-setup.desktop ]

# Sign-in PIN (DEV.md, "PIN sign-in"): at the login screen and the lock screen
# only, 4 to 8 digits typed in the password field. authselect stays in charge:
# a custom profile, atlasos, based on local, adds a with-pin feature to
# password-auth (the login screen's and the lock screen's stack, and also
# sshd's, so the module acts only for the services kde and plasmalogin).
# system-auth (sudo, polkit, su) is untouched. Every other file of the profile
# is a symlink to local's, so authselect updates still reach it.
# pam_unix gets the typed text first; pam_atlasos_pin (build_files/pam-pin/,
# C, built by the Containerfile) takes the same text (the existing
# PAM_AUTHTOK, never a second prompt) to atlasos-pin.socket: the lock screen
# runs as the user and can't read the root-only hashes. On a correct PIN it
# CLEARS PAM_AUTHTOK, so the wallet and keyring modules after the stack don't
# take the PIN for the password. It also answers pam_setcred (which the login
# screen calls after a PIN login, and pam_unix answers with its saved failure)
# and, in the session stack, clears the wrong-PIN count after a login by
# password. Everywhere else it returns PAM_IGNORE.
install -m 0755 /pam-pin/pam_atlasos_pin.so /usr/lib64/security/pam_atlasos_pin.so
authselect create-profile atlasos -b local --symlink-nsswitch --symlink-pam --symlink-dconf
profile=/etc/authselect/custom/atlasos
# The copy below is only right for the password-auth it was written against:
# when authselect's local profile changes, the build stops here so someone
# looks at what changed and updates the lines and this checksum.
local_pa=/usr/share/authselect/default/local/password-auth
echo "a3e41a8e381058b92d8e31b6b42ce4c074017978d15967c30afcce8ce6466ece  $local_pa" | sha256sum -c --quiet || {
	echo "build.sh: authselect's local password-auth changed; check the with-pin lines against it" >&2
	exit 1
}
rm "$profile/password-auth"
cp "$local_pa" "$profile/password-auth"
python3 - "$profile" <<'PYEOF'
import sys
profile = sys.argv[1]
path = profile + "/password-auth"
text = open(path).read()
unix = '{if not "without-nullok":nullok}'
edits = [
    ("auth        sufficient                                   pam_unix.so " + unix + "\n",
     "auth        sufficient                                   pam_unix.so " + unix + " try_first_pass\n"
     "auth        [default=1 success=ignore]                   pam_succeed_if.so quiet service in kde:plasmalogin {include if \"with-pin\"}\n"
     "auth        sufficient                                   pam_atlasos_pin.so {include if \"with-pin\"}\n"),
    ("session     required                                     pam_unix.so\n",
     "session     required                                     pam_unix.so\n"
     "session     optional                                     pam_atlasos_pin.so {include if \"with-pin\"}\n"),
]
for old, new in edits:
    if text.count(old) != 1:
        sys.exit(f"build.sh: password-auth line not found once in the local profile: {old!r}")
    text = text.replace(old, new)
open(path, "w").write(text)
readme = open(profile + "/README").read()
old = "with-silent-lastlog::\n"
if readme.count(old) != 1:
    sys.exit("build.sh: with-silent-lastlog not found once in the local profile's README")
readme = readme.replace(old, "with-pin::\n    Sign in and unlock the screen with a PIN (AtlasOS: login and lock screen only).\n\n" + old)
open(profile + "/README", "w").write(readme)
PYEOF
# Apart from our lines, the profile's password-auth is local's, byte for byte
if ! diff <(grep -v -e 'pam_atlasos_pin' -e 'pam_succeed_if.so quiet service in' "$profile/password-auth" |
	sed 's/ try_first_pass$//') "$local_pa"; then
	echo "build.sh: the atlasos password-auth differs from local's beyond the with-pin lines" >&2
	exit 1
fi
# The login screen's own stack runs the wallet and keyring modules after
# password-auth. After a PIN login the token is gone (cleared on purpose), and
# pam_kwallet5 would prompt for the password a second time; the PIN must not
# reach them either. So /etc/pam.d/plasmalogin is the vendor file with one
# line added: after a PIN login, jump over those modules. (KWallet then asks
# for the password itself, once.) The build fails if the vendor file is not
# the shape this expects.
python3 - <<'PYEOF3'
import re, sys
src = open("/usr/lib/pam.d/plasmalogin").read().split("\n")
sub = [i for i, l in enumerate(src) if re.match(r"auth\s+substack\s+password-auth\s*$", l)]
if len(sub) != 1:
    sys.exit("build.sh: plasmalogin's pam file has no single 'auth substack password-auth'")
i = sub[0]
wallet = src[i + 1:i + 5]
if len(wallet) != 4 or not all(re.match(r"-auth\s+optional\s+pam_(gnome_keyring|kwallet5|kwallet|oo7)\.so\s*$", l) for l in wallet):
    sys.exit(f"build.sh: plasmalogin's pam file: expected the four keyring and wallet auth lines after password-auth, got {wallet}")
src.insert(i + 1, "auth        [success=4 default=ignore]   pam_atlasos_pin.so pinlogin")
open("/etc/pam.d/plasmalogin", "w").write("\n".join(src))
PYEOF3
features=$(authselect current --raw | cut -d' ' -f2-)
# shellcheck disable=SC2086  # one word per feature
authselect select custom/atlasos $features with-pin --force
systemctl enable atlasos-pin.socket
[ "$(systemctl is-enabled atlasos-pin.socket)" = enabled ]
authselect check
authselect current | grep -qx 'Profile ID: custom/atlasos'
authselect current | grep -qx -- '- with-pin'
authselect current | grep -qx -- '- with-silent-lastlog'
authselect current | grep -qx -- '- with-mdns4'
# The switch to custom/atlasos keeps the fingerprint set up above
authselect current | grep -qx -- '- with-fingerprint'
grep -q 'pam_fprintd.so' /etc/pam.d/system-auth
grep -q 'pam_fprintd.so' /etc/pam.d/fingerprint-auth
if grep -q 'pam_fprintd.so' /etc/pam.d/password-auth; then
	echo "build.sh: password-auth must not use pam_fprintd" >&2
	exit 1
fi
grep -q '^auth .*pam_unix.so .*try_first_pass' /etc/pam.d/password-auth
[ -x /usr/lib64/security/pam_atlasos_pin.so ]
grep -qx 'auth        \[success=4 default=ignore\]   pam_atlasos_pin.so pinlogin' /etc/pam.d/plasmalogin
[ "$(grep -c pam_atlasos_pin /etc/pam.d/plasmalogin)" = 1 ]
# The order is the security: pam_unix, the service gate, the PIN module and
# pam_deny, one right after the other in the auth stack, and the module once
# in auth and once in session.
python3 - /etc/pam.d/password-auth <<'PYEOF2'
import sys
lines = [l.split() for l in open(sys.argv[1]) if l.strip() and not l.lstrip().startswith("#")]
auth = [l for l in lines if l[0] == "auth"]
mods = [next(w for w in l[2:] if w.endswith(".so")) for l in auth]
want = ["pam_unix.so", "pam_succeed_if.so", "pam_atlasos_pin.so", "pam_deny.so"]
if mods.count("pam_atlasos_pin.so") != 1:
    sys.exit("build.sh: password-auth must have one pam_atlasos_pin auth line")
i = mods.index("pam_atlasos_pin.so") - 2
if i < 0 or mods[i:i + 4] != want:
    sys.exit(f"build.sh: password-auth auth order is {mods}, expected {want} in a row")
if "pam_succeed_if.so" != mods[i + 1] or "kde:plasmalogin" not in auth[i + 1] or auth[i][1] != "sufficient" or auth[i + 2][1] != "sufficient":
    sys.exit("build.sh: password-auth's PIN lines have the wrong gate or controls")
if sum(1 for l in lines if l[0] == "session" and "pam_atlasos_pin.so" in l) != 1:
    sys.exit("build.sh: password-auth must have one pam_atlasos_pin session line")
if any("pin-auth" in w or "pin-session" in w for l in lines for w in l):
    sys.exit("build.sh: password-auth still runs the old PIN helpers")
PYEOF2
# Not in system-auth: sudo, polkit and su never take the PIN
if grep -q 'pam_atlasos_pin\|pin-auth\|pin-session' /etc/pam.d/system-auth; then
	echo "build.sh: system-auth must not use the PIN" >&2
	exit 1
fi
for f in pin-admin pin-daemon pin-setup; do
	[ -x "/usr/libexec/atlasos/$f" ]
done
[ -f /usr/libexec/atlasos/pinlib.py ]
[ -f /usr/lib/systemd/system/atlasos-pin@.service ]
grep -qx 'ListenStream=/run/atlasos/pin.sock' /usr/lib/systemd/system/atlasos-pin.socket
grep -qx 'd /var/lib/atlasos/pin 0700 root root -' /usr/lib/tmpfiles.d/atlasos-pin.conf
[ -f /usr/share/polkit-1/actions/org.atlasos.pin.policy ]
# polkitd reads only *.policy: an action file named otherwise is ignored and
# its prompt falls back to the generic administrator one.
if find /usr/share/polkit-1/actions -name 'org.atlasos.*' ! -name '*.policy' | grep -q .; then
	echo "build.sh: a polkit action file not named *.policy" >&2
	exit 1
fi
[ -f /usr/share/applications/atlasos-pin-setup.desktop ]
[ -f /etc/xdg/autostart/atlasos-pin-setup.desktop ]
python3 -c 'import ctypes; ctypes.CDLL("libcrypt.so.2").crypt_gensalt'
# The SELinux module (selinux/, compiled by the Containerfile's selinux-policy
# stage): the login screen's domain (xdm_t) may connect to the verifier's
# socket, and the verifier runs in its own domain.
# atlasos_bootc: bootc and ostree get install_t when a service runs them
# (selinux/atlasos_bootc.te, DEV.md "Updates"). One transaction for both.
semodule -i /selinux/atlasos_pin.pp -i /selinux/atlasos_bootc.pp
semodule -l | grep -qx atlasos_pin
semodule -l | grep -qx atlasos_bootc

# Icons and logos rendered from branding/ (see branding/render.sh)
cp -a /branding/icons/. /usr/share/icons/
cp -a /branding/pixmaps/. /usr/share/pixmaps/
cp -a /branding/wallpapers/. /usr/share/wallpapers/
# Cursors: Bibata Modern Ice (light) and Classic (dark), see
# branding/cursors/README.md. They replace Breeze's, whose files go:
# plasma-integration requires the breeze-cursor-theme package, so it stays
# installed, empty. "default" is the cursor anything without its own setting
# uses (X11 apps, the login screen before Plasma's settings load).
# The archives must be the release's own (sums in that README), and hold only
# their theme's folder.
sha256sum -c - <<'EOF'
a68cae60c4dc706350e194ebc91c5fe48bc7bc9d59e119555834a2a7ee5078ef  /ctx/cursors/Bibata-Modern-Ice.tar.xz
7d3495864e5bbef02f5e77de760b2905903b63c71495a78ef6306d19a3b556d8  /ctx/cursors/Bibata-Modern-Classic.tar.xz
EOF
for c in Bibata-Modern-Ice Bibata-Modern-Classic; do
	# Listings read into variables first: grep -q closing a pipe early would
	# kill tar with SIGPIPE under pipefail.
	names=$(tar -tJf "/ctx/cursors/$c.tar.xz")
	details=$(tar -tvJf "/ctx/cursors/$c.tar.xz")
	# Only files, folders and the cursor aliases: symlinks to a file in the
	# same folder (arrow -> left_ptr). No hard links, devices or fifos.
	if grep -v "^$c/" <<<"$names" | grep -q . ||
		grep -qE '(^|/)\.\.(/|$)' <<<"$names" ||
		grep -qv '^[-dl]' <<<"$details" ||
		grep '^l' <<<"$details" | grep -qvE ' -> [A-Za-z0-9_.+-]+$'; then
		echo "build.sh: $c.tar.xz has files outside $c/, or links that leave their folder" >&2
		exit 1
	fi
	tar -xJf "/ctx/cursors/$c.tar.xz" -C /usr/share/icons --no-same-owner --no-same-permissions
	[ -f "/usr/share/icons/$c/cursors/left_ptr" ] && [ -f "/usr/share/icons/$c/index.theme" ]
done
install -Dm644 /ctx/cursors/LICENSE /usr/share/licenses/bibata-cursor-themes/LICENSE
rm -r /usr/share/icons/breeze_cursors /usr/share/icons/Breeze_Light
grep -qx 'Inherits=Adwaita' /usr/share/icons/default/index.theme
sed -i 's/^Inherits=Adwaita$/Inherits=Bibata-Modern-Ice/' /usr/share/icons/default/index.theme
# Nothing may still point at Breeze's cursors.
if grep -rIl -e breeze_cursors -e Breeze_Light /etc/xdg /usr/share/plasma/look-and-feel/org.atlasos*; then
	echo "build.sh: settings above still name Breeze's cursors" >&2
	exit 1
fi
# Icons: Papirus (Fedora's papirus-icon-theme and -dark, installed by
# packages.sh) for AtlasOS Light and Papirus-Dark for AtlasOS Dark, picked by
# each global theme's defaults. Both follow the colour scheme in their panel
# and symbolic icons, and fall back to Breeze (Papirus) and Breeze Dark.
icon_themes=(/usr/share/icons/Papirus /usr/share/icons/Papirus-Dark)
for t in "${icon_themes[@]}"; do
	[ -f "$t/index.theme" ]
done
# Folders in violet, to match the accent: what papirus-folders does. Each
# places/ dir has folder-*.svg (and user-*.svg, the home folder) links to the
# folder-blue-* files (the default); point them at the -violet- ones. Papirus-Dark has its own places/ in the
# smallest sizes and links to Papirus's for the rest; find doesn't follow those.
violet=0
while IFS= read -r -d '' link; do
	target=$(readlink "$link" | sed -E 's/^(folder|user)-blue([-.])/\1-violet\2/')
	[ -e "$(dirname "$link")/$target" ]
	ln -sfn "$target" "$link"
	violet=$((violet + 1))
done < <(find "${icon_themes[@]}" -path '*/places/*' -type l \( -lname 'folder-blue[-.]*' -o -lname 'user-blue[-.]*' \) -print0)
[ "$violet" -gt 300 ]
[ "$(readlink /usr/share/icons/Papirus/48x48/places/folder.svg)" = folder-violet.svg ]
[ "$(readlink /usr/share/icons/Papirus-Dark/48x48/places/folder.svg)" = folder-violet.svg ]
if find "${icon_themes[@]}" -path '*/places/*' -type l \( -lname 'folder-blue[-.]*' -o -lname 'user-blue[-.]*' \) | grep .; then
	echo "build.sh: the folder links above are still blue" >&2
	exit 1
fi
# Apps AtlasOS ships whose own icons are in other styles (Brave's under the
# name brave-origin, Ghostty's a photo-like screen): Papirus's for them too,
# in every size directory that has the icon and lacks one under that name.
for alias in brave-origin:brave-browser com.mitchellh.ghostty:utilities-terminal; do
	[ -e "/usr/share/icons/Papirus/48x48/apps/${alias#*:}.svg" ]
	while IFS= read -r -d '' dir; do
		if [ -e "$dir/${alias#*:}.svg" ] && [ ! -e "$dir/${alias%%:*}.svg" ]; then
			ln -sfn "${alias#*:}.svg" "$dir/${alias%%:*}.svg"
		fi
	done < <(find "${icon_themes[@]}" -type d -name apps -print0)
done
[ -e /usr/share/icons/Papirus/48x48/apps/brave-origin.svg ]
[ -e /usr/share/icons/Papirus-Dark/16x16/apps/com.mitchellh.ghostty.svg ]
# Every user must be able to read them (tar keeps the archive's modes).
if find "${icon_themes[@]}" /usr/share/icons/Bibata-Modern-* ! -type l ! -perm -o=r | grep .; then
	echo "build.sh: the icon or cursor files above are not readable by everyone" >&2
	exit 1
fi
# "Default" is the wallpaper anything without its own setting falls back to.
# The first-run wizard loads two files from it by name; branding/render.sh
# makes those too. It replaces Fedora's own "Default" link to F44.
ln -sfn AtlasOS /usr/share/wallpapers/Default
# What else the wallpaper picker lists: Fedora's F44 set (9 MiB), Breeze's
# "Next" (plasma-breeze-common has to stay for its icons and styles),
# kde-settings's "Fedora" link to "Default" and /usr/share/backgrounds. Only the
# pictures go: kde-settings-plasma requires the F44 packages (as
# system-backgrounds-kde), and removing them would leave that requirement unmet
# for every later dnf and rpm-ostree call. kde-settings also names "Fedora" for
# the lock screen of users without our setting (a profile that
# /etc/xdg/kscreenlockerrc overrides): point that at ours.
rm -rf /usr/share/wallpapers/F44 /usr/share/wallpapers/Next /usr/share/wallpapers/Fedora \
	/usr/share/backgrounds
ks=/usr/share/kde-settings/kde-profile/default/xdg/kscreenlockerrc
grep -q 'wallpapers/Fedora/' "$ks"
sed -i 's|wallpapers/Fedora/|wallpapers/AtlasOS-Login/|' "$ks"
# The picker shows only AtlasOS's own: fail if a package brings another back.
[ ! -e /usr/share/backgrounds ]
for w in /usr/share/wallpapers/*; do
	case "${w##*/}" in
	AtlasOS | AtlasOS-Login | Default) ;;
	*)
		echo "build.sh: $w is in the wallpaper picker, and is not AtlasOS's" >&2
		exit 1
		;;
	esac
done

# os-release: AtlasOS on top of Fedora 44. VERSION_ID stays Fedora's so
# anything that keys on the release (dnf, toolbox, bootc-image-builder) still
# sees 44. The image's version (VERSION and IMAGE_VERSION) is "dev" here;
# version.sh puts the real one in, in the Containerfile's last step, so the
# initramfs's copy (initrd-release) keeps "dev".
# shellcheck source=/dev/null
support_end=$(. /usr/lib/os-release && echo "${SUPPORT_END:-}")
cat >/usr/lib/os-release <<EOF
NAME="AtlasOS"
VERSION="44 (dev)"
ID=atlasos
ID_LIKE=fedora
VERSION_ID=44
VERSION_CODENAME=""
PLATFORM_ID="platform:f44"
PRETTY_NAME="AtlasOS 44"
ANSI_COLOR="0;38;2;114;98;234"
LOGO=atlasos
DEFAULT_HOSTNAME="atlasos"
HOME_URL="https://github.com/EternalCoder454/AtlasOS"
BUG_REPORT_URL="https://github.com/EternalCoder454/AtlasOS/issues"
SUPPORT_END=${support_end}
VARIANT="Desktop"
VARIANT_ID=desktop
IMAGE_ID=atlasos
IMAGE_VERSION="dev"
EOF

# system-release (what /etc/system-release and /etc/redhat-release read; the
# RPM database's system-release is a package name and doesn't change): the
# release line of AtlasOS in place of fedora-release's "Fedora release 44".
# /etc/fedora-release stays Fedora's, for whatever checks it. version.sh puts
# the image's version in place of "dev", as in os-release.
echo "AtlasOS release 44 (dev)" >/usr/lib/atlasos-release
ln -sfn ../usr/lib/atlasos-release /etc/system-release
ln -sfn ../usr/lib/atlasos-release /etc/redhat-release

# Fail rather than ship half-branded when Fedora moves something these edits
# rely on: each one checks the text it replaces is still there.
replace() { # file, old, new
	grep -qF -- "$2" "$1" || {
		echo "build.sh: '$2' not found in $1" >&2
		exit 1
	}
	# Escape both texts so sed treats them literally, as grep -F did.
	local old new
	old=$(printf '%s' "$2" | sed 's/[][\\.*^$|]/\\&/g')
	new=$(printf '%s' "$3" | sed 's/[\\&|]/\\&/g')
	sed -i "s|$old|$new|g" "$1"
}

# Two Global Themes, AtlasOS Light (org.atlasos.desktop, the default in
# /etc/xdg/kdeglobals) and AtlasOS Dark (org.atlasos.dark.desktop). Each is
# our metadata, defaults and layout (menu bar and dock) from system_files,
# completed with Fedora's theme and then Breeze for every file we don't have.
# Complete, because Plasma looks up missing files in Breeze's theme, which is
# removed below.
themes=/usr/share/plasma/look-and-feel
cp -a "$themes/org.atlasos.desktop/contents/layouts" "$themes/org.atlasos.dark.desktop/contents/"
for t in org.atlasos.desktop:org.fedoraproject.fedora.desktop:org.kde.breeze.desktop \
	org.atlasos.dark.desktop:org.fedoraproject.fedoradark.desktop:org.kde.breezedark.desktop; do
	IFS=: read -r ours fedora breeze <<<"$t"
	cp -a --update=none "$themes/$fedora/." "$themes/$ours/"
	cp -a --update=none "$themes/$breeze/." "$themes/$ours/"

	# App launcher icon for Kickoff, Kicker and Dashboard added later by hand
	# (the taskbar's own start button gets it from the layout script)
	for f in "$themes/$ours"/contents/plasmoidsetupscripts/org.kde.plasma.{kickoff,kicker,kickerdash}.js; do
		replace "$f" '"icon", "start-here"' '"icon", "atlasos"'
	done

	# Plasma splash: Fedora's splash, with the AtlasOS mark in place of
	# Plasma's. The "Plasma made by KDE" credit in the corner stays.
	cp /branding/splash/atlasos.svg "$themes/$ours/contents/splash/images/atlasos.svg"
	replace "$themes/$ours/contents/splash/Splash.qml" \
		'source: "images/plasma.svgz"' 'source: "images/atlasos.svg"'
done

# The AtlasOS themes are the only ones: no other Global Themes, colour
# schemes or Plasma Styles. ("default" is the Plasma Style that follows the
# colour scheme, so it is AtlasOS Light or Dark.)
for t in "$themes"/*; do
	case ${t##*/} in
	org.atlasos.desktop | org.atlasos.dark.desktop) ;;
	*) rm -r "$t" ;;
	esac
done
find /usr/share/color-schemes -name '*.colors' ! -name 'AtlasOS*.colors' -delete
rm -r /usr/share/plasma/desktoptheme/breeze-dark /usr/share/plasma/desktoptheme/breeze-light
# The AtlasOS Plasma style (system_files) is Breeze with its own dock
# indicators (widgets/tasks.svg); everything else falls back to "default".
# Breeze's settings (blur behind panels and popups) come along.
cp /usr/share/plasma/desktoptheme/default/plasmarc /usr/share/plasma/desktoptheme/atlasos/plasmarc
# Copied symlinks that pointed into a removed theme would now break quietly.
dangling=$(find "$themes" /usr/share/plasma/desktoptheme -xtype l)
[ -z "$dangling" ] || {
	echo "build.sh: broken links after removing themes:" >&2
	echo "$dangling" >&2
	exit 1
}

# AtlasOS Light's colours for every KDE program that runs outside a Plasma
# session too, the login screen above all. A user's own theme choice is
# written to their kdeglobals and overrides these.
awk '/^\[/ { keep = /^\[(Colors:|ColorEffects:|WM\])/ } keep' \
	/usr/share/color-schemes/AtlasOSLight.colors >>/etc/xdg/kdeglobals

# Login screen, macOS style: the blurred, tinted sakura picture with the clock
# above the user's avatar and password field. (The lock screen uses the same
# picture, set in /etc/xdg/kscreenlockerrc.) New users' desktop wallpaper is
# in the themes' defaults.
replace /usr/lib/plasmalogin/defaults.conf \
	"file:///usr/share/wallpapers/Fedora/" "file:///usr/share/wallpapers/AtlasOS-Login/"
grep -qx '\[Greeter\]' /usr/lib/plasmalogin/defaults.conf
sed -i -e '/^ShowClock=/d' -e '/^\[Greeter\]$/a ShowClock=true' /usr/lib/plasmalogin/defaults.conf

# Lock screen: no "Unlocking failed" after waking from sleep. Before sleep the
# greeter cancels the password check that is waiting (kscreenlocker 6.7's
# greeterapp.cpp, on logind's PrepareForSleep), and the cancelled check comes
# back as a failure: the message and the shake were on screen at wake. Now a
# failure with no password sent starts the check again quietly, once, after
# the grace delay (which outlasts PAM's 2 s fail delay); the password field is
# off for that delay, as after any failure. A second one in a row, before the
# check has asked for a password, is a real fault (a broken PAM stack) and
# shows the message as before, so the screen never retries silently forever.
# Upstream replaced this code in 6.8.
python3 - /usr/share/plasma/shells/org.kde.plasma.desktop/contents/lockscreen/LockScreenUi.qml <<'EOF'
import sys
path = sys.argv[1]
qml = open(path).read()
edits = [
    ("    id: lockScreenUi\n",
     "    id: lockScreenUi\n"
     "    // AtlasOS: the user sent a password that the check hasn't answered yet\n"
     "    property bool answered: false\n"
     "    // AtlasOS: quiet restarts since the check last asked for a password\n"
     "    property int quietRetries: 0\n"),
    ("                    authenticator.respond(password)\n",
     "                    lockScreenUi.answered = true;\n"
     "                    authenticator.respond(password)\n"),
    ('            const msg = i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:status", "Unlocking failed");\n',
     "            if (!lockScreenUi.answered && lockScreenUi.quietRetries < 1) { // cancelled, as before sleep\n"
     "                lockScreenUi.quietRetries++;\n"
     "                graceLockTimer.restart();\n"
     "                return;\n"
     "            }\n"
     '            const msg = i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:status", "Unlocking failed");\n'),
    ("        function onPromptForSecretChanged(msg) {\n",
     "        function onPromptForSecretChanged(msg) {\n"
     "            lockScreenUi.quietRetries = 0;\n"),
    ("            onTriggered: {\n"
     "                root.clearPassword();\n"
     "                authenticator.startAuthenticating();\n",
     "            onTriggered: {\n"
     "                if (lockScreenUi.answered) {\n"
     "                    root.clearPassword();\n"
     "                }\n"
     "                lockScreenUi.answered = false;\n"
     "                authenticator.startAuthenticating();\n"),
]
for old, new in edits:
    if qml.count(old) != 1:
        sys.exit(f"build.sh: lock screen text not found once in {path}: {old!r}")
    qml = qml.replace(old, new)
open(path, "w").write(qml)
EOF

# Boot splash: Fedora's spinner theme with the AtlasOS lockup as the watermark
mkdir -p /usr/share/plymouth/themes/atlasos
cp -a /usr/share/plymouth/themes/spinner/. /usr/share/plymouth/themes/atlasos/
rm /usr/share/plymouth/themes/atlasos/spinner.plymouth
cp /branding/plymouth/watermark.png /usr/share/plymouth/themes/atlasos/watermark.png
plymouth-set-default-theme atlasos

# Plymouth lives in the initramfs, so it has to be rebuilt to pick the theme up.
kver=$(find /usr/lib/modules -mindepth 1 -maxdepth 1 -printf '%f\n')
[ -n "$kver" ] && [ "$(wc -l <<<"$kver")" -eq 1 ] || {
	echo "build.sh: expected one kernel, found: $kver" >&2
	exit 1
}
# (dracut.conf.d/50-atlasos-plymouth.conf in system_files adds the module that
# gives Plymouth IBM Plex Sans; its label plugin ignores the theme's Font=.)
dracut --no-hostonly --kver "$kver" --reproducible --add ostree \
	-f "/usr/lib/modules/$kver/initramfs.img"
# The listing is read whole first: grep -q stopping early would kill lsinitrd
# with SIGPIPE, which pipefail would report as a missing font.
initrd_list=$(lsinitrd "/usr/lib/modules/$kver/initramfs.img")
grep -q 'usr/share/fonts/Plymouth.ttf -> .*/IBMPlexSans-Regular.otf' <<<"$initrd_list" || {
	echo "build.sh: Plymouth's font in the initramfs is not IBM Plex Sans" >&2
	exit 1
}

# New icons and wallpapers need the icon cache to know about them
gtk-update-icon-cache -f /usr/share/icons/hicolor
gtk-update-icon-cache -f /usr/share/icons/Papirus
gtk-update-icon-cache -f /usr/share/icons/Papirus-Dark

### Clean up

/ctx/cleanup.sh
