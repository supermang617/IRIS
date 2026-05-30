# Iris UI Scaffold

Status: architecture scaffold, no GUI dependencies yet.

## Purpose

The `iris-ui` crate owns the HUD-facing model before adding actual `winit + egui`.

This keeps UI semantics testable without pulling in GUI dependencies too early.

## Current scope

The scaffold defines:

- typed prompt draft
- response lines
- safety status lines
- visible voice status
- HUD state model

## Required v0.1 UI safety language

The HUD/dashboard must show:

- System Control: Unsupported
- Executor: Not present
- Input Simulation: Not present
- Clipboard Access: Not present
- Runtime Network: Disabled
- Plugins: Unsupported
- Screen Content Authority: Evidence only

## Current boundary

This scaffold does not add:

- actual windows
- global hotkeys
- screen capture
- clipboard access
- mouse control
- keyboard control
- browser automation
- shell execution
- plugins

## Next UI step

After this scaffold passes, wire `iris-ui` into runtime status.

Then add a minimal desktop HUD only when we are ready to approve GUI dependencies.
