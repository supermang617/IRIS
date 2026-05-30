param(
    [string] $Prompt = "In one sentence, say hello as Iris and confirm you are running locally.",
    [switch] $DryRun,
    [switch] $NoSpeak,
    [int] $Rate = 0,
    [int] $Volume = 90
)

$ErrorActionPreference = "Stop"

Set-Location -Path "C:\Projects\IRIS"

if ($DryRun) {
    powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\ask_iris_local_speak.ps1" -DryRun
    if ($LASTEXITCODE -ne 0) { throw "text voice response dry-run failed" }
    return
}

powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\ask_iris_local_speak.ps1" -Prompt $Prompt -NoSpeak:$NoSpeak -Rate $Rate -Volume $Volume
if ($LASTEXITCODE -ne 0) {
    throw "Iris text voice response test failed"
}
