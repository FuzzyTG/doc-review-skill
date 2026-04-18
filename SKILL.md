---
name: doc-review
description: "Use when the user wants a password-protected document review page with inline annotations, persistent comments, or feedback collection, not a view-only sharing page. Keywords: review, comments, feedback, annotate, inline comments, 批注, 收集反馈, 查看批注, delete review, 下线review."
---

# Doc Review Skill

Deploy articles/documents to Cloudflare Pages with inline text annotation support. Reviewers select text and add comments. Comments persist in Cloudflare D1. Agent can read feedback and iterate. This skill is always password-protected.

## Prerequisites

- Cloudflare credentials: `$HOME/.openclaw/credentials/cloudflare.json`
- Cloudflare API token must have **D1 Edit** permission
- D1 database is created automatically by deploy.sh — **禁止手动创建或传入 DB 参数**

## Key Rules

1. **Project name must end with `-review`** — deploy.sh enforces this
2. **每个 review page 有独立的 D1 数据库** — 命名规则 `review-<project-name>`，自动创建，禁止复用
3. **持久化目录**: `$HOME/.openclaw/published-content/<project-name>/` — 存放 meta.json、content.html、index.html
4. **content.html 是构建产物** — redeploy 时从源文件重新生成，不要直接改 content.html

## Workflow

### 1. Deploy for Review (首次发布)

1. 确定源文件，生成纯语义 HTML content（see HTML Content Rules below）→ save as `content.html`
2. Run render.js to wrap with theme → produces `index.html`:
   ```bash
   node references/render.js \
     --input /tmp/<project-name>/content.html \
     --output /tmp/<project-name>/index.html \
     --theme editorial
   ```
3. Deploy（annotation injection + D1 creation is fully automatic）:
   ```bash
   bash scripts/deploy.sh <project-name> /tmp/<project-name>
   ```
4. **部署后立即更新 meta.json**（deploy.sh 自动创建初始 meta.json，agent 需补充源文件信息）:
   ```bash
   python3 -c "
   import json
   meta_path = '$HOME/.openclaw/published-content/<project-name>/meta.json'
   with open(meta_path) as f: meta = json.load(f)
   meta['source'] = '<源文件路径，如 /path/to/your/source/file.md>'
   meta['sourceType'] = '<markdown|pdf|text|generated>'
   meta['theme'] = '<实际使用的主题>'
   with open(meta_path, 'w') as f: json.dump(meta, f, indent=2, ensure_ascii=False)
   "
   ```

### Password Protected With User-Specified Password
```bash
bash scripts/deploy.sh <project-name> /tmp/<project-name> --password <password>
```

The deploy script automatically:
- **Creates a dedicated D1 database** named `review-<project-name>` (1:1 per project, never reused)
- Creates the annotations + comments tables
- Copies `functions/api/annotations.js` from `references/annotations-api.js`
- Copies `functions/_middleware.js` from `references/middleware-template.js`
- Sets `PAGE_PASSWORD` via `wrangler pages secret put` (password never in source code)
- Generates `wrangler.toml` with the D1 binding
- Persists content.html, index.html, and meta.json to `$HOME/.openclaw/published-content/<project-name>/`

**⚠️ 禁止手动传入 db-name 或 db-id。脚本自动管理，确保每个 review page 有独立的 D1 数据库。**

**密码管理**:
- 首次部署: `--password` 参数指定，或自动生成
- 密码通过 Cloudflare Secret 存储，不在 meta.json 或源码中
- 换密码: `deploy.sh <project-name> --change-password <new-password>`（自动更新 secret + redeploy + meta.json）
- Redeploy 不需要重新设密码（secret 跨部署持久化）

### 2. Read Feedback

Query D1 for all annotations and comments (DB name is always `review-<project-name>`):
```bash
npx wrangler d1 execute review-<project-name> --remote --command "
  SELECT a.text as highlighted, c.author, c.text as comment, c.created_at
  FROM comments c JOIN annotations a ON c.annotation_id = a.id
  ORDER BY c.created_at
"
```

