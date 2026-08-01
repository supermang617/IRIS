# Iris Privacy Policy

Effective date: July 28, 2026

Iris is a local-first Windows assistant. Normal chat inference, speech recognition, speech generation, private memory, and diagnostics are designed to run on the user's own Windows device.

## Data Iris stores locally

Installed builds keep Iris-owned state under `%LOCALAPPDATA%\Iris`. This can include:

- accepted memories and staged memory proposals;
- local preference and communication-context records;
- voice, camera, screen, browser, and runtime diagnostics;
- approved generated images and browser-session data; and
- user-requested exports.

Source checkouts use the configured `IRIS_DATA_ROOT` or the repository-local `.iris-data` and `diagnostics` directories. Iris does not intentionally place live memory in cloud-sync folders.

## Network activity

Iris does not operate an account service, telemetry service, advertising network, or cloud memory store. Network access occurs only for a feature that requires a named external endpoint, including:

- downloading or updating Iris from GitHub or the Microsoft WinGet catalog;
- installing or updating declared runtime dependencies;
- communicating with a user-configured local Ollama service;
- explicit web research or an approved isolated-browser session; and
- an external image provider only after the user approves that request and configures its credentials.

External sites and package providers receive normal connection information such as an IP address and user-agent string and apply their own privacy terms. Iris treats returned web content as untrusted evidence.

## Microphone, camera, screen, and files

Iris requests Windows permission before using protected devices. Camera and screen features are user-initiated snapshots, not continuous recording. Files and pasted content are processed for the user's current request. Diagnostic files can contain technical event details and captured evidence paths; users should review them before sharing a bug report.

## User control and deletion

Iris keeps `%LOCALAPPDATA%\Iris` across app upgrades and uninstall to prevent software maintenance from erasing user-owned data. A user who wants full deletion can close Iris and manually remove that directory after making any desired backup. Removing it deletes local memories, settings, diagnostics, and other Iris-owned state on that Windows account.

## Security and support

Secrets must not be committed to the repository or attached to public issue reports. Security issues should follow [SECURITY.md](SECURITY.md). Privacy questions can be sent to `super.mangmail@gmail.com`.
