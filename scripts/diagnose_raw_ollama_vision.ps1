[CmdletBinding()]
param(
    [switch]$RequirePass,
    [switch]$PassThru,
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"

function Test-RawVisionCanaryResponse {
    param([Parameter(Mandatory = $true)][string]$Text)

    $normalized = (($Text.ToLowerInvariant() -replace "\s+", " ").Trim())
    return $normalized -match "^(?:a )?red circle[.!]?$"
}

if ($SelfTest) {
    foreach ($passing in @("red circle", "A red circle.", "  red`n circle!  ")) {
        if (-not (Test-RawVisionCanaryResponse -Text $passing)) {
            throw "Raw vision canary parser rejected a valid answer: $passing"
        }
    }
    foreach ($failing in @(
            "red rectangle",
            "This is not a red circle.",
            "I expected a red circle but see a rectangle.",
            "red circle and blue square",
            "round red object"
        )) {
        if (Test-RawVisionCanaryResponse -Text $failing) {
            throw "Raw vision canary parser accepted an invalid answer: $failing"
        }
    }
    Write-Host "Raw Ollama vision canary parser tests passed."
    return
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$manifest = Get-Content -LiteralPath (Join-Path $repoRoot "manifest.json") -Raw | ConvertFrom-Json
$model = [string]$manifest.vision_model_policy.model_id
$imagePath = Join-Path ([System.IO.Path]::GetTempPath()) ("iris-raw-vision-canary-" + [System.Guid]::NewGuid().ToString("N") + ".png")

try {
    $showBody = @{ model = $model } | ConvertTo-Json -Compress
    $show = Invoke-RestMethod `
        -Uri "http://127.0.0.1:11434/api/show" `
        -Method Post `
        -ContentType "application/json" `
        -Body $showBody `
        -TimeoutSec 30
    if (-not (@($show.capabilities) -contains "vision")) {
        throw "Configured Ollama model does not report vision capability: $model"
    }

    Add-Type -AssemblyName System.Drawing
    $bitmap = New-Object System.Drawing.Bitmap 512, 512
    try {
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.Clear([System.Drawing.Color]::White)
            $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::Red)
            $outline = New-Object System.Drawing.Pen ([System.Drawing.Color]::Black), 10
            try {
                $graphics.FillEllipse($brush, 96, 96, 320, 320)
                $graphics.DrawEllipse($outline, 96, 96, 320, 320)
            } finally {
                $outline.Dispose()
                $brush.Dispose()
            }
        } finally {
            $graphics.Dispose()
        }
        $bitmap.Save($imagePath, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $bitmap.Dispose()
    }

    $request = @{
        model = $model
        prompt = "What color and geometric shape is the single large object? Answer with the color and shape only."
        images = @([Convert]::ToBase64String([System.IO.File]::ReadAllBytes($imagePath)))
        stream = $false
        think = $false
        keep_alive = "10m"
        options = @{
            num_ctx = [int]$manifest.vision_model_policy.num_ctx_ceiling
            num_predict = 32
            temperature = 0.0
            top_k = 1
            top_p = 0.1
            seed = 7
        }
    }
    $response = Invoke-RestMethod `
        -Uri "http://127.0.0.1:11434/api/generate" `
        -Method Post `
        -ContentType "application/json" `
        -Body ($request | ConvertTo-Json -Depth 5 -Compress) `
        -TimeoutSec 120
    $responseText = ([string]$response.response).Trim()
    $passed = Test-RawVisionCanaryResponse -Text $responseText
    $status = if ($passed) { "PASS" } else { "BLOCKED" }
    $result = [pscustomobject]@{
        Status = $status
        Model = $model
        Response = $responseText
        VisionRoute = "separate_locked_local_model"
    }

    if ($passed) {
        Write-Host "Raw Ollama vision canary: PASS ($responseText)"
    } else {
        Write-Warning "Raw Ollama vision canary: BLOCKED because the exact locked visual runtime did not identify the canary ($responseText)"
        if ($RequirePass) {
            throw "Raw Ollama vision canary failed for $model`: $responseText"
        }
    }
    if ($PassThru) {
        Write-Output $result
    }
} finally {
    if (Test-Path -LiteralPath $imagePath -PathType Leaf) {
        Remove-Item -LiteralPath $imagePath -Force -ErrorAction SilentlyContinue
    }
}
