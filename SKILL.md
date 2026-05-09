---
name: doc-review
description: "Use when the user wants a password-protected document review page with inline annotations, persistent comments, or feedback collection, not a view-only sharing page. Keywords: review, comments, feedback, annotate, inline comments, 批注, 收集反馈, 查看批注, delete review, 下线review."
---

# Doc Review Skill

Deploy articles/documents to Cloudflare Pages with inline text annotation support. Reviewers select text and add comments. Comments persist in Cloudflare D1. Agent can read feedback and iterate. This skill is always password-protected.

## Prerequisites

- Cloudflare account with API token (must have **D1 Edit** permission)
- Node.js (for `npx wrangler`)
- Cloudflare credentials configured via one of:
  - Environment variables: `CLOUDFLARE_ACCOUNT_ID` + `CLOUDFLARE_API_TOKEN`
  - JSON file at `~/.doc-review/credentials/cloudflare.json`
  - JSON file at `~/.openclaw/credentials/cloudflare.json` (OpenClaw users)
- D1 database is created automatically by deploy.sh — **禁止手动创建或传入 DB 参数**

### First-Time Setup

If no credentials are found, the agent should guide the user:

1. Ask: "Do you have a Cloudflare account with an API token that has D1 Edit permission?"
2. If yes → collect account ID and API token → save to `~/.doc-review/credentials/cloudflare.json`:
   ```bash
   mkdir -p ~/.doc-review/credentials
   cat > ~/.doc-review/credentials/cloudflare.json << 'EOF'
   {
     "account_id": "YOUR_ACCOUNT_ID",
     "api_token": "YOUR_API_TOKEN"
   }
   EOF
   chmod 600 ~/.doc-review/credentials/cloudflare.json
   ```
3. If no → guide them to create a Cloudflare account and API token with D1 Edit permission
4. Verify with: `npx wrangler d1 list`

## Key Rules

1. **Project name must end with `-review`** — deploy.sh enforces this
2. **每个 review page 有独立的 D1 数据库** — 命名规则 `review-<project-name>`，自动创建，禁止复用
3. **持久化目录**: `$HOME/.doc-review/published-content/<project-name>/` — 存放 meta.json、content.html、index.html（向后兼容 `$HOME/.openclaw/published-content/`）
4. **content.html 是构建产物** — redeploy 时从源文件重新生成，不要直接改 content.html

## Internal Scripts — Do Not Call Directly

The following scripts are internal to the workflow. They are called automatically by `deploy.sh` or by specific workflow steps. **Do not run them outside of these contexts.**

| Script | Called by | Purpose |
|--------|----------|---------|
| `scripts/inject-annotations.sh` | `deploy.sh` (automatically) | Injects annotation UI into index.html |
| `references/annotations-api.js` | `deploy.sh` (copied to deploy dir) | D1 API for annotations |
| `references/middleware-template.js` | `deploy.sh` (copied to deploy dir) | Password protection middleware |

## Workflow

### 1. Deploy for Review (首次发布)

This workflow has 4 sequential steps. It is NOT complete until all 4 are done.

#### Pre-flight

Before starting any work, create a checklist:

- [ ] Step 1: Generate HTML content (md2html → component enhancement → content.html)
- [ ] Step 2: Render with theme (render.js → index.html)
- [ ] Step 3: Deploy to Cloudflare (deploy.sh — handles annotation injection, D1, secrets)
- [ ] Step 4: Update meta.json with source info

Track this checklist. Mark each step as you complete it.

---

#### Step 1: Generate HTML content

确定源文件，用 md2html 脚本生成基线 HTML，然后按 HTML Content Rules 做组件增强 → save as `content.html`
```bash
# Step 1a: 脚本生成基线（确定性 1:1 映射）
bash scripts/md2html.sh <source.md> /tmp/<project-name>/baseline.html
# Step 1b: Agent 读取 baseline.html，按 HTML Content Rules 做组件增强，输出 content.html
# ⚠️ 只能添加组件包装，不能替换基础 HTML 结构（见 HTML Content Rules）
```

**Checkpoint**: `/tmp/<project-name>/content.html` exists and is non-empty.
If checkpoint fails: re-read baseline.html and retry enhancement.

**→ Mark Step 1 complete. Proceed to Step 2.**

---

#### Step 2: Render with theme

Run render.js to wrap with theme → produces `index.html`:
```bash
node references/render.js \
  --input /tmp/<project-name>/content.html \
  --output /tmp/<project-name>/index.html \
  --theme editorial
```

