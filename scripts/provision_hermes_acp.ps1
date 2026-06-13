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
$Wheel = Join-Path $DownloadRoot "hermes_agent-0.16.0-py3-none-any.whl"
$WheelUrl = "https://files.pythonhosted.org/packages/f2/76/189239ec60769ef70c35f0e81b250d6e5f9cfe16f9433033e08ee9b1d598/hermes_agent-0.16.0-py3-none-any.whl"
$ExpectedSha256 = "accb5a4a4827b41b3d162d2eb0b5f6db585d942ee23a3678ef21fc94d21c34a2"

if (-not (Test-Path -LiteralPath $Uv)) {
    throw "uv is required at $Uv"
}

New-Item -ItemType Directory -Force -Path $DownloadRoot | Out-Null
if (-not (Test-Path -LiteralPath $Wheel)) {
    Invoke-WebRequest -Uri $WheelUrl -OutFile $Wheel
}

$ActualSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $Wheel).Hash.ToLowerInvariant()
if ($ActualSha256 -ne $ExpectedSha256) {
    throw "Hermes Agent wheel hash mismatch: $ActualSha256"
}

if (-not (Test-Path -LiteralPath $Python)) {
    & $Uv venv $VenvRoot --python 3.11
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create the Iris-owned Hermes Python environment."
    }
}

& $Uv pip install --python $Python "$Wheel[acp]"
if ($LASTEXITCODE -ne 0) {
    throw "Failed to install Hermes Agent ACP."
}

& $HermesAcp --version
if ($LASTEXITCODE -ne 0) {
    throw "Hermes ACP version check failed."
}

& $HermesAcp --check
if ($LASTEXITCODE -ne 0) {
    throw "Hermes ACP import check failed."
}

& $Python -c "import importlib.metadata as m; assert m.version('hermes-agent') == '0.16.0'; assert m.version('agent-client-protocol') == '0.9.0'"
if ($LASTEXITCODE -ne 0) {
    throw "Hermes ACP package version audit failed."
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
    $ToolAudit.nativeDurableMemory -ne $false -or
    $ToolAudit.mcpAllowed -ne $false
) {
    throw "Hermes ACP Iris tool audit failed."
}

Write-Output "Iris-owned Hermes Agent 0.16.0 ACP runtime is ready."
