param([switch]$WhatIf)

$ErrorActionPreference = 'Stop'
function Get-CaijFileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    $stream = [IO.File]::OpenRead([IO.Path]::GetFullPath($Path))
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return (($sha.ComputeHash($stream) | ForEach-Object { $_.ToString('x2') }) -join '')
    } finally {
        $sha.Dispose()
        $stream.Dispose()
    }
}
$sourcePath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'ServidorImpressao.ps1'))
$watchdogSourcePath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'ServidorImpressaoWatchdog.ps1'))
$desktopPath = [IO.Path]::GetFullPath([Environment]::GetFolderPath('Desktop'))
$targetPath = [IO.Path]::GetFullPath((Join-Path $desktopPath 'ServidorImpressao.ps1'))
$watchdogTargetPath = [IO.Path]::GetFullPath((Join-Path $desktopPath 'ServidorImpressaoWatchdog.ps1'))
$startupPath = [Environment]::GetFolderPath('Startup')
$startupShortcutPath = Join-Path $startupPath 'CAIJ Servidor Impressao.lnk'
$urlPrefix = 'http://+:9100/'

if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    throw "Servidor de origem nao encontrado: $sourcePath"
}
if (-not (Test-Path -LiteralPath $watchdogSourcePath -PathType Leaf)) {
    throw "Monitor de origem nao encontrado: $watchdogSourcePath"
}
if ((Split-Path -Parent $targetPath) -ne $desktopPath -or (Split-Path -Leaf $targetPath) -ne 'ServidorImpressao.ps1') {
    throw "Destino inesperado para o servidor: $targetPath"
}

$sourceHash = Get-CaijFileSha256 -Path $sourcePath
$watchdogSourceHash = Get-CaijFileSha256 -Path $watchdogSourcePath
$targetHash = if (Test-Path -LiteralPath $targetPath -PathType Leaf) {
    Get-CaijFileSha256 -Path $targetPath
} else { '' }
$watchdogTargetHash = if (Test-Path -LiteralPath $watchdogTargetPath -PathType Leaf) {
    Get-CaijFileSha256 -Path $watchdogTargetPath
} else { '' }

if ($sourceHash -eq $targetHash -and $watchdogSourceHash -eq $watchdogTargetHash -and (Test-Path -LiteralPath $startupShortcutPath -PathType Leaf)) {
    if (Test-Path -LiteralPath $startupShortcutPath -PathType Leaf) {
        try {
            $statusAtual = Invoke-RestMethod -Uri 'http://127.0.0.1:9100/status' -Method Get -TimeoutSec 2 -ErrorAction Stop
            if ($statusAtual.status -eq 'ok') {
                Write-Host '[OK] O servidor local ja esta atualizado e supervisionado.'
                exit 0
            }
        } catch {}
    }
}

if ($WhatIf) {
    Write-Host "[OK] Atualizacao do servidor validada: $sourcePath -> $targetPath"
    exit 0
}

# Reserva a URL uma unica vez para o usuario atual. O Windows solicita UAC
# somente nesta preparacao; depois o watchdog reinicia o servidor sem elevacao.
$urlAclOutput = (& netsh http show urlacl url=$urlPrefix 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0 -or $urlAclOutput -notmatch [regex]::Escape($urlPrefix)) {
    $currentAccount = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $netshArgs = 'http add urlacl url={0} user="{1}" listen=yes delegate=no' -f $urlPrefix, $currentAccount
    $urlAclProcess = Start-Process -FilePath (Join-Path $env:WINDIR 'System32\netsh.exe') -Verb RunAs -ArgumentList $netshArgs -Wait -PassThru
    if (-not $urlAclProcess -or $urlAclProcess.ExitCode -ne 0) {
        throw 'Nao foi possivel autorizar a porta 9100 para o supervisor.'
    }
}

$backupPath = $null
if ($sourceHash -ne $targetHash -and (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
    $backupPath = Join-Path $desktopPath ('ServidorImpressao.backup-{0}.ps1' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Copy-Item -LiteralPath $targetPath -Destination $backupPath -Force
}
if ($sourceHash -ne $targetHash) {
    Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force
}
if ($watchdogSourceHash -ne $watchdogTargetHash) {
    Copy-Item -LiteralPath $watchdogSourcePath -Destination $watchdogTargetPath -Force
}

$shell = New-Object -ComObject WScript.Shell
$startupShortcut = $shell.CreateShortcut($startupShortcutPath)
$startupShortcut.TargetPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$startupShortcut.Arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $watchdogTargetPath + '"'
$startupShortcut.WorkingDirectory = $desktopPath
$startupShortcut.WindowStyle = 7
$startupShortcut.Save()

$targetPattern = [regex]::Escape($targetPath)
$servidoresAtivos = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match '^(powershell|pwsh)\.exe$' -and
    ([string]$_.CommandLine) -match $targetPattern
})
foreach ($processo in $servidoresAtivos) {
    Stop-Process -Id ([int]$processo.ProcessId) -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Milliseconds 700

$argumentosWatchdog = '-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $watchdogTargetPath
Start-Process -FilePath 'powershell.exe' -ArgumentList $argumentosWatchdog -WindowStyle Hidden | Out-Null

$servidorOk = $false
foreach ($tentativa in 1..20) {
    try {
        $status = Invoke-RestMethod -Uri 'http://127.0.0.1:9100/status' -Method Get -TimeoutSec 2 -ErrorAction Stop
        if ($status.status -eq 'ok') { $servidorOk = $true; break }
    } catch {}
    Start-Sleep -Milliseconds 500
}
if (-not $servidorOk) {
    throw 'O arquivo foi atualizado, mas o servidor nao respondeu na porta 9100.'
}

Write-Host '[OK] Servidor local atualizado e protegido por recuperacao automatica.'
if ($backupPath) { Write-Host "     Backup: $backupPath" }
