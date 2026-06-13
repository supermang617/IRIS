export function latestBrowserPreview(events) {
  if (!Array.isArray(events)) {
    return null;
  }
  for (let index = events.length - 1; index >= 0; index -= 1) {
    const event = events[index];
    if (event?.type !== "browser_preview" || !event.payload) {
      continue;
    }
    const url = String(event.payload.url || "").trim();
    const screenshotPath = String(
      event.payload.screenshotPath || event.payload.screenshot_path || ""
    ).trim();
    if (url || screenshotPath) {
      return { url, screenshotPath };
    }
  }
  return null;
}
