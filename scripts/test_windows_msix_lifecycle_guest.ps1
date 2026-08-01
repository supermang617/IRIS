[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$MsixPath,
    [Parameter(Mandatory = $true)][string]$ExpectedPublisher,
    [Parameter(Mandatory = $true)][string]$ExpectedVersion,
    [string]$PackageIdentityName = "ProjectIris.LocalAssistant",
    [string]$ApplicationId = "Iris",
    [Parameter(Mandatory = $true)][string]$TestContextId,
    [string]$AppCertPath = "",
    [Parameter(Mandatory = $true)][string]$WackReportPath,
    [Parameter(Mandatory = $true)][string]$EvidencePath,
    [switch]$ConfirmDisposableTestGuest
)

$ErrorActionPreference = "Stop"

function ConvertTo-MsixVersion {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($Value -notmatch "^(0|[1-9][0-9]{0,4})(\.(0|[1-9][0-9]{0,4})){3}$") {
        throw "$Name must contain four numeric MSIX components, for example 1.0.0.0."
    }
    foreach ($part in $Value.Split(".")) {
        if ([int]$part -gt 65535) {
            throw "$Name contains a component outside the MSIX range 0-65535: $Value"
        }
    }
    return [version]$Value
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
        Sha256 = (
            Get-FileHash -LiteralPath $resolved -Algorithm SHA256
        ).Hash.ToLowerInvariant()
    }
}

function Get-VerifiedMsixIdentity {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedPackageVersion,
        [Parameter(Mandatory = $true)][string]$ExpectedIdentityName,
        [Parameter(Mandatory = $true)][string]$ExpectedIdentityPublisher,
        [Parameter(Mandatory = $true)][string]$ExpectedApplicationId
    )

    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if (-not $signature.SignerCertificate) {
        throw "MSIX is not signed: $Path"
    }
    if ($signature.Status -ne "Valid") {
        throw "MSIX signature is not valid and trusted in this guest: $Path ($($signature.Status) $($signature.StatusMessage))"
    }
    if (-not $signature.TimeStamperCertificate) {
        throw "MSIX signature has no trusted RFC 3161 timestamp: $Path"
    }
    if ([string]$signature.SignerCertificate.Subject -cne $ExpectedIdentityPublisher) {
        throw "MSIX signer '$($signature.SignerCertificate.Subject)' does not match expected publisher '$ExpectedIdentityPublisher': $Path"
    }

    $archive = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $manifestEntry = $archive.GetEntry("AppxManifest.xml")
        $signatureEntry = $archive.GetEntry("AppxSignature.p7x")
        if (-not $manifestEntry) {
            throw "MSIX is missing AppxManifest.xml: $Path"
        }
        if (-not $signatureEntry) {
            throw "MSIX is missing AppxSignature.p7x: $Path"
        }

        $reader = New-Object System.IO.StreamReader($manifestEntry.Open())
        try {
            [xml]$manifest = $reader.ReadToEnd()
        } finally {
            $reader.Dispose()
        }

        $identity = $manifest.Package.Identity
        if ([string]$identity.Name -cne $ExpectedIdentityName) {
            throw "MSIX identity '$($identity.Name)' does not match expected identity '$ExpectedIdentityName': $Path"
        }
        if ([string]$identity.Publisher -cne $ExpectedIdentityPublisher) {
            throw "MSIX manifest publisher '$($identity.Publisher)' does not match expected publisher '$ExpectedIdentityPublisher': $Path"
        }
        if ([string]$identity.Publisher -cne [string]$signature.SignerCertificate.Subject) {
            throw "MSIX manifest publisher does not match its signing certificate subject: $Path"
        }
        if ([string]$identity.Version -cne $ExpectedPackageVersion) {
            throw "MSIX version '$($identity.Version)' does not match expected version '$ExpectedPackageVersion': $Path"
        }

        $applications = @($manifest.Package.Applications.Application)
        if ($applications.Count -ne 1) {
            throw "MSIX must declare exactly one registered application: $Path"
        }
        $application = $applications[0]
        if ([string]$application.Id -cne $ExpectedApplicationId) {
            throw "MSIX application id '$($application.Id)' does not match '$ExpectedApplicationId': $Path"
        }
        if ([string]$application.Executable -cne "VFS\ProgramFilesX64\Iris\bin\iris-tauri.exe") {
            throw "MSIX registered application points at an unexpected executable: $($application.Executable)"
        }

        return [pscustomobject]@{
            Name = [string]$identity.Name
            Publisher = [string]$identity.Publisher
            Version = [string]$identity.Version
            ApplicationId = [string]$application.Id
            SignerThumbprint = ([string]$signature.SignerCertificate.Thumbprint).ToLowerInvariant()
        }
    } finally {
        $archive.Dispose()
    }
}