Present feedback as a table to the user.

### 3. Iterate (Redeploy)

When user requests changes based on review feedback:

1. Read `$HOME/.openclaw/published-content/<project-name>/meta.json` — 获取 source 路径和 sourceType
2. Read D1 feedback（同 Section 2）
3. **根据 sourceType 决定如何更新**:
   - `markdown`/`text`: 从 `source` 路径重新读取源文件 → 重新生成 content.html
   - `pdf`: 源文件还在就重新提取，不在就用 `$HOME/.openclaw/published-content/<project-name>/content.html`
   - `generated`: 用 `$HOME/.openclaw/published-content/<project-name>/content.html` 作为基础修改
4. Render with same theme → `index.html`
5. **使用完全相同的 project-name** redeploy:
   ```bash
   bash scripts/deploy.sh <project-name> /tmp/<project-name>
   ```
   - 同名 project → 同名 DB → annotations 数据保留
   - **Redeploy 时必须传 `--password` 以保持原密码**，否则会生成新密码覆盖旧 secret

**⚠️ Redeploy 必须使用相同的 project-name。换名字 = 新页面 + 新 DB，旧数据丢失。**

Processed annotations will auto-disappear (highlighted text no longer matches in the new page).

### 4. Cleanup (Take Down)

**删除项目时必须同时清理 D1 数据库和本地持久化目录**，不要留残留。

```bash
# 1. 删除 Pages 项目
npx wrangler pages project delete <project-name>

# 2. 删除对应的 D1 数据库（命名规则固定为 review-<project-name>）
npx wrangler d1 delete review-<project-name>

# 3. 删除本地持久化目录
rm -rf $HOME/.openclaw/published-content/<project-name>
```

三步都做完才算清理完毕。

## meta.json Schema

```json
{
  "type": "review",
  "project": "my-report-review",
  "source": "/path/to/your/source/file.md",
  "sourceType": "markdown",
  "theme": "editorial",
  "dbName": "review-my-report-review",
  "dbId": "uuid-here",
  "created": "2026-04-12T13:20:00+08:00",
  "lastDeployed": "2026-04-12T15:30:00+08:00"
}
```

sourceType values:
- `markdown` — knowledge-base 或其他路径的 .md 文件（最常见）
- `pdf` — PDF 文件
- `text` — 纯文本文件
- `generated` — 对话中直接生成，无源文件

## Environment Setup

All wrangler commands need:
```bash
source <(python3 -c "
import json
with open('$HOME/.openclaw/credentials/cloudflare.json') as f:
    c = json.load(f)
print(f'export CLOUDFLARE_ACCOUNT_ID={c[\"account_id\"]}')
print(f'export CLOUDFLARE_API_TOKEN={c[\"api_token\"]}')
")
```

## Notes

- Password is stored as Cloudflare Secret (PAGE_PASSWORD), never in source code or meta.json
- Comments stored with author name "Reviewer" by default (no login required)
- D1 free tier: 5M reads/day, 100K writes/day — more than enough
- Annotation matching is text-based; if source text changes, old highlights disappear naturally
- Persistent state lives in `$HOME/.openclaw/published-content/<project-name>/` — shared across all agents
- **Theme files are synced from `cloudflare-pages`** — do not edit `themes/` or `render.js` here directly. Modify in `cloudflare-pages/references/` then run `bash scripts/sync-themes.sh (from cloudflare-pages skill)`

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

### Component Library (重要 — 必须使用)

生成 content.html 时，**必须积极使用以下组件**让内容有视觉层次。纯 `<p>` + `<ul>` 的平铺 HTML 是不合格的。

