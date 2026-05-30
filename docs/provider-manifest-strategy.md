# Iris Provider Manifest Strategy

Status: active architecture plan.

## Purpose

The manifest lets Iris change models and runners without rewriting core runtime code.

## Manifest-owned decisions

- runner kind
- runner endpoint or local path
- text model
- vision model
- ASR backend
- TTS backend
- embedding backend
- context cap
- hardware tier
- thermal safety limits

## Current rule

The runtime should read model and runner choices from config.

Hardcoded model strings are temporary development scaffolding only.

## Backend classes

- ollama: current development runner
- llama_cpp: future local packaged runner candidate
- bundled: future Iris-managed runner candidate
- disabled: safe fallback

## Subsystems stay decoupled

Typed input, ASR transcript, screen evidence, memory, and diagnostics all enter through the Context Gate.

TTS remains output-only.

Vision remains evidence-only.

No subsystem may introduce action capabilities.
