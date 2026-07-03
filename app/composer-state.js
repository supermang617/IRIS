export const composerMinHeight = 46;
export const composerMaxHeight = 160;
export const responseMinHeight = 72;
export const responseDefaultHeight = 168;
export const responseLayoutReserveHeight = 278;

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

export function responseHeightLimitForViewport(viewportHeight) {
  return Math.max(
    responseMinHeight,
    Math.floor(Number(viewportHeight) || responseMinHeight) - responseLayoutReserveHeight
  );
}

export function responseHeightFromDrag(startHeight, startY, currentY) {
  return Number(startHeight) - (Number(currentY) - Number(startY));
}

export function responseHeightFromKeyboard(currentHeight, key) {
  if (key === "ArrowUp") {
    return Number(currentHeight) + 16;
  }
  if (key === "ArrowDown") {
    return Number(currentHeight) - 16;
  }
  return null;
}
