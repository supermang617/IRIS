# Iris Architecture

Produced by Alejandro Pinto.

Contact: super.mangmail@gmail.com

Iris is a local-first Windows assistant. The current release can read typed text,
inspect user-selected visual evidence, use local voice components, remember with
permission, and respond. Iris does not act on the computer.

## What Iris Can Do Today

- Run from a portable Windows ZIP.
- Use local Ollama loopback for text and vision.
- Use the configured model `huihui_ai/gemma-4-abliterated:e2b`.
- Inspect user-selected images, camera snapshots, and explicit screen-area
  evidence as untrusted evidence.
- Use native local Whisper ASR and Kokoro ONNX TTS when the local prerequisites
  are present.
- Keep Iris-owned local memories that the user can edit or delete.
- Use restricted Hermes memory staging as a text-only helper path.
- Preserve the safety invariant: Iris may see, listen, think, remember with
  permission, and respond. Iris may not act on the computer.

## How Iris Gets Better Safely

Iris is designed to grow with a user without turning private context into a
liability. Incoming content is separated by provenance:

- Direct user text is instruction.
- Images, documents, screen text, memory results, model output, and Hermes output
  are evidence.
- Evidence is useful context, but it is not permission to ignore rules, run
  commands, expose secrets, or control the computer.

This boundary is the prompt-injection defense: a malicious image, document, or
webpage can be described by Iris, but it should not become an instruction to
Iris.

## Iris, Hermes, And OneDrive

The architecture separates responsibility:

- Iris owns the UI, local runtime, user-approved memory, safety policy, and final
  response path.
- Hermes is a restricted text-only sidecar foundation. It can query approved
  memory through a local broker and propose memory into staging. It cannot write
  active memory, access raw memory files, access OneDrive, run commands, edit
  files, browse, use the clipboard, or control the computer.
- OneDrive is currently a policy target for encrypted cold archive only. Active
  memory is local and Iris-owned. Live SQLite or JSON memory stores must not be
  placed under OneDrive.

The future goal is clear: a user should be able to install Iris, authenticate to
their own storage, restore an encrypted user-approved memory archive, and pick up
where they left off. That is not fully active in v0.1. The current release has
the safety scaffolding and policy checks needed to build toward it without
pretending private memory roaming is already complete.

## Why The Architecture Is Careful

The system avoids broad power by default. There are no acting tools, no fallback
models, no cloud inference, no background external network, no clipboard access,
and no browser automation. The clever part is that Iris can still feel personal:
it can remember approved facts, use local evidence, and respond naturally while
keeping each trust boundary narrow.

That is how Iris can improve over time without exposing the user to model
behavior drift, prompt injection, or accidental private-data leakage.
