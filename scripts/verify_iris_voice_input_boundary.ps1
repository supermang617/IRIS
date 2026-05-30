[CmdletBinding()]
param(
    [string] $ExpectedPhrase = "Testing now, Iris local voice test.",
    [string[]] $AnchorWords = @("testing", "voice", "test"),
    [int] $TimeoutSeconds = 30,
    [int] $MaxAttempts = 3
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

$anchorWordsCsv = ($AnchorWords -join ",")

Write-Host "=== Project Iris voice input boundary verification ==="
Write-Host "When prompted, say clearly:"
Write-Host $ExpectedPhrase
Write-Host ("Required anchor words: " + ($AnchorWords -join ", "))

$powershellArgs = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $listener,
    "-ExpectedPhrase", $ExpectedPhrase,
    "-AnchorWordsCsv", $anchorWordsCsv,
    "-TimeoutSeconds", "$TimeoutSeconds",
    "-MaxAttempts", "$MaxAttempts",`r`n    "-NoResponse"
)


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

foreach ($word in $AnchorWords) {
    $w = (($word.ToLowerInvariant() -replace "[^a-z0-9\s]", " ") -replace "\s+", " ").Trim()

    if (-not [string]::IsNullOrWhiteSpace($w) -and $normalized -notmatch [regex]::Escape($w)) {
        $missing += $word
    }
}

if ($missing.Count -gt 0) {
    throw "Transcript is missing expected words: $($missing -join ", ")"
}

Write-Host ""
Write-Host ("Transcript: " + $transcript)
Write-Host "Result: PASS"
Write-Host "PASS: Iris voice input boundary passed."
