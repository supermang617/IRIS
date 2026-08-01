$ErrorActionPreference = "Stop"

function Get-WorkflowJobBlock {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$JobName
    )

    $pattern = "(?ms)^  $([regex]::Escape($JobName)):\r?\n(?<body>.*?)(?=^  [A-Za-z0-9_-]+:\r?$|\z)"
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) {
        throw "Release workflow is missing job '$JobName'."
    }
    return $match.Groups["body"].Value
}

function Get-MultilineRunBlocks {
    param([Parameter(Mandatory = $true)][string]$Text)

    $lines = @($Text -split "\r?\n")
    $blocks = New-Object System.Collections.Generic.List[string]
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -notmatch "^(?<indent>[ ]*)run:[ ]*\|[ ]*$") {
            continue
        }
        $parentIndent = $Matches.indent.Length
        $body = New-Object System.Collections.Generic.List[string]
        for ($bodyIndex = $index + 1; $bodyIndex -lt $lines.Count; $bodyIndex++) {
            $line = $lines[$bodyIndex]
            if (-not $line.Trim()) {
                $body.Add($line)
                continue
            }
            $leading = ([regex]::Match($line, "^ *")).Value.Length
            if ($leading -le $parentIndent) {
                break
            }
            $body.Add($line)
        }
        $blocks.Add(($body -join "`n"))
    }
    return @($blocks)
}

function Assert-NativeBlocksFailFast {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $nativePattern = '(?im)(?:^|[=(|;&])[ \t]*(?:&[ \t]*)?(?:cargo|npm|node|python|uv|uvx|git|gh|choco|rustup)\b|&[ \t]*\$gh\b'
    foreach ($block in Get-MultilineRunBlocks -Text $Text) {
        if ($block -notmatch $nativePattern) {
            continue
        }
        if (-not $block.Contains('$ErrorActionPreference = "Stop"') -or
            -not $block.Contains('$PSNativeCommandUseErrorActionPreference = $true')) {
            throw "$Name contains a multiline native-command block without fail-fast PowerShell settings:`n$block"
        }
    }
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$releaseWorkflowPath = Join-Path $repoRoot ".github\workflows\release.yml"
$ciWorkflowPath = Join-Path $repoRoot ".github\workflows\ci.yml"
$allWorkflowPaths = @(
    Get-ChildItem -LiteralPath (Join-Path $repoRoot ".github\workflows") -Filter "*.yml" -File |
        Sort-Object -Property FullName |
        Select-Object -ExpandProperty FullName
)
$templatePath = Join-Path $repoRoot ".github\release-notes-template.md"
$verifierPath = Join-Path $repoRoot "scripts\test_github_versioned_release.ps1"
$publisherPath = Join-Path $repoRoot "scripts\publish_github_versioned_release.ps1"
$tagProtectionPath = Join-Path $repoRoot "scripts\test_github_semantic_tag_protection.ps1"
$versionScriptPath = Join-Path $repoRoot "scripts\test_release_version.ps1"
$privacyPath = Join-Path $repoRoot "PRIVACY.md"
$githubSettingsPath = Join-Path $repoRoot "docs\github-settings.md"
$wingetReleasePath = Join-Path $repoRoot "docs\winget-release.md"

foreach ($path in @(
        $releaseWorkflowPath,
        $ciWorkflowPath,
        $templatePath,
        $verifierPath,
        $publisherPath,
        $tagProtectionPath,
        $versionScriptPath,
        $privacyPath,
        $githubSettingsPath,
        $wingetReleasePath
    )) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Release publication input is missing: $path"
    }
}

$workflow = Get-Content -LiteralPath $releaseWorkflowPath -Raw
$ci = Get-Content -LiteralPath $ciWorkflowPath -Raw
$template = Get-Content -LiteralPath $templatePath -Raw
$verifier = Get-Content -LiteralPath $verifierPath -Raw
$publisher = Get-Content -LiteralPath $publisherPath -Raw
$privacy = Get-Content -LiteralPath $privacyPath -Raw
$githubSettings = Get-Content -LiteralPath $githubSettingsPath -Raw
$wingetRelease = Get-Content -LiteralPath $wingetReleasePath -Raw
$allWorkflows = ($allWorkflowPaths | ForEach-Object {
        Get-Content -LiteralPath $_ -Raw
    }) -join "`n"

$buildJob = Get-WorkflowJobBlock -Text $workflow -JobName "build"
$signJob = Get-WorkflowJobBlock -Text $workflow -JobName "sign"
$draftJob = Get-WorkflowJobBlock -Text $workflow -JobName "draft"
$cleanupJob = Get-WorkflowJobBlock -Text $workflow -JobName "cleanup"

