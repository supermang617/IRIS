# Dynamic System Context

Iris maintains a small local communication profile so its presentation can
adapt as the user's writing changes. This is separate from user-approved
durable memory.

## Design

After a direct user turn completes, Iris calculates aggregate values for:

- average sentence length;
- vocabulary diversity;
- structural complexity;
- formal versus casual register;
- direct, witty, analytical, and expressive language.

`Expressive` means visible writing features such as punctuation and emphasis.
It is not a psychological, medical, personality, or emotion diagnosis.

The next turn receives a compact advisory instruction generated only from
those aggregate values. The current request always overrides the inferred
profile. Iris does not imitate spelling errors, and the profile does not change
facts, permissions, tools, safety boundaries, or memory authority.

The profile uses a 30-day half-life and a recent-observation cap of 64. New
language therefore replaces old tendencies instead of creating permanent
rules. Inputs shorter than three words are ignored to keep acknowledgments such
as `yes` or `continue` from distorting the profile.

## Privacy

The local file is:

```text
.iris-data/dynamic_context.json
```

It stores numeric aggregates, a version, an observation count, an enabled
flag, and an update timestamp. It does not store user messages, excerpts,
tokens, topics, names, secrets, attachments, document text, image contents, or
screen contents.

Document attachments are analyzed only through the user's direct prompt. The
attached document text remains untrusted evidence and does not affect the
communication profile.

## Controls

Enter these exact commands through Iris:

```text
dynamic context
dynamic context on
dynamic context off
dynamic context reset
```

`communication profile` can be used instead of `dynamic context`.

## Industry Basis

The implementation follows the practical pattern visible in current first-party
systems:

- OpenAI separates explicit saved memory from evolving chat-history
  personalization, provides review and deletion controls, and prioritizes
  recency and frequency:
  <https://help.openai.com/en/articles/8590148-memory-faq>
- Google separates past-chat memory from explicit response instructions:
  <https://support.google.com/gemini/answer/16598623>
- Google recommends concise system instructions with clear persona,
  conversational rules, and user information:
  <https://ai.google.dev/gemini-api/docs/live-api/best-practices>
- Anthropic documents layered system-prompt customization for response style
  while preserving the base permission and safety model:
  <https://code.claude.com/docs/en/agent-sdk/modifying-system-prompts>

Iris keeps this implementation fully local and deterministic. It does not use
a classifier model, cloud service, background agent, or extra inference call.
