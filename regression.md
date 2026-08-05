# Aspen connector regression testing

This repo doubles as a regression suite for `aspen-connector`'s five modes of
operation (A, B, C, D, E) on GitHub Actions. One workflow
(`.github/workflows/regression.yml`) covers all of them; each mode lives on
its own branch so commit-back modes don't race each other pushing to the
same ref.

## How it's set up

**`regression-base`** is the common starting point: a copy of `main` with
four vulnerable-code fixtures added (`auth.py` CWE-798, `search.py` CWE-89,
`comments.py` CWE-79, `upload.py` CWE-434) so Snyk-scan-based modes have real
findings to detect, plus a clean `.claude/CLAUDE.md`. `regression.yml`
itself is committed on this branch too — GitHub resolves `on: push` workflow
definitions from the *pushed ref's own tree*, not from `main`, so the
workflow file has to exist on every branch that triggers it.

**Ten `regression/*` branches**, one per mode/fixture, are just branch
pointers at `regression-base`'s tip:

| Branch | Mode | What it exercises |
| --- | --- | --- |
| `regression/mode-a-full` | A | Scan → rewrite instructions, commit back, record CWEs |
| `regression/mode-a-guardian-only` | A | Same, but CWE recording suppressed (`exclude_git_metadata_fields: all`) |
| `regression/mode-a-no-commit` | A | Same, but `auto_commit: false` — writes the file locally, doesn't commit |
| `regression/mode-b-full` | B | Explicit CWE list → rewrite instructions, commit back |
| `regression/mode-b-guardian-only` | B | Same, CWE recording suppressed |
| `regression/mode-c` | C | Explicit CWE list → record only, no instruction file, no commit-back |
| `regression/mode-d` | D | Scan results → extract + record CWEs, no commit-back |
| `regression/gate-compliant` | E | Gate check against a compliant learner — expected to pass |
| `regression/gate-noncompliant` | E | Gate check against a non-compliant learner — expected to block |
| `regression/gate-notfound` | E | Gate check against an unregistered email — expected to fail open (pass, with a warning) |

`regression.yml` is triggered by `push` to any `regression/**` branch (has
to be a real `push` event — the connector's GitHub provider hard-rejects
`workflow_dispatch`). A single job configures itself per-branch via a `case`
on `github.ref_name`, then asserts pass/fail inline against each branch's
`expect_gate_outcome`/`expect_commit` — no external checker. A red job in
the GitHub Actions UI *is* the regression signal.

**Nothing in the workflow creates these branches.** They're plain local
`git` branches, created once and pushed like any other branch — see below
for how to (re)create or reset them.

### The three gate fixtures

The connector reads the gate's target email via `git log -1 --format=%ae`
on whatever's checked out — so each gate branch's fixture is just that
branch's last commit's author email, not anything backend-configured per
branch:

- **compliant** / **noncompliant** need to be real, registered learners in
  the tenant (with their required training complete/incomplete,
  respectively) — you provide the actual email.
- **notfound** just needs an email that doesn't match any directory entry —
  `non-existent-user@securityjourney.com` by default, no backend setup
  needed.

`scripts/set-gate-fixture.sh` sets/resets one of these branches with the
right author email — see below.

## Triggering a regression run

Pushing (or force-pushing) a `regression/*` branch is what runs its mode —
there's no separate "run" command beyond git push. Two scripts wrap the
git commands so you don't have to remember them.

**Run everything at once:**

```bash
./scripts/run-regression.sh                                    # skips gate-compliant, no email known
./scripts/run-regression.sh cory_engdahl@securityjourney.com    # include gate-compliant
```

Resets and pushes all 7 non-gate mode branches from `regression-base`, then
calls `set-gate-fixture.sh` for all three gate cases. `noncompliant`
defaults to `cory_engdahl@securityjourney.com`, `notfound` defaults to
`non-existent-user@securityjourney.com`; override either with
`NONCOMPLIANT_EMAIL=... NOTFOUND_EMAIL=...`. `compliant` is skipped (rather
than run against a placeholder) unless you pass its email as `$1` or set
`COMPLIANT_EMAIL`.

**Re-run just one non-gate mode** (e.g. after changing `regression.yml` and
wanting to retest only `mode-c`):

```bash
git checkout regression-base
git branch -f regression/mode-c regression-base
git push origin -f regression/mode-c
```

**Re-run just one gate fixture:**

```bash
./scripts/set-gate-fixture.sh compliant    cory_engdahl@securityjourney.com
./scripts/set-gate-fixture.sh noncompliant cory_engdahl@securityjourney.com
./scripts/set-gate-fixture.sh notfound     # or: notfound some-other@email.com
```

**Watch results:**

```bash
gh run list -R cjengdahl/guardian-adapt-demo --workflow=regression.yml -L 10
gh run watch <run-id> -R cjengdahl/guardian-adapt-demo
```

Or just check the Actions tab in the GitHub UI, filtered to the
"Aspen Connector Regression" workflow — one run per branch pushed.

### If you change `regression.yml` or the base fixtures

Edit the files on `regression-base`, commit, push `regression-base` itself,
then re-run `run-regression.sh` (or reset individual branches) — they won't
pick up the change until they're reset to the new `regression-base` tip.

### Why force-reset instead of just re-pushing more commits?

Commit-back modes (A/B) push a real commit onto their branch every run. If
you don't reset first, each re-run starts from wherever the *previous* run
left the instruction file, rather than from the same clean vulnerable-code
baseline — making runs non-deterministic and hard to compare. Resetting to
`regression-base` before every push (which is all both scripts do) keeps
each run identical to the last.
