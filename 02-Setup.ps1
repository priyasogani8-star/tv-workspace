# ============================================================
# TV Workspace - 02-Setup.ps1
# One-time setup: enables Remote Desktop, installs RDP Wrapper.
# RDP Wrapper is required to allow loopback RDP on Windows
# Home editions (which block it by default).
# Run this ONCE during first-time setup.
# ============================================================

function Log($msg)  { Write-Host "  $msg" -ForegroundColor Cyan }
function OK($msg)   { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "  [!]  $msg" -ForegroundColor Yellow }
function Fail($msg) {
    Write-Host "  [X]  $msg" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Press Enter to close..." -ForegroundColor Gray
    Read-Host | Out-Null
    exit 1
}

Write-Host ""
Write-Host "  TV Workspace - System Setup" -ForegroundColor White
Write-Host "  ============================" -ForegroundColor DarkGray
Write-Host ""

# ============================================================
# CHECK 1 - WINDOWS VERSION
# ============================================================
Log "Checking Windows version..."
$osVer = [System.Environment]::OSVersion.Version
$winBuild = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentBuildNumber
$winName  = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").ProductName

OK "$winName  (Build $winBuild)"

if ($osVer.Major -lt 10) {
    Fail "Windows 10 or later is required. Your version: $winName"
}

# ============================================================
# CHECK 2 - ENABLE REMOTE DESKTOP
# ============================================================
Log "Enabling Remote Desktop..."

# Enable RDP in registry
Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" `
    -Name "fDenyTSConnections" -Value 0 -ErrorAction SilentlyContinue

# Disable NLA requirement (so loopback RDP works without domain)
Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" `
    -Name "UserAuthentication" -Value 0 -ErrorAction SilentlyContinue

# Allow loopback connections (needed for 127.0.0.2 trick)
$loopbackKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"
if (-not (Test-Path $loopbackKey)) {
    New-Item -Path $loopbackKey -Force | Out-Null
}

# Allow firewall rule for Remote Desktop
try {
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
    OK "Remote Desktop enabled and firewall rule activated"
} catch {
    Warn "Could not update firewall rule automatically. If RDP fails, manually allow Remote Desktop in Windows Firewall."
}

# ============================================================
# CHECK 3 - RDP WRAPPER
# ============================================================
Log "Checking RDP Wrapper..."

$rdpwrapDir  = "C:\Program Files\RDP Wrapper"
$rdpwrapExe  = "$rdpwrapDir\RDPWInst.exe"
$rdpwrapIni  = "$rdpwrapDir\rdpwrap.ini"
$tsDll       = "$env:SystemRoot\System32\termsrv.dll"
$tsVer       = (Get-Item $tsDll -ErrorAction SilentlyContinue).VersionInfo.FileVersion
$tsBuild     = if ($tsVer) { $tsVer.Split('.')[3].Trim().Split(' ')[0] } else { "unknown" }

if (Test-Path $rdpwrapExe) {
    OK "RDP Wrapper already installed at: $rdpwrapDir"

    # Check if current build is supported
    if (Test-Path $rdpwrapIni) {
        $iniContent = Get-Content $rdpwrapIni -Raw
        if ($iniContent -match [regex]::Escape($tsBuild)) {
            OK "INI supports current Windows build ($tsBuild) - all good!"
        } else {
            Warn "INI may not support build $tsBuild yet."
            Warn "StartTV.bat will try to auto-update the INI when you run it."
        }
    }
} else {
    Write-Host ""
    Write-Host "  RDP Wrapper is not installed." -ForegroundColor Yellow
    Write-Host "  It is required to enable concurrent RDP sessions on Windows Home/Pro." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Downloading from GitHub (stascorp/rdpwrap)..." -ForegroundColor Cyan

    # Fetch latest release info
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    try {
        $releaseApi = "https://api.github.com/repos/stascorp/rdpwrap/releases/latest"
        $releaseInfo = Invoke-RestMethod -Uri $releaseApi -TimeoutSec 15
        $zipAsset = $releaseInfo.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1
        if (-not $zipAsset) { throw "No zip asset found in latest release" }

        $zipUrl  = $zipAsset.browser_download_url
        $zipPath = "$env:TEMP\rdpwrap.zip"
        $extPath = "$env:TEMP\rdpwrap-install"

        Log "Downloading $($zipAsset.name) ($([math]::Round($zipAsset.size/1KB)) KB)..."
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing -TimeoutSec 60

        Log "Extracting..."
        if (Test-Path $extPath) { Remove-Item $extPath -Recurse -Force }
        Expand-Archive -Path $zipPath -DestinationPath $extPath -Force

        $installer = Get-ChildItem -Path $extPath -Filter "RDPWInst.exe" -Recurse | Select-Object -First 1
        if (-not $installer) { throw "RDPWInst.exe not found in downloaded zip" }

        Log "Installing RDP Wrapper (this patches termsrv.dll)..."
        $result = Start-Process -FilePath $installer.FullName -ArgumentList "-i" -Wait -PassThru -WindowStyle Hidden
        if ($result.ExitCode -ne 0) { throw "Installer exited with code $($result.ExitCode)" }

        # Clean up
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
        Remove-Item $extPath -Recurse -Force -ErrorAction SilentlyContinue

        if (Test-Path $rdpwrapExe) {
            OK "RDP Wrapper installed successfully!"
        } else {
            Fail "Installation appeared to complete but RDPWInst.exe not found. Try running the installer manually."
        }

    } catch {
        Write-Host ""
        Write-Host "  [X] Auto-download failed: $_" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Manual install steps:" -ForegroundColor Yellow
        Write-Host "  1. Open this link in your browser:" -ForegroundColor White
        Write-Host "     https://github.com/stascorp/rdpwrap/releases/latest" -ForegroundColor Cyan
        Write-Host "  2. Download the .zip file" -ForegroundColor White
        Write-Host "  3. Extract it and run RDPWInst.exe as Administrator" -ForegroundColor White
        Write-Host "  4. Run this script (02-Setup.bat) again to verify" -ForegroundColor White
        Write-Host ""
        Write-Host "  Press Enter to close..." -ForegroundColor Gray
        Read-Host | Out-Null
        exit 1
    }
}

