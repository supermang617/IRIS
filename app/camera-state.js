export function cameraErrorMessage(error) {
  const name = String(error?.name || "").trim();
  const message = String(error?.message || error || "").trim();
  const normalized = `${name} ${message}`.toLowerCase();

  if (name === "CameraDeviceUnavailableError" || normalized.includes("could not open a usable camera")) {
    return "Camera devices were found, but Iris could not open a usable camera. Close other camera apps and check Windows camera privacy or driver settings, then try again.";
  }

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

export function rankCameraDevice(device) {
  const label = String(device?.label || "").toLowerCase();
  let score = 0;

  if (label.includes("windows studio effects")) {
    score += 120;
  }
  if (label.includes("brio") || label.includes("webcam")) {
    score += 90;
  }
  if (label.includes("camera")) {
    score += 40;
  }
  if (label.includes("front")) {
    score += 8;
  }
  if (label.includes("ir") || label.includes("infrared") || label.includes("depth")) {
    score -= 120;
  }
  if (!label) {
    score -= 20;
  }

  return score;
}

export function cameraDiagnosticLabel(device, index) {
  const label = String(device?.label || "").trim();
  return label || `Camera ${index + 1}`;
}

export function buildCameraCapturePlan(devices, videoConstraints) {
  const baseVideoConstraints = { ...videoConstraints };
  const attempts = [
    {
      attemptId: "default",
      label: "Default camera",
      constraints: {
        audio: false,
        video: baseVideoConstraints
      }
    }
  ];

  const rankedDevices = Array.from(devices || [])
    .map((device, index) => ({ device, index, score: rankCameraDevice(device) }))
    .filter(({ device }) => device?.kind === "videoinput" && device.deviceId)
    .sort((left, right) => right.score - left.score || left.index - right.index);

  for (const { device, index } of rankedDevices) {
    attempts.push({
      attemptId: `device-${index}`,
      label: cameraDiagnosticLabel(device, index),
      constraints: {
        audio: false,
        video: {
          ...baseVideoConstraints,
          deviceId: { exact: device.deviceId }
        }
      }
    });
  }

  return attempts;
}

export function cameraAttemptDiagnostic(attempt, error) {
  return {
    attemptId: String(attempt?.attemptId || "unknown"),
    label: String(attempt?.label || "Unknown camera"),
    errorName: String(error?.name || "Error"),
    errorMessage: String(error?.message || error || "Camera attempt failed.")
  };
}

export function createCameraUnavailableError() {
  const error = new Error("Camera devices were found, but Iris could not open a usable camera.");
  error.name = "CameraDeviceUnavailableError";
  return error;
}
