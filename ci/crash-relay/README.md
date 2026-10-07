# Crash relay on the VPS

`atlas-crash-relay` takes crash reports from Atlas Updater at
https://telamon.eterneon.net/crash/ and files them as GitHub issues in
`EternalCoder454/AtlasOS`, labelled `crash`. The clients hold no GitHub token;
the relay holds one fine-grained token. It speaks the Sentry store API that
`crates/atlas-core/src/crash.rs` in Atlas Updater posts to
(`POST /api/1/store/`, header `X-Sentry-Auth` with `sentry_key=atlasos`) and
answers `{"id": "<event_id>", "url": "<issue url>"}`.

## What it does

- Refuses to start when `SENTRY_KEY` is unset or empty. Rejects a missing or
  wrong `X-Relay-Proxy` header when `RELAY_PROXY_SECRET` is set (403), a wrong key (401), a body over 256 KiB (413), malformed JSON, a bad
  `event_id`, a `report_type` other than `panic`, `fatal`, `coredump` or the
  failure events below, or an `app` outside `[A-Za-z0-9._/+-]`, 1 to 100
  characters, an `app_version` outside `[0-9A-Za-z.+~_-]`, 1 to 40 characters,
  or an `atlasos_version` that isn't `<2-3 digits>.<8 digits>[-<n>]` such as
  `44.20261003` (400). Either version may also be empty or `unknown` (what
  the apps send when they can't tell). Coredumps can come from any program, so there is no list
  of apps. Only known fields are read, and every string is capped; control and
  invisible format characters (bidi overrides, zero-width) are stripped.
- Success events (`update-staged`, `update-applied`, `rollback-requested`,
  `rollback-applied`, `channel-switched`, `channel-switch-applied`,
  `health-check-passed`) from older clients get a 200 and nothing is filed.
- The same `event_id` again gets the stored url and nothing is filed.
- Reports are grouped by a signature: sha256 of app, report type and the top 5
  function names at the crash end, or the message with digits normalised when
  there is no stack. The issue body holds `<!-- atlas-crash-signature: <hex> -->`.
  - Open issue: a comment with versions, kernel, GPU and the occurrence count.
    At most 10 comments per issue per day; the count goes up regardless. An
    issue seen open is trusted for 5 minutes, to save GitHub calls. A locked
    issue (GitHub answers 403 or 422 to the comment) is just counted.
  - Closed issue: a new issue that says it was seen again after #N.
  - A signature is marked pending in the state before the issue is created. If
    the reply is lost, the next report for it searches the repo for the marker
    and adopts the issue found instead of filing a duplicate (GitHub's search
    index can lag by a minute or so).
  - GitHub errors give 502 and the report stays pending on the client. An
    issue that can't be read for good (deleted, hidden, or 5 failures in a
    row) counts as gone, so a signature can't get stuck.
- Titles: `Crash: <app> <app_version> (<report_type>)`, or for
  `update-failed`, `rollback-failed`, `channel-switch-failed`,
  `automatic-rollback` and `health-check-failed`,
  `Update problem: <report_type> on AtlasOS <atlasos_version>`.

## Limits

| Limit | Value | Over it |
|---|---|---|
| Reports per client IP | 10 per hour | 429 with Retry-After |
| New issues per client IP | 3 per day (UTC) | 429 with Retry-After |
| New issues, all clients | 30 per day (UTC) | 429 with Retry-After |
| Comments, all clients | 200 per day (UTC) | 429 with Retry-After |

Of the 30 new issues a day, only 15 go to reports whose `app_version` is a
plain release number (`1.2` or `1.2.3`); dev and git builds share the other
15, so a flood of fake versions can't use up the whole quota. When the daily
quota is reached the relay logs one `WARNING: daily new-issue quota` line per
day (and one for the unreleased half); alert on it from `docker compose
logs`/the journal. The quota is a cap, not a guarantee: the sentry key is
public, so someone can still fill it, but clients keep reports pending and
retry the next day, so a real report is delayed rather than lost. IPv6 sources
are also limited to 6 new issues per day per /48, besides 3 per /64.
Update-problem reports with a valid AtlasOS version count as released.

The client IP is the rightmost `X-Forwarded-For` entry (Caddy adds it), else
the peer address; IPv6 is counted by /64. That entry is only right if every
request comes through Caddy. Two things enforce it: the relay sits on its own
network (`crash_relay_edge`) shared only with Caddy, and when
`RELAY_PROXY_SECRET` is set the relay answers 403 to any request to the API
without the matching `X-Relay-Proxy` header (constant-time compare). The relay
refuses to start if the secret is set but blank or under 32 characters, and
logs a warning at start if it is not set. Caddy must see the real client
address: no NAT or other proxy in front of it, or `trusted_proxies` set so the
`X-Forwarded-For` it passes on is right.
The IP table lives in memory, is swept every 5 minutes and holds at most
50,000 entries; when full, new IPs share one limit of 100 reports per hour. A 429 or any other non-2xx leaves the report pending on the
user's machine, so it is sent again later.

