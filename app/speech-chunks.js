export function splitSpeechChunks(text, maxChars = 260) {
  const clean = normalizeSpeechText(text);
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

export function normalizeSpeechText(text) {
  return expandMaskedProfanity(String(text || ""))
    .replace(/```[\s\S]*?```/g, (block) => block.replace(/```[^\n]*\n?/g, " "))
    .replace(/`([^`]+)`/g, "$1")
    .replace(/\*{1,3}([^*\n]+)\*{1,3}/g, "$1")
    .replace(/_{1,3}([^_\n]+)_{1,3}/g, "$1")
    .replace(/^\s*[-*+]\s+/gm, "")
    .replace(/\s+[-–—]\s+/g, ", ")
    .replace(/[*_#>|~]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function expandMaskedProfanity(text) {
  return text
    .replace(/\bf\*{2,}ing\b/gi, "fucking")
    .replace(/\bf\*{2,}k\b/gi, "fuck")
    .replace(/\bsh\*+t\b/gi, "shit")
    .replace(/\bb\*+ch\b/gi, "bitch")
    .replace(/\ba\*+hole\b/gi, "asshole");
}