foreach ($fragment in @(
        "workflow_dispatch:",
        'group: iris-release-${{ inputs.tag }}',
        "cancel-in-progress: false",
        "if: github.ref == 'refs/heads/main'",
        "IRIS_PRODUCTION_GATE_CONFIGURED",
        "refs/remotes/origin/main",
        "Production signing requires",
        "test_github_semantic_tag_protection.ps1",
        "-DeferBypassVerification",
        "tag_name = `$env:IRIS_RELEASE_TAG",
        "Semantic releases require IRIS_SIGNING_PFX_BASE64",
        '-ExpectedPublisher $env:IRIS_MSIX_PUBLISHER',
        "draft = `$true",
        'make_latest = "false"',
        "generate_release_notes = `$true",
        "Atomic draft creation failed",
        "no existing release will be reused",
        'iris-signed-provenance-${{ needs.build.outputs.tag }}-attempt-${{ github.run_attempt }}',
        "retention-days: 10",
        "iris-unsigned-build.json",
        "-ExpectedSignerThumbprint",
        "-ExpectedProvenancePath",
        "-RequireBuildProvenance",
        "-AllowDraft",
        "-RequireSignedMsix",
        "-RequireWingetBundle",
        "Publication remains blocked by the clean-VM lifecycle gate",
        "release-only WACK, install, registered-launch, and uninstall gate",
        "scripts/publish_github_versioned_release.ps1",
        'iris-release-unsigned-${{ github.run_id }}-${{ github.run_attempt }}',
        'iris-release-signed-${{ github.run_id }}-${{ github.run_attempt }}'
    )) {
    if (-not $workflow.Contains($fragment)) {
        throw "Release workflow is missing fail-closed publication behavior: $fragment"
    }
}

if (
    ([regex]::Matches($wingetRelease, [regex]::Escape("-WackReportPath"))).Count -lt 2 -or
    -not $wingetRelease.Contains("wack_package_sha256") -or
    -not $wingetRelease.Contains("Lifecycle schema 3")
) {
    throw "WinGet release instructions must pass the bound WACK report through both guest and publisher gates."
}
if ($workflow.Contains("sign_and_draft:")) {
    throw "Signing secrets and release-write credentials must remain in separate jobs."
}
if ($workflow.Contains('- "v[0-9]+"')) {
    throw "Mutable major-only release tags must not trigger new publication runs."
}
if ($workflow.Contains("push:`n") -or $workflow.Contains("push:`r`n")) {
    throw "Pushing a tag must not automatically expose the production signing path."
}
if ($workflow.Contains("--draft=false")) {
    throw "The draft workflow must not bypass the external clean-VM lifecycle gate."
}
foreach ($fragment in @(
        "timeout-minutes: 180",
        "actions/cache/save@caa296126883cff596d87d8935842f9db880ef25",
        'key: iris-release-unsigned-${{ github.run_id }}-${{ github.run_attempt }}',
        "iris-unsigned-build.json"
    )) {
    if (-not $buildJob.Contains($fragment)) {
        throw "Unsigned build job is missing its bounded cache handoff: $fragment"
    }
}
if ($buildJob.Contains("actions/upload-artifact@") -or
    $buildJob.Contains("actions/download-artifact@")) {
    throw "The large unsigned release payload must use the run-scoped cache handoff."
}

