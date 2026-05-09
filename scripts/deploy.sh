#!/usr/bin/env bash
# Deploy a doc-review page to Cloudflare Pages with mandatory password protection
# Each deployment automatically creates a dedicated D1 database (1:1 with project)
#
# Usage: deploy.sh <project-name> <directory> [--password <password>]
#        deploy.sh <project-name> --change-password <new-password>
#
# Project name MUST end with "-review" (enforced).
# D1 database name is always "review-<project-name>" (deterministic).
# Password stored in Cloudflare Secret (PAGE_PASSWORD), not locally.

set -euo pipefail

# ── Resolve published-content directory (fallback chain) ──
if [[ -n "${DOC_REVIEW_HOME:-}" ]]; then
  DOC_REVIEWS_DIR="$DOC_REVIEW_HOME/published-content"
elif [[ -d "$HOME/.doc-review/published-content" ]]; then
  DOC_REVIEWS_DIR="$HOME/.doc-review/published-content"
elif [[ -d "$HOME/.openclaw/published-content" ]]; then
  DOC_REVIEWS_DIR="$HOME/.openclaw/published-content"
else
  DOC_REVIEWS_DIR="$HOME/.doc-review/published-content"
fi

usage() {
  echo "Usage: deploy.sh <project-name> <directory> [--password <password>]" >&2
  echo "  project-name must end with '-review'" >&2
}

PROJECT_NAME="${1:?$(usage)}"

# ── Change-password mode ──
if [[ "${2:-}" == "--change-password" ]]; then
  NEW_PW="${3:?--change-password requires a password value}"
  PERSISTENT_DIR="$DOC_REVIEWS_DIR/$PROJECT_NAME"
  META_FILE="$PERSISTENT_DIR/meta.json"
  SNAPSHOT_DIR="$PERSISTENT_DIR/deploy-snapshot"
  echo "🔑 Changing password for $PROJECT_NAME..."
  printf '%s' "$NEW_PW" | npx wrangler pages secret put PAGE_PASSWORD --project-name="$PROJECT_NAME"
  # Redeploy from snapshot (secrets require redeploy to take effect)
  if [[ -d "$SNAPSHOT_DIR" ]]; then
    cd "$SNAPSHOT_DIR"
    npx wrangler pages deploy . --project-name="$PROJECT_NAME" --branch=main
  else
    echo "⚠️  No deploy snapshot found at $SNAPSHOT_DIR; secret updated but redeploy skipped"
    echo "   Run a full deploy first to create the snapshot."
  fi
  if [[ -f "$META_FILE" ]]; then
    jq --arg pw "$NEW_PW" '.password = $pw' "$META_FILE" > "$META_FILE.tmp" && mv "$META_FILE.tmp" "$META_FILE"
  fi
  echo "✅ Password changed to: $NEW_PW"
  exit 0
fi

DEPLOY_DIR="${2:?$(usage)}"
PASSWORD=""

shift 2
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

# ── Enforce -review suffix ──
if [[ "$PROJECT_NAME" != *-review ]]; then
  echo "❌ Project name must end with '-review' (got: $PROJECT_NAME)" >&2
  echo "   Example: my-report-review" >&2
  exit 1
fi

# ── Password resolution: arg > meta.json > generate ──
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

# Password resolution: arg > generate (no meta.json fallback; password stored in Cloudflare Secret)
PERSISTENT_DIR="$DOC_REVIEWS_DIR/$PROJECT_NAME"
META_FILE="$PERSISTENT_DIR/meta.json"
PASSWORD_SOURCE="arg"

if [[ -z "$PASSWORD" ]]; then
  PASSWORD="$(generate_speakable_password)"
  PASSWORD_SOURCE="generated"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REFERENCES_DIR="$SKILL_DIR/references"
ANNOTATIONS_API_TEMPLATE="$REFERENCES_DIR/annotations-api.js"
MIDDLEWARE_TEMPLATE="$REFERENCES_DIR/middleware-template.js"

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

# ── Resolve Cloudflare credentials (fallback chain) ──
if [[ -n "${CLOUDFLARE_ACCOUNT_ID:-}" && -n "${CLOUDFLARE_API_TOKEN:-}" ]]; then
  : # Already set in environment — use as-is
