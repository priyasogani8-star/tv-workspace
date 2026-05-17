# ============================================================
# TV Workspace - StartTV.ps1
# - Ensures extended display on TV
# - Auto-patches RDP Wrapper if community update available
# - Launches RDP session on TV screen
# - All extra windows suppressed / minimized silently
# - Run LockCursor.bat separately to lock cursor to laptop
# ============================================================

Add-Type -AssemblyName System.Windows.Forms

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinApi {
    [DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string t);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr i, int x, int y, int w, int ht, uint f);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
}
"@

# ---- Load local config (created by 01-CreateTVUser.bat) ----
$configFile = "$PSScriptRoot\tv-config.local.ps1"
if (-not (Test-Path $configFile)) {
    Write-Host ""
    Write-Host "  [X] Setup not complete." -ForegroundColor Red
    Write-Host "      Run 01-CreateTVUser.bat first, then 02-Setup.bat." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Press Enter to close..." -ForegroundColor Gray
    Read-Host | Out-Null
    exit 1
}
. $configFile   # loads $TV_USERNAME and $TV_PASSWORD

$TV_FULLUSER  = "$env:COMPUTERNAME\$TV_USERNAME"
$WRAP_INI     = "C:\Program Files\RDP Wrapper\rdpwrap.ini"
$RDP_FILE     = "$PSScriptRoot\TVSession.rdp"

# Multiple community INI sources - tried in order until one works
$INI_SOURCES = @(
    "https://raw.githubusercontent.com/sebaxakerhtc/rdpwrap.ini/master/rdpwrap.ini",
    "https://raw.githubusercontent.com/asmtron/rdpwrap/master/res/rdpwrap.ini",
    "https://raw.githubusercontent.com/llccd/rdpwrap/master/res/rdpwrap.ini",
    "https://raw.githubusercontent.com/stascorp/rdpwrap/master/res/rdpwrap.ini"
)

# ---- INI Safety Validator ----
# Checks the downloaded content BEFORE applying it to your system.
function Test-IniSafe {
    param([string]$content)

    # 1. Size check: real INI files are 50KB–3MB
    $bytes = [System.Text.Encoding]::UTF8.GetByteCount($content)
    if ($bytes -lt 50000 -or $bytes -gt 3145728) {
        Warn "  INI rejected: unexpected file size ($bytes bytes). Skipping source."
        return $false
    }

    # 2. Must contain Windows version section headers like [10.0.XXXXX.XXXX]
    if ($content -notmatch '\[10\.\d+\.\d+\.\d+') {
        Warn "  INI rejected: missing Windows version headers. Not a valid rdpwrap.ini."
        return $false
    }

    # 3. Must contain known RDPWrap parameter names
    $requiredKeys = @("LocalOnlyPatch","SLInitHookOffset","SLInitOffset","SingleUserPatch")
    $found = ($requiredKeys | Where-Object { $content -match $_ }).Count
    if ($found -lt 2) {
        Warn "  INI rejected: missing expected RDPWrap parameters. Possibly tampered."
        return $false
    }

    # 4. Must NOT contain executable-like or script content
    $dangerous = @("powershell","cmd.exe","base64","invoke-","iex ","wget ","curl ",
                   "http://","<script","eval(","exec(","shell(",".exe","MZ`u0000")
    foreach ($bad in $dangerous) {
        if ($content.ToLower() -match [regex]::Escape($bad.ToLower())) {
            Warn "  INI rejected: contains suspicious content ('$bad'). Skipping source."
            return $false
        }
    }

    # 5. Values must only be hex offsets, numbers, or 0/1 flags - no random strings
    $nonIniLines = ($content -split "`n") | Where-Object {
        $_ -notmatch '^\s*$' -and
        $_ -notmatch '^\s*[;#]' -and
        $_ -notmatch '^\s*\[' -and
        $_ -notmatch '^\s*\w[\w\.]*\s*='
    }
    if ($nonIniLines.Count -gt 20) {
        Warn "  INI rejected: too many unrecognised lines ($($nonIniLines.Count)). Skipping source."
        return $false
    }

    return $true
}

