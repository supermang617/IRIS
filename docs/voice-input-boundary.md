# Voice Input Boundary

Status: active checkpoint.

## Current phrase

Testing now, Iris local voice test.

## Gate type

Soft milestone gate.

## Why

The speech recognizer is currently imperfect. It may hear:

Just testing now ...

That is good enough to prove live capture, but unrelated phrases like "Brewers" must still be rejected.

## Current rule

Pass when the transcript:

- has enough text
- has at least two words
- does not match known bad phrases
- contains at least one anchor word

## Anchor words

- testing
- test
- voice
- iris
- local

## Boundary

A rejected transcript must not continue into Iris response or Kokoro speech.