**Checkpoint**: `/tmp/<project-name>/index.html` exists and contains `<html`.
If checkpoint fails: verify content.html is valid HTML, check theme name, retry.

**→ Mark Step 2 complete. Proceed to Step 3.**

---

#### Step 3: Deploy to Cloudflare

Deploy（annotation injection + D1 creation is fully automatic）:
```bash
bash scripts/deploy.sh <project-name> /tmp/<project-name>
```

deploy.sh automatically handles:
- **Creates a dedicated D1 database** named `review-<project-name>` (1:1 per project, never reused)
- Creates the annotations + comments tables
- **Injects annotation UI** (CSS + HTML + JS) into index.html
- Copies middleware and API functions
- Sets `PAGE_PASSWORD` via `wrangler pages secret put` (password never in source code)
- Generates `wrangler.toml` with the D1 binding
- Persists content.html, index.html, and meta.json to `$HOME/.doc-review/published-content/<project-name>/`

**Checkpoint**: deploy.sh exits with code 0 and prints the project URL.
If checkpoint fails: check Cloudflare credentials and wrangler output.

**→ Mark Step 3 complete. Proceed to Step 4.**

---

#### Step 4: Update meta.json

部署后立即更新 meta.json（deploy.sh 自动创建初始 meta.json，agent 需补充源文件信息）:
```bash
python3 -c "
import json
meta_path = '$HOME/.doc-review/published-content/<project-name>/meta.json'
with open(meta_path) as f: meta = json.load(f)
meta['source'] = '<源文件路径，如 /path/to/your/source/file.md>'
meta['sourceType'] = '<markdown|pdf|text|generated>'
meta['theme'] = '<实际使用的主题>'
with open(meta_path, 'w') as f: json.dump(meta, f, indent=2, ensure_ascii=False)
"
```

**Checkpoint**: meta.json contains `source`, `sourceType`, and `theme` fields with non-null values.
If checkpoint fails: read meta.json, identify missing fields, update manually.

**→ Mark Step 4 complete. Proceed to Post-flight.**

---

#### Post-flight

Review your checklist:

- [ ] Step 1 — content.html generated? Non-empty?
- [ ] Step 2 — index.html rendered with theme? Contains `<html`?
- [ ] Step 3 — deploy.sh succeeded? URL printed?
- [ ] Step 4 — meta.json updated with source info?

If ANY step is incomplete, go back and complete it now.
The workflow ends here, only after all boxes are checked.

---

### Password Protected With User-Specified Password
```bash
bash scripts/deploy.sh <project-name> /tmp/<project-name> --password <password>
```

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

