param(
    [string]$Path = "",
    [string]$Label = "",
    [int]$ExpectedInterruptions = -1,
    [ValidateRange(1, 1440)][int]$MaximumAgeMinutes = 240,
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"

if (-not $Path) {
    if (-not $env:LOCALAPPDATA) {
        throw "LOCALAPPDATA is unavailable; provide -Path explicitly."
    }
    $Path = Join-Path $env:LOCALAPPDATA "Iris\diagnostics\voice-events.jsonl"
}
$resolved = [System.IO.Path]::GetFullPath($Path)
if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
    throw "Fresh voice diagnostics are missing: $resolved"
}
$file = Get-Item -LiteralPath $resolved
if ($file.Length -eq 0) {
    throw "Voice diagnostics are empty: $resolved"
}
if ($file.LastWriteTimeUtc -lt [DateTime]::UtcNow.AddMinutes(-$MaximumAgeMinutes)) {
    throw "Voice diagnostics are older than $MaximumAgeMinutes minutes: $resolved"
}

$records = New-Object System.Collections.Generic.List[object]
$lineNumber = 0
$latest = $null
$latestTimestampMs = [long]::MinValue
foreach ($line in Get-Content -LiteralPath $resolved) {
    $lineNumber += 1
    if (-not $line.Trim()) {
        continue
    }
    try {
        $record = $line | ConvertFrom-Json
    } catch {
        throw "Invalid voice diagnostic JSON at line ${lineNumber}: $($_.Exception.Message)"
    }
    if (-not $record.session_id -or -not $record.event) {
        throw "Voice diagnostic line $lineNumber is missing session_id or event."
    }
    $record | Add-Member -NotePropertyName _line_number -NotePropertyValue $lineNumber -Force
    $timestampText = [string]$record.timestamp_ms
    if ($timestampText -notmatch "^[0-9]+$") {
        throw "Voice diagnostic line $lineNumber has an invalid timestamp_ms."
    }
    try {
        $recordTimestampMs = [long]::Parse(
            $timestampText,
            [System.Globalization.CultureInfo]::InvariantCulture
        )
    } catch {
        throw "Voice diagnostic line $lineNumber has an invalid timestamp_ms."
    }
    if ($recordTimestampMs -gt $latestTimestampMs) {
        $latestTimestampMs = $recordTimestampMs
        $latest = $record
    }
    $records.Add($record)
}
if ($records.Count -eq 0) {
    throw "Voice diagnostics contain no events: $resolved"
}
$eventCutoffMs = [DateTimeOffset]::UtcNow.AddMinutes(-$MaximumAgeMinutes).ToUnixTimeMilliseconds()
if ($latestTimestampMs -lt $eventCutoffMs) {
    throw "Voice diagnostic event timestamps are older than $MaximumAgeMinutes minutes: $resolved"
}

$sessionId = [string]$latest.session_id
$session = @($records | Where-Object { [string]$_.session_id -eq $sessionId })

function Get-EventCount {
    param([Parameter(Mandatory = $true)][string]$Name)
    return @($session | Where-Object { [string]$_.event -eq $Name }).Count
}

function Get-DeviceLabels {
    param([Parameter(Mandatory = $true)][string]$EventName)
    return @(
        $session |
            Where-Object { [string]$_.event -eq $EventName } |
            ForEach-Object {
                $detail = [string]$_.detail
                if ($detail.StartsWith("device=", [System.StringComparison]::Ordinal)) {
                    $label = $detail.Substring(7).Trim()
                    if ($label) {
                        $label
                    }
                }
            } |
            Select-Object -Unique
    )
}

function Get-DetailMetric {
    param(
        [Parameter(Mandatory = $true)][string]$EventName,
        [Parameter(Mandatory = $true)][string]$Metric,
        [string]$RequiredDetailPattern = ""
    )
    $values = New-Object System.Collections.Generic.List[double]
    foreach ($record in $session | Where-Object { [string]$_.event -eq $EventName }) {
        $detail = [string]$record.detail
        if ($RequiredDetailPattern -and $detail -notmatch $RequiredDetailPattern) {
            continue
        }
        $match = [regex]::Match($detail, "(?:^|;\s*)$([regex]::Escape($Metric))=(?<value>[0-9]+)")
        if ($match.Success) {
            $values.Add([double]$match.Groups["value"].Value)
        }
    }
    return @($values)
}

function Get-Median {
    param([double[]]$Values)
    if (-not $Values -or $Values.Count -eq 0) {
        return $null
    }
    $sorted = @($Values | Sort-Object)
    $middle = [int][Math]::Floor($sorted.Count / 2)
    if ($sorted.Count % 2 -eq 1) {
        return [Math]::Round($sorted[$middle], 1)
    }
    return [Math]::Round(($sorted[$middle - 1] + $sorted[$middle]) / 2, 1)
}

