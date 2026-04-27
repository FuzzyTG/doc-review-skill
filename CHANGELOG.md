# Changelog

## v3.0.0

### Breaking Changes

- **New `md2html.sh` baseline step**: Workflow now requires running `scripts/md2html.sh` to generate a deterministic HTML baseline before agent enhancement. Agent can no longer write `content.html` from scratch.
- **HTML Content Rules rewritten**: Components are now optional enhancements (semantic match only), not mandatory. Old quantity mandates removed.

### Added

- `scripts/md2html.sh` — deterministic Markdown→HTML conversion using `marked` (GFM mode)
- Highest-priority rule: source file structure maps 1:1 to HTML tags
- Positive/negative examples for each component (callout, path-card, reasoning-chain, action-items, final-rec)
- "Default downgrade on ambiguity" rule: when uncertain, use basic HTML tags
- Component judgment principle: 3-step decision flow

### Removed

- "每个 h2 section 至少包含 1 个组件" mandate
- "纯 p+ul 的平铺 HTML 是不合格的" quality gate
- "必须积极使用以下组件" directive

## v2.0.0

### Breaking Changes

- **`deploy.sh` signature changed**: `<project-name> <directory> <db-name> <db-id>` → `<project-name> <directory>`. D1 databases are now created automatically (1:1 per project, named `review-<project-name>`).
- **Password storage moved to Cloudflare Secrets**: The middleware no longer uses `__REPLACE_WITH_ACTUAL_PASSWORD__` placeholder. Passwords are stored via `wrangler pages secret put` and read from `env.PAGE_PASSWORD` at runtime.
- **Project name must end with `-review`** (enforced by deploy.sh).

### New Features

- **Auto D1 creation**: Each project automatically gets a dedicated D1 database. No manual database setup required.
- **`--change-password` mode**: Update a review page's password without redeploying content: `deploy.sh <project-name> --change-password <new-password>`
- **W3C TextQuoteSelector**: Annotations now store `prefix` and `suffix` context for precise text positioning, even when the same text appears multiple times.
- **Whitelist middleware**: Password protection middleware uses Cloudflare Secrets for secure credential storage.
- **Deploy snapshot**: A snapshot of each deployment is saved locally, enabling `--change-password` to redeploy without the original source files.
- **i18n**: Annotation UI supports English and Chinese, auto-detected from browser language.

### Bug Fixes

- Fixed annotation highlighting for cross-node text selections
- Fixed sidebar badge not showing on initial load
- Added `ALTER TABLE` migration for `prefix`/`suffix` columns on redeploy (backwards compatible)

### Migration Guide (from v1.0.0)

1. **Update skill files**:
   ```bash
   openclaw skill update doc-review
   # Or: git pull in your skills directory
   ```

2. **Add prefix/suffix columns** to existing D1 databases:
   ```bash
   npx wrangler d1 execute review-<project-name> --remote \
     --command "ALTER TABLE annotations ADD COLUMN prefix TEXT; ALTER TABLE annotations ADD COLUMN suffix TEXT;"
   ```

3. **Set Cloudflare Secrets** for each existing project:
   ```bash
   # Set the password
   printf 'yourpassword' | npx wrangler pages secret put PAGE_PASSWORD \
     --project-name=your-project-review

   # Compute and set PAGE_SECRET
   # PAGE_SECRET = "cloudflare-pages-auth-" + sha256(password)
   HASH=$(printf 'yourpassword' | sha256sum | cut -d' ' -f1)
   printf "cloudflare-pages-auth-${HASH}" | npx wrangler pages secret put PAGE_SECRET \
     --project-name=your-project-review
   ```

4. **Redeploy** with the new deploy.sh (new signature, no db-name/db-id):
   ```bash
   bash scripts/deploy.sh your-project-review /path/to/html-dir
   ```

## v1.0.0

Initial release.
