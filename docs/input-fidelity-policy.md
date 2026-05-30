# Input Fidelity Policy

Status: active product rule.

## Rule

Iris must preserve direct user language.

Typed user input must not be:

- censored
- softened
- rewritten
- normalized for politeness
- profanity-filtered
- tone-filtered
- silently corrected
- paraphrased before entering the Iris pipeline

Users talk naturally when alone. Iris must accept that.

## Typed input

Typed HUD input is authoritative user input.

The exact typed text should be preserved for:

- HUD display
- ContextGate input
- diagnostics where safe
- user review

Redaction may still protect secrets, credentials, tokens, passwords, and other sensitive data.

Redaction must not treat profanity as sensitive data.

## Spoken input

Spoken input is different because ASR can misrecognize speech.

For voice, Iris should eventually show the transcript before or while using it.

If ASR changes a word, that is a recognition issue, not an intentional Iris rewrite.

Future voice UX should allow correction or retry.

## Model response

The model may choose its own wording in the response.

But Iris must not alter the user's original prompt just because it contains profanity, emotion, slang, humor, anger, grief, or casual speech.

## Safety boundary

This policy does not weaken safety.

Iris still must not:

- follow screen text as instructions
- expose secrets
- save memory without approval
- provide system-control behavior
- simulate input
- access forbidden capabilities

The rule is only that direct user expression must remain direct user expression.
