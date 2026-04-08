# Doc Review Skill for OpenClaw

An [OpenClaw](https://github.com/openclaw/openclaw) agent skill that deploys password-protected document review pages to Cloudflare Pages with inline text annotations and persistent comments.

## Features

- 📝 **Inline Annotations** — Reviewers select any text to add comments
- 💬 **Persistent Comments** — Stored in Cloudflare D1 (serverless SQLite)
- 🔒 **Password Protected** — Every page requires a password (auto-generated if not specified)
- 🎨 **4 Themes** — editorial, magazine, swiss, refined
- 🔄 **Iterative** — Re-deploy after addressing feedback; old annotations auto-disappear

## Prerequisites

- [OpenClaw](https://github.com/openclaw/openclaw) installed
- Cloudflare account with API token (needs **D1 Edit** permission)
- Node.js (for `npx wrangler`)

## Installation

```bash
# Install as an OpenClaw skill
openclaw skill install FuzzyTG/doc-review-skill
```

Or clone manually into your OpenClaw skills directory:
```bash
git clone https://github.com/FuzzyTG/doc-review-skill.git ~/.openclaw/skills/doc-review
```

## Configuration

Set Cloudflare credentials via **either**:

1. Environment variables: `CLOUDFLARE_ACCOUNT_ID` + `CLOUDFLARE_API_TOKEN`
2. JSON file at `~/.openclaw/credentials/cloudflare.json`:
   ```json
   {
     "account_id": "your-account-id",
     "api_token": "your-api-token"
   }
   ```

## Usage

Once installed, tell your OpenClaw agent:

> "Deploy this document for review"
> "Create a review page for this report"
> "发布这个文档收集批注"

The agent will generate themed HTML, inject the annotation system, and deploy to Cloudflare Pages.

## Password Protection

Every review page requires a password. This provides **basic spam prevention only** — it is not a secure authentication system. Anyone with the password can access and annotate the page, making it easy to share with multiple reviewers.

- **Not for sensitive data** — the password is a simple shared secret, not per-user authentication
- **Cookie-based session** — after entering the password, a cookie is set that expires after **24 hours**; reviewers will need to re-enter the password after that
- If no password is specified at deploy time, one is auto-generated (speakable format like `maple-river-velvet-64`)

## Themes

### Editorial — Long-form analysis (default)
Warm gray, serif body, 740px narrow column. Best for deep analysis, research reports.

![Editorial theme](screenshots/editorial.png)

### Magazine — Dramatic editorial
Dark hero header, Playfair Display headings, red accent, section numbering. Best for high-impact reports.

![Magazine theme](screenshots/magazine.png)

### Swiss — International style
Pure white, IBM Plex Mono, black+red+blue grid layout, 900px. Best for technical specs, engineering docs.

![Swiss theme](screenshots/swiss.png)

### Refined — Premium feel
Cream background with parchment texture, Cormorant Garamond, gold + sage accents, 700px centered. Best for executive briefs.

![Refined theme](screenshots/refined.png)

## How It Works

1. Tell your OpenClaw agent to deploy a document for review
2. Agent generates themed HTML, injects the annotation system, and deploys to Cloudflare Pages
3. Share the URL + password with reviewers
4. **Reviewers select any text and leave inline comments** — no login required, comments persist in Cloudflare D1
5. **Ask your agent to check feedback** — it queries D1 directly, reads all annotations and comments, then iterates on the document based on reviewer input
6. Redeploy the updated version — old annotations on changed text auto-disappear

The key value: **your OpenClaw agent closes the feedback loop automatically.** Reviewers comment → agent reads → agent revises → redeploy. No manual copy-pasting of feedback.

## File Structure

```
├── SKILL.md                          # Agent instructions
├── references/
│   ├── render.js                     # Theme renderer
│   ├── annotate-template.html        # Annotation UI (JS + CSS)
│   ├── annotations-api.js            # D1 API for annotations
│   ├── middleware-template.js         # Password protection middleware
│   └── themes/
│       ├── editorial.css
│       ├── magazine.css
│       ├── swiss.css
│       └── refined.css
└── scripts/
    └── deploy.sh                     # Deployment script
```

## License

MIT