#### Callout Boxes — 突出关键信息
```html
<div class="callout">默认 callout：一般性重点信息</div>
<div class="callout callout-conclusion"><strong>结论：</strong>核心判断和最终建议</div>
<div class="callout callout-warning"><strong>注意：</strong>风险、隐忧、需关注的问题</div>
<div class="callout callout-important"><strong>重要：</strong>关键数据、不可忽视的事实</div>
```

#### Path Cards — 选项/路径对比
```html
<div class="path-card">
  <div class="path-label">方案 A</div>
  <p>描述内容...</p>
</div>
<div class="path-card recommended">
  <div class="path-label">方案 B（推荐）</div>
  <p>描述内容...</p>
</div>
```

#### Reasoning Chain — 逻辑推理链
```html
<div class="reasoning-chain">
  <ol>
    <li>第一步推理...</li>
    <li>第二步推理...</li>
    <li>因此得出结论...</li>
  </ol>
</div>
```

#### Action Items — 行动建议
```html
<div class="action-items">
  <ol>
    <li><strong>短期（1 周内）：</strong>具体行动...</li>
    <li><strong>中期（1 个月）：</strong>具体行动...</li>
  </ol>
</div>
```

#### Final Recommendation — 最终建议（深色块）
```html
<div class="final-rec">
  <p><strong>最终建议：</strong>一句话核心结论，放在文末作为收尾。</p>
</div>
```

#### Keywords — 标签
```html
<div class="keywords">
  <span class="kw">标签1</span>
  <span class="kw">标签2</span>
</div>
```

#### Section Dividers — 章节分隔（magazine/refined 主题效果最佳）
```html
<div class="section-divider"><span class="num">Section 01</span></div>
```

#### Disclaimer — 文末免责声明
```html
<p class="disclaimer">本报告由 AI 生成，仅供参考，不构成专业建议。</p>
```

### 内容质量标准

生成 content.html 时必须做到：
1. **每个 h2 section 至少包含 1 个组件**（callout / path-card / table / reasoning-chain 等）
2. **关键结论必须用 callout-conclusion**，不要藏在普通段落里
3. **有对比就用 path-card 或 table**，不要用纯文字罗列
4. **文末必须有 final-rec**（如果内容有明确结论/建议）
5. **TOC 必须用 `<div class="toc">`** 包裹，不要用裸 `<ul>`

### Available Themes
- `editorial` — long-form analysis style (serif body + sans headings, warm gray background, deep blue-gray accents, 740px narrow column). Best for deep analysis, research reports. Features: callout boxes, path cards, reasoning chains, action items.
- `magazine` — 杂志长文风格 (Playfair Display headings + DM Sans body, dark hero header, red accent, "Section 01" numbering, *** dividers). Best for high-impact editorial pieces, visually striking reports. Requires Google Fonts.
- `swiss` — 瑞士国际主义风格 (IBM Plex Mono body + Instrument Serif headings, pure white, black+red+blue, grid layout, 900px). Best for ultra-clean, rational, engineering-feel documents. Requires Google Fonts.
- `refined` — 高端精致风格 (Cormorant Garamond serif body + Outfit sans labels, cream background with parchment texture, gold + sage green + rose, centered layout, 700px). Best for premium white papers, executive briefs. Requires Google Fonts.

### Theme Selection
- If user specifies a theme (e.g., "灰的"/"灰色那个"/"editorial 风格", "magazine 风格"/"杂志风"/"黑的", "swiss 风格"/"白的"/"极简", "refined"/"金的"/"精致"/"fancy"), use that theme.
- If user doesn't specify, **auto-select based on content type**:
  - `editorial`: deep analysis, long-form arguments, school/product comparisons, research briefs, formal reports, evaluations — **default choice**
  - `magazine`: high-impact editorial pieces that benefit from dramatic visual presentation
  - `swiss`: ultra-clean, rational, engineering-style documents, technical specs, comparisons, data summaries
  - `refined`: premium white papers, executive briefs, luxury-feel documents, high-stakes analysis
- If unsure, default to `editorial`.
