# Stable Guard Contract

Status: active.

The foundation guard is deterministic. It must not depend on live model wording.

The voice/text milestone guard runs the foundation guard and the current dry-run.

PowerShell guard scripts must run native commands through Start-Process with stdout and stderr redirected to files.

Reason: cargo writes normal progress to stderr. Capturing cargo with 2>&1 under ErrorActionPreference Stop creates false NativeCommandError failures.

Do not add broad string scans. Scan actual forbidden runtime capabilities only.
