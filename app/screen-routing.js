const screenObjectPattern =
  /\b(?:screen|monitor|desktop|window|app|application|page|webpage|website|browser|tab|youtube|video|player|caption|captions|subtitle|subtitles)\b/i;

const screenActionPattern =
  /\b(?:look\s+at|look\s+on|look\s+over|see|seeing|read|scan|describe|watch|inspect|visible|shown|showing|displayed|playing|title|caption|captions|subtitle|subtitles)\b/i;

const directVisualQuestionPattern =
  /^(?:iris[\s,.:;!?-]+)?(?:what\s+(?:can|do)\s+you\s+see|can\s+you\s+see\s+this|look\s+at\s+this|describe\s+this|read\s+this)\b/i;

const underIrisTargetPattern =
  /\b(?:under|underneath|beneath|behind)\s+iris\b|\bwhere\s+iris\s+is\b|\biris\s+window\s+area\b/i;

export function classifyScreenProbeRoute(text) {
  const clean = String(text || "").trim();
  if (!clean) {
    return { route: "none", target: null, prompt: "" };
  }

  const asksAboutVisibleScreen =
    directVisualQuestionPattern.test(clean) ||
    (underIrisTargetPattern.test(clean) && screenActionPattern.test(clean)) ||
    (screenObjectPattern.test(clean) && screenActionPattern.test(clean)) ||
    /\bwhat(?:'s| is)\s+on\s+(?:my\s+)?(?:screen|monitor|desktop)\b/i.test(clean) ||
    /\bwhat\s+is\s+(?:this|that)\s+(?:page|window|video|tab|app)\b/i.test(clean);

  if (!asksAboutVisibleScreen) {
    return { route: "none", target: null, prompt: clean };
  }

  return {
    route: "implicit",
    target: underIrisTargetPattern.test(clean) ? "under-iris" : "virtual-screen",
    prompt: clean
  };
}

export function screenProbeStatusText(target) {
  return target === "virtual-screen"
    ? "Looking at the visible desktop.\n\nThinking locally..."
    : "Looking under Iris.\n\nThinking locally...";
}
