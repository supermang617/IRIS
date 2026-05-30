# Iris Foundation Guard

Status: active lightweight periodic verification.

## Purpose

This script is the current foundation guard for Iris.

It prevents the project from drifting into fragile patch chains, missing helper references, broken role handling, or broken milestone diagnostics.

## Command

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify_iris_foundation_guard.ps1

## What it checks

- git status
- no suffixed HUD helper chains
- no interactive Read-Host prompts
- no broken native-command diagnostics capture pattern
- cargo fmt check
- cargo build
- cargo test
- xtask audit
- runtime self-check
- UI status
- voice status
- push-to-talk state test
- response post-check
- assistant output normalization
- addressee intent
- deictic role handling
- assistant role repair
- HUD targeted behavior checks
- current milestone diagnostics

## Timing

The script writes a timing report to:

.iris-dev\foundation\

This is local development state and should not be committed.

## Development rule

Prefer clean canonical rewrites over stacked messy patches when a file becomes unstable.

Do not create helper chains like:

- function_v2
- function_v3
- function_v4

Use one canonical helper name and replace the broken implementation cleanly.
