#!/usr/bin/env bash

# Cut a new ValarMindSkills release.
#
# Usage:
#   bash .github/scripts/release.sh <version> [--draft]
#
# <version> may be "v0.1.3" or "0.1.3" — both are accepted.
#
# Steps:
#   1. Validate working tree is clean and tag does not exist.
#   2. Bump .claude-plugin/plugin.json `version` to <version>.
#   3. Commit "chore(release): bump plugin.json to <version>".
#   4. Push the commit to the current branch.
#   5. Create + push tag v<version>.
#   6. Create GitHub release with `gh release create --generate-notes`.
#
# Environment overrides:
#   RELEASE_TITLE   Custom GitHub release title. Default: "v<version>".

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <version> [--draft]" >&2
  echo "       (e.g. $0 v0.1.3)" >&2
  exit 2
fi

raw_version="$1"
shift || true
version="${raw_version#v}"
tag="v${version}"

draft_flag=""
for arg in "$@"; do
  case "$arg" in
    --draft) draft_flag="--draft" ;;
    *) echo "Unknown flag: $arg" >&2; exit 2 ;;
  esac
done

if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: version must be N.N.N (got: $version)" >&2
  exit 1
fi

# Script lives at <repo>/.github/scripts/release.sh — climb two levels.
REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_DIR"

# --------------------------------------------------------------------
# Pre-flight
# --------------------------------------------------------------------
command -v gh >/dev/null 2>&1 || { echo "Error: gh CLI not found." >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "Error: jq not found." >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "Error: git not found." >&2; exit 1; }

if [ -n "$(git status --porcelain)" ]; then
  echo "Error: working tree not clean. Commit or stash first." >&2
  git status --short >&2
  exit 1
fi

if git rev-parse "$tag" >/dev/null 2>&1; then
  echo "Error: tag $tag already exists locally." >&2
  exit 1
fi

if git ls-remote --tags origin "refs/tags/$tag" | grep -q "$tag"; then
  echo "Error: tag $tag already exists on origin." >&2
  exit 1
fi

current_branch="$(git branch --show-current)"
if [ "$current_branch" != "main" ]; then
  echo "Warning: current branch is '$current_branch', not 'main'." >&2
fi

plugin_json="$REPO_DIR/.claude-plugin/plugin.json"
[ -f "$plugin_json" ] || { echo "Error: $plugin_json not found." >&2; exit 1; }

current_version=$(jq -r '.version' "$plugin_json")
if [ "$current_version" = "$version" ]; then
  echo "Error: plugin.json is already at $version. Pick a higher version." >&2
  exit 1
fi

# --------------------------------------------------------------------
# Bump plugin.json
# --------------------------------------------------------------------
echo "[release] bumping plugin.json: $current_version → $version"
tmp=$(mktemp)
jq --arg v "$version" '.version = $v' "$plugin_json" > "$tmp" && mv "$tmp" "$plugin_json"

# --------------------------------------------------------------------
# Commit + push
# --------------------------------------------------------------------
echo "[release] committing version bump"
git add "$plugin_json"
git commit -m "chore(release): bump plugin.json to $version"

echo "[release] pushing commit to origin/$current_branch"
git push origin "$current_branch"

# --------------------------------------------------------------------
# Tag + push
# --------------------------------------------------------------------
echo "[release] tagging $tag"
git tag "$tag"
git push origin "$tag"

# --------------------------------------------------------------------
# GitHub release
# --------------------------------------------------------------------
title="${RELEASE_TITLE:-$tag}"
echo "[release] creating GitHub release ($title)"

if [ -n "$draft_flag" ]; then
  gh release create "$tag" --title "$title" --generate-notes "$draft_flag"
else
  gh release create "$tag" --title "$title" --generate-notes
fi

repo_slug=$(gh repo view --json nameWithOwner -q .nameWithOwner)
echo ""
echo "[release] done: https://github.com/$repo_slug/releases/tag/$tag"
