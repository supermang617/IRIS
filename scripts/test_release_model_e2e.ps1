param(
    [switch]$RequireDocumentImage
)

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

$showBody = @{ model = $model } | ConvertTo-Json -Compress
$show = Invoke-RestMethod -Uri "http://127.0.0.1:11434/api/show" -Method Post -ContentType "application/json" -Body $showBody -TimeoutSec 30
$capabilities = @($show.capabilities)
if (-not ($capabilities -contains "vision")) {
    throw "Configured Ollama model does not report vision capability from /api/show. Capabilities: $($capabilities -join ', ')"
}

$extractRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("iris-release-model-e2e-" + [System.Guid]::NewGuid().ToString("N"))
$imagePath = Join-Path ([System.IO.Path]::GetTempPath()) ("iris-release-model-e2e-red-circle-" + [System.Guid]::NewGuid().ToString("N") + ".png")
$documentImagePath = Join-Path ([System.IO.Path]::GetTempPath()) ("iris-release-model-e2e-document-" + [System.Guid]::NewGuid().ToString("N") + ".png")

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
        -Arguments @("--image-probe", $imagePath, "Look at the filled object, not the square image canvas. What color and shape is the filled object? Answer with exactly two words.") `
        -Name "release image probe"
    $visionText = $vision.Output.ToLowerInvariant()
    $shapeOk = $visionText.Contains("circle") -or $visionText.Contains("round") -or $visionText.Contains("rounded")
    if (-not ($visionText.Contains("red") -and $shapeOk)) {
        throw "Vision model response did not identify the red circular object: $($vision.Output)"
    }

    $documentBitmap = New-Object System.Drawing.Bitmap 640, 320
    $documentGraphics = [System.Drawing.Graphics]::FromImage($documentBitmap)
    $documentGraphics.Clear([System.Drawing.Color]::White)
    $font = New-Object System.Drawing.Font "Arial", 48, ([System.Drawing.FontStyle]::Bold)
    $blackBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::Black)
    $documentGraphics.DrawString("IRIS TEST 742", $font, $blackBrush, 48, 96)
    $blackBrush.Dispose()
    $font.Dispose()
    $documentGraphics.Dispose()
    $documentBitmap.Save($documentImagePath, [System.Drawing.Imaging.ImageFormat]::Png)
    $documentBitmap.Dispose()

    $documentVision = Invoke-ReleaseRuntime `
        -Runtime $runtime `
        -Arguments @("--image-probe", $documentImagePath, "Read the large text in this image. Answer with the text only.") `
        -Name "release document image probe"
    $documentText = $documentVision.Output.ToLowerInvariant()
    $documentPassed = $documentText.Contains("iris") -and $documentText.Contains("742")
    if ($RequireDocumentImage -and -not $documentPassed) {
        throw "Vision model response did not read the document image text: $($documentVision.Output)"
    }

    Write-Host "Release model E2E passed."
    Write-Host "Capabilities: $($capabilities -join ', ')"
    Write-Host "Text response:"
    Write-Host $text.Output
    Write-Host "Vision response:"
    Write-Host $vision.Output
    Write-Host "Document vision response:"
    Write-Host $documentVision.Output
    if (-not $documentPassed) {
        Write-Host "Document image OCR gate: BLOCKED. Rerun with -RequireDocumentImage to fail on this blocker."
    }
} finally {
    Set-Location -LiteralPath $originalLocation
    Remove-Item -LiteralPath $extractRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $imagePath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $documentImagePath -Force -ErrorAction SilentlyContinue
}
