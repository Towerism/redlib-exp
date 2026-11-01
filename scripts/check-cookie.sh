#!/bin/sh
# Checks that a cookie file holds one usable reddit_session cookie.
# Prints the expiry date, never the cookie. Exits 1 with a reason on failure.
# Usage: scripts/check-cookie.sh [file]   (default: .cookie)
set -eu

file=${1:-.cookie}
fail() { echo "FAIL: $*" >&2; exit 1; }

[ -f "$file" ] || fail "$file not found. Get your session cookie first: see README.md, \"1. Get your session cookie\"."
[ -r "$file" ] || fail "$file is not readable by $(id -un)."

lines=$(tr -d '\r' < "$file" | grep -c '[^[:space:]]' || true)
[ "$lines" -eq 1 ] || fail "$file must hold exactly one non-empty line; it has $lines."

line=$(tr -d '\r' < "$file" | grep '[^[:space:]]')
case $line in
  reddit_session=*) token=${line#reddit_session=} ;;
  *) fail "$file must start with reddit_session= (format: reddit_session=eyJ...)." ;;
esac

printf '%s' "$token" | grep -Eq '^eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$' \
  || fail "the value in $file is not a reddit_session token: expected three dot-separated parts starting with eyJ, with no quotes or spaces."

# The middle part of the token is base64url JSON holding the expiry time "exp".
payload=$(printf '%s' "$token" | cut -d. -f2 | tr '_-' '/+')
case $(( ${#payload} % 4 )) in 2) payload="$payload==" ;; 3) payload="$payload=" ;; esac
exp=$(printf '%s' "$payload" | { base64 -d 2>/dev/null || base64 -D 2>/dev/null; } | sed -n 's/.*"exp":[[:space:]]*\([0-9][0-9]*\).*/\1/p') || true
[ -n "$exp" ] && [ ${#exp} -le 12 ] || fail "could not read the expiry date from the token in $file; copy the cookie again."

expires=$(date -u -d "@$exp" '+%Y-%m-%d %H:%M UTC' 2>/dev/null || date -u -r "$exp" '+%Y-%m-%d %H:%M UTC' 2>/dev/null) || expires="(unknown date)"
[ "$exp" -gt "$(date +%s)" ] || fail "the session in $file expired on $expires. Log in on reddit.com again and copy a new cookie."

echo "OK: $file holds a reddit_session cookie that expires $expires."
