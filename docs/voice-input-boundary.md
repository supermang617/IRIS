# Voice Input Boundary

Status: active checkpoint.

## Purpose

This verifies that Iris can capture a spoken user prompt as transcript text before chaining it into the response and Kokoro speech path.

## Command

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify_iris_voice_input_boundary.ps1

## Test phrase

Hello Iris, this is a local voice test.

## Rule

Iris must not continue when the transcript is clearly wrong.

The script now allows multiple attempts because short STT phrases are fragile.

## Required words

- hello
- iris

Accepted Iris-like variants:

- iris
- irish
- heiress
- aris

## Rejected example

If the transcript is unrelated, such as:

If a whole

the script must fail and write:

.iris-dev\voice\last-transcript-rejected.txt
