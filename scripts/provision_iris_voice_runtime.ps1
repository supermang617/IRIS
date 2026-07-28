param(
    [string]$PythonPath = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$runtimeRoot = Join-Path $repoRoot ".iris-runtime\voice"
$sitePackages = Join-Path $runtimeRoot "Lib\site-packages"
$lockPath = Join-Path $repoRoot "profiles\iris_voice_python_3_13.lock.txt"
$runtimeLockPath = Join-Path $runtimeRoot "runtime-lock.txt"
$expectedLockSha256 = "47721402e024c64e8d9bef71b16e44d2323876b16dd0860827e0cec24489fd8c"
$expectedDistributionCount = 32
$uvCommand = Get-Command uv -ErrorAction SilentlyContinue
$uv = if ($uvCommand) {
    $uvCommand.Source
} else {
    Join-Path $env:USERPROFILE ".local\bin\uv.exe"
}

function Assert-ChildPath {
    param(
        [Parameter(Mandatory = $true)][string]$Parent,
        [Parameter(Mandatory = $true)][string]$Child
    )

    $parentResolved = [System.IO.Path]::GetFullPath($Parent).TrimEnd("\")
    $childResolved = [System.IO.Path]::GetFullPath($Child)
    if (-not $childResolved.StartsWith($parentResolved + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to manage a voice runtime path outside $parentResolved`: $childResolved"
    }
    return $childResolved
}

function Find-Python313 {
    if ($PythonPath) {
        return [System.IO.Path]::GetFullPath($PythonPath)
    }

    $uvPython = (& $uv python find 3.13 2>$null | Select-Object -First 1)
    if ($uvPython) {
        return [System.IO.Path]::GetFullPath([string]$uvPython)
    }
    throw "Exact Python 3.13 was not found. Install Python.Python.3.13 or run uv python install 3.13."
}

if (-not (Test-Path -LiteralPath $uv -PathType Leaf)) {
    throw "uv is required to provision the Iris-owned voice layer at $uv"
}
if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) {
    throw "Voice runtime lock is missing: $lockPath"
}

$lockHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $lockPath).Hash.ToLowerInvariant()
if ($lockHash -ne $expectedLockSha256) {
    throw "Voice runtime lock hash mismatch: $lockHash"
}
$lockedDistributionCount = @(
    Get-Content -LiteralPath $lockPath |
        Where-Object { $_ -match '^[a-z0-9][a-z0-9._-]*==[^ ]+ \\' }
).Count
if ($lockedDistributionCount -ne $expectedDistributionCount) {
    throw "Voice runtime lock contains $lockedDistributionCount distributions; expected $expectedDistributionCount."
}

$python = Find-Python313
$pythonVersion = (& $python -S -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>$null | Select-Object -First 1)
if ($pythonVersion -ne "3.13") {
    throw "Voice runtime provisioning requires exact Python 3.13: $python"
}

$runtimeRootResolved = [System.IO.Path]::GetFullPath($runtimeRoot).TrimEnd("\")
$sitePackagesResolved = Assert-ChildPath -Parent $runtimeRootResolved -Child $sitePackages
$stagingRoot = Assert-ChildPath -Parent $runtimeRootResolved -Child (Join-Path $runtimeRoot ("staging-" + [System.Guid]::NewGuid().ToString("N")))
$backupRoot = Assert-ChildPath -Parent $runtimeRootResolved -Child (Join-Path $runtimeRoot ("backup-" + [System.Guid]::NewGuid().ToString("N")))

New-Item -ItemType Directory -Force -Path $runtimeRootResolved, $stagingRoot | Out-Null

try {
    & $uv pip sync `
        --python $python `
        --target $stagingRoot `
        --require-hashes `
        --strict `
        --only-binary :all: `
        $lockPath
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to synchronize the fully hash-locked Iris voice layer."
    }

    foreach ($cacheDirectory in @(Get-ChildItem -LiteralPath $stagingRoot -Recurse -Force -Directory -Filter "__pycache__" -ErrorAction SilentlyContinue)) {
        $cachePath = Assert-ChildPath -Parent $stagingRoot -Child $cacheDirectory.FullName
        Remove-Item -LiteralPath $cachePath -Recurse -Force
    }
    foreach ($bytecodeFile in @(Get-ChildItem -LiteralPath $stagingRoot -Recurse -Force -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in @(".pyc", ".pyo") })) {
        $bytecodePath = Assert-ChildPath -Parent $stagingRoot -Child $bytecodeFile.FullName
        Remove-Item -LiteralPath $bytecodePath -Force
    }

    $auditCode = @'
import importlib.metadata as metadata
import json
import pathlib
import re
import sys

site = pathlib.Path(sys.argv[1]).resolve()
lock_text = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")
expected = {
    re.sub(r"[-_.]+", "-", match.group(1)).lower(): match.group(2)
    for match in re.finditer(r"^([a-z0-9][a-z0-9._-]*)==([^ \\\r\n]+) \\$", lock_text, re.MULTILINE)
}
actual = {
    re.sub(r"[-_.]+", "-", dist.metadata["Name"]).lower(): dist.version
    for dist in metadata.distributions(path=[str(site)])
}
if actual != expected:
    raise SystemExit(f"locked distribution mismatch: expected={expected!r} actual={actual!r}")
sys.path.insert(0, str(site))
import kokoro_onnx
import numpy
import onnxruntime
import soundfile
for module in (kokoro_onnx, numpy, onnxruntime, soundfile):
    module_path = pathlib.Path(module.__file__).resolve()
    if site not in module_path.parents:
        raise SystemExit(f"{module.__name__} escaped the Iris voice layer: {module_path}")
required = {
    "kokoro-onnx": "0.5.0",
    "soundfile": "0.14.0",
    "numpy": "2.5.1",
    "onnxruntime": "1.28.0",
}
for name, version in required.items():
    if actual.get(name) != version:
        raise SystemExit(f"{name} version mismatch: expected {version}, found {actual.get(name)}")
print(json.dumps({name: actual[name] for name in sorted(required)}, sort_keys=True))
'@
    $auditEncoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($auditCode))
    & $python -S -c "import base64;exec(base64.b64decode('$auditEncoded'))" $stagingRoot $lockPath
    if ($LASTEXITCODE -ne 0) {
        throw "Iris-owned voice layer import/version audit failed."
    }

    if (Test-Path -LiteralPath $sitePackagesResolved) {
        Move-Item -LiteralPath $sitePackagesResolved -Destination $backupRoot
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $sitePackagesResolved) | Out-Null
    Move-Item -LiteralPath $stagingRoot -Destination $sitePackagesResolved
    Copy-Item -LiteralPath $lockPath -Destination $runtimeLockPath -Force
    if (Test-Path -LiteralPath $backupRoot) {
        Remove-Item -LiteralPath $backupRoot -Recurse -Force
    }
} catch {
    if ((Test-Path -LiteralPath $backupRoot) -and -not (Test-Path -LiteralPath $sitePackagesResolved)) {
        Move-Item -LiteralPath $backupRoot -Destination $sitePackagesResolved
    }
    throw
} finally {
    foreach ($temporaryPath in @($stagingRoot, $backupRoot)) {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

$installedLockHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $runtimeLockPath).Hash.ToLowerInvariant()
$layerBytes = (Get-ChildItem -LiteralPath $sitePackagesResolved -Recurse -Force -File |
        Measure-Object -Property Length -Sum).Sum
Write-Output "Iris-owned voice Python 3.13 layer is ready."
Write-Output "Lock SHA256: $installedLockHash"
Write-Output "Installed bytes: $layerBytes"
