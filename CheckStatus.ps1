# ============================================================
# TV Workspace - CheckStatus.ps1
# Checks all requirements and shows green/red for each.
# Run this any time to see what's working and what's not.
# No admin required.
# ============================================================

Add-Type -AssemblyName System.Windows.Forms

function Pass($label) {
    Write-Host "  [OK] " -ForegroundColor Green -NoNewline
    Write-Host $label
}
function Fail($label, $hint) {
    Write-Host "  [X]  " -ForegroundColor Red -NoNewline
    Write-Host $label
    if ($hint) { Write-Host "       --> $hint" -ForegroundColor Yellow }
}
function Warn($label, $hint) {
    Write-Host "  [!]  " -ForegroundColor Yellow -NoNewline
    Write-Host $label
    if ($hint) { Write-Host "       --> $hint" -ForegroundColor DarkYellow }
}
function Section($title) {
    Write-Host ""
    Write-Host "  $title" -ForegroundColor White
    Write-Host "  $("-" * $title.Length)" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "  TV Workspace - Status Check" -ForegroundColor Cyan
Write-Host "  =============================" -ForegroundColor DarkGray

# ============================================================
# SECTION 1: WINDOWS
# ============================================================
Section "Windows"

$os = [System.Environment]::OSVersion.Version
$build = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue).CurrentBuildNumber
$winName = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue).ProductName

if ($os.Major -ge 10) {
    Pass "$winName  (Build $build)"
} else {
    Fail "$winName - Windows 10 or 11 required" "Upgrade your Windows version"
}

# ============================================================
# SECTION 2: DISPLAY
# ============================================================
Section "Display"

$screens = [System.Windows.Forms.Screen]::AllScreens
if ($screens.Count -ge 2) {
    $tv = $screens | Where-Object { -not $_.Primary } | Select-Object -First 1
    Pass "$($screens.Count) screens detected  (TV/monitor: $($tv.Bounds.Width)x$($tv.Bounds.Height))"
} else {
    Warn "Only 1 screen detected - TV/monitor not connected" "Plug in your HDMI cable and turn the TV on, then re-run this check"
}

$rdpEnabled = (Get-ItemProperty "HKLM:\System\CurrentControlSet\Control\Terminal Server" -ErrorAction SilentlyContinue).fDenyTSConnections
if ($rdpEnabled -eq 0) {
    Pass "Remote Desktop is enabled"
} else {
    Fail "Remote Desktop is disabled" "Run 02-Setup.bat to enable it"
}

# ============================================================
# SECTION 3: RDP WRAPPER
# ============================================================
Section "RDP Wrapper"

$rdpwrapDir = "C:\Program Files\RDP Wrapper"
$rdpwrapExe = "$rdpwrapDir\RDPWInst.exe"
$rdpwrapIni = "$rdpwrapDir\rdpwrap.ini"

if (Test-Path $rdpwrapExe) {
    Pass "RDP Wrapper installed  ($rdpwrapDir)"
} else {
    Fail "RDP Wrapper not installed" "Run 02-Setup.bat to install it"
}

if (Test-Path $rdpwrapIni) {
    $tsDll   = "$env:SystemRoot\System32\termsrv.dll"
    $tsVer   = (Get-Item $tsDll -ErrorAction SilentlyContinue).VersionInfo.FileVersion
    $tsBuild = if ($tsVer) { $tsVer.Split('.')[3].Trim().Split(' ')[0] } else { "unknown" }
    $iniContent = Get-Content $rdpwrapIni -Raw -ErrorAction SilentlyContinue

    if ($iniContent -match [regex]::Escape($tsBuild)) {
        Pass "INI supports current Windows build ($tsBuild)"
    } else {
        Warn "INI may not support current build ($tsBuild)" "Run StartTV.bat - it auto-downloads the patch, or wait 24h after a Windows Update"
    }
} else {
    Fail "rdpwrap.ini not found" "Run 02-Setup.bat to download it"
}