$confirmed = Get-EventCount -Name "speech_interruption_detected"
$fallback = Get-EventCount -Name "speech_interruption_fallback_cancelled"
$totalCancellations = $confirmed + $fallback
$unexpected = if ($ExpectedInterruptions -ge 0) {
    [Math]::Max(0, $totalCancellations - $ExpectedInterruptions)
} else {
    $null
}
$missed = if ($ExpectedInterruptions -ge 0) {
    [Math]::Max(0, $ExpectedInterruptions - $totalCancellations)
} else {
    $null
}
$terminalPlaybackEvents = @(
    "speech_playback_error",
    "speech_interruption_resume_error"
)
$terminalPlaybackRecords = @(
    $session |
        Where-Object { [string]$_.event -in $terminalPlaybackEvents }
)
$errors = @(
    $session |
        Where-Object {
            [string]$_.event -match "(?:error|unavailable)$" -and
            [string]$_.event -like "*interruption*" -and
            [string]$_.event -notin $terminalPlaybackEvents
        }
).Count + $terminalPlaybackRecords.Count
$successfulPauseRecords = @(
    $session |
        Where-Object {
            [string]$_.event -eq "speech_interruption_vad_pause" -and
            [string]$_.detail -match "(?:^|;\s*)paused=true(?:;|$)"
        }
)
$failedPauseRecords = @(
    $session |
        Where-Object {
            [string]$_.event -eq "speech_interruption_vad_pause" -and
            [string]$_.detail -notmatch "(?:^|;\s*)paused=true(?:;|$)"
        }
)
$successfulResumeRecords = @(
    $session |
        Where-Object {
            [string]$_.event -eq "speech_interruption_playback_resumed" -and
            [string]$_.detail -match "(?:^|;\s*)resumed=true(?:;|$)"
        }
)
$failedResumeRecords = @(
    $session |
        Where-Object {
            [string]$_.event -eq "speech_interruption_playback_resumed" -and
            [string]$_.detail -notmatch "(?:^|;\s*)resumed=true(?:;|$)"
        }
)
$resumeCompletionEvidence = 0
$resumesWithoutCompletion = 0
foreach ($resumeRecord in $successfulResumeRecords) {
    $runMatch = [regex]::Match([string]$resumeRecord.detail, "(?:^|;\s*)run=(?<value>[0-9]+)")
    if (-not $runMatch.Success) {
        $resumesWithoutCompletion += 1
        continue
    }
    $runId = $runMatch.Groups["value"].Value
    $completionRecord = @(
        $session |
            Where-Object {
                [int]$_._line_number -gt [int]$resumeRecord._line_number -and
                [string]$_.event -in @("speech_playback_finished", "speech_finished") -and
                [string]$_.detail -match "(?:^|;\s*)run=$([regex]::Escape($runId))(?:;|$)"
            } |
            Select-Object -First 1
    )
    $completionLine = if ($completionRecord.Count -gt 0) {
        [int]$completionRecord[0]._line_number
    } else {
        [int]::MaxValue
    }
    $terminalBeforeCompletion = @(
        $session |
            Where-Object {
                [int]$_._line_number -gt [int]$resumeRecord._line_number -and
                [int]$_._line_number -lt $completionLine -and
                [string]$_.event -in $terminalPlaybackEvents -and
                [string]$_.detail -match "(?:^|;\s*)run=$([regex]::Escape($runId))(?:;|$)"
            }
    ).Count -gt 0
    if ($completionRecord.Count -gt 0 -and -not $terminalBeforeCompletion) {
        $resumeCompletionEvidence += 1
    } else {
        $resumesWithoutCompletion += 1
    }
}
$errors += $failedPauseRecords.Count + $failedResumeRecords.Count + $resumesWithoutCompletion
$candidateDetails = @(
    $session |
        Where-Object { [string]$_.event -eq "speech_interruption_vad_candidate" } |
        ForEach-Object { [string]$_.detail }
)
$inputDevices = @(Get-DeviceLabels -EventName "audio_input_device")
$outputDevices = @(Get-DeviceLabels -EventName "audio_output_device")
$aecStatus = if ($candidateDetails.Count -gt 0 -and @($candidateDetails | Where-Object { $_ -notmatch "(?:^|;\s*)aec=false(?:;|$)" }).Count -eq 0) {
    "not-enabled"
} else {
    "not-proven"
}

$summary = [pscustomobject]@{
    label = if ($Label) { $Label } else { [System.IO.Path]::GetFileNameWithoutExtension($resolved) }
    path = $resolved
    session_id = $sessionId
    event_count = $session.Count
    input_devices = $inputDevices
    output_devices = $outputDevices
    speech_runs = Get-EventCount -Name "speech_started"
    interruption_listens = Get-EventCount -Name "speech_interruption_listen_start"
    vad_candidates = Get-EventCount -Name "speech_interruption_vad_candidate"
    playback_pauses = $successfulPauseRecords.Count
    pause_failures = $failedPauseRecords.Count
    rejected_resumes = $successfulResumeRecords.Count
    resume_failures = $failedResumeRecords.Count
    resume_completion_evidence = $resumeCompletionEvidence
    resumes_without_completion = $resumesWithoutCompletion
    playback_terminal_errors = $terminalPlaybackRecords.Count
    pause_suppressed = Get-EventCount -Name "speech_interruption_pause_suppressed"
    confirmed_interruptions = $confirmed
    fallback_cancellations = $fallback
    total_cancellations = $totalCancellations
    expected_interruptions = if ($ExpectedInterruptions -ge 0) { $ExpectedInterruptions } else { $null }
    missed_expected_interruptions = $missed
    unexpected_cancellations = $unexpected
    interruption_errors = $errors
    median_capture_to_vad_ms = Get-Median -Values (Get-DetailMetric -EventName "speech_interruption_vad_candidate" -Metric "capture_to_vad_ms")
    median_vad_to_pause_ms = Get-Median -Values (Get-DetailMetric -EventName "speech_interruption_vad_pause" -Metric "vad_to_pause_ms" -RequiredDetailPattern "(?:^|;\s*)paused=true(?:;|$)")
    median_resolution_ms = Get-Median -Values (Get-DetailMetric -EventName "speech_interruption_detected" -Metric "resolution_ms")
    acoustic_echo_cancellation = $aecStatus
}

if ($AsJson) {
    $summary | ConvertTo-Json -Depth 3
} else {
    $summary
}
