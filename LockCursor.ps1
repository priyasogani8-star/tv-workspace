# ============================================================
# LockCursor.ps1  (D:\TVWorkspace)
# Locks cursor to laptop (primary) screen.
# Re-applies every 200ms so window focus changes can't break it.
# Run this anytime the TV is connected but you're working on laptop.
# Close this window to unlock the cursor.
# ============================================================

Add-Type -AssemblyName System.Windows.Forms

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class CursorLock {
    [DllImport("user32.dll")] public static extern bool ClipCursor(ref RECT r);
    [DllImport("user32.dll")] public static extern bool ClipCursor(IntPtr r);
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
}
"@

$laptop = [System.Windows.Forms.Screen]::PrimaryScreen
$b = $laptop.Bounds

$r = New-Object CursorLock+RECT
$r.Left   = $b.Left
$r.Top    = $b.Top
$r.Right  = $b.Right
$r.Bottom = $b.Bottom

Write-Host ""
Write-Host "  +---------------------------------------+" -ForegroundColor Cyan
Write-Host "  |  CURSOR LOCKED to laptop screen       |" -ForegroundColor Cyan
Write-Host "  |  Laptop: $($b.Width)x$($b.Height) @ ($($b.Left),$($b.Top))        |" -ForegroundColor Cyan
Write-Host "  |  CLOSE THIS WINDOW to unlock          |" -ForegroundColor Cyan
Write-Host "  +---------------------------------------+" -ForegroundColor Cyan
Write-Host ""

# Re-apply every 200ms - prevents apps/Windows from releasing the lock on focus change
try {
    while ($true) {
        [CursorLock]::ClipCursor([ref]$r) | Out-Null
        Start-Sleep -Milliseconds 200
    }
} finally {
    [CursorLock]::ClipCursor([IntPtr]::Zero) | Out-Null
    Write-Host "  Cursor unlocked." -ForegroundColor Magenta
}
