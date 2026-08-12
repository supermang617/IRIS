$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$sourceLauncher = Get-Content -LiteralPath (Join-Path $repoRoot "Start Iris.ps1") -Raw
$packageScript = Get-Content -LiteralPath (Join-Path $repoRoot "scripts\package_windows_release.ps1") -Raw

foreach ($name in @(
        "OLLAMA_FLASH_ATTENTION",
        "OLLAMA_KV_CACHE_TYPE",
        "OLLAMA_NUM_PARALLEL",
        "OLLAMA_MAX_LOADED_MODELS"
    )) {
    foreach ($source in @($sourceLauncher, $packageScript)) {
        if (-not $source.Contains("Set-IrisOllamaDefault -Name `"$name`"")) {
            throw "Launcher source is missing the measured Ollama default: $name"
        }
    }
}

foreach ($source in @($sourceLauncher, $packageScript)) {
    foreach ($fragment in @(
            '[Environment]::GetEnvironmentVariable($Name, "Process")',
            '-not [string]::IsNullOrWhiteSpace($current)',
            'Set-Item -Path "Env:$Name" -Value $Value'
        )) {
        if (-not $source.Contains($fragment)) {
            throw "Launcher defaults must preserve non-empty user overrides; missing implementation fragment: $fragment"
        }
    }
}

foreach ($source in @($sourceLauncher, $packageScript)) {
    foreach ($fragment in @(
            'function Assert-IrisOllamaLoopbackOnly',
            'Get-NetTCPConnection -State Listen -LocalPort 11434',
            '$env:OLLAMA_HOST = "127.0.0.1:11434"',
            '"::ffff:127.0.0.1"',
            'Iris will not use a network-exposed model service.',
            'Assert-IrisOllamaLoopbackOnly'
        )) {
        if (-not $source.Contains($fragment)) {
            throw "Launcher must force and verify the local-only Ollama listener; missing: $fragment"
        }
    }
    if ($source.Contains('Set-IrisOllamaDefault -Name "OLLAMA_HOST"') -or
        $source.Contains('OLLAMA_HOST" -PersistForCurrentUser')) {
        throw "Launcher must not persist or honor a network-wide OLLAMA_HOST for Iris-owned launches."
    }
}

foreach ($source in @($sourceLauncher, $packageScript)) {
    foreach ($fragment in @(
            "Iris will not terminate the shared server",
            "Iris will use the shared server without terminating it"
        )) {
        if (-not $source.Contains($fragment)) {
            throw "Launcher must preserve an existing user-owned Ollama server; missing: $fragment"
        }
    }
    foreach ($unsafeFragment in @(
            'Get-Process "ollama", "ollama app", "llama-server"',
            "Stop-OllamaForIris",
            "taskkill.exe /PID",
            "taskkill.exe /IM",
            "taskkill /IM"
        )) {
        if ($source.Contains($unsafeFragment)) {
            throw "Launcher must not terminate an existing Ollama process: $unsafeFragment"
        }
    }
}

foreach ($source in @($sourceLauncher, $packageScript)) {
    foreach ($persistentDefault in @(
            'Set-IrisOllamaDefault -Name "OLLAMA_FLASH_ATTENTION" -Value "1" -PersistForCurrentUser',
            'Set-IrisOllamaDefault -Name "OLLAMA_KV_CACHE_TYPE" -Value "q8_0" -PersistForCurrentUser'
        )) {
        if (-not $source.Contains($persistentDefault)) {
            throw "Ollama server memory default must persist only when no override exists; missing: $persistentDefault"
        }
    }
    foreach ($processOnlyDefault in @(
            'Set-IrisOllamaDefault -Name "OLLAMA_NUM_PARALLEL" -Value "1"',
            'Set-IrisOllamaDefault -Name "OLLAMA_MAX_LOADED_MODELS" -Value "1"'
        )) {
        if (-not $source.Contains($processOnlyDefault) -or $source.Contains("$processOnlyDefault -PersistForCurrentUser")) {
            throw "Ollama concurrency default must remain process-only: $processOnlyDefault"
        }
    }
    foreach ($fragment in @(
            '[Environment]::GetEnvironmentVariable($Name, "User")',
            '[Environment]::GetEnvironmentVariable($Name, "Machine")',
            '[Environment]::SetEnvironmentVariable($Name, $Value, "User")',
            '$script:irisOllamaServerDefaultsInitialized',
            'if ($script:irisOllamaServerDefaultsInitialized)'
        )) {
        if (-not $source.Contains($fragment)) {
            throw "Launcher is missing safe first-run Ollama server-default handling: $fragment"
        }
    }
}

foreach ($source in @($sourceLauncher, $packageScript)) {
    if (-not $source.Contains('$SelfCheck')) {
        throw "Launcher must support the canonical PowerShell -SelfCheck switch."
    }
    if (-not $source.Contains('$args -contains "--self-check"')) {
        throw "Launcher must preserve the legacy --self-check alias."
    }
}

Write-Host "Windows launcher Ollama-default test passed."
