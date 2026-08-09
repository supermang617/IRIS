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
  "assets/iris-social-preview.jpg",
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

const boundedImageClaim = "bounded image and OCR assistance";
for (const [name, text] of [
  ["index.html", html],
  ["llms.txt", llms],
  ["release-manifest.json description", manifest.description ?? ""],
]) {
  if (!text.toLowerCase().includes(boundedImageClaim.toLowerCase())) {
    throw new Error(`${name} must describe Iris image support as bounded image and OCR assistance.`);
  }
}
const publicMetadata = `${html}\n${llms}\n${manifest.description}`;
for (const [pattern, label] of [
  [/\b(?:camera|screen)(?:[^.!?\n]{0,32})\bvision\b/i, "camera or screen vision"],
  [/\bvision\s+ai\b/i, "vision AI"],
  [/\b(?:full|general|unrestricted)\s+(?:local\s+)?vision\b/i, "unbounded vision"],
  [/\b(?:text|voice)\s*(?:,|and|plus)\s*vision\b/i, "text or voice plus vision"],
  [/\bvision\s*(?:,|and)\s*(?:memory|voice|chat)\b/i, "vision as an unrestricted peer capability"],
]) {
  if (pattern.test(publicMetadata)) {
    throw new Error(`Public metadata overstates the current image path: ${label}`);
  }
}

if (
  manifest.name !== "Iris" ||
  manifest.repository !== "https://github.com/supermang617/IRIS" ||
  !/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(manifest.version) ||
  !/^v(?:1|(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*))$/.test(manifest.tag) ||
  !manifest.description?.toLowerCase().includes("local-first windows ai assistant")
) {
  throw new Error("Release manifest must include canonical Iris product and version metadata.");
}
if (
  manifest.release !== `${manifest.repository}/releases/tag/${manifest.tag}` ||
  !/^\d{4}-\d{2}-\d{2}$/.test(manifest.published_date) ||
  !/^\d{4}-\d{2}-\d{2}$/.test(manifest.modified_date) ||
  typeof manifest.immutable !== "boolean"
) {
  throw new Error("Release manifest must include consistent release dates and immutability state.");
}
if (
  manifest.modified_date < manifest.published_date ||
  (manifest.tag === "v1" && manifest.version !== "1.0.0") ||
  (manifest.tag !== "v1" && manifest.tag !== `v${manifest.version}`) ||
  manifest.version.split(".").some((part) => Number(part) > 65_535) ||
  (manifest.tag !== "v1" && !manifest.immutable)
) {
  throw new Error("Semantic site releases must be immutable and use ordered release dates.");
}
if (!Array.isArray(manifest.assets) || manifest.assets.length < 3) {
  throw new Error("Release manifest must include the public release assets.");
}

const expectedHashes = new Map();
for (const asset of manifest.assets) {
  if (
    typeof asset.name !== "string" ||
    expectedHashes.has(asset.name) ||
    asset.url !== `${manifest.repository}/releases/download/${manifest.tag}/${asset.name}` ||
    !/^[a-f0-9]{64}$/.test(asset.sha256)
  ) {
    throw new Error(`Invalid or duplicate release asset metadata: ${asset.name ?? "(unnamed)"}`);
  }
  if (
    asset.size_bytes !== undefined &&
    (!Number.isSafeInteger(asset.size_bytes) || asset.size_bytes <= 0)
  ) {
    throw new Error(`Invalid release asset size: ${asset.name}`);
  }
  expectedHashes.set(asset.name, asset.sha256);
}
for (const requiredAsset of [
  "iris-windows-installer.zip",
  "iris-windows.zip",
  "install-iris-windows.ps1",
]) {
  if (!expectedHashes.has(requiredAsset)) {
    throw new Error(`Release manifest is missing required asset: ${requiredAsset}`);
  }
}

const isHistoricalRelease = manifest.tag === "v1";
const semanticMsixAsset = manifest.assets.find((asset) => asset.name === "iris-windows.msix");
if (!isHistoricalRelease && !semanticMsixAsset) {
  throw new Error("Semantic release manifest must include the production-signed iris-windows.msix.");
}

const releaseLabel = `Iris ${manifest.tag}`;
const beginnerAsset = manifest.assets.find((asset) => asset.name === "iris-windows-installer.zip");
const recommendedAsset = isHistoricalRelease ? beginnerAsset : semanticMsixAsset;

