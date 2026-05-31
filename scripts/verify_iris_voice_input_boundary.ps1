[CmdletBinding()]
param(
    [string] $ExpectedPhrase = "Testing now, Iris local voice test.",
    [string] $AnchorWordsCsv = "testing,voice,test",
    [int] $TimeoutSeconds = 30,
    [int] $MaxAttempts = 3,
    [string] $SimulatedTranscript = "",
    [switch] $StrictAnchorGate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location -Path $repoRoot

$listener = Join-Path $PSScriptRoot "listen_iris_local_speak.ps1"
$transcriptPath = Join-Path $repoRoot ".iris-dev\voice\last-transcript.txt"

if (-not (Test-Path $listener)) {
    throw "Missing listener: $listener"
}

$anchorWords = @(
    $AnchorWordsCsv -split "," |
        ForEach-Object { $_.Trim().ToLowerInvariant() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)

Write-Host "=== Project Iris voice input boundary verification ==="
Write-Host "When prompted, say clearly:"
Write-Host $ExpectedPhrase
Write-Host ("Anchor words for diagnostics: " + ($anchorWords -join ", "))
Write-Host ("Strict anchor gate: " + [bool]$StrictAnchorGate)

$powershellArgs = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $listener,
    "-ExpectedPhrase", $ExpectedPhrase,
    "-AnchorWordsCsv", $AnchorWordsCsv,
    "-TimeoutSeconds", $TimeoutSeconds.ToString(),
    "-MaxAttempts", $MaxAttempts.ToString(),
    "-NoResponse"
)

if (-not [string]::IsNullOrWhiteSpace($SimulatedTranscript)) {
    $powershellArgs += "-SimulatedTranscript"
    $powershellArgs += $SimulatedTranscript
}

powershell @powershellArgs

if ($LASTEXITCODE -ne 0) {
    throw "Voice input capture failed with exit code $LASTEXITCODE"
}

if (-not (Test-Path $transcriptPath)) {
    throw "Voice input passed but no transcript file was written."
}

$transcript = (Get-Content -Raw -Path $transcriptPath).Trim()

if ([string]::IsNullOrWhiteSpace($transcript)) {
    throw "Transcript file was empty."
}

$normalized = (($transcript.ToLowerInvariant() -replace "[^a-z0-9\s]", " ") -replace "\s+", " ").Trim()
$missing = @()

foreach ($word in $anchorWords) {
    $w = (($word.ToLowerInvariant() -replace "[^a-z0-9\s]", " ") -replace "\s+", " ").Trim()

    if (-not [string]::IsNullOrWhiteSpace($w) -and $normalized -notmatch [regex]::Escape($w)) {
        $missing += $word
    }
}

Write-Host ""
Write-Host ("Transcript: " + $transcript)

if ($missing.Count -gt 0) {
    Write-Host ("WARN: transcript is missing anchor words: " + ($missing -join ", "))

    if ($StrictAnchorGate) {
        throw "Transcript is missing expected words: $($missing -join ", ")"
    }
}
else {
    Write-Host "Anchor diagnostics: PASS"
}

Write-Host "Result: PASS"
Write-Host "PASS: Iris voice input boundary passed."
