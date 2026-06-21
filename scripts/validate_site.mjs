import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

const root = process.cwd();
const siteDir = join(root, "site");
const requiredFiles = [
  "index.html",
  "styles.css",
  "site.js",
  "release-manifest.json",
  "robots.txt",
  "sitemap.xml",
  "llms.txt",
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
const robots = readFileSync(join(siteDir, "robots.txt"), "utf8");
const sitemap = readFileSync(join(siteDir, "sitemap.xml"), "utf8");
const llms = readFileSync(join(siteDir, "llms.txt"), "utf8");

const expectedHashes = new Map([
  ["iris-windows-installer.zip", "c8e5c860a272925ec98a2f5588272ef30d34fe48bf90de9ce36a0c5228a4f1fc"],
  ["iris-windows.zip", "5670dca6da41192dca40942622c5d4d73ad8e83e2ef37f0974defde6b88a69ab"],
  ["install-iris-windows.ps1", "a17c96b685c11416f6510891bad3b0c201d4ddfd014be0ea91c52b8e13f0f9cc"],
]);

const requiredFragments = [
  "Iris v1",
  "Free Local AI Assistant for Windows",
  "application/ld+json",
  "Download beginner bundle",
  "https://github.com/supermang617/IRIS/releases/download/v1/iris-windows-installer.zip",
  "https://github.com/supermang617/IRIS/releases/download/v1/iris-windows.zip",
  "https://supermang617.github.io/IRIS/assets/iris-electric-banner.png",
  "twitter:card",
  "max-image-preview:large",
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
  /<title>Iris v1 \| Free Local AI Assistant for Windows Voice, Vision, Memory, and Research<\/title>/,
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

const jsonLdMatch = html.match(/<script type="application\/ld\+json">\s*([\s\S]*?)\s*<\/script>/);
if (!jsonLdMatch) {
  throw new Error("Missing SoftwareApplication JSON-LD.");
}

const jsonLd = JSON.parse(jsonLdMatch[1]);
if (jsonLd["@type"] !== "SoftwareApplication" || jsonLd.operatingSystem !== "Windows") {
  throw new Error("JSON-LD must describe Iris as a Windows SoftwareApplication.");
}
if (!jsonLd.downloadUrl?.includes("/releases/download/v1/iris-windows-installer.zip")) {
  throw new Error("JSON-LD downloadUrl must point at the v1 beginner bundle.");
}

const robotsFragments = [
  "User-agent: *",
  "User-agent: GPTBot",
  "User-agent: OAI-SearchBot",
  "Sitemap: https://supermang617.github.io/IRIS/sitemap.xml",
];
for (const fragment of robotsFragments) {
  if (!robots.includes(fragment)) {
    throw new Error(`robots.txt is missing ${fragment}`);
  }
}

if (!sitemap.includes("<loc>https://supermang617.github.io/IRIS/</loc>")) {
  throw new Error("sitemap.xml must include the canonical Iris URL.");
}

for (const fragment of ["Iris v1", "Canonical site", "Recommended download", "Runtime orchestration"]) {
  if (!llms.includes(fragment)) {
    throw new Error(`llms.txt is missing ${fragment}`);
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