elif [[ -n "${CF_CREDS:-}" && -f "$CF_CREDS" ]]; then
  export CLOUDFLARE_ACCOUNT_ID="$(jq -r '.account_id' "$CF_CREDS")"
  export CLOUDFLARE_API_TOKEN="$(jq -r '.api_token' "$CF_CREDS")"
elif [[ -f "$HOME/.doc-review/credentials/cloudflare.json" ]]; then
  export CLOUDFLARE_ACCOUNT_ID="$(jq -r '.account_id' "$HOME/.doc-review/credentials/cloudflare.json")"
  export CLOUDFLARE_API_TOKEN="$(jq -r '.api_token' "$HOME/.doc-review/credentials/cloudflare.json")"
elif [[ -f "$HOME/.openclaw/credentials/cloudflare.json" ]]; then
  export CLOUDFLARE_ACCOUNT_ID="$(jq -r '.account_id' "$HOME/.openclaw/credentials/cloudflare.json")"
  export CLOUDFLARE_API_TOKEN="$(jq -r '.api_token' "$HOME/.openclaw/credentials/cloudflare.json")"
else
  echo "❌ Cloudflare credentials not found." >&2
  echo "" >&2
  echo "Set credentials using one of these methods:" >&2
  echo "  1. Export env vars: CLOUDFLARE_ACCOUNT_ID and CLOUDFLARE_API_TOKEN" >&2
  echo "  2. Create ~/.doc-review/credentials/cloudflare.json with:" >&2
  echo '     { "account_id": "...", "api_token": "..." }' >&2
  echo "  3. Set CF_CREDS=/path/to/credentials.json" >&2
  exit 1
fi

# ── Auto-create dedicated D1 database (1:1 per project) ──
DB_NAME="review-${PROJECT_NAME}"
echo "🗄️  Ensuring dedicated D1 database: $DB_NAME ..."
CREATE_OUTPUT=$(npx wrangler d1 create "$DB_NAME" 2>&1) || {
  if echo "$CREATE_OUTPUT" | grep -qi "already exists"; then
    echo "ℹ️  D1 database '$DB_NAME' already exists (redeploy)"
    DB_ID=$(npx wrangler d1 list --json 2>/dev/null | jq -r ".[] | select(.name==\"$DB_NAME\") | .uuid")
    if [[ -z "$DB_ID" || "$DB_ID" == "null" ]]; then
      echo "❌ Could not find existing DB id for '$DB_NAME'" >&2
      exit 1
    fi
  else
    echo "❌ Failed to create D1 database:" >&2
    echo "$CREATE_OUTPUT" >&2
    exit 1
  fi
}