if (-not $buildJob.Contains("contents: read") -or $buildJob.Contains("secrets.")) {
    throw "Unsigned build job must be read-only and must not receive production secrets."
}
foreach ($fragment in @(
        "contents: read",
        "timeout-minutes: 60",
        "environment: iris-production-release",
        "IRIS_SIGNING_PFX_BASE64",
        "actions/cache/restore@caa296126883cff596d87d8935842f9db880ef25",
        "actions/cache/save@caa296126883cff596d87d8935842f9db880ef25",
        'key: iris-release-unsigned-${{ github.run_id }}-${{ github.run_attempt }}',
        'key: iris-release-signed-${{ github.run_id }}-${{ github.run_attempt }}',
        "fail-on-cache-miss: true",
        'iris-signed-provenance-${{ needs.build.outputs.tag }}-attempt-${{ github.run_attempt }}',
        "iris-unsigned-build.json",
        "iris-signed-build.json"
    )) {
    if (-not $signJob.Contains($fragment)) {
        throw "Protected signing job is missing its isolated trust boundary: $fragment"
    }
}
if ($signJob.Contains("contents: write") -or
    $signJob.Contains("softprops/action-gh-release") -or
    $signJob.Contains('${{ github.token }}') -or
    $signJob.Contains("actions/download-artifact@")) {
    throw "Protected signing job must not have a release-write GitHub credential."
}
$signArtifactUploads = @(
    [regex]::Matches($signJob, "(?m)^[ \t]*uses:[ \t]*actions/upload-artifact@")
).Count
if ($signArtifactUploads -ne 1) {
    throw "Signing must retain exactly one small provenance artifact, not the large payload."
}
foreach ($fragment in @(
        "contents: write",
        "timeout-minutes: 60",
        "needs:",
        "- build",
        "- sign",
        "actions/cache/restore@caa296126883cff596d87d8935842f9db880ef25",
        'key: iris-release-signed-${{ github.run_id }}-${{ github.run_attempt }}',
        "fail-on-cache-miss: true",
        "Verify signed artifact provenance without executing the payload",
        "Create a new draft atomically and upload complete release assets",
        "gh api",
        "Invoke-RestMethod",
        '${uploadBase}?name=$([uri]::EscapeDataString($name))',
        "IRIS_DRAFT_RELEASE_ID",
        "release/dist/iris-unsigned-build.json",
        "-ExpectedReleaseId"
    )) {
    if (-not $draftJob.Contains($fragment)) {
        throw "Credential-isolated draft job is missing: $fragment"
    }
}
if ($draftJob.Contains("IRIS_SIGNING_PFX") -or
    $draftJob.Contains("iris-production-release") -or
    $draftJob.Contains("actions/download-artifact@") -or
    $draftJob.Contains("actions/upload-artifact@")) {
    throw "Draft job must never receive the PFX or protected signing environment."
}

foreach ($fragment in @(
        "needs:",
        "- build",
        "- sign",
        "- draft",
        'if: ${{ always() }}',
        "runs-on: ubuntu-24.04",
        "timeout-minutes: 10",
        "actions: write",
        'IRIS_UNSIGNED_CACHE_KEY: iris-release-unsigned-${{ github.run_id }}-${{ github.run_attempt }}',
        'IRIS_SIGNED_CACHE_KEY: iris-release-signed-${{ github.run_id }}-${{ github.run_attempt }}',
        "actions/caches?key=`$encodedKey&ref=`$encodedRef&per_page=100",
        "Transient release cache pagination was incomplete",
        "actions/caches/`$([long]`$cache.id)"
    )) {
    if (-not $cleanupJob.Contains($fragment)) {
        throw "Transient cache cleanup job is missing its exact-key safety boundary: $fragment"
    }
}
if ($cleanupJob.Contains("contents: write") -or
    $cleanupJob.Contains("secrets.") -or
    $cleanupJob.Contains("actions/cache/")) {
    throw "Transient cache cleanup must have only Actions write access and no signing inputs."
}

foreach ($fragment in @(
        "timeout-minutes: 180",
        'name: iris-dependency-inventory-attempt-${{ github.run_attempt }}',
        "if-no-files-found: error",
        "retention-days: 7"
    )) {
    if (-not $ci.Contains($fragment)) {
        throw "CI dependency inventory is missing bounded retention or rerun isolation: $fragment"
    }
}

$actionMatches = @(
    [regex]::Matches(
        $allWorkflows,
        "(?m)^[ \t]*uses:[ \t]*[^@\s]+@(?<ref>[^\s#]+)"
    )
)
if ($actionMatches.Count -eq 0) {
    throw "No GitHub Actions references were found."
}
foreach ($match in $actionMatches) {
    if ($match.Groups["ref"].Value -notmatch "^[a-fA-F0-9]{40}$") {
        throw "Every GitHub Action must be pinned to a full commit SHA: $($match.Value)"
    }
}
$allowedActions = @(
    "actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803",
    "actions/setup-node@249970729cb0ef3589644e2896645e5dc5ba9c38",
    "actions/setup-python@ece7cb06caefa5fff74198d8649806c4678c61a1",
    "actions/cache/save@caa296126883cff596d87d8935842f9db880ef25",
    "actions/cache/restore@caa296126883cff596d87d8935842f9db880ef25",
    "actions/upload-artifact@b7c566a772e6b6bfb58ed0dc250532a479d7789f",
    "actions/download-artifact@37930b1c2abaa49bbe596cd826c3c89aef350131",
    "actions/upload-pages-artifact@7b1f4a764d45c48632c6b24a0339c27f5614fb0b",
    "actions/deploy-pages@d6db90164ac5ed86f2b6aed7e0febac5b3c0c03e",
    "actions/dependency-review-action@a1d282b36b6f3519aa1f3fc636f609c47dddb294"
)
foreach ($match in $actionMatches) {
    $action = ($match.Value -replace "^[ \t]*uses:[ \t]*", "").Trim()
    if ($action -notin $allowedActions) {
        throw "GitHub Action is not in the reviewed repository/SHA allowlist: $action"
    }
}
$checkoutCount = @(
    [regex]::Matches($allWorkflows, "(?m)^[ \t]*uses:[ \t]*actions/checkout@")
).Count
$nonPersistingCheckoutCount = @(
    [regex]::Matches($allWorkflows, "(?m)^[ \t]*persist-credentials:[ \t]*false[ \t]*$")
).Count
if ($checkoutCount -ne $nonPersistingCheckoutCount) {
    throw "Every checkout must disable persisted GitHub credentials."
}

