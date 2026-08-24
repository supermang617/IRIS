const spotifyPattern = /\bspotify\b/i;
const spotifyConnectPattern =
  /\b(?:spotify\s+(?:connect|authorize|auth|setup|set\s+up)|(?:connect|authorize|auth|setup|set\s+up)\s+spotify)\b/i;
const spotifyStatusPattern = /\bspotify\s+(?:status|connection|connected)\b|\b(?:is\s+)?spotify\s+connected\b/i;
const playbackIntentPattern =
  /\b(?:play|put\s+on|listen\s+to|start|open)\b/i;
const mediaNounPattern = /\b(?:the\s+)?(?:song|track|music|playlist|album|artist)\b/i;

export function classifySpotifyConnectRoute(text) {
  const clean = String(text || "").trim();
  if (!clean || !spotifyPattern.test(clean)) {
    return { route: "none", action: null, clientId: "", prompt: clean };
  }
  if (spotifyStatusPattern.test(clean)) {
    return { route: "spotify-connect", action: "status", clientId: "", prompt: clean };
  }
  if (!spotifyConnectPattern.test(clean)) {
    return { route: "none", action: null, clientId: "", prompt: clean };
  }
  return {
    route: "spotify-connect",
    action: "connect",
    clientId: spotifyClientIdFromConnectRequest(clean),
    prompt: clean
  };
}

export function classifyMediaActionRoute(text) {
  const clean = String(text || "").trim();
  if (!clean) {
    return { route: "none", service: null, query: "", prompt: "" };
  }
  if (!spotifyPattern.test(clean) || !playbackIntentPattern.test(clean)) {
    return { route: "none", service: null, query: "", prompt: clean };
  }

  const query = spotifyQueryFromPlaybackRequest(clean);
  if (!query) {
    return { route: "none", service: null, query: "", prompt: clean };
  }

  return {
    route: "implicit",
    service: "spotify",
    query,
    prompt: clean
  };
}

export function spotifyQueryFromPlaybackRequest(text) {
  return String(text || "")
    .trim()
    .replace(/^(?:iris|hey\s+iris|hi\s+iris|okay\s+iris)[\s,.:;!?-]+/i, "")
    .replace(/\bon\s+spotify\b/gi, " ")
    .replace(/\b(?:from|using)\s+spotify\b/gi, " ")
    .replace(/\b(?:please|can\s+you|could\s+you|would\s+you)\b/gi, " ")
    .replace(/\b(?:play|put\s+on|listen\s+to|start|open)\b/i, " ")
    .replace(mediaNounPattern, " ")
    .replace(/\s+/g, " ")
    .trim();
}

export function spotifyClientIdFromConnectRequest(text) {
  const clean = String(text || "")
    .trim()
    .replace(/^(?:iris|hey\s+iris|hi\s+iris|okay\s+iris)[\s,.:;!?-]+/i, "")
    .replace(spotifyConnectPattern, " ")
    .replace(/\b(?:client\s*id|clientid|id|is|with|using|please)\b/gi, " ")
    .replace(/[^a-z0-9]/gi, " ")
    .split(/\s+/)
    .find((part) => /^[a-z0-9]{8,128}$/i.test(part));
  return clean || "";
}

export function mediaActionStatusText(route) {
  const service = route?.service === "spotify" ? "Spotify" : "music";
  return `Opening ${service}.`;
}

export function spotifyConnectStatusText(route) {
  return route?.action === "status" ? "Checking Spotify connection." : "Starting Spotify connection.";
}
