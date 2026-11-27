// Safe Markdown rendering for Agent Board dashboards.
//
// Card text and thread entries are Markdown written by agents and people, so treat them as
// untrusted. This renderer builds DOM nodes with createElement/textContent and never uses
// innerHTML: raw HTML in the text shows as text, HTML comments are dropped, and only http(s)
// links become anchors (opened in a new tab with rel="noopener noreferrer").
//
// Covers: headings (h1-h6, capped at h4), paragraphs with line breaks, bullet and numbered lists
// (nested by indent), tables (GitHub pipe syntax), fenced code blocks, blockquotes, horizontal
// rules, **bold**, *italic*, ~~strike~~, `code`, [text](https://...) and bare https:// URLs.
//
// Usage: paste into a dashboard script (dashboards can load only their own files), then call
// renderMd(element, markdownText) inside the drawing that shows a card or thread entry. Give the
// element a class with modest spacing for p, ul, ol, table, pre and blockquote.

function mdInline(text) {
  const out = [];
  const re = /(`+)([^`]+?)\1|\*\*([^*]+?)\*\*|__([^_]+?)__|\*([^*\s][^*]*?)\*|_([^_\s][^_]*?)_|~~([^~]+?)~~|\[([^\]]+)\]\(([^)\s]+)\)|(https?:\/\/[^\s<>()]+[^\s<>().,;:!?'"])/g;
  let last = 0, m;
  while ((m = re.exec(text))) {
    if (m.index > last) out.push(document.createTextNode(text.slice(last, m.index)));
    let n;
    if (m[2] != null) { n = document.createElement('code'); n.textContent = m[2]; }
    else if (m[3] != null || m[4] != null) { n = document.createElement('strong'); n.append(...mdInline(m[3] ?? m[4])); }
    else if (m[5] != null || m[6] != null) { n = document.createElement('em'); n.append(...mdInline(m[5] ?? m[6])); }
    else if (m[7] != null) { n = document.createElement('s'); n.append(...mdInline(m[7])); }
    else if (m[8] != null) {
      if (/^https?:\/\//i.test(m[9])) { n = document.createElement('a'); n.href = m[9]; n.target = '_blank'; n.rel = 'noopener noreferrer'; n.append(...mdInline(m[8])); }
      else { n = document.createTextNode(m[8]); }
    } else { n = document.createElement('a'); n.href = m[10]; n.target = '_blank'; n.rel = 'noopener noreferrer'; n.textContent = m[10]; }
    out.push(n); last = re.lastIndex;
  }
  if (last < text.length) out.push(document.createTextNode(text.slice(last)));
  return out;
}
function mdBlocks(src) {
  const lines = String(src || '').replace(/\r\n?/g, '\n').split('\n');
  const out = []; let i = 0;
  const isTableSep = (l) => /^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$/.test(l);
  const cells = (l) => l.trim().replace(/^\||\|$/g, '').split('|').map((c) => c.trim());
  const listRe = /^(\s*)([-*+]|\d+[.)])\s+(.*)$/;
  while (i < lines.length) {
    const line = lines[i];
    if (!line.trim()) { i++; continue; }
    if (/^\s*<!--/.test(line)) { while (i < lines.length && !/-->/.test(lines[i])) i++; i++; continue; }
    const fence = line.match(/^\s*(```|~~~)/);
    if (fence) {
      const buf = []; i++;
      while (i < lines.length && !lines[i].trim().startsWith(fence[1])) buf.push(lines[i++]);
      i++;
      const pre = document.createElement('pre'); const code = document.createElement('code'); code.textContent = buf.join('\n'); pre.appendChild(code); out.push(pre); continue;
    }
    const hm = line.match(/^\s*(#{1,6})\s+(.*?)\s*#*\s*$/);
    if (hm) { const el = document.createElement('h' + Math.min(4, hm[1].length)); el.append(...mdInline(hm[2])); out.push(el); i++; continue; }
    if (/^\s*([-*_])(\s*\1){2,}\s*$/.test(line)) { out.push(document.createElement('hr')); i++; continue; }
    if (line.includes('|') && i + 1 < lines.length && isTableSep(lines[i + 1])) {
      const wrap = document.createElement('div'); wrap.className = 'ab-md-table';
      const table = document.createElement('table'); const thead = document.createElement('thead'); const tr = document.createElement('tr');
      cells(line).forEach((c) => { const th = document.createElement('th'); th.append(...mdInline(c)); tr.appendChild(th); });
      thead.appendChild(tr); table.appendChild(thead); i += 2;
      const tbody = document.createElement('tbody');
      while (i < lines.length && lines[i].includes('|') && lines[i].trim()) {
        const r = document.createElement('tr'); cells(lines[i]).forEach((c) => { const td = document.createElement('td'); td.append(...mdInline(c)); r.appendChild(td); }); tbody.appendChild(r); i++;
      }
      table.appendChild(tbody); wrap.appendChild(table); out.push(wrap); continue;
    }
    if (/^\s*>/.test(line)) {
      const buf = []; while (i < lines.length && /^\s*>/.test(lines[i])) buf.push(lines[i++].replace(/^\s*>\s?/, ''));
      const bq = document.createElement('blockquote'); bq.append(...mdBlocks(buf.join('\n'))); out.push(bq); continue;
    }
    if (listRe.test(line)) {
      const base = line.match(listRe)[1].length;
      const ordered = /\d/.test(line.match(listRe)[2]);
      const list = document.createElement(ordered ? 'ol' : 'ul');
      let li = null, sub = [];
      const flush = () => { if (li && sub.length) { li.append(...mdBlocks(sub.join('\n'))); } sub = []; };
      while (i < lines.length) {
        const l = lines[i]; const lm = l.match(listRe);
        if (lm && lm[1].length <= base) { flush(); li = document.createElement('li'); li.append(...mdInline(lm[3])); list.appendChild(li); i++; continue; }
        if (!l.trim()) { if (i + 1 < lines.length && (/^\s+/.test(lines[i + 1]) || (listRe.test(lines[i + 1]) && lines[i + 1].match(listRe)[1].length <= base))) { i++; continue; } break; }
        if (/^\s+/.test(l)) { sub.push(l.replace(new RegExp('^\\s{0,' + (base + 4) + '}'), '')); i++; continue; }
        break;
      }
      flush(); out.push(list); continue;
    }
    const buf = [];
    while (i < lines.length && lines[i].trim() && !/^\s*(#{1,6}\s|```|~~~|>)/.test(lines[i]) && !listRe.test(lines[i]) && !(lines[i].includes('|') && i + 1 < lines.length && isTableSep(lines[i + 1]))) buf.push(lines[i++]);
    const p = document.createElement('p');
    buf.forEach((b, k) => { if (k) p.appendChild(document.createElement('br')); p.append(...mdInline(b.trim())); });
    out.push(p);
  }
  return out;
}
function renderMd(el, text) { el.replaceChildren(...mdBlocks(text)); }
