# Minimal Desktop HUD Slice

Status: active first GUI slice.

## Purpose

This is the first real desktop HUD window for Project Iris.

## Current scope

The HUD shows:

- Project Iris title
- read-only local assistant description
- required safety absence language
- visible voice state
- typed prompt field
- Send button
- local response area

## Current limitation

Typed prompts are captured in the HUD model only.

Model wiring from the HUD to Iris runtime comes next.

## Boundary

This slice does not add:

- screen capture
- OCR
- memory database
- full dashboard
- wake word runtime
- always-listening voice
- system control
- mouse control
- keyboard control
- browser automation
- plugins

## Run command

cargo run -p iris-runtime -- hud
