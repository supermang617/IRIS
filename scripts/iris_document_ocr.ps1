param(
    [Parameter(Mandatory = $true)][string]$ImagePath
)

$ErrorActionPreference = "Stop"

function Find-Tesseract {
    if ($env:IRIS_TESSERACT_EXE -and (Test-Path -LiteralPath $env:IRIS_TESSERACT_EXE -PathType Leaf)) {
        return $env:IRIS_TESSERACT_EXE
    }
    $command = Get-Command "tesseract" -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }
    foreach ($candidate in @(
            "C:\Program Files\Tesseract-OCR\tesseract.exe",
            "C:\Program Files (x86)\Tesseract-OCR\tesseract.exe"
        )) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }
    return $null
}

function Require-DocumentImage {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Document OCR image does not exist: $Path"
    }
    $extension = [System.IO.Path]::GetExtension($Path).TrimStart(".").ToLowerInvariant()
    if ($extension -notin @("png", "jpg", "jpeg", "tif", "tiff", "bmp", "webp")) {
        throw "Document OCR supports png, jpg, jpeg, tif, tiff, bmp, and webp files."
    }
    if ((Get-Item -LiteralPath $Path).Length -eq 0) {
        throw "Document OCR requires a non-empty image."
    }
}

$resolvedImage = (Resolve-Path -LiteralPath $ImagePath).Path
Require-DocumentImage -Path $resolvedImage

$tesseract = Find-Tesseract
if (-not $tesseract) {
    throw "Tesseract OCR was not found. Install Tesseract locally, then rerun this script."
}

$output = & $tesseract $resolvedImage stdout --psm 6 -l eng 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Tesseract OCR failed with exit code $LASTEXITCODE`: $($output -join "`n")"
}

$text = (($output -join "`n").Trim())
if (-not $text) {
    throw "Tesseract OCR returned no text."
}

Write-Output "OCR text (untrusted evidence):"
Write-Output $text
