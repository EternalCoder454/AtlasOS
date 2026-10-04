/*
 * pam_atlasos_pin: the PIN in the password field (see DEV.md, "PIN sign-in").
 *
 * Only for the services kde (the lock screen) and plasmalogin (the login
 * screen); for every other service each entry point returns PAM_IGNORE.
 *
 * authenticate  Runs after pam_unix has declined the typed text as a
 *               password. If the text (PAM_AUTHTOK, never prompted for) is 4
 *               to 8 digits, asks the verifier (atlasos-pin.socket) whether
 *               it is the user's PIN. On success it CLEARS PAM_AUTHTOK, so the
 *               keyring and wallet modules after the stack never see the PIN
 *               as the login secret, remembers that this login was by PIN, and
 *               returns PAM_SUCCESS. Anything else is PAM_IGNORE or
 *               PAM_AUTH_ERR, so the stack goes on to pam_deny.
 *               With the argument "pinlogin" it only reports whether this
 *               login was by PIN (success) or not (ignore): /etc/pam.d/
 *               plasmalogin uses it to jump over the wallet and keyring lines,
 *               which would otherwise prompt for the password a second time
 *               (the token is gone) or take the PIN for it.
 * setcred       The login screen calls it after a PIN login, when pam_unix
 *               answers with its saved failure: success, but only for a login
 *               this module let in.
 *               (The request carries the user name too: the verifier only
 *               accepts it if it is the name getpwuid gives for the uid.)
 * open_session  At the login screen, a session that was not opened by a PIN
 *               login was opened by password (auto-login is another PAM
 *               service, plasmalogin-autologin, without this module): tells
 *               the verifier to clear the wrong-PIN count (a PIN can't have
 *               been used, so this is the only thing that clears it; the
 *               lifetime count stays).
 */
#define PAM_SM_AUTH
#define PAM_SM_SESSION
#include <ctype.h>
#include <errno.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/un.h>
#include <unistd.h>
#include <security/pam_ext.h>
#include <security/pam_modules.h>

#define SOCKET_PATH "/run/atlasos/pin.sock"
#define FLAG "atlasos_pin_login"

static int service_is(pam_handle_t *pamh, const char *a, const char *b)
{
	const void *svc = NULL;

	if (pam_get_item(pamh, PAM_SERVICE, &svc) != PAM_SUCCESS || svc == NULL)
		return 0;
	return strcmp(svc, a) == 0 || (b != NULL && strcmp(svc, b) == 0);
}

/* The user's uid as text and the name it came from (a name the request line
 * can carry: 1 to 40 printable characters, no space). "-" for a uid and "" for
 * the name when the user doesn't exist or can't be looked up (the verifier
 * then spends the same time and answers "nopin"). */
static void uid_text(pam_handle_t *pamh, char *out, size_t n, char *name, size_t nn)
{
	const void *user = NULL;
	struct passwd pw, *res = NULL;
	size_t size = 2048, i, len;
	char *buf;
	int rc;

	snprintf(out, n, "-");
	name[0] = '\0';
	if (pam_get_item(pamh, PAM_USER, &user) != PAM_SUCCESS || user == NULL)
		return;
	len = strlen(user);
	if (len == 0 || len >= nn)
		return;
	for (i = 0; i < len; i++)
		if (((const unsigned char *)user)[i] <= ' ' || ((const unsigned char *)user)[i] > '~')
			return;
	/* ERANGE means the buffer was too small, not that there is no user. */
	for (;;) {
		buf = malloc(size);
		if (buf == NULL)
			return;
		rc = getpwnam_r(user, &pw, buf, size, &res);
		if (rc != ERANGE)
			break;
		free(buf);
		buf = NULL;
		if (size >= (size_t)1 << 20)
			return;
		size *= 2;
	}
	if (rc == 0 && res != NULL && res->pw_name != NULL) {
		/* The name the system knows, not the typed one (an alias or a
		 * case-insensitive backend would not match the uid's name). */
		len = strlen(res->pw_name);
		if (len == 0 || len >= nn)
			goto done;
		for (i = 0; i < len; i++)
			if (((const unsigned char *)res->pw_name)[i] <= ' ' || ((const unsigned char *)res->pw_name)[i] > '~')
				goto done;
		snprintf(out, n, "%u", (unsigned)res->pw_uid);
		memcpy(name, res->pw_name, len + 1);
	}
done:
	free(buf);
}

