# Iris Feedback Learning Phase 1

Phase 1 captures local response feedback for future personalization and offline
preference datasets. It does not fine-tune model weights.

## Runtime Behavior

- Iris shows thumbs up/down after assistant, vision, screen, Hermes, and image
  provider responses.
- Thumbs down can include an optional reason and correction.
- `feedback status` reports aggregate counts and the current advisory summary.
- `feedback export` writes DPO-style preference pairs to
  `.iris-data/exports/preference-pairs.jsonl`.

## Privacy Boundary

Feedback events use bounded JSONL at `.iris-data/feedback-events.jsonl`. Iris
keeps the current 512 KB journal plus one rotated journal and loads at most the
400 most recent valid events. A truncated final record from an interrupted
append is ignored; corruption earlier in a journal remains an explicit error.
They store:

- turn id, source, model/provider, tool labels, and latency;
- user prompt hash only, not raw prompt text;
- bounded assistant response preview;
- optional reason and correction.

The preference export includes only downvote-plus-correction pairs. A simple
thumbs-up is not treated as training data because it does not identify a
rejected alternative.

## Dynamic Context

Stable feedback patterns can produce a small advisory instruction merged into
the existing Dynamic System Context. It is explicitly lower priority than the
current user request, facts, safety policy, and tool boundaries.

## Deferred

- No online reinforcement learning.
- No automatic model weight updates.
- No cloud feedback service.
- No safety-policy learning from user ratings.
- No raw prompt history storage in feedback events.
