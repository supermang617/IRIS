param(
    [string] $Prompt = "In one sentence, say hello as Iris and confirm you are running locally.",
    [switch] $DryRun,
    [switch] $NoSpeak,
    [int] $Rate = 0,
    [int] $Volume = 90
)

$ErrorActionPreference = "Stop"

Set-Location -Path "C:\Projects\IRIS"

function Join-NativeArguments {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Arguments
    )

    $quoted = foreach ($argument in $Arguments) {
        if ($null -eq $argument) {
            '""'
        } else {
            '"' + ($argument.Replace('\', '\\').Replace('"', '\"')) + '"'
        }
    }

    $quoted -join " "
}

function Invoke-NativeCapture {
    param(
        [Parameter(Mandatory = $true)]
        [string] $CommandName,

        [Parameter(Mandatory = $true)]
        [string[]] $Arguments
    )

    $command = Get-Command $CommandName -CommandType Application -ErrorAction Stop
    $stdoutPath = [System.IO.Path]::GetTempFileName()
    $stderrPath = [System.IO.Path]::GetTempFileName()

    try {
        $argumentString = Join-NativeArguments -Arguments $Arguments

        $process = Start-Process `
            -FilePath $command.Source `
            -ArgumentList $argumentString `
            -NoNewWindow `
            -Wait `
            -PassThru `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath

        [pscustomobject]@{
            ExitCode = $process.ExitCode
            Stdout = Get-Content -Raw -Path $stdoutPath
            Stderr = Get-Content -Raw -Path $stderrPath
        }
    } finally {
        Remove-Item -Force -ErrorAction SilentlyContinue $stdoutPath
        Remove-Item -Force -ErrorAction SilentlyContinue $stderrPath
    }
}

Write-Host ""
Write-Host "=== Project Iris text prompt + spoken response test ==="
Write-Host "Prompt: $Prompt"

if ($DryRun) {
    Write-Host ""
    Write-Host "Dry run only."
    Write-Host "This script will:"
    Write-Host "- send a text prompt through Iris ask-local"
    Write-Host "- capture stdout and stderr separately through Start-Process"
    Write-Host "- require Response post-check: PASS"
    Write-Host "- extract the checked model response"
    Write-Host "- print the text response"
    Write-Host "- speak the response using local Windows speech synthesis unless -NoSpeak is used"
    Write-Host "No model call was made."
    Write-Host "No speech was played."
    Write-Host "Result: PASS"
    return
}

$result = Invoke-NativeCapture -CommandName "cargo" -Arguments @(
    "run",
    "-p",
    "iris-runtime",
    "--",
    "ask-local",
    $Prompt
)

Write-Host ""
Write-Host "=== Cargo/runtime stderr ==="
if ([string]::IsNullOrWhiteSpace($result.Stderr)) {
    Write-Host "(none)"
} else {
    Write-Host $result.Stderr
}

Write-Host ""
Write-Host "=== Raw Iris output ==="
Write-Host $result.Stdout

if ($result.ExitCode -ne 0) {
    throw "Iris ask-local failed with exit code $($result.ExitCode)"
}

if ($result.Stdout -match "Response post-check: BLOCKED") {
    throw "Response was blocked. Refusing to speak model output."
}

if ($result.Stdout -notmatch "Response post-check: PASS") {
    throw "Response post-check did not pass. Refusing to speak model output."
}

$lines = $result.Stdout -split '\r?\n'
$startIndex = -1

for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].Trim() -eq "Model response:") {
        $startIndex = $i + 1
        break
    }
}

if ($startIndex -lt 0) {
    throw "Could not find model response in Iris output."
}

$responseLines = New-Object System.Collections.Generic.List[string]

for ($i = $startIndex; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]

    if ($line.StartsWith("Backend:") -or $line.StartsWith("Result:")) {
        break
    }

    if (-not [string]::IsNullOrWhiteSpace($line)) {
        $responseLines.Add($line)
    }
}

$responseText = ($responseLines -join "`n").Trim()

if ([string]::IsNullOrWhiteSpace($responseText)) {
    throw "Model response was empty."
}

Write-Host ""
Write-Host "=== Iris text response ==="
Write-Host $responseText

if ($NoSpeak) {
    Write-Host ""
    Write-Host "Speech skipped because -NoSpeak was provided."
    Write-Host "Result: PASS"
    return
}

Write-Host ""
Write-Host "=== Speaking Iris response locally ==="

Add-Type -AssemblyName System.Speech

$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
$synth.Rate = $Rate
$synth.Volume = $Volume

try {
    $synth.Speak($responseText)
} finally {
    $synth.Dispose()
}

Write-Host ""
Write-Host "Result: PASS"
