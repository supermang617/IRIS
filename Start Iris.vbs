Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

repoRoot = fso.GetParentFolderName(WScript.ScriptFullName)
launcher = fso.BuildPath(repoRoot, "Start Iris.ps1")

shell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File " & Quote(launcher), 0, False

Function Quote(value)
    Quote = Chr(34) & Replace(value, Chr(34), Chr(34) & Chr(34)) & Chr(34)
End Function
