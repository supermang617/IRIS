$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$HermesPython = Join-Path $RepoRoot ".iris-runtime\hermes\.venv\Scripts\python.exe"

if (-not (Test-Path -LiteralPath $HermesPython)) {
    throw "The Iris-owned Hermes Python runtime is missing. Run scripts\provision_hermes_acp.ps1 first."
}

Push-Location $RepoRoot
try {
    & python -m unittest discover -s plugins/hermes_sidecar -p "test_*.py"
    if ($LASTEXITCODE -ne 0) {
        throw "Safe Hermes Python tests failed."
    }

    & python -m unittest discover -s plugins/memory/iris_broker -p "test_*.py"
    if ($LASTEXITCODE -ne 0) {
        throw "Iris memory broker Python tests failed."
    }

    & $HermesPython -W error::ResourceWarning -m unittest discover -s plugins/hermes_acp -p "test_*.py"
    if ($LASTEXITCODE -ne 0) {
        throw "Hermes ACP Python tests failed."
    }
}
finally {
    Pop-Location
}
