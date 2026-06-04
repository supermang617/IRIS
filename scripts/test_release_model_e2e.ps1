$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
Set-Location -LiteralPath $repoRoot
$originalLocation = (Get-Location).Path

$model = "huihui_ai/gemma-4-abliterated:e2b"
$zipPath = Join-Path $repoRoot "release\dist\iris-windows.zip"

function Require-File {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing required file: $Path"
    }
}

function Invoke-ReleaseRuntime {
    param(
        [Parameter(Mandatory = $true)][string]$Runtime,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Name
    )
    $output = & $Runtime @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $text = $output -join "`n"
    if ($exitCode -ne 0) {
        throw "$Name failed with exit code $exitCode`: $text"
    }
    if ($text.Contains("Local model unavailable:") -or $text.Contains("Local image probe unavailable:")) {
        throw "$Name did not reach the configured local model: $text"
    }
    [pscustomobject]@{
        Output = $text
    }
}

Require-File -Path $zipPath

$models = (& ollama list 2>&1) -join "`n"
if (-not $models.Contains($model)) {
    throw "Configured Ollama model is not available locally: $model"
}

$extractRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("iris-release-model-e2e-" + [System.Guid]::NewGuid().ToString("N"))
$imagePath = Join-Path ([System.IO.Path]::GetTempPath()) ("iris-release-model-e2e-red-circle-" + [System.Guid]::NewGuid().ToString("N") + ".png")

try {
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractRoot -Force
    $runtime = Join-Path $extractRoot "bin\iris-runtime.exe"
    $launcher = Join-Path $extractRoot "Start Iris.ps1"
    Require-File -Path $runtime
    Require-File -Path $launcher

    & $launcher --self-check | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Release launcher self-check failed with exit code $LASTEXITCODE"
    }

    $text = Invoke-ReleaseRuntime `
        -Runtime $runtime `
        -Arguments @("--ask", "Answer in one short sentence: what can Iris do right now with text and vision?") `
        -Name "release text ask"
    if (-not ($text.Output.ToLowerInvariant().Contains("text") -and $text.Output.ToLowerInvariant().Contains("vision"))) {
        throw "Text model response did not mention text and vision: $($text.Output)"
    }

    Add-Type -AssemblyName System.Drawing
    $bitmap = New-Object System.Drawing.Bitmap 256, 256
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.Clear([System.Drawing.Color]::White)
    $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::Red)
    $graphics.FillEllipse($brush, 64, 64, 128, 128)
    $brush.Dispose()
    $graphics.Dispose()
    $bitmap.Save($imagePath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()

    $vision = Invoke-ReleaseRuntime `
        -Runtime $runtime `
        -Arguments @("--image-probe", $imagePath, "What color and shape is centered in this image? Answer in five words or fewer.") `
        -Name "release image probe"
    if (-not $vision.Output.ToLowerInvariant().Contains("red")) {
        throw "Vision model response did not identify the red object: $($vision.Output)"
    }

    Write-Host "Release model E2E passed."
    Write-Host "Text response:"
    Write-Host $text.Output
    Write-Host "Vision response:"
    Write-Host $vision.Output
} finally {
    Set-Location -LiteralPath $originalLocation
    Remove-Item -LiteralPath $extractRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $imagePath -Force -ErrorAction SilentlyContinue
}
