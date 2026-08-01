[CmdletBinding()]
param(
    [string]$Repo = "supermang617/IRIS",
    [Parameter(Mandatory = $true)][string]$Tag,
    [Parameter(Mandatory = $true)][string]$ExpectedCommit,
    [Parameter(Mandatory = $true)][long]$ReleaseRunId,
    [Parameter(Mandatory = $true)][string]$ExpectedPublisher,
    [Parameter(Mandatory = $true)][string]$ExpectedSignerThumbprint,
    [Parameter(Mandatory = $true)][string]$LifecycleEvidencePath,
    [Parameter(Mandatory = $true)][string]$WackReportPath,
    [ValidateRange(1, 168)][int]$MaximumEvidenceAgeHours = 168
)

$ErrorActionPreference = "Stop"

if ($Tag -notmatch "^v(?<major>0|[1-9][0-9]*)\.(?<minor>0|[1-9][0-9]*)\.(?<patch>0|[1-9][0-9]*)$") {
    throw "Publication requires an immutable semantic tag such as v1.0.0."
}
$packageVersion = "$($Matches.major).$($Matches.minor).$($Matches.patch)"
foreach ($component in @($Matches.major, $Matches.minor, $Matches.patch)) {
    if ([uint64]$component -gt 65535) {
        throw "Every release version component must fit the MSIX range 0-65535."
    }
}
$msixVersion = "$packageVersion.0"
$releaseName = "Iris $packageVersion $([char]0x2014) Local-First Windows AI Assistant"
$releaseBodyPrefix = "Iris $packageVersion is a local-first Windows AI assistant"
if ($ExpectedCommit -notmatch "^[a-fA-F0-9]{40}$") {
    throw "ExpectedCommit must be the full 40-character Git commit for the semantic tag."
}
$ExpectedCommit = $ExpectedCommit.ToLowerInvariant()
if ($ReleaseRunId -le 0) {
    throw "ReleaseRunId must identify the exact successful protected release workflow run."
}
if (-not $ExpectedPublisher.Trim() -or $ExpectedPublisher -match "[\r\n]") {
    throw "ExpectedPublisher must be the exact single-line production certificate subject."
}
if ($ExpectedSignerThumbprint -notmatch "^[a-fA-F0-9]{40}$") {
    throw "ExpectedSignerThumbprint must contain exactly 40 hexadecimal characters."
}
$ExpectedSignerThumbprint = $ExpectedSignerThumbprint.ToLowerInvariant()

function Require-Command {
    param([Parameter(Mandatory = $true)][string]$Name)
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "$Name is required to publish the GitHub release."
    }
    return $command.Source
}

function Get-VerifiedWackReport {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolved = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        throw "External WACK report is missing: $resolved"
    }
    $item = Get-Item -LiteralPath $resolved
    if ($item.Length -le 0 -or $item.Length -gt 32MB) {
        throw "External WACK report is empty or exceeds the 32 MiB evidence bound: $resolved"
    }

    $settings = New-Object System.Xml.XmlReaderSettings
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $reader = $null
    try {
        $reader = [System.Xml.XmlReader]::Create($resolved, $settings)
        $document = New-Object System.Xml.XmlDocument
        $document.XmlResolver = $null
        $document.Load($reader)
    } catch {
        throw "External WACK report is not safe, valid XML: $($_.Exception.Message)"
    } finally {
        if ($reader) {
            $reader.Dispose()
        }
    }
    if ([string]$document.REPORT.OVERALL_RESULT -cne "PASS") {
        throw "External WACK report did not record REPORT.OVERALL_RESULT=PASS."
    }

    return [pscustomobject]@{
        Path = $resolved
        Length = [int64]$item.Length
        LastWriteUtc = [DateTimeOffset]$item.LastWriteTimeUtc
        Sha256 = (
            Get-FileHash -LiteralPath $resolved -Algorithm SHA256
        ).Hash.ToLowerInvariant()
    }
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$verifier = Join-Path $repoRoot "scripts\test_github_versioned_release.ps1"
$tagProtectionVerifier = Join-Path $repoRoot "scripts\test_github_semantic_tag_protection.ps1"
if (-not (Test-Path -LiteralPath $verifier -PathType Leaf)) {
    throw "Versioned release verifier is missing: $verifier"
}
if (-not (Test-Path -LiteralPath $tagProtectionVerifier -PathType Leaf)) {
    throw "Semantic tag protection verifier is missing: $tagProtectionVerifier"
}
$gh = Require-Command -Name "gh"

$repositoryJson = & $gh api "repos/$Repo"
if ($LASTEXITCODE -ne 0) {
    throw "The GitHub repository metadata could not be verified before publication."
}
$repository = $repositoryJson | ConvertFrom-Json
$repositoryOwner = ([string]$repository.owner.login).Trim()
if (-not $repositoryOwner) {
    throw "The GitHub repository owner could not be resolved."
}

& $tagProtectionVerifier -Repo $Repo -Tag $Tag

$immutableJson = & $gh api "repos/$Repo/immutable-releases"
if ($LASTEXITCODE -ne 0) {
    throw "Immutable releases are disabled or the current credential lacks repository administration read access."
}
$immutableSettings = $immutableJson | ConvertFrom-Json
if (-not $immutableSettings.enabled) {
    throw "GitHub release immutability must be enabled before a draft can be published."
}

