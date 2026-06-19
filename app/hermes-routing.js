const imageGenerationIntentPattern = /\b(?:generate|create|make|draw|render)\s+(?:an?\s+)?(?:image|picture|logo|illustration|wallpaper|banner|icon|avatar)\b/i;

const onlineIntentPattern = /\b(?:look\s+(?:it\s+)?up|look\s+online|google\s+(?:it|this|that|for)?|search\s+(?:google|online|the\s+web|the\s+internet)|research|find\s+(?:online|on\s+the\s+web)|check\s+(?:online|the\s+web|the\s+internet)|what(?:'s| is)\s+(?:the\s+latest|new|current)|latest\s+(?:news|info|information|updates?)|current\s+(?:release|version|news|price|weather|status)|today(?:'s)?\s+(?:news|weather|price|status)|this\s+(?:week|month|year)|who\s+won|browse\s+(?:the\s+web|online|the\s+internet)|visit\s+(?:the\s+site|the\s+website|https?:\/\/)|open\s+(?:a\s+|the\s+)?(?:site|website|webpage|browser)|go\s+to\s+https?:\/\/|use\s+(?:the\s+)?(?:site|website|web)|download\s+(?:from\s+)?(?:the\s+web|https?:\/\/)|upload\s+.+\b(?:site|website|webpage))\b/i;

const codeIntentPattern = /\b(?:review|debug|fix|explain|suggest)\b.*\b(?:code|error|test|build|clippy|cargo|npm|rust|javascript|typescript)\b/i;

const memoryIntentPattern = /\b(?:what\s+do\s+you\s+(?:know|remember)\s+(?:from\s+memory|about\s+me)|summari[sz]e\s+(?:what\s+you\s+know\s+)?(?:from\s+)?memory|memory\s+summary|what(?:'s| is)\s+my\s+(?:age|name)|how\s+old\s+am\s+i)\b/i;

export function classifyHermesRoute(text) {
  const clean = String(text || "").trim();
  if (!clean) {
    return { route: "none", mode: null, text: "" };
  }

  const hermesResearchMatch = clean.match(/^hermes\s+research\s*[:,-]?\s+(.+)$/i);
  if (hermesResearchMatch) {
    return { route: "explicit", mode: "research", text: hermesResearchMatch[1].trim() };
  }

  const hermesCodeMatch = clean.match(/^hermes\s+code\s*[:,-]?\s+(.+)$/i);
  if (hermesCodeMatch) {
    return { route: "explicit", mode: "code_suggestion", text: hermesCodeMatch[1].trim() };
  }

  const hermesMatch = clean.match(/^hermes\s*[:,-]?\s+(.+)$/i);
  if (hermesMatch) {
    return { route: "explicit", mode: "reason", text: hermesMatch[1].trim() };
  }

  if (imageGenerationIntentPattern.test(clean)) {
    return { route: "implicit", mode: "image_generation", text: clean };
  }

  if (onlineIntentPattern.test(clean)) {
    return { route: "implicit", mode: "research", text: clean };
  }

  if (memoryIntentPattern.test(clean)) {
    return { route: "implicit", mode: "reason", text: clean };
  }

  if (codeIntentPattern.test(clean)) {
    return { route: "implicit", mode: "code_suggestion", text: clean };
  }

  return { route: "none", mode: null, text: clean };
}
