# Iris Foundation Guard

Status: active lightweight periodic verification.

## Purpose

This script verifies that the current Iris foundation still builds, tests, audits, and preserves core HUD behavior.

## Command

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify_iris_foundation_guard.ps1

## Guard rules

- Use one canonical HUD response helper.
- Do not create suffixed helper chains.
- Do not use interactive script prompts.
- Capture native command output with Start-Process.
- Keep HUD role handling stable.
- Keep assistant output free of censor-marker asterisks.
- Keep user input direct and unmodified.

## Timing

Reports are written to:

.iris-dev\foundation\

This directory is local development state and should not be committed.