$branchProtectionJson = & $gh api "repos/$Repo/branches/main/protection"
if ($LASTEXITCODE -ne 0) {
    throw "The protected main branch could not be verified before publication."
}
$branchProtection = $branchProtectionJson | ConvertFrom-Json
if (-not $branchProtection.required_status_checks -or
    @($branchProtection.required_status_checks.contexts).Count -eq 0 -or
    -not $branchProtection.required_status_checks.strict -or
    -not $branchProtection.required_pull_request_reviews -or
    -not $branchProtection.required_conversation_resolution.enabled -or
    -not $branchProtection.enforce_admins.enabled -or
    $branchProtection.allow_force_pushes.enabled -or
    $branchProtection.allow_deletions.enabled) {
    throw "Main must require pull requests, resolved conversations, and up-to-date status checks for administrators while blocking force pushes and deletion."
}

$checkRunsJson = & $gh api --paginate --slurp "repos/$Repo/commits/$ExpectedCommit/check-runs?per_page=100"
if ($LASTEXITCODE -ne 0) {
    throw "GitHub check runs for the release commit could not be verified."
}
$checkRunPages = @(($checkRunsJson -join "`n") | ConvertFrom-Json)
$checkRuns = @(
    $checkRunPages |
        ForEach-Object { @($_.check_runs) }
)
if (
    $checkRunPages.Count -eq 0 -or
    $checkRuns.Count -ne [int]$checkRunPages[0].total_count
) {
    throw "GitHub check-run pagination was incomplete."
}
$commitStatusJson = & $gh api --paginate --slurp "repos/$Repo/commits/$ExpectedCommit/status?per_page=100"
if ($LASTEXITCODE -ne 0) {
    throw "GitHub commit statuses for the release commit could not be verified."
}
$commitStatusPages = @(($commitStatusJson -join "`n") | ConvertFrom-Json)
$commitStatuses = @(
    $commitStatusPages |
        ForEach-Object { @($_.statuses) }
)
if (
    $commitStatusPages.Count -eq 0 -or
    $commitStatuses.Count -ne [int]$commitStatusPages[0].total_count
) {
    throw "GitHub commit-status pagination was incomplete."
}
foreach ($context in @($branchProtection.required_status_checks.contexts)) {
    $matchingRequiredChecks = @(
        @($branchProtection.required_status_checks.checks) |
            Where-Object { [string]$_.context -ceq [string]$context }
    )
    $boundAppIds = @(
        $matchingRequiredChecks |
            ForEach-Object {
                if ($null -ne $_.app_id -and [long]$($_.app_id) -gt 0) {
                    [long]$($_.app_id)
                }
            } |
            Select-Object -Unique
    )
    if ($boundAppIds.Count -gt 1) {
        throw "Required main status '$context' is ambiguously bound to multiple GitHub Apps."
    }
    $requiredAppId = if ($boundAppIds.Count -eq 1) {
        [long]$boundAppIds[0]
    } else {
        [long]0
    }

    $resultCandidates = New-Object System.Collections.Generic.List[object]
    foreach ($checkRun in @(
            $checkRuns |
                Where-Object {
                    [string]$_.name -ceq [string]$context -and
                    (
                        $requiredAppId -eq 0 -or
                        [long]$($_.app.id) -eq $requiredAppId
                    )
                }
        )) {
        $timestampText = @(
            [string]$checkRun.completed_at,
            [string]$checkRun.updated_at,
            [string]$checkRun.created_at,
            [string]$checkRun.started_at
        ) | Where-Object { $_ } | Select-Object -First 1
        $sortTime = [DateTimeOffset]::MinValue
        if ($timestampText) {
            $parsedTime = [DateTimeOffset]::MinValue
            if ([DateTimeOffset]::TryParse(
                    [string]$timestampText,
                    [ref]$parsedTime
                )) {
                $sortTime = $parsedTime
            }
        }
        $resultCandidates.Add([pscustomobject]@{
                Source = "check-run"
                SortTime = $sortTime
                SortId = [long]$checkRun.id
                Successful = (
                    [string]$checkRun.status -ceq "completed" -and
                    [string]$checkRun.conclusion -ceq "success"
                )
            })
    }
    if ($requiredAppId -eq 0) {
        foreach ($commitStatus in @(
                $commitStatuses |
                    Where-Object {
                        [string]$_.context -ceq [string]$context
                    }
            )) {
            $timestampText = @(
                [string]$commitStatus.completed_at,
                [string]$commitStatus.updated_at,
                [string]$commitStatus.created_at
            ) | Where-Object { $_ } | Select-Object -First 1
            $sortTime = [DateTimeOffset]::MinValue
            if ($timestampText) {
                $parsedTime = [DateTimeOffset]::MinValue
                if ([DateTimeOffset]::TryParse(
                        [string]$timestampText,
                        [ref]$parsedTime
                    )) {
                    $sortTime = $parsedTime
                }
            }
            $resultCandidates.Add([pscustomobject]@{
                    Source = "commit-status"
                    SortTime = $sortTime
                    SortId = [long]$commitStatus.id
                    Successful = ([string]$commitStatus.state -ceq "success")
                })
        }
    }
    $latestRequiredResult = @(
        $resultCandidates |
            Sort-Object -Property @(
                @{ Expression = { $_.SortTime }; Descending = $true },
                @{ Expression = { $_.SortId }; Descending = $true }
            ) |
            Select-Object -First 1
    )
    if (
        $latestRequiredResult.Count -ne 1 -or
        -not $latestRequiredResult[0].Successful
    ) {
        $appBinding = if ($requiredAppId -gt 0) {
            " bound to GitHub App $requiredAppId"
        } else {
            ""
        }
        throw "Required main status '$context'$appBinding has no result or its latest result is not successful for $ExpectedCommit."
    }
}

