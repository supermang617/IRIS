export const composerMinHeight = 46;
export const composerMaxHeight = 160;
export const responseMinHeight = 96;
export const responseDefaultHeight = 168;

export function shouldSubmitComposer({ key, shiftKey, isComposing }) {
  return key === "Enter" && !shiftKey && !isComposing;
}

export function composerHeightFor(scrollHeight) {
  const numeric = Number(scrollHeight);
  if (!Number.isFinite(numeric)) {
    return composerMinHeight;
  }
  return Math.min(composerMaxHeight, Math.max(composerMinHeight, Math.ceil(numeric)));
}

export function clampResponseHeight(requestedHeight, availableHeight) {
  const maximum = Math.max(responseMinHeight, Math.floor(Number(availableHeight) || responseMinHeight));
  const requested = Number(requestedHeight);
  const fallback = Math.min(responseDefaultHeight, maximum);
  if (!Number.isFinite(requested)) {
    return fallback;
  }
  return Math.min(maximum, Math.max(responseMinHeight, Math.round(requested)));
}
