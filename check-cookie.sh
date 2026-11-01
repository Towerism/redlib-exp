#!/usr/bin/env bash
# Verify the reddit_session cookie in .cookie works with the image in docker-image.
# Never prints the cookie value.
set -euo pipefail
cd "$(dirname "$0")"

COOKIE="$(tr -d '\r\n' < .cookie)"
[[ -n "$COOKIE" ]] || { echo "FAIL: .cookie is empty"; exit 1; }
[[ "$COOKIE" == *reddit_session=* ]] || COOKIE="reddit_session=$COOKIE"

NAME=redlib-cookie-check PORT=8089
docker rm -f "$NAME" >/dev/null 2>&1 || true
trap 'docker rm -f "$NAME" >/dev/null 2>&1 || true' EXIT
# Force comments through the session backend only, so a page only loads if the cookie is good.
docker run -d --name "$NAME" -p "127.0.0.1:$PORT:8080" \
  -e REDLIB_REDDIT_COOKIE="$COOKIE" \
  -e REDLIB_ENDPOINTS_COMMENTS=cookied-json -e REDLIB_ENABLE_SCRAPE_FALLBACK=off \
  "$(cat docker-image)" >/dev/null
sleep 5

fail=0
if docker logs "$NAME" 2>&1 | grep -qiE 'no reddit_session|expired|not a valid cookie'; then
  echo "FAIL: redlib rejected the session:"; docker logs "$NAME" 2>&1 | grep -iE 'session|cookie'; fail=1
fi

post=$(curl -s "http://127.0.0.1:$PORT/r/popular" | grep -oE '/r/[^/"]+/comments/[a-z0-9]+' | head -1 || true)
[[ -n "$post" ]] || { echo "FAIL: no post link found on /r/popular to test with"; exit 1; }
page=$(curl -s -w '\n%{http_code}' "http://127.0.0.1:$PORT$post")
code=${page##*$'\n'}
echo "GET $post -> $code"
grep -qE 'REDLIB_REDDIT_COOKIE|logged-in sessions' <<<"$page" && { echo "FAIL: Reddit refused the session"; fail=1; }
[[ "$code" == 200 ]] || fail=1

echo "--- redlib log ---"; docker logs "$NAME" 2>&1 | tail -20
(( fail == 0 )) && echo "PASS: cookie works" || { echo "FAIL"; exit 1; }
