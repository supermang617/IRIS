[CmdletBinding()]
param(
    [string]$Repo = "supermang617/IRIS",
    [Parameter(Mandatory = $true)][string]$Tag,
    [switch]$DeferBypassVerification
)

$ErrorActionPreference = "Stop"

if ($Tag -notmatch "^v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)$") {
    throw "Semantic tag protection requires a canonical vMAJOR.MINOR.PATCH tag."
}
if ($Repo -notmatch "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$") {
    throw "Repo must use the OWNER/REPOSITORY form."
}

$ghCommand = Get-Command gh -ErrorAction SilentlyContinue
if (-not $ghCommand) {
    throw "gh is required to verify semantic tag protection."
}
$gh = $ghCommand.Source

function Test-RefPattern {
    param(
        [Parameter(Mandatory = $true)][string]$Ref,
        [Parameter(Mandatory = $true)][string]$Pattern
    )

    if ($Pattern -ceq "~ALL") {
        return $true
    }
    $escaped = [regex]::Escape($Pattern)
    $regex = "^" + $escaped.Replace("\*", ".*").Replace("\?", ".") + "$"
    return [regex]::IsMatch(
        $Ref,
        $regex,
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    )
}

$rulesetsJson = & $gh api "repos/$Repo/rulesets?includes_parents=true"
if ($LASTEXITCODE -ne 0) {
    throw "Repository rulesets could not be read for $Repo."
}
$rulesets = @($rulesetsJson | ConvertFrom-Json)
$tagRef = "refs/tags/$Tag"
$matchingRulesets = New-Object System.Collections.Generic.List[object]
$deferredRulesets = New-Object System.Collections.Generic.List[object]

foreach ($summary in $rulesets) {
    if (
        [string]$summary.target -cne "tag" -or
        [string]$summary.enforcement -cne "active" -or
        [long]$summary.id -le 0
    ) {
        continue
    }

    $detailJson = & $gh api "repos/$Repo/rulesets/$([long]$summary.id)"
    if ($LASTEXITCODE -ne 0) {
        throw "Tag ruleset $($summary.id) could not be inspected."
    }
    $detail = $detailJson | ConvertFrom-Json
    if (
        [string]$detail.target -cne "tag" -or
        [string]$detail.enforcement -cne "active"
    ) {
        continue
    }

    $includes = @($detail.conditions.ref_name.include)
    $excludes = @($detail.conditions.ref_name.exclude)
    $included = @(
        $includes |
            Where-Object { Test-RefPattern -Ref $tagRef -Pattern ([string]$_) }
    ).Count -gt 0
    $excluded = @(
        $excludes |
            Where-Object { Test-RefPattern -Ref $tagRef -Pattern ([string]$_) }
    ).Count -gt 0
    if (-not $included -or $excluded) {
        continue
    }

    $ruleTypes = @($detail.rules | ForEach-Object { [string]$_.type })
    if ("update" -notin $ruleTypes -or "deletion" -notin $ruleTypes) {
        continue
    }

    $bypassProperty = $detail.PSObject.Properties["bypass_actors"]
    if ($null -eq $bypassProperty) {
        if ($DeferBypassVerification) {
            $deferredRulesets.Add($detail)
        }
        continue
    }
    if (@($bypassProperty.Value).Count -ne 0) {
        continue
    }
    $matchingRulesets.Add($detail)
}

if ($matchingRulesets.Count -eq 0 -and $deferredRulesets.Count -eq 0) {
    throw "No active, no-bypass tag ruleset prevents update and deletion of $tagRef."
}

if ($matchingRulesets.Count -gt 0) {
    $ids = @($matchingRulesets | ForEach-Object { [string]$_.id }) -join ", "
    Write-Host "Semantic tag protection verified for $tagRef with ruleset(s): $ids"
} else {
    $ids = @($deferredRulesets | ForEach-Object { [string]$_.id }) -join ", "
    Write-Host (
        "Semantic tag update/deletion protection verified for $tagRef with " +
        "ruleset(s) $ids; bypass actors are hidden from this read-only token " +
        "and must be verified by the owner-side publisher."
    )
}
