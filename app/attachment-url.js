export function isTrustedBlobUrl(url, trustedUrls) {
  if (typeof url !== "string" || !trustedUrls?.has(url)) {
    return false;
  }

  try {
    return new URL(url).protocol === "blob:";
  } catch {
    return false;
  }
}

export function requireTrustedBlobUrl(url, trustedUrls) {
  if (!isTrustedBlobUrl(url, trustedUrls)) {
    throw new Error("Attachment preview URL is not trusted.");
  }
  return url;
}