const requiredFragments = [
  releaseLabel,
  "Local-First AI Assistant for Windows",
  "application/ld+json",
  ...(isHistoricalRelease ? ["Download beginner bundle"] : []),
  beginnerAsset.url,
  manifest.assets.find((asset) => asset.name === "iris-windows.zip").url,
  "https://supermang617.github.io/IRIS/assets/iris-social-preview.jpg",
  'property="og:image:width" content="1280"',
  'property="og:image:height" content="640"',
  'name="twitter:image:alt"',
  "twitter:card",
  "max-image-preview:large",
  "docs/download-and-run.md",
  "docs/manual-test.md",
  "docs/runtime-orchestration.md",
  "PRIVACY.md",
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

if (/<meta\s+name=["']keywords["']/i.test(html)) {
  throw new Error("Site must not carry the ignored meta keywords tag.");
}

const socialPreview = join(siteDir, "assets/iris-social-preview.jpg");
const socialPreviewBytes = readFileSync(socialPreview);
const socialPreviewSize = socialPreviewBytes.byteLength;
if (socialPreviewSize >= 1_000_000) {
  throw new Error(`Social preview must stay below 1 MB; got ${socialPreviewSize} bytes.`);
}
const socialPreviewDimensions = jpegDimensions(socialPreviewBytes);
if (socialPreviewDimensions.width !== 1280 || socialPreviewDimensions.height !== 640) {
  throw new Error(
    `Social preview must be 1280x640; got ${socialPreviewDimensions.width}x${socialPreviewDimensions.height}.`,
  );
}

for (const fragment of [
  `"softwareVersion": "${manifest.version}"`,
  '"author":',
  '"name": "Alejandro Pinto"',
  `"datePublished": "${manifest.published_date}"`,
  `"dateModified": "${manifest.modified_date}"`,
  `"releaseNotes": "${manifest.release}"`,
  '"processorRequirements": "x86-64"',
]) {
  if (!html.includes(fragment)) {
    throw new Error(`Software metadata is missing: ${fragment}`);
  }
}

if (/@keyframes|animation\s*:/i.test(css)) {
  throw new Error("Site CSS must not include extra animation effects.");
}

if (
  manifest.package_manager?.id !== "AlejandroPinto.Iris" ||
  manifest.package_manager?.documentation !==
    "https://github.com/supermang617/IRIS/blob/main/docs/winget-release.md" ||
  ![
    "pending-signed-release-and-catalog-acceptance",
    "pending-catalog-acceptance",
    "public",
  ].includes(manifest.package_manager?.status)
) {
  throw new Error("Release manifest must describe a recognized truthful WinGet publication state.");
}
if (
  (manifest.package_manager.status === "pending-signed-release-and-catalog-acceptance" &&
    (manifest.tag !== "v1" || manifest.immutable)) ||
  (manifest.package_manager.status !== "pending-signed-release-and-catalog-acceptance" &&
    (manifest.tag === "v1" || !manifest.immutable))
) {
  throw new Error("WinGet status must match the verified release publication state.");
}
if (
  manifest.package_manager.status !== "public" &&
  !html.includes("WinGet package ID <code>AlejandroPinto.Iris</code> is prepared but not yet public")
) {
  throw new Error("Site must not imply that Iris is already available from the WinGet catalog.");
}
if (
  manifest.package_manager.status === "public" &&
  (html.includes("is prepared but not yet public") ||
    !html.includes("winget install --id AlejandroPinto.Iris -e"))
) {
  throw new Error("A public WinGet status must expose the verified install command.");
}
if (
  manifest.tag !== "v1" &&
  (/Iris v1(?!\.)/.test(html) ||
    /releases\/(?:tag|download)\/v1(?:["/])/.test(html) ||
    /Iris v1(?!\.)/.test(llms) ||
    /releases\/(?:tag|download)\/v1(?:\s|$)/m.test(llms))
) {
  throw new Error("Semantic release metadata must not retain historical v1 links or labels.");
}

if (!isHistoricalRelease) {
  const primaryDownloadPanels = [
    ...html.matchAll(
      /<article\b[^>]*class="[^"]*\bprimary-panel\b[^"]*"[^>]*>(?<body>[\s\S]*?)<\/article>/gi,
    ),
  ];
  if (primaryDownloadPanels.length !== 1) {
    throw new Error("Semantic release page must contain exactly one primary download panel.");
  }
  const primaryDownload = primaryDownloadPanels[0].groups?.body ?? "";
  if (
    !primaryDownload.includes(semanticMsixAsset.url) ||
    !primaryDownload.includes(semanticMsixAsset.name) ||
    !/\bsigned\b/i.test(primaryDownload) ||
    !/class="button primary"/i.test(primaryDownload)
  ) {
    throw new Error(
      "Semantic release primary download must present the exact production-signed MSIX asset.",
    );
  }
  if (
    !html.includes(semanticMsixAsset.url) ||
    !html.includes(semanticMsixAsset.sha256)
  ) {
    throw new Error("Semantic release page must expose the exact signed MSIX URL and SHA-256.");
  }
}

for (const [name, hash] of expectedHashes) {
  const asset = manifest.assets.find((candidate) => candidate.name === name);
  if (!html.includes(asset.url) || !html.includes(name)) {
    throw new Error(`Site HTML is missing the public URL or name for ${name}.`);
  }
  if (!html.includes(hash)) {
    throw new Error(`Site HTML is missing current checksum for ${name}.`);
  }
}

for (const asset of manifest.assets) {
  if (expectedHashes.get(asset.name) !== asset.sha256) {
    throw new Error(`Release manifest checksum drift for ${asset.name}`);
  }
}

const requiredMeta = [
  `<title>${releaseLabel} — Local-First AI Assistant for Windows</title>`,
  `<meta name="application-name" content="${releaseLabel}" />`,
  `<meta property="og:title" content="${releaseLabel} — Local-First AI Assistant for Windows" />`,
  `<meta name="twitter:title" content="${releaseLabel} — Local-First AI Assistant for Windows" />`,
  /<link rel="canonical" href="https:\/\/supermang617\.github\.io\/IRIS\/" \/>/,
  /<meta property="og:url" content="https:\/\/supermang617\.github\.io\/IRIS\/" \/>/,
  /<meta property="og:type" content="website" \/>/,
  /<meta name="twitter:card" content="summary_large_image" \/>/,
  /<meta name="theme-color" content="#030711" \/>/,
];

for (const pattern of requiredMeta) {
  const present = typeof pattern === "string" ? html.includes(pattern) : pattern.test(html);
  if (!present) {
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
if (
  jsonLd.softwareVersion !== manifest.version ||
  jsonLd.downloadUrl !== recommendedAsset.url ||
  jsonLd.installUrl !== recommendedAsset.url ||
  jsonLd.releaseNotes !== manifest.release ||
  jsonLd.datePublished !== manifest.published_date ||
  jsonLd.dateModified !== manifest.modified_date
) {
  throw new Error("JSON-LD release metadata must match release-manifest.json.");
}
if (
  jsonLd.codeRepository !== manifest.repository ||
  jsonLd.license !== `${manifest.repository}/blob/main/LICENSE` ||
  jsonLd.author?.name !== "Alejandro Pinto" ||
  jsonLd.publisher?.name !== "Alejandro Pinto" ||
  jsonLd.offers?.["@type"] !== "Offer" ||
  jsonLd.offers?.price !== "0" ||
  jsonLd.offers?.priceCurrency !== "USD" ||
  jsonLd.offers?.availability !== "https://schema.org/InStock" ||
  jsonLd.offers?.url !== recommendedAsset.url
) {
  throw new Error("JSON-LD authorship, license, and free download offer are inconsistent.");
}
if (
  recommendedAsset.size_bytes !== undefined &&
  jsonLd.fileSize !== `${recommendedAsset.size_bytes} bytes`
) {
  throw new Error("JSON-LD fileSize must match the recommended release asset.");
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

for (const fragment of [
  releaseLabel,
  `software version ${manifest.version}`,
  manifest.release,
  recommendedAsset.url,
  "Canonical site",
  "Recommended download",
  "Runtime orchestration",
]) {
  if (!llms.includes(fragment)) {
    throw new Error(`llms.txt is missing ${fragment}`);
  }
}

if (!sitemap.includes(`<lastmod>${manifest.modified_date}</lastmod>`)) {
  throw new Error("sitemap.xml lastmod must match release-manifest.json.");
}

console.log("Site validation passed.");

function contrastRatio(foreground, background) {
  const fg = relativeLuminance(hexToRgb(foreground));
  const bg = relativeLuminance(hexToRgb(background));
  const lighter = Math.max(fg, bg);
  const darker = Math.min(fg, bg);
  return (lighter + 0.05) / (darker + 0.05);
}

function jpegDimensions(bytes) {
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8) {
    throw new Error("Social preview is not a valid JPEG file.");
  }
  const startOfFrameMarkers = new Set([
    0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf,
  ]);
  let offset = 2;
  while (offset + 8 < bytes.length) {
    if (bytes[offset] !== 0xff) {
      offset += 1;
      continue;
    }
    const marker = bytes[offset + 1];
    if (marker === 0xd9 || marker === 0xda) {
      break;
    }
    if (marker === 0x00 || marker === 0xff) {
      offset += 1;
      continue;
    }
    const segmentLength = bytes.readUInt16BE(offset + 2);
    if (segmentLength < 2 || offset + 2 + segmentLength > bytes.length) {
      break;
    }
    if (startOfFrameMarkers.has(marker)) {
      return {
        height: bytes.readUInt16BE(offset + 5),
        width: bytes.readUInt16BE(offset + 7),
      };
    }
    offset += 2 + segmentLength;
  }
  throw new Error("Social preview JPEG has no readable dimensions.");
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
