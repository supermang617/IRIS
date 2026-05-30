[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $Path,

    [int] $Seconds = 6
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path $Path)) {
    throw "WAV file not found: $Path"
}

$resolved = (Resolve-Path $Path).Path
$wav = Get-Item $resolved

if ($wav.Length -lt 1000) {
    throw "WAV file is unexpectedly small: $($wav.Length) bytes"
}

$player = New-Object System.Media.SoundPlayer $resolved
$player.Load()
$player.Play()

Start-Sleep -Seconds $Seconds

try {
    $player.Stop()
} catch {
}

Write-Host "Playback: bounded"
Write-Host "WAV: $resolved"
Write-Host "Result: PASS"
