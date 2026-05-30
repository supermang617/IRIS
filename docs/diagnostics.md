# Iris Diagnostics Script

Status: active development helper.

## Purpose

Run one command to catch build, test, audit, runtime status, UI status, voice status, and current live-session dry-run issues.

## Command

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\diagnose_iris_current_milestone.ps1

## Output

Diagnostics reports are written to:

.iris-dev\diagnostics\

This directory is local development state and should not be committed.

## What it checks

- git status
- cargo fmt
- cargo build
- cargo test
- xtask audit
- runtime self-check
- runtime ui-status
- runtime voice-status
- runtime push-to-talk visible-state test
- runtime response post-check test
- Kokoro voice milestone verifier
- live text/voice session dry-run