foreach ($workflowPath in $allWorkflowPaths) {
    Assert-NativeBlocksFailFast `
        -Text (Get-Content -LiteralPath $workflowPath -Raw) `
        -Name ([System.IO.Path]::GetFileName($workflowPath))
}

$requiredOpening = "Iris {{VERSION}} is a local-first Windows AI assistant with natural voice, vision, private memory, Ollama, and approval-gated Hermes agent tools."
if (-not $template.StartsWith($requiredOpening, [System.StringComparison]::Ordinal)) {
    throw "Release notes must begin with the canonical product summary."
}
foreach ($fragment in @(
        "WinGet catalog status:",
        "not yet submitted or public",
        "iris-windows.msix",
        "iris-msix-lifecycle-evidence.json",
        "iris-unsigned-build.json",
        "iris-signed-build.json",
        "iris-windows-wack-report.xml",
        "iris-windows-wack-report.xml.sha256",
        "install, registered launch, uninstall, and state-preservation evidence",
        "REPORT.OVERALL_RESULT=PASS",
        "genuine higher semantic release",
        "Get-AuthenticodeSignature",
        "%LOCALAPPDATA%\Iris",
        "true acoustic echo cancellation is not claimed",
        "PRIVACY.md",
        "known-limitations.md"
    )) {
    if (-not $template.Contains($fragment)) {
        throw "Release notes template is missing required metadata: $fragment"
    }
}

foreach ($fragment in @(
        '[string]$ExpectedPublisher',
        '[string]$ExpectedSignerThumbprint',
        '[string]$ExpectedProvenancePath',
        '[long]$ExpectedReleaseId',
        '[string]$ExpectedAuthor',
        '[switch]$AllowDraft',
        '[switch]$RequireLatest',
        '[switch]$RequireBuildProvenance',
        '[switch]$RequireLifecycleEvidence',
        '[switch]$RequireWackReport',
        '[switch]$RequireWingetClientValidation',
        '$releaseApi.immutable',
        "ProjectIris.LocalAssistant",
        "AppxSignature.p7x",
        "TimeStamperCertificate",
        "iris-unsigned-build.json",
        "iris-signed-build.json",
        "unsigned_build_provenance_sha256",
        "Published unsigned build provenance does not match its protected signed-build binding.",
        "InstallerSha256",
        "SignatureSha256",
        "release-only schema 3",
        "iris-windows-wack-report.xml",
        "REPORT.OVERALL_RESULT=PASS",
        "wack_package_sha256",
        "Published WACK report does not match clean-VM lifecycle evidence.",
        "releases/latest",
        "release notes do not start with the required product summary",
        "Published MSIX manifest publisher does not match its signing certificate.",
        "Published certificate does not match the MSIX signer."
    )) {
    if (-not $verifier.Contains($fragment)) {
        throw "Versioned release verifier is missing a publication assertion: $fragment"
    }
}