function Get-InstalledIrisPackage {
    param(
        [Parameter(Mandatory = $true)][string]$ExpectedPackageVersion
    )

    $packages = @(Get-AppxPackage -Name $PackageIdentityName -ErrorAction Stop)
    if ($packages.Count -ne 1) {
        throw "Expected exactly one installed '$PackageIdentityName' package, found $($packages.Count)."
    }
    $package = $packages[0]
    if ([string]$package.Publisher -cne $ExpectedPublisher) {
        throw "Installed package publisher '$($package.Publisher)' does not match '$ExpectedPublisher'."
    }
    if ([string]$package.Version -cne $ExpectedPackageVersion) {
        throw "Installed package version '$($package.Version)' does not match '$ExpectedPackageVersion'."
    }
    if (-not ([string]$package.PackageFamilyName).Trim()) {
        throw "Installed package did not expose a PackageFamilyName."
    }
    return $package
}

function Add-RegisteredApplicationActivationType {
    if ("IrisReleaseLifecycle.RegisteredApplicationLauncher" -as [type]) {
        return
    }

    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace IrisReleaseLifecycle
{
    [Flags]
    internal enum ActivateOptions
    {
        None = 0x00000000,
        DesignMode = 0x00000001,
        NoErrorUI = 0x00000002,
        NoSplashScreen = 0x00000004
    }

    [ComImport]
    [Guid("2e941141-7f97-4756-ba1d-9decde894a3d")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IApplicationActivationManager
    {
        [PreserveSig]
        int ActivateApplication(
            [MarshalAs(UnmanagedType.LPWStr)] string appUserModelId,
            [MarshalAs(UnmanagedType.LPWStr)] string arguments,
            ActivateOptions options,
            out uint processId);

        [PreserveSig]
        int ActivateForFile(
            [MarshalAs(UnmanagedType.LPWStr)] string appUserModelId,
            IntPtr itemArray,
            [MarshalAs(UnmanagedType.LPWStr)] string verb,
            out uint processId);

        [PreserveSig]
        int ActivateForProtocol(
            [MarshalAs(UnmanagedType.LPWStr)] string appUserModelId,
            IntPtr itemArray,
            out uint processId);
    }

    [ComImport]
    [Guid("45BA127D-10A8-46EA-8AB7-56EA9078943C")]
    internal class ApplicationActivationManager
    {
    }

    public static class RegisteredApplicationLauncher
    {
        public static uint Activate(string appUserModelId, string arguments)
        {
            IApplicationActivationManager manager =
                (IApplicationActivationManager)new ApplicationActivationManager();
            try
            {
                uint processId;
                int result = manager.ActivateApplication(
                    appUserModelId,
                    arguments,
                    ActivateOptions.None,
                    out processId);
                if (result < 0)
                {
                    Marshal.ThrowExceptionForHR(result);
                }
                return processId;
            }
            finally
            {
                Marshal.FinalReleaseComObject(manager);
            }
        }
    }
}
'@
}

function Invoke-IrisLifecycleProbe {
    param(
        [Parameter(Mandatory = $true)]$Package,
        [Parameter(Mandatory = $true)][string]$ExpectedStateRoot
    )

    Add-RegisteredApplicationActivationType
    $appUserModelId = "$([string]$Package.PackageFamilyName)!$ApplicationId"
    $arguments = "--msix-lifecycle-probe $TestContextId"
    $processId = [IrisReleaseLifecycle.RegisteredApplicationLauncher]::Activate(
        $appUserModelId,
        $arguments
    )
    if ($processId -le 0) {
        throw "Registered Iris activation did not return a process id."
    }

    $path = Join-Path $ExpectedStateRoot "diagnostics\msix-lifecycle-$TestContextId.json"
    $process = $null
    try {
        try {
            $process = [System.Diagnostics.Process]::GetProcessById([int]$processId)
        } catch [System.ArgumentException] {
            $process = $null
        }

        $deadline = [DateTime]::UtcNow.AddSeconds(30)
        while (-not (Test-Path -LiteralPath $path -PathType Leaf) -and
            [DateTime]::UtcNow -lt $deadline) {
            if ($process -and $process.HasExited -and $process.ExitCode -ne 0) {
                throw "Registered Iris lifecycle probe failed with exit code $($process.ExitCode)."
            }
            Start-Sleep -Milliseconds 100
        }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Registered Iris activation did not create its lifecycle state probe: $path"
        }
        if ($process -and -not $process.HasExited) {
            if (-not $process.WaitForExit(5000)) {
                $process.Kill()
                throw "Registered Iris lifecycle probe did not exit after writing its evidence."
            }
        }
        if ($process -and $process.HasExited -and $process.ExitCode -ne 0) {
            throw "Registered Iris lifecycle probe failed with exit code $($process.ExitCode)."
        }
    } finally {
        if ($process) {
            $process.Dispose()
        }
    }

    $content = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    try {
        $payload = $content | ConvertFrom-Json
    } catch {
        throw "Registered Iris lifecycle state probe is invalid JSON."
    }
    if (
        [int]$payload.schema -ne 1 -or
        [string]$payload.purpose -cne "signed-release-lifecycle" -or
        [string]$payload.test_context_id -cne $TestContextId -or
        [string]$payload.executable -cne "iris-tauri.exe" -or
        [long]$payload.created_utc_ms -le 0
    ) {
        throw "Registered Iris lifecycle state probe has invalid provenance."
    }

    return [pscustomobject]@{
        AppUserModelId = $appUserModelId
        Path = $path
        Content = $content
        Sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

if (-not $ConfirmDisposableTestGuest) {
    throw "Refusing to mutate AppX state. Pass -ConfirmDisposableTestGuest only inside a disposable clean Windows VM."
}
if ($TestContextId -notmatch "^iris-disposable-guest-[0-9a-fA-F]{32}$") {
    throw "TestContextId must be unique and match iris-disposable-guest-<32 hex characters>."
}
if (-not $ExpectedPublisher.Trim()) {
    throw "ExpectedPublisher must be the exact signing certificate subject."
}
if (-not $PackageIdentityName.Trim()) {
    throw "PackageIdentityName cannot be empty."
}
if (-not $ApplicationId.Trim()) {
    throw "ApplicationId cannot be empty."
}
if ($env:IRIS_DATA_ROOT) {
    throw "Clean-VM lifecycle testing requires IRIS_DATA_ROOT to be unset so the packaged default is exercised."
}

$releaseExpectedVersion = ConvertTo-MsixVersion -Value $ExpectedVersion -Name "ExpectedVersion"
if ($releaseExpectedVersion.ToString(4) -cne $ExpectedVersion) {
    throw "ExpectedVersion must use its canonical four-component form."
}
$releaseMsix = [System.IO.Path]::GetFullPath($MsixPath)
if (-not (Test-Path -LiteralPath $releaseMsix -PathType Leaf)) {
    throw "Production signed MSIX is missing: $releaseMsix"
}
$wackResolved = [System.IO.Path]::GetFullPath($WackReportPath)
if (Test-Path -LiteralPath $wackResolved) {
    throw "Refusing to overwrite an existing WACK report: $wackResolved"
}
$wackParent = Split-Path -Parent $wackResolved
if (-not $wackParent) {
    throw "WackReportPath must include a parent directory."
}
$evidenceResolved = [System.IO.Path]::GetFullPath($EvidencePath)
if (Test-Path -LiteralPath $evidenceResolved) {
    throw "Refusing to overwrite existing lifecycle evidence: $evidenceResolved"
}
if ($wackResolved.Equals(
        $evidenceResolved,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
    throw "WackReportPath and EvidencePath must be different files."
}
$evidenceParent = Split-Path -Parent $evidenceResolved
if (-not $evidenceParent) {
    throw "EvidencePath must include a parent directory."
}
if (-not $AppCertPath) {
    $windowsKitsRoot = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
    if (-not $windowsKitsRoot) {
        throw "ProgramFiles(x86) is unavailable; pass the exact App Certification Kit appcert.exe path."
    }
    $AppCertPath = Join-Path $windowsKitsRoot "Windows Kits\10\App Certification Kit\appcert.exe"
}
$appCertResolved = [System.IO.Path]::GetFullPath($AppCertPath)
if (-not (Test-Path -LiteralPath $appCertResolved -PathType Leaf)) {
    throw "Windows App Certification Kit appcert.exe is missing: $appCertResolved"
}

$windowsIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
try {
    $windowsPrincipal = New-Object Security.Principal.WindowsPrincipal($windowsIdentity)
    if (-not $windowsPrincipal.IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator
        )) {
        throw "WACK and lifecycle testing require an elevated disposable guest session."
    }
} finally {
    $windowsIdentity.Dispose()
}
if (-not [Environment]::UserInteractive) {
    throw "WACK and lifecycle testing require an active interactive user session."
}

foreach ($commandName in @(
        "Add-AppxPackage",
        "Get-AppxPackage",
        "Remove-AppxPackage",
        "Get-AuthenticodeSignature",
        "Get-CimInstance"
    )) {
    if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
        throw "Required Windows command is unavailable: $commandName"
    }
}

$computerSystem = Get-CimInstance Win32_ComputerSystem
$virtualIdentity = "$($computerSystem.Manufacturer) $($computerSystem.Model)".Trim()
if (
    -not $virtualIdentity -or
    $virtualIdentity.Length -gt 200 -or
    $virtualIdentity -match "[\x00-\x1f\x7f]"
) {
    throw "The virtual-machine identity is empty, too long, or contains control characters."
}
if ($virtualIdentity -notmatch "(?i)(virtual machine|vmware|virtualbox|kvm|qemu|xen|hvm domu|parallels|amazon ec2|google compute engine)") {
    throw "Refusing to run outside a recognized virtual machine. Detected host: $virtualIdentity"
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$releaseIdentity = Get-VerifiedMsixIdentity `
    -Path $releaseMsix `
    -ExpectedPackageVersion $ExpectedVersion `
    -ExpectedIdentityName $PackageIdentityName `
    -ExpectedIdentityPublisher $ExpectedPublisher `
    -ExpectedApplicationId $ApplicationId

$existingPackages = @(Get-AppxPackage -Name $PackageIdentityName -ErrorAction Stop)
if ($existingPackages.Count -ne 0) {
    throw "Refusing to replace an existing '$PackageIdentityName' installation. Start from a clean disposable guest."
}

$localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
if (-not $localAppData) {
    throw "The guest did not resolve a LocalApplicationData directory."
}
$localAppData = [System.IO.Path]::GetFullPath($localAppData).TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
)
if (-not $localAppData -or $localAppData -eq [System.IO.Path]::GetPathRoot($localAppData)) {
    throw "Refusing unsafe LocalApplicationData root: $localAppData"
}
$stateRoot = Join-Path $localAppData "Iris"
if (Test-Path -LiteralPath $stateRoot) {
    throw "Refusing to touch pre-existing Iris user state: $stateRoot"
}
$statePrefix = [System.IO.Path]::GetFullPath($stateRoot).TrimEnd("\") + "\"
if ($evidenceResolved.StartsWith($statePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "EvidencePath must remain outside the Iris state root."
}
if ($wackResolved.StartsWith($statePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "WackReportPath must remain outside the Iris state root."
}

$releaseSha256 = (
    Get-FileHash -LiteralPath $releaseMsix -Algorithm SHA256
).Hash.ToLowerInvariant()
[System.IO.Directory]::CreateDirectory($wackParent) | Out-Null
& $appCertResolved reset
if ($LASTEXITCODE -ne 0) {
    throw "WACK reset failed with exit code $LASTEXITCODE."
}
& $appCertResolved test `
    -appxpackagepath $releaseMsix `
    -reportoutputpath $wackResolved
if ($LASTEXITCODE -ne 0) {
    throw "WACK execution failed with exit code $LASTEXITCODE."
}
$releaseHashAfterWack = (
    Get-FileHash -LiteralPath $releaseMsix -Algorithm SHA256
).Hash.ToLowerInvariant()
if ($releaseHashAfterWack -cne $releaseSha256) {
    throw "The signed MSIX changed while WACK was testing it."
}
$wackReport = Get-VerifiedWackReport -Path $wackResolved
Write-Host "WACK passed against exact signed MSIX: $wackResolved"

$installAttempted = $false
$uninstallCompleted = $false

try {
    $installAttempted = $true
    Add-AppxPackage -Path $releaseMsix -ForceApplicationShutdown -Confirm:$false
    $releasePackage = Get-InstalledIrisPackage -ExpectedPackageVersion $ExpectedVersion
    Write-Host "Production release installed: $($releasePackage.PackageFullName)"

    $stateProbe = Invoke-IrisLifecycleProbe `
        -Package $releasePackage `
        -ExpectedStateRoot $stateRoot
    Write-Host "Registered Iris activation passed: $($stateProbe.AppUserModelId)"

    Remove-AppxPackage `
        -Package $releasePackage.PackageFullName `
        -PreserveApplicationData `
        -Confirm:$false
    $remainingPackages = @(Get-AppxPackage -Name $PackageIdentityName -ErrorAction Stop)
    if ($remainingPackages.Count -ne 0) {
        throw "Iris MSIX remained registered after uninstall."
    }
    $uninstallCompleted = $true

    if (-not (Test-Path -LiteralPath $stateRoot -PathType Container)) {
        throw "Iris state root did not survive uninstall: $stateRoot"
    }
    if (-not (Test-Path -LiteralPath $stateProbe.Path -PathType Leaf)) {
        throw "Iris-created lifecycle state did not survive uninstall: $($stateProbe.Path)"
    }
    $contentAfterUninstall = [System.IO.File]::ReadAllText(
        $stateProbe.Path,
        [System.Text.Encoding]::UTF8
    )
    if ($contentAfterUninstall -cne $stateProbe.Content) {
        throw "Iris-created lifecycle state changed during uninstall: $($stateProbe.Path)"
    }
    $hashAfterUninstall = (
        Get-FileHash -LiteralPath $stateProbe.Path -Algorithm SHA256
    ).Hash.ToLowerInvariant()
    if ($hashAfterUninstall -cne $stateProbe.Sha256) {
        throw "Iris-created lifecycle state hash changed during uninstall."
    }
    $releaseHashAfterLifecycle = (
        Get-FileHash -LiteralPath $releaseMsix -Algorithm SHA256
    ).Hash.ToLowerInvariant()
    if ($releaseHashAfterLifecycle -cne $releaseSha256) {
        throw "The signed MSIX changed during lifecycle testing."
    }

    $evidence = [ordered]@{
        schema = 3
        test_context_id = $TestContextId
        tested_utc = [DateTime]::UtcNow.ToString("o")
        virtual_machine = $virtualIdentity
        package_identity = $PackageIdentityName
        package_family_name = [string]$releasePackage.PackageFamilyName
        application_id = $ApplicationId
        app_user_model_id = $stateProbe.AppUserModelId
        publisher = $ExpectedPublisher
        signer_thumbprint = $releaseIdentity.SignerThumbprint
        release_version = $ExpectedVersion
        release_sha256 = $releaseSha256
        wack_package_sha256 = $releaseSha256
        wack_overall_result = "PASS"
        wack_report_sha256 = $wackReport.Sha256
        wack_report_length_bytes = $wackReport.Length
        install_succeeded = $true
        activation_succeeded = $true
        uninstall_succeeded = $true
        state_root = "%LOCALAPPDATA%\Iris"
        state_probe_sha256 = $stateProbe.Sha256
        state_probe_content_base64 = [Convert]::ToBase64String(
            [System.Text.Encoding]::UTF8.GetBytes($stateProbe.Content)
        )
        state_survived = $true
    }
    [System.IO.Directory]::CreateDirectory($evidenceParent) | Out-Null
    [System.IO.File]::WriteAllText(
        $evidenceResolved,
        ($evidence | ConvertTo-Json -Depth 3),
        (New-Object System.Text.UTF8Encoding($false))
    )

    Write-Host "Signed production MSIX guest lifecycle gauntlet passed."
    Write-Host "State preserved intentionally at: $stateRoot"
    Write-Host "Release evidence: $evidenceResolved"
    Write-Host "Discard this disposable guest after collecting the test evidence."
} finally {
    if ($installAttempted -and -not $uninstallCompleted) {
        $cleanupPackages = @(Get-AppxPackage -Name $PackageIdentityName -ErrorAction SilentlyContinue)
        foreach ($package in $cleanupPackages) {
            if ([string]$package.Publisher -ceq $ExpectedPublisher) {
                try {
                    Remove-AppxPackage `
                        -Package $package.PackageFullName `
                        -PreserveApplicationData `
                        -Confirm:$false `
                        -ErrorAction Stop
                } catch {
                    Write-Warning "Could not unregister test package '$($package.PackageFullName)': $($_.Exception.Message)"
                }
            }
        }
    }
}
