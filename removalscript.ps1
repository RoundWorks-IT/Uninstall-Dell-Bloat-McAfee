# RMM-ONLY SCRIPT
# Purpose: Remove Dell bloat and ANY McAfee products

$ErrorActionPreference = 'SilentlyContinue'

# -------------------------------------------------------------------
# Folder + logging (optional but handy)
# -------------------------------------------------------------------
$DebloatFolder = "C:\ProgramData\Debloat"
if (-not (Test-Path $DebloatFolder)) {
    New-Item -Path $DebloatFolder -ItemType Directory | Out-Null
}
Start-Transcript -Path "$DebloatFolder\Debloat.log" -ErrorAction SilentlyContinue

$startUtc = [datetime]::UtcNow

# -------------------------------------------------------------------
# Collect uninstall strings from HKLM (32-bit + 64-bit)
# -------------------------------------------------------------------
Write-Output "Gathering uninstall strings from registry..."

$allUninstallEntries = @()

$uninstallRoots = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

foreach ($root in $uninstallRoots) {
    if (-not (Test-Path $root)) { continue }

    Get-ChildItem -Path $root | ForEach-Object {
        try {
            $p = Get-ItemProperty -Path $_.PsPath
        } catch { return }

        if (-not $p.DisplayName) { return }

        $uninstallString = $p.UninstallString
        if (-not $uninstallString) { return }

        # Store raw info – we’ll normalise later
        $allUninstallEntries += [PSCustomObject]@{
            DisplayName     = $p.DisplayName
            UninstallString = $uninstallString
            QuietUninstall  = $p.QuietUninstallString
        }
    }
}

# -------------------------------------------------------------------
# Helper: normalised uninstall runner
# -------------------------------------------------------------------
function Invoke-UninstallString {
    param(
        [string]$UninstallString,
        [string]$QuietUninstallString
    )

    # Prefer quiet string if present
    $cmd = if ($QuietUninstallString) { $QuietUninstallString } else { $UninstallString }

    if (-not $cmd) { return }

    $cmd = $cmd.Trim()
    if (-not $cmd) { return }

    # -----------------------------
    # MSI uninstall – use msiexec
    # -----------------------------
    if ($cmd -match 'msiexec(\.exe)?') {
        # Strip "msiexec.exe" or "msiexec"
        $args = $cmd -replace 'msiexec(\.exe)?\s*', ''

        # Ensure we're uninstalling, not installing
        if ($args -match '/I') {
            $args = $args -replace '/I', '/X'
        }

        if ($args -notmatch '/quiet')     { $args += ' /quiet' }
        if ($args -notmatch '/norestart') { $args += ' /norestart' }

        Write-Output "  -> MSI uninstall: msiexec.exe $args"
        Start-Process -FilePath "msiexec.exe" -ArgumentList $args -Wait -NoNewWindow
        return
    }

    # ----------------------------------------
    # NON-MSI: parse EXE + arguments properly
    # ----------------------------------------
    $exe  = $null
    $args = ""

    $trimmed = $cmd.Trim()

    if ($trimmed.StartsWith('"')) {
        # Format: "C:\Path With Spaces\app.exe" /arg1 /arg2
        $secondQuoteIndex = $trimmed.IndexOf('"', 1)
        if ($secondQuoteIndex -lt 0) {
            # Only one quote – treat everything (minus quotes) as exe
            $exe = $trimmed.Trim('"')
        }
        else {
            $exe = $trimmed.Substring(1, $secondQuoteIndex - 1)
            if ($trimmed.Length -gt $secondQuoteIndex + 1) {
                $args = $trimmed.Substring($secondQuoteIndex + 1).Trim()
            }
        }
    }
    else {
        # Format: C:\Program Files\Vendor\App\uninstall.exe /arg1 /arg2
        $firstSpace = $trimmed.IndexOf(' ')
        if ($firstSpace -lt 0) {
            $exe = $trimmed
        }
        else {
            $exe  = $trimmed.Substring(0, $firstSpace)
            $args = $trimmed.Substring($firstSpace + 1).Trim()
        }
    }

    if (-not $exe) {
        Write-Output "  -> Unable to parse uninstall command: $cmd"
        return
    }

    Write-Output "  -> EXE uninstall: `"$exe`" $args"

    try {
        if ([string]::IsNullOrWhiteSpace($args)) {
            Start-Process -FilePath $exe -Wait -NoNewWindow
        }
        else {
            Start-Process -FilePath $exe -ArgumentList $args -Wait -NoNewWindow
        }
    }
    catch {
        Write-Output "  -> Failed to start uninstall process for `"$exe`": $_"
        throw
    }
}



