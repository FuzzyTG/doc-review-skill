#!/usr/bin/env bash
# Inject annotation CSS + JS from annotate-template.html into a rendered index.html
# Usage: inject-annotations.sh <index.html> <annotate-template.html>
set -euo pipefail

INDEX="${1:?Usage: inject-annotations.sh <index.html> <annotate-template.html>}"
TEMPLATE="${2:?Usage: inject-annotations.sh <index.html> <annotate-template.html>}"

if [[ ! -f "$INDEX" ]]; then echo "❌ Not found: $INDEX" >&2; exit 1; fi
if [[ ! -f "$TEMPLATE" ]]; then echo "❌ Not found: $TEMPLATE" >&2; exit 1; fi

# Extract <style>...</style> block (first occurrence)
STYLE=$(sed -n '/<style>/,/<\/style>/p' "$TEMPLATE")

# Extract <script>...</script> block (the IIFE)
SCRIPT=$(sed -n '/<script>/,/<\/script>/p' "$TEMPLATE")

# Extract the hint element (sits just before <script>)
HINT='<p class="hint" id="hintText"></p>'

if [[ -z "$STYLE" ]]; then echo "❌ No <style> block found in template" >&2; exit 1; fi
if [[ -z "$SCRIPT" ]]; then echo "❌ No <script> block found in template" >&2; exit 1; fi

# Create temp files for safe sed replacement
TMPDIR_INJ=$(mktemp -d)
trap "rm -rf $TMPDIR_INJ" EXIT

echo "$STYLE" > "$TMPDIR_INJ/style.txt"
printf '%s\n%s' "$HINT" "$SCRIPT" > "$TMPDIR_INJ/script.txt"

# Inject style before </head>
python3 - "$INDEX" "$TMPDIR_INJ/style.txt" "$TMPDIR_INJ/script.txt" << 'PY'
import sys

index_path = sys.argv[1]
style_path = sys.argv[2]
script_path = sys.argv[3]

with open(index_path) as f:
    html = f.read()
with open(style_path) as f:
    style = f.read()
with open(script_path) as f:
    script = f.read()

if '</head>' not in html:
    print("❌ No </head> tag in index.html", file=sys.stderr)
    sys.exit(1)
if '</body>' not in html:
    print("❌ No </body> tag in index.html", file=sys.stderr)
    sys.exit(1)

html = html.replace('</head>', style + '\n</head>', 1)
html = html.replace('</body>', script + '\n</body>', 1)

with open(index_path, 'w') as f:
    f.write(html)

# Verify
missing = []
for tag in ['addTooltip', 'sidebar-badge', 'comment-panel', 'mouseup', 'hintText']:
    if tag not in html:
        missing.append(tag)

if missing:
    print(f"⚠️  Missing after injection: {', '.join(missing)}", file=sys.stderr)
    sys.exit(1)

print(f"✅ Annotations injected ({len(style)} + {len(script)} chars)")
PY
