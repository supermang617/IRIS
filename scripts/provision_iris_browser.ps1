param(
    [switch]$IncludePinnedDevelopmentBrowser
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$RuntimeRoot = Join-Path $RepoRoot ".iris-runtime\browser"
$DownloadRoot = Join-Path $RuntimeRoot "downloads"
$BrowserRoot = Join-Path $RuntimeRoot "browsers\chrome-149.0.7827.115"
$BrowserExe = Join-Path $BrowserRoot "chrome.exe"
$AgentBrowserExe = Join-Path $RuntimeRoot "node_modules\agent-browser\bin\agent-browser-win32-x64.exe"
$PatchedControllerRoot = Join-Path $RepoRoot "third_party\agent-browser"
$PatchedControllerArchive = Join-Path $PatchedControllerRoot "agent-browser-win32-x64.zip"
$PatchedControllerPatch = Join-Path $PatchedControllerRoot "iris-default-context-race.patch"
$PatchedControllerProvenance = Join-Path $PatchedControllerRoot "provenance.json"
$ChromeZip = Join-Path $DownloadRoot "chrome-for-testing-149.0.7827.115-win64.zip"
$ChromeZipUrl = "https://storage.googleapis.com/chrome-for-testing-public/149.0.7827.115/win64/chrome-win64.zip"
$ExpectedPackageIntegrity = "sha512-e+TZ0G04uw2rs+lVB8gn0IWTT7ErfiAl3jQ4zNNwyqDhgXWJKhqxYKkyibjuBGXLzx/APlzU3IWAsOVdRwh0DA=="
$ExpectedNpmAgentBrowserSha256 = "291f0c33c2fbcbf159b5868065ab412dfd8722d6299821e010cf0715964f2cba"
$ExpectedAgentBrowserSha256 = "87ec662f82290a9f841808808f3d6934ae6502544da9ef564dafb634761dc86c"
$ExpectedAgentBrowserBytes = 14817280
$ExpectedPatchedControllerArchiveSha256 = "4b7e61f0c106b679f9451f146bdd6a3c7ef33f2287a490605e40ca049240a04f"
$ExpectedPatchedControllerArchiveBytes = 5650150
$ExpectedPatchedControllerPatchSha256 = "b62c7599e3e185e92813f3e891b0e446da54ad1bdc7810f9c6e0bb5750e2a36f"
$ExpectedPatchedControllerUpstreamHead = "c21c9b741a1eb23218c2bc9d165dc9c0af718604"
$ExpectedChromeZipSha256 = "1553389900824037aec828effab3051337df57a571e2f8800ee71cf8ed6fa76d"
$ExpectedChromeExeSha256 = "815ac13164ee3a5fa15a0e119fe868ec8d6ef6b3bd16bbe35ddd1da57c515c56"

if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    throw "Node.js 24 and npm are required to provision the Iris browser runtime."
}

$NodeMajor = [int]((& node --version).TrimStart("v").Split(".")[0])
if ($NodeMajor -lt 24) {
    throw "agent-browser 0.33.2 requires Node.js 24 or newer."
}

New-Item -ItemType Directory -Force -Path $RuntimeRoot | Out-Null
& npm install --prefix $RuntimeRoot --save-exact --ignore-scripts "agent-browser@0.33.2"
if ($LASTEXITCODE -ne 0) {
    throw "Failed to install pinned agent-browser 0.33.2."
}

$LockText = Get-Content -LiteralPath (Join-Path $RuntimeRoot "package-lock.json") -Raw
if (
    -not $LockText.Contains('"version": "0.33.2"') -or
    -not $LockText.Contains('"integrity": "' + $ExpectedPackageIntegrity + '"')
) {
    throw "agent-browser package lock does not match the pinned version and integrity."
}

$NpmAgentBrowserHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $AgentBrowserExe).Hash.ToLowerInvariant()
if ($NpmAgentBrowserHash -notin @($ExpectedNpmAgentBrowserSha256, $ExpectedAgentBrowserSha256)) {
    throw "npm or previously provisioned agent-browser native binary hash mismatch: $NpmAgentBrowserHash"
}

foreach ($requiredPatchedControllerFile in @(
        $PatchedControllerArchive,
        $PatchedControllerPatch,
        $PatchedControllerProvenance
    )) {
    if (-not (Test-Path -LiteralPath $requiredPatchedControllerFile -PathType Leaf)) {
        throw "Pinned Iris agent-browser controller input is missing: $requiredPatchedControllerFile"
    }
}

$PatchedControllerArchiveItem = Get-Item -LiteralPath $PatchedControllerArchive
$PatchedControllerArchiveHash = (
    Get-FileHash -Algorithm SHA256 -LiteralPath $PatchedControllerArchive
).Hash.ToLowerInvariant()
if (
    $PatchedControllerArchiveItem.Length -ne $ExpectedPatchedControllerArchiveBytes -or
    $PatchedControllerArchiveHash -ne $ExpectedPatchedControllerArchiveSha256
) {
    throw "Pinned Iris agent-browser controller archive does not match reviewed provenance."
}

