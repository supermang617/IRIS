[CmdletBinding()]
param(
    [string] $Transcript = "",
    [string] $TranscriptPath = ".iris-dev\voice\last-transcript.txt",
    [string] $AnchorWordsCsv = "testing,voice,test",
    [int] $MinAnchorHits = 2,
    [int] $MinChars = 3
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location -Path $repoRoot

function Normalize-Text {
    param([string] $Text)
    return (($Text.ToLowerInvariant() -replace "[^a-z0-9\s]", " ") -replace "\s+", " ").Trim()
}

if ([string]::IsNullOrWhiteSpace($Transcript)) {
    if (-not (Test-Path $TranscriptPath)) {
        throw "Transcript file missing: $TranscriptPath"
    }

    $Transcript = (Get-Content -Raw -Path $TranscriptPath).Trim()
}

if ([string]::IsNullOrWhiteSpace($Transcript)) {
    throw "Transcript is empty."
}

if ($Transcript.Trim().Length -lt $MinChars) {
    throw "Transcript is too short to trust: $Transcript"
}

$anchors = @(
    $AnchorWordsCsv -split "," |
        ForEach-Object { $_.Trim().ToLowerInvariant() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)

$normalized = Normalize-Text $Transcript
$hits = @()

foreach ($anchor in $anchors) {
    $needle = Normalize-Text $anchor

    if (-not [string]::IsNullOrWhiteSpace($needle) -and $normalized -match [regex]::Escape($needle)) {
        $hits += $anchor
    }
}

Write-Host "=== Iris transcript quality gate ==="
Write-Host ("Transcript: " + $Transcript)
Write-Host ("Required anchor hits: " + $MinAnchorHits)
Write-Host ("Anchor words: " + ($anchors -join ", "))
Write-Host ("Matched anchors: " + ($hits -join ", "))
Write-Host ("Matched count: " + $hits.Count)

if ($anchors.Count -gt 0 -and $hits.Count -lt $MinAnchorHits) {
    throw "Transcript quality gate failed. Blocking model response because speech recognition likely misheard the user."
}

Write-Host "Result: PASS"
Write-Host "PASS: transcript quality gate passed."
