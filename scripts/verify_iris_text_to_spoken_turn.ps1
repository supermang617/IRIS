param(
    [string] $Prompt = "Iris, your voice sounds awesome.",
    [string] $SecondPrompt = "Okay that was the test. You passed! Congrats!!!",
    [switch] $NoPlay
)

$ErrorActionPreference = "Stop"

Set-Location -Path "C:\Projects\IRIS"

New-Item -ItemType Directory -Force ".iris-dev\voice" | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$report = ".iris-dev\voice\iris-text-to-spoken-turn-$timestamp.txt"

function Write-ReportLine {
    param([string] $Text)

    Add-Content -Encoding UTF8 -Path $report -Value $Text
}

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
    Write-ReportLine ""
    Write-ReportLine "=== $Name ==="

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
            Write-ReportLine $combined
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

function Assert-Contains {
    param(
        [string] $Output,
        [string] $Needle,
        [string] $Failure
    )

    if (-not $Output.Contains($Needle)) {
        throw $Failure
    }
}

function Assert-NotContains {
    param(
        [string] $Output,
        [string] $Needle,
        [string] $Failure
    )

    if ($Output.Contains($Needle)) {
        throw $Failure
    }
}

function Invoke-TextToSpokenTurn {
    param(
        [string] $Name,
        [string] $TurnPrompt,
        [string[]] $MustContain,
        [string[]] $MustNotContain
    )

    $args = @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        "scripts\test_iris_dev_hud_speech_boundary.ps1",
        "-Prompt",
        $TurnPrompt
    )

    if ($NoPlay) {
        $args += "-NoPlay"
    }

    $output = Invoke-NativeCapture `
        -Name $Name `
        -CommandName "powershell" `
        -Arguments $args

    Assert-Contains $output "Result: PASS" "$Name did not pass."
    Assert-Contains $output "=== Approved speech text ===" "$Name did not expose approved speech text."

    foreach ($needle in $MustContain) {
        Assert-Contains $output $needle "$Name missing expected text: $needle"
    }

    foreach ($needle in $MustNotContain) {
        Assert-NotContains $output $needle "$Name contained forbidden text: $needle"
    }
}

Write-Host ""
Write-Host "=== Project Iris text-to-spoken turn milestone ==="
Write-Host "Prompt 1: $Prompt"
Write-Host "Prompt 2: $SecondPrompt"
Write-Host "NoPlay: $NoPlay"

Write-ReportLine "Project Iris text-to-spoken turn milestone"
Write-ReportLine "Timestamp: $timestamp"
Write-ReportLine "Prompt 1: $Prompt"
Write-ReportLine "Prompt 2: $SecondPrompt"
Write-ReportLine "NoPlay: $NoPlay"

Invoke-TextToSpokenTurn `
    -Name "Text prompt to spoken voice role turn" `
    -TurnPrompt $Prompt `
    -MustContain @("my voice") `
    -MustNotContain @("your voice sounds good", "f*ck", "f**k", "sh*t")

Invoke-TextToSpokenTurn `
    -Name "Text prompt to spoken passed-role turn" `
    -TurnPrompt $SecondPrompt `
    -MustContain @("I passed") `
    -MustNotContain @("you passed", "proud of yourself", "f*ck", "f**k", "sh*t")

Write-Host ""
Write-Host "PASS: Iris text-to-spoken turn milestone passed"
Write-Host "Report: $report"

Write-ReportLine ""
Write-ReportLine "PASS: Iris text-to-spoken turn milestone passed"
