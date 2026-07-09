#!/usr/bin/env bash
# scripts/rebase-onto-upstream.sh — advance the current patches branch onto a new upstream SkipUI tag.
#
# Usage:
#   source /path/to/fianchetto_env.sh   # sets JAVA_HOME, ANDROID_HOME, PATH
#   # Create and check out the new patches branch first, e.g.:
#   #   git checkout -b patches/1.59.0 fork/patches/1.58.0
#   scripts/rebase-onto-upstream.sh <upstream-tag>
#
# The script:
#   1. Verifies that JAVA_HOME and ANDROID_HOME are set and prerequisites are met.
#   2. Fetches the specified tag from the upstream remote.
#   3. Rebases the current patches branch onto the tag.
#   4. Runs the full dual-side suite (swift test) and verifies the JUNIT summary line.
#   5. Prints a pass/fail report and exits non-zero on any failure.
#
# Drop any fix commits whose upstream PRs have been merged BEFORE running this script.
# The app should then be re-pinned to the new annotated tag created after a successful rebase.
#
# Known gaps (to be addressed in a future pass):
#   - PATCHES_BRANCH is still compared against the current branch; the check below should
#     accept any patches/X.Y.Z branch, not a hardcoded name.
#   - UPSTREAM_REMOTE should be a configurable variable pointing at skiptools/skip-ui
#     (the upstream origin), not the fork remote.  In this repo the upstream is typically
#     named "upstream"; "origin" points at the local SPM checkout, not GitHub.
#   - The script does not create the new patches branch — the caller must do so first.
#   - The script does not rebase the five fix/* branches onto the new tag.
#   - The script does not create the annotated tag (it prints instructions instead).
#   - The script does not push to the fork remote.
#   - The script does not update FORK.md.

set -euo pipefail

# Set UPSTREAM_REMOTE to whichever remote tracks skiptools/skip-ui in your clone.
# In a fresh clone from the fork, add: git remote add upstream https://github.com/skiptools/skip-ui.git
UPSTREAM_REMOTE="upstream"
PATCHES_BRANCH="patches/1.58.0"

# ── argument check ────────────────────────────────────────────────────────────

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <upstream-tag>" >&2
    echo "Example: $0 1.58.0" >&2
    exit 1
fi

UPSTREAM_TAG="$1"

# ── prerequisite checks ───────────────────────────────────────────────────────

if [[ -z "${JAVA_HOME:-}" ]]; then
    echo "ERROR: JAVA_HOME is not set. Source the environment file first:" >&2
    echo "  source /path/to/fianchetto_env.sh" >&2
    exit 1
fi

if ! java -version &>/dev/null; then
    echo "ERROR: java not found on PATH (JAVA_HOME=$JAVA_HOME). Check your environment." >&2
    exit 1
fi

if [[ -z "${ANDROID_HOME:-}" ]]; then
    echo "ERROR: ANDROID_HOME is not set. Source the environment file first:" >&2
    echo "  source /path/to/fianchetto_env.sh" >&2
    echo "  (Without ANDROID_HOME the Gradle/Robolectric side silently does not run;" >&2
    echo "   the JUNIT SUITES summary line will be absent and the suite check will fail.)" >&2
    exit 1
fi

if ! swift --version &>/dev/null; then
    echo "ERROR: swift not found on PATH. Check your Xcode installation." >&2
    exit 1
fi

REPO_ROOT="$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"
echo "Repository root: $REPO_ROOT"

# ── confirm the target branch exists and is checked out ──────────────────────

CURRENT_BRANCH="$(git -C "$REPO_ROOT" branch --show-current)"
if [[ "$CURRENT_BRANCH" != "$PATCHES_BRANCH" ]]; then
    echo "ERROR: Expected to be on '$PATCHES_BRANCH', currently on '$CURRENT_BRANCH'." >&2
    echo "Switch to $PATCHES_BRANCH before running this script." >&2
    exit 1
fi

# ── ensure working tree is clean ─────────────────────────────────────────────

if ! git -C "$REPO_ROOT" diff --quiet HEAD; then
    echo "ERROR: Working tree has uncommitted changes. Commit or stash them first." >&2
    exit 1
fi

# ── fetch the upstream tag ───────────────────────────────────────────────────

echo ""
echo "==> Fetching $UPSTREAM_TAG from $UPSTREAM_REMOTE ..."
git -C "$REPO_ROOT" fetch "$UPSTREAM_REMOTE" "refs/tags/${UPSTREAM_TAG}:refs/tags/${UPSTREAM_TAG}" --no-tags

TAG_COMMIT="$(git -C "$REPO_ROOT" rev-parse "refs/tags/${UPSTREAM_TAG}" 2>/dev/null || true)"
if [[ -z "$TAG_COMMIT" ]]; then
    echo "ERROR: Tag '$UPSTREAM_TAG' not found after fetch. Verify the tag name." >&2
    exit 1
fi

echo "Tag $UPSTREAM_TAG resolves to $TAG_COMMIT"

# ── rebase patches/1.57.0 onto the upstream tag ──────────────────────────────

echo ""
echo "==> Rebasing $PATCHES_BRANCH onto $UPSTREAM_TAG ($TAG_COMMIT) ..."
git -C "$REPO_ROOT" rebase "$TAG_COMMIT"

echo ""
echo "==> Rebase complete. New HEAD: $(git -C "$REPO_ROOT" rev-parse HEAD)"

# ── run the dual-side suite ──────────────────────────────────────────────────

echo ""
echo "==> Running dual-side suite (swift test) — this takes several minutes ..."
echo ""

SUITE_LOG="$(mktemp)"
set +e
(cd "$REPO_ROOT" && swift test 2>&1) | tee "$SUITE_LOG"
SWIFT_TEST_EXIT=$?
set -e

# ── verify JUNIT summary line ────────────────────────────────────────────────

JUNIT_LINE="$(grep "^JUNIT SUITES" "$SUITE_LOG" || true)"
rm -f "$SUITE_LOG"

echo ""
echo "==> Suite summary line: ${JUNIT_LINE:-<NOT FOUND>}"
echo ""

if [[ -z "$JUNIT_LINE" ]]; then
    echo "FAIL: JUNIT SUITES summary line not found in test output." >&2
    echo "The Android/Kotlin side did not execute. Verify JAVA_HOME and try again." >&2
    exit 1
fi

if echo "$JUNIT_LINE" | grep -q "FAILED 0"; then
    echo "PASS: $JUNIT_LINE"
    echo ""
    echo "Suite is green. Next steps:"
    echo "  1. Create an annotated tag for the new release, e.g.:"
    echo "     git tag -a '${UPSTREAM_TAG}+fixes.1' -m 'patches/${UPSTREAM_TAG}: 5 Android safe-area and layout fixes'"
    echo "  2. Push the branch and tag:"
    echo "     git push fork ${PATCHES_BRANCH} '${UPSTREAM_TAG}+fixes.1'"
    echo "  3. Update the app's Package.swift or .resolved to pin the new tag."
else
    echo "FAIL: Suite reports failures: $JUNIT_LINE" >&2
    echo "Resolve failures before advancing the app pin." >&2
    exit 1
fi
