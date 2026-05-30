param(
    [string] $ModelPrefix = "huihui_ai/qwen3.5-abliterated",
    [int] $NumCtx = 8192,
    [int] $NumPredict = 160
)

$ErrorActionPreference = "Stop"
Set-Location -Path "C:\Projects\IRIS"

function Write-Section {
    param([string] $Text)
    Write-Host ""
    Write-Host "=== $Text ==="
}

function Invoke-IrisNative {
    param(
        [string] $Name,
        [string] $FilePath,
        [string[]] $Arguments
    )

    Write-Section $Name

    $base = Join-Path $env:TEMP ("iris-native-" + [guid]::NewGuid().ToString())
    $stdout = "$base.out"
    $stderr = "$base.err"

    try {
        $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr

        if (Test-Path $stdout) {
            Get-Content -Path $stdout | ForEach-Object { Write-Host $_ }
        }

        if (Test-Path $stderr) {
            Get-Content -Path $stderr | ForEach-Object { Write-Host $_ }
        }

        if ($process.ExitCode -ne 0) {
            throw "$Name failed with exit code $($process.ExitCode)"
        }
    } finally {
        Remove-Item -Force -ErrorAction SilentlyContinue $stdout, $stderr
    }
}

function Get-InstalledIrisModel {
    param([string] $Prefix)

    Write-Section "Ollama model check"

    if (-not (Get-Command ollama -ErrorAction SilentlyContinue)) {
        Write-Host "Ollama not found. Skipping model environment setup."
        return ""
    }

    $list = @(ollama list)
    $list | ForEach-Object { Write-Host $_ }

    foreach ($line in ($list | Select-Object -Skip 1)) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }

        $name = ($trimmed -split "\s+")[0]
        if ($name.StartsWith($Prefix)) { return $name }
    }

    Write-Host "No installed model found for prefix. Continuing because foundation guard is deterministic."
    return ""
}

function Assert-NoInteractiveDevPrompts {
    Write-Section "Development script prompt scan"

    $token = "Read" + "-Host"

    $hits = Get-ChildItem -Path "scripts" -Recurse -File -Filter "*.ps1" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin @("verify_iris_foundation_guard.ps1", "verify_iris_voice_text_milestone.ps1") } |
        Select-String -Pattern $token -SimpleMatch -ErrorAction SilentlyContinue

    if ($hits) {
        foreach ($hit in $hits) {
            Write-Host "$($hit.Path):$($hit.LineNumber): $($hit.Line.Trim())"
        }
        throw "Development scripts must not use interactive prompts."
    }

    Write-Host "PASS: no interactive development prompts found."
}

function Assert-RuntimeBoundary {
    Write-Section "Runtime safety boundary scan"

    $runtimeRoot = "crates\iris-runtime\src"
    if (-not (Test-Path $runtimeRoot)) { throw "Missing runtime source root: $runtimeRoot" }

    $forbidden = @(
        "std::net",
        "TcpStream",
        "std::process::Command",
        "process::Command",
        "Command::new",
        "cmd.exe",
        "python.exe"
    )

    $files = Get-ChildItem -Path $runtimeRoot -Recurse -File -Filter "*.rs"
    $hits = @()

    foreach ($file in $files) {
        $text = Get-Content -Raw -Path $file.FullName

        foreach ($needle in $forbidden) {
            if ($text.Contains($needle)) {
                $hits += "$($file.FullName): forbidden runtime capability: $needle"
            }
        }
    }

    if ($hits.Count -gt 0) {
        $hits | ForEach-Object { Write-Host $_ }
        throw "Runtime safety boundary failed."
    }

    Write-Host "PASS: runtime safety boundary scan passed."
}

function Assert-ManifestSafetyWording {
    Write-Section "Manifest safety wording"

    foreach ($path in @("config\iris-runtime-manifest.dev.toml", "config\iris-runtime-manifest.example.toml")) {
        if (-not (Test-Path $path)) { continue }

        $text = Get-Content -Raw -Path $path

        if ($text.Contains("clipboard = `"forbidden`"")) {
            throw "$path still uses deprecated clipboard safety wording."
        }

        if ($text.Contains("clipboard_access = `"forbidden`"")) {
            throw "$path still uses deprecated clipboard_access safety wording."
        }
    }

    Write-Host "PASS: manifest safety wording passed."
}

function Assert-ModelConfigOnly {
    Write-Section "Model config check"

    $oldPatterns = @(
        "qwen3-vl:4b",
        "qwen3.6",
        "gemma4",
        "local-coder",
        "qwen2.5-coder",
        "huihui_ai/qwen2.5-vl-abliterated"
    )

    $scanFiles = @()

    foreach ($root in @("config", "crates\iris-model-router\src")) {
        if (Test-Path $root) {
            $scanFiles += Get-ChildItem -Path $root -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in @(".toml", ".rs", ".txt") }
        }
    }

    $hits = @()

    foreach ($pattern in $oldPatterns) {
        $found = $scanFiles | Select-String -Pattern $pattern -SimpleMatch -ErrorAction SilentlyContinue
        if ($found) { $hits += $found }
    }

    if ($hits.Count -gt 0) {
        foreach ($hit in $hits) {
            Write-Host "$($hit.Path):$($hit.LineNumber): $($hit.Line.Trim())"
        }
        throw "Old model reference found in runtime config/router files."
    }

    Write-Host "PASS: model config/router check passed."
}

Write-Section "Project Iris deterministic foundation guard"

$Model = Get-InstalledIrisModel -Prefix $ModelPrefix

if (-not [string]::IsNullOrWhiteSpace($Model)) {
    $env:IRIS_MODEL_ID = $Model
    $env:IRIS_OLLAMA_MODEL = $Model
    $env:IRIS_LOCAL_MODEL = $Model
    $env:IRIS_MODEL_NUM_CTX = "$NumCtx"
    $env:IRIS_MODEL_NUM_PREDICT = "$NumPredict"

    Write-Host "IRIS_MODEL_ID=$env:IRIS_MODEL_ID"
    Write-Host "IRIS_MODEL_NUM_CTX=$env:IRIS_MODEL_NUM_CTX"
    Write-Host "IRIS_MODEL_NUM_PREDICT=$env:IRIS_MODEL_NUM_PREDICT"
}

Assert-NoInteractiveDevPrompts
Assert-RuntimeBoundary
Assert-ManifestSafetyWording
Assert-ModelConfigOnly

Invoke-IrisNative "Cargo format" "cargo" @("fmt", "--all")
Invoke-IrisNative "Cargo build" "cargo" @("build", "--workspace")
Invoke-IrisNative "Cargo test" "cargo" @("test", "--workspace")
Invoke-IrisNative "Addressee intent test" "cargo" @("run", "-p", "iris-runtime", "--", "addressee-intent-test")
Invoke-IrisNative "Deictic role test" "cargo" @("run", "-p", "iris-runtime", "--", "deictic-role-test")
Invoke-IrisNative "Xtask audit" "cargo" @("run", "-p", "xtask")

Write-Section "Foundation result"
Write-Host "PASS: Iris deterministic foundation guard passed."
