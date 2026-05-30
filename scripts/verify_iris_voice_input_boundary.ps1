param(
    [int] $TimeoutSeconds = 10
)

$ErrorActionPreference = "Stop"

Set-Location -Path "C:\Projects\IRIS"

Write-Host ""
Write-Host "=== Project Iris voice input boundary verification ==="
Write-Host "Timeout seconds: $TimeoutSeconds"
Write-Host ""
Write-Host "When prompted, say:"
Write-Host "Iris, your voice sounds awesome."
Write-Host ""

$candidates = @(
    "scripts\listen_iris_local_speak.ps1",
    "scripts\test_iris_voice_text_response.ps1",
    "scripts\test_iris_voice_text_response_fixed.ps1"
)

$voiceScript = $null

foreach ($candidate in $candidates) {
    if (Test-Path $candidate) {
        $voiceScript = $candidate
        break
    }
}

if ($null -eq $voiceScript) {
    throw "No existing voice input script found."
}

Write-Host "Voice input script: $voiceScript"

$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path $voiceScript),
    [ref] $tokens,
    [ref] $parseErrors
)

$paramNames = @()

if ($null -ne $ast.ParamBlock) {
    $paramNames = @(
        $ast.ParamBlock.Parameters |
            ForEach-Object { $_.Name.VariablePath.UserPath }
    )
}

$splat = @{}

if ($paramNames -contains "TimeoutSeconds") {
    $splat["TimeoutSeconds"] = $TimeoutSeconds
}

if ($paramNames -contains "NoSpeak") {
    $splat["NoSpeak"] = $true
}

if ($paramNames -contains "NoPlay") {
    $splat["NoPlay"] = $true
}

if ($paramNames -contains "DryRun") {
    $splat["DryRun"] = $false
}

Write-Host ""
Write-Host "=== Running voice input boundary ==="

$output = & $voiceScript @splat 2>&1
$exitCode = $LASTEXITCODE
$lines = @($output | ForEach-Object { "$_" })

$lines | ForEach-Object { Write-Host $_ }

if ($exitCode -ne 0) {
    throw "Voice input script failed with exit code $exitCode"
}

$joined = $lines -join "`n"

if ($joined -match "Recognized transcript\s*===\s*(?<text>.+)") {
    $transcript = $Matches["text"].Trim()
} elseif ($joined -match "Transcript:\s*(?<text>.+)") {
    $transcript = $Matches["text"].Trim()
} elseif ($joined -match "Prompt:\s*(?<text>.+)") {
    $transcript = $Matches["text"].Trim()
} else {
    $transcript = $null
}

if ([string]::IsNullOrWhiteSpace($transcript)) {
    throw "Could not extract transcript from voice input output."
}

Write-Host ""
Write-Host "=== Extracted transcript ==="
Write-Host $transcript

if ($transcript.Length -lt 3) {
    throw "Transcript is too short to be useful."
}

$transcriptPath = ".iris-dev\voice\last-transcript.txt"
Set-Content -Encoding UTF8 -Path $transcriptPath -Value $transcript

Write-Host ""
Write-Host "Transcript file: $transcriptPath"
Write-Host "Result: PASS"

