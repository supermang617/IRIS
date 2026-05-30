param(
    [string] $Model,
    [int] $NumCtx = 8192,
    [int] $NumPredict = 96
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Model)) {
    throw "Missing -Model"
}

$Endpoint = "http://127.0.0.1:11434"

$body = @{
    model = $Model
    messages = @(
        @{
            role = "system"
            content = "You are Iris. Reply only with the final answer. Do not show reasoning, thinking, analysis, drafts, bullets, or explanations. Do not censor profanity with asterisks. Keep the reply under twenty words."
        },
        @{
            role = "user"
            content = "Can you say fuckin shit without using asterisks?"
        }
    )
    stream = $false
    think = $false
    options = @{
        num_ctx = $NumCtx
        num_predict = $NumPredict
        temperature = 0.2
        top_p = 0.8
        repeat_penalty = 1.1
    }
} | ConvertTo-Json -Depth 12

$response = Invoke-RestMethod `
    -Method Post `
    -Uri "$Endpoint/api/chat" `
    -ContentType "application/json" `
    -Body $body

$text = ""

if ($null -ne $response.message -and $null -ne $response.message.content) {
    $text = [string] $response.message.content
} elseif ($null -ne $response.response) {
    $text = [string] $response.response
}

$text = $text.Trim()
$text = [regex]::Replace($text, "(?is)<think>.*?</think>", "").Trim()

Write-Host ""
Write-Host "=== Bounded local model response ==="
Write-Host $text

if ([string]::IsNullOrWhiteSpace($text)) {
    throw "Bounded local model response was empty."
}

if ($text.Length -gt 240) {
    throw "Bounded local model response was too long."
}

if ($text -match "\*") {
    throw "Bounded local model response still contains an asterisk."
}

if ($text.ToLowerInvariant().Contains("thinking")) {
    throw "Bounded local model response exposed thinking text."
}

Write-Host ""
Write-Host "PASS: bounded local model smoke test passed"
