#!/usr/bin/env bash
# Migrate doc-review published-content from ~/.openclaw/ to ~/.doc-review/
# One-time migration for users upgrading to v4.0.0 (multi-agent support)
#
# Usage: migrate.sh [--dry-run] [--yes]
#
# Does NOT touch credentials — deploy.sh fallback chain handles credential discovery.

set -euo pipefail

DRY_RUN=0
YES=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --yes) YES=1 ;;
    *) echo "Unknown argument: $arg" >&2; echo "Usage: migrate.sh [--dry-run] [--yes]" >&2; exit 2 ;;
  esac
done

OLD_DIR="$HOME/.openclaw/published-content"
NEW_DIR="$HOME/.doc-review/published-content"

if [[ ! -d "$OLD_DIR" ]]; then
  echo "Nothing to migrate: $OLD_DIR does not exist."
  exit 0
fi

if [[ -L "$OLD_DIR" ]]; then
  echo "Already migrated: $OLD_DIR is a symlink → $(readlink "$OLD_DIR")"
  exit 0
fi

PROJECTS=()
for dir in "$OLD_DIR"/*/; do
  [[ -d "$dir" ]] && PROJECTS+=("$(basename "$dir")")
done

if [[ ${#PROJECTS[@]} -eq 0 ]]; then
  echo "Nothing to migrate: $OLD_DIR exists but contains no projects."
  exit 0
fi

echo "doc-review migration plan:"
echo "  source:      $OLD_DIR"
echo "  destination:  $NEW_DIR"
echo "  projects:     ${#PROJECTS[@]}"
for p in "${PROJECTS[@]}"; do
  echo "    - $p"
done
echo ""
echo "After migration:"
echo "  - Projects moved to $NEW_DIR"
echo "  - Symlink created: $OLD_DIR → $NEW_DIR"
echo "  - Credentials NOT moved (deploy.sh finds them automatically)"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo ""
  echo "Dry run only. No changes made."
  exit 0
fi

if [[ "$YES" -ne 1 ]]; then
  echo ""
  echo "Refusing to migrate without --yes."
  exit 1
fi

mkdir -p "$NEW_DIR"

for p in "${PROJECTS[@]}"; do
  echo "Moving $p ..."
  mv "$OLD_DIR/$p" "$NEW_DIR/$p"
done

rmdir "$OLD_DIR" 2>/dev/null || {
  echo "⚠️  $OLD_DIR not empty after moving projects — unexpected files remain:" >&2
  ls -la "$OLD_DIR" >&2
  echo "Symlink not created. Please inspect and clean up manually." >&2
  exit 1
}

ln -s "$NEW_DIR" "$OLD_DIR"

echo ""
echo "Migration complete:"
echo "  ✅ ${#PROJECTS[@]} project(s) moved to $NEW_DIR"
echo "  ✅ Symlink: $OLD_DIR → $NEW_DIR"
echo "  ℹ️  Credentials unchanged (deploy.sh reads from existing location)"
