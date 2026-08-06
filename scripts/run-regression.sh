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
# gate to short-circuit before the mode runs) need their trigger commit
# authored by the non-compliant learner's email, so they're skipped rather
# than run against a placeholder if noncompliant_email isn't given.

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
gated_branches=(mode-a-gated mode-b-gated mode-c-gated mode-d-gated)

is_gated_branch() {
  local candidate="$1"
  for g in "${gated_branches[@]}"; do
    [[ "$candidate" == "$g" ]] && return 0
  done
  return 1
}

echo "== Resetting mode branches from regression-base =="
git fetch origin --quiet

# The non-commit-back modes (mode-*-no-commit, mode-c, mode-d, and every
# mode-*-gated) leave their branch sitting exactly at regression-base's tip,
# so a plain reset + force-push to that same SHA is a no-op that fires no
# workflow. Put a fresh empty commit on each branch (unique per branch and per
# run) so the ref SHA always changes and the push reliably triggers a run.
#
# The gate check reads the committer's email from the HEAD commit's author
# (git log --format=%ae), so mode-*-gated branches get their trigger commit
# authored as the known non-compliant learner - that's what they expect to be
# blocked on. Every other branch just reuses regression-base's tip author; a
# stock empty commit would reattribute HEAD to whoever runs this script and
# quietly change what those branches actually test.
base_author=$(git log -1 --format='%an <%ae>' origin/regression-base)
run_stamp=$(date -u +%Y%m%dT%H%M%SZ)

# Can't force-update a branch you're currently on, so make sure we're not
# sitting on one of the branches this loop is about to reset.
git checkout regression-base --quiet
pushed_branches=()
for b in "${mode_branches[@]}"; do
  if is_gated_branch "$b"; then
    if [[ -z "$noncompliant_email" ]]; then
      echo "Skipping regression/$b - gated branches require a non-compliant learner email (pass as \$2 or set NONCOMPLIANT_EMAIL)"
      continue
    fi
    author="Aspen Gate Fixture <$noncompliant_email>"
  else
    author="$base_author"
  fi
  git branch -f "regression/$b" origin/regression-base
  git checkout "regression/$b" --quiet
  git commit --allow-empty --author="$author" \
    -m "regression trigger: $b @ $run_stamp" --quiet
  pushed_branches+=("$b")
done
git checkout regression-base --quiet
if [[ "${#pushed_branches[@]}" -gt 0 ]]; then
  git push origin -f "${pushed_branches[@]/#/regression/}"
fi

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
