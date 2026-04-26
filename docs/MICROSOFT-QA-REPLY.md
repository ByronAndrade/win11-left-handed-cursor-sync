I ran into the same problem as a left-handed mouse user on Windows 11: switching the primary mouse button to `Right` does not make the standard arrow cursor point to the right.

I put together a small PowerShell-based solution that keeps the directional Windows cursors in sync with the mouse setting:

- if `Primary mouse button = Right`, it applies mirrored right-facing Arrow, Hand, Help, and AppStarting cursors;
- if `Primary mouse button = Left`, it restores the normal default cursors;
- it installs per-user, does not replace system files, and survives reboot.

Public repo:

`<repo-url>`

Easiest install path:

1. Download ZIP
2. Extract it
3. Double-click `install.cmd`

Manual install command:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install-mouse-cursor-sync.ps1
```

It works by watching:

- `HKCU\Control Panel\Mouse\SwapMouseButtons`
- `HKCU\Control Panel\Cursors\Arrow`
- `HKCU\Control Panel\Cursors\Hand`
- `HKCU\Control Panel\Cursors\Help`
- `HKCU\Control Panel\Cursors\AppStarting`

and switching both cursors automatically.

If this helps anyone else, feel free to use it or adapt it.
