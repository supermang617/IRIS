# Iris Manual Test

Run this launcher from the repository root:

```text
C:\Projects\IRIS\Start Iris.vbs
```

Before opening the desktop shell, run the launcher self-check:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Projects\IRIS\Start Iris.ps1" -SelfCheck
```

The self-check runs the read-only preflight wizard, the repository audit, and
the runtime self-check. If it fails, fix the reported local prerequisite before
starting manual desktop testing.

Normal desktop launch is one UI: open Iris only. `Start Iris.ps1` starts Ollama
hidden if it is not already listening on `127.0.0.1:11434`, then opens the Iris
desktop shell.

The launcher also refreshes Iris shortcuts on your user Desktop, Start Menu, and Windows pinned-taskbar shortcut folder. Windows may still require manually choosing "Pin to taskbar" from the visible shortcut if Explorer does not honor programmatic pinning.

Do not open `target\debug\iris-tauri.exe` directly after a `tauri dev` run. A dev-built debug executable can try to load `127.0.0.1` and show a connection-refused page if the dev server is not running. The launcher rebuilds the standalone debug shell first, then starts Iris.

If the launcher fails, check:

```text
C:\Projects\IRIS\diagnostics\manual-launch.log
```

Diagnostics are written automatically while the app is open:

```text
C:\Projects\IRIS\diagnostics\voice-events.jsonl
```

## Current Manual Milestone

1. Confirm the app opens as a compact bottom Iris console, not the old dashboard.
2. Confirm the response pane is above the multiline composer and the compact
   tool icons sit along the bottom of the composer.
3. Type a short message and press Enter or the circular arrow button. Confirm
   Shift+Enter adds a new line without submitting.
4. Confirm Iris shows `Thinking locally...`, then returns a local model response and speaks it with Kokoro `af_heart`.
5. Click the mic icon, say a short prompt, and confirm it submits through the same local model path.
6. Without pressing the mic icon, say `Iris`.
7. Confirm Iris acknowledges and stays ready for the next spoken request.
8. Say a short follow-up request.
9. Confirm Iris submits the follow-up, answers, and returns to wake-word listening.
10. Try `Iris what can you do right now?` as one phrase and confirm only the request after `Iris` is sent.
11. While Iris is speaking, say `Iris`, `stop`, or `Iris stop`.
12. Confirm Iris stops speaking and returns to listening.
13. Click the attachment icon, paste, or drag a small png, jpg, jpeg, or webp image into the text bar.
14. Confirm a small attachment preview appears above the text bar. For a simple PNG fixture, ask a narrow color/shape question; for an arbitrary scene, confirm the affected Windows Gemma 4 path names the projector limitation and refuses to guess.
15. Drag the divider between the response pane and composer. Confirm the
    response pane grows and shrinks, then relaunch Iris and confirm the chosen
    height is retained.
16. Drag the top Iris titlebar and confirm the window moves without disrupting
    typing, resizing, or tool buttons.
17. Click the camera icon with an empty text bar.
18. Confirm Iris takes a capped camera snapshot and does not guess at an unverified scene. On the affected Windows Gemma 4 path it must name the projector limitation, speak the response, and remain usable.
19. Type a camera-specific question, then click the camera icon.
20. Confirm Iris uses that typed question for the camera snapshot and returns only confidence-filtered visible text when available or the same explicit limitation.
21. Move Iris over a visible app, document, or webpage, then click the screen icon.
22. Confirm Iris briefly hides and captures the area underneath the Iris window. It may return confidence-filtered visible text, but it must refuse an unverified general scene description on the affected projector path and remain usable.
23. Type a screen-specific question, then click the screen icon.
24. Confirm Iris uses that typed question for the screen-area capture without silently presenting an unverified scene guess.
25. Click the attachment icon, paste, or drag a small mp4, webm, or mov video into the text bar.
26. Confirm Iris attaches one video frame preview for the next prompt.
27. Click the attachment icon, paste, or drag a txt, md, csv, json, log, or rtf text document into the text bar.
28. Confirm Iris shows a document attachment box and uses only capped text from that document as untrusted context.
29. Enter `dynamic context reset`, then send two direct analytical prompts of
    at least three words each.
30. Enter `dynamic context` and confirm it reports observations plus sentence,
    vocabulary, and tone labels without showing prior prompt text.
31. Enter `dynamic context off`, send another prompt, then confirm the
    observation count does not increase. Re-enable it with `dynamic context on`.

## Speaker And Headset Interruption Matrix

Run this matrix on physical hardware before a signed public release. Automated
voice-state tests do not prove acoustic behavior. Use three fresh Iris
processes and retain three separate logs per hardware condition; never mix
silent, intended-interruption, and non-command trials in one session because
their errors can numerically cancel each other:

| Condition | Trials |
| --- | --- |
| Built-in speakers at 25% | 5 uninterrupted replies, 5 explicit interruptions, 2 non-command utterances |
| Built-in speakers at 60% | 5 uninterrupted replies, 5 explicit interruptions, 2 non-command utterances |
| Built-in speakers at 90% | 5 uninterrupted replies, 5 explicit interruptions, 2 non-command utterances |
| Wired or USB headset | Same trials |
| Bluetooth headset, if supported | Same trials |

For each condition:

1. Select the intended Windows default microphone and output device, then ask
   Iris for a response long enough to speak for at least 10 seconds. The
   retained summary must name those endpoints under `input_devices` and
   `output_devices`; a mislabeled route invalidates that condition.
2. Start a fresh process for five silent replies. Iris must not pause or cancel
   itself. Close Iris, retain the log as `<condition>-silent`, and summarize it
   with `-ExpectedInterruptions 0`.
3. Start a fresh process for five intended interruptions. Alternate `Iris`, `stop`, and
   `Iris, actually explain the other option` near the beginning, middle, and end
   of speech. Iris must pause promptly, confirm the utterance locally, stop, and
   retain a spoken follow-up. Close Iris, retain the log as
   `<condition>-intended`, and summarize it with `-ExpectedInterruptions 5`.
4. Start a fresh process and twice speak a phrase that is not an interruption
   command. A speculative
   pause may occur, but playback must resume and must not be permanently
   cancelled. Close Iris, retain the log as `<condition>-noncommand`, and
   summarize it with `-ExpectedInterruptions 0`.
5. Retain each fresh
   `%LOCALAPPDATA%\Iris\diagnostics\voice-events.jsonl` before starting the next
   run. Source runs use the configured `IRIS_DATA_ROOT`, normally the repository
   `diagnostics` directory.
6. Summarize each retained file:

```powershell
.\scripts\summarize_voice_interruption.ps1 `
  -Path C:\IrisTest\speaker-60-intended\voice-events.jsonl `
  -Label speaker-60-intended `
  -ExpectedInterruptions 5
```

