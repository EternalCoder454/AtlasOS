#!/bin/bash
# A throwaway GlitchTip for the crash-report test, inside the test VM (the
# guest can't reach the host's ports). Rootless podman, listening on
# 127.0.0.1:8000 only. Prints the project's DSN on the last line.
#   glitchtip.sh up      start it (pulls the images on the first run)
#   glitchtip.sh events  list the events GlitchTip received (JSON)
#   glitchtip.sh down    remove it
set -euo pipefail

pod=atlas-glitchtip
image=docker.io/glitchtip/glitchtip:latest
secret=$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')
db=postgres://postgres:postgres@127.0.0.1:5432/postgres
env=(-e "DATABASE_URL=$db" -e "VALKEY_URL=redis://127.0.0.1:6379/0" -e "REDIS_URL=redis://127.0.0.1:6379/0"
	-e "SECRET_KEY=$secret" -e PORT=8000 -e GLITCHTIP_DOMAIN=http://127.0.0.1:8000
	-e ENABLE_USER_REGISTRATION=false -e "CELERY_WORKER_AUTOSCALE=1,1")

manage() { podman exec "$pod-web" ./manage.py "$@"; }

case ${1-} in
up)
	podman pod exists "$pod" || podman pod create --name "$pod" -p 127.0.0.1:8000:8000 >/dev/null
	podman container exists "$pod-db" ||
		podman run -d --pod "$pod" --name "$pod-db" -e POSTGRES_PASSWORD=postgres docker.io/library/postgres:17 >/dev/null
	podman container exists "$pod-valkey" ||
		podman run -d --pod "$pod" --name "$pod-valkey" docker.io/valkey/valkey:8 >/dev/null
	# Containers from an earlier boot exist but are stopped.
	podman pod start "$pod" >/dev/null
	for _ in $(seq 120); do podman exec "$pod-db" pg_isready -q -U postgres && break; sleep 1; done
	podman exec "$pod-db" pg_isready -q -U postgres || { echo "postgres did not start" >&2; exit 1; }
	podman container exists "$pod-web" || podman run -d --pod "$pod" --name "$pod-web" "${env[@]}" "$image" >/dev/null
	podman container exists "$pod-worker" ||
		podman run -d --pod "$pod" --name "$pod-worker" "${env[@]}" "$image" ./bin/run-celery-with-beat.sh >/dev/null
	manage migrate --noinput >/dev/null
	until curl -sf -o /dev/null http://127.0.0.1:8000/api/0/; do sleep 2; done
	# A test owner, organization and project; the DSN of its key goes last.
	manage shell -c '
import importlib
def mod(*names):
    for n in names:
        try:
            return importlib.import_module(n)
        except ImportError:
            pass
    raise ImportError(names)
users = mod("apps.users.models", "users.models")
orgs = mod("apps.organizations_ext.models", "organizations_ext.models")
projects = mod("apps.projects.models", "projects.models")
u = users.User.objects.filter(email="test@example.invalid").first() or \
    users.User.objects.create_superuser(email="test@example.invalid", password=None)
org = orgs.Organization.objects.filter(name="AtlasOS test").first()
if org is None:
    org = orgs.Organization.objects.create(name="AtlasOS test")
    org.add_user(u, orgs.OrganizationUserRole.OWNER)
p = projects.Project.objects.filter(organization=org, name="atlasos").first() or \
    projects.Project.objects.create(organization=org, name="atlasos", platform="other")
k = projects.ProjectKey.objects.filter(project=p).first() or projects.ProjectKey.objects.create(project=p)
print(k.get_dsn())
' | tail -1
	;;
events)
	manage shell -c '
import importlib, json
def mod(*names):
    for n in names:
        try:
            return importlib.import_module(n)
        except ImportError:
            pass
    raise ImportError(names)
ev = mod("apps.issue_events.models", "issue_events.models", "events.models")
out = []
for e in ev.IssueEvent.objects.order_by("-timestamp")[:20]:
    out.append({"id": str(e.id), "timestamp": str(e.timestamp), "title": e.title, "data": e.data})
print(json.dumps(out, default=str))
' | tail -1
	;;
down)
	podman pod rm -f "$pod" >/dev/null 2>&1 || true
	;;
*)
	echo "usage: $0 up|events|down" >&2
	exit 2
	;;
esac
