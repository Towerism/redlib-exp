#!/bin/sh
# Starts a throwaway Redlib container that may only reach Reddit through the
# session in the cookie file, loads a subreddit page and removes the container.
# Usage: scripts/smoke-test.sh <docker|podman> <image> <cookie-file> <port>
set -eu

docker=$1 image=$2 cookie=$3 port=$4
name=redlib-test-$$
url=http://127.0.0.1:$port
page=$(mktemp)

cleanup() { "$docker" rm -f "$name" >/dev/null 2>&1 || true; rm -f "$page"; }
trap cleanup EXIT INT TERM

fail() {
  echo "FAIL: $*" >&2
  echo "--- container log ---" >&2
  "$docker" logs "$name" 2>&1 | sed -E 's/eyJ[A-Za-z0-9._-]+/<redacted>/g' >&2 || true
  exit 1
}

# The image runs as uid 65532, which cannot read a chmod 600 cookie file.
# Run as the current user instead; rootless Podman also needs keep-id so that
# uid maps to you on the host.
userns=
case $docker in *podman*) userns=--userns=keep-id ;; esac

# Session-only backend, no scrape fallback, no stale cache: the page loads only
# if Reddit accepts the session.
"$docker" run -d --name "$name" ${userns:+"$userns"} --user "$(id -u):$(id -g)" \
  -p "127.0.0.1:$port:8080" \
  -v "$(cd "$(dirname "$cookie")" && pwd)/$(basename "$cookie"):/run/secrets/reddit_cookie:ro,Z" \
  -e REDLIB_REDDIT_COOKIE_FILE=/run/secrets/reddit_cookie \
  -e REDLIB_ENDPOINTS=cookied-json \
  -e REDLIB_ENABLE_SCRAPE_FALLBACK=off \
  -e REDLIB_STALE_CACHE_MB=0 \
  "$image" >/dev/null || fail "could not start the container (is port $port free? try make test TEST_PORT=18081)."

i=0
until curl -fsS -o /dev/null "$url/info" 2>/dev/null; do
  i=$((i + 1)); [ "$i" -lt 30 ] || fail "Redlib did not answer on $url within 15 seconds."
  sleep 0.5
done
echo "OK: Redlib is up on $url."

# /info lists the cookied-json backend only when a session was read.
curl -fsS "$url/info" | grep -q 'cookied-json' \
  || fail "Redlib did not load the session from $cookie (see the log below for the reason)."
echo "OK: Redlib loaded the session."

code=$(curl -s -o "$page" -w '%{http_code}' "$url/r/linux") || code=000
posts=$(grep -c 'class="post_title"' "$page" || true)
if [ "$code" != 200 ] || [ "$posts" -eq 0 ]; then
  reason=$(sed -n 's:.*<title>Error\: \([^<]*\)</title>.*:\1:p' "$page" | head -n 1)
  fail "Reddit refused the session: /r/linux returned HTTP $code${reason:+ ($reason)}. Copy a fresh cookie (README.md, step 1)."
fi
echo "OK: /r/linux loaded $posts posts through your session."
echo "PASS"
