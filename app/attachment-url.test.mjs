import assert from "node:assert/strict";
import { test } from "node:test";
import { isTrustedBlobUrl, requireTrustedBlobUrl } from "./attachment-url.js";

test("accepts only trusted blob URLs for attachment previews", () => {
  const blobUrl = "blob:https://iris.local/123";
  const trustedUrls = new Set([blobUrl]);

  assert.equal(isTrustedBlobUrl(blobUrl, trustedUrls), true);
  assert.equal(requireTrustedBlobUrl(blobUrl, trustedUrls), blobUrl);
});

test("rejects untracked, non-blob, and malformed preview URLs", () => {
  const trustedUrls = new Set(["https://example.invalid/image.png", "not a url"]);

  assert.equal(isTrustedBlobUrl("blob:https://iris.local/untracked", trustedUrls), false);
  assert.equal(isTrustedBlobUrl("https://example.invalid/image.png", trustedUrls), false);
  assert.equal(isTrustedBlobUrl("not a url", trustedUrls), false);
  assert.throws(
    () => requireTrustedBlobUrl("blob:https://iris.local/untracked", trustedUrls),
    /not trusted/
  );
});