# Check RDP Wrapper service status
$rdpwrapSvc = Get-Service -Name "RDPWrap" -ErrorAction SilentlyContinue
if ($rdpwrapSvc) {
    if ($rdpwrapSvc.Status -eq "Running") {
        Pass "RDPWrap service is running"
    } else {
        Warn "RDPWrap service is $($rdpwrapSvc.Status)" "Try restarting: net start RDPWrap (run as admin)"
    }
} else {
    if (Test-Path $rdpwrapExe) {
        Warn "RDPWrap service not found - may need reinstall" "Run 02-Setup.bat"
    }
}

# ============================================================
# SECTION 4: TV USER ACCOUNT
# ============================================================
Section "TV User Account"

$configFile = "$PSScriptRoot\tv-config.local.ps1"
if (Test-Path $configFile) {
    Pass "Config file found  (tv-config.local.ps1)"
    . $configFile  # load $TV_USERNAME, $TV_PASSWORD

    $tvUser = Get-LocalUser -Name $TV_USERNAME -ErrorAction SilentlyContinue
    if ($tvUser) {
        Pass "Windows user '$TV_USERNAME' exists"
        if ($tvUser.Enabled) {
            Pass "Account is enabled"
        } else {
            Fail "Account '$TV_USERNAME' is disabled" "Enable it via Settings > Accounts > Family & other users"
        }

        # Check Remote Desktop Users group membership
        $rdpGroup = Get-LocalGroupMember -Group "Remote Desktop Users" -ErrorAction SilentlyContinue
        $inRdpGroup = $rdpGroup | Where-Object { $_.Name -like "*$TV_USERNAME*" }
        if ($inRdpGroup) {
            Pass "'$TV_USERNAME' is in Remote Desktop Users group"
        } else {
            Warn "'$TV_USERNAME' not in Remote Desktop Users group" "Run 01-CreateTVUser.bat again to fix this"
        }

        # Verify saved password works
        try {
            Add-Type -AssemblyName System.DirectoryServices.AccountManagement -ErrorAction SilentlyContinue
            $ctx = New-Object System.DirectoryServices.AccountManagement.PrincipalContext(
                [System.DirectoryServices.AccountManagement.ContextType]::Machine)
            $valid = $ctx.ValidateCredentials($TV_USERNAME, $TV_PASSWORD)
            if ($valid) {
                Pass "Saved password is correct"
            } else {
                Fail "Saved password does not match account" "Run 01-CreateTVUser.bat to reset and re-save the password"
            }
        } catch {
            Warn "Could not verify password (run as non-admin)" $null
        }
    } else {
        Fail "Windows user '$TV_USERNAME' does not exist" "Run 01-CreateTVUser.bat to create it"
    }
} else {
    Fail "Config file missing  (tv-config.local.ps1)" "Run 01-CreateTVUser.bat - it creates this file"
}

# Check Credential Manager
$credCheck = & cmdkey /list:TERMSRV/127.0.0.2 2>&1
if ($credCheck -match "127.0.0.2") {
    Pass "Credentials saved in Windows Credential Manager"
} else {
    Warn "Credential Manager entry not found for 127.0.0.2" "Run StartTV.bat once - it saves credentials automatically"
}

# ============================================================
# SECTION 5: FIREWALL
# ============================================================
Section "Firewall"

try {
    $rdpRule = Get-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($rdpRule -and $rdpRule.Enabled -eq "True") {
        Pass "Remote Desktop firewall rule is active"
    } else {
        Warn "Remote Desktop firewall rule may be disabled" "Run 02-Setup.bat to fix this"
    }
} catch {
    Warn "Could not check firewall rules (need admin for full check)" $null
}

# ============================================================
# SUMMARY
# ============================================================
Write-Host ""
Write-Host "  ================================" -ForegroundColor DarkGray
Write-Host "  If everything shows [OK]: run StartTV.bat" -ForegroundColor White
Write-Host "  Any [X] errors: follow the --> hints above" -ForegroundColor White
Write-Host "  See TROUBLESHOOT.md for detailed help" -ForegroundColor DarkGray
Write-Host "  ================================" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Press Enter to close..." -ForegroundColor Gray
Read-Host | Out-Null
