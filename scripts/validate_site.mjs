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

const requiredFragments = [
  "Iris v1",
  "Download beginner bundle",
  "https://github.com/supermang617/IRIS/releases/download/v1/iris-windows-installer.zip",
  "https://github.com/supermang617/IRIS/releases/download/v1/iris-windows.zip",
  "2fad05933328c7fcff1e3667b37c392682be1f0dc4bee1eba826c7a00e404a3a",
  "28a948833f1396f8add27aadecec196e5be5a17fd83868d6ee7bf17f0e1f7f47",
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

if (!Array.isArray(manifest.assets) || manifest.assets.length < 2) {
  throw new Error("Release manifest must include release assets.");
}

for (const asset of manifest.assets) {
  if (!asset.url.includes("/releases/download/v1/")) {
    throw new Error(`Release asset must point at the v1 release: ${asset.name}`);
  }
  if (!/^[a-f0-9]{64}$/.test(asset.sha256)) {
    throw new Error(`Invalid SHA-256 for release asset: ${asset.name}`);
  }
}

console.log("Site validation passed.");