$PatchedControllerPatchHash = (
    Get-FileHash -Algorithm SHA256 -LiteralPath $PatchedControllerPatch
).Hash.ToLowerInvariant()
if ($PatchedControllerPatchHash -ne $ExpectedPatchedControllerPatchSha256) {
    throw "Pinned Iris agent-browser source patch hash mismatch: $PatchedControllerPatchHash"
}

$Provenance = Get-Content -LiteralPath $PatchedControllerProvenance -Raw | ConvertFrom-Json
if (
    $Provenance.package.version -ne "0.33.2" -or
    $Provenance.package.npm_integrity -ne $ExpectedPackageIntegrity -or
    $Provenance.source.pull_request_head -ne $ExpectedPatchedControllerUpstreamHead -or
    $Provenance.source.local_patch_sha256 -ne $ExpectedPatchedControllerPatchSha256 -or
    $Provenance.artifact.archive_sha256 -ne $ExpectedPatchedControllerArchiveSha256 -or
    [int64]$Provenance.artifact.archive_bytes -ne $ExpectedPatchedControllerArchiveBytes -or
    $Provenance.artifact.executable_sha256 -ne $ExpectedAgentBrowserSha256 -or
    [int64]$Provenance.artifact.executable_bytes -ne $ExpectedAgentBrowserBytes
) {
    throw "Pinned Iris agent-browser provenance does not match reviewed constants."
}

$PatchedControllerExtractRoot = Join-Path (
    [System.IO.Path]::GetTempPath()
) ("iris-agent-browser-" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $PatchedControllerExtractRoot | Out-Null
try {
    Expand-Archive -LiteralPath $PatchedControllerArchive -DestinationPath $PatchedControllerExtractRoot
    $PatchedControllerExe = Join-Path $PatchedControllerExtractRoot "agent-browser-win32-x64.exe"
    if (-not (Test-Path -LiteralPath $PatchedControllerExe -PathType Leaf)) {
        throw "Pinned Iris agent-browser archive is missing agent-browser-win32-x64.exe."
    }
    $PatchedControllerExeItem = Get-Item -LiteralPath $PatchedControllerExe
    $PatchedControllerExeHash = (
        Get-FileHash -Algorithm SHA256 -LiteralPath $PatchedControllerExe
    ).Hash.ToLowerInvariant()
    if (
        $PatchedControllerExeItem.Length -ne $ExpectedAgentBrowserBytes -or
        $PatchedControllerExeHash -ne $ExpectedAgentBrowserSha256
    ) {
        throw "Expanded Iris agent-browser controller does not match reviewed provenance."
    }
    Copy-Item -LiteralPath $PatchedControllerExe -Destination $AgentBrowserExe -Force
} finally {
    $ResolvedExtractRoot = [System.IO.Path]::GetFullPath($PatchedControllerExtractRoot)
    $ResolvedTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd("\")
    if (-not $ResolvedExtractRoot.StartsWith($ResolvedTempRoot + "\iris-agent-browser-", [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove agent-browser extraction path outside the dedicated temporary root."
    }
    Remove-Item -LiteralPath $ResolvedExtractRoot -Recurse -Force
}

$AgentBrowserHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $AgentBrowserExe).Hash.ToLowerInvariant()
if ($AgentBrowserHash -ne $ExpectedAgentBrowserSha256) {
    throw "Installed Iris agent-browser controller hash mismatch: $AgentBrowserHash"
}
$AgentBrowserVersion = (& $AgentBrowserExe --version).Trim()
if ($LASTEXITCODE -ne 0 -or $AgentBrowserVersion -ne "agent-browser 0.33.2") {
    throw "Installed Iris agent-browser controller version mismatch: $AgentBrowserVersion"
}

if ($IncludePinnedDevelopmentBrowser) {
    New-Item -ItemType Directory -Force -Path $DownloadRoot | Out-Null
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
    Write-Output "Pinned Iris-patched agent-browser 0.33.2 and optional Chrome for Testing 149.0.7827.115 development fallback are ready."
    return
}

$configuredBrowser = if ($env:IRIS_BROWSER_EXECUTABLE_PATH) {
    if (-not [System.IO.Path]::IsPathRooted($env:IRIS_BROWSER_EXECUTABLE_PATH)) {
        throw "IRIS_BROWSER_EXECUTABLE_PATH must be an absolute path."
    }
    [System.IO.Path]::GetFullPath($env:IRIS_BROWSER_EXECUTABLE_PATH)
} else {
    $null
}
$systemBrowserCandidates = @($configuredBrowser)
foreach ($candidate in @(
        @{ Root = $env:ProgramFiles; Relative = "Google\Chrome\Application\chrome.exe" },
        @{ Root = ${env:ProgramFiles(x86)}; Relative = "Google\Chrome\Application\chrome.exe" },
        @{ Root = $env:LOCALAPPDATA; Relative = "Google\Chrome\Application\chrome.exe" }
    )) {
    if ($candidate.Root) {
        $systemBrowserCandidates += Join-Path $candidate.Root $candidate.Relative
    }
}
$systemBrowser = $systemBrowserCandidates |
    Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } |
    Select-Object -First 1
if (-not $systemBrowser) {
    throw "Iris needs Google Chrome for isolated browser automation. Install it with: winget install --id Google.Chrome -e"
}

Write-Output "Pinned Iris-patched agent-browser 0.33.2 is ready with system browser: $systemBrowser"
