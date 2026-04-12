# Doc Review Skill for OpenClaw

An [OpenClaw](https://github.com/openclaw/openclaw) agent skill that deploys password-protected document review pages to Cloudflare Pages with inline text annotations and persistent comments.

## Features

- 📝 **Inline Annotations** — Reviewers select any text to add comments (W3C TextQuoteSelector for precise positioning)
- 💬 **Persistent Comments** — Stored in Cloudflare D1 (serverless SQLite)
- 🔒 **Password Protected** — Every page requires a password via Cloudflare Secrets (auto-generated if not specified)
- 🎨 **4 Themes** — editorial, magazine, swiss, refined
- 🔄 **Iterative** — Re-deploy after addressing feedback; old annotations auto-disappear
- 🗄️ **Auto D1 Creation** — Each project gets a dedicated D1 database automatically
- 🔑 **Change Password** — Update password without redeploying content

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

### Deploy

```bash
# Basic deploy (password auto-generated)
bash scripts/deploy.sh my-report-review /path/to/html-dir

# With specific password
bash scripts/deploy.sh my-report-review /path/to/html-dir --password mypassword
```

**Note:** Project name must end with `-review`. The D1 database is created automatically — no need to specify database name or ID.

### Change Password

```bash
bash scripts/deploy.sh my-report-review --change-password newpassword
```

This updates the Cloudflare Secret and redeploys from the saved snapshot.

### How Passwords Work

Passwords are stored as **Cloudflare Secrets** (`PAGE_PASSWORD` and `PAGE_SECRET`), never in source code or config files. The middleware reads secrets from the environment at runtime.

- `PAGE_PASSWORD` — the plaintext password reviewers enter
- `PAGE_SECRET` — a derived hash used for cookie signing: `cloudflare-pages-auth-$(echo -n 'yourpassword' | sha256sum | cut -d' ' -f1)`

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
    ├── deploy.sh                     # Deployment script
    └── inject-annotations.sh         # HTML injection helper
```

## License

MIT
