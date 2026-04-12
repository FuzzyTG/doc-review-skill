# Changelog

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