# ============================================================
# CHECK 4 - DOWNLOAD COMMUNITY INI (for current build)
# ============================================================
Log "Checking community INI for build $tsBuild..."

$INI_SOURCES = @(
    "https://raw.githubusercontent.com/sebaxakerhtc/rdpwrap.ini/master/rdpwrap.ini",
    "https://raw.githubusercontent.com/asmtron/rdpwrap/master/res/rdpwrap.ini",
    "https://raw.githubusercontent.com/stascorp/rdpwrap/master/res/rdpwrap.ini"
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$bestIni = $null

foreach ($url in $INI_SOURCES) {
    try {
        $candidate = (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 8).Content
        # Basic safety: must be text with INI structure
        if ($candidate -match '\[10\.\d+\.\d+\.\d+' -and $candidate -match 'LocalOnlyPatch') {
            if ($candidate -match [regex]::Escape($tsBuild)) {
                $bestIni = $candidate
                OK "Found INI with support for your build at: $($url.Split('/')[4])"
                break
            } elseif (-not $bestIni) {
                $bestIni = $candidate  # Fallback: most up-to-date even if build not yet listed
            }
        }
    } catch { <# source unavailable, try next #> }
}

if ($bestIni -and (Test-Path $rdpwrapIni)) {
    Stop-Service TermService -Force -ErrorAction SilentlyContinue
    Start-Sleep 2
    $bestIni | Out-File -FilePath $rdpwrapIni -Encoding UTF8 -Force
    Start-Service TermService -ErrorAction SilentlyContinue
    Start-Sleep 2
    OK "Community INI applied"
} elseif (-not $bestIni) {
    Warn "Could not reach any INI source - check your internet connection."
    Warn "StartTV.bat will retry this automatically each time you run it."
}

# ============================================================
# CHECK 5 - VERIFY CONFIG FILE EXISTS
# ============================================================
$configFile = "$PSScriptRoot\tv-config.local.ps1"
if (-not (Test-Path $configFile)) {
    Write-Host ""
    Warn "tv-config.local.ps1 not found."
    Warn "Make sure you ran 01-CreateTVUser.bat first!"
    Write-Host ""
} else {
    OK "Config file found (tv-config.local.ps1)"
}

Write-Host ""
Write-Host "  +---------------------------------------------+" -ForegroundColor Green
Write-Host "  |  Step 2 Complete!                           |" -ForegroundColor Green
Write-Host "  |  System is ready for TV sessions.           |" -ForegroundColor Green
Write-Host "  |                                             |" -ForegroundColor Green
Write-Host "  |  Next: Plug in your HDMI cable, turn on     |" -ForegroundColor Green
Write-Host "  |  your TV, then run StartTV.bat              |" -ForegroundColor Green
Write-Host "  +---------------------------------------------+" -ForegroundColor Green
Write-Host ""
Write-Host "  Press Enter to close..." -ForegroundColor Gray
Read-Host | Out-Null