## Privacy and safety

- IPs are held in memory for the hourly limit only. IPs and payloads are never
  logged or stored. The log has one line per filed issue.
- `user.id` is never put in an issue.
- Report text is attacker-controlled. The message and stack trace go in code
  fences longer than any backtick run inside them. Short values go in a table
  as inline code with newlines, pipes and backticks removed. Titles are one
  line, at most 200 characters, with a zero-width space after `@` and `#` so
  nothing mentions a user or links an issue.
- A state file that can't be parsed is moved aside as
  `state.json.corrupt-<time>` and the relay starts from `state.json.bak` (the state before the last save), or empty if that is bad too. Signatures idle for 180 days are dropped. A failed state write
  gives a 500, never a false success.
- State (`state.json`: signature to issue number, daily counters, the last
  10,000 event ids) is in the `state` volume, written atomically.

## The GitHub token

Fine-grained token, https://github.com/settings/personal-access-tokens/new:

- Resource owner `EternalCoder454`, expiry set (90 days or less; note the date).
- Repository access: only `EternalCoder454/AtlasOS`.
- Repository permissions: Issues, read and write. Nothing else.

The `crash` label already exists on the repo. Put the token on the VPS as the
deploy user. `~/crash-relay` is mode 700, so only that user can reach the
directory. The container runs as uid 10001 and a plain bind-mounted file keeps
its host owner (Docker Compose ignores `uid` and `mode` on a file secret), so
make the file mode 0600 and owned by 10001, not world-readable:

```sh
mkdir -p ~/crash-relay && chmod 700 ~/crash-relay
sudo install -m600 -o 10001 -g 10001 /dev/stdin ~/crash-relay/github-token
```

(Or use a Docker/podman secret created with `docker secret create` under
Swarm, or `podman secret`, which set the owner for you.) A 600 file owned by
the deploy user instead gives "permission denied" in the container.
`docker exec` can't check it (no shell); `docker compose logs` shows a
"reading token" failure if the file is unreadable.

Also make the proxy secret, once, in `~/crash-relay/.env` (mode 600):

```sh
install -m600 /dev/null ~/crash-relay/.env
echo "RELAY_PROXY_SECRET=$(openssl rand -hex 32)" >> ~/crash-relay/.env
```

To renew, run the `install` again, then `docker compose up -d --force-recreate`.

## Caddy

Add inside the `telamon.eterneon.net { ... }` block of the matrix stack's
`caddy/Caddyfile`, before the catch-all `handle`:

```
handle_path /crash/* {
	reverse_proxy crash-relay:8080 {
		header_up X-Relay-Proxy {$RELAY_PROXY_SECRET}
	}
}
```

The relay is on its own network, `crash_relay_edge`, which Caddy must join to
reach it by name. In the Matrix stack's compose file, for the Caddy service:

```yaml
services:
  caddy:
    networks:
      - matrix_inside      # keep whatever it has now
      - crash_relay_edge
    environment:
      RELAY_PROXY_SECRET: ${RELAY_PROXY_SECRET}   # same value as the relay's .env

networks:
  crash_relay_edge:
    external: true
```

Start the relay first (it creates the network), then recreate Caddy
(`docker compose up -d caddy`) so it joins and gets the variable. `{$VAR}` in
the Caddyfile reads Caddy's environment. Nothing is published on the host.

## Deploy

From this folder on your machine (the `claude` user on the VPS is in the
docker group):

```sh
rsync -av --exclude github-token --exclude .env --exclude '*_test.go' ./ claude@eterneon-vps:crash-relay/
ssh claude@eterneon-vps 'cd ~/crash-relay && docker compose up -d --build'
# then the Caddy network, env var and block above, recreate Caddy, and:
ssh claude@eterneon-vps 'docker exec matrix-caddy-1 caddy reload --config /etc/caddy/Caddyfile'
```

The container has a read-only root, no capabilities, no-new-privileges, 128 MB
of memory, 64 processes, half a CPU, 3 x 10 MB of logs and a healthcheck
(`/crash-relay -healthcheck`, since the image has no curl).

## Smoke test

```sh
curl -s https://telamon.eterneon.net/crash/healthz
curl -s -X POST https://telamon.eterneon.net/crash/api/1/store/ \
  -H 'Content-Type: application/json' \
  -H 'X-Sentry-Auth: Sentry sentry_version=7, sentry_key=atlasos' \
  -d '{"event_id":"0123456789abcdef0123456789abcdef","message":"smoke test","tags":{"app":"smoke-test","app_version":"0.0","report_type":"panic"}}'
```

To check limits are per source, send the same request from two different
addresses (for example your machine and another network or `curl --interface`,
with a changed `event_id` and `message`) until one gets 429; the other must
still get 200.

The second prints the new issue's url. Close that issue afterwards. A wrong
key gives 401.

## Tests

`go vet ./... && go test -race ./...` in this folder. They run against a fake
GitHub API. `GITHUB_API` overrides `https://api.github.com` for that.
