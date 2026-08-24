param(
    [switch]$RequireDocumentImage
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
Set-Location -LiteralPath $repoRoot
$originalLocation = (Get-Location).Path

$sourceManifest = Get-Content -LiteralPath (Join-Path $repoRoot "manifest.json") -Raw | ConvertFrom-Json
$model = [string]$sourceManifest.model_policy.model_id
$zipPath = Join-Path $repoRoot "release\dist\iris-windows.zip"
$rawVisionCanaryPath = Join-Path $repoRoot "scripts\diagnose_raw_ollama_vision.ps1"

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
Require-File -Path $rawVisionCanaryPath

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
$rawVisionCanary = @(
    @(& $rawVisionCanaryPath -PassThru) |
        Where-Object { $_.PSObject.Properties.Name -contains "Status" }
)
if ($rawVisionCanary.Count -ne 1 -or $rawVisionCanary[0].Status -notin @("PASS", "BLOCKED")) {
    throw "Raw Ollama vision canary did not return one valid status."
}
$rawVisionStatus = [string]$rawVisionCanary[0].Status

$extractRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("iris-release-model-e2e-" + [System.Guid]::NewGuid().ToString("N"))
$imagePath = Join-Path ([System.IO.Path]::GetTempPath()) ("iris-release-model-e2e-red-circle-" + [System.Guid]::NewGuid().ToString("N") + ".png")
$documentImagePath = Join-Path ([System.IO.Path]::GetTempPath()) ("iris-release-model-e2e-document-" + [System.Guid]::NewGuid().ToString("N") + ".png")

try {
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractRoot -Force
    $runtime = Join-Path $extractRoot "bin\iris-runtime.exe"
    $launcher = Join-Path $extractRoot "Start Iris.ps1"
    $documentOcrScript = Join-Path $extractRoot "Iris Document OCR.ps1"
    $releaseManifestPath = Join-Path $extractRoot "manifest.json"
    Require-File -Path $runtime
    Require-File -Path $launcher
    Require-File -Path $documentOcrScript
    Require-File -Path $releaseManifestPath
    $releaseManifest = Get-Content -LiteralPath $releaseManifestPath -Raw | ConvertFrom-Json
    if ([string]$releaseManifest.project.version -ne [string]$sourceManifest.project.version) {
        throw "Release package version $($releaseManifest.project.version) does not match source version $($sourceManifest.project.version). Rebuild it with scripts/package_windows_release.ps1 before E2E testing."
    }
    if ([string]$releaseManifest.model_policy.model_id -ne $model) {
        throw "Release package is stale. Rebuild it with scripts/package_windows_release.ps1 before E2E testing."
    }

    & $launcher -SelfCheck | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Release launcher self-check failed with exit code $LASTEXITCODE"
    }

    $text = Invoke-ReleaseRuntime `
        -Runtime $runtime `
        -Arguments @("--ask", "Reply with exactly: IRIS MODEL READY") `
        -Name "release text ask"
    $textOutput = $text.Output.ToLowerInvariant()
    if (-not ($textOutput.Contains("iris") -and $textOutput.Contains("model") -and $textOutput.Contains("ready"))) {
        throw "Text model readiness response was unexpected: $($text.Output)"
    }

    Add-Type -AssemblyName System.Drawing
    $bitmap = New-Object System.Drawing.Bitmap 512, 512
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.Clear([System.Drawing.Color]::White)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::Red)
    $outline = New-Object System.Drawing.Pen ([System.Drawing.Color]::Black), 10
    $graphics.FillEllipse($brush, 96, 96, 320, 320)
    $graphics.DrawEllipse($outline, 96, 96, 320, 320)
    $outline.Dispose()
    $brush.Dispose()
    $graphics.Dispose()
    $bitmap.Save($imagePath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()

    $vision = Invoke-ReleaseRuntime `
        -Runtime $runtime `
        -Arguments @("--image-probe", $imagePath, "What color and geometric shape is the single large object? Answer with the color and shape only.") `
        -Name "release image probe"
    $visionText = $vision.Output.ToLowerInvariant()
    $shapeOk = $visionText.Contains("circle") -or $visionText.Contains("round") -or $visionText.Contains("rounded")
    if (-not ($visionText.Contains("red") -and $shapeOk)) {
        throw "Vision response did not identify the red circular object: $($vision.Output)"
    }

    $boundedVision = Invoke-ReleaseRuntime `
        -Runtime $runtime `
        -Arguments @("--image-probe", $imagePath, "Describe the mood and scene in this image.") `
        -Name "release bounded image probe"
    $boundedVisionText = $boundedVision.Output.ToLowerInvariant()
    if ($rawVisionStatus -ne "PASS") {
        throw "The exact locked Qwen visual route failed its raw projector canary."
    }
    if ($boundedVisionText.Contains("known projector defect") -or
        $boundedVisionText.Contains("local image probe unavailable")) {
        throw "The release runtime did not use the verified Qwen route for broad visual inference: $($boundedVision.Output)"
    }

    $documentBitmap = New-Object System.Drawing.Bitmap 1000, 360
    $documentGraphics = [System.Drawing.Graphics]::FromImage($documentBitmap)
    $documentGraphics.Clear([System.Drawing.Color]::White)
    $documentGraphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::SingleBitPerPixelGridFit
    $font = New-Object System.Drawing.Font "Consolas", 72, ([System.Drawing.FontStyle]::Bold)
    $blackBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::Black)
    $documentGraphics.DrawString("IRIS 742", $font, $blackBrush, 80, 100)
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
    Write-Host "Release model E2E passed."
    Write-Host "Capabilities: $($capabilities -join ', ')"
    Write-Host "Raw Ollama vision canary: $rawVisionStatus"
    Write-Host "Text response:"
    Write-Host $text.Output
    Write-Host "Vision response:"
    Write-Host $vision.Output
    Write-Host "Document vision response:"
    Write-Host $documentVision.Output
    if (-not $documentPassed) {
        Write-Host "Ollama document OCR diagnostic: BLOCKED. Tesseract OCR is the document-image gate."
    }

    $documentOcrOutput = & $documentOcrScript -ImagePath $documentImagePath 2>&1
    $documentOcrExit = $LASTEXITCODE
    $documentOcrTextRaw = $documentOcrOutput -join "`n"
    if ($documentOcrExit -ne 0) {
        throw "release document OCR failed with exit code $documentOcrExit`: $documentOcrTextRaw"
    }
    $documentOcrText = $documentOcrTextRaw.ToLowerInvariant()
    $documentOcrPassed = $documentOcrText.Contains("iris") -and $documentOcrText.Contains("742")
    if (-not $documentOcrPassed) {
        throw "Tesseract document OCR response did not read the document image text: $documentOcrTextRaw"
    }
    if ($RequireDocumentImage -and -not $documentOcrPassed) {
        throw "Document-image OCR gate failed: $documentOcrTextRaw"
    }
    Write-Host "Document OCR response:"
    Write-Host $documentOcrTextRaw
} finally {
    Set-Location -LiteralPath $originalLocation
    Remove-Item -LiteralPath $extractRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $imagePath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $documentImagePath -Force -ErrorAction SilentlyContinue
}
