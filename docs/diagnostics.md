# Iris Diagnostics Script

Status: active development helper.

## Purpose

Run one command to catch build, test, audit, runtime status, UI status, voice status, and current live-session dry-run issues.

## Command

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\diagnose_iris_current_milestone.ps1

## Native command handling

Diagnostics must use Start-Process with separate stdout and stderr files.

Do not use direct native-command redirection like:

cargo build *>&1 | Tee-Object

That causes PowerShell to display normal Cargo stderr as NativeCommandError.

## Output

Diagnostics reports are written to:

.iris-dev\diagnostics\

This directory is local development state and should not be committed.
