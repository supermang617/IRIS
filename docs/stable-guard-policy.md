# Stable Guard Policy

Status: active.

The foundation guard and voice/text milestone guard are the canonical checks.

## Rule

Do not add ad hoc patches when these fail.

Fix the first failing guard section, then rerun:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify_iris_foundation_guard.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify_iris_voice_text_milestone.ps1

## Current milestone

The next milestone is open back-and-forth typed and spoken conversation.
