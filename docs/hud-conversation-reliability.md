# HUD Conversation Reliability

Status: active checkpoint.

## Purpose

This checkpoint locks the HUD conversation behavior before adding HUD speech.

## Verifies

- assistant output normalization
- profanity censor-marker removal
- deictic role handling
- Iris-directed praise handling
- HUD submit path
- current milestone diagnostics

## Required behavior

User says:

Okay that was the test. You passed! Congrats!!!

Iris says:

I'm glad I passed. I did great, didn't I?

User says:

Awesome, you passed our test, Iris. I am proud of you.

Iris says:

I'm glad I passed. Thank you for being proud of me.

## Boundary

This does not add:

- Kokoro speech from HUD
- screen capture
- OCR
- memory database
- wake word runtime
- input simulation
- system control
