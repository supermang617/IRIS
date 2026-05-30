param(
    [string] $TextPrompt = "Hello Iris. In one short sentence, confirm you are running locally with your Kokoro voice.",
    [int] $TimeoutSeconds = 10,
    [switch] $NoVoiceInput,
    [switch] $NoSpeak,
    [switch] $SkipBuild,
    [switch] $DryRun
)

$ErrorActionPreference = "Stop"

Set-Location -Path "C:\Projects\IRIS"

Write-Host ""
Write-Host "=== Project Iris live text + voice session ==="
Write-Host "Text prompt: $TextPrompt"
Write-Host "Voice input timeout seconds: $TimeoutSeconds"

if ($DryRun) {
    Write-Host ""
    Write-Host "Dry run only."
    Write-Host "This script will:"
    Write-Host "- verify baseline build/test/status unless -SkipBuild is used"
    Write-Host "- run typed prompt -> Iris -> checked response -> Kokoro voice"
    Write-Host "- run explicit one-shot spoken prompt -> Iris -> checked response -> Kokoro voice unless -NoVoiceInput is used"
    Write-Host "- keep microphone inactive until the explicit voice-input step"
    Write-Host "- use no wake word and no always-listening mode"
    Write-Host "No model call was made."
    Write-Host "No microphone capture was started."
    Write-Host "No speech was played."
    Write-Host "Result: PASS"
    exit 0
}

function Invoke-IrisStep {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [scriptblock] $Command
    )

    Write-Host ""
    Write-Host "=== $Name ==="

    & $Command

    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE"
    }
}

if (-not $SkipBuild) {
    Invoke-IrisStep "Cargo format" {
        cargo fmt --all
    }

    Invoke-IrisStep "Cargo build" {
        cargo build --workspace
    }

    Invoke-IrisStep "Cargo test" {
        cargo test --workspace
    }

    Invoke-IrisStep "Xtask audit" {
        cargo run -p xtask
    }
}

Invoke-IrisStep "Runtime self-check" {
    cargo run -p iris-runtime -- self-check
}

Invoke-IrisStep "Runtime voice status" {
    cargo run -p iris-runtime -- voice-status
}

Invoke-IrisStep "Runtime push-to-talk visible-state test" {
    cargo run -p iris-runtime -- voice-ptt-state-test
}

Invoke-IrisStep "Runtime response post-check test" {
    cargo run -p iris-runtime -- response-check-test
}

Write-Host ""
Write-Host "=== Typed prompt -> Iris -> Kokoro voice ==="

$textArgs = @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    "scripts\test_iris_text_voice_response.ps1",
    "-Prompt",
    $TextPrompt,
    "-TtsBackend",
    "Kokoro",
    "-KokoroVoice",
    "af_heart",
    "-KokoroSpeed",
    "0.95",
    "-KokoroWakeSignalMs",
    "900",
    "-KokoroLeadSilenceMs",
    "300",
    "-KokoroTailSilenceMs",
    "300"
)

if ($NoSpeak) {
    $textArgs += "-NoSpeak"
}

powershell @textArgs
if ($LASTEXITCODE -ne 0) {
    throw "Typed prompt to Kokoro voice failed"
}

if ($NoVoiceInput) {
    Write-Host ""
    Write-Host "Voice input skipped because -NoVoiceInput was provided."
    Write-Host "Result: PASS"
    exit 0
}

Write-Host ""
Write-Host "=== Explicit spoken prompt -> Iris -> Kokoro voice ==="
Write-Host "When it says Listening now, say something short like:"
Write-Host "Hello Iris, can you hear me and answer with your Kokoro voice?"

$voiceArgs = @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    "scripts\test_iris_voice_text_response.ps1",
    "-TimeoutSeconds",
    "$TimeoutSeconds"
)

if ($NoSpeak) {
    $voiceArgs += "-NoSpeak"
}

powershell @voiceArgs
if ($LASTEXITCODE -ne 0) {
    throw "Explicit spoken prompt to Kokoro voice failed"
}

Write-Host ""
Write-Host "=== Live session result ==="
Write-Host "PASS: Iris accepted typed input, accepted explicit spoken input, answered with checked local model text, and spoke with Kokoro."
