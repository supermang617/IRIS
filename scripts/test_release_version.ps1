param(
    [Parameter(Mandatory = $true)][string]$Tag
)

$ErrorActionPreference = "Stop"

if ($Tag -notmatch "^v(?<major>0|[1-9][0-9]*)\.(?<minor>0|[1-9][0-9]*)\.(?<patch>0|[1-9][0-9]*)$") {
    throw "Release tag must be immutable semantic version vMAJOR.MINOR.PATCH."
}
$expected = "$($Matches.major).$($Matches.minor).$($Matches.patch)"
foreach ($component in @($Matches.major, $Matches.minor, $Matches.patch)) {
    if ([uint64]$component -gt 65535) {
        throw "Every release version component must fit the MSIX range 0-65535."
    }
}
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path

$package = Get-Content -LiteralPath (Join-Path $repoRoot "package.json") -Raw | ConvertFrom-Json
$packageLockText = Get-Content -LiteralPath (Join-Path $repoRoot "package-lock.json") -Raw
if ($PSVersionTable.PSVersion.Major -ge 6) {
    $packageLock = $packageLockText | ConvertFrom-Json -AsHashtable
} else {
    Add-Type -AssemblyName System.Web.Extensions
    $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $serializer.MaxJsonLength = $packageLockText.Length + 1024
    $packageLock = $serializer.DeserializeObject($packageLockText)
}
$tauri = Get-Content -LiteralPath (Join-Path $repoRoot "src-tauri\tauri.conf.json") -Raw | ConvertFrom-Json
$manifest = Get-Content -LiteralPath (Join-Path $repoRoot "manifest.json") -Raw | ConvertFrom-Json
$rootCargoText = Get-Content -LiteralPath (Join-Path $repoRoot "Cargo.toml") -Raw
$workspaceVersionMatch = [regex]::Match(
    $rootCargoText,
    '(?ms)^\[workspace\.package\]\s+version\s*=\s*"([^"]+)"'
)
if (-not $workspaceVersionMatch.Success) {
    throw "Root Cargo.toml has no [workspace.package] version."
}

foreach ($entry in @(
        [pscustomobject]@{ Name = "package.json"; Version = [string]$package.version },
        [pscustomobject]@{ Name = "package-lock.json"; Version = [string]$packageLock["version"] },
        [pscustomobject]@{ Name = "package-lock root package"; Version = [string]$packageLock["packages"][""]["version"] },
        [pscustomobject]@{ Name = "src-tauri/tauri.conf.json"; Version = [string]$tauri.version },
        [pscustomobject]@{ Name = "manifest.json"; Version = [string]$manifest.project.version },
        [pscustomobject]@{ Name = "Cargo workspace"; Version = $workspaceVersionMatch.Groups[1].Value }
    )) {
    if ($entry.Version -ne $expected) {
        throw "$($entry.Name) version '$($entry.Version)' does not match release tag $Tag."
    }
}

$cargoFiles = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot "crates") -Recurse -Filter Cargo.toml -File)
$cargoFiles += Get-Item -LiteralPath (Join-Path $repoRoot "src-tauri\Cargo.toml")
$cargoFiles += Get-Item -LiteralPath (Join-Path $repoRoot "xtask\Cargo.toml")
foreach ($cargoFile in $cargoFiles) {
    $text = Get-Content -LiteralPath $cargoFile.FullName -Raw
    if ($text -notmatch '(?m)^version\.workspace\s*=\s*true\s*$') {
        $relative = $cargoFile.FullName.Substring($repoRoot.Length).TrimStart("\")
        throw "$relative must inherit [workspace.package].version."
    }
}

Write-Host "Release version consistency test passed for $Tag."
