I ran into the same problem as a left-handed mouse user on Windows 11: switching the primary mouse button to `Right` does not make the standard arrow cursor point to the right.

I put together a small PowerShell-based solution that keeps the main cursor in sync with the Windows setting:

- if `Primary mouse button = Right`, it applies a mirrored right-pointing cursor;
- if `Primary mouse button = Left`, it restores the normal default cursor;
- it installs per-user, does not replace system files, and survives reboot.

Public repo:

`<repo-url>`

Main install command:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install-mouse-cursor-sync.ps1
```

It works by watching:

- `HKCU\Control Panel\Mouse\SwapMouseButtons`
- `HKCU\Control Panel\Cursors\Arrow`

and switching only the main arrow cursor automatically.

If this helps anyone else, feel free to use it or adapt it.