$environmentJson = & $gh api "repos/$Repo/environments/iris-production-release"
if ($LASTEXITCODE -ne 0) {
    throw "The protected iris-production-release environment could not be verified."
}
$environment = $environmentJson | ConvertFrom-Json
$reviewerRules = @(
    $environment.protection_rules |
        Where-Object {
            [string]$_.type -eq "required_reviewers" -and
            @($_.reviewers).Count -gt 0
        }
)
$configuredReviewers = @(
    $reviewerRules |
        ForEach-Object { @($_.reviewers) }
)
if (
    $reviewerRules.Count -ne 1 -or
    $configuredReviewers.Count -ne 1 -or
    [string]$configuredReviewers[0].type -cne "User" -or
    [string]$configuredReviewers[0].reviewer.login -ine $repositoryOwner
) {
    throw (
        "The iris-production-release environment must have exactly one required " +
        "reviewer: repository owner '$repositoryOwner' as a User."
    )
}
if (
    -not $environment.deployment_branch_policy -or
    -not $environment.deployment_branch_policy.protected_branches -or
    $environment.deployment_branch_policy.custom_branch_policies
) {
    throw "The production signing environment must permit protected branches only."
}

$environmentSecretsJson = & $gh api --paginate --slurp "repos/$Repo/environments/iris-production-release/secrets?per_page=100"
if ($LASTEXITCODE -ne 0) {
    throw "Production environment secret scope could not be verified."
}
$environmentSecretPages = @(($environmentSecretsJson -join "`n") | ConvertFrom-Json)
$environmentSecrets = @(
    $environmentSecretPages |
        ForEach-Object { @($_.secrets) }
)
if (
    $environmentSecretPages.Count -eq 0 -or
    $environmentSecrets.Count -ne [int]$environmentSecretPages[0].total_count
) {
    throw "Production environment secret pagination was incomplete."
}
$environmentSecretNames = @(
    $environmentSecrets |
        ForEach-Object { [string]$_.name }
)
$repositorySecretsJson = & $gh api --paginate --slurp "repos/$Repo/actions/secrets?per_page=100"
if ($LASTEXITCODE -ne 0) {
    throw "Repository secret scope could not be verified."
}
$repositorySecretPages = @(($repositorySecretsJson -join "`n") | ConvertFrom-Json)
$repositorySecrets = @(
    $repositorySecretPages |
        ForEach-Object { @($_.secrets) }
)
if (
    $repositorySecretPages.Count -eq 0 -or
    $repositorySecrets.Count -ne [int]$repositorySecretPages[0].total_count
) {
    throw "Repository secret pagination was incomplete."
}
$repositorySecretNames = @(
    $repositorySecrets |
        ForEach-Object { [string]$_.name }
)
foreach ($secretName in @(
        "IRIS_SIGNING_PFX_BASE64",
        "IRIS_SIGNING_PFX_PASSWORD",
        "IRIS_MSIX_PUBLISHER"
    )) {
    if ($secretName -notin $environmentSecretNames) {
        throw "Required production secret '$secretName' is absent from iris-production-release."
    }
    if ($secretName -in $repositorySecretNames) {
        throw "Production secret '$secretName' must not exist at repository scope."
    }
}

$environmentVariablesJson = & $gh api --paginate --slurp "repos/$Repo/environments/iris-production-release/variables?per_page=100"
if ($LASTEXITCODE -ne 0) {
    throw "Production environment variables could not be verified."
}
$environmentVariablePages = @(($environmentVariablesJson -join "`n") | ConvertFrom-Json)
$environmentVariables = @(
    $environmentVariablePages |
        ForEach-Object { @($_.variables) }
)
if (
    $environmentVariablePages.Count -eq 0 -or
    $environmentVariables.Count -ne [int]$environmentVariablePages[0].total_count
) {
    throw "Production environment variable pagination was incomplete."
}
$gateVariables = @(
    $environmentVariables |
        Where-Object {
            [string]$_.name -ceq "IRIS_PRODUCTION_GATE_CONFIGURED" -and
            [string]$_.value -ceq "true"
        }
)
$repositoryVariablesJson = & $gh api --paginate --slurp "repos/$Repo/actions/variables?per_page=100"
if ($LASTEXITCODE -ne 0) {
    throw "Repository variable scope could not be verified."
}
$repositoryVariablePages = @(($repositoryVariablesJson -join "`n") | ConvertFrom-Json)
$repositoryVariables = @(
    $repositoryVariablePages |
        ForEach-Object { @($_.variables) }
)
if (
    $repositoryVariablePages.Count -eq 0 -or
    $repositoryVariables.Count -ne [int]$repositoryVariablePages[0].total_count
) {
    throw "Repository variable pagination was incomplete."
}
$repositoryVariableNames = @(
    $repositoryVariables |
        ForEach-Object { [string]$_.name }
)
if (
    $gateVariables.Count -ne 1 -or
    "IRIS_PRODUCTION_GATE_CONFIGURED" -in $repositoryVariableNames
) {
    throw "IRIS_PRODUCTION_GATE_CONFIGURED=true must exist only in the protected production environment."
}

$releaseWorkflowJson = & $gh api "repos/$Repo/actions/workflows/release.yml"
if ($LASTEXITCODE -ne 0) {
    throw "The canonical .github/workflows/release.yml workflow could not be verified."
}
$releaseWorkflow = $releaseWorkflowJson | ConvertFrom-Json
if (
    [long]$releaseWorkflow.id -le 0 -or
    [string]$releaseWorkflow.path -cne ".github/workflows/release.yml" -or
    [string]$releaseWorkflow.state -cne "active"
) {
    throw "The canonical release.yml workflow is missing, inactive, or has an unexpected identity."
}

$releaseRunJson = & $gh run view $ReleaseRunId `
    --repo $Repo `
    --json attempt,conclusion,createdAt,databaseId,event,headBranch,headSha,jobs,status,url,workflowDatabaseId,workflowName
