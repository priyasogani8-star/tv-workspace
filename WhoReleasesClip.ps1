# ============================================================
# WhoReleasesClip.ps1
# Monitors ClipCursor releases - logs which process/window
# was in the foreground each time the lock gets cleared.
# Run this, then do normal activity (click around, open apps).
# Press Ctrl+C to stop and see the report.
# ============================================================

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class CursorMonitor {
    [DllImport("user32.dll")] public static extern bool ClipCursor(ref RECT r);
    [DllImport("user32.dll")] public static extern bool ClipCursor(IntPtr r);
    [DllImport("user32.dll")] public static extern bool GetClipCursor(ref RECT r);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
    [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr hWnd, out int pid);
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
}
"@

Add-Type -AssemblyName System.Windows.Forms
$laptop   = [System.Windows.Forms.Screen]::PrimaryScreen
$b        = $laptop.Bounds

$lockRect = New-Object CursorMonitor+RECT
$lockRect.Left = $b.Left; $lockRect.Top = $b.Top
$lockRect.Right = $b.Right; $lockRect.Bottom = $b.Bottom

# Apply initial lock
[CursorMonitor]::ClipCursor([ref]$lockRect) | Out-Null

$releases = @()
$checkRect = New-Object CursorMonitor+RECT

Write-Host ""
Write-Host "  Monitoring... move mouse, click things, switch windows." -ForegroundColor Yellow
Write-Host "  Lock re-applies instantly. Press Ctrl+C to see report." -ForegroundColor Yellow
Write-Host ""

try {
    while ($true) {
        [CursorMonitor]::GetClipCursor([ref]$checkRect) | Out-Null

        # Detect if clip was released (rect expanded beyond laptop bounds)
        $released = ($checkRect.Left  -lt $b.Left)  -or
                    ($checkRect.Top   -lt $b.Top)    -or
                    ($checkRect.Right -gt $b.Right)  -or
                    ($checkRect.Bottom -gt $b.Bottom)

        if ($released) {
            # Snap lock back immediately
            [CursorMonitor]::ClipCursor([ref]$lockRect) | Out-Null

            # Identify foreground window + process
            $hwnd = [CursorMonitor]::GetForegroundWindow()
            $title = New-Object System.Text.StringBuilder 256
            [CursorMonitor]::GetWindowText($hwnd, $title, 256) | Out-Null
            $pid = 0
            [CursorMonitor]::GetWindowThreadProcessId($hwnd, [ref]$pid) | Out-Null
            $proc = try { (Get-Process -Id $pid -ErrorAction Stop).Name } catch { "PID $pid" }

            $entry = [PSCustomObject]@{
                Time    = (Get-Date).ToString("HH:mm:ss.fff")
                Process = $proc
                Title   = $title.ToString()
                Rect    = "L=$($checkRect.Left) T=$($checkRect.Top) R=$($checkRect.Right) B=$($checkRect.Bottom)"
            }
            $releases += $entry
            Write-Host "  [$($entry.Time)] RELEASED by: $($entry.Process)  |  '$($entry.Title)'" -ForegroundColor Red
        }

        Start-Sleep -Milliseconds 30
    }
} finally {
    [CursorMonitor]::ClipCursor([IntPtr]::Zero) | Out-Null
    Write-Host ""
    Write-Host "  === REPORT: $($releases.Count) release(s) detected ===" -ForegroundColor Cyan
    if ($releases.Count -gt 0) {
        $releases | Group-Object Process | Sort-Object Count -Descending | ForEach-Object {
            Write-Host "  $($_.Count)x  $($_.Name)" -ForegroundColor White
        }
    }
    Write-Host ""
    Write-Host "  Press Enter to close..." -ForegroundColor Gray
    Read-Host | Out-Null
}
