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

function Get-DetailMetric {
    param(
        [Parameter(Mandatory = $true)][string]$EventName,
        [Parameter(Mandatory = $true)][string]$Metric
    )
    $values = New-Object System.Collections.Generic.List[double]
    foreach ($record in $session | Where-Object { [string]$_.event -eq $EventName }) {
        $match = [regex]::Match([string]$record.detail, "(?:^|;\s*)$([regex]::Escape($Metric))=(?<value>[0-9]+)")
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
$errors = @(
    $session |
        Where-Object {
            [string]$_.event -match "(?:error|unavailable)$" -and
            [string]$_.event -like "*interruption*"
        }
).Count
$candidateDetails = @(
    $session |
        Where-Object { [string]$_.event -eq "speech_interruption_vad_candidate" } |
        ForEach-Object { [string]$_.detail }
)
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
    speech_runs = Get-EventCount -Name "speech_started"
    interruption_listens = Get-EventCount -Name "speech_interruption_listen_start"
    vad_candidates = Get-EventCount -Name "speech_interruption_vad_candidate"
    playback_pauses = Get-EventCount -Name "speech_interruption_vad_pause"
    rejected_resumes = Get-EventCount -Name "speech_interruption_playback_resumed"
    pause_suppressed = Get-EventCount -Name "speech_interruption_pause_suppressed"
    confirmed_interruptions = $confirmed
    fallback_cancellations = $fallback
    total_cancellations = $totalCancellations
    expected_interruptions = if ($ExpectedInterruptions -ge 0) { $ExpectedInterruptions } else { $null }
    missed_expected_interruptions = $missed
    unexpected_cancellations = $unexpected
    interruption_errors = $errors
    median_capture_to_vad_ms = Get-Median -Values (Get-DetailMetric -EventName "speech_interruption_vad_candidate" -Metric "capture_to_vad_ms")
    median_vad_to_pause_ms = Get-Median -Values (Get-DetailMetric -EventName "speech_interruption_vad_pause" -Metric "vad_to_pause_ms")
    median_resolution_ms = Get-Median -Values (Get-DetailMetric -EventName "speech_interruption_detected" -Metric "resolution_ms")
    acoustic_echo_cancellation = $aecStatus
}

if ($AsJson) {
    $summary | ConvertTo-Json -Depth 3
} else {
    $summary
}
