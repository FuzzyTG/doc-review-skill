#!/usr/bin/env bash
# md2html.sh — Deterministic Markdown→HTML conversion for doc-review
# Usage: bash md2html.sh <input.md> <output.html>
#
# Produces pure semantic HTML (no wrapper, no styles).
# This is the BASELINE. Agent enhances on top, never replaces.

set -euo pipefail

INPUT="${1:?Usage: md2html.sh <input.md> <output.html>}"
OUTPUT="${2:?Usage: md2html.sh <input.md> <output.html>}"

if [ ! -f "$INPUT" ]; then
  echo "Error: Input file not found: $INPUT" >&2
  exit 1
fi

# Use marked for deterministic conversion
# --gfm: GitHub Flavored Markdown (tables, strikethrough, etc.)
npx marked --gfm "$INPUT" > "$OUTPUT"

echo "✅ Converted: $INPUT → $OUTPUT"
