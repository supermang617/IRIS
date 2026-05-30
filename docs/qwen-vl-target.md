# Qwen2.5-VL Abliterated Target

Status: selected local test target.

Default local test model:

huihui_ai/qwen3.5-abliterated:9b:9b

Purpose:

- first real local Iris thinking test
- small enough target for RTX 4060 class hardware
- vision-language capable model family
- abliterated/uncensored variant selected for this user's local test path

Important:

- This is the selected model target for the user's machine.
- Ollama is responsible for resolving and pulling the model tag.
- If the tag changes, update this document and scripts/setup_iris_qwen_vl_ollama.ps1.
- Runtime default remains disabled stub until explicit test commands are used.

Current test command after setup:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\setup_iris_qwen_vl_ollama.ps1

Manual Iris loopback test after model exists:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test_iris_ollama_loopback.ps1 huihui_ai/qwen3.5-abliterated:9b:9b "In one sentence, say hello as Iris and confirm you are running locally."





