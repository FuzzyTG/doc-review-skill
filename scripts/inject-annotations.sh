#!/usr/bin/env bash
# Inject annotation CSS + HTML elements + JS from annotate-template.html into a rendered index.html
# Usage: inject-annotations.sh <index.html> <annotate-template.html>
set -euo pipefail

INDEX="${1:?Usage: inject-annotations.sh <index.html> <annotate-template.html>}"
TEMPLATE="${2:?Usage: inject-annotations.sh <index.html> <annotate-template.html>}"

if [[ ! -f "$INDEX" ]]; then echo "❌ Not found: $INDEX" >&2; exit 1; fi
if [[ ! -f "$TEMPLATE" ]]; then echo "❌ Not found: $TEMPLATE" >&2; exit 1; fi

python3 - "$INDEX" "$TEMPLATE" << 'PY'
import sys, re

index_path = sys.argv[1]
template_path = sys.argv[2]

with open(template_path) as f:
    tpl = f.read()
with open(index_path) as f:
    html = f.read()

# Idempotency: skip if already injected
if 'id="addTooltip"' in html and 'id="commentPanel"' in html:
    print("ℹ️  Annotations already present — skipping injection")
    sys.exit(0)

# 1. Extract <style>...</style>
style_m = re.search(r'(<style>.*?</style>)', tpl, re.DOTALL)
if not style_m:
    print("❌ No <style> block found in template", file=sys.stderr)
    sys.exit(1)

# 2. Extract HTML elements: from '<p class="hint"' to '<script>' (exclusive)
hint_start = tpl.find('<p class="hint"')
script_start = tpl.find('<script>')
if hint_start == -1 or script_start == -1:
    print("❌ Cannot find annotation HTML elements in template", file=sys.stderr)
    sys.exit(1)
annotation_html = tpl[hint_start:script_start].strip()

# 3. Extract <script>...</script>
script_m = re.search(r'(<script>.*?</script>)', tpl, re.DOTALL)
if not script_m:
    print("❌ No <script> block found in template", file=sys.stderr)
    sys.exit(1)

# Inject
if '</head>' not in html or '</body>' not in html:
    print("❌ index.html missing </head> or </body>", file=sys.stderr)
    sys.exit(1)

html = html.replace('</head>', style_m.group(1) + '\n</head>', 1)
html = html.replace('</body>', annotation_html + '\n' + script_m.group(1) + '\n</body>', 1)

with open(index_path, 'w') as f:
    f.write(html)

# Verify
missing = []
for tag in ['addTooltip', 'sidebarBadge', 'commentPanel', 'hintText', 'mouseup']:
    if tag not in html:
        missing.append(tag)
if missing:
    print(f"❌ Missing after injection: {', '.join(missing)}", file=sys.stderr)
    sys.exit(1)

style_len = len(style_m.group(1))
html_len = len(annotation_html)
script_len = len(script_m.group(1))
print(f"✅ Annotations injected (CSS:{style_len} + HTML:{html_len} + JS:{script_len} chars)")
PY
