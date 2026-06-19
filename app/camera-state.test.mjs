import assert from "node:assert/strict";
import { test } from "node:test";
import { cameraErrorMessage } from "./camera-state.js";

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
