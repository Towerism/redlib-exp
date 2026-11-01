# redlib-exp

Scratch repo for two experiments:

- **Ralph feedback-baseline gate**: does `omc ralph verify` ignore failures that were already there at baseline and catch new ones? Reproduce it with `experiment/replicate.sh` (below).
- **Redlib session cookie**: `check-cookie.sh` checks that a `reddit_session` cookie in `.cookie` (gitignored, not committed) works with the image named in `docker-image`. It needs Docker and your own cookie.

## Ralph feedback-baseline experiment

### Prerequisites

- GNU make (tested with 4.4.1)
- Node.js and `omc` 5.7.19: `npm i -g oh-my-claude-sisyphus@5.7.19`
- bash

### Run it

```sh
git clone git@github.com:Towerism/redlib-exp.git
cd redlib-exp
git checkout add-cookie-check
./experiment/replicate.sh
```

It exits 0 and ends with `ALL CHECKS PASSED`. It creates a throwaway session under `.omc/state/sessions/replicate-*` and deletes it on exit.

### What it does

| File | Role |
|------|------|
| `Makefile` | `make build` and `make test` always fail. The recipes run `exit 1`; GNU make itself exits 2. |
| `experiment/prd.json` | Ralph PRD. `feedbackCommands` are `make build`, `make test`, `sh experiment/probe.sh`. |
| `experiment/probe.sh` | Passes silently. Fails with an error line if `experiment/BREAK_LOUD` exists, or with no output if `experiment/BREAK_SILENT` exists. |
| `experiment/replicate.sh` | Runs the checks below. |

Checks:

1. `make build` and `make test` each exit 2.
2. `omc ralph verify --write-baseline --session <id>` exits 0 and records both make failures.
3. With nothing changed, `omc ralph verify --session <id>` exits 0 (`clean vs baseline`).
4. With `BREAK_LOUD`, the probe fails with an error line, and the gate exits 1 (`1 NEW failure(s) since baseline`).
5. With `BREAK_SILENT`, the probe fails with no output, and the gate still exits 0.

### Findings (omc 5.7.19)

- **Silent failures pass the gate.** `omc ralph verify` compares output lines only. It ignores exit status except 126/127, which it treats as "unrunnable". A command that passed at baseline and now fails without printing anything is reported `clean vs baseline`. See `runFeedbackCommand` in `dist/cli/commands/ralph.js`. Check 5 expects this gap; if a later omc fixes it, check 5 fails and says so.
- **The auto-generated Ralph PRD is invalid.** Starting Ralph through the Skill tool wrote `.omc/prd.json` with a `stories` key. The validator requires `project`, `branchName`, `description` and `userStories`, so `omc ralph verify` failed with `Invalid PRD structure` until the PRD was rewritten.
- **A session PRD wins.** `omc ralph verify --session <id>` reads `.omc/state/sessions/<id>/prd.json` before any repo-root `prd.json` or `.omc/prd.json`. `replicate.sh` relies on that, so it doesn't interfere with other Ralph state. That's also why the PRD lives in `experiment/` and not at the repo root, where every Ralph run would pick it up.
