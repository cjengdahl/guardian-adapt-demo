#!/usr/bin/env bash
# Resets and pushes every regression/* branch from regression-base, which
# triggers a fresh regression.yml run for each of the 8 modes.
#
# Usage:
#   scripts/run-regression.sh [compliant_email]
#
# The gate's non-compliant and not-found fixtures use known-good defaults
# (see set-gate-fixture.sh). The compliant fixture needs a real learner
# whose required training is complete - pass its email as the one argument
# here, or set COMPLIANT_EMAIL. If neither is given, gate-compliant is
# skipped rather than run against a placeholder.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

compliant_email="${1:-${COMPLIANT_EMAIL:-}}"
noncompliant_email="${NONCOMPLIANT_EMAIL:-cory_engdahl@securityjourney.com}"

mode_branches=(
  mode-a-full
  mode-a-guardian-only
  mode-a-no-commit
  mode-b-full
  mode-b-guardian-only
  mode-c
  mode-d
)

echo "== Resetting mode branches from regression-base =="
git fetch origin --quiet
# Can't force-update a branch you're currently on, so make sure we're not
# sitting on one of the branches this loop is about to reset.
git checkout regression-base --quiet
for b in "${mode_branches[@]}"; do
  git branch -f "regression/$b" origin/regression-base
done
git push origin -f "${mode_branches[@]/#/regression/}"

echo
echo "== Setting gate fixtures =="
./scripts/set-gate-fixture.sh noncompliant "$noncompliant_email"
./scripts/set-gate-fixture.sh notfound

if [[ -n "$compliant_email" ]]; then
  ./scripts/set-gate-fixture.sh compliant "$compliant_email"
else
  echo "Skipping gate-compliant - no email given (pass as \$1 or set COMPLIANT_EMAIL)"
fi

echo
echo "All branches pushed. Watch results with:"
echo "  gh run list -R cjengdahl/guardian-adapt-demo --workflow=regression.yml -L 10"
