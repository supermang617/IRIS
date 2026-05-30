$ErrorActionPreference = "Stop"
Set-Location -Path "C:\Projects\IRIS"

New-Item -ItemType Directory -Force ".iris-dev\diagnostics" | Out-Null
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$report = ".iris-dev\diagnostics\iris-voice-provider-test-$timestamp.txt"

function Write-Report {
    param([string] $Text)

    Write-Host $Text
    Add-Content -Encoding UTF8 -Path $report -Value $Text
}

function Write-Section {
    param([string] $Text)

    Write-Report ""
    Write-Report "=== $Text ==="
}

function Invoke-IrisNativeCapture {
    param(
        [string] $Name,
        [string] $FilePath,
        [string[]] $Arguments
    )

    Write-Section $Name

    $base = Join-Path $env:TEMP ("iris-voice-provider-" + [guid]::NewGuid().ToString())
    $stdout = "$base.out"
    $stderr = "$base.err"

    try {
        $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr

        $captured = New-Object System.Collections.Generic.List[string]

        if (Test-Path $stdout) {
            Get-Content -Path $stdout | ForEach-Object {
                $captured.Add($_)
                Write-Report $_
            }
        }

        if (Test-Path $stderr) {
            Get-Content -Path $stderr | ForEach-Object {
                $captured.Add($_)
                Write-Report $_
            }
        }

        if ($process.ExitCode -ne 0) {
            throw "$Name failed with exit code $($process.ExitCode)"
        }

        return @($captured)
    } finally {
        Remove-Item -Force -ErrorAction SilentlyContinue $stdout, $stderr
    }
}

Write-Section "Iris voice provider test"
Write-Report "Goal: prefer Kokoro later, allow SAPI only as fallback now."

$Prompt = "Hello Iris. In one short sentence, say the voice provider test is running."

Write-Section "Model check"

if (-not (Get-Command ollama -ErrorAction SilentlyContinue)) {
    throw "Ollama command not found."
}

$modelLine = @(ollama list | Select-Object -Skip 1 | Where-Object {
    $_.Trim() -match "^huihui_ai/qwen3\.5-abliterated(:\S+)?\s+"
} | Select-Object -First 1)

if (-not $modelLine) {
    throw "Qwen 3.5 target model is not installed."
}

$TargetModel = (($modelLine[0].Trim()) -split "\s+")[0]

$env:IRIS_MODEL_ID = $TargetModel
$env:IRIS_OLLAMA_MODEL = $TargetModel
$env:IRIS_LOCAL_MODEL = $TargetModel
$env:IRIS_MODEL_NUM_CTX = "8192"
$env:IRIS_MODEL_NUM_PREDICT = "160"

Write-Report "Model: $TargetModel"
Write-Report "Context: $env:IRIS_MODEL_NUM_CTX"
Write-Report "Max response tokens: $env:IRIS_MODEL_NUM_PREDICT"

$output = Invoke-IrisNativeCapture "Get checked Iris response" "cargo" @(
    "run",
    "-p",
    "iris-runtime",
    "--",
    "hud-submit-test",
    $Prompt
)

$responseLines = New-Object System.Collections.Generic.List[string]
$capture = $false

foreach ($line in $output) {
    if ($line -match "^HUD response:\s*$") {
        $capture = $true
        continue
    }

    if ($capture -and $line -match "^Result:\s*PASS") {
        break
    }

    if ($capture) {
        $clean = $line.Trim()
        if (-not [string]::IsNullOrWhiteSpace($clean)) {
            $responseLines.Add($clean)
        }
    }
}

$IrisResponse = ($responseLines -join " ").Trim()

if ([string]::IsNullOrWhiteSpace($IrisResponse)) {
    throw "Could not parse Iris response from HUD output."
}

Write-Section "Parsed Iris response"
Write-Report $IrisResponse

Write-Section "Search for Kokoro provider"

$kokoroCandidates = @(Get-ChildItem -Path "." -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
    $_.FullName -notmatch "\\target\\" -and
    $_.FullName -notmatch "\\.git\\" -and
    $_.FullName -notmatch "\\.iris-dev\\" -and
    (
        $_.Name -match "kokoro" -or
        $_.Extension -eq ".onnx"
    )
})

if ($kokoroCandidates.Count -gt 0) {
    Write-Report "Kokoro-related files found:"
    $kokoroCandidates | Select-Object -First 30 | ForEach-Object { Write-Report $_.FullName }
} else {
    Write-Report "No Kokoro-related files found in repo."
}

Write-Section "Voice output"

$usedProvider = "sapi-fallback"

try {
    $voice = New-Object -ComObject SAPI.SpVoice
    $voice.Rate = 0
    $voice.Volume = 100
    [void] $voice.Speak($IrisResponse)

    Write-Report "Provider used: $usedProvider"
    Write-Report "PASS: Voice output completed through SAPI fallback."
} catch {
    throw "SAPI fallback failed: $($_.Exception.Message)"
}

Write-Section "Result"
Write-Report "PASS: Voice provider test completed."
Write-Report "Next: wire Kokoro as preferred provider after confirming the local Kokoro runtime/model path."
Write-Report "Report: $report"
