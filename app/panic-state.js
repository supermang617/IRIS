export function nextPanicState(active) {
  return !Boolean(active);
}

export function canSubmitWhilePanicStopped(active) {
  return !Boolean(active);
}

export function panicStatusText(active) {
  return active ? "Panic Stop active. Iris is paused." : "Panic Stop cleared. Iris is ready.";
}
