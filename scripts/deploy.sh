#!/usr/bin/env bash
# Deploy a doc-review page to Cloudflare Pages with mandatory password protection
# Usage: deploy.sh <project-name> <directory> <db-name> <db-id> [--password <password>]

set -euo pipefail

usage() {
  echo "Usage: deploy.sh <project-name> <directory> <db-name> <db-id> [--password <password>]" >&2
}

PROJECT_NAME="${1:?Usage: deploy.sh <project-name> <directory> <db-name> <db-id> [--password <password>] }"
DEPLOY_DIR="${2:?Usage: deploy.sh <project-name> <directory> <db-name> <db-id> [--password <password>] }"
DB_NAME="${3:?Usage: deploy.sh <project-name> <directory> <db-name> <db-id> [--password <password>] }"
DB_ID="${4:?Usage: deploy.sh <project-name> <directory> <db-name> <db-id> [--password <password>] }"
PASSWORD=""
GENERATED_PASSWORD=0

shift 4
while [[ $# -gt 0 ]]; do
  case "$1" in
    --password)
      PASSWORD="${2:?--password requires a value}"
      shift 2
      ;;
    *)
      echo "❌ Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

generate_speakable_password() {
  local words=(
    amber apple bamboo berry cedar citrus cloud coral ember fern glacier harbor
    hazel iris ivy lemon lotus maple meadow mango mint ocean olive orchid pebble
    pine river robin saffron silver solar stone sunset tiger velvet willow
  )

  rand_mod() {
    local max="$1"
    local value
    value=$(od -An -N2 -tu2 /dev/urandom | tr -d ' \n')
    echo $(( value % max ))
  }

  local w1="${words[$(rand_mod ${#words[@]})]}"
  local w2="${words[$(rand_mod ${#words[@]})]}"
  local w3="${words[$(rand_mod ${#words[@]})]}"
  local suffix
  suffix=$(printf '%02d' "$(rand_mod 100)")

  echo "${w1}-${w2}-${w3}-${suffix}"
}

if [[ -z "$PASSWORD" ]]; then
  PASSWORD="$(generate_speakable_password)"
  GENERATED_PASSWORD=1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REFERENCES_DIR="$SKILL_DIR/references"
ANNOTATIONS_API_TEMPLATE="$REFERENCES_DIR/annotations-api.js"
MIDDLEWARE_TEMPLATE="$REFERENCES_DIR/middleware-template.js"
CF_CREDS="${CF_CREDS:-${HOME}/.openclaw/credentials/cloudflare.json}"

if [[ ! -f "$DEPLOY_DIR/index.html" ]]; then
  echo "❌ No index.html found in $DEPLOY_DIR" >&2
  exit 1
fi

for required_file in "$ANNOTATIONS_API_TEMPLATE" "$MIDDLEWARE_TEMPLATE"; do
  if [[ ! -f "$required_file" ]]; then
    echo "❌ Required file not found: $required_file" >&2
    exit 1
  fi
done

# Auth: prefer env vars, fall back to credentials JSON file
if [[ -z "${CLOUDFLARE_ACCOUNT_ID:-}" || -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
  if [[ ! -f "$CF_CREDS" ]]; then
    echo "❌ Set CLOUDFLARE_ACCOUNT_ID + CLOUDFLARE_API_TOKEN env vars, or provide credentials at $CF_CREDS" >&2
    exit 1
  fi
  export CLOUDFLARE_ACCOUNT_ID="$(jq -r '.account_id' "$CF_CREDS")"
  export CLOUDFLARE_API_TOKEN="$(jq -r '.api_token' "$CF_CREDS")"
fi

# Auto-inject annotation CSS + JS into index.html if present
INJECT_SCRIPT="$SCRIPT_DIR/inject-annotations.sh"
ANNOTATE_TEMPLATE="$REFERENCES_DIR/annotate-template.html"
if [[ -f "$DEPLOY_DIR/index.html" && -f "$INJECT_SCRIPT" && -f "$ANNOTATE_TEMPLATE" ]]; then
  bash "$INJECT_SCRIPT" "$DEPLOY_DIR/index.html" "$ANNOTATE_TEMPLATE"
fi

echo "🔒 Setting up protected doc-review deploy..."
mkdir -p "$DEPLOY_DIR/functions/api"
cp "$ANNOTATIONS_API_TEMPLATE" "$DEPLOY_DIR/functions/api/annotations.js"
cp "$MIDDLEWARE_TEMPLATE" "$DEPLOY_DIR/functions/_middleware.js"

python3 - "$DEPLOY_DIR/functions/_middleware.js" "$PASSWORD" <<'PY'
from pathlib import Path
import json
import sys

path = Path(sys.argv[1])
password = sys.argv[2]
text = path.read_text()
placeholder = "const PASSWORD = '__REPLACE_WITH_ACTUAL_PASSWORD__';"
replacement = f"const PASSWORD = {json.dumps(password)};"
if placeholder not in text:
    raise SystemExit('password placeholder not found in middleware template')
path.write_text(text.replace(placeholder, replacement, 1))
PY

COMPATIBILITY_DATE="$(date +%Y-%m-%d)"

cat > "$DEPLOY_DIR/wrangler.toml" <<EOF2
name = "$PROJECT_NAME"
compatibility_date = "$COMPATIBILITY_DATE"
pages_build_output_dir = "."

[[d1_databases]]
binding = "DB"
database_name = "$DB_NAME"
database_id = "$DB_ID"
EOF2

D1_SCHEMA=$(cat <<'SQL'
CREATE TABLE IF NOT EXISTS annotations (
  id TEXT PRIMARY KEY,
  text TEXT NOT NULL,
  created_at TEXT DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS comments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  annotation_id TEXT NOT NULL REFERENCES annotations(id),
  author TEXT NOT NULL DEFAULT 'Reviewer',
  text TEXT NOT NULL,
  created_at TEXT DEFAULT (datetime('now'))
);
SQL
)

cd "$DEPLOY_DIR"
npx wrangler d1 execute "$DB_NAME" --remote --command "$D1_SCHEMA"

curl -s -X POST \
  "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/pages/projects" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"$PROJECT_NAME\",\"production_branch\":\"main\"}" \
  | jq -r 'if .success then "✅ Project ready: \(.result.name)" else "ℹ️  Project may already exist (continuing...)" end'

echo "📤 Deploying $DEPLOY_DIR → $PROJECT_NAME.pages.dev ..."
npx wrangler pages deploy . --project-name="$PROJECT_NAME" --branch=main

echo ""
echo "🌐 URL: https://$PROJECT_NAME.pages.dev"
echo "🔒 Protection: Protected"
if [[ "$GENERATED_PASSWORD" -eq 1 ]]; then
  echo "🔑 Password (auto-generated): $PASSWORD"
else
  echo "🔑 Password: $PASSWORD"
fi
echo "🗄️  D1 Database: $DB_NAME ($DB_ID)"
