import assert from "node:assert/strict";
import test from "node:test";

import { latestBrowserPreview } from "./browser-preview.js";

test("returns the latest usable browser preview", () => {
  const preview = latestBrowserPreview([
    { type: "browser_preview", payload: { url: "https://first.example" } },
    { type: "tool_activity", payload: "browser click" },
    {
      type: "browser_preview",
      payload: {
        url: "https://example.com/docs",
        screenshotPath: "diagnostics/browser/latest.png"
      }
    }
  ]);

  assert.deepEqual(preview, {
    url: "https://example.com/docs",
    screenshotPath: "diagnostics/browser/latest.png"
  });
});

test("ignores malformed browser events", () => {
  assert.equal(latestBrowserPreview(null), null);
  assert.equal(
    latestBrowserPreview([
      { type: "browser_preview", payload: {} },
      { type: "tool_activity", payload: "browser open" }
    ]),
    null
  );
});
