$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$helperPath = Join-Path $repoRoot "scripts\iris_release_workspace.ps1"
. $helperPath

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-OrderedFragments {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string[]]$Fragments,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $previous = -1
    foreach ($fragment in $Fragments) {
        $position = $Text.IndexOf($fragment, [System.StringComparison]::Ordinal)
        if ($position -lt 0) {
            throw "$Name is missing required cleanup fragment: $fragment"
        }
        if ($position -le $previous) {
            throw "$Name does not perform cleanup only after completed artifact hashing: $fragment"
        }
        $previous = $position
    }
}

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("iris-release-cleanup-" + [System.Guid]::NewGuid().ToString("N"))
$fixtureRoot = Join-Path $testRoot "repo"
$releaseRoot = Join-Path $fixtureRoot "release"
$distRoot = Join-Path $releaseRoot "dist"
$externalRoot = Join-Path $testRoot "external"
$lockedStream = $null
$junctionPath = $null

try {
    $fixtureScriptsRoot = Join-Path $fixtureRoot "scripts"
    New-Item -ItemType Directory -Force -Path $distRoot, $externalRoot, $fixtureScriptsRoot | Out-Null
    Set-Content -LiteralPath (Join-Path $fixtureRoot "Cargo.toml") -Value "[workspace]" -Encoding ascii
    Set-Content -LiteralPath (Join-Path $fixtureRoot "manifest.json") -Value "{}" -Encoding ascii
    Set-Content -LiteralPath (Join-Path $fixtureScriptsRoot "iris_release_workspace.ps1") -Value "# fixture" -Encoding ascii
    Set-Content -LiteralPath (Join-Path $fixtureScriptsRoot "package_windows_release.ps1") -Value "# fixture" -Encoding ascii
    Set-Content -LiteralPath (Join-Path $fixtureScriptsRoot "package_windows_msix.ps1") -Value "# fixture" -Encoding ascii
    $distSentinel = Join-Path $distRoot "iris-windows.zip"
    $externalSentinel = Join-Path $externalRoot "outside.txt"
    Set-Content -LiteralPath $distSentinel -Value "preserve-dist" -Encoding ascii
    Set-Content -LiteralPath $externalSentinel -Value "preserve-external" -Encoding ascii

    $stagingRoot = Join-Path $releaseRoot "staging"
    New-Item -ItemType Directory -Force -Path (Join-Path $stagingRoot "nested\payload") | Out-Null
    Set-Content -LiteralPath (Join-Path $stagingRoot "nested\payload\file.bin") -Value "generated" -Encoding ascii
    Remove-IrisReleaseWorkspace `
        -RepositoryRoot $fixtureRoot `
        -Workspace "staging" `
        -RetryCount 1 `
        -RetryDelayMilliseconds 0
    Assert-Condition -Condition (-not (Test-Path -LiteralPath $stagingRoot)) -Message "Successful cleanup left release\staging behind."
    Assert-Condition -Condition (Test-Path -LiteralPath $distSentinel -PathType Leaf) -Message "Cleanup removed a release\dist artifact."
    Assert-Condition -Condition (Test-Path -LiteralPath $externalSentinel -PathType Leaf) -Message "Cleanup escaped the generated release workspace."

    Remove-IrisReleaseWorkspace `
        -RepositoryRoot $fixtureRoot `
        -Workspace "staging" `
        -RetryCount 1 `
        -RetryDelayMilliseconds 0

    $invalidTargetRejected = $false
    try {
        Remove-IrisReleaseWorkspace `
            -RepositoryRoot $fixtureRoot `
            -Workspace "dist" `
            -RetryCount 1 `
            -RetryDelayMilliseconds 0
    } catch {
        $invalidTargetRejected = $true
    }
    Assert-Condition -Condition $invalidTargetRejected -Message "Cleanup accepted release\dist as a generated workspace."
    Assert-Condition -Condition (Test-Path -LiteralPath $distSentinel -PathType Leaf) -Message "Invalid-target cleanup touched release\dist."

    $unverifiedRoot = Join-Path $testRoot "not-an-iris-repo"
    $unverifiedStaging = Join-Path $unverifiedRoot "release\staging"
    New-Item -ItemType Directory -Force -Path $unverifiedStaging | Out-Null
    Set-Content -LiteralPath (Join-Path $unverifiedStaging "sentinel.txt") -Value "preserve" -Encoding ascii
    $unverifiedRootRejected = $false
    try {
        Remove-IrisReleaseWorkspace `
            -RepositoryRoot $unverifiedRoot `
            -Workspace "staging" `
            -RetryCount 1 `
            -RetryDelayMilliseconds 0
    } catch {
        $unverifiedRootRejected = $_.Exception.Message -like "*outside an Iris repository*"
    }
    Assert-Condition -Condition $unverifiedRootRejected -Message "Cleanup accepted a repository root without Iris identity markers."
    Assert-Condition -Condition (Test-Path -LiteralPath (Join-Path $unverifiedStaging "sentinel.txt") -PathType Leaf) -Message "Unverified-root cleanup deleted data."

    New-Item -ItemType Directory -Force -Path $stagingRoot | Out-Null
    $junctionPath = Join-Path $stagingRoot "redirect"
    New-Item -ItemType Junction -Path $junctionPath -Target $externalRoot | Out-Null
    $reparseRejected = $false
    try {
        Remove-IrisReleaseWorkspace `
            -RepositoryRoot $fixtureRoot `
            -Workspace "staging" `
            -RetryCount 1 `
            -RetryDelayMilliseconds 0
    } catch {
        $reparseRejected = $_.Exception.Message -like "*reparse point*"
    }
    Assert-Condition -Condition $reparseRejected -Message "Cleanup did not fail closed on a nested release-workspace junction."
    Assert-Condition -Condition (Test-Path -LiteralPath $externalSentinel -PathType Leaf) -Message "Cleanup followed a release-workspace junction outside its target."
    [System.IO.Directory]::Delete($junctionPath)
    $junctionPath = $null
    Remove-IrisReleaseWorkspace `
        -RepositoryRoot $fixtureRoot `
        -Workspace "staging" `
        -RetryCount 1 `
        -RetryDelayMilliseconds 0

    $msixRoot = Join-Path $releaseRoot "msix"
    New-Item -ItemType Directory -Force -Path $msixRoot | Out-Null
    $lockedPath = Join-Path $msixRoot "locked.bin"
    Set-Content -LiteralPath $lockedPath -Value "locked" -Encoding ascii
    $lockedStream = [System.IO.File]::Open(
        $lockedPath,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None
    )
    $lockRejected = $false
    try {
        Remove-IrisReleaseWorkspace `
            -RepositoryRoot $fixtureRoot `
            -Workspace "msix" `
            -RetryCount 2 `
            -RetryDelayMilliseconds 10
    } catch {
        $lockRejected = $_.Exception.Message -like "*release\dist was preserved*"
    }
    Assert-Condition -Condition $lockRejected -Message "Cleanup falsely reported success while a workspace file was exclusively locked."
    Assert-Condition -Condition (Test-Path -LiteralPath $msixRoot -PathType Container) -Message "Locked cleanup removed its workspace despite reporting failure."
    Assert-Condition -Condition (Test-Path -LiteralPath $distSentinel -PathType Leaf) -Message "Locked cleanup touched release\dist."
    $lockedStream.Dispose()
    $lockedStream = $null
    Remove-IrisReleaseWorkspace `
        -RepositoryRoot $fixtureRoot `
        -Workspace "msix" `
        -RetryCount 1 `
        -RetryDelayMilliseconds 0
    Assert-Condition -Condition (-not (Test-Path -LiteralPath $msixRoot)) -Message "Cleanup did not recover after the exclusive lock was released."

    $releasePackager = Get-Content -LiteralPath (Join-Path $repoRoot "scripts\package_windows_release.ps1") -Raw
    $msixPackager = Get-Content -LiteralPath (Join-Path $repoRoot "scripts\package_windows_msix.ps1") -Raw
    $installer = Get-Content -LiteralPath (Join-Path $repoRoot "scripts\install_iris_windows.ps1") -Raw
    foreach ($entry in @(
            [pscustomobject]@{ Name = "portable packager"; Text = $releasePackager; Workspace = "staging" },
            [pscustomobject]@{ Name = "MSIX packager"; Text = $msixPackager; Workspace = "msix" }
        )) {
        foreach ($fragment in @(
                '[switch]$KeepPackagingWorkspace',
                '. (Join-Path $PSScriptRoot "iris_release_workspace.ps1")',
                "Remove-IrisReleaseWorkspace -RepositoryRoot `$repoRoot -Workspace `"$($entry.Workspace)`""
            )) {
            Assert-Condition -Condition $entry.Text.Contains($fragment) -Message "$($entry.Name) is missing bounded workspace cleanup: $fragment"
        }
    }
    Assert-OrderedFragments `
        -Text $releasePackager `
        -Name "portable packager" `
        -Fragments @(
            'Set-Content -LiteralPath $beginnerShaPath',
            'Remove-IrisReleaseWorkspace -RepositoryRoot $repoRoot -Workspace "staging"',
            'Write-Host "Iris Windows ZIP:'
        )
    Assert-OrderedFragments `
        -Text $msixPackager `
        -Name "MSIX packager" `
        -Fragments @(
            'Set-Content -LiteralPath $msixShaPath',
            'Remove-IrisReleaseWorkspace -RepositoryRoot $repoRoot -Workspace "msix"',
            'Write-Host "MSIX:'
        )
    Assert-OrderedFragments `
        -Text $installer `
        -Name "source-tree installer fallback" `
        -Fragments @(
            '$sourceDistRoot = Join-Path $scriptRoot "..\release\dist"',
            '$sourceRoot = (Resolve-Path -LiteralPath (Join-Path $sourceRoot "..\release\staging\iris-windows")).Path'
        )

    Write-Host "Iris release packaging-workspace cleanup tests passed."
} finally {
    if ($lockedStream) {
        $lockedStream.Dispose()
    }
    if ($junctionPath -and (Test-Path -LiteralPath $junctionPath)) {
        try {
            [System.IO.Directory]::Delete($junctionPath)
        } catch {
            Write-Warning "Could not remove cleanup-test junction $junctionPath`: $($_.Exception.Message)"
        }
    }
    if (Test-Path -LiteralPath $testRoot) {
        $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
        $resolvedTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd("\")
        if (-not $resolvedTestRoot.StartsWith($resolvedTempRoot + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove cleanup test data outside the system temp directory: $resolvedTestRoot"
        }
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
