[CmdletBinding()]
param(
    [string] $ExpectedPhrase = "Testing now, Iris local voice test.",
    [string] $AnchorWordsCsv = "testing,voice,test",
    [int] $TimeoutSeconds = 30,
    [int] $MaxAttempts = 3,
    [switch] $NoResponse,
    [string] $SimulatedTranscript = "",
    [ValidateSet("Auto", "Phrase", "Dictation")]
    [string] $RecognitionMode = "Auto",
    [double] $MinConfidence = 0.35
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$voiceDir = Join-Path $repoRoot ".iris-dev\voice"
$diagDir = Join-Path $repoRoot ".iris-dev\diagnostics"

New-Item -ItemType Directory -Force -Path @($voiceDir, $diagDir) | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$transcriptPath = Join-Path $voiceDir "last-transcript.txt"
$diagPath = Join-Path $diagDir ("voice-input-" + $timestamp + ".txt")

Remove-Item -Force -ErrorAction SilentlyContinue $transcriptPath

$anchorWords = @(
    $AnchorWordsCsv -split "," |
        ForEach-Object { $_.Trim().ToLowerInvariant() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)

function Add-Diag {
    param([string] $Text)
    $Text | Add-Content -Encoding UTF8 $diagPath
}

function Save-Transcript {
    param([string] $Text)

    $clean = ($Text -replace "`0", "").Trim()

    if ([string]::IsNullOrWhiteSpace($clean)) {
        throw "Transcript was empty."
    }

    $clean | Set-Content -Encoding UTF8 $transcriptPath

    Add-Diag ("Final transcript: " + $clean)
    Add-Diag ("Transcript file: " + $transcriptPath)

    Write-Host ""
    Write-Host "=== Extracted transcript ==="
    Write-Host $clean
    Write-Host ("Transcript file: " + $transcriptPath)
    Write-Host "Result: PASS"
}

Write-Host "=== Project Iris one-shot voice input ==="
Write-Host ("Expected phrase: " + $ExpectedPhrase)
Write-Host ("Anchor words for diagnostics: " + ($anchorWords -join ", "))
Write-Host ("Timeout seconds: " + $TimeoutSeconds)
Write-Host ("Max attempts: " + $MaxAttempts)
Write-Host ("Recognition mode: " + $RecognitionMode)
Write-Host ("Minimum confidence: " + $MinConfidence)
Write-Host "Mode: explicit bounded voice input"

Add-Diag "Project Iris voice input diagnostic"
Add-Diag ("Expected phrase: " + $ExpectedPhrase)
Add-Diag ("Anchor words: " + ($anchorWords -join ", "))
Add-Diag ("Recognition mode: " + $RecognitionMode)
Add-Diag ("Minimum confidence: " + $MinConfidence)

if (-not [string]::IsNullOrWhiteSpace($SimulatedTranscript)) {
    Write-Host "Mode: simulated transcript"
    Add-Diag "Mode: simulated transcript"
    Save-Transcript $SimulatedTranscript
    exit 0
}

Write-Host "Speak only after: Listening now..."

try {
    Add-Type -AssemblyName System.Speech
}
catch {
    throw "System.Speech is unavailable. Check Windows speech components."
}

$recognizer = $null
$acceptedTranscript = ""

try {
    $recognizer = New-Object System.Speech.Recognition.SpeechRecognitionEngine
    $recognizer.SetInputToDefaultAudioDevice()

    $effectiveMode = $RecognitionMode

    if ($effectiveMode -eq "Auto") {
        if ([string]::IsNullOrWhiteSpace($ExpectedPhrase)) {
            $effectiveMode = "Dictation"
        }
        else {
            $effectiveMode = "Phrase"
        }
    }

    if ($effectiveMode -eq "Phrase") {
        $choices = New-Object System.Speech.Recognition.Choices

        $cleanExpected = (($ExpectedPhrase -replace "[^A-Za-z0-9\s]", " ") -replace "\s+", " ").Trim()

        $phraseOptions = @(
            $ExpectedPhrase,
            $cleanExpected,
            "Testing now Iris local voice test",
            "Iris local voice test",
            "Testing Iris voice test"
        ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

        foreach ($phrase in $phraseOptions) {
            [void] $choices.Add($phrase)
        }

        $grammarBuilder = New-Object System.Speech.Recognition.GrammarBuilder
        $grammarBuilder.Append($choices)

        $grammar = New-Object System.Speech.Recognition.Grammar($grammarBuilder)
        $grammar.Name = "Iris bounded phrase grammar"
        $recognizer.LoadGrammar($grammar)

        Add-Diag ("Loaded grammar: phrase")
        Add-Diag ("Phrase options: " + ($phraseOptions -join " | "))
    }
    else {
        $grammar = New-Object System.Speech.Recognition.DictationGrammar
        $grammar.Name = "Iris dictation"
        $recognizer.LoadGrammar($grammar)

        Add-Diag ("Loaded grammar: dictation")
    }

    Add-Diag ("Recognizer: " + $recognizer.RecognizerInfo.Name)
    Add-Diag ("Culture: " + $recognizer.RecognizerInfo.Culture.Name)

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        Write-Host ""
        Write-Host ("=== Voice input capture attempt " + $attempt + " of " + $MaxAttempts + " ===")
        Write-Host "Listening now..."

        $result = $recognizer.Recognize([TimeSpan]::FromSeconds($TimeoutSeconds))

        if ($null -eq $result) {
            Write-Host ("No speech was recognized on attempt " + $attempt + ".")
            Add-Diag ("Attempt " + $attempt + ": no speech recognized.")
            continue
        }

        $candidate = ($result.Text).Trim()
        $confidence = [double] $result.Confidence

        Write-Host ("Transcript candidate: " + $candidate)
        Write-Host ("Confidence: " + $confidence)

        Add-Diag ("Attempt " + $attempt + " transcript: " + $candidate)
        Add-Diag ("Attempt " + $attempt + " confidence: " + $confidence)

        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        if ($confidence -lt $MinConfidence) {
            Write-Host ("Rejected low-confidence transcript. Required >= " + $MinConfidence)
            Add-Diag ("Attempt " + $attempt + ": rejected low-confidence transcript.")
            continue
        }

        $acceptedTranscript = $candidate
        break
    }

    if ([string]::IsNullOrWhiteSpace($acceptedTranscript)) {
        Write-Host ""
        Write-Host ("Diagnostics: " + $diagPath)
        throw "No acceptable speech was recognized. Check Windows default input device, microphone privacy permission, microphone gain, and room noise."
    }

    Save-Transcript $acceptedTranscript
}
finally {
    if ($null -ne $recognizer) {
        $recognizer.Dispose()
    }
}
