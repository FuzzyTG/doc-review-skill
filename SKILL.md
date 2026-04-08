---
name: doc-review
description: "Use when the user wants a password-protected document review page with inline annotations, persistent comments, or feedback collection, not a view-only sharing page. Keywords: review, comments, feedback, annotate, inline comments, 批注, 收集反馈, 查看批注, delete review, 下线review."
---

# Doc Review Skill

Deploy articles/documents to Cloudflare Pages with inline text annotation support. Reviewers select text and add comments. Comments persist in Cloudflare D1. Agent can read feedback and iterate. This skill is always password-protected.

## Prerequisites

- **Cloudflare credentials** — set via environment variables or a JSON file:
  - Option A (env vars): `CLOUDFLARE_ACCOUNT_ID` + `CLOUDFLARE_API_TOKEN`
  - Option B (file): `$HOME/.openclaw/credentials/cloudflare.json` with `{"account_id": "...", "api_token": "..."}`
  - The deploy script checks env vars first, then falls back to the JSON file
- Cloudflare API token must have **D1 Edit** permission
- `npx wrangler` must be available (Node.js required)
- D1 database: create with `npx wrangler d1 create <name>` before first deploy

## Workflow

### 1. Deploy for Review

1. Generate pure semantic HTML content (see HTML Content Rules below) → save as `content.html`
2. Run render.js to wrap with theme → produces `index.html`:
   ```bash
   node references/render.js \
     --input /tmp/<project-name>/content.html \
     --output /tmp/<project-name>/index.html \
     --theme editorial
   ```
   (Use the `references/render.js` path relative to this skill directory)
3. Deploy with the protected-only script (annotation injection is automatic):

```bash
bash scripts/deploy.sh <project-name> <directory> <db-name> <db-id>
```

### Password Protected With User-Specified Password
```bash
bash scripts/deploy.sh <project-name> <directory> <db-name> <db-id> --password <password>
```

The deploy script automatically:
- Copies `functions/api/annotations.js` from `references/annotations-api.js`
- Copies `functions/_middleware.js` from `references/middleware-template.js`
- Injects the actual password into the middleware template
- Generates `wrangler.toml` with the D1 binding
- Ensures the D1 tables exist before deploy

**Password protection is mandatory.** No public mode allowed. When no password is specified, the script auto-generates a speakable password and outputs it after deployment. Always share the URL + password with the user.

### 2. Read Feedback

Query D1 for all annotations and comments:
```bash
npx wrangler d1 execute <db-name> --remote --command "
  SELECT a.text as highlighted, c.author, c.text as comment, c.created_at
  FROM comments c JOIN annotations a ON c.annotation_id = a.id
  ORDER BY c.created_at
"
```

Present feedback as a table to the user.

### 3. Iterate

1. Read feedback from D1
2. Modify the HTML content based on comments
3. Redeploy with the same deploy script
4. Processed annotations will auto-disappear (highlighted text no longer matches)

### 4. Cleanup

**Always delete both the Pages project and D1 database together.**

```bash
npx wrangler pages project delete <project-name>
npx wrangler d1 delete <db-name>
```

## Environment Setup

If using the JSON credentials file, source env vars before wrangler commands:
```bash
source <(python3 -c "
import json, os
p = os.environ.get('CF_CREDS', os.path.expanduser('~/.openclaw/credentials/cloudflare.json'))
with open(p) as f:
    c = json.load(f)
print(f'export CLOUDFLARE_ACCOUNT_ID={c[\"account_id\"]}')
print(f'export CLOUDFLARE_API_TOKEN={c[\"api_token\"]}')
")
```

## Notes

- Password is injected by `scripts/deploy.sh` on each deployment
- Comments stored with author name "Reviewer" by default (no login required)
- D1 free tier: 5M reads/day, 100K writes/day — more than enough
- Annotation matching is text-based; if source text changes, old highlights disappear naturally
- Theme CSS files are in `references/themes/` — edit directly in this skill

