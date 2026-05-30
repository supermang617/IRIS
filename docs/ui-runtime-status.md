# UI Runtime Status

Status: active scaffold.

## Purpose

Runtime now exposes the Iris HUD state model before real GUI dependencies are added.

## Command

cargo run -p iris-runtime -- ui-status

## What it verifies

- HUD scaffold is available
- typed prompt model exists
- response display model exists
- visible voice state model exists
- safety absence language is available
- no GUI dependencies are enabled yet

## Boundary

This does not add:

- real desktop windows
- winit
- egui
- screen capture
- OCR
- global hotkeys
- wake word runtime
- system control
- input simulation
- plugins

## Next route

After this is stable, we can decide whether to add the actual minimal HUD dependencies.
