#!/usr/bin/env node
// Render Mermaid to ASCII via beautiful-mermaid. Reads a file arg or stdin ('-').
// Exits 1 with the parser's message on invalid Mermaid.
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { homedir } from "node:os";

// beautiful-mermaid ships no bin, so it is resolved as a library. A global
// install is not on node's default resolution path from an arbitrary cwd.
function candidates() {
  const paths = [
    "beautiful-mermaid",
    `${homedir()}/.bun/install/global/node_modules/beautiful-mermaid/dist/index.js`,
  ];
  // `npm root -g` rather than a hardcoded prefix: mise/nvm/volta relocate it.
  try {
    const root = execFileSync("npm", ["root", "-g"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
    if (root) paths.push(`${root}/beautiful-mermaid/dist/index.js`);
  } catch {}
  return paths;
}

async function load() {
  for (const spec of candidates()) {
    try {
      return await import(spec);
    } catch {} // ponytail: a broken install reads as missing; fine until it bites
  }
  console.error(
    "beautiful-mermaid not found. Install with:\n" +
      "  bun add -g beautiful-mermaid   (or)   npm i -g beautiful-mermaid",
  );
  process.exit(127);
}

const arg = process.argv[2];
if (!arg) {
  console.error("usage: mermaid-ascii.mjs <file.mmd|->");
  process.exit(2);
}
const src = readFileSync(arg === "-" ? 0 : arg, "utf8");

const { renderMermaidASCII } = await load();
try {
  process.stdout.write((await renderMermaidASCII(src)).replace(/\s+$/, "") + "\n");
} catch (e) {
  console.error(`mermaid parse error: ${e.message}`);
  process.exit(1);
}
