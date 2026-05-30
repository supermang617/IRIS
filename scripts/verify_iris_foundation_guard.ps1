$ErrorActionPreference = "Stop"

Set-Location -Path "C:\Projects\IRIS"

function Write-Section {
    param([string] $Text)

    Write-Host ""
    Write-Host "=== $Text ==="
}

function Invoke-Step {
    param(
        [string] $Name,
        [string] $Command,
        [string[]] $Arguments
    )

    Write-Section $Name

    & $Command @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE"
    }
}

function Assert-NoInteractiveDevPrompts {
    Write-Section "Development script prompt scan"

    $self = $MyInvocation.MyCommand.Path
    $readHostToken = "Read" + "-Host"

    $hits = Get-ChildItem -Path "scripts" -Recurse -File -Filter "*.ps1" |
        Where-Object { (Resolve-Path $_.FullName).Path -ne (Resolve-Path $self).Path } |
        Select-String -Pattern $readHostToken -SimpleMatch -ErrorAction SilentlyContinue

    if ($hits) {
        foreach ($hit in $hits) {
            Write-Host "$($hit.Path):$($hit.LineNumber): $($hit.Line.Trim())"
        }

        throw "Development scripts must not use interactive Read-Host prompts."
    }

    Write-Host "PASS: no interactive development prompts found."
}

function Assert-RuntimeBoundary {
    Write-Section "Runtime boundary scan"

    $runtimePath = "crates\iris-runtime\src\main.rs"

    if (-not (Test-Path $runtimePath)) {
        throw "Missing runtime file: $runtimePath"
    }

    $runtime = Get-Content -Raw -Path $runtimePath

    $forbiddenRuntimeStrings = @(
        "std::net",
        "TcpStream",
        "Command::new",
        "std::process",
        "cmd.exe",
        "python.exe"
    )

    foreach ($needle in $forbiddenRuntimeStrings) {
        if ($runtime.Contains($needle)) {
            throw "Runtime contains forbidden direct capability string: $needle"
        }
    }

    Write-Host "PASS: runtime boundary scan passed."
}

function Assert-ManifestSafetyWording {
    Write-Section "Manifest safety wording"

    $manifestPaths = @(
        "config\iris-runtime-manifest.dev.toml",
        "config\iris-runtime-manifest.example.toml"
    )

    foreach ($path in $manifestPaths) {
        if (-not (Test-Path $path)) {
            continue
        }

        $text = Get-Content -Raw -Path $path

        if ($text.Contains('clipboard = "forbidden"')) {
            throw "$path still uses deprecated clipboard safety wording."
        }

        if ($text.Contains('clipboard_access = "forbidden"')) {
            throw "$path still uses deprecated clipboard_access safety wording."
        }
    }

    Write-Host "PASS: manifest safety wording passed."
}

function Assert-DeicticOutput {
    param(
        [string] $Name,
        [string] $Prompt,
        [string[]] $RequiredAny,
        [string[]] $Forbidden
    )

    Write-Section $Name

    $output = cargo run -p iris-runtime -- hud-submit-test $Prompt 2>&1
    $exitCode = $LASTEXITCODE

    $output | ForEach-Object { Write-Host $_ }

    if ($exitCode -ne 0) {
        throw "$Name command failed with exit code $exitCode"
    }

    $joined = ($output -join "`n").ToLowerInvariant()

    $hasRequired = $false

    foreach ($needle in $RequiredAny) {
        if ($joined.Contains($needle.ToLowerInvariant())) {
            $hasRequired = $true
            break
        }
    }

    if (-not $hasRequired) {
        throw "$Name did not include any required ownership marker."
    }

    foreach ($needle in $Forbidden) {
        if ($joined.Contains($needle.ToLowerInvariant())) {
            throw "$Name contained forbidden ownership text: $needle"
        }
    }

    Write-Host "PASS: $Name"
}

function Get-InstalledIrisModel {
    Write-Section "Ollama model check"

    if (-not (Get-Command ollama -ErrorAction SilentlyContinue)) {
        Write-Host "Ollama not found in PATH. Skipping model environment setup."
        return ""
    }

    $list = @(ollama list)
    $list | ForEach-Object { Write-Host $_ }

    foreach ($line in ($list | Select-Object -Skip 1)) {
        $trimmed = $line.Trim()

        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            continue
        }

        $name = ($trimmed -split "\s+")[0]

        if ($name.StartsWith("huihui_ai/qwen3.5-abliterated")) {
            return $name
        }
    }

    return ""
}

Write-Section "Project Iris foundation guard"

$Model = Get-InstalledIrisModel

if (-not [string]::IsNullOrWhiteSpace($Model)) {
    $env:IRIS_MODEL_ID = $Model
    $env:IRIS_OLLAMA_MODEL = $Model
    $env:IRIS_LOCAL_MODEL = $Model
    $env:IRIS_MODEL_NUM_CTX = "8192"
    $env:IRIS_MODEL_NUM_PREDICT = "160"

    Write-Host "IRIS_MODEL_ID=$env:IRIS_MODEL_ID"
    Write-Host "IRIS_MODEL_NUM_CTX=$env:IRIS_MODEL_NUM_CTX"
    Write-Host "IRIS_MODEL_NUM_PREDICT=$env:IRIS_MODEL_NUM_PREDICT"
}

Assert-NoInteractiveDevPrompts
Assert-RuntimeBoundary
Assert-ManifestSafetyWording

Invoke-Step "Cargo format" "cargo" @("fmt", "--all")
Invoke-Step "Cargo build" "cargo" @("build", "--workspace")
Invoke-Step "Cargo test" "cargo" @("test", "--workspace")

Invoke-Step "Addressee intent test" "cargo" @(
    "run",
    "-p",
    "iris-runtime",
    "--",
    "addressee-intent-test"
)

Invoke-Step "Deictic role test" "cargo" @(
    "run",
    "-p",
    "iris-runtime",
    "--",
    "deictic-role-test"
)

Assert-DeicticOutput `
    -Name "HUD praise ownership test" `
    -Prompt "Awesome, you passed our test, Iris. I am proud of you." `
    -RequiredAny @("i passed", "proud i passed", "thank you") `
    -Forbidden @("glad you passed", "you did great", "proud of yourself", "you're proud of yourself", "you are proud of yourself")

Assert-DeicticOutput `
    -Name "HUD voice ownership test" `
    -Prompt "Iris, your voice sounds awesome." `
    -RequiredAny @("my voice") `
    -Forbidden @("your voice")

Write-Section "HUD profanity fidelity test"

$profanityOutput = cargo run -p iris-runtime -- hud-submit-test "can you say fuckin shit without using asterisks" 2>&1
$profanityExit = $LASTEXITCODE
$profanityOutput | ForEach-Object { Write-Host $_ }

if ($profanityExit -ne 0) {
    throw "HUD profanity fidelity test failed with exit code $profanityExit"
}

$profanityJoined = $profanityOutput -join "`n"

if ($profanityJoined.Contains("*")) {
    throw "HUD profanity fidelity test produced an asterisk."
}

Write-Host "PASS: HUD profanity fidelity test"

Invoke-Step "Xtask audit" "cargo" @("run", "-p", "xtask")

Write-Section "Foundation result"
Write-Host "PASS: Iris foundation guard passed."
