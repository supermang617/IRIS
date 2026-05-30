[CmdletBinding()]
param(
    [string] $ExpectedPhrase = "Testing now, Iris local voice test.",
    [string[]] $AnchorWords = @("testing", "iris", "voice", "test"),
    [int] $TimeoutSeconds = 25,
    [int] $MaxAttempts = 3,
    [switch] $NoResponse
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$voiceDir = Join-Path $repoRoot ".iris-dev\voice"
$diagDir = Join-Path $repoRoot ".iris-dev\diagnostics"
New-Item -ItemType Directory -Force -Path @($voiceDir, $diagDir) | Out-Null
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$transcriptPath = Join-Path $voiceDir "last-transcript.txt"
$diagPath = Join-Path $diagDir "voice-input-$timestamp.txt"
Remove-Item -Force -ErrorAction SilentlyContinue $transcriptPath
function Add-Diag { param([string] $Text) $Text | Add-Content -Encoding UTF8 $diagPath }
Write-Host "=== Project Iris one-shot voice input ==="
Write-Host "Expected phrase: $ExpectedPhrase"
Write-Host "Timeout seconds: $TimeoutSeconds"
Write-Host "Max attempts: $MaxAttempts"
Write-Host "Speak only after: Listening now..."
Add-Diag "Project Iris voice input diagnostic"
Add-Diag "Expected phrase: $ExpectedPhrase"
try { Add-Type -AssemblyName System.Speech } catch { throw "System.Speech is unavailable. Check Windows speech components." }
$recognizer = $null
try {
    $recognizer = New-Object System.Speech.Recognition.SpeechRecognitionEngine
    $recognizer.SetInputToDefaultAudioDevice()
    $grammar = New-Object System.Speech.Recognition.DictationGrammar
    $recognizer.LoadGrammar($grammar)
    Add-Diag "Recognizer: $($recognizer.RecognizerInfo.Name)"
    Add-Diag "Culture: $($recognizer.RecognizerInfo.Culture.Name)"
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        Write-Host ""
        Write-Host "=== Voice input capture attempt $attempt of $MaxAttempts ==="
        Write-Host "Listening now..."
        $result = $recognizer.Recognize([TimeSpan]::FromSeconds($TimeoutSeconds))
        if ($null -eq $result) {
            Write-Host "No speech was recognized on attempt $attempt."
            Add-Diag "Attempt $attempt: no speech recognized"
            continue
        }
        $text = ($result.Text).Trim()
        Write-Host "Transcript candidate: $text"
        Write-Host "Confidence: $($result.Confidence)"
        Add-Diag "Attempt $attempt transcript: $text"
        Add-Diag "Attempt $attempt confidence: $($result.Confidence)"
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            $text | Set-Content -Encoding UTF8 $transcriptPath
            Write-Host ""
            Write-Host "Transcript accepted: $text"
            Write-Host "Transcript file: $transcriptPath"
            Write-Host "Result: PASS"
            exit 0
        }
    }
    throw "No speech was recognized. Check Windows default input device, mic privacy permission, and mic gain."
} finally {
    if ($null -ne $recognizer) { $recognizer.Dispose() }
}