# -------------------------------------------------------------------
# Helper: uninstall by product display name (exact or pattern)
# -------------------------------------------------------------------
function Uninstall-AppByName {
    param(
        [string]$NamePattern     # e.g. 'Dell Optimizer' or 'McAfee*'
    )

    $matches = $allUninstallEntries | Where-Object {
        $_.DisplayName -like $NamePattern
    }

    if (-not $matches) {
        Write-Output "No installed applications found matching: $NamePattern"
        return
    }

    foreach ($app in $matches) {
        Write-Output "Uninstalling: $($app.DisplayName)"
        try {
            Invoke-UninstallString -UninstallString $app.UninstallString -QuietUninstallString $app.QuietUninstall
            Write-Output "Successfully triggered uninstall for: $($app.DisplayName)"
        }
        catch {
            Write-Output "Failed to uninstall $($app.DisplayName): $_"
        }
    }
}

# -------------------------------------------------------------------
# DELL BOOTSTRAP
# -------------------------------------------------------------------
Write-Output "Detecting manufacturer..."
try {
    $details      = Get-CimInstance -ClassName Win32_ComputerSystem
    $manufacturer = $details.Manufacturer
    Write-Output "Manufacturer detected: $manufacturer"
} catch {
    Write-Output "Unable to detect manufacturer: $_"
}

if ($manufacturer -like "*Dell*") {
    Write-Output "Dell device detected – running Dell bloat removal..."

    $dellApps = @(
        "Dell Optimizer",
        "DellOptimizerUI",
        "Dell SupportAssist OS Recovery",
        "Dell SupportAssist",
        "Dell Optimizer Service",
        "Dell Optimizer Core",
        "DellInc.PartnerPromo",
        "DellInc.DellOptimizer",
        "DellInc.DellCommandUpdate",
        "DellInc.DellDigitalDelivery",
        "DellInc.DellSupportAssistforPCs",
        "Dell Command | Update",
        "Dell Command | Update for Windows Universal",
        "Dell Command | Update for Windows 10",
        "Dell Digital Delivery Service",
        "Dell Digital Delivery",
        "Dell SupportAssist Remediation",
        "SupportAssist Recovery Assistant",
        "Dell SupportAssist OS Recovery Plugin for Dell Update",
        "Dell SupportAssistAgent",
        "Dell Update - SupportAssist Update Plugin"
    )

    foreach ($app in $dellApps) {
        Uninstall-AppByName -NamePattern $app
    }

    # Extra direct clean-ups from original script
}
else {
    Write-Output "Non-Dell device – Dell removal section skipped."
}

# -------------------------------------------------------------------
# MCAFEE REMOVAL
# -------------------------------------------------------------------
Write-Output "Checking for McAfee products..."

$mcafeePresent = $false

foreach ($entry in $allUninstallEntries) {
    if ($entry.DisplayName -like "*McAfee*") {
        $mcafeePresent = $true
        break
    }
}

