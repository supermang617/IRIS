# Voice Input Boundary

Status: active checkpoint.

## Current test phrase

Testing now, Iris local voice test.

## Required words

- iris
- voice
- test

## Reason

Short phrases such as "Hello Iris" are too easy for STT to clip or mishear at the start of capture.

The milestone phrase now puts the important words later in the phrase so the quality gate measures a more reliable transcript.

## Rule

A bad transcript must not continue into Iris response or Kokoro speech.
