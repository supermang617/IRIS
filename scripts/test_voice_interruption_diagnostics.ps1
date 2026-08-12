$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$analyzer = Join-Path $repoRoot "scripts\summarize_voice_interruption.ps1"
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("iris-voice-diagnostics-" + [Guid]::NewGuid().ToString("N"))
$fixture = Join-Path $testRoot "voice-events.jsonl"
$silentFixture = Join-Path $testRoot "silent.jsonl"
$intendedFixture = Join-Path $testRoot "intended.jsonl"
$resumeFixture = Join-Path $testRoot "resume.jsonl"
$interruptedAfterResumeFixture = Join-Path $testRoot "interrupted-after-resume.jsonl"
$detectedWithoutTerminalFixture = Join-Path $testRoot "detected-without-terminal.jsonl"
$nativeCancelErrorFixture = Join-Path $testRoot "native-cancel-error.jsonl"
$unrelatedCancellationFixture = Join-Path $testRoot "unrelated-cancellation.jsonl"
$failedControlFixture = Join-Path $testRoot "failed-control.jsonl"
$missingCompletionFixture = Join-Path $testRoot "missing-completion.jsonl"
$terminalPlaybackFixture = Join-Path $testRoot "terminal-playback.jsonl"
$staleRecordFixture = Join-Path $testRoot "stale-record.jsonl"

