$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$RuntimeRoot = Join-Path $RepoRoot ".iris-runtime\browser"
$DownloadRoot = Join-Path $RuntimeRoot "downloads"
$BrowserRoot = Join-Path $RuntimeRoot "browsers\chrome-149.0.7827.115"
$BrowserExe = Join-Path $BrowserRoot "chrome.exe"
$AgentBrowserExe = Join-Path $RuntimeRoot "node_modules\agent-browser\bin\agent-browser-win32-x64.exe"
$ChromeZip = Join-Path $DownloadRoot "chrome-for-testing-149.0.7827.115-win64.zip"
$ChromeZipUrl = "https://storage.googleapis.com/chrome-for-testing-public/149.0.7827.115/win64/chrome-win64.zip"
$ExpectedPackageIntegrity = "sha512-RZNxZFvnspSxSmpjkZjM0Lv69ArwYr8t+Ndavko/NGrfkdUkp5lVGJAs4f88tJNNcBVFcn92hhS+3pulVF9oSw=="
$ExpectedAgentBrowserSha256 = "013c9bb6084e72d69a8ebb6c3d5669ba117129479b81d9336012b36b91f490e5"
$ExpectedChromeZipSha256 = "1553389900824037aec828effab3051337df57a571e2f8800ee71cf8ed6fa76d"
$ExpectedChromeExeSha256 = "815ac13164ee3a5fa15a0e119fe868ec8d6ef6b3bd16bbe35ddd1da57c515c56"

if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    throw "Node.js 24 and npm are required to provision the Iris browser runtime."
}

$NodeMajor = [int]((& node --version).TrimStart("v").Split(".")[0])
if ($NodeMajor -lt 24) {
    throw "agent-browser 0.27.2 requires Node.js 24 or newer."
}

New-Item -ItemType Directory -Force -Path $RuntimeRoot, $DownloadRoot | Out-Null
& npm install --prefix $RuntimeRoot --save-exact "agent-browser@0.27.2"
if ($LASTEXITCODE -ne 0) {
    throw "Failed to install pinned agent-browser 0.27.2."
}

$LockText = Get-Content -LiteralPath (Join-Path $RuntimeRoot "package-lock.json") -Raw
if (
    -not $LockText.Contains('"version": "0.27.2"') -or
    -not $LockText.Contains('"integrity": "' + $ExpectedPackageIntegrity + '"')
) {
    throw "agent-browser package lock does not match the pinned version and integrity."
}

$AgentBrowserHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $AgentBrowserExe).Hash.ToLowerInvariant()
if ($AgentBrowserHash -ne $ExpectedAgentBrowserSha256) {
    throw "agent-browser native binary hash mismatch: $AgentBrowserHash"
}

if (-not (Test-Path -LiteralPath $ChromeZip -PathType Leaf)) {
    Invoke-WebRequest -Uri $ChromeZipUrl -OutFile $ChromeZip
}
$ChromeZipHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $ChromeZip).Hash.ToLowerInvariant()
if ($ChromeZipHash -ne $ExpectedChromeZipSha256) {
    throw "Chrome for Testing archive hash mismatch: $ChromeZipHash"
}

if (-not (Test-Path -LiteralPath $BrowserExe -PathType Leaf)) {
    if (Test-Path -LiteralPath $BrowserRoot) {
        throw "Incomplete Iris browser directory already exists: $BrowserRoot"
    }
    $ExtractRoot = Join-Path $RuntimeRoot "chrome-extract-149.0.7827.115"
    if (Test-Path -LiteralPath $ExtractRoot) {
        $ResolvedRuntime = [System.IO.Path]::GetFullPath($RuntimeRoot)
        $ResolvedExtract = [System.IO.Path]::GetFullPath($ExtractRoot)
        if (-not $ResolvedExtract.StartsWith($ResolvedRuntime, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove browser extraction path outside the Iris runtime."
        }
        Remove-Item -LiteralPath $ExtractRoot -Recurse -Force
    }
    Expand-Archive -LiteralPath $ChromeZip -DestinationPath $ExtractRoot
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $BrowserRoot) | Out-Null
    Move-Item -LiteralPath (Join-Path $ExtractRoot "chrome-win64") -Destination $BrowserRoot
    Remove-Item -LiteralPath $ExtractRoot -Recurse -Force
}

$ChromeHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $BrowserExe).Hash.ToLowerInvariant()
if ($ChromeHash -ne $ExpectedChromeExeSha256) {
    throw "Chrome for Testing executable hash mismatch: $ChromeHash"
}

Write-Output "Iris-owned agent-browser 0.27.2 and Chrome for Testing 149.0.7827.115 are ready."
