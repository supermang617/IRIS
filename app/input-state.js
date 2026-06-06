export function shouldClearInputOnSubmit(text, busy) {
  return Boolean(String(text || "").trim()) && !Boolean(busy);
}
