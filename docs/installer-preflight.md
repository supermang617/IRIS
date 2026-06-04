# Iris Windows Preflight

Produced by Alejandro Pinto.

Contact: super.mangmail@gmail.com

The Iris preflight wizard is a read-only setup check for beginners. It tells a
user what is ready, what is missing, and what to do next. It does not install
software, pull models, edit PATH, change services, write OneDrive data, or weaken
Iris safety rules.

Run it from a source checkout:

```powershell
scripts\iris_preflight_wizard.ps1
```

Run it from the portable release folder:

```powershell
.\Iris Preflight.ps1
```

## What It Checks

- Windows 10 or Windows 11.
- Installed RAM and free disk space.
- Microsoft Edge WebView2 Runtime.
- Ollama executable and local service model list.
- Required model: `huihui_ai/gemma-4-abliterated:e2b`.
- Bundled Kokoro and Whisper assets.
- Python availability and optional Kokoro TTS packages.
- Release ZIP/SHA256 integrity when run from a developer checkout.
- Manifest local-only loopback policy.

## What It Does Not Do

- It does not download Iris, Ollama, models, Python packages, or WebView2.
- It does not install dependencies.
- It does not enable OneDrive sync.
- It does not move memory files.
- It does not run shell commands from model output.
- It does not grant Iris computer-control permissions.

The next milestone can turn these checks into an installer UI with explicit user
approval for each repair step.
