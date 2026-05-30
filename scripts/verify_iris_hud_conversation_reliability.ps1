$ErrorActionPreference = "Stop"

Set-Location -Path "C:\Projects\IRIS"

Write-Host ""
Write-Host "=== Project Iris HUD conversation reliability verification ==="

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

function Invoke-CapturedNative {
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

function Assert-Contains {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Output,

        [Parameter(Mandatory = $true)]
        [string] $Needle,

        [Parameter(Mandatory = $true)]
        [string] $Failure
    )

    if (-not $Output.Contains($Needle)) {
        throw $Failure
    }
}

function Assert-NotContains {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Output,

        [Parameter(Mandatory = $true)]
        [string] $Needle,

        [Parameter(Mandatory = $true)]
        [string] $Failure
    )

    if ($Output.Contains($Needle)) {
        throw $Failure
    }
}

Invoke-CapturedNative "Cargo format" "cargo" @("fmt", "--all")
Invoke-CapturedNative "Cargo build" "cargo" @("build", "--workspace")
Invoke-CapturedNative "Cargo test" "cargo" @("test", "--workspace")
Invoke-CapturedNative "Xtask audit" "cargo" @("run", "-p", "xtask")

$output = Invoke-CapturedNative "Assistant output normalization" "cargo" @(
    "run", "-p", "iris-runtime", "--", "assistant-text-normalization-test"
)
Assert-Contains $output "Result: PASS" "Assistant output normalization did not pass."

$output = Invoke-CapturedNative "Deictic role test" "cargo" @(
    "run", "-p", "iris-runtime", "--", "deictic-role-test"
)
Assert-Contains $output "Result: PASS" "Deictic role test did not pass."

$output = Invoke-CapturedNative "HUD passed-praise submit test" "cargo" @(
    "run", "-p", "iris-runtime", "--", "hud-submit-test",
    "Okay that was the test. You passed! Congrats!!!"
)
Assert-Contains $output "I'm glad I passed" "HUD must have Iris take ownership of passing."
Assert-NotContains $output "I'm glad you passed" "HUD must not say the user passed when Iris passed."

$output = Invoke-CapturedNative "HUD combined praise submit test" "cargo" @(
    "run", "-p", "iris-runtime", "--", "hud-submit-test",
    "Awesome, you passed our test, Iris. I am proud of you."
)
Assert-Contains $output "I'm glad I passed" "HUD combined praise must preserve that Iris passed."
Assert-Contains $output "proud of me" "HUD combined praise must understand the user is proud of Iris."
Assert-NotContains $output "proud of yourself" "HUD must not redirect Iris praise back to the user."

$output = Invoke-CapturedNative "HUD profanity asterisk submit test" "cargo" @(
    "run", "-p", "iris-runtime", "--", "hud-submit-test",
    "can you say fuckin shit without using asterisks"
)
Assert-NotContains $output "f*ck" "Assistant output must not contain f*ck censor marker."
Assert-NotContains $output "f**k" "Assistant output must not contain f**k censor marker."
Assert-NotContains $output "sh*t" "Assistant output must not contain sh*t censor marker."

Invoke-CapturedNative "Current milestone diagnostics" "powershell" @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    "scripts\diagnose_iris_current_milestone.ps1"
)

Write-Host ""
Write-Host "PASS: HUD conversation reliability checkpoint passed."