if ($LASTEXITCODE -ne 0) {
    throw "The exact protected release workflow run could not be verified."
}
$releaseRun = $releaseRunJson | ConvertFrom-Json
if (
    [long]$releaseRun.databaseId -ne $ReleaseRunId -or
    [long]$releaseRun.workflowDatabaseId -ne [long]$releaseWorkflow.id -or
    [string]$releaseRun.workflowName -cne "Release" -or
    [string]$releaseRun.headSha -cne $ExpectedCommit -or
    [string]$releaseRun.headBranch -cne "main" -or
    [string]$releaseRun.event -cne "workflow_dispatch" -or
    [string]$releaseRun.status -cne "completed" -or
    [string]$releaseRun.conclusion -cne "success" -or
    [int]$releaseRun.attempt -le 0
) {
    throw "ReleaseRunId does not identify a successful release.yml dispatch on the expected main commit."
}
$releaseJobs = @($releaseRun.jobs)
foreach ($jobName in @(
        "Build and test unsigned Windows payload",
        "Sign verified Windows artifacts",
        "Create and verify private draft"
    )) {
    $successfulJob = @(
        $releaseJobs |
            Where-Object {
                [string]$_.name -ceq $jobName -and
                [string]$_.conclusion -ceq "success"
            }
    )
    if ($successfulJob.Count -ne 1) {
        throw "Protected release workflow job '$jobName' was not successful for $ExpectedCommit."
    }
}

$approvalsJson = & $gh api "repos/$Repo/actions/runs/$ReleaseRunId/approvals"
if ($LASTEXITCODE -ne 0) {
    throw "Protected-environment approval history could not be verified for ReleaseRunId."
}
$approvals = @($approvalsJson | ConvertFrom-Json)
$ownerApprovals = @(
    $approvals |
        Where-Object {
            [string]$_.state -ceq "approved" -and
            [string]$_.user.login -ieq $repositoryOwner -and
            @(
                $_.environments |
                    Where-Object {
                        [string]$_.name -ceq "iris-production-release"
                    }
            ).Count -gt 0
        }
)
if ($ownerApprovals.Count -eq 0) {
    throw "The exact signing run lacks recorded owner approval for iris-production-release."
}

$evidencePath = [System.IO.Path]::GetFullPath($LifecycleEvidencePath)
if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
    throw "Clean-VM lifecycle evidence is missing: $evidencePath"
}
$wackReport = Get-VerifiedWackReport -Path $WackReportPath
try {
    $evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
} catch {
    throw "Clean-VM lifecycle evidence is not valid JSON: $($_.Exception.Message)"
}

foreach ($field in @(
        "test_context_id",
        "tested_utc",
        "virtual_machine",
        "package_identity",
        "package_family_name",
        "application_id",
        "app_user_model_id",
        "publisher",
        "signer_thumbprint",
        "release_version",
        "release_sha256",
        "wack_package_sha256",
        "wack_overall_result",
        "wack_report_sha256",
        "wack_report_length_bytes",
        "state_probe_sha256",
        "state_probe_content_base64"
    )) {
    $property = $evidence.PSObject.Properties[$field]
    if (-not $property -or -not ([string]$property.Value).Trim()) {
        throw "Clean-VM lifecycle evidence is missing '$field'."
    }
}
if ([int]$evidence.schema -ne 3) {
    throw "Unsupported clean-VM lifecycle evidence schema: $($evidence.schema)"
}
$virtualMachine = ([string]$evidence.virtual_machine).Trim()
if (
    -not $virtualMachine -or
    $virtualMachine.Length -gt 200 -or
    $virtualMachine -match "[\x00-\x1f\x7f]"
) {
    throw "Clean-VM lifecycle evidence has an invalid virtual-machine identity."
}
if ([string]$evidence.test_context_id -notmatch "^iris-disposable-guest-[0-9a-fA-F]{32}$") {
    throw "Clean-VM lifecycle evidence has an invalid test context."
}
if ([string]$evidence.package_identity -cne "ProjectIris.LocalAssistant") {
    throw "Clean-VM lifecycle evidence has the wrong MSIX package identity."
}
if ([string]$evidence.application_id -cne "Iris") {
    throw "Clean-VM lifecycle evidence has the wrong registered application id."
}
if ([string]$evidence.package_family_name -notmatch "^ProjectIris\.LocalAssistant_[A-Za-z0-9]+$") {
    throw "Clean-VM lifecycle evidence has an invalid package family name."
}
if (
    [string]$evidence.app_user_model_id -cne
    "$([string]$evidence.package_family_name)!$([string]$evidence.application_id)"
) {
    throw "Clean-VM lifecycle evidence does not identify the registered Iris application."
}
if ([string]$evidence.release_version -cne $msixVersion) {
    throw "Lifecycle release version '$($evidence.release_version)' does not match $Tag ($msixVersion)."
}
foreach ($field in @(
        "release_sha256",
        "state_probe_sha256",
        "wack_package_sha256",
        "wack_report_sha256"
    )) {
    if ([string]$evidence.$field -notmatch "^[a-fA-F0-9]{64}$") {
        throw "Clean-VM lifecycle evidence has an invalid '$field'."
    }
}
if ([string]$evidence.wack_overall_result -cne "PASS") {
    throw "Clean-VM lifecycle evidence does not prove WACK REPORT.OVERALL_RESULT=PASS."
}
if (
    ([string]$evidence.wack_package_sha256).ToLowerInvariant() -cne
    ([string]$evidence.release_sha256).ToLowerInvariant()
) {
    throw "Clean-VM lifecycle evidence does not bind WACK to the exact tested MSIX."
}
if (
    [long]$evidence.wack_report_length_bytes -ne $wackReport.Length -or
    $wackReport.Sha256 -cne
        ([string]$evidence.wack_report_sha256).ToLowerInvariant()
) {
    throw "External WACK report does not match the report bound into clean-VM lifecycle evidence."
}
if ([string]$evidence.signer_thumbprint -notmatch "^[a-fA-F0-9]{40}$") {
    throw "Clean-VM lifecycle evidence has an invalid signer thumbprint."
}
if ([string]$evidence.publisher -cne $ExpectedPublisher) {
    throw "Clean-VM lifecycle evidence does not match ExpectedPublisher."
}
if (
    ([string]$evidence.signer_thumbprint).ToLowerInvariant() -cne
    $ExpectedSignerThumbprint
) {
    throw "Clean-VM lifecycle evidence does not match ExpectedSignerThumbprint."
}
foreach ($field in @(
        "install_succeeded",
        "activation_succeeded",
        "uninstall_succeeded",
        "state_survived"
    )) {
    if ($evidence.$field -ne $true) {
        throw "Clean-VM lifecycle evidence does not prove '$field'."
    }
}
if ([string]$evidence.state_root -cne "%LOCALAPPDATA%\Iris") {
    throw "Clean-VM lifecycle evidence does not identify the canonical Iris state root."
}

