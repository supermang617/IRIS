$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$analyzer = Join-Path $repoRoot "scripts\summarize_voice_interruption.ps1"
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("iris-voice-diagnostics-" + [Guid]::NewGuid().ToString("N"))
$fixture = Join-Path $testRoot "voice-events.jsonl"
$silentFixture = Join-Path $testRoot "silent.jsonl"
$intendedFixture = Join-Path $testRoot "intended.jsonl"
$staleRecordFixture = Join-Path $testRoot "stale-record.jsonl"

try {
    New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $records = @(
        [ordered]@{ session_id = "older"; timestamp_ms = $now - 1000; event = "speech_interruption_detected"; detail = "resolution_ms=999; request=1; transcript_chars=4" },
        [ordered]@{ session_id = "matrix"; timestamp_ms = $now; event = "speech_started"; detail = "run=2" },
        [ordered]@{ session_id = "matrix"; timestamp_ms = $now + 1; event = "speech_interruption_listen_start"; detail = "run=2; request=3" },
        [ordered]@{ session_id = "matrix"; timestamp_ms = $now + 2; event = "speech_interruption_vad_candidate"; detail = "run=2; request=3; capture_to_vad_ms=180; aec=false" },
        [ordered]@{ session_id = "matrix"; timestamp_ms = $now + 3; event = "speech_interruption_vad_pause"; detail = "run=2; request=3; capture_to_vad_ms=180; vad_to_pause_ms=22; paused=True" },
        [ordered]@{ session_id = "matrix"; timestamp_ms = $now + 4; event = "speech_interruption_detected"; detail = "resolution_ms=640; request=3; transcript_chars=4" }
    )
    $lines = $records | ForEach-Object { $_ | ConvertTo-Json -Compress }
    Set-Content -LiteralPath $fixture -Value $lines -Encoding utf8

    $summary = & $analyzer -Path $fixture -Label "speaker-60" -ExpectedInterruptions 1
    if (
        $summary.session_id -ne "matrix" -or
        $summary.label -ne "speaker-60" -or
        $summary.vad_candidates -ne 1 -or
        $summary.confirmed_interruptions -ne 1 -or
        $summary.unexpected_cancellations -ne 0 -or
        $summary.missed_expected_interruptions -ne 0 -or
        $summary.median_capture_to_vad_ms -ne 180 -or
        $summary.median_vad_to_pause_ms -ne 22 -or
        $summary.median_resolution_ms -ne 640 -or
        $summary.acoustic_echo_cancellation -ne "not-enabled"
    ) {
        throw "Voice interruption diagnostics summary was inaccurate."
    }

    Set-Content -LiteralPath $silentFixture -Value (
        [ordered]@{
            session_id = "silent"
            timestamp_ms = $now + 10
            event = "speech_interruption_fallback_cancelled"
            detail = "run=1; request=1; method=web-audio; aec=false"
        } | ConvertTo-Json -Compress
    ) -Encoding utf8
    $silentSummary = & $analyzer -Path $silentFixture -Label "speaker-60-silent" -ExpectedInterruptions 0

    $intendedRecords = foreach ($index in 1..4) {
        [ordered]@{
            session_id = "intended"
            timestamp_ms = $now + 20 + $index
            event = "speech_interruption_detected"
            detail = "resolution_ms=600; request=$index; transcript_chars=4"
        } | ConvertTo-Json -Compress
    }
    Set-Content -LiteralPath $intendedFixture -Value $intendedRecords -Encoding utf8
    $intendedSummary = & $analyzer -Path $intendedFixture -Label "speaker-60-intended" -ExpectedInterruptions 5
    if (
        $silentSummary.unexpected_cancellations -ne 1 -or
        $silentSummary.missed_expected_interruptions -ne 0 -or
        $intendedSummary.unexpected_cancellations -ne 0 -or
        $intendedSummary.missed_expected_interruptions -ne 1
    ) {
        throw "Separate interruption trial sessions did not expose compensating false-cancel and missed-interruption errors."
    }

    $staleRejected = $false
    (Get-Item -LiteralPath $fixture).LastWriteTimeUtc = [DateTime]::UtcNow.AddHours(-8)
    try {
        & $analyzer -Path $fixture -MaximumAgeMinutes 60 | Out-Null
    } catch {
        $staleRejected = $_.Exception.Message.Contains("older than 60 minutes")
    }
    if (-not $staleRejected) {
        throw "Voice interruption analyzer accepted stale evidence."
    }

    Set-Content -LiteralPath $staleRecordFixture -Value (
        [ordered]@{
            session_id = "stale-record"
            timestamp_ms = $now - [long][TimeSpan]::FromHours(8).TotalMilliseconds
            event = "speech_started"
            detail = "run=1"
        } | ConvertTo-Json -Compress
    ) -Encoding utf8
    $staleRecordRejected = $false
    try {
        & $analyzer -Path $staleRecordFixture -MaximumAgeMinutes 60 | Out-Null
    } catch {
        $staleRecordRejected = $_.Exception.Message.Contains(
            "event timestamps are older than 60 minutes"
        )
    }
    if (-not $staleRecordRejected) {
        throw "Voice interruption analyzer accepted stale event timestamps."
    }

    Set-Content -LiteralPath $staleRecordFixture -Value (
        [ordered]@{
            session_id = "invalid-record"
            timestamp_ms = "not-a-timestamp"
            event = "speech_started"
            detail = "run=1"
        } | ConvertTo-Json -Compress
    ) -Encoding utf8
    $invalidTimestampRejected = $false
    try {
        & $analyzer -Path $staleRecordFixture | Out-Null
    } catch {
        $invalidTimestampRejected = $_.Exception.Message.Contains("invalid timestamp_ms")
    }
    if (-not $invalidTimestampRejected) {
        throw "Voice interruption analyzer accepted an invalid event timestamp."
    }

    Write-Host "Voice interruption diagnostics tests passed."
} finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolved = [System.IO.Path]::GetFullPath($testRoot)
        $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        if (-not $resolved.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove voice diagnostics fixture outside temp: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