function Log($msg)  { Write-Host "  $msg" -ForegroundColor Cyan }
function OK($msg)   { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "  [!]  $msg" -ForegroundColor Yellow }
function Fail($msg) {
    Write-Host "  [X]  $msg" -ForegroundColor Red
    Write-Host ""
    Write-Host "Press Enter to close..." -ForegroundColor Gray
    Read-Host | Out-Null
    exit 1
}

Write-Host ""
Write-Host "  TV Workspace Starting..." -ForegroundColor White
Write-Host ""

# ============================================================
# STEP 1 - DISPLAY: ENSURE EXTENDED (NOT MIRRORED)
# ============================================================
Log "Checking display..."
$screens = [System.Windows.Forms.Screen]::AllScreens

if ($screens.Count -lt 2) {
    Log "TV not detected - activating..."
    Start-Process "DisplaySwitch.exe" -ArgumentList "/extend" -WindowStyle Hidden
    Start-Sleep 4
    $screens = [System.Windows.Forms.Screen]::AllScreens
    if ($screens.Count -lt 2) {
        Fail "TV not found. Plug in HDMI cable, turn TV on, then try again."
    }
}

Start-Process "DisplaySwitch.exe" -ArgumentList "/extend" -WindowStyle Hidden
Start-Sleep 2

$laptop = [System.Windows.Forms.Screen]::PrimaryScreen
$tv     = [System.Windows.Forms.Screen]::AllScreens | Where-Object { -not $_.Primary } | Select-Object -First 1

if (-not $tv) { Fail "TV not set as extended display. Check display settings." }

$tvL = $tv.Bounds.Left;   $tvT = $tv.Bounds.Top
$tvW = $tv.Bounds.Width;  $tvH = $tv.Bounds.Height
OK "TV screen: ${tvW}x${tvH}  |  Laptop: $($laptop.Bounds.Width)x$($laptop.Bounds.Height)"

# ============================================================
# STEP 2 - RDP WRAPPER: AUTO-PATCH IF COMMUNITY UPDATE READY
# ============================================================
Log "Checking RDP Wrapper..."

$tsDll   = "$env:SystemRoot\System32\termsrv.dll"
$tsVer   = (Get-Item $tsDll -ErrorAction SilentlyContinue).VersionInfo.FileVersion
$tsBuild = if ($tsVer) { $tsVer.Split('.')[3].Trim().Split(' ')[0] } else { "unknown" }

$rdpReady = $false

