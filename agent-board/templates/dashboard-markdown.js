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
// Usage: paste into a dashboard script (dashboards can load only their own files). It defines one
// global, window.renderMd(element, markdownText); call it inside the drawing that shows a card or
// thread entry. Give the element a class with modest spacing for p, ul, ol, table, pre and
// blockquote.

(function defineRenderMd(global) {
  const INLINE_RE = /(`+)([^`]+?)\1|\*\*([^*]+?)\*\*|__([^_]+?)__|\*([^*\s][^*]*?)\*|_([^_\s][^_]*?)_|~~([^~]+?)~~|\[([^\]]+)\]\(([^)\s]+)\)|(https?:\/\/[^\s<>()]+[^\s<>().,;:!?'"])/g;
  const LIST_RE = /^(\s*)([-*+]|\d+[.)])\s+(.*)$/;
  const HEADING_RE = /^\s*(#{1,6})\s+(.*?)\s*#*\s*$/;
  const FENCE_RE = /^\s*(```|~~~)/;
  const RULE_RE = /^\s*([-*_])(\s*\1){2,}\s*$/;
  const TABLE_SEP_RE = /^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$/;
  const PARAGRAPH_STOP_RE = /^\s*(#{1,6}\s|```|~~~|>)/;

  function element(tag, children) {
    const node = document.createElement(tag);
    if (children) node.append(...children);
    return node;
  }

  function link(href, children) {
    const anchor = element('a', children);
    anchor.href = href;
    anchor.target = '_blank';
    anchor.rel = 'noopener noreferrer';
    return anchor;
  }

  function inlineNode(match) {
    const [, , code, bold, bold2, em, em2, strike, linkText, linkHref, bareUrl] = match;
    if (code != null) {
      const node = element('code');
      node.textContent = code;
      return node;
    }
    if (bold != null || bold2 != null) return element('strong', parseInline(bold ?? bold2));
    if (em != null || em2 != null) return element('em', parseInline(em ?? em2));
    if (strike != null) return element('s', parseInline(strike));
    if (linkText != null) {
      return /^https?:\/\//i.test(linkHref) ? link(linkHref, parseInline(linkText)) : document.createTextNode(linkText);
    }
    const anchor = link(bareUrl);
    anchor.textContent = bareUrl;
    return anchor;
  }

  function parseInline(text) {
    const out = [];
    const re = new RegExp(INLINE_RE.source, 'g');
    let last = 0;
    for (let match = re.exec(text); match; match = re.exec(text)) {
      if (match.index > last) out.push(document.createTextNode(text.slice(last, match.index)));
      out.push(inlineNode(match));
      last = re.lastIndex;
    }
    if (last < text.length) out.push(document.createTextNode(text.slice(last)));
    return out;
  }

  const isTableStart = (lines, i) => lines[i].includes('|') && i + 1 < lines.length && TABLE_SEP_RE.test(lines[i + 1]);
  const tableCells = (line) => line.trim().replace(/^\||\|$/g, '').split('|').map((cell) => cell.trim());

  // Each block reader takes (lines, i) and returns {nodes, next} when it handles line i, else null.
  function readComment(lines, i) {
    if (!/^\s*<!--/.test(lines[i])) return null;
    let next = i;
    while (next < lines.length && !/-->/.test(lines[next])) next += 1;
    return { nodes: [], next: next + 1 };
  }

  function readFence(lines, i) {
    const fence = lines[i].match(FENCE_RE);
    if (!fence) return null;
    const body = [];
    let next = i + 1;
    while (next < lines.length && !lines[next].trim().startsWith(fence[1])) body.push(lines[next++]);
    const code = element('code');
    code.textContent = body.join('\n');
    return { nodes: [element('pre', [code])], next: next + 1 };
  }

  function readHeading(lines, i) {
    const heading = lines[i].match(HEADING_RE);
    if (!heading) return null;
    return { nodes: [element(`h${Math.min(4, heading[1].length)}`, parseInline(heading[2]))], next: i + 1 };
  }

  function readRule(lines, i) {
    return RULE_RE.test(lines[i]) ? { nodes: [element('hr')], next: i + 1 } : null;
  }

  function readTable(lines, i) {
    if (!isTableStart(lines, i)) return null;
    const row = (line, tag) => element('tr', tableCells(line).map((cell) => element(tag, parseInline(cell))));
    const rows = [];
    let next = i + 2;
    while (next < lines.length && lines[next].includes('|') && lines[next].trim()) rows.push(row(lines[next++], 'td'));
    const table = element('table', [element('thead', [row(lines[i], 'th')]), element('tbody', rows)]);
    const wrap = element('div', [table]);
    wrap.className = 'ab-md-table';
    return { nodes: [wrap], next };
  }

  function readQuote(lines, i) {
    if (!/^\s*>/.test(lines[i])) return null;
    const body = [];
    let next = i;
    while (next < lines.length && /^\s*>/.test(lines[next])) body.push(lines[next++].replace(/^\s*>\s?/, ''));
    return { nodes: [element('blockquote', parseBlocks(body.join('\n')))], next };
  }

  function continuesList(lines, next, base) {
    if (next + 1 >= lines.length) return false;
    const after = lines[next + 1];
    const item = after.match(LIST_RE);
    return /^\s+/.test(after) || Boolean(item && item[1].length <= base);
  }

  function readList(lines, i) {
    const first = lines[i].match(LIST_RE);
    if (!first) return null;
    const base = first[1].length;
    const list = element(/\d/.test(first[2]) ? 'ol' : 'ul');
    const indent = new RegExp(`^\\s{0,${base + 4}}`);
    let item = null;
    let nested = [];
    const flush = () => {
      if (item && nested.length) item.append(...parseBlocks(nested.join('\n')));
      nested = [];
    };
    let next = i;
    while (next < lines.length) {
      const line = lines[next];
      const marker = line.match(LIST_RE);
      if (marker && marker[1].length <= base) {
        flush();
        item = element('li', parseInline(marker[3]));
        list.appendChild(item);
      } else if (!line.trim()) {
        if (!continuesList(lines, next, base)) break;
      } else if (/^\s+/.test(line)) {
        nested.push(line.replace(indent, ''));
      } else {
        break;
      }
      next += 1;
    }
    flush();
    return { nodes: [list], next };
  }

  function readParagraph(lines, i) {
    const body = [];
    let next = i;
    while (next < lines.length && lines[next].trim() && !PARAGRAPH_STOP_RE.test(lines[next]) && !LIST_RE.test(lines[next]) && !isTableStart(lines, next)) {
      body.push(lines[next++]);
    }
    if (!body.length) body.push(lines[next++]); // never stall on a line no reader claims
    const paragraph = element('p');
    body.forEach((line, k) => {
      if (k) paragraph.appendChild(element('br'));
      paragraph.append(...parseInline(line.trim()));
    });
    return { nodes: [paragraph], next };
  }

  const READERS = [readComment, readFence, readHeading, readRule, readTable, readQuote, readList, readParagraph];

  function parseBlocks(src) {
    const lines = String(src || '').replace(/\r\n?/g, '\n').split('\n');
    const out = [];
    let i = 0;
    while (i < lines.length) {
      if (!lines[i].trim()) {
        i += 1;
      } else {
        const result = READERS.reduce((found, read) => found || read(lines, i), null);
        out.push(...result.nodes);
        i = result.next;
      }
    }
    return out;
  }

  global.renderMd = function renderMd(target, text) {
    target.replaceChildren(...parseBlocks(text));
  };
})(window);
