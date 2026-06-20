import assert from "node:assert/strict";
import { test } from "node:test";
import {
  buildCameraCapturePlan,
  cameraAttemptDiagnostic,
  cameraErrorMessage,
  createCameraUnavailableError,
  rankCameraDevice
} from "./camera-state.js";

test("camera errors show no-camera guidance instead of raw DOM exceptions", () => {
  assert.equal(
    cameraErrorMessage(new DOMException("Requested device not found", "NotFoundError")),
    "No camera device was found. Connect or enable a camera, then try again."
  );
});

test("camera permission errors show permission recovery guidance", () => {
  assert.equal(
    cameraErrorMessage(new DOMException("Permission denied", "NotAllowedError")),
    "Camera permission was denied. Allow camera access for Iris, then try again."
  );
});

test("busy camera errors show close-other-apps guidance", () => {
  assert.equal(
    cameraErrorMessage(new DOMException("Could not start video source", "NotReadableError")),
    "The camera is already in use or unavailable. Close other camera apps, then try again."
  );
});

test("unknown camera errors preserve useful details", () => {
  assert.equal(cameraErrorMessage(new Error("Camera driver crashed.")), "Camera driver crashed.");
});

test("camera fallback errors show usable device recovery guidance", () => {
  assert.equal(
    cameraErrorMessage(createCameraUnavailableError()),
    "Camera devices were found, but Iris could not open a usable camera. Close other camera apps and check Windows camera privacy or driver settings, then try again."
  );
});

test("camera ranking prefers visible usable cameras over IR cameras", () => {
  assert.ok(
    rankCameraDevice({ label: "Windows Studio Effects Camera" }) >
      rankCameraDevice({ label: "Surface IR Camera Front" })
  );
  assert.ok(
    rankCameraDevice({ label: "Camera MX Brio" }) >
      rankCameraDevice({ label: "Surface Camera Front" })
  );
});

test("camera capture plan tries default then ranked device ids", () => {
  const plan = buildCameraCapturePlan(
    [
      { kind: "audioinput", label: "Microphone", deviceId: "mic-1" },
      { kind: "videoinput", label: "Surface IR Camera Front", deviceId: "ir-1" },
      { kind: "videoinput", label: "Windows Studio Effects Camera", deviceId: "studio-1" },
      { kind: "videoinput", label: "Surface Camera Front", deviceId: "front-1" }
    ],
    { width: { ideal: 640 }, height: { ideal: 480 } }
  );

  assert.equal(plan[0].attemptId, "default");
  assert.equal(plan[1].label, "Windows Studio Effects Camera");
  assert.equal(plan[1].constraints.video.deviceId.exact, "studio-1");
  assert.equal(plan.at(-1).label, "Surface IR Camera Front");
});

test("camera attempt diagnostics omit raw device ids", () => {
  const diagnostic = cameraAttemptDiagnostic(
    { attemptId: "device-2", label: "Surface Camera Front" },
    new DOMException("Could not start video source", "NotReadableError")
  );

  assert.deepEqual(diagnostic, {
    attemptId: "device-2",
    label: "Surface Camera Front",
    errorName: "NotReadableError",
    errorMessage: "Could not start video source"
  });
});
