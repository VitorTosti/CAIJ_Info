Option Explicit

Dim shell, fso, baseDir, coreDir, updaterPath, scriptPath, command, updateCommand
Dim serverConfigPath, versionPath
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

baseDir = fso.GetParentFolderName(WScript.ScriptFullName)
coreDir = fso.BuildPath(baseDir, "CoreCAIJ")
updaterPath = fso.BuildPath(coreDir, "AtualizarCAIJ.ps1")
scriptPath = fso.BuildPath(coreDir, "InfoNotebook.ps1")
serverConfigPath = fso.BuildPath(coreDir, "caij_servidor_url.txt")
versionPath = fso.BuildPath(coreDir, "caij_versao_app.txt")

Function ReadSmallText(path)
    Dim fileHandle
    ReadSmallText = ""
    On Error Resume Next
    If fso.FileExists(path) Then
        Set fileHandle = fso.OpenTextFile(path, 1, False)
        ReadSmallText = Trim(fileHandle.ReadAll)
        fileHandle.Close
    End If
    On Error GoTo 0
End Function

Function NeedsUpdate()
    Dim localVersion, baseUrl, http, expression, matches, remoteVersion
    NeedsUpdate = False

    localVersion = ReadSmallText(versionPath)
    If localVersion = "" Then
        NeedsUpdate = True
        Exit Function
    End If

    baseUrl = ReadSmallText(serverConfigPath)
    If baseUrl = "" Then Exit Function
    Do While Right(baseUrl, 1) = "/"
        baseUrl = Left(baseUrl, Len(baseUrl) - 1)
    Loop

    On Error Resume Next
    Set http = CreateObject("MSXML2.ServerXMLHTTP.6.0")
    http.setTimeouts 300, 300, 700, 700
    http.Open "GET", baseUrl & "/atualizacao/manifesto", False
    http.Send
    If Err.Number <> 0 Or http.Status <> 200 Then
        Err.Clear
        On Error GoTo 0
        Exit Function
    End If

    Set expression = CreateObject("VBScript.RegExp")
    expression.Pattern = """version""\s*:\s*""([^""]+)"""
    expression.IgnoreCase = True
    Set matches = expression.Execute(http.ResponseText)
    If matches.Count > 0 Then
        remoteVersion = Trim(matches(0).SubMatches(0))
        NeedsUpdate = (remoteVersion <> "" And remoteVersion <> localVersion)
    End If
    On Error GoTo 0
End Function

If fso.FileExists(updaterPath) And NeedsUpdate() Then
    updateCommand = "powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Chr(34) & updaterPath & Chr(34) & " -NoLaunch -Quiet"
    shell.Run updateCommand, 0, True
End If

command = "powershell.exe -NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Chr(34) & scriptPath & Chr(34)

shell.Run command, 0, False
