# redlib-exp

Run [Redlib](https://github.com/Nachtalb/redlib), a private Reddit front end, in Docker with your own Reddit session cookie. Reddit only serves some pages (post comments, user pages) to logged-in sessions, so Redlib needs one to work well.

The image is `ghcr.io/nachtalb/redlib:latest` (set in [`docker-image`](docker-image)).

## Before you start

- Docker, or Podman (add `DOCKER=podman` to every `make` command).
- `make`, `curl` and a POSIX shell.
- A **throwaway Reddit account**. Every request your Redlib instance makes runs through this account, and Reddit may ban it. Never use your main account.

Get this repository and work in it; every command below runs from this directory:

```sh
git clone https://github.com/Towerism/redlib-exp.git
cd redlib-exp
```

## 1. Get your session cookie

1. Open https://www.reddit.com in a desktop browser and log in with the throwaway account.
2. Open the developer tools: press `F12` (or `Cmd+Option+I` on macOS).
3. Find the cookies:
   - **Chrome, Edge, Brave:** *Application* tab → *Storage* → *Cookies* → `https://www.reddit.com`.
   - **Firefox:** *Storage* tab → *Cookies* → `https://www.reddit.com`.
4. Type `reddit_session` in the filter box.
5. Double-click the **Value** cell of the `reddit_session` row and copy it. Copy only that one value; Redlib needs no other cookie.

## 2. Check what it looks like

The value is a token of about 700 characters: three parts joined by dots, and it always starts with `eyJ`. Shortened, it looks like this:

```
eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ0Ml9hYmMxMjMiLCJleHAiOjE4MDk...<several hundred more characters>...Q2ZmY.dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk
```

If yours doesn't start with `eyJ` or has no dots, you copied the wrong cookie or only part of it.

The session lasts about six months. Pressing "Log out" on reddit.com ends it at once, so close the tab instead of logging out.

## 3. Save it in `.cookie`

Run this, paste the value when the cursor waits, then press `Enter` and `Ctrl+D`:

```sh
( umask 077; { printf 'reddit_session='; cat; } > .cookie )
chmod 600 .cookie
```

Pasting instead of typing the value into the command keeps it out of your shell history. `umask 077` and `chmod 600` make the file readable only by you, also when you overwrite an older `.cookie`. The finished file holds a single line:

```
reddit_session=eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIi...
```

`.cookie` is in `.gitignore`. Keep it secret: anyone with it can use the Reddit account.

## 4. Download the image

```sh
make build
```

This runs `docker pull ghcr.io/nachtalb/redlib:latest`.

## 5. Test the cookie

```sh
make test
```

`make test` first checks `.cookie` (one line, the right format, not expired) and prints when it expires. It then starts a temporary Redlib container that may only reach Reddit through your session, loads https://www.reddit.com/r/linux through it, and removes the container. It never prints the cookie. A passing run looks like this:

```
OK: .cookie holds a reddit_session cookie that expires 2027-05-01 17:16 UTC.
OK: Redlib is up on http://127.0.0.1:18080.
OK: Redlib loaded the session.
OK: /r/linux loaded 25 posts through your session.
PASS
```

Any failure prints one `FAIL:` line saying what is wrong; see [Troubleshooting](#troubleshooting).

## 6. Run Redlib

With Docker:

```sh
docker run -d --name redlib \
  --user "$(id -u):$(id -g)" \
  -p 127.0.0.1:8080:8080 \
  -v "$PWD/.cookie:/run/secrets/reddit_cookie:ro,z" \
  -e REDLIB_REDDIT_COOKIE_FILE=/run/secrets/reddit_cookie \
  ghcr.io/nachtalb/redlib:latest
```

With Podman, add `--userns=keep-id` and use `podman` instead of `docker`. This also applies if your `docker` command is Podman's wrapper (`docker --version` mentions Podman):

```sh
podman run -d --name redlib \
  --userns=keep-id --user "$(id -u):$(id -g)" \
  -p 127.0.0.1:8080:8080 \
  -v "$PWD/.cookie:/run/secrets/reddit_cookie:ro,z" \
  -e REDLIB_REDDIT_COOKIE_FILE=/run/secrets/reddit_cookie \
  ghcr.io/nachtalb/redlib:latest
```

Then open http://localhost:8080. If port 8080 is already taken, `docker run` fails with `address already in use`; run `docker rm -f redlib` and start it again with another port, e.g. `-p 127.0.0.1:8081:8080`, then open http://localhost:8081.

What each part does:

| Part | Why |
|---|---|
| `--user "$(id -u):$(id -g)"` | The image runs as uid 65532, which can't read your mode-600 `.cookie`. This runs Redlib as you instead. Rootless Podman also needs `--userns=keep-id`. |
| `-p 127.0.0.1:8080:8080` | Only this computer can reach Redlib. Use `-p 8080:8080` to open it to your network, but anyone who reaches it browses through your Reddit account. |
| `-v ...:/run/secrets/reddit_cookie:ro,z` | Mounts `.cookie` read-only. `z` lets SELinux systems (Fedora, RHEL) allow the mount and still lets `make test` read the same file; other systems ignore it. |
| `-e REDLIB_REDDIT_COOKIE_FILE=...` | Tells Redlib to read the session from that file. This keeps the cookie out of `docker inspect` and your shell history. |

To confirm the session is in use, open http://localhost:8080/info: the backend list includes `cookied-json`.

Stop and remove it:

```sh
docker rm -f redlib
```

If you replace `.cookie` with a new session, run `docker restart redlib`. A single-file mount keeps showing the old file after an editor replaces it.

## Troubleshooting

| `make test` says | Fix |
|---|---|
| `.cookie not found` | Do steps 1–3. |
| `is not readable` | You don't own `.cookie`. Run `sudo chown "$(id -un)" .cookie`. |
| `must hold exactly one non-empty line` | The paste broke into several lines or picked up extra text. Redo step 3. |
| `must start with reddit_session=` | The line must be `reddit_session=` then the value, with no spaces. |
| `is not a reddit_session token` | You copied the wrong cookie, part of it, or quotes. Copy the `reddit_session` value again. |
| `could not read the expiry date` | The value is cut off or altered. Copy the `reddit_session` value again. |
| `expired on ...` | Log in on reddit.com again and copy a new `reddit_session`. |
| `could not start the container` | Read the Docker error above it. For example, if port 18080 is in use, run `make test TEST_PORT=18081`; if the Docker daemon isn't running, start it. |
| `stopped before it answered` or `did not answer` | Read the container log printed below the message. |
| `Redlib did not load the session` | Read the container log printed below the message. `Permission denied` means the container user can't read `.cookie`: check that you own it, and if you use rootless Docker, use Podman with `DOCKER=podman` instead. |
| `Reddit refused the session` | The session was logged out, expired early, or the account is banned. Copy a new cookie, from a new throwaway account if needed. |
| `docker-image is missing or empty` | Restore it with `git checkout docker-image`. |

Settings for `make`:

| Variable | Default | Meaning |
|---|---|---|
| `DOCKER` | `docker` | Container command, a single word such as `docker` or `podman`. |
| `COOKIE` | `.cookie` | Path to the cookie file. |
| `TEST_PORT` | `18080` | Local port for the `make test` container. |

All Redlib settings are described in the fork's [CONFIGURATION.md](https://github.com/Nachtalb/redlib/blob/main/CONFIGURATION.md).
