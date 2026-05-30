[CmdletBinding()]
param(
    [switch] $AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

function Get-Rel {
    param([string] $Path)

    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full.StartsWith($RepoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($RepoRoot.Length).TrimStart("\")
    }

    return $full
}

function Test-Ignored {
    param([string] $Path)

    $lower = [System.IO.Path]::GetFullPath($Path).ToLowerInvariant()

    if ($lower -match "\\\.git(\\|$)") { return $true }
    if ($lower -match "\\target(\\|$)") { return $true }
    if ($lower -match "\\scripts\\legacy(\\|$)") { return $true }
    if ($lower -match "\\\.iris-dev\\diagnostics(\\|$)") { return $true }
    if ($lower -match "\\\.venv(\\|$)") { return $true }
    if ($lower -match "\\site-packages(\\|$)") { return $true }
    if ($lower -match "\\onnxruntime(\\|$)") { return $true }

    return $false
}

$roots = @(
    ".iris-dev\tts\kokoro",
    ".iris-dev\kokoro",
    ".iris-dev\tts",
    "tts\kokoro",
    "models\kokoro",
    "assets\kokoro"
)

$scanRoots = @()

foreach ($root in $roots) {
    $full = Join-Path $RepoRoot $root
    if (Test-Path $full) {
        $scanRoots += (Resolve-Path $full).Path
    }
}

if ($scanRoots.Count -eq 0) {
    $scanRoots = @($RepoRoot)
}

$modelCandidates = @()
$voiceCandidates = @()

foreach ($root in $scanRoots) {
    Get-ChildItem -Path $root -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { -not (Test-Ignored $_.FullName) } |
        ForEach-Object {
            $name = $_.Name.ToLowerInvariant()
            $path = $_.FullName.ToLowerInvariant()

            if ($_.Extension -ieq ".onnx" -and ($name -match "kokoro" -or $path -match "\\kokoro\\")) {
                $score = 0
                if ($path -match "\\\.iris-dev\\tts\\kokoro\\") { $score += 1000 }
                if ($name -eq "kokoro-v1_0.onnx") { $score += 300 }
                if ($name -eq "kokoro-v1.0.onnx") { $score += 250 }
                if ($name -match "kokoro") { $score += 100 }

                $modelCandidates += [pscustomobject]@{
                    Path = $_.FullName
                    RelativePath = Get-Rel $_.FullName
                    Name = $_.Name
                    Size = $_.Length
                    Score = $score
                }
            }

            if ($_.Extension -in @(".bin", ".json", ".npz") -and ($name -match "voice|voices|kokoro")) {
                $score = 0
                if ($path -match "\\\.iris-dev\\tts\\kokoro\\") { $score += 1000 }
                if ($name -match "^voices.*\.bin$") { $score += 500 }
                if ($name -match "voice") { $score += 200 }
                if ($_.Extension -ieq ".bin") { $score += 100 }

                $voiceCandidates += [pscustomobject]@{
                    Path = $_.FullName
                    RelativePath = Get-Rel $_.FullName
                    Name = $_.Name
                    Size = $_.Length
                    Score = $score
                }
            }
        }
}

$model = $modelCandidates | Sort-Object Score, Size -Descending | Select-Object -First 1
$voices = $voiceCandidates | Sort-Object Score, Size -Descending | Select-Object -First 1

$result = [pscustomobject]@{
    ok = [bool]($model -and $voices)
    provider = "kokoro"
    repo_root = $RepoRoot
    model_path = if ($model) { $model.Path } else { $null }
    model_relative_path = if ($model) { $model.RelativePath } else { $null }
    voices_path = if ($voices) { $voices.Path } else { $null }
    voices_relative_path = if ($voices) { $voices.RelativePath } else { $null }
    model_candidate_count = $modelCandidates.Count
    voice_candidate_count = $voiceCandidates.Count
    scanned_roots = @($scanRoots | ForEach-Object { Get-Rel $_ })
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 8
} else {
    $result
}
