# Troubleshooting Guide

Common problems and how to fix them; no technical knowledge needed.

---

## "TV not found. Plug in HDMI cable, turn TV on, then try again."

**What's happening:** Windows can't see your TV.

**Fix:**
1. Make sure the HDMI cable is firmly plugged into both the laptop and the TV
2. Turn the TV on and switch it to the correct HDMI input (usually labeled HDMI 1, HDMI 2, etc.)
3. Wait 5 seconds and run `StartTV.bat` again

---

## "RDP Wrapper not installed. Run 02-Setup.bat first."

**What's happening:** Step 2 of setup wasn't completed.

**Fix:**
1. Run `02-Setup.bat` as described in the README
2. If it fails, see the "02-Setup.bat fails to install RDP Wrapper" section below

---

## "Setup not complete. Run 01-CreateTVUser.bat first, then 02-Setup.bat."

**What's happening:** The `tv-config.local.ps1` file is missing. This file is created by `01-CreateTVUser.bat`.

**Fix:**
1. Run `01-CreateTVUser.bat` and follow the prompts
2. Then run `02-Setup.bat`
3. Then try `StartTV.bat` again

---

## TV session says "This PC can't connect to the remote computer"

**Most common causes:**

**A) Remote Desktop is not enabled**
- Open **Settings → System → Remote Desktop** and turn it ON
- Then run `02-Setup.bat` again to ensure the firewall rule is set

**B) Wrong password in config**
- Delete `tv-config.local.ps1` from the TV Workspace folder
- Run `01-CreateTVUser.bat` again and re-enter the correct password

**C) RDP Wrapper isn't working for your Windows build**
- Open `C:\Program Files\RDP Wrapper\` and run `RDPConf.exe`
- Look at the status next to "Wrapper state"; it should say "Fully supported"
- If it says "Not supported", run `02-Setup.bat` again or wait 24 hours for the community patch

---

## TV session shows black screen or immediately disconnects

**Fix:**
1. Make sure the TV user account (`TVUser`) has a password set
   - Open **Settings → Accounts → Family & other users**
   - Click `TVUser` → **Change account type** → make sure it's a standard user with a password
2. Run `01-CreateTVUser.bat` again to reset and re-save the password
3. Try `StartTV.bat` again

---

## 02-Setup.bat fails to install RDP Wrapper

**Manual install steps:**
1. Open your browser and go to: https://github.com/stascorp/rdpwrap/releases/latest
2. Download the `.zip` file (e.g., `RDPWrap-v1.6.2.zip`)
3. Right-click the zip → **Extract All**
4. Inside the extracted folder, right-click `RDPWInst.exe` → **Run as administrator**
5. Click Yes when Windows asks for permission
6. Run `02-Setup.bat` again; it will verify the installation and download the INI

---

## "Build XXXXX not patched by community yet"

**What's happening:** You recently installed a Windows Update, and the RDP Wrapper community hasn't released an update for your exact Windows build yet.

**Fix:** Wait 12–48 hours and run `StartTV.bat` again. The script automatically checks for the patch; you don't need to do anything else.

---

## Mouse cursor escaped to the TV screen

**Fix:**
- Run `LockCursor.bat`; it instantly locks the mouse back to the laptop
- Keep the `LockCursor` window open as long as you want the lock active
- Close that window to freely move the mouse between screens again

---

## LockCursor stops working (mouse escapes while locked)

**What's happening:** Some apps (games, video players, certain system tools) can override the cursor lock.

**Fix:**
1. Close the LockCursor window
2. Run `LockCursor.bat` again
3. If a specific app keeps releasing it, run `WhoReleasesClip.ps1` to identify which one

---

## After a Windows Update, everything stopped working

**Fix, in order:**
1. Restart your PC first (if not already done after the update)
2. Run `StartTV.bat`; it auto-patches RDP Wrapper
3. If it says "not patched yet", wait 24 hours and try again
4. If you wait 48+ hours and it still doesn't work, run `02-Setup.bat` to force a fresh INI download

---

## "Access is denied" when running any .bat file

**What's happening:** The script needs administrator privileges.

**Fix:**
- Right-click the `.bat` file → **Run as administrator**
- The scripts ask for this automatically, but sometimes Windows blocks the auto-elevation

---

## Still stuck?

Open an issue on GitHub and describe:
1. Which file you ran
2. What the error message says (take a photo of the screen if needed)
3. Your Windows version (press **Win + R**, type `winver`, press Enter)