try {
    $probeBytes = [Convert]::FromBase64String(
        [string]$evidence.state_probe_content_base64
    )
} catch {
    throw "Clean-VM lifecycle evidence contains an invalid encoded Iris state probe."
}
if ($probeBytes.Length -le 0 -or $probeBytes.Length -gt 8192) {
    throw "Clean-VM lifecycle state probe is empty or exceeds the evidence bound."
}
$probeSha = [System.Security.Cryptography.SHA256]::Create()
try {
    $probeHash = (
        [System.BitConverter]::ToString($probeSha.ComputeHash($probeBytes))
    ).Replace("-", "").ToLowerInvariant()
} finally {
    $probeSha.Dispose()
}
if (
    $probeHash -cne
    ([string]$evidence.state_probe_sha256).ToLowerInvariant()
) {
    throw "Clean-VM lifecycle state-probe content does not match its hash."
}
try {
    $probe = (
        [System.Text.Encoding]::UTF8.GetString($probeBytes) |
            ConvertFrom-Json
    )
} catch {
    throw "Clean-VM lifecycle state-probe content is not valid JSON."
}
if (
    [int]$probe.schema -ne 1 -or
    [string]$probe.purpose -cne "signed-release-lifecycle" -or
    [string]$probe.test_context_id -cne [string]$evidence.test_context_id -or
    [string]$probe.executable -cne "iris-tauri.exe" -or
    [long]$probe.created_utc_ms -le 0
) {
    throw "Clean-VM lifecycle state-probe content has invalid Iris provenance."
}

$testedUtc = [DateTimeOffset]::MinValue
if (-not [DateTimeOffset]::TryParse([string]$evidence.tested_utc, [ref]$testedUtc)) {
    throw "Clean-VM lifecycle evidence has an invalid tested_utc value."
}
$now = [DateTimeOffset]::UtcNow
if ($testedUtc -gt $now.AddMinutes(5)) {
    throw "Clean-VM lifecycle evidence is dated in the future."
}
if ($testedUtc -lt $now.AddHours(-$MaximumEvidenceAgeHours)) {
    throw "Clean-VM lifecycle evidence is older than $MaximumEvidenceAgeHours hours."
}
if ($wackReport.LastWriteUtc -gt $now.AddMinutes(5)) {
    throw "External WACK report is dated in the future."
}
if ($wackReport.LastWriteUtc -lt $now.AddHours(-$MaximumEvidenceAgeHours)) {
    throw "External WACK report is older than $MaximumEvidenceAgeHours hours."
}

$releaseJson = & $gh release view $Tag `
    --repo $Repo `
    --json author,databaseId,isDraft,isPrerelease,name,tagName,targetCommitish
if ($LASTEXITCODE -ne 0) {
    throw "The draft GitHub release for $Tag is not readable."
}
$release = $releaseJson | ConvertFrom-Json
if (
    [string]$release.tagName -cne $Tag -or
    -not $release.isDraft -or
    $release.isPrerelease -or
    [string]$release.name -cne $releaseName -or
    [string]$release.targetCommitish -cne $ExpectedCommit -or
    [string]$release.author.login -cne "github-actions[bot]" -or
    [long]$release.databaseId -le 0
) {
    throw "$Tag must be the exact verified non-prerelease draft before publication."
}

