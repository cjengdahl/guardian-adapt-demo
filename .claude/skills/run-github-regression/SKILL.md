---
name: run-github-regression
description: Run and verify the full GitHub Actions regression suite for aspen-connector (15 regression/* branches covering every mode + gate fixture) in this repo. Use when asked to "run the GitHub regression suite", "run the aspen-connector regression tests", or to validate an aspen-connector change end-to-end against the real API before/after merging.
---

# Running the aspen-connector GitHub regression suite

This repo (`guardian-adapt-demo`) is the GitHub-side regression harness for
[`aspen-connector`](https://github.com/SecurityJourney/aspen-connector). See
`.github/workflows/regression.yml` for the matrix definition and
`scripts/run-regression.sh` / `scripts/set-gate-fixture.sh` for the drivers.
(The GitLab counterpart is `aspen-gitlab-testing`, same structure, its own skill.)

## Prerequisites

- Two real, known learner emails in the tenant: one **compliant** (required
  training complete) and one **non-compliant** (incomplete). As of this
  writing: `cory_engdahl@securityjourney.com` (compliant) and
  `noah_sloan@securityjourney.com` (non-compliant) — confirm these are still
  accurate before relying on them; compliance status can and has changed
  between sessions.
- `gh` CLI authenticated against `cjengdahl/guardian-adapt-demo`.

## Running it

```bash
cd /Users/coryengdahl/git/guardian-adapt-demo
git fetch origin --quiet
./scripts/run-regression.sh "<compliant_email>" "<noncompliant_email>"
```

This force-pushes 15 `regression/*` branches (12 mode branches + 3 gate
fixtures), each triggering its own `regression.yml` run.

## Watching results

Do **not** use `gh run list ... | grep`-style one-shot checks — write a
polling loop and use the `Monitor` tool so results stream in as each of the
15 runs finishes, rather than guessing when they're done. Two portability
traps to avoid when writing that loop on macOS:

- **Don't use `zsh`**: `status` is a read-only special variable in zsh, so a
  loop that does `status=$(...)` silently fails. Write the script to a file
  and invoke it explicitly with `bash /tmp/watch-regression.sh` — don't rely
  on `Monitor`'s default shell.
- **Don't use `declare -A` (associative arrays)**: macOS ships bash 3.2,
  which doesn't support them. Use parallel indexed arrays instead.

Known-good polling script (adjust the branch list if the matrix changes):

```bash
#!/usr/bin/env bash
set -uo pipefail
cd /Users/coryengdahl/git/guardian-adapt-demo
branches=(mode-a-full mode-a-gated mode-a-guardian-only mode-a-no-commit mode-b-full mode-b-gated mode-b-guardian-only mode-b-no-commit mode-c mode-c-gated mode-d mode-d-gated gate-notfound gate-compliant gate-noncompliant)
n=${#branches[@]}
done_flags=()
for ((i=0; i<n; i++)); do done_flags[i]=0; done

while true; do
  all_done=1
  for ((i=0; i<n; i++)); do
    if [[ "${done_flags[i]}" == "1" ]]; then continue; fi
    b="${branches[i]}"
    line=$(gh run list -R cjengdahl/guardian-adapt-demo --workflow=regression.yml --branch "regression/$b" -L 1 --json status,conclusion,databaseId 2>/dev/null | jq -r '.[0] | "\(.status) \(.conclusion) \(.databaseId)"')
    run_status=$(echo "$line" | awk '{print $1}')
    concl=$(echo "$line" | awk '{print $2}')
    id=$(echo "$line" | awk '{print $3}')
    if [[ "$run_status" == "completed" ]]; then
      done_flags[i]=1
      echo "$b -> $concl (run $id)"
    else
      all_done=0
    fi
  done
  [[ "$all_done" == "1" ]] && break
  sleep 15
done
echo "ALL RUNS COMPLETE"
```

Run it with:

```
Monitor({ command: "bash /tmp/watch-regression.sh", description: "poll GitHub aspen-connector regression branches" })
```

## What "done" should look like

All 15 should report `success`, including:
- `gate-compliant` → gate passes
- `gate-noncompliant` → gate *correctly blocks* (this is still `success` at
  the run level — the workflow's own assertion step checks for the block and
  reports success when it happened as expected)
- `gate-notfound` → fail-open, passes
- `mode-*-gated` (4 branches) → the gate blocks *before* the mode's
  commit-back/CWE-recording logic runs — these are the most important
  branches, since they prove the short-circuit, not just gate-alone behavior

## Gotchas hit in practice (check these first if something fails)

1. **Stale action version pin.** `regression.yml` (and `main_alt`'s
   `aspen-gate-check.yml`) `uses: SecurityJourney/aspen-connector@<ref>`. If
   that ref was a feature branch that has since merged and been deleted,
   every run fails immediately with `unable to find version '<ref>'`. Check
   what's actually on `aspen-connector`'s `trunk`/latest tag and update the
   pin (prefer a real version tag once one exists; fall back to `@trunk` if
   the work merged but hasn't been tagged yet).

2. **Gate fixture author drift.** The `mode-*-gated` branches need their
   trigger commit authored by the *actual* non-compliant learner —
   `run-regression.sh` stamps this explicitly from the `noncompliant_email`
   argument (not inferred from `regression-base`'s tip), so this shouldn't
   silently break anymore, but if a gated branch fails while `gate-noncompliant`
   passes, verify the email you passed is still genuinely non-compliant.

3. **`[skip ci]` follow-up commits.** Modes that commit back (A/B, non-gated)
   have the connector tag its commit `[skip ci]`. Not currently a problem for
   this repo's trigger rule, but if commit-back branches start showing
   unexpected extra runs, check for this.

If a run fails, pull the actual log before guessing:

```bash
gh run view <run_id> -R cjengdahl/guardian-adapt-demo --log-failed
```

Don't attribute failures to whatever you were just working on without
checking the log first — e.g. a proto/enum change and a deleted Action ref
can both cause failures in the same session, and they need different fixes.