if ($mcafeePresent) {
    Write-Output "McAfee detected – running removal steps."

    # 1. Legacy McAfee cleanup tool
    try {
        Write-Output "Downloading legacy McAfee cleanup tool..."
        $urlLegacy      = 'https://github.com/RoundWorks-IT/Uninstall-Dell-Bloat-McAfee/blob/main/mcafeeclean.zip'
        $destLegacyZip  = "$DebloatFolder\mcafee.zip"
        Invoke-WebRequest -Uri $urlLegacy -OutFile $destLegacyZip -Method Get

        Expand-Archive $destLegacyZip -DestinationPath $DebloatFolder -Force

        Write-Output "Running legacy MCCleanup..."
        Start-Process "$DebloatFolder\Mccleanup.exe" -ArgumentList "-p StopServices,MFSY,PEF,MXD,CSP,Sustainability,MOCP,MFP,APPSTATS,Auth,EMproxy,FWdiver,HW,MAS,MAT,MBK,MCPR,McProxy,McSvcHost,VUL,MHN,MNA,MOBK,MPFP,MPFPCU,MPS,SHRED,MPSCU,MQC,MQCCU,MSAD,MSHR,MSK,MSKCU,MWL,NMC,RedirSvc,VS,REMEDIATION,MSC,YAP,TRUEKEY,LAM,PCB,Symlink,SafeConnect,MGS,WMIRemover,RESIDUEFWDRIVER,Redir,MSHR,WPS,MSSPlus -v -s" -NoNewWindow
    } catch {
        Write-Output "Failed to run legacy McAfee cleanup: $_"
    }

    # 2. New McAfee cleanup tool
    try {
        Write-Output "Downloading new McAfee cleanup tool..."
        $urlNew      = 'https://github.com/RoundWorks-IT/Uninstall-Dell-Bloat-McAfee/blob/main/mcafeeclean.zip'
        $destNewZip  = "$DebloatFolder\mcafeenew.zip"
        Invoke-WebRequest -Uri $urlNew -OutFile $destNewZip -Method Get

        $mcNewFolder = "$DebloatFolder\mcnew"
        if (-not (Test-Path $mcNewFolder)) {
            New-Item -Path $mcNewFolder -ItemType Directory | Out-Null
        }

        Expand-Archive $destNewZip -DestinationPath $mcNewFolder -Force

        Write-Output "Running new MCCleanup..."
        Start-Process "$mcNewFolder\Mccleanup.exe" -ArgumentList "-p StopServices,MFSY,PEF,MXD,CSP,Sustainability,MOCP,MFP,APPSTATS,Auth,EMproxy,FWdiver,HW,MAS,MAT,MBK,MCPR,McProxy,McSvcHost,VUL,MHN,MNA,MOBK,MPFP,MPFPCU,MPS,SHRED,MPSCU,MQC,MQCCU,MSAD,MSHR,MSK,MSKCU,MWL,NMC,RedirSvc,VS,REMEDIATION,MSC,YAP,TRUEKEY,LAM,PCB,Symlink,SafeConnect,MGS,WMIRemover,RESIDUE -v -s" -NoNewWindow
    } catch {
        Write-Output "Failed to run new McAfee cleanup: $_"
    }

    # 3. Uninstall any remaining McAfee entries via uninstall strings
    Write-Output "Attempting to uninstall any remaining McAfee entries via uninstall strings..."
    $mcafeeEntries = $allUninstallEntries | Where-Object { $_.DisplayName -like "*McAfee*" }

    foreach ($entry in $mcafeeEntries) {
        Write-Output "Processing: $($entry.DisplayName)"
        try {
            Invoke-UninstallString -UninstallString $entry.UninstallString -QuietUninstallString $entry.QuietUninstall
        } catch {
            Write-Output "Failed to uninstall $($entry.DisplayName): $_"
        }
    }

    # 4. McAfee Safe Connect
    Write-Output "Checking for 'McAfee Safe Connect'..."
    Uninstall-AppByName -NamePattern "McAfee Safe Connect*"

    # 5. Clean obvious leftovers
    if (Test-Path "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\McAfee") {
        Write-Output "Removing McAfee start menu folder..."
        Remove-Item "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\McAfee" -Recurse -Force
    }

    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\McAfee.WPS") {
        Write-Output "Removing leftover McAfee.WPS uninstall key..."
        Remove-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\McAfee.WPS" -Recurse -Force
    }

    # Remove McAfee UWP stub if provisioned
    try {
        Get-AppxProvisionedPackage -Online |
            Where-Object DisplayName -eq "McAfeeWPSSparsePackage" |
            Remove-AppxProvisionedPackage -Online -AllUsers
    } catch {
        Write-Output "Failed to remove McAfeeWPSSparsePackage provisioned package (if present): $_"
    }
}
else {
    Write-Output "No McAfee products detected – McAfee removal skipped."
}

# -------------------------------------------------------------------
# WRAP UP
# -------------------------------------------------------------------
$stopUtc = [datetime]::UtcNow
$runTime = $stopUtc - $startUtc

if ($runTime.TotalHours -ge 1) {
    $runTimeFormatted = 'Duration: {0:hh} hr {0:mm} min {0:ss} sec' -f $runTime
} else {
    $runTimeFormatted = 'Duration: {0:mm} min {0:ss} sec' -f $runTime
}

Write-Output "Completed. $runTimeFormatted"

Stop-Transcript -ErrorAction SilentlyContinue