## HTML Content Rules

When generating HTML content for review pages, follow these rules strictly:

### Semantic HTML Only
- Output **pure semantic HTML** — no `<style>` tags, no inline styles, no `<html>`/`<head>`/`<body>` wrappers
- Use standard tags: `<h1>`-`<h4>`, `<p>`, `<table>`, `<ul>`/`<ol>`, `<blockquote>`, `<details>`, `<hr>`

### Structural Conventions
- `<table>` for comparisons, scores, data grids
- `<blockquote>` for key takeaways or important quotes
- `<details><summary>` for collapsible sections
- `<div class="toc">` for table of contents
- `<p class="meta">` for metadata lines (date, author, etc.)
- `<div class="footer">` for footer text

### Badge Classes
- `<span class="badge badge-green">Pass</span>` — positive
- `<span class="badge badge-yellow">Warning</span>` — caution
- `<span class="badge badge-red">Miss</span>` — negative

### Component Library (Important — Must Use)

Use these components for visual hierarchy. Plain `<p>` + `<ul>` HTML is not acceptable.

#### Callout Boxes
```html
<div class="callout">Default callout: general emphasis</div>
<div class="callout callout-conclusion"><strong>Conclusion:</strong> core judgment</div>
<div class="callout callout-warning"><strong>Warning:</strong> risks and concerns</div>
<div class="callout callout-important"><strong>Important:</strong> key facts</div>
```

#### Path Cards — Option/Path Comparison
```html
<div class="path-card">
  <div class="path-label">Option A</div>
  <p>Description...</p>
</div>
<div class="path-card recommended">
  <div class="path-label">Option B (Recommended)</div>
  <p>Description...</p>
</div>
```

#### Reasoning Chain
```html
<div class="reasoning-chain">
  <ol>
    <li>Step 1...</li>
    <li>Step 2...</li>
    <li>Therefore...</li>
  </ol>
</div>
```

#### Action Items
```html
<div class="action-items">
  <ol>
    <li><strong>Short-term (1 week):</strong> action...</li>
    <li><strong>Mid-term (1 month):</strong> action...</li>
  </ol>
</div>
```

#### Final Recommendation (dark block)
```html
<div class="final-rec">
  <p><strong>Final recommendation:</strong> one-sentence conclusion at the end.</p>
</div>
```

#### Keywords
```html
<div class="keywords">
  <span class="kw">Tag1</span>
  <span class="kw">Tag2</span>
</div>
```

#### Section Dividers (best with magazine/refined themes)
```html
<div class="section-divider"><span class="num">Section 01</span></div>
```

#### Disclaimer
```html
<p class="disclaimer">This report is AI-generated and for reference only.</p>
```

### Content Quality Standards

1. **Each h2 section must contain at least 1 component** (callout / path-card / table / reasoning-chain etc.)
2. **Key conclusions must use callout-conclusion**, not buried in plain paragraphs
3. **Use path-card or table for comparisons**, not plain text lists
4. **End with final-rec** if the content has a clear conclusion/recommendation
5. **TOC must use `<div class="toc">`**, not bare `<ul>`

### Available Themes
- `editorial` — long-form analysis (serif body + sans headings, warm gray, 740px column). **Default.**
- `magazine` — dramatic editorial (Playfair Display headings, dark hero, red accent, section numbering)
- `swiss` — Swiss international style (IBM Plex Mono, pure white, black+red+blue, 900px grid)
- `refined` — premium feel (Cormorant Garamond, cream + gold + sage, parchment texture, 700px centered)

### Theme Selection
- User specifies → use that theme
- No preference → auto-select based on content:
  - `editorial`: deep analysis, research, evaluations — **default**
  - `magazine`: high-impact editorial, visually striking reports
  - `swiss`: technical specs, engineering docs, data summaries
  - `refined`: executive briefs, premium white papers
- If unsure, default to `editorial`.