$provenanceArtifactName = (
    "iris-signed-provenance-${Tag}-attempt-$([int]$releaseRun.attempt)"
)
$artifactsJson = & $gh api --paginate --slurp "repos/$Repo/actions/runs/$ReleaseRunId/artifacts?per_page=100"
if ($LASTEXITCODE -ne 0) {
    throw "The exact release run's provenance artifact could not be listed."
}
$artifactPages = @(($artifactsJson -join "`n") | ConvertFrom-Json)
$releaseArtifacts = @(
    $artifactPages |
        ForEach-Object { @($_.artifacts) }
)
if (
    $artifactPages.Count -eq 0 -or
    $releaseArtifacts.Count -ne [int]$artifactPages[0].total_count
) {
    throw "The exact release run's artifact pagination was incomplete."
}
$provenanceArtifacts = @(
    $releaseArtifacts |
        Where-Object {
            [string]$_.name -ceq $provenanceArtifactName -and
            -not $_.expired
        }
)
if ($provenanceArtifacts.Count -ne 1) {
    throw "ReleaseRunId must retain exactly one unexpired immutable signed-provenance artifact."
}

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("iris-release-publish-" + [Guid]::NewGuid().ToString("N"))
try {
    New-Item -ItemType Directory -Force -Path $testRoot | Out-Null

    $provenanceRoot = Join-Path $testRoot "workflow-provenance"
    New-Item -ItemType Directory -Force -Path $provenanceRoot | Out-Null
    & $gh run download $ReleaseRunId `
        --repo $Repo `
        --name $provenanceArtifactName `
        --dir $provenanceRoot
    if ($LASTEXITCODE -ne 0) {
        throw "Could not download immutable provenance from the exact release workflow run."
    }
    $provenanceArtifactFiles = @(
        Get-ChildItem -LiteralPath $provenanceRoot -Recurse -File
    )
    $provenanceArtifactNames = @(
        $provenanceArtifactFiles |
            ForEach-Object Name |
            Sort-Object
    )
    $expectedProvenanceArtifactNames = @(
        "iris-signed-build.json",
        "iris-unsigned-build.json"
    ) | Sort-Object
    if (
        $provenanceArtifactNames.Count -ne
            $expectedProvenanceArtifactNames.Count -or
        (Compare-Object `
            -ReferenceObject $expectedProvenanceArtifactNames `
            -DifferenceObject $provenanceArtifactNames)
    ) {
        throw "The exact release run artifact must contain only the signed and unsigned provenance files."
    }
    $trustedProvenancePath = (
        $provenanceArtifactFiles |
            Where-Object { $_.Name -ceq "iris-signed-build.json" }
    )[0].FullName
    $trustedUnsignedProvenancePath = (
        $provenanceArtifactFiles |
            Where-Object { $_.Name -ceq "iris-unsigned-build.json" }
    )[0].FullName
    try {
        $provenance = Get-Content -LiteralPath $trustedProvenancePath -Raw | ConvertFrom-Json
    } catch {
        throw "Protected workflow provenance is not valid JSON: $($_.Exception.Message)"
    }
    if (
        [int]$provenance.schema -ne 3 -or
        [string]$provenance.tag -cne $Tag -or
        [string]$provenance.source_commit -cne $ExpectedCommit -or
        [long]$provenance.workflow_run_id -ne $ReleaseRunId -or
        [int]$provenance.workflow_run_attempt -ne [int]$releaseRun.attempt -or
        [string]$provenance.package_version -cne $packageVersion -or
        [string]$provenance.msix_version -cne $msixVersion -or
        [string]$provenance.signer_subject -cne $ExpectedPublisher -or
        ([string]$provenance.signer_thumbprint).ToLowerInvariant() -cne
            $ExpectedSignerThumbprint -or
        -not ([string]$provenance.timestamp_subject).Trim() -or
        [string]$provenance.timestamp_subject -match "[\r\n]" -or
        [string]$provenance.timestamp_thumbprint -notmatch "^[a-fA-F0-9]{40}$" -or
        [string]$provenance.unsigned_build_provenance_sha256 -notmatch "^[a-fA-F0-9]{64}$"
    ) {
        throw "Protected workflow provenance does not match the exact run, source, version, or production signer."
    }
    $trustedUnsignedProvenanceHash = (
        Get-FileHash -LiteralPath $trustedUnsignedProvenancePath -Algorithm SHA256
    ).Hash.ToLowerInvariant()
    if (
        $trustedUnsignedProvenanceHash -cne
            ([string]$provenance.unsigned_build_provenance_sha256).ToLowerInvariant()
    ) {
        throw "Protected unsigned build provenance does not match its signed-build binding."
    }
    try {
        $unsignedProvenance = (
            Get-Content -LiteralPath $trustedUnsignedProvenancePath -Raw |
                ConvertFrom-Json
        )
    } catch {
        throw "Protected unsigned build provenance is not valid JSON: $($_.Exception.Message)"
    }
    if (
        [int]$unsignedProvenance.schema -ne 2 -or
        [string]$unsignedProvenance.tag -cne $Tag -or
        [string]$unsignedProvenance.source_commit -cne $ExpectedCommit
    ) {
        throw "Protected unsigned build provenance does not match the exact source and tag."
    }

    $provenanceFiles = [ordered]@{
        "install-iris-windows.ps1" = "install-iris-windows.ps1"
        "install-iris-windows.ps1.sha256" = "install-iris-windows.ps1.sha256"
        "iris-windows-installer.zip" = "iris-windows-installer.zip"
        "iris-windows-installer.zip.sha256" = "iris-windows-installer.zip.sha256"
        "iris-windows.zip" = "iris-windows.zip"
        "iris-windows.zip.sha256" = "iris-windows.zip.sha256"
        "iris-windows.msix" = "iris-windows.msix"
        "iris-windows.msix.sha256" = "iris-windows.msix.sha256"
        "iris-msix-signing.cer" = "iris-msix-signing.cer"
        "iris-msix-signing.cer.sha256" = "iris-msix-signing.cer.sha256"
        "winget/iris-winget-manifests.zip" = "iris-winget-manifests.zip"
        "winget/iris-winget-manifests.zip.sha256" = "iris-winget-manifests.zip.sha256"
    }
    $provenanceNames = @($provenance.files.PSObject.Properties.Name | Sort-Object)
    if (
        $provenanceNames.Count -ne $provenanceFiles.Count -or
        (Compare-Object `
            -ReferenceObject @($provenanceFiles.Keys | Sort-Object) `
            -DifferenceObject $provenanceNames)
    ) {
        throw "Protected workflow provenance contains an unexpected release file set."
    }

    $draftRoot = Join-Path $testRoot "draft-assets"
    New-Item -ItemType Directory -Force -Path $draftRoot | Out-Null
    & $gh release download $Tag --repo $Repo --dir $draftRoot
    if ($LASTEXITCODE -ne 0) {
        throw "Could not download every current draft asset for provenance comparison."
    }
    $expectedAssetHashes = @{}
    foreach ($relativePath in $provenanceFiles.Keys) {
        $assetName = $provenanceFiles[$relativePath]
        $hash = [string]$provenance.files.PSObject.Properties[$relativePath].Value
        if ($hash -notmatch "^[a-fA-F0-9]{64}$") {
            throw "Protected workflow provenance has an invalid hash for $relativePath."
        }
        $expectedAssetHashes[$assetName] = $hash.ToLowerInvariant()
    }
    $trustedProvenanceHash = (
        Get-FileHash -LiteralPath $trustedProvenancePath -Algorithm SHA256
    ).Hash.ToLowerInvariant()
    $expectedAssetHashes["iris-unsigned-build.json"] = $trustedUnsignedProvenanceHash
    $expectedAssetHashes["iris-signed-build.json"] = $trustedProvenanceHash
    $draftFiles = @(Get-ChildItem -LiteralPath $draftRoot -File)
    $draftNames = @($draftFiles | ForEach-Object Name | Sort-Object)
    $expectedDraftNames = @($expectedAssetHashes.Keys | Sort-Object)
    if (
        $draftNames.Count -ne $expectedDraftNames.Count -or
        (Compare-Object -ReferenceObject $expectedDraftNames -DifferenceObject $draftNames)
    ) {
        throw "The draft asset set does not match the exact protected workflow provenance."
    }
    foreach ($draftFile in $draftFiles) {
        $actualHash = (
            Get-FileHash -LiteralPath $draftFile.FullName -Algorithm SHA256
        ).Hash.ToLowerInvariant()
        if ($actualHash -cne [string]$expectedAssetHashes[$draftFile.Name]) {
            throw "Draft asset does not match protected workflow provenance: $($draftFile.Name)"
        }
    }

    $msixPath = Join-Path $draftRoot "iris-windows.msix"
    $releaseHash = (Get-FileHash -LiteralPath $msixPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($releaseHash -cne ([string]$evidence.release_sha256).ToLowerInvariant()) {
        throw "Clean-VM evidence targets a different MSIX. Evidence: $($evidence.release_sha256); draft: $releaseHash."
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $msixPath
    if (-not $signature.SignerCertificate -or $signature.Status -ne "Valid") {
        throw "Draft MSIX signature is not valid and trusted: $($signature.Status) $($signature.StatusMessage)"
    }
    if (-not $signature.TimeStamperCertificate) {
        throw "Draft MSIX signature has no trusted RFC 3161 timestamp."
    }
    if (
        [string]$signature.SignerCertificate.Subject -cne $ExpectedPublisher -or
        [string]$signature.SignerCertificate.Subject -cne [string]$evidence.publisher -or
        [string]$signature.SignerCertificate.Subject -cne [string]$provenance.signer_subject
    ) {
        throw "Draft MSIX publisher does not match the owner pin, lifecycle evidence, and protected provenance."
    }
    if (
        ([string]$signature.SignerCertificate.Thumbprint).ToLowerInvariant() -cne
            $ExpectedSignerThumbprint -or
        ([string]$signature.SignerCertificate.Thumbprint).ToLowerInvariant() -cne
            ([string]$evidence.signer_thumbprint).ToLowerInvariant() -or
        ([string]$signature.SignerCertificate.Thumbprint).ToLowerInvariant() -cne
            ([string]$provenance.signer_thumbprint).ToLowerInvariant() -or
        [string]$signature.TimeStamperCertificate.Subject -cne
            [string]$provenance.timestamp_subject -or
        ([string]$signature.TimeStamperCertificate.Thumbprint).ToLowerInvariant() -cne
            ([string]$provenance.timestamp_thumbprint).ToLowerInvariant()
    ) {
        throw "Draft MSIX signer or timestamp does not match the owner pin, lifecycle evidence, and protected provenance."
    }

    $publishedEvidence = Join-Path $testRoot "iris-msix-lifecycle-evidence.json"
    Copy-Item -LiteralPath $evidencePath -Destination $publishedEvidence
    $evidenceHash = (Get-FileHash -LiteralPath $publishedEvidence -Algorithm SHA256).Hash.ToLowerInvariant()
    $evidenceHashPath = "$publishedEvidence.sha256"
    Set-Content -LiteralPath $evidenceHashPath `
        -Value "$evidenceHash  iris-msix-lifecycle-evidence.json" `
        -Encoding ascii
    $publishedWackReport = Join-Path $testRoot "iris-windows-wack-report.xml"
    Copy-Item -LiteralPath $wackReport.Path -Destination $publishedWackReport
    $publishedWackHash = (
        Get-FileHash -LiteralPath $publishedWackReport -Algorithm SHA256
    ).Hash.ToLowerInvariant()
    if (
        $publishedWackHash -cne $wackReport.Sha256 -or
        (Get-Item -LiteralPath $publishedWackReport).Length -ne $wackReport.Length
    ) {
        throw "The staged WACK report changed before publication."
    }
    $publishedWackHashPath = "$publishedWackReport.sha256"
    Set-Content -LiteralPath $publishedWackHashPath `
        -Value "$publishedWackHash  iris-windows-wack-report.xml" `
        -Encoding ascii
    $publisherToken = (& $gh auth token | Select-Object -First 1).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $publisherToken) {
        throw "The GitHub CLI credential could not be loaded for exact-release asset upload."
    }
    $uploadHeaders = @{
        Accept = "application/vnd.github+json"
        Authorization = "Bearer $publisherToken"
        "X-GitHub-Api-Version" = "2022-11-28"
    }
    foreach ($assetPath in @(
            $publishedEvidence,
            $evidenceHashPath,
            $publishedWackReport,
            $publishedWackHashPath
        )) {
        $assetName = [System.IO.Path]::GetFileName($assetPath)
        $uploadUri = (
            "https://uploads.github.com/repos/$Repo/releases/" +
            "$([long]$release.databaseId)/assets?name=$([uri]::EscapeDataString($assetName))"
        )
        $uploaded = Invoke-RestMethod `
            -Method Post `
            -Uri $uploadUri `
            -Headers $uploadHeaders `
            -ContentType "application/octet-stream" `
            -InFile $assetPath
        if (
            [long]$uploaded.id -le 0 -or
            [string]$uploaded.name -cne $assetName
        ) {
            throw "GitHub did not attach release-gate evidence to the exact draft release: $assetName"
        }
    }
    $publisherToken = $null

    & $verifier `
        -Repo $Repo `
        -Tag $Tag `
        -ExpectedCommit $ExpectedCommit `
        -ExpectedReleaseId ([long]$release.databaseId) `
        -ExpectedAuthor "github-actions[bot]" `
        -ExpectedName $releaseName `
        -ExpectedBodyPrefix $releaseBodyPrefix `
        -ExpectedPublisher $ExpectedPublisher `
        -ExpectedSignerThumbprint $ExpectedSignerThumbprint `
        -ExpectedProvenancePath $trustedProvenancePath `
        -AllowDraft `
        -RequireSignedMsix `
        -RequireWingetBundle `
        -RequireBuildProvenance `
        -RequireWingetClientValidation `
        -RequireLifecycleEvidence `
        -RequireWackReport `
        -DownloadPayloads

    & $tagProtectionVerifier -Repo $Repo -Tag $Tag
    $publishRequestPath = Join-Path $testRoot "publish-release.json"
    [ordered]@{
        draft = $false
        prerelease = $false
        make_latest = "true"
    } |
        ConvertTo-Json |
        Set-Content -LiteralPath $publishRequestPath -Encoding utf8
    $publishedJson = & $gh api `
        --method PATCH `
        "repos/$Repo/releases/$([long]$release.databaseId)" `
        --input $publishRequestPath
    if ($LASTEXITCODE -ne 0) {
        throw "The exact verified draft release could not be published."
    }
    $publishedRelease = ($publishedJson -join "`n") | ConvertFrom-Json
    if (
        [long]$publishedRelease.id -ne [long]$release.databaseId -or
        [string]$publishedRelease.tag_name -cne $Tag -or
        $publishedRelease.draft -or
        $publishedRelease.prerelease
    ) {
        throw "GitHub did not confirm publication of the exact verified draft."
    }

    & $verifier `
        -Repo $Repo `
        -Tag $Tag `
        -ExpectedCommit $ExpectedCommit `
        -ExpectedReleaseId ([long]$release.databaseId) `
        -ExpectedAuthor "github-actions[bot]" `
        -ExpectedName $releaseName `
        -ExpectedBodyPrefix $releaseBodyPrefix `
        -ExpectedPublisher $ExpectedPublisher `
        -ExpectedSignerThumbprint $ExpectedSignerThumbprint `
        -ExpectedProvenancePath $trustedProvenancePath `
        -RequireLatest `
        -RequireSignedMsix `
        -RequireWingetBundle `
        -RequireBuildProvenance `
        -RequireWingetClientValidation `
        -RequireLifecycleEvidence `
        -RequireWackReport `
        -DownloadPayloads

    $releaseAttestationVerified = $false
    for ($attempt = 1; $attempt -le 6; $attempt++) {
        & $gh release verify $Tag --repo $Repo
        if ($LASTEXITCODE -eq 0) {
            $releaseAttestationVerified = $true
            break
        }
        if ($attempt -lt 6) {
            Start-Sleep -Seconds 2
        }
    }
    if (-not $releaseAttestationVerified) {
        throw "GitHub's cryptographic immutable-release attestation could not be verified."
    }
    foreach ($attestedAsset in @(
            $msixPath,
            $publishedEvidence,
            $evidenceHashPath,
            $publishedWackReport,
            $publishedWackHashPath,
            (Join-Path $draftRoot "iris-winget-manifests.zip"),
            (Join-Path $draftRoot "iris-unsigned-build.json"),
            (Join-Path $draftRoot "iris-signed-build.json")
        )) {
        & $gh release verify-asset $Tag $attestedAsset --repo $Repo
        if ($LASTEXITCODE -ne 0) {
            throw "GitHub release attestation does not cover $(Split-Path -Leaf $attestedAsset)."
        }
    }

    $anonymousMsix = Join-Path $testRoot "anonymous-iris-windows.msix"
    Invoke-WebRequest `
        -Uri "https://github.com/$Repo/releases/download/$Tag/iris-windows.msix" `
        -OutFile $anonymousMsix `
        -UseBasicParsing
    $anonymousHash = (
        Get-FileHash -LiteralPath $anonymousMsix -Algorithm SHA256
    ).Hash.ToLowerInvariant()
    if ($anonymousHash -cne $releaseHash) {
        throw "The anonymously downloadable public MSIX does not match the tested immutable artifact."
    }

    Write-Host "Immutable GitHub release publication verified: https://github.com/$Repo/releases/tag/$Tag"
} finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolved = [System.IO.Path]::GetFullPath($testRoot)
        $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        if (-not $resolved.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove release publisher data outside temp: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
