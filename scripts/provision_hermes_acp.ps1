$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$UvCommand = Get-Command uv -ErrorAction SilentlyContinue
$Uv = if ($UvCommand) {
    $UvCommand.Source
} else {
    Join-Path $env:USERPROFILE ".local\bin\uv.exe"
}
$RuntimeRoot = Join-Path $RepoRoot ".iris-runtime\hermes"
$DownloadRoot = Join-Path $RuntimeRoot "downloads"
$VenvRoot = Join-Path $RuntimeRoot ".venv"
$Python = Join-Path $VenvRoot "Scripts\python.exe"
$HermesAcp = Join-Path $VenvRoot "Scripts\hermes-acp.exe"
$Wheel = Join-Path $DownloadRoot "hermes_agent-0.18.0-py3-none-any.whl"
$WheelUrl = "https://files.pythonhosted.org/packages/8a/9e/7179407c41f70d65a4d28edf9e81186598b9c6561b7b1865110f61e8e0e9/hermes_agent-0.18.0-py3-none-any.whl"
$ExpectedSha256 = "bf75c02d59f7c464cd0d85026fb7ee2e6bb15f003beccab3442b572f1ae1fd37"
$ProvenancePath = Join-Path $RepoRoot "profiles\hermes_agent_0_18_0.json"
$DependencyLock = Join-Path $RepoRoot "profiles\hermes_agent_python_3_13.lock.txt"
$ExpectedDependencyLockSha256 = "0e2e636b49109143e4ddf6787f94bf24722cdbd491001436298515934f47be5f"

if (-not (Test-Path -LiteralPath $Uv)) {
    throw "uv is required at $Uv"
}
if (-not (Test-Path -LiteralPath $DependencyLock -PathType Leaf)) {
    throw "Hermes dependency lock is missing: $DependencyLock"
}
$DependencyLockSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $DependencyLock).Hash.ToLowerInvariant()
if ($DependencyLockSha256 -ne $ExpectedDependencyLockSha256) {
    throw "Hermes dependency lock hash mismatch: $DependencyLockSha256"
}

New-Item -ItemType Directory -Force -Path $DownloadRoot | Out-Null
if (-not (Test-Path -LiteralPath $Wheel)) {
    Invoke-WebRequest -Uri $WheelUrl -OutFile $Wheel
}

$ActualSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $Wheel).Hash.ToLowerInvariant()
if ($ActualSha256 -ne $ExpectedSha256) {
    throw "Hermes Agent wheel hash mismatch: $ActualSha256"
}

$Provenance = Get-Content -LiteralPath $ProvenancePath -Raw | ConvertFrom-Json
if (
    $Provenance.version -ne "0.18.0" -or
    $Provenance.release_tag -ne "v2026.7.1" -or
    $Provenance.release_commit -ne "7c1a029553d87c43ecff8a3821336bc95872213b" -or
    $Provenance.wheel_sha256 -ne $ExpectedSha256 -or
    $Provenance.dependency_lock_sha256 -ne $ExpectedDependencyLockSha256 -or
    [int]$Provenance.dependency_count -ne 65 -or
    [string]$Provenance.sigstore_transparency_entry -ne "2040635656" -or
    $Provenance.trusted_publishing -ne $true
) {
    throw "Hermes Agent provenance profile does not match the audited 0.18.0 release."
}

