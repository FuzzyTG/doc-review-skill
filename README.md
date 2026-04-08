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

## Themes

| Theme | Style | Best For |
|-------|-------|----------|
| `editorial` | Warm gray, serif body, 740px column | Deep analysis, research reports (default) |
| `magazine` | Dark hero, Playfair Display, red accent | High-impact editorial pieces |
| `swiss` | Pure white, IBM Plex Mono, grid layout | Technical specs, engineering docs |
| `refined` | Cream + gold, Cormorant Garamond, parchment | Executive briefs, premium white papers |

## How It Works

1. Agent generates semantic HTML content
2. `render.js` wraps it with the selected theme CSS
3. Annotation JS/CSS from `annotate-template.html` is injected
4. `deploy.sh` deploys to Cloudflare Pages with D1 backend + password middleware

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
