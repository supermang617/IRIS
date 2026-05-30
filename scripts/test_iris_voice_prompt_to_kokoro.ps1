[CmdletBinding()]
param(
    [string[]] $ExpectedWords = @("testing", "iris", "voice", "test"),
    [switch] $NoPlay
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Set-Location -Path "C:\Projects\IRIS"

function Write-Section {
    param([string] $Text)
    Write-Host ""
    Write-Host "=== $Text ==="
}

function Invoke-Captured {
    param(
        [string] $Name,
        [string] $FilePath,
        [string[]] $ArgumentList
    )

    Write-Section $Name

    $outFile = Join-Path $env:TEMP ("iris-out-" + [guid]::NewGuid().ToString("N") + ".txt")
    $errFile = Join-Path $env:TEMP ("iris-err-" + [guid]::NewGuid().ToString("N") + ".txt")

    try {
        $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -NoNewWindow -Wait -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile
        $stdout = if (Test-Path $outFile) { Get-Content -Raw -Path $outFile } else { "" }
        $stderr = if (Test-Path $errFile) { Get-Content -Raw -Path $errFile } else { "" }

        if (-not [string]::IsNullOrWhiteSpace($stdout)) { Write-Host $stdout.TrimEnd() }
        if (-not [string]::IsNullOrWhiteSpace($stderr)) { Write-Host $stderr.TrimEnd() }

        if ($process.ExitCode -ne 0) { throw "$Name failed with exit code $($process.ExitCode)" }

        return $stdout
    } finally {
        Remove-Item -Force -ErrorAction SilentlyContinue $outFile, $errFile
    }
}

$env:IRIS_MODEL_ID = "huihui_ai/qwen3.5-abliterated:9b"
$env:IRIS_OLLAMA_MODEL = "huihui_ai/qwen3.5-abliterated:9b"
$env:IRIS_LOCAL_MODEL = "huihui_ai/qwen3.5-abliterated:9b"
$env:IRIS_MODEL_NUM_CTX = "8192"
$env:IRIS_MODEL_NUM_PREDICT = "160"

Write-Section "Required files"

$required = @(
    "scripts\verify_iris_voice_input_boundary.ps1",
    "scripts\listen_iris_local_speak.ps1",
    "scripts\ask_iris_local_speak.ps1",
    "scripts\speak_iris_kokoro.ps1",
    "scripts\resolve_iris_kokoro_provider.ps1",
    "scripts\play_iris_wav_bounded.ps1",
    "config\iris-voice-provider.dev.json"
)

foreach ($file in $required) {
    if (Test-Path $file) { Write-Host "FOUND: $file" } else { throw "Missing required file: $file" }
}

Write-Section "Resolve Kokoro provider"

$providerJson = powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\resolve_iris_kokoro_provider.ps1" -AsJson
$provider = $providerJson | ConvertFrom-Json

Write-Host "Provider OK: $($provider.ok)"
Write-Host "Model: $($provider.model_relative_path)"
Write-Host "Voices: $($provider.voices_relative_path)"

if (-not $provider.ok) { throw "Kokoro provider is incomplete." }

Write-Section "Voice capture instruction"
Write-Host "When prompted, say clearly: Testing now, Iris local voice test."
Write-Host "Required transcript words: $($ExpectedWords -join ", ")"

$before = Get-Date

Write-Section "Run Iris voice input boundary"

powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\verify_iris_voice_input_boundary.ps1"

if ($LASTEXITCODE -ne 0) { throw "Voice input boundary failed. Do not continue to model response." }

Write-Section "Find captured transcript"

$transcriptFiles = Get-ChildItem -Path ".iris-dev" -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {
        $_.FullName -notmatch "\\diagnostics\\backups\\" -and
        $_.Name -match "transcript" -and
        $_.LastWriteTime -ge $before.AddMinutes(-5)
    } |
    Sort-Object LastWriteTime -Descending

if (-not $transcriptFiles -or $transcriptFiles.Count -eq 0) {
    throw "No recent transcript file found after voice input boundary passed."
}

$transcriptPath = $transcriptFiles[0].FullName
$transcript = (Get-Content -Raw -Path $transcriptPath).Trim()
$transcript = $transcript -replace "`0", ""
$transcript = $transcript.Trim()

Write-Host "Transcript file: $transcriptPath"
Write-Host "Transcript: $transcript"

if ([string]::IsNullOrWhiteSpace($transcript)) { throw "Transcript was empty." }

$normalized = $transcript.ToLowerInvariant()

foreach ($word in $ExpectedWords) {
    if ($normalized -notmatch [regex]::Escape($word.ToLowerInvariant())) {
        throw "Transcript is missing expected word: $word"
    }
}

Write-Section "Run transcript through Iris local response path"

$responseOutput = Invoke-Captured "Iris response from voice transcript" "cargo" @(
    "run",
    "-p",
    "iris-runtime",
    "--",
    "hud-submit-test",
    $transcript
)

if ($responseOutput -notmatch "Response post-check:\s+PASS") { throw "Iris response post-check did not pass." }

$match = [regex]::Match($responseOutput, "HUD response:\s*(?<response>[\s\S]*?)\r?\nResult:\s*PASS")

if (-not $match.Success) { throw "Could not extract HUD response from Iris output." }

$reply = $match.Groups["response"].Value.Trim()
$reply = $reply -replace "`0", ""
$reply = $reply -replace "\x1B\[[0-9;]*[A-Za-z]", ""
$reply = $reply.Trim()

if ([string]::IsNullOrWhiteSpace($reply)) { throw "Iris produced an empty reply." }
if ($reply.Length -gt 300) { throw "Iris reply is too long for this milestone: $($reply.Length) characters." }

Write-Section "Extracted Iris reply"
Write-Host $reply

Write-Section "Speak Iris reply with Kokoro"

$speakArgs = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", "scripts\speak_iris_kokoro.ps1",
    "-Text", $reply,
    "-OutWav", ".iris-dev\diagnostics\voice-to-kokoro-response.wav",
    "-PlaybackSeconds", "6"
)

if ($NoPlay) { $speakArgs += "-NoPlay" }

powershell @speakArgs

if ($LASTEXITCODE -ne 0) { throw "Kokoro speech failed." }

Write-Section "Result"
Write-Host "PASS: voice input -> transcript -> Iris/Qwen response -> Kokoro speech completed."
