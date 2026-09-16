# OnePlus USB Mirror for Windows

Mirror and control an Android phone from a Windows laptop over USB while keeping the phone's physical display off.

The launcher uses the official [Genymobile scrcpy](https://github.com/Genymobile/scrcpy) package. On a new Windows environment, it installs scrcpy and ADB through WinGet, waits for the phone to be authorized, and starts mirroring with `--turn-screen-off --stay-awake`.

## One-click start

1. Download or clone this repository.
2. Connect the unlocked phone with a USB data cable.
3. Double-click **`Run Phone Mirror.cmd`**.
4. On the first connection, tap **Allow** on the phone's USB debugging prompt.

The first run needs an internet connection so WinGet can install scrcpy. Later runs do not need an internet connection.

## One-time phone setup

On a OnePlus Nord N20 SE:

1. Open **Settings → About device → Version**.
2. Tap **Build number** or **Version number** seven times.
3. Open **Settings → Additional settings → Developer options**.
4. Enable **USB debugging**.
5. Connect the phone, keep it unlocked, and approve the computer when prompted.

The phone may use **Charging only** or **File transfer / Android Auto**. USB debugging authorization is what enables mirroring.

## Controls

| Action | Shortcut |
| --- | --- |
| Turn the phone display off, keep mirroring | `Alt+O` |
| Turn the phone display on | `Alt+Shift+O` |
| Full screen | `Alt+F` or `F11` |
| Android Back | Right-click |
| Android Home | Middle-click |
| Quit | `Alt+Q` or close the window |

## Requirements

- Windows 10 or Windows 11
- Microsoft WinGet (included with current Windows App Installer)
- A USB cable that supports data, not charge-only
- Android USB debugging enabled
- Internet access on the first run

No root access or Android-side app is required.

## Troubleshooting

- **Phone not detected:** unlock it, select a USB data mode, try another USB port, and confirm the cable supports data.
- **Unauthorized:** check the phone for the **Allow USB debugging?** prompt. If it does not appear, disconnect and reconnect the cable.
- **Authorization was rejected:** in Developer options, choose **Revoke USB debugging authorizations**, reconnect, and approve again.
- **Phone display turns on:** focus the mirror window and press `Alt+O`. Pressing the physical power button turns the phone display on.
- **WinGet unavailable:** install or update **App Installer** from the Microsoft Store, then rerun the launcher.

## Security

Only authorize computers you trust. To remove the computer's access, disable **USB debugging** or choose **Revoke USB debugging authorizations** in Developer options.

## Validate without launching

From PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Start-PhoneMirror.ps1 -ValidateOnly
```

## License

This launcher is released under the MIT License. scrcpy is a separate project distributed under its own license.
