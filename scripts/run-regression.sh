#!/usr/bin/env bash
# Resets and pushes every regression/* branch from regression-base, which
# triggers a fresh regression.yml run for each of the 12 modes.
#
# Usage:
#   scripts/run-regression.sh [compliant_email] [noncompliant_email]
#
# compliant/noncompliant need real learners in the tenant (training
# complete/incomplete respectively) - pass their emails positionally, or set
# COMPLIANT_EMAIL/NONCOMPLIANT_EMAIL. Neither has a default; whichever one
# is missing gets skipped rather than run against a placeholder. The
# not-found fixture has a known-good default (see set-gate-fixture.sh) and
# always runs.
#
# The four mode-*-gated branches (combined mode + gate check, expecting the
# gate to short-circuit before the mode runs) rely on the HEAD commit being
# authored by the known non-compliant learner's email. The mode loop below
# preserves regression-base's tip author when it adds its trigger commit, so
# this holds as long as regression-base's own tip stays authored by that
# learner - true today since that's whoever's git identity last committed to
# it. If that ever changes, these branches need re-checking.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

compliant_email="${1:-${COMPLIANT_EMAIL:-}}"
noncompliant_email="${2:-${NONCOMPLIANT_EMAIL:-}}"

mode_branches=(
  mode-a-full
  mode-a-guardian-only
  mode-a-no-commit
  mode-b-full
  mode-b-guardian-only
  mode-b-no-commit
  mode-c
  mode-d
  mode-a-gated
  mode-b-gated
  mode-c-gated
  mode-d-gated
)

echo "== Resetting mode branches from regression-base =="
git fetch origin --quiet

# The non-commit-back modes (mode-*-no-commit, mode-c, mode-d, and every
# mode-*-gated) leave their branch sitting exactly at regression-base's tip,
# so a plain reset + force-push to that same SHA is a no-op that fires no
# workflow. Put a fresh empty commit on each branch (unique per branch and per
# run) so the ref SHA always changes and the push reliably triggers a run.
#
# The gate check reads the committer's email from the HEAD commit's author
# (git log --format=%ae), so reuse regression-base's tip author here - that's
# the known non-compliant learner the mode-*-gated branches expect to be
# blocked on. A stock empty commit would reattribute HEAD to whoever runs
# this script and quietly change what those branches actually test.
base_author=$(git log -1 --format='%an <%ae>' origin/regression-base)
run_stamp=$(date -u +%Y%m%dT%H%M%SZ)

# Can't force-update a branch you're currently on, so make sure we're not
# sitting on one of the branches this loop is about to reset.
git checkout regression-base --quiet
for b in "${mode_branches[@]}"; do
  git branch -f "regression/$b" origin/regression-base
  git checkout "regression/$b" --quiet
  git commit --allow-empty --author="$base_author" \
    -m "regression trigger: $b @ $run_stamp" --quiet
done
git checkout regression-base --quiet
git push origin -f "${mode_branches[@]/#/regression/}"

echo
echo "== Setting gate fixtures =="
./scripts/set-gate-fixture.sh notfound

if [[ -n "$compliant_email" ]]; then
  ./scripts/set-gate-fixture.sh compliant "$compliant_email"
else
  echo "Skipping gate-compliant - no email given (pass as \$1 or set COMPLIANT_EMAIL)"
fi

if [[ -n "$noncompliant_email" ]]; then
  ./scripts/set-gate-fixture.sh noncompliant "$noncompliant_email"
else
  echo "Skipping gate-noncompliant - no email given (pass as \$2 or set NONCOMPLIANT_EMAIL)"
fi

echo
echo "All branches pushed. Watch results with:"
echo "  gh run list -R cjengdahl/guardian-adapt-demo --workflow=regression.yml -L 10"
