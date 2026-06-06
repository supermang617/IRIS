const onlineIntentPattern = /\b(?:look\s+(?:it\s+)?up|look\s+online|search\s+(?:online|the\s+web|the\s+internet)|research|find\s+(?:online|on\s+the\s+web)|check\s+(?:online|the\s+web|the\s+internet)|what(?:'s| is)\s+(?:the\s+latest|new|current)|latest\s+(?:news|info|information|updates?)|browse\s+(?:the\s+web|online|the\s+internet))\b/i;

const codeIntentPattern = /\b(?:review|debug|fix|explain|suggest)\b.*\b(?:code|error|test|build|clippy|cargo|npm|rust|javascript|typescript)\b/i;

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

  if (onlineIntentPattern.test(clean)) {
    return { route: "implicit", mode: "research", text: clean };
  }

  if (codeIntentPattern.test(clean)) {
    return { route: "implicit", mode: "code_suggestion", text: clean };
  }

  return { route: "none", mode: null, text: clean };
}
