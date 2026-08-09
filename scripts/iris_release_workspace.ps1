function Remove-IrisReleaseWorkspace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)]
        [ValidateSet("staging", "msix")]
        [string]$Workspace,
        [ValidateRange(1, 10)][int]$RetryCount = 3,
        [ValidateRange(0, 5000)][int]$RetryDelayMilliseconds = 250
    )

    $repository = (Resolve-Path -LiteralPath $RepositoryRoot -ErrorAction Stop).Path.TrimEnd("\")
    $repositoryDriveRoot = [System.IO.Path]::GetPathRoot($repository).TrimEnd("\")
    if (-not $repository -or $repository -ieq $repositoryDriveRoot) {
        throw "Refusing to clean an Iris packaging workspace from an invalid repository root: $repository"
    }

    foreach ($identityMarker in @(
            "manifest.json",
            "Cargo.toml",
            "scripts\iris_release_workspace.ps1",
            "scripts\package_windows_release.ps1",
            "scripts\package_windows_msix.ps1"
        )) {
        $markerPath = Join-Path $repository $identityMarker
        if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) {
            throw "Refusing to clean a release workspace outside an Iris repository; missing identity marker: $markerPath"
        }
    }

    $releaseRoot = [System.IO.Path]::GetFullPath((Join-Path $repository "release")).TrimEnd("\")
    $workspaceRoot = [System.IO.Path]::GetFullPath((Join-Path $releaseRoot $Workspace)).TrimEnd("\")
    if (
        (Split-Path -Parent $workspaceRoot) -ine $releaseRoot -or
        $workspaceRoot -ieq $releaseRoot -or
        $workspaceRoot -ieq $repository
    ) {
        throw "Refusing to clean a path outside the exact Iris release workspace: $workspaceRoot"
    }

    if (-not (Test-Path -LiteralPath $workspaceRoot)) {
        return
    }

    foreach ($boundary in @($repository, $releaseRoot, $workspaceRoot)) {
        $item = Get-Item -LiteralPath $boundary -Force -ErrorAction Stop
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing to recursively clean an Iris release path containing a reparse boundary: $boundary"
        }
    }
    if (-not (Test-Path -LiteralPath $workspaceRoot -PathType Container)) {
        throw "Iris release workspace is not a directory: $workspaceRoot"
    }

    # Walk one directory at a time so Windows PowerShell 5.1 can never follow a
    # junction while searching for reparse points.
    $pendingDirectories = New-Object System.Collections.Generic.Stack[string]
    $pendingDirectories.Push($workspaceRoot)
    $nestedReparsePoint = $null
    while ($pendingDirectories.Count -gt 0 -and -not $nestedReparsePoint) {
        $directory = $pendingDirectories.Pop()
        foreach ($child in @(Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop)) {
            $childPath = [System.IO.Path]::GetFullPath($child.FullName)
            if (-not $childPath.StartsWith($workspaceRoot + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Refusing to inspect a release-workspace entry outside its exact root: $childPath"
            }
            if (($child.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                $nestedReparsePoint = $child
                break
            }
            if ($child.PSIsContainer) {
                $pendingDirectories.Push($childPath)
            }
        }
    }
    if ($nestedReparsePoint) {
        throw "Refusing to recursively clean an Iris release workspace containing a reparse point: $($nestedReparsePoint.FullName)"
    }

    $lastFailure = $null
    for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
        try {
            Remove-Item -LiteralPath $workspaceRoot -Recurse -Force -ErrorAction Stop
            if (-not (Test-Path -LiteralPath $workspaceRoot)) {
                return
            }
            $lastFailure = "the directory still exists after Remove-Item returned"
        } catch {
            $lastFailure = $_.Exception.Message
        }

        if ($attempt -lt $RetryCount -and $RetryDelayMilliseconds -gt 0) {
            Start-Sleep -Milliseconds $RetryDelayMilliseconds
        }
    }

    throw (
        "Iris release workspace cleanup of $workspaceRoot failed " +
        "after $RetryCount attempts: $lastFailure. release\dist was preserved."
    )
}
