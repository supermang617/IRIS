export function nextPanicState(active) {
  return !Boolean(active);
}

export function canSubmitWhilePanicStopped(active) {
  return !Boolean(active);
}

export function panicStatusText(active) {
  return active ? "Iris is paused." : "Iris resumed. Wake word armed.";
}