try {
    New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $records = @(
        [ordered]@{ session_id = "older"; timestamp_ms = $now - 1000; event = "speech_interruption_detected"; detail = "resolution_ms=999; request=1; transcript_chars=4" },
        [ordered]@{ session_id = "matrix"; timestamp_ms = $now; event = "audio_input_device"; detail = "device=RODE NT-USB Mini" },
        [ordered]@{ session_id = "matrix"; timestamp_ms = $now + 1; event = "audio_output_device"; detail = "device=Speakers (Surface)" },
        [ordered]@{ session_id = "matrix"; timestamp_ms = $now + 2; event = "speech_started"; detail = "run=2" },
        [ordered]@{ session_id = "matrix"; timestamp_ms = $now + 3; event = "speech_interruption_listen_start"; detail = "run=2; request=3" },
        [ordered]@{ session_id = "matrix"; timestamp_ms = $now + 4; event = "speech_interruption_vad_candidate"; detail = "run=2; request=3; capture_to_vad_ms=180; aec=false" },
        [ordered]@{ session_id = "matrix"; timestamp_ms = $now + 5; event = "speech_interruption_vad_pause"; detail = "run=2; request=3; capture_to_vad_ms=180; vad_to_pause_ms=22; paused=True" },
        [ordered]@{ session_id = "matrix"; timestamp_ms = $now + 6; event = "speech_interruption_detected"; detail = "resolution_ms=640; request=3; transcript_chars=4" }
    )
    $lines = $records | ForEach-Object { $_ | ConvertTo-Json -Compress }
    Set-Content -LiteralPath $fixture -Value $lines -Encoding utf8

    $summary = & $analyzer -Path $fixture -Label "speaker-60" -ExpectedInterruptions 1
    if (
        $summary.session_id -ne "matrix" -or
        $summary.label -ne "speaker-60" -or
        @($summary.input_devices).Count -ne 1 -or
        @($summary.input_devices)[0] -ne "RODE NT-USB Mini" -or
        @($summary.output_devices).Count -ne 1 -or
        @($summary.output_devices)[0] -ne "Speakers (Surface)" -or
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

    $resumeRecords = @(
        [ordered]@{ session_id = "resume"; timestamp_ms = $now + 30; event = "speech_started"; detail = "run=5" },
        [ordered]@{ session_id = "resume"; timestamp_ms = $now + 31; event = "speech_interruption_vad_pause"; detail = "run=5; request=8; vad_to_pause_ms=25; paused=True" },
        [ordered]@{ session_id = "resume"; timestamp_ms = $now + 32; event = "speech_interruption_playback_resumed"; detail = "run=5; request=8; paused=True; resumed=True" },
        [ordered]@{ session_id = "resume"; timestamp_ms = $now + 33; event = "speech_playback_finished"; detail = "run=5" }
    )
    $resumeRecords | ForEach-Object { $_ | ConvertTo-Json -Compress } |
        Set-Content -LiteralPath $resumeFixture -Encoding utf8
    $resumeSummary = & $analyzer -Path $resumeFixture -ExpectedInterruptions 0
    if (
        $resumeSummary.playback_pauses -ne 1 -or
        $resumeSummary.pause_failures -ne 0 -or
        $resumeSummary.rejected_resumes -ne 1 -or
        $resumeSummary.resume_failures -ne 0 -or
        $resumeSummary.resume_completion_evidence -ne 1 -or
        $resumeSummary.resumes_without_completion -ne 0 -or
        $resumeSummary.interruption_errors -ne 0 -or
        $resumeSummary.median_vad_to_pause_ms -ne 25
    ) {
        throw "Voice interruption analyzer did not prove a successful pause, resume, and playback completion."
    }

    $interruptedAfterResumeRecords = @(
        [ordered]@{ session_id = "interrupted-after-resume"; timestamp_ms = $now + 34; event = "speech_started"; detail = "run=9" },
        [ordered]@{ session_id = "interrupted-after-resume"; timestamp_ms = $now + 35; event = "speech_interruption_vad_pause"; detail = "run=9; request=12; vad_to_pause_ms=18; paused=True" },
        [ordered]@{ session_id = "interrupted-after-resume"; timestamp_ms = $now + 36; event = "speech_interruption_playback_resumed"; detail = "run=9; request=12; paused=True; resumed=True" },
        [ordered]@{ session_id = "interrupted-after-resume"; timestamp_ms = $now + 37; event = "speech_interruption_listen_start"; detail = "run=9; request=13" },
        [ordered]@{ session_id = "interrupted-after-resume"; timestamp_ms = $now + 38; event = "speech_interruption_detected"; detail = "resolution_ms=510; request=13; transcript_chars=4" },
        [ordered]@{ session_id = "interrupted-after-resume"; timestamp_ms = $now + 39; event = "speech_cancelled"; detail = "run=9; chunks=2" }
    )
    $interruptedAfterResumeRecords | ForEach-Object { $_ | ConvertTo-Json -Compress } |
        Set-Content -LiteralPath $interruptedAfterResumeFixture -Encoding utf8
    $interruptedAfterResumeSummary = & $analyzer -Path $interruptedAfterResumeFixture -ExpectedInterruptions 1
    if (
        $interruptedAfterResumeSummary.confirmed_interruptions -ne 1 -or
        $interruptedAfterResumeSummary.total_cancellations -ne 1 -or
        $interruptedAfterResumeSummary.resume_completion_evidence -ne 1 -or
        $interruptedAfterResumeSummary.resumes_without_completion -ne 0 -or
        $interruptedAfterResumeSummary.interruption_errors -ne 0
    ) {
        throw "Voice interruption analyzer rejected a resumed run that ended in a later confirmed interruption."
    }

    $detectedWithoutTerminalRecords = @(
        [ordered]@{ session_id = "detected-without-terminal"; timestamp_ms = $now + 40; event = "speech_started"; detail = "run=10" },
        [ordered]@{ session_id = "detected-without-terminal"; timestamp_ms = $now + 41; event = "speech_interruption_vad_pause"; detail = "run=10; request=14; vad_to_pause_ms=17; paused=True" },
        [ordered]@{ session_id = "detected-without-terminal"; timestamp_ms = $now + 42; event = "speech_interruption_playback_resumed"; detail = "run=10; request=14; paused=True; resumed=True" },
        [ordered]@{ session_id = "detected-without-terminal"; timestamp_ms = $now + 43; event = "speech_interruption_listen_start"; detail = "run=10; request=15" },
        [ordered]@{ session_id = "detected-without-terminal"; timestamp_ms = $now + 44; event = "speech_interruption_detected"; detail = "resolution_ms=490; request=15; transcript_chars=4" }
    )
    $detectedWithoutTerminalRecords | ForEach-Object { $_ | ConvertTo-Json -Compress } |
        Set-Content -LiteralPath $detectedWithoutTerminalFixture -Encoding utf8
    $detectedWithoutTerminalSummary = & $analyzer -Path $detectedWithoutTerminalFixture -ExpectedInterruptions 1
    if (
        $detectedWithoutTerminalSummary.confirmed_interruptions -ne 1 -or
        $detectedWithoutTerminalSummary.resume_completion_evidence -ne 0 -or
        $detectedWithoutTerminalSummary.resumes_without_completion -ne 1 -or
        $detectedWithoutTerminalSummary.interruption_errors -ne 1
    ) {
        throw "Voice interruption analyzer accepted detection without a later cancellation terminal."
    }

    $nativeCancelErrorRecords = @(
        [ordered]@{ session_id = "native-cancel-error"; timestamp_ms = $now + 45; event = "speech_started"; detail = "run=11" },
        [ordered]@{ session_id = "native-cancel-error"; timestamp_ms = $now + 46; event = "speech_interruption_vad_pause"; detail = "run=11; request=16; vad_to_pause_ms=16; paused=True" },
        [ordered]@{ session_id = "native-cancel-error"; timestamp_ms = $now + 47; event = "speech_interruption_playback_resumed"; detail = "run=11; request=16; paused=True; resumed=True" },
        [ordered]@{ session_id = "native-cancel-error"; timestamp_ms = $now + 48; event = "speech_interruption_listen_start"; detail = "run=11; request=17" },
        [ordered]@{ session_id = "native-cancel-error"; timestamp_ms = $now + 49; event = "speech_interruption_detected"; detail = "resolution_ms=505; request=17; transcript_chars=4" },
        [ordered]@{ session_id = "native-cancel-error"; timestamp_ms = $now + 50; event = "speech_native_cancel_error"; detail = "run=11; output device cancellation failed" },
        [ordered]@{ session_id = "native-cancel-error"; timestamp_ms = $now + 51; event = "speech_cancelled"; detail = "run=11; chunks=2" }
    )
    $nativeCancelErrorRecords | ForEach-Object { $_ | ConvertTo-Json -Compress } |
        Set-Content -LiteralPath $nativeCancelErrorFixture -Encoding utf8
    $nativeCancelErrorSummary = & $analyzer -Path $nativeCancelErrorFixture -ExpectedInterruptions 1
    if (
        $nativeCancelErrorSummary.confirmed_interruptions -ne 1 -or
        $nativeCancelErrorSummary.resume_completion_evidence -ne 0 -or
        $nativeCancelErrorSummary.resumes_without_completion -ne 1 -or
        $nativeCancelErrorSummary.playback_terminal_errors -ne 1 -or
        $nativeCancelErrorSummary.interruption_errors -lt 2
    ) {
        throw "Voice interruption analyzer did not fail a native playback cancellation error."
    }

    $unrelatedCancellationRecords = @(
        [ordered]@{ session_id = "unrelated-cancellation"; timestamp_ms = $now + 40; event = "speech_started"; detail = "run=10" },
        [ordered]@{ session_id = "unrelated-cancellation"; timestamp_ms = $now + 41; event = "speech_interruption_vad_pause"; detail = "run=10; request=14; vad_to_pause_ms=17; paused=True" },
        [ordered]@{ session_id = "unrelated-cancellation"; timestamp_ms = $now + 42; event = "speech_interruption_playback_resumed"; detail = "run=10; request=14; paused=True; resumed=True" },
        [ordered]@{ session_id = "unrelated-cancellation"; timestamp_ms = $now + 43; event = "speech_cancelled"; detail = "run=10; chunks=2" }
    )
    $unrelatedCancellationRecords | ForEach-Object { $_ | ConvertTo-Json -Compress } |
        Set-Content -LiteralPath $unrelatedCancellationFixture -Encoding utf8
    $unrelatedCancellationSummary = & $analyzer -Path $unrelatedCancellationFixture -ExpectedInterruptions 0
    if (
        $unrelatedCancellationSummary.confirmed_interruptions -ne 0 -or
        $unrelatedCancellationSummary.resume_completion_evidence -ne 0 -or
        $unrelatedCancellationSummary.resumes_without_completion -ne 1 -or
        $unrelatedCancellationSummary.interruption_errors -ne 1
    ) {
        throw "Voice interruption analyzer accepted an unrelated cancellation as resume completion."
    }

    $failedControlRecords = @(
        [ordered]@{ session_id = "failed-control"; timestamp_ms = $now + 40; event = "speech_started"; detail = "run=6" },
        [ordered]@{ session_id = "failed-control"; timestamp_ms = $now + 41; event = "speech_interruption_vad_pause"; detail = "run=6; request=9; vad_to_pause_ms=10; paused=False" },
        [ordered]@{ session_id = "failed-control"; timestamp_ms = $now + 42; event = "speech_interruption_playback_resumed"; detail = "run=6; request=9; paused=False; resumed=False" },
        [ordered]@{ session_id = "failed-control"; timestamp_ms = $now + 43; event = "speech_playback_finished"; detail = "run=6" }
    )
    $failedControlRecords | ForEach-Object { $_ | ConvertTo-Json -Compress } |
        Set-Content -LiteralPath $failedControlFixture -Encoding utf8
    $failedControlSummary = & $analyzer -Path $failedControlFixture -ExpectedInterruptions 0
    if (
        $failedControlSummary.playback_pauses -ne 0 -or
        $failedControlSummary.pause_failures -ne 1 -or
        $failedControlSummary.rejected_resumes -ne 0 -or
        $failedControlSummary.resume_failures -ne 1 -or
        $failedControlSummary.interruption_errors -ne 2 -or
        $null -ne $failedControlSummary.median_vad_to_pause_ms
    ) {
        throw "Voice interruption analyzer counted failed pause/resume controls as successful."
    }

    $missingCompletionRecords = @(
        [ordered]@{ session_id = "missing-completion"; timestamp_ms = $now + 50; event = "speech_started"; detail = "run=7" },
        [ordered]@{ session_id = "missing-completion"; timestamp_ms = $now + 51; event = "speech_interruption_vad_pause"; detail = "run=7; request=10; vad_to_pause_ms=20; paused=True" },
        [ordered]@{ session_id = "missing-completion"; timestamp_ms = $now + 52; event = "speech_interruption_playback_resumed"; detail = "run=7; request=10; paused=True; resumed=True" }
    )
    $missingCompletionRecords | ForEach-Object { $_ | ConvertTo-Json -Compress } |
        Set-Content -LiteralPath $missingCompletionFixture -Encoding utf8
    $missingCompletionSummary = & $analyzer -Path $missingCompletionFixture -ExpectedInterruptions 0
    if (
        $missingCompletionSummary.resume_completion_evidence -ne 0 -or
        $missingCompletionSummary.resumes_without_completion -ne 1 -or
        $missingCompletionSummary.interruption_errors -ne 1
    ) {
        throw "Voice interruption analyzer accepted a resume without later playback completion."
    }

    $terminalPlaybackRecords = @(
        [ordered]@{ session_id = "terminal-playback"; timestamp_ms = $now + 60; event = "speech_started"; detail = "run=8" },
        [ordered]@{ session_id = "terminal-playback"; timestamp_ms = $now + 61; event = "speech_interruption_vad_pause"; detail = "run=8; request=11; vad_to_pause_ms=15; paused=True" },
        [ordered]@{ session_id = "terminal-playback"; timestamp_ms = $now + 62; event = "speech_interruption_playback_resumed"; detail = "run=8; request=11; paused=True; resumed=True" },
        [ordered]@{ session_id = "terminal-playback"; timestamp_ms = $now + 63; event = "speech_playback_error"; detail = "run=8; output device failed" },
        [ordered]@{ session_id = "terminal-playback"; timestamp_ms = $now + 64; event = "speech_playback_finished"; detail = "run=8" }
    )
    $terminalPlaybackRecords | ForEach-Object { $_ | ConvertTo-Json -Compress } |
        Set-Content -LiteralPath $terminalPlaybackFixture -Encoding utf8
    $terminalPlaybackSummary = & $analyzer -Path $terminalPlaybackFixture -ExpectedInterruptions 0
    if (
        $terminalPlaybackSummary.resume_completion_evidence -ne 0 -or
        $terminalPlaybackSummary.resumes_without_completion -ne 1 -or
        $terminalPlaybackSummary.playback_terminal_errors -ne 1 -or
        $terminalPlaybackSummary.interruption_errors -lt 2
    ) {
        throw "Voice interruption analyzer accepted playback completion after a terminal error."
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