if (Test-Path $WRAP_INI) {
    $iniContent = Get-Content $WRAP_INI -Raw
    if ($iniContent -match [regex]::Escape($tsBuild)) {
        OK "RDP Wrapper already supports build $tsBuild"
        $rdpReady = $true
    } else {
        Log "Build $tsBuild not in current INI - searching $($INI_SOURCES.Count) community sources..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $patchedIni = $null

        foreach ($url in $INI_SOURCES) {
            try {
                $candidate = (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 8).Content
                if (-not (Test-IniSafe $candidate)) { continue }
                if ($candidate -match [regex]::Escape($tsBuild)) {
                    Log "  Found patch at: $($url.Split('/')[4])/$($url.Split('/')[5])"
                    $patchedIni = $candidate
                    break
                }
            } catch { <# source unavailable, try next #> }
        }

        if ($patchedIni) {
            Log "Applying patch (stopping TermService)..."
            Stop-Service TermService -Force -ErrorAction SilentlyContinue
            Start-Sleep 2
            $patchedIni | Out-File -FilePath $WRAP_INI -Encoding UTF8 -Force
            Start-Service TermService -ErrorAction SilentlyContinue
            Start-Sleep 3
            OK "RDP Wrapper patched for build $tsBuild - ready!"
            $rdpReady = $true
        } else {
            Warn "Build $tsBuild not patched by community yet (checked $($INI_SOURCES.Count) sources)."
            Warn ""
            Warn "This happens 0-48 hours after a Windows update."
            Warn "Try again tomorrow - the script will auto-fix when the patch lands."
            Warn ""
            Warn "Your workspace and scripts are ready. Just re-run StartTV.bat tomorrow."
            Write-Host ""
            Write-Host "  Press Enter to close..." -ForegroundColor Gray
            Read-Host | Out-Null
            exit 0
        }
    }
} else {
    Fail "RDP Wrapper not installed. Run 02-Setup.bat first."
}

if (-not $rdpReady) { exit 0 }

# ============================================================
# STEP 3 - CREDENTIALS: SAVE SILENTLY FOR LOOPBACK
# ============================================================
Log "Saving credentials..."
& cmdkey /delete:TERMSRV/127.0.0.2 2>&1 | Out-Null
& cmdkey /generic:TERMSRV/127.0.0.2 /user:$TV_FULLUSER /pass:$TV_PASSWORD 2>&1 | Out-Null
Set-LocalUser -Name $TV_USERNAME -PasswordNeverExpires $true -ErrorAction SilentlyContinue
OK "Credentials saved"

# ============================================================
# STEP 4 - RDP FILE: BUILD SESSION FILE FOR TV
# ============================================================
@"
full address:s:127.0.0.2
username:s:$TV_FULLUSER
authentication level:i:0
negotiate security layer:i:1
prompt for credentials:i:0
desktopwidth:i:$tvW
desktopheight:i:$tvH
screen mode id:i:2
smart sizing:i:0
winposstr:s:0,1,$tvL,$tvT,$($tvL + $tvW),$($tvT + $tvH)
disable wallpaper:i:1
disable full window drag:i:1
disable themes:i:0
allow font smoothing:i:1
redirectclipboard:i:0
"@ | Out-File -FilePath $RDP_FILE -Encoding ASCII -Force

OK "RDP session file created"

# ============================================================
# STEP 5 - LAUNCH RDP WINDOW ON TV
# ============================================================
Log "Launching TV session..."
$mstscPath = "$env:SystemRoot\System32\mstsc.exe"
if (-not (Test-Path $mstscPath)) {
    Log "mstsc.exe missing - restoring Remote Desktop feature via DISM..."
    & dism /online /Enable-Feature /FeatureName:Microsoft-RemoteDesktopConnection /NoRestart 2>&1 | Out-Null
    if (-not (Test-Path $mstscPath)) {
        Fail "mstsc.exe still missing after DISM restore. Restart your PC and try again."
    }
    OK "Remote Desktop feature restored"
}
Start-Process $mstscPath -ArgumentList $RDP_FILE -WindowStyle Normal

# Wait for RDP window to appear (retry up to 20s)
$rdpHwnd = [IntPtr]::Zero
for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep 1
    $rdpHwnd = [WinApi]::FindWindow("TscShellContainerClass", $null)
    if ($rdpHwnd -ne [IntPtr]::Zero) { break }
}

if ($rdpHwnd -ne [IntPtr]::Zero) {
    Start-Sleep 2
    [WinApi]::ShowWindow($rdpHwnd, 1)   | Out-Null
    [WinApi]::SetWindowPos($rdpHwnd, [IntPtr]::Zero, $tvL, $tvT, $tvW, $tvH, 0x0040) | Out-Null
    [WinApi]::ShowWindow($rdpHwnd, 3)   | Out-Null
    OK "RDP window placed on TV"
} else {
    Warn "Could not position RDP window - drag it to the TV manually if needed"
}

Write-Host ""
Write-Host "  +-----------------------------------------+" -ForegroundColor Yellow
Write-Host "  |   TV WORKSPACE RUNNING                  |" -ForegroundColor Yellow
Write-Host "  |   Session launched on TV                |" -ForegroundColor Yellow
Write-Host "  |   Run LockCursor.bat to lock mouse      |" -ForegroundColor Yellow
Write-Host "  +-----------------------------------------+" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Press Enter to close..." -ForegroundColor Gray
Read-Host | Out-Null
