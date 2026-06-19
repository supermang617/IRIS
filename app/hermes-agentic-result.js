export function formatAgenticTaskResult(response) {
  const text = String(response?.text || "").trim();
  const activity = (response?.events || [])
    .filter((event) => event?.type === "tool_activity")
    .map((event) => String(event.payload || "").trim())
    .filter(Boolean)
    .filter((payload) => !text || !/\bin_progress\b/i.test(payload));

  if (text && activity.length > 0) {
    return `${text}\n\nTool activity:\n${activity.join("\n\n")}`;
  }
  if (text) {
    return text;
  }
  if (activity.length > 0) {
    return `Tool activity:\n${activity.join("\n\n")}`;
  }
  return "";
}
