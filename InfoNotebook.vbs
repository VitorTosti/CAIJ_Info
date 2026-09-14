Option Explicit

Dim shell, fso, baseDir, coreDir, updaterPath, scriptPath, legacyScriptPath, command, updateCommand
Dim serverConfigPath, versionPath, updateServerFound
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

baseDir = fso.GetParentFolderName(WScript.ScriptFullName)
coreDir = fso.BuildPath(baseDir, "CoreCAIJ")
updaterPath = fso.BuildPath(coreDir, "AtualizarCAIJ.ps1")
scriptPath = fso.BuildPath(coreDir, "InfoNotebookWindowsPreview.ps1")
legacyScriptPath = fso.BuildPath(coreDir, "InfoNotebook.ps1")
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

Sub SaveServerUrl(baseUrl)
    Dim fileHandle
    On Error Resume Next
    Set fileHandle = fso.CreateTextFile(serverConfigPath, True, False)
    fileHandle.Write baseUrl
    fileHandle.Close
    On Error GoTo 0
End Sub

Function ProbeUpdateServer(baseUrl, localVersion)
    Dim http, expression, matches, remoteVersion
    ProbeUpdateServer = False
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
        If remoteVersion <> "" Then
            updateServerFound = True
            SaveServerUrl baseUrl
            ProbeUpdateServer = (remoteVersion <> localVersion)
        End If
    End If
    On Error GoTo 0
End Function

Function NeedsUpdate()
    Dim localVersion, baseUrl, fallbackUrl, fallbackIpUrl
    NeedsUpdate = False
    updateServerFound = False

    localVersion = ReadSmallText(versionPath)
    If localVersion = "" Then
        NeedsUpdate = True
        Exit Function
    End If

    baseUrl = ReadSmallText(serverConfigPath)
    If ProbeUpdateServer(baseUrl, localVersion) Then
        NeedsUpdate = True
        Exit Function
    End If
    If updateServerFound Then Exit Function

    fallbackUrl = "http://INFOCAIJ:9100"
    If LCase(baseUrl) <> LCase(fallbackUrl) Then
        If ProbeUpdateServer(fallbackUrl, localVersion) Then
            NeedsUpdate = True
            Exit Function
        End If
        If updateServerFound Then Exit Function
    End If

    fallbackIpUrl = "http://192.168.15.11:9100"
    If LCase(baseUrl) <> LCase(fallbackIpUrl) Then
        NeedsUpdate = ProbeUpdateServer(fallbackIpUrl, localVersion)
    End If
End Function

If fso.FileExists(updaterPath) And NeedsUpdate() Then
    updateCommand = "powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Chr(34) & updaterPath & Chr(34) & " -NoLaunch -Quiet"
    shell.Run updateCommand, 0, True
End If

If Not fso.FileExists(scriptPath) Then scriptPath = legacyScriptPath
command = "powershell.exe -NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Chr(34) & scriptPath & Chr(34)

shell.Run command, 0, False
