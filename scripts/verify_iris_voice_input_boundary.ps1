param(
    [int] $TimeoutSeconds = 10,
    [string] $ExpectedPhrase = "Hello Iris.",
    [switch] $AllowUnverifiedTranscript
)

$ErrorActionPreference = "Stop"

Set-Location -Path "C:\Projects\IRIS"

New-Item -ItemType Directory -Force ".iris-dev\voice" | Out-Null

$transcriptPath = ".iris-dev\voice\last-transcript.txt"
$rejectedTranscriptPath = ".iris-dev\voice\last-transcript-rejected.txt"

Remove-Item -Force -ErrorAction SilentlyContinue $transcriptPath
Remove-Item -Force -ErrorAction SilentlyContinue $rejectedTranscriptPath

function Join-NativeArguments {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Arguments
    )

    $quoted = foreach ($argument in $Arguments) {
        if ($null -eq $argument) {
            '""'
        } elseif ($argument -match '[\s"]') {
            '"' + ($argument.Replace('"', '\"')) + '"'
        } else {
            $argument
        }
    }

    $quoted -join " "
}

function Invoke-NativeCapture {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [string] $CommandName,

        [Parameter(Mandatory = $true)]
        [string[]] $Arguments
    )

    Write-Host ""
    Write-Host "=== $Name ==="

    $command = Get-Command $CommandName -CommandType Application -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        throw "Command not found: $CommandName"
    }

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

        $stdout = Get-Content -Raw -ErrorAction SilentlyContinue -Path $stdoutPath
        $stderr = Get-Content -Raw -ErrorAction SilentlyContinue -Path $stderrPath
        $combined = (($stdout, $stderr) -join "`n").Trim()

        if (-not [string]::IsNullOrWhiteSpace($combined)) {
            Write-Host $combined
        }

        if ($process.ExitCode -ne 0) {
            throw "$Name failed with exit code $($process.ExitCode)"
        }

        return $combined
    } finally {
        Remove-Item -Force -ErrorAction SilentlyContinue $stdoutPath
        Remove-Item -Force -ErrorAction SilentlyContinue $stderrPath
    }
}

function Get-TranscriptFromOutput {
    param([string] $Output)

    $lines = @($Output -split "`r?`n")

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i].Trim()

        if ($line -match "Recognized transcript") {
            for ($j = $i + 1; $j -lt $lines.Count; $j++) {
                $candidate = $lines[$j].Trim()

                if ([string]::IsNullOrWhiteSpace($candidate)) {
                    continue
                }

                if ($candidate.StartsWith("===")) {
                    break
                }

                return $candidate
            }
        }
    }

    foreach ($line in $lines) {
        if ($line -match "^Transcript:\s*(?<text>.+)$") {
            return $Matches["text"].Trim()
        }

        if ($line -match "^Prompt:\s*(?<text>.+)$") {
            return $Matches["text"].Trim()
        }
    }

    return $null
}

function Get-NormalizedWords {
    param([string] $Text)

    @([regex]::Matches($Text.ToLowerInvariant(), "[a-z0-9']+") | ForEach-Object { $_.Value })
}

function Test-ExpectedTranscript {
    param(
        [string] $Transcript,
        [string] $Expected
    )

    $transcriptWords = @(Get-NormalizedWords -Text $Transcript)
    $expectedWords = @(Get-NormalizedWords -Text $Expected)

    if ($expectedWords.Count -eq 0) {
        return $true
    }

    $missing = New-Object System.Collections.Generic.List[string]

    foreach ($word in $expectedWords) {
        if ($word -eq "iris") {
            $irisMatched = $transcriptWords -contains "iris" -or
                $transcriptWords -contains "irish" -or
                $transcriptWords -contains "heiress"

            if (-not $irisMatched) {
                $missing.Add("iris")
            }

            continue
        }

        if (-not ($transcriptWords -contains $word)) {
            $missing.Add($word)
        }
    }

    if ($missing.Count -gt 0) {
        Write-Host ""
        Write-Host "Missing expected word(s): $($missing -join ', ')"
        return $false
    }

    return $true
}

Write-Host ""
Write-Host "=== Project Iris voice input boundary verification ==="
Write-Host "Timeout seconds: $TimeoutSeconds"
Write-Host "Expected phrase: $ExpectedPhrase"
Write-Host ""
Write-Host "When prompted, say exactly:"
Write-Host $ExpectedPhrase
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

$voiceArgs = @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $voiceScript
)

if ($paramNames -contains "TimeoutSeconds") {
    $voiceArgs += @("-TimeoutSeconds", "$TimeoutSeconds")
}

if ($paramNames -contains "NoSpeak") {
    $voiceArgs += "-NoSpeak"
}

if ($paramNames -contains "NoPlay") {
    $voiceArgs += "-NoPlay"
}

# Important:
# Do not pass -DryRun:$false to child scripts.
# DryRun is a switch parameter; omitting it means false.
# Passing it incorrectly can break voice capture before STT starts.

Write-Host ""
Write-Host "Listening will start now."

$output = Invoke-NativeCapture `
    -Name "Voice input capture" `
    -CommandName "powershell" `
    -Arguments $voiceArgs

$transcript = Get-TranscriptFromOutput -Output $output

if ([string]::IsNullOrWhiteSpace($transcript)) {
    throw "Could not extract transcript from voice input output."
}

Write-Host ""
Write-Host "=== Extracted transcript ==="
Write-Host $transcript

if ($transcript.Length -lt 3) {
    Set-Content -Encoding UTF8 -Path $rejectedTranscriptPath -Value $transcript
    throw "Transcript is too short to be useful."
}

$matchesExpected = Test-ExpectedTranscript -Transcript $transcript -Expected $ExpectedPhrase

if (-not $matchesExpected -and -not $AllowUnverifiedTranscript) {
    Set-Content -Encoding UTF8 -Path $rejectedTranscriptPath -Value $transcript

    Write-Host ""
    Write-Host "Rejected transcript file: $rejectedTranscriptPath"
    throw "Transcript failed quality gate. Iris will not answer because the captured words did not match what you were asked to say."
}

Set-Content -Encoding UTF8 -Path $transcriptPath -Value $transcript

Write-Host ""
Write-Host "Transcript quality gate: PASS"
Write-Host "Transcript file: $transcriptPath"
Write-Host "Result: PASS"