foreach ($fragment in @(
        '[Parameter(Mandatory = $true)][string]$ExpectedCommit',
        '[Parameter(Mandatory = $true)][long]$ReleaseRunId',
        '[Parameter(Mandatory = $true)][string]$ExpectedPublisher',
        '[Parameter(Mandatory = $true)][string]$ExpectedSignerThumbprint',
        '[Parameter(Mandatory = $true)][string]$WackReportPath',
        "Clean-VM lifecycle evidence is older than",
        "External WACK report is older than",
        "External WACK report does not match the report bound into clean-VM lifecycle evidence.",
        "Clean-VM lifecycle evidence does not bind WACK to the exact tested MSIX.",
        "Clean-VM evidence targets a different MSIX",
        "immutable-releases",
        "branches/main/protection",
        "required_status_checks.strict",
        "required_pull_request_reviews",
        "required_conversation_resolution.enabled",
        '--paginate --slurp "repos/$Repo/commits/$ExpectedCommit/check-runs?per_page=100"',
        '--paginate --slurp "repos/$Repo/commits/$ExpectedCommit/status?per_page=100"',
        "check-run pagination was incomplete",
        "commit-status pagination was incomplete",
        "required_status_checks.checks",
        "app_id",
        '$_.app.id',
        '[string]$checkRun.completed_at',
        '[string]$checkRun.updated_at',
        '[string]$checkRun.created_at',
        '[string]$checkRun.started_at',
        '[string]$commitStatus.updated_at',
        '[string]$commitStatus.created_at',
        "Sort-Object -Property",
        '$latestRequiredResult',
        "latest result is not successful",
        'commits/$ExpectedCommit/check-runs',
        "environments/iris-production-release",
        "repository owner",
        '$configuredReviewers.Count -ne 1',
        "exactly one required",
        '--paginate --slurp "repos/$Repo/environments/iris-production-release/secrets?per_page=100"',
        '--paginate --slurp "repos/$Repo/actions/secrets?per_page=100"',
        '--paginate --slurp "repos/$Repo/environments/iris-production-release/variables?per_page=100"',
        '--paginate --slurp "repos/$Repo/actions/variables?per_page=100"',
        "secret pagination was incomplete",
        "variable pagination was incomplete",
        "IRIS_SIGNING_PFX_BASE64",
        'actions/runs/$ReleaseRunId/approvals',
        'actions/workflows/release.yml',
        "workflowDatabaseId",
        'iris-signed-provenance-${Tag}-attempt-$([int]$releaseRun.attempt)',
        '--paginate --slurp "repos/$Repo/actions/runs/$ReleaseRunId/artifacts?per_page=100"',
        "artifact pagination was incomplete",
        '$provenanceArtifactName',
        "gh run download",
        '$trustedUnsignedProvenancePath',
        "iris-unsigned-build.json",
        "unsigned_build_provenance_sha256",
        "Protected unsigned build provenance does not match its signed-build binding.",
        "Sign verified Windows artifacts",
        '-ExpectedPublisher $ExpectedPublisher',
        '-ExpectedSignerThumbprint $ExpectedSignerThumbprint',
        '-ExpectedProvenancePath $trustedProvenancePath',
        '-ExpectedCommit $ExpectedCommit',
        'release verify $Tag',
        'release verify-asset $Tag',
        "-RequireLifecycleEvidence",
        "-RequireWackReport",
        "-RequireWingetClientValidation",
        "--method PATCH",
        'make_latest = "true"',
        "-RequireLatest",
        "anonymous-iris-windows.msix",
        "Immutable GitHub release publication verified"
    )) {
    if ($publisher.IndexOf($fragment, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
        throw "Versioned release publisher is missing an external-gate assertion: $fragment"
    }
}
foreach ($obsoleteFragment in @(
        '$successfulCheck',
        '$successfulStatus'
    )) {
    if ($publisher.Contains($obsoleteFragment)) {
        throw "An older successful required check must not mask a newer failure: $obsoleteFragment"
    }
}
foreach ($obsoleteFragment in @(
        "baseline_version",
        "target_version",
        "upgrade_succeeded",
        "upgrade from a lower MSIX version"
    )) {
    if ($publisher.Contains($obsoleteFragment)) {
        throw "First production publication must not require an artificial lower version: $obsoleteFragment"
    }
}

foreach ($fragment in @(
        'Required checks on `main`: `Validate`',
        '`Analyze (actions)`',
        '`Analyze (javascript-typescript)`',
        '`Analyze (python)`',
        '`Analyze (rust)`',
        'Keep `Dependency Review / Dependency Review`',
        "do not add that PR-only context"
    )) {
    if (-not $githubSettings.Contains($fragment)) {
        throw "GitHub branch-protection guidance is not aligned with main-head publication: $fragment"
    }
}

foreach ($fragment in @(
        "local-first Windows assistant",
        "%LOCALAPPDATA%\Iris",
        "does not operate an account service, telemetry service",
        "super.mangmail@gmail.com"
    )) {
    if (-not $privacy.Contains($fragment)) {
        throw "Privacy policy is missing required truthful disclosure: $fragment"
    }
}

& $versionScriptPath -Tag "v1.0.0"
foreach ($invalidTag in @("v01.0.0", "v1.00.0", "v1.0.00", "v65536.0.0")) {
    $rejected = $false
    try {
        & $versionScriptPath -Tag $invalidTag
    } catch {
        $rejected = $true
    }
    if (-not $rejected) {
        throw "Release version validation accepted noncanonical or impossible tag: $invalidTag"
    }
}

Write-Host "Release workflow, trust boundaries, and metadata tests passed."