1. Read `$HOME/.doc-review/published-content/<project-name>/meta.json` — 获取 source 路径和 sourceType
2. Read D1 feedback（同 Section 2）
3. **根据 sourceType 决定如何更新**:
   - `markdown`/`text`: 从 `source` 路径重新读取源文件 → 用 `md2html.sh` 重新生成基线 → 按 HTML Content Rules 做组件增强 → content.html
   - `pdf`: 源文件还在就重新提取，不在就用 `$HOME/.doc-review/published-content/<project-name>/content.html`
   - `generated`: 用 `$HOME/.doc-review/published-content/<project-name>/content.html` 作为基础修改
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
rm -rf $HOME/.doc-review/published-content/<project-name>
```

三步都做完才算清理完毕。

## Error Handling

| Failed component | Action |
|-----------------|--------|
| `md2html.sh` fails (marked not installed) | Run `npx marked --gfm` directly. Note in output. |
| `render.js` fails (theme not found) | List available themes in `references/themes/`, retry with valid name. |
| `deploy.sh` fails (credentials missing) | Print credential setup instructions. Do not abort — guide user through setup. |
| D1 database creation fails | Check if DB already exists (`wrangler d1 list`). If yes, continue. If no, log error. |
| `wrangler pages secret put` fails | Retry up to 3 times (deploy.sh handles this). If still failing, log error and continue. |
| `wrangler pages deploy` fails | Check wrangler output for specific error. Common: project name conflict, auth issue. |
| meta.json update fails | Log warning. Deploy succeeded — meta.json can be updated manually later. |
| Source file not found (during redeploy) | Fall back to `$HOME/.doc-review/published-content/<project-name>/content.html`. |
| All steps fail | Notify user with full error details. Do not go silent. |

**Principle**: Degrade gracefully, never abort silently.

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

deploy.sh resolves Cloudflare credentials automatically using this fallback chain:

1. **Env vars already set** (`CLOUDFLARE_ACCOUNT_ID` + `CLOUDFLARE_API_TOKEN`) → used as-is
2. **`CF_CREDS` env var** → reads from that file path
3. **`~/.doc-review/credentials/cloudflare.json`** → default for standalone installs
4. **`~/.openclaw/credentials/cloudflare.json`** → backward compat for OpenClaw users

For manual wrangler commands outside deploy.sh (e.g., reading feedback), set env vars first:
```bash
export CLOUDFLARE_ACCOUNT_ID="your-account-id"
export CLOUDFLARE_API_TOKEN="your-api-token"
```

## Notes

- Password is stored as Cloudflare Secret (PAGE_PASSWORD), never in source code or meta.json
- Comments stored with author name "Reviewer" by default (no login required)
- D1 free tier: 5M reads/day, 100K writes/day — more than enough
- Annotation matching is text-based; if source text changes, old highlights disappear naturally
- Persistent state lives in `$HOME/.doc-review/published-content/<project-name>/` (falls back to `$HOME/.openclaw/published-content/` for existing OpenClaw installs)
- **Theme files are synced from `cloudflare-pages`** — do not edit `themes/` or `render.js` here directly. Modify in `cloudflare-pages/references/` then run `bash scripts/sync-themes.sh (from cloudflare-pages skill)`

## HTML Content Rules

When generating HTML content for review pages, follow these rules strictly.

### ⚠️ 最高优先级：源文件结构 1:1 映射

**这条规则优先于所有其他规则。**

源文件的 Markdown 结构必须 1:1 映射到 HTML 基础标签。用 `md2html.sh` 脚本生成基线，agent 只在基线上做组件增强，**不能替换基础 HTML 结构**。

| Markdown | HTML | 备注 |
|----------|------|------|
| `# H1` | `<h1>` | 直接映射 |
| `## H2` | `<h2>` | 直接映射 |
| `### H3` | `<h3>` | 直接映射 |
| `- item` | `<ul><li>` | **不升级为组件** |
| `1. item` | `<ol><li>` | **不升级为组件** |
| `> quote` | `<blockquote>` | **不升级为 callout** |
| `**bold**` | `<strong>` | |
| `---` | `<hr>` | |
| 普通段落 | `<p>` | |
| 表格 | `<table>` | |

**铁律**：脚本输出即为基线。Agent 只能在基线上**添加**组件包装（在现有结构外层包一个 `<div>`），不能**替换**基础 HTML 标签。

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

### Component Library（语义匹配，不强制使用）

组件是**可选增强**，只在内容语义确实匹配时使用。**模糊时默认降级**：不确定该不该用组件，就用基础 HTML 标签。

#### Callout Boxes — 突出关键信息
```html
<div class="callout">默认 callout：一般性重点信息</div>
<div class="callout callout-conclusion"><strong>结论：</strong>核心判断和最终建议</div>
<div class="callout callout-warning"><strong>注意：</strong>风险、隐忧、需关注的问题</div>
<div class="callout callout-important"><strong>重要：</strong>关键数据、不可忽视的事实</div>
```
- ✅ 正例：文章的核心结论、关键数据成果（如 "17K WAU at 161% of target"）、不可忽视的风险警告
- ❌ 反例：普通段落里的重点、每段话的小结、一般性描述

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
- ✅ 正例：两个互斥方案需要决策（"保守方案 vs 激进方案"）
- ❌ 反例：三个独立要点恰好并列、普通 bullet list 内容

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
- ✅ 正例：明确的因果推理链（A→B→C→结论）
- ❌ 反例：普通有序步骤、操作流程、并列要点

#### Action Items — 行动建议
```html
<div class="action-items">
  <ol>
    <li><strong>短期（1 周内）：</strong>具体行动...</li>
    <li><strong>中期（1 个月）：</strong>具体行动...</li>
  </ol>
</div>
```
- ✅ 正例：文档明确列出的行动建议/下一步计划
- ❌ 反例：一般性描述恰好用了有序列表

#### Final Recommendation — 最终建议（深色块）
```html
<div class="final-rec">
  <p><strong>最终建议：</strong>一句话核心结论，放在文末作为收尾。</p>
</div>
```
- ✅ 正例：文末确实有明确的总结性建议
- ❌ 反例：文章没有建议性质，不硬加

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

### 组件使用判断原则

组件是为了帮助读者理解内容的**语义结构**，不是为了让页面看起来花哨。判断顺序：

1. 基础 HTML 能清晰表达吗？→ 能就不用组件
2. 内容语义确实匹配某个组件定义吗？→ 匹配才用
3. 不确定？→ **默认降级，用基础 HTML**

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