$RecreateVenv = -not (Test-Path -LiteralPath $Python -PathType Leaf)
if (-not $RecreateVenv) {
    $ExistingPythonVersion = (& $Python -S -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>$null | Select-Object -First 1)
    $RecreateVenv = $ExistingPythonVersion -ne "3.13"
}
if ($RecreateVenv) {
    if (Test-Path -LiteralPath $VenvRoot) {
        $RuntimeRootResolved = [System.IO.Path]::GetFullPath($RuntimeRoot).TrimEnd("\")
        $VenvRootResolved = [System.IO.Path]::GetFullPath($VenvRoot)
        if (-not $VenvRootResolved.StartsWith($RuntimeRootResolved + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to replace a Hermes environment outside $RuntimeRootResolved`: $VenvRootResolved"
        }
        Remove-Item -LiteralPath $VenvRootResolved -Recurse -Force
    }
    & $Uv venv $VenvRoot --python 3.13
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create the Iris-owned Hermes Python 3.13 environment."
    }
}

& $Uv pip install --python $Python --require-hashes --no-deps --only-binary :all: --requirement $DependencyLock
if ($LASTEXITCODE -ne 0) {
    throw "Failed to install the fully hash-locked Hermes Agent ACP runtime."
}

& $HermesAcp --version
if ($LASTEXITCODE -ne 0) {
    throw "Hermes ACP version check failed."
}

& $HermesAcp --check
if ($LASTEXITCODE -ne 0) {
    throw "Hermes ACP import check failed."
}

$LockAudit = @'
import importlib.metadata as metadata
import pathlib
import re
import sys

lock_text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
expected = {
    re.sub(r"[-_.]+", "-", match.group(1)).lower(): match.group(2)
    for match in re.finditer(r"^([a-z0-9][a-z0-9._-]*)==([^ \\\r\n]+) \\$", lock_text, re.MULTILINE)
}
expected["hermes-agent"] = "0.18.0"
actual = {
    re.sub(r"[-_.]+", "-", dist.metadata["Name"]).lower(): dist.version
    for dist in metadata.distributions()
}
if actual != expected:
    raise SystemExit(f"locked distribution mismatch: expected={expected!r} actual={actual!r}")
required = {
    "hermes-agent": "0.18.0",
    "agent-client-protocol": "0.9.0",
    "pyjwt": "2.13.0",
    "cryptography": "50.0.0",
    "pillow": "12.3.0",
}
for name, version in required.items():
    if actual.get(name) != version:
        raise SystemExit(f"{name} version mismatch: expected {version}, found {actual.get(name)}")
'@
$LockAuditEncoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($LockAudit))
& $Python -c "import base64;exec(base64.b64decode('$LockAuditEncoded'))" $DependencyLock
if ($LASTEXITCODE -ne 0) {
    throw "Hermes ACP exact dependency-set audit failed."
}

$ToolAudit = & $Python (Join-Path $RepoRoot "plugins\hermes_acp\iris_acp.py") --audit-tools | ConvertFrom-Json
if (
    $ToolAudit.toolset -ne "iris-acp-bridge" -or
    @($ToolAudit.tools).Count -ne 2 -or
    -not (@($ToolAudit.tools) -contains "iris_query_memory") -or
    -not (@($ToolAudit.tools) -contains "iris_propose_memory") -or
    @($ToolAudit.actionTools).Count -ne 6 -or
    @($ToolAudit.browserTools).Count -ne 10 -or
    @($ToolAudit.allActingTools).Count -ne 16 -or
    -not (@($ToolAudit.allActingTools) -contains "read_file") -or
    -not (@($ToolAudit.allActingTools) -contains "write_file") -or
    -not (@($ToolAudit.allActingTools) -contains "patch") -or
    -not (@($ToolAudit.allActingTools) -contains "search_files") -or
    -not (@($ToolAudit.allActingTools) -contains "terminal") -or
    -not (@($ToolAudit.allActingTools) -contains "process") -or
    -not (@($ToolAudit.allActingTools) -contains "browser_open") -or
    -not (@($ToolAudit.allActingTools) -contains "browser_snapshot") -or
    -not (@($ToolAudit.allActingTools) -contains "browser_click") -or
    -not (@($ToolAudit.allActingTools) -contains "browser_fill") -or
    -not (@($ToolAudit.allActingTools) -contains "browser_press") -or
    -not (@($ToolAudit.allActingTools) -contains "browser_screenshot") -or
    -not (@($ToolAudit.allActingTools) -contains "browser_get_url") -or
    -not (@($ToolAudit.allActingTools) -contains "browser_upload") -or
    -not (@($ToolAudit.allActingTools) -contains "browser_download") -or
    -not (@($ToolAudit.allActingTools) -contains "browser_close") -or
    $ToolAudit.maxIterations -ne 8 -or
    $ToolAudit.maxTokens -ne 512 -or
    $ToolAudit.promptScopedTools -ne $true -or
    $ToolAudit.requestOverrides.temperature -ne 0 -or
    $ToolAudit.requestOverrides.toolChoice -ne "prompt_scoped" -or
    $ToolAudit.requestOverrides.extraBody.think -ne $false -or
    $ToolAudit.requestOverrides.extraBody.options.numPredict -ne 512 -or
    $ToolAudit.nativeDurableMemory -ne $false -or
    $ToolAudit.mcpAllowed -ne $false
) {
    throw "Hermes ACP Iris tool audit failed."
}

Write-Output "Iris-owned Hermes Agent 0.18.0 ACP runtime on Python 3.13 is ready."
