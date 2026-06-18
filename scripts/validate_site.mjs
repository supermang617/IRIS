import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

const root = process.cwd();
const siteDir = join(root, "site");
const requiredFiles = [
  "index.html",
  "styles.css",
  "site.js",
  "release-manifest.json",
  "assets/iris-logo-256.png",
  "assets/iris-electric-banner.png",
];

for (const file of requiredFiles) {
  const path = join(siteDir, file);
  if (!existsSync(path)) {
    throw new Error(`Missing site file: ${file}`);
  }
}

const html = readFileSync(join(siteDir, "index.html"), "utf8");
const css = readFileSync(join(siteDir, "styles.css"), "utf8");
const manifest = JSON.parse(readFileSync(join(siteDir, "release-manifest.json"), "utf8"));

const expectedHashes = new Map([
  ["iris-windows-installer.zip", "e1ca7f9092d0ffac4f54a1510a0f138dfe4e4d8b2c758614408d0176e1011340"],
  ["iris-windows.zip", "94b0d0f8a23d5d58a8a5fe4b9795a151319ec56094842ba55d43e0ea06a69d24"],
  ["install-iris-windows.ps1", "e9a610e8b8616a4d0f4ac8e0554a40e238bc6cb85c46d2e055ba39b5cfe1a9da"],
]);

const requiredFragments = [
  "Iris v1",
  "Download beginner bundle",
  "https://github.com/supermang617/IRIS/releases/download/v1/iris-windows-installer.zip",
  "https://github.com/supermang617/IRIS/releases/download/v1/iris-windows.zip",
  "https://supermang617.github.io/IRIS/assets/iris-electric-banner.png",
  "twitter:card",
  "docs/download-and-run.md",
  "docs/manual-test.md",
  "docs/runtime-orchestration.md",
  "super.mangmail@gmail.com",
];

for (const fragment of requiredFragments) {
  if (!html.includes(fragment)) {
    throw new Error(`Site HTML is missing required fragment: ${fragment}`);
  }
}

if (/unclassified/i.test(`${html}\n${css}`)) {
  throw new Error("Site must not contain the word unclassified.");
}

if (/@keyframes|animation\s*:/i.test(css)) {
  throw new Error("Site CSS must not include extra animation effects.");
}

if (manifest.tag !== "v1") {
  throw new Error(`Release manifest must stay on v1; got ${manifest.tag}`);
}

for (const [name, hash] of expectedHashes) {
  if (!html.includes(hash)) {
    throw new Error(`Site HTML is missing current checksum for ${name}.`);
  }
}

if (!Array.isArray(manifest.assets) || manifest.assets.length !== expectedHashes.size) {
  throw new Error("Release manifest must include release assets.");
}

for (const asset of manifest.assets) {
  if (!asset.url.includes("/releases/download/v1/")) {
    throw new Error(`Release asset must point at the v1 release: ${asset.name}`);
  }
  if (!/^[a-f0-9]{64}$/.test(asset.sha256)) {
    throw new Error(`Invalid SHA-256 for release asset: ${asset.name}`);
  }
  if (expectedHashes.get(asset.name) !== asset.sha256) {
    throw new Error(`Release manifest checksum drift for ${asset.name}`);
  }
}

const requiredMeta = [
  /<link rel="canonical" href="https:\/\/supermang617\.github\.io\/IRIS\/" \/>/,
  /<meta property="og:url" content="https:\/\/supermang617\.github\.io\/IRIS\/" \/>/,
  /<meta property="og:type" content="website" \/>/,
  /<meta name="twitter:card" content="summary_large_image" \/>/,
  /<meta name="theme-color" content="#030711" \/>/,
];

for (const pattern of requiredMeta) {
  if (!pattern.test(html)) {
    throw new Error(`Missing required SEO/social metadata: ${pattern}`);
  }
}

const contrastPairs = [
  ["#f3f8ff", "#030711", "body text"],
  ["#afc6df", "#030711", "muted text"],
  ["#7ce9ff", "#030711", "section label"],
  ["#031025", "#a9eeff", "primary button"],
];

for (const [foreground, background, label] of contrastPairs) {
  const ratio = contrastRatio(foreground, background);
  if (ratio < 4.5) {
    throw new Error(`${label} contrast ratio ${ratio.toFixed(2)} is below 4.5.`);
  }
}

console.log("Site validation passed.");

function contrastRatio(foreground, background) {
  const fg = relativeLuminance(hexToRgb(foreground));
  const bg = relativeLuminance(hexToRgb(background));
  const lighter = Math.max(fg, bg);
  const darker = Math.min(fg, bg);
  return (lighter + 0.05) / (darker + 0.05);
}

function hexToRgb(hex) {
  const value = hex.replace("#", "");
  return [
    Number.parseInt(value.slice(0, 2), 16) / 255,
    Number.parseInt(value.slice(2, 4), 16) / 255,
    Number.parseInt(value.slice(4, 6), 16) / 255,
  ];
}

function relativeLuminance([r, g, b]) {
  const [lr, lg, lb] = [r, g, b].map((channel) =>
    channel <= 0.03928 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4,
  );
  return 0.2126 * lr + 0.7152 * lg + 0.0722 * lb;
}
