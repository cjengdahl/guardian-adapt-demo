#!/usr/bin/env bash
# Creates/resets a regression/gate-<case> branch with an empty commit whose
# author email is the gate fixture for that case, then pushes it (which
# triggers that branch's regression.yml run).
#
# Usage:
#   scripts/set-gate-fixture.sh compliant    <email>
#   scripts/set-gate-fixture.sh noncompliant <email>
#   scripts/set-gate-fixture.sh notfound     [email]   # defaults to non-existent-user@securityjourney.com
#
# The compliant/noncompliant emails must belong to a real, registered
# learner in the tenant - compliant needs their required training fully
# complete, noncompliant needs it incomplete. The notfound email just needs
# to not match any directory entry - no backend setup required for it.

set -euo pipefail

case_name="${1:-}"
email="${2:-}"

if [[ -z "$case_name" ]]; then
  echo "Usage: $0 <compliant|noncompliant|notfound> [email]" >&2
  exit 1
fi

case "$case_name" in
  compliant|noncompliant)
    if [[ -z "$email" ]]; then
      echo "Error: $case_name requires an email, e.g.:" >&2
      echo "  $0 $case_name cory_engdahl@securityjourney.com" >&2
      exit 1
    fi
    ;;
  notfound)
    email="${email:-non-existent-user@securityjourney.com}"
    ;;
  *)
    echo "Error: unknown case '$case_name' (expected compliant, noncompliant, or notfound)" >&2
    exit 1
    ;;
esac

branch="regression/gate-$case_name"

echo "Setting $branch -> author email: $email"

git fetch origin --quiet
git branch -f "$branch" origin/regression-base
git checkout "$branch" --quiet
git commit --allow-empty \
  --author="Aspen Gate Fixture <$email>" \
  -m "gate fixture ($case_name): $email" --quiet
git push origin -f "$branch"

echo "Pushed $branch - this triggers its regression.yml run automatically."
echo "Watch it with: gh run list -R cjengdahl/guardian-adapt-demo --workflow=regression.yml -L 3"
