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

**Eight `regression/*` branches**, one per mode, are just branch pointers at
`regression-base`'s tip:

| Branch | Mode | What it exercises |
| --- | --- | --- |
| `regression/mode-a-full` | A | Scan → rewrite instructions, commit back, record CWEs |
| `regression/mode-a-guardian-only` | A | Same, but CWE recording suppressed (`exclude_git_metadata_fields: all`) |
| `regression/mode-a-no-commit` | A | Same, but `auto_commit: false` — writes the file locally, doesn't commit |
| `regression/mode-b-full` | B | Explicit CWE list → rewrite instructions, commit back |
| `regression/mode-b-guardian-only` | B | Same, CWE recording suppressed |
| `regression/mode-c` | C | Explicit CWE list → record only, no instruction file, no commit-back |
| `regression/mode-d` | D | Scan results → extract + record CWEs, no commit-back |
| `regression/gate-noncompliant` | E | Gate check against a known non-compliant learner — expected to block |

`regression.yml` is triggered by `push` to any `regression/**` branch (has
to be a real `push` event — the connector's GitHub provider hard-rejects
`workflow_dispatch`). A single job configures itself per-branch via a `case`
on `github.ref_name`, then asserts pass/fail inline (commit-back
happened/didn't as expected, gate blocked as expected) — no external
checker. A red job in the GitHub Actions UI *is* the regression signal.

**Nothing in the workflow creates these branches.** They're plain local
`git` branches, created once and pushed like any other branch — see below
for how to (re)create or reset them.

### Known gap

`regression/gate-noncompliant` is the only gate fixture — there's no second,
compliant-learner branch, so the "gate correctly passes a compliant
learner" path isn't covered, only "gate correctly blocks a non-compliant
one." Add a `regression/gate-compliant` branch (same idea, but its last
commit's author email needs to be a learner who's actually completed the
required training) if/when a second test learner exists.

## Triggering a regression run

Pushing (or force-pushing) a `regression/*` branch is what runs its mode —
there's no separate "run" command beyond git push.

**Re-run the whole suite** (reset every branch back to a clean
`regression-base` and re-trigger all eight):

```bash
git checkout regression-base
for b in mode-a-full mode-a-guardian-only mode-a-no-commit mode-b-full mode-b-guardian-only mode-c mode-d gate-noncompliant; do
  git branch -f "regression/$b" regression-base
done
git push origin -f $(for b in mode-a-full mode-a-guardian-only mode-a-no-commit mode-b-full mode-b-guardian-only mode-c mode-d gate-noncompliant; do echo "regression/$b"; done)
```

**Re-run just one mode** (e.g. after changing `regression.yml` and wanting
to retest only `mode-c`):

```bash
git checkout regression-base
git branch -f regression/mode-c regression-base
git push origin -f regression/mode-c
```

**Watch results:**

```bash
gh run list -R cjengdahl/guardian-adapt-demo --workflow=regression.yml -L 8
gh run watch <run-id> -R cjengdahl/guardian-adapt-demo
```

Or just check the Actions tab in the GitHub UI, filtered to the
"Aspen Connector Regression" workflow — one run per branch pushed.

### If you change `regression.yml` or the base fixtures

Edit the files on `regression-base`, commit, push `regression-base` itself,
then re-point and re-push whichever `regression/*` branches you want to
retest (same commands as above) — they won't pick up the change until
they're reset to the new `regression-base` tip.

### Why force-reset instead of just re-pushing more commits?

Commit-back modes (A/B) push a real commit onto their branch every run. If
you don't reset first, each re-run starts from wherever the *previous* run
left the instruction file, rather than from the same clean vulnerable-code
baseline — making runs non-deterministic and hard to compare. Resetting to
`regression-base` before every push keeps each run identical to the last.
