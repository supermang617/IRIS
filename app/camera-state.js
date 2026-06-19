export function cameraErrorMessage(error) {
  const name = String(error?.name || "").trim();
  const message = String(error?.message || error || "").trim();
  const normalized = `${name} ${message}`.toLowerCase();

  if (
    name === "NotFoundError" ||
    normalized.includes("requested device not found") ||
    normalized.includes("device not found") ||
    normalized.includes("no camera")
  ) {
    return "No camera device was found. Connect or enable a camera, then try again.";
  }

  if (
    name === "NotAllowedError" ||
    name === "SecurityError" ||
    normalized.includes("permission denied") ||
    normalized.includes("not allowed")
  ) {
    return "Camera permission was denied. Allow camera access for Iris, then try again.";
  }

  if (name === "NotReadableError" || normalized.includes("could not start video source")) {
    return "The camera is already in use or unavailable. Close other camera apps, then try again.";
  }

  return message || "Camera snapshot failed.";
}
