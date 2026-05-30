param(
    [string] $Prompt = "Iris, your voice sounds awesome.",
    [switch] $NoPlay
)

$ErrorActionPreference = "Stop"

Set-Location -Path "C:\Projects\IRIS"

Write-Host ""
Write-Host "=== Project Iris dev HUD speech boundary test ==="
Write-Host "Prompt: $Prompt"
Write-Host ""

$planOutput = & cargo run -p iris-runtime -- hud-speech-plan-test $Prompt 2>&1
$exitCode = $LASTEXITCODE
$lines = @($planOutput | ForEach-Object { "$_" })

$lines | ForEach-Object { Write-Host $_ }

if ($exitCode -ne 0) {
    throw "HUD speech plan failed with exit code $exitCode"
}

if (-not ($lines -contains "Result: PASS")) {
    throw "HUD speech plan did not report PASS"
}

if (-not ($lines -contains "Voice may speak: true")) {
    throw "HUD speech plan did not approve speech"
}

$speechMarkerIndex = [Array]::IndexOf($lines, "Speech text:")
if ($speechMarkerIndex -lt 0) {
    throw "Could not find Speech text marker in HUD speech plan output"
}

$speechText = $null

for ($i = $speechMarkerIndex + 1; $i -lt $lines.Count; $i++) {
    $candidate = $lines[$i].Trim()

    if ([string]::IsNullOrWhiteSpace($candidate)) {
        continue
    }

    if ($candidate -eq "Result: PASS") {
        break
    }

    $speechText = $candidate
    break
}

if ([string]::IsNullOrWhiteSpace($speechText)) {
    throw "Could not extract speech text from HUD speech plan output"
}

$speechLower = $speechText.ToLowerInvariant()

if ($speechLower.Contains("your voice sounds good")) {
    throw "Speech text still contains wrong Iris/user role wording: your voice sounds good"
}

if ($Prompt.ToLowerInvariant().Contains("your voice") -and -not $speechLower.Contains("my voice")) {
    throw "Speech text must say my voice when the user praises Iris's voice"
}

if ($speechLower.Contains("f*ck") -or $speechLower.Contains("f**k") -or $speechLower.Contains("sh*t")) {
    throw "Speech text contains censor-marker profanity that TTS could read incorrectly"
}

Write-Host ""
Write-Host "=== Approved speech text ==="
Write-Host $speechText

if ($NoPlay) {
    Write-Host ""
    Write-Host "NoPlay was set. Speech text was not played."
    Write-Host "Result: PASS"
    exit 0
}

$candidateScripts = @(
    "scripts\speak_iris_kokoro.ps1",
    "scripts\play_iris_kokoro.ps1",
    "scripts\say_iris_kokoro.ps1"
)

$speakScript = $null

foreach ($candidate in $candidateScripts) {
    if (Test-Path $candidate) {
        $speakScript = $candidate
        break
    }
}

if ($null -eq $speakScript) {
    $discovered = Get-ChildItem -Path "scripts" -File -Filter "*.ps1" -Recurse |
        Where-Object {
            $_.Name -match "kokoro|speak|tts" -and
            (Get-Content -Raw -Path $_.FullName) -match "\$Text|\$Prompt|\$InputText"
        } |
        Select-Object -First 1

    if ($null -ne $discovered) {
        $speakScript = $discovered.FullName
    }
}

if ($null -eq $speakScript) {
    throw "Could not find an existing Kokoro speak script"
}

Write-Host ""
Write-Host "=== Kokoro speak script ==="
Write-Host $speakScript

$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path $speakScript),
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

if ($paramNames -contains "Text") {
    $splat["Text"] = $speechText
} elseif ($paramNames -contains "Prompt") {
    $splat["Prompt"] = $speechText
} elseif ($paramNames -contains "InputText") {
    $splat["InputText"] = $speechText
} elseif ($paramNames -contains "Message") {
    $splat["Message"] = $speechText
}

if ($paramNames -contains "Voice") {
    $splat["Voice"] = "af_heart"
}

if ($paramNames -contains "Speed") {
    $splat["Speed"] = 0.95
}

if ($splat.Count -gt 0) {
    powershell -NoProfile -ExecutionPolicy Bypass -File $speakScript @splat
} else {
    powershell -NoProfile -ExecutionPolicy Bypass -File $speakScript $speechText
}

if ($LASTEXITCODE -ne 0) {
    throw "Kokoro speak script failed"
}

Write-Host ""
Write-Host "Result: PASS"
