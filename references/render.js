#!/usr/bin/env node
/**
 * render.js — Wrap semantic HTML content with a theme CSS + theme-specific header.
 *
 * Usage:
 *   node render.js --input content.html --output index.html --theme editorial
 *   node render.js --input content.html --output index.html --theme magazine --title "My Page"
 *
 * The input HTML should be pure semantic HTML (no <html>, <head>, <body>, <style>).
 * render.js extracts <h1>, <p class="meta">, and the first <p> (abstract) from the content,
 * then generates a theme-specific header structure and wraps everything in a complete HTML document.
 *
 * Options:
 *   --input    Path to semantic HTML file (required)
 *   --output   Path to write final HTML (required)
 *   --theme    Theme name, maps to themes/<name>.css (default: editorial)
 *   --title    Page <title> (optional, auto-detected from first <h1>)
 *   --themes-dir  Custom themes directory (default: same dir as this script + /themes)
 */

const fs = require('fs');
const path = require('path');

function parseArgs(argv) {
  const args = {};
  for (let i = 2; i < argv.length; i++) {
    if (argv[i].startsWith('--') && i + 1 < argv.length) {
      args[argv[i].slice(2)] = argv[++i];
    }
  }
  return args;
}

function extractTitle(html) {
  const m = html.match(/<h1[^>]*>(.*?)<\/h1>/is);
  if (m) return m[1].replace(/<[^>]+>/g, '').trim();
  return 'Document';
}

/**
 * Extract header elements from content HTML:
 * - <h1>...</h1> (title)
 * - <p class="meta">...</p> (metadata line)
 * - First <p> after h1/meta (abstract)
 * Returns { title, titleHtml, meta, abstract, rest }
 */
function extractHeaderParts(html) {
  let rest = html;
  let titleHtml = '';
  let titleText = '';
  let meta = '';
  let abstract = '';

  // Extract <h1>
  const h1Match = rest.match(/<h1[^>]*>(.*?)<\/h1>/is);
  if (h1Match) {
    titleHtml = h1Match[1].trim();
    titleText = titleHtml.replace(/<[^>]+>/g, '').trim();
    rest = rest.replace(h1Match[0], '').trim();
  }

  // Extract <p class="meta">
  const metaMatch = rest.match(/<p\s+class="meta"[^>]*>(.*?)<\/p>/is);
  if (metaMatch) {
    meta = metaMatch[1].trim();
    rest = rest.replace(metaMatch[0], '').trim();
  }

  // Extract first <p> as abstract (only if it's at the start, before any <h2>/<div>/<table>)
  const firstBlock = rest.match(/^(\s*<p(?:\s[^>]*)?>)(.*?)(<\/p>)/is);
  if (firstBlock) {
    // Only take it if it's a plain <p> (no special class) and appears before headings
    const pTag = firstBlock[1];
    if (!pTag.includes('class=')) {
      abstract = firstBlock[2].trim();
      rest = rest.replace(firstBlock[0], '').trim();
    }
  }

  return { titleText, titleHtml, meta, abstract, rest };
}

/**
 * Parse meta string like "Draft v0.3 · April 2026 · Confidential"
 * into structured fields for themes that need them.
 */
function parseMeta(meta) {
  if (!meta) return [];
  return meta.split(/\s*[·|]\s*/).filter(Boolean).map(s => s.trim());
}

