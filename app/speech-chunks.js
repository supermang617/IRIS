export function splitSpeechChunks(text, maxChars = 260) {
  const clean = String(text || "").replace(/\s+/g, " ").trim();
  if (!clean) {
    return [];
  }
  const limit = Math.max(80, Number(maxChars) || 260);
  const sentences = clean.match(/[^.!?]+[.!?]+|[^.!?]+$/g) || [clean];
  const chunks = [];
  let current = "";

  for (const sentenceValue of sentences) {
    let sentence = sentenceValue.trim();
    while (sentence.length > limit) {
      const available = current ? limit - current.length - 1 : limit;
      const wordBoundary = sentence.lastIndexOf(" ", available);
      const splitAt =
        wordBoundary > 0 ? wordBoundary : Math.min(available, sentence.length);
      const part = sentence.slice(0, splitAt).trim();
      if (part) {
        current = current ? `${current} ${part}` : part;
      }
      if (current) {
        chunks.push(current);
        current = "";
      }
      sentence = sentence.slice(splitAt).trim();
    }
    if (!sentence) {
      continue;
    }
    if (current && current.length + sentence.length + 1 > limit) {
      chunks.push(current);
      current = sentence;
    } else {
      current = current ? `${current} ${sentence}` : sentence;
    }
  }
  if (current) {
    chunks.push(current);
  }
  return chunks;
}