Release targets for each separate run are:

- silent and non-command runs: zero cancellations and zero interruption errors;
- intended run: all five intended interruptions detected and zero errors;
- no permanent cancellation for either non-command utterance;
- zero pause failures, resume failures, or resumes without a later valid terminal
  outcome, with run-correlated playback completion or cancellation after every
  successful rejected resume; a detection record alone is not terminal evidence;
- zero native playback cancellation errors;
- median capture-to-VAD at or below 350 ms;
- median VAD-to-pause at or below 150 ms; and
- median confirmed-interruption resolution at or below 1,200 ms.

Do not add or claim acoustic echo cancellation merely because a VAD candidate
occurred. Evidence supports true AEC work only when silent speaker trials
reproducibly create unexpected pauses/cancellations, the rate rises with speaker
volume, and the same trials do not fail on a headset. If speaker and headset
conditions both fail, investigate microphone input, ASR, device routing, or
thresholds first. Any true AEC implementation must use the native microphone
capture plus the actual playback reference signal and must rerun this entire
matrix; a browser `echoCancellation` flag alone is not proof of AEC.

## Signed MSIX Certification Gate

Run the release-only guest gauntlet in an elevated, active user session on the
disposable Windows VM. It invokes the Windows App Certification Kit itself
against the exact resolved signed draft MSIX before installation, requires a
fresh report path, and refuses to create lifecycle evidence unless WACK reports
`REPORT.OVERALL_RESULT=PASS`:

```powershell
$testContext = "iris-disposable-guest-$([guid]::NewGuid().ToString('N'))"
$report = "C:\IrisTest\iris-v1.0.0-wack.xml"
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\test_windows_msix_lifecycle_guest.ps1 `
  -MsixPath "C:\IrisTest\iris-windows.msix" `
  -ExpectedPublisher "CN=YOUR EXACT CERTIFICATE SUBJECT" `
  -ExpectedVersion "1.0.0.0" `
  -TestContextId $testContext `
  -WackReportPath $report `
  -EvidencePath "C:\IrisTest\iris-msix-lifecycle-evidence.json" `
  -ConfirmDisposableTestGuest
```

Both output paths must be new. Retain the XML report with the lifecycle
evidence. Lifecycle schema 3 records the exact MSIX SHA-256 as both
`release_sha256` and `wack_package_sha256`, plus the WACK report SHA-256 and
length. The kit requires administrator rights and an active user session; a
non-elevated source checkout is not a substitute for this signed-package gate.

## Hermes and Memory Boundary Checks

Run these from `C:\Projects\IRIS` before opening the desktop shell:

```powershell
cargo run -p xtask
cargo run -p iris-runtime -- --self-check
cargo run -p iris-runtime -- --dashboard-json
```

Expected:

- Safe is the startup default. In Safe mode, Hermes is an Iris-owned research,
  local RAG, and memory-transfer helper that exposes only
  `iris_query_memory`, `iris_propose_memory`, and `iris_web_research`.
- Natural Iris requests such as `look online for the latest Ollama release` route through Hermes research.
- Natural Iris requests such as `generate an image of Iris as an electric blue logo` open an approval request, call the configured provider only after approval, save the file under `.iris-data\generated-images`, and show the generated preview.
- Hermes can propose staged memory, and Iris can transfer it into active memory only after explicit `hermes accept <number>`.
- Hermes cannot access raw memory files.
- Hermes cannot access cloud-sync storage.
- Safe mode cannot run commands, edit files, control browsers/windows, use the
  clipboard, or operate the computer.
- An explicit Agentic Session can use the reviewed file, PowerShell, process, and isolated browser tools through Iris supervision. Its selected workspace
  boundary is advisory rather than an OS sandbox. Scope-expanding and high-risk
  actions require separate confirmation, and Panic Stop terminates the session.
- Memory search is enabled for local approved memory by default.
- Memory proposals go to staging and require Iris/user approval before promotion.
- Memory archive export remains unavailable until real local encryption is implemented.
- Archive paths must be local Iris-owned paths and must end with `.iris-memory-archive.enc`.
- Live memory JSON/SQLite stores must not be placed under cloud-sync folders.

## If Wake Word Fails

Open this file after closing the app:

```text
C:\Projects\IRIS\diagnostics\voice-events.jsonl
```

The important events are:

- `native_asr_start_requested`
- `native_asr_result`
- `native_asr_no_input`
- `native_asr_error`
- `speech_interruption_listen_start`
- `speech_interruption_result`
- `speech_interruption_detected`
- `kokoro_tts_start`
- `kokoro_tts_error`
- `speech_started`
- `voice_decision`
- `submit_start`
- `submit_end`

If Iris stops listening, the last few lines of this file should show whether native ASR errored, returned an empty transcript, missed the wake word, or classified the transcript incorrectly.

## Expected Boundaries

- No fallback model should be used.
- No model download should start.
- No system control should occur in Safe mode or outside an explicitly approved
  Agentic Session. Agentic control remains limited to the reviewed file,
  PowerShell, process, and isolated browser tools.
- No programmatic clipboard reading should occur. User-driven paste into the text bar is allowed for prompt attachments.
- No continuous screen capture should occur. The screen icon performs one explicit capped capture of the area under Iris.
- File attachments are user selected through the attachment icon, paste, or drag/drop, and are consumed by the next prompt only.
- The configured model remains `huihui_ai/gemma-4-abliterated:e2b`.
- The configured TTS voice remains Kokoro `af_heart`.
- Wake-word mode is armed by default.
- Push-to-talk and typed text must keep working.
- The interruption word is `Iris` while Iris is speaking; `stop` and `Iris stop` should also cancel current speech.
- Voice input must use native local ASR. WebView speech recognition is not an acceptable runtime path because it censors profanity before Iris receives the transcript.
- Dynamic system context must store aggregate metrics only. It must not retain
  prompt text, attachment text, image contents, or screen contents.