function buildHeader(theme, parts) {
  const { titleText, titleHtml, meta, abstract } = parts;
  const metaParts = parseMeta(meta);
  const today = new Date().toISOString().split('T')[0];

  switch (theme) {
    case 'magazine':
      return `
  <header class="hero">
    <div class="hero-inner">
      ${metaParts[2] ? `<div class="overline">${metaParts[2]}</div>` : '<div class="overline">ANALYSIS</div>'}
      <h1>${titleHtml || titleText}</h1>
      ${abstract ? `<p class="abstract">${abstract}</p>` : ''}
      <div class="hero-meta">
        ${metaParts[0] ? `<span>${metaParts[0]}</span>` : ''}
        ${metaParts[1] ? `<span>${metaParts[1]}</span>` : `<span>${today}</span>`}
      </div>
    </div>
  </header>`;

    case 'refined':
      return `
  <header class="header">
    <div class="ornament">&middot; &middot; &middot;</div>
    <h1>${titleHtml || titleText}</h1>
    ${meta ? `<div class="subtitle">${meta}</div>` : ''}
    <div class="header-divider"><div class="diamond"></div></div>
    ${abstract ? `<p class="abstract">${abstract}</p>` : ''}
    <div class="meta-row">
      ${metaParts.map(p => `<div>${p}</div>`).join('\n      ')}
      ${metaParts.length === 0 ? `<div>${today}</div>` : ''}
    </div>
  </header>`;

    case 'swiss':
      return `
  <header class="header">
    <div class="header-grid">
      <h1>${titleHtml || titleText}</h1>
      <div class="header-sidebar">
        ${metaParts.map(p => `<div class="field"><span class="label">Info</span><span class="value">${p}</span></div>`).join('\n        ')}
        ${metaParts.length === 0 ? `<div class="field"><span class="label">Date</span><span class="value">${today}</span></div>` : ''}
      </div>
    </div>
    ${abstract ? `<p class="abstract-bar">${abstract}</p>` : ''}
  </header>`;

    case 'editorial':
    default:
      return `
  <header class="meta-header">
    <h1>${titleHtml || titleText}</h1>
    ${meta ? `<p class="subtitle">${meta}</p>` : ''}
    ${abstract ? `<p class="subtitle">${abstract}</p>` : ''}
    ${metaParts.length > 0 ? `<div class="meta-details">${metaParts.map(p => `<span>${p}</span>`).join(' ')}</div>` : ''}
  </header>`;
  }
}

/**
 * Get the appropriate content wrapper class/structure per theme.
 */
function wrapContent(theme, header, bodyContent) {
  switch (theme) {
    case 'refined':
      return `<div class="page">\n${header}\n  <main>\n${bodyContent}\n  </main>\n</div>`;
    case 'swiss':
      return `<div class="content">\n${header}\n  <main class="main">\n${bodyContent}\n  </main>\n</div>`;
    case 'magazine':
      return `${header}\n<main class="content">\n${bodyContent}\n</main>`;
    case 'editorial':
    default:
      return `<div class="content" id="article">\n${header}\n${bodyContent}\n</div>`;
  }
}

function main() {
  const args = parseArgs(process.argv);

  if (!args.input || !args.output) {
    console.error('Usage: node render.js --input <file> --output <file> [--theme editorial] [--title "..."]');
    process.exit(1);
  }

  const themeName = args.theme || 'editorial';
  const themesDir = args['themes-dir'] || path.join(__dirname, 'themes');
  const cssPath = path.join(themesDir, `${themeName}.css`);

  if (!fs.existsSync(cssPath)) {
    const available = fs.readdirSync(themesDir)
      .filter(f => f.endsWith('.css'))
      .map(f => f.replace('.css', ''));
    console.error(`Theme "${themeName}" not found at ${cssPath}`);
    console.error(`Available themes: ${available.join(', ')}`);
    process.exit(1);
  }

  const content = fs.readFileSync(args.input, 'utf-8');
  const css = fs.readFileSync(cssPath, 'utf-8');

  // Extract header parts from content
  const parts = extractHeaderParts(content);
  const title = args.title || parts.titleText || 'Document';

  // Build theme-specific header
  const header = buildHeader(themeName, parts);

  // Wrap everything
  const wrappedBody = wrapContent(themeName, header, parts.rest);

  const html = `<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${title}</title>
<style>
${css}
</style>
</head>
<body>
${wrappedBody}
<p class="hint" id="hintText"></p>
</body>
</html>`;

  fs.writeFileSync(args.output, html, 'utf-8');
  console.log(`✅ Rendered: ${args.output} (theme: ${themeName}, title: ${title})`);
}

main();
