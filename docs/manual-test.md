# Iris Manual Test

Run this launcher from the repository root:

```text
C:\Projects\IRIS\Start Iris.vbs
```

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
2. Confirm only two visible boxes are present: the text input bar and the output box underneath it.
3. Type a short message and press the arrow button.
4. Confirm Iris shows `Thinking locally...`, then returns a local model response and speaks it with Kokoro `af_heart`.
5. Click the mic icon, say a short prompt, and confirm it submits through the same local model path.
6. Without pressing the mic icon, say `Iris`.
7. Confirm Iris acknowledges and stays ready for the next spoken request.
8. Say a short follow-up request.
9. Confirm Iris submits the follow-up, answers, and returns to wake-word listening.
10. Try `Iris what can you do right now?` as one phrase and confirm only the request after `Iris` is sent.
11. While Iris is speaking, say `Iris`, `stop`, or `Iris stop`.
12. Confirm Iris stops speaking and returns to listening.
13. Paste or drag a small png, jpg, jpeg, or webp image into the text bar.
14. Confirm a small attachment preview appears above the text bar, then ask Iris what is in the image.
15. Click and drag the narrow strip above the text bar or the small handle at the left of the text bar.
16. Confirm the Iris window moves without disrupting typing or buttons.
17. Click the camera icon with an empty text bar.
18. Confirm Iris takes a capped camera snapshot, answers what it can see, and speaks the answer.
19. Type a camera-specific question, then click the camera icon.
20. Confirm Iris uses that typed question for the camera snapshot.
21. Move Iris over a visible app, document, or webpage, then click the screen icon.
22. Confirm Iris briefly hides, captures the area underneath the Iris window, answers what it sees, and speaks the answer.
23. Type a screen-specific question, then click the screen icon.
24. Confirm Iris uses that typed question for the screen-area capture.
25. Drag a small mp4, webm, or mov video into the text bar.
26. Confirm Iris attaches one video frame preview for the next prompt.
27. Drag a txt, md, csv, json, log, or rtf text document into the text bar.
28. Confirm Iris shows a document attachment box and uses only capped text from that document as untrusted context.

## If Wake Word Fails

Open this file after closing the app:

```text
C:\Projects\IRIS\diagnostics\voice-events.jsonl
```

The important events are:

- `native_asr_start_requested`
- `native_asr_result`
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
- No system control should occur.
- No programmatic clipboard reading should occur. User-driven paste into the text bar is allowed for prompt attachments.
- No continuous screen capture should occur. The screen icon performs one explicit capped capture of the area under Iris.
- The configured model remains `huihui_ai/gemma-4-abliterated:e2b`.
- The configured TTS voice remains Kokoro `af_heart`.
- Wake-word mode is armed by default.
- Push-to-talk and typed text must keep working.
- The interruption word is `Iris` while Iris is speaking; `stop` and `Iris stop` should also cancel current speech.
- Voice input must use native local ASR. WebView speech recognition is not an acceptable runtime path because it censors profanity before Iris receives the transcript.