if [[ -z "${DB_ID:-}" ]]; then
  DB_ID=$(echo "$CREATE_OUTPUT" | grep -oP '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1)
  if [[ -z "$DB_ID" ]]; then
    echo "❌ Could not extract database_id from wrangler output:" >&2
    echo "$CREATE_OUTPUT" >&2
    exit 1
  fi
fi

echo "✅ D1 database ready: $DB_NAME ($DB_ID)"

# Auto-inject annotation CSS + HTML + JS into index.html if present
INJECT_SCRIPT="$SCRIPT_DIR/inject-annotations.sh"
ANNOTATE_TEMPLATE="$REFERENCES_DIR/annotate-template.html"
if [[ -f "$DEPLOY_DIR/index.html" && -f "$INJECT_SCRIPT" && -f "$ANNOTATE_TEMPLATE" ]]; then
  bash "$INJECT_SCRIPT" "$DEPLOY_DIR/index.html" "$ANNOTATE_TEMPLATE"
fi

echo "🔒 Setting up protected doc-review deploy..."
mkdir -p "$DEPLOY_DIR/functions/api"
cp "$ANNOTATIONS_API_TEMPLATE" "$DEPLOY_DIR/functions/api/annotations.js"
cp "$MIDDLEWARE_TEMPLATE" "$DEPLOY_DIR/functions/_middleware.js"

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
  prefix TEXT,
  suffix TEXT,
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
# Migrate: add prefix/suffix columns (ignore errors if already exist)
npx wrangler d1 execute "$DB_NAME" --remote --command "ALTER TABLE annotations ADD COLUMN prefix TEXT;" 2>/dev/null || true
npx wrangler d1 execute "$DB_NAME" --remote --command "ALTER TABLE annotations ADD COLUMN suffix TEXT;" 2>/dev/null || true

curl -s -X POST \
  "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/pages/projects" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"$PROJECT_NAME\",\"production_branch\":\"main\"}" \
  | jq -r 'if .success then "✅ Project ready: \(.result.name)" else "ℹ️  Project may already exist (continuing...)" end'

# Set Cloudflare Secrets BEFORE deploy (so middleware can read them on first deployment)
SECRET="cloudflare-pages-auth-$(printf '%s' "$PASSWORD" | sha256sum | cut -d' ' -f1)"
echo "🔐 Setting Cloudflare Secrets..."

set_secret() {
  local name="$1" value="$2" attempt
  for attempt in 1 2 3; do
    if printf '%s' "$value" | npx wrangler pages secret put "$name" --project-name="$PROJECT_NAME" 2>&1 | tail -1; then
      if [[ ${PIPESTATUS[1]} -eq 0 ]]; then
        return 0
      fi
    fi
    echo "⚠️  $name attempt $attempt failed, retrying in 3s..." >&2
    sleep 3
  done
  echo "❌ Failed to set $name after 3 attempts" >&2
  return 1
}

set_secret PAGE_PASSWORD "$PASSWORD" || exit 1
set_secret PAGE_SECRET "$SECRET" || exit 1
echo "✅ Secrets configured"

echo "📤 Deploying $DEPLOY_DIR → $PROJECT_NAME.pages.dev ..."
npx wrangler pages deploy . --project-name="$PROJECT_NAME" --branch=main

# ── Persist state to ~/published-content/<project-name>/ ──
mkdir -p "$PERSISTENT_DIR"

# Save source.html (pure semantic HTML) for future redeploy
if [[ -f "$DEPLOY_DIR/content.html" ]]; then
  cp "$DEPLOY_DIR/content.html" "$PERSISTENT_DIR/source.html"
fi
# Save rendered index.html (with CSS + annotations) as backup
if [[ -f "$DEPLOY_DIR/index.html" ]]; then
  cp "$DEPLOY_DIR/index.html" "$PERSISTENT_DIR/rendered.html"
fi

# Write/update meta.json (no password stored)
NOW=$(date -Iseconds)
if [[ -f "$META_FILE" ]]; then
  python3 - "$META_FILE" "$NOW" "$DB_NAME" "$DB_ID" <<'PY'
import json, sys
path, now, db_name, db_id = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
with open(path) as f:
    meta = json.load(f)
meta["lastDeployed"] = now
meta["dbName"] = db_name
meta["dbId"] = db_id
with open(path, "w") as f:
    json.dump(meta, f, indent=2, ensure_ascii=False)
PY
else
  python3 - "$META_FILE" "$PROJECT_NAME" "$NOW" "$DB_NAME" "$DB_ID" <<'PY'
import json, sys
path, project, now, db_name, db_id = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
meta = {
    "type": "review",
    "project": project,
    "source": None,
    "sourceType": "unknown",
    "theme": "editorial",
    "dbName": db_name,
    "dbId": db_id,
    "created": now,
    "lastDeployed": now
}
with open(path, "w") as f:
    json.dump(meta, f, indent=2, ensure_ascii=False)
PY
fi

# Save deploy snapshot for --change-password redeploy
rm -rf "$PERSISTENT_DIR/deploy-snapshot"
mkdir -p "$PERSISTENT_DIR/deploy-snapshot"
cp -r . "$PERSISTENT_DIR/deploy-snapshot/"

echo ""
echo "🔒 Protection: Protected"
case "$PASSWORD_SOURCE" in
  generated) echo "🔑 Password (auto-generated): $PASSWORD" ;;
  arg)       echo "🔑 Password: $PASSWORD" ;;
esac
echo "🗄️  D1 Database: $DB_NAME ($DB_ID)"
echo "📁 Persistent state: $PERSISTENT_DIR"