/* One request line out, one answer line back. 0 if there was an answer. */
static int ask(const char *req, size_t len, char *reply, size_t n)
{
	struct sockaddr_un addr;
	struct timeval tv = { .tv_sec = 3 };
	size_t got = 0;
	int fd, ok = -1;

	fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
	if (fd < 0)
		return -1;
	setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
	setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof tv);
	memset(&addr, 0, sizeof addr);
	addr.sun_family = AF_UNIX;
	strcpy(addr.sun_path, SOCKET_PATH);
	if (connect(fd, (struct sockaddr *)&addr, sizeof addr) != 0)
		goto out;
	if (send(fd, req, len, MSG_NOSIGNAL) != (ssize_t)len)
		goto out;
	shutdown(fd, SHUT_WR);
	while (got < n - 1) {
		ssize_t r = read(fd, reply + got, n - 1 - got);
		if (r <= 0)
			break;
		got += (size_t)r;
	}
	reply[got] = '\0';
	reply[strcspn(reply, "\n")] = '\0';
	ok = got > 0 ? 0 : -1;
out:
	close(fd);
	return ok;
}

PAM_EXTERN int pam_sm_authenticate(pam_handle_t *pamh, int flags, int argc, const char **argv)
{
	const void *tok = NULL;
	const char *pin;
	char uid[24], name[41], req[128], reply[64];
	size_t i, len;
	int n, rc;

	(void)flags;
	if (!service_is(pamh, "kde", "plasmalogin"))
		return PAM_IGNORE;
	/* A reused handle must not carry a flag from an earlier attempt. The
	 * "pinlogin" check below reads it, so clear it only for a real try. */
	if (!(argc > 0 && strcmp(argv[0], "pinlogin") == 0))
		pam_set_data(pamh, FLAG, NULL, NULL);
	if (argc > 0 && strcmp(argv[0], "pinlogin") == 0) {
		if (pam_get_data(pamh, FLAG, &tok) == PAM_SUCCESS && tok != NULL)
			return PAM_SUCCESS;
		return PAM_IGNORE;
	}
	/* Whatever pam_unix saw; never a prompt of our own. */
	if (pam_get_item(pamh, PAM_AUTHTOK, &tok) != PAM_SUCCESS || tok == NULL)
		return PAM_IGNORE;
	pin = tok;
	len = strlen(pin);
	if (len < 4 || len > 8)
		return PAM_IGNORE;
	for (i = 0; i < len; i++)
		if (pin[i] < '0' || pin[i] > '9')
			return PAM_IGNORE;

	uid_text(pamh, uid, sizeof uid, name, sizeof name);
	n = snprintf(req, sizeof req, "verify %s %s %s\n", uid, name[0] ? name : "-", pin);
	if (n <= 0 || (size_t)n >= sizeof req) {
		explicit_bzero(req, sizeof req);
		return PAM_IGNORE;
	}
	rc = ask(req, (size_t)n, reply, sizeof reply);
	explicit_bzero(req, sizeof req);
	if (rc != 0)
		return PAM_IGNORE;
	if (strcmp(reply, "ok") == 0) {
		/* The PIN is not the login secret: nothing after this stack
		 * (kwallet, gnome-keyring, ...) gets it. */
		pam_set_item(pamh, PAM_AUTHTOK, NULL);
		pam_set_data(pamh, FLAG, (void *)1, NULL);
		return PAM_SUCCESS;
	}
	/* Only the lock screen: the login screen would tell anyone which
	 * names have a PIN. */
	if (strcmp(reply, "locked") == 0 && service_is(pamh, "kde", NULL))
		pam_info(pamh, "Too many wrong PINs. Use your password.");
	return PAM_AUTH_ERR;
}

PAM_EXTERN int pam_sm_setcred(pam_handle_t *pamh, int flags, int argc, const char **argv)
{
	const void *data = NULL;

	(void)flags; (void)argc; (void)argv;
	if (!service_is(pamh, "kde", "plasmalogin"))
		return PAM_IGNORE;
	if (pam_get_data(pamh, FLAG, &data) != PAM_SUCCESS || data == NULL)
		return PAM_IGNORE;
	return PAM_SUCCESS;
}

PAM_EXTERN int pam_sm_open_session(pam_handle_t *pamh, int flags, int argc, const char **argv)
{
	const void *data = NULL;
	char uid[24], name[41], req[48], reply[64];
	int n;

	(void)flags; (void)argc; (void)argv;
	if (!service_is(pamh, "plasmalogin", NULL))
		return PAM_IGNORE;
	if (pam_get_data(pamh, FLAG, &data) == PAM_SUCCESS && data != NULL)
		return PAM_IGNORE;	/* by PIN: the count stays */
	uid_text(pamh, uid, sizeof uid, name, sizeof name);
	if (uid[0] == '-')
		return PAM_IGNORE;
	n = snprintf(req, sizeof req, "reset %s\n", uid);
	if (n <= 0 || (size_t)n >= sizeof req)
		return PAM_IGNORE;
	ask(req, (size_t)n, reply, sizeof reply);
	return PAM_IGNORE;
}

PAM_EXTERN int pam_sm_close_session(pam_handle_t *pamh, int flags, int argc, const char **argv)
{
	(void)pamh; (void)flags; (void)argc; (void)argv;
	return PAM_IGNORE;
}
