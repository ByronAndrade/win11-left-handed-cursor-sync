Option Explicit

Dim shell
Dim fso
Dim installDir
Dim syncScriptPath
Dim lastSwapValue
Dim currentSwapValue

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

installDir = fso.GetParentFolderName(WScript.ScriptFullName)
syncScriptPath = fso.BuildPath(installDir, "mouse-cursor-button-sync.ps1")

If Not fso.FileExists(syncScriptPath) Then
    WScript.Quit 1
End If

Function ReadSwapMouseButtons()
    On Error Resume Next
    ReadSwapMouseButtons = CStr(shell.RegRead("HKCU\Control Panel\Mouse\SwapMouseButtons"))
    If Err.Number <> 0 Then
        Err.Clear
        ReadSwapMouseButtons = ""
    End If
    On Error GoTo 0
End Function

Sub ApplyCursorSync()
    Dim command
    command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & syncScriptPath & """ -RunOnce"
    shell.Run command, 0, True
End Sub

ApplyCursorSync
lastSwapValue = ReadSwapMouseButtons()

Do
    WScript.Sleep 750
    currentSwapValue = ReadSwapMouseButtons()

    If currentSwapValue <> lastSwapValue Then
        ApplyCursorSync
        lastSwapValue = currentSwapValue
    End If
Loop
