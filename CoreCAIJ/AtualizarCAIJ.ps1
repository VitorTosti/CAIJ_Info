param(
    [string]$AppRoot = '',
    [string]$ServerBaseUrl = '',
    [switch]$NoLaunch,
    [switch]$Force,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $AppRoot) { $AppRoot = Split-Path -Parent $scriptDirectory }
$coreRoot = Join-Path $AppRoot 'CoreCAIJ'
$versionPath = Join-Path $coreRoot 'caij_versao_app.txt'
$serverConfigPath = Join-Path $coreRoot 'caij_servidor_url.txt'
$appScriptPath = Join-Path $coreRoot 'InfoNotebook.ps1'
$protectedPattern = '(^|/)(caij_historico_notebooks\.json|caij_os_counter\.txt|caij_os_por_serial\.json|caij_servidor_url\.txt|caij_modelos_manuais\.json|caij_ultimo_modelo_manual\.json)$'

function Write-UpdateMessage {
    param([string]$Message)
    if (-not $Quiet) { Write-Host "[CAIJ] $Message" }
}

function Get-ServerBaseUrl {
    if ($ServerBaseUrl) { return $ServerBaseUrl.Trim().TrimEnd('/') }
    if (Test-Path -LiteralPath $serverConfigPath) {
        $configured = ([string](Get-Content -LiteralPath $serverConfigPath -Raw -ErrorAction SilentlyContinue)).Trim().TrimEnd('/')
        if ($configured -match '^https?://') { return $configured }
    }
    return ''
}

function Resolve-UpdateUrl {
    param([string]$BaseUrl, [string]$PackageUrl)
    if ($PackageUrl -match '^https?://') { return $PackageUrl }
    if (-not $PackageUrl.StartsWith('/')) { $PackageUrl = '/' + $PackageUrl }
    return $BaseUrl.TrimEnd('/') + $PackageUrl
}

function Test-SafeRelativePath {
    param([string]$RelativePath)
    $normalized = ([string]$RelativePath).Replace('\', '/').TrimStart('/')
    if (-not $normalized -or $normalized -match '(^|/)\.\.(/|$)' -or [IO.Path]::IsPathRooted($RelativePath)) { return $false }
    if ($normalized -match $protectedPattern) { return $false }
    return $true
}

function Set-CaijLauncherVisibility {
    foreach ($relative in @(
        '.git', 'CoreCAIJ', '.gitattributes', '.gitignore', '.hidden',
        'InfoNotebook.bat', 'InfoNotebook.vbs', 'TestarNotebook.bat', 'TestarNotebook.vbs'
    )) {
        $path = Join-Path $AppRoot $relative
        if (Test-Path -LiteralPath $path) {
            try {
                $item = Get-Item -LiteralPath $path -Force
                $item.Attributes = $item.Attributes -bor [IO.FileAttributes]::Hidden
            } catch {}
        }
    }
    foreach ($relative in @('InfoNotebook.lnk', 'InfoNotebookMac.command')) {
        $path = Join-Path $AppRoot $relative
        if (Test-Path -LiteralPath $path) {
            try {
                $item = Get-Item -LiteralPath $path -Force
                $item.Attributes = $item.Attributes -band (-bnot [IO.FileAttributes]::Hidden)
            } catch {}
        }
    }
}

function New-CaijWindowsShortcut {
    try {
        $vbsPath = Join-Path $AppRoot 'InfoNotebook.vbs'
        if (-not (Test-Path -LiteralPath $vbsPath -PathType Leaf)) { return }
        $shortcutPath = Join-Path $AppRoot 'InfoNotebook.lnk'
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
        $shortcut.Arguments = '//B //Nologo "' + $vbsPath + '"'
        $shortcut.WorkingDirectory = $AppRoot
        $shortcut.IconLocation = (Join-Path $env:WINDIR 'System32\imageres.dll') + ',11'
        $shortcut.Save()
    } catch {
        Write-UpdateMessage 'Nao foi possivel criar o atalho visual do InfoNotebook.'
    }
}

function Invoke-CaijUpdate {
    $baseUrl = Get-ServerBaseUrl
    if (-not $baseUrl) {
        Write-UpdateMessage 'Servidor nao configurado; iniciando a versao local.'
        return $false
    }

    try {
        $manifest = Invoke-RestMethod -Uri "$baseUrl/atualizacao/manifesto" -Method Get -TimeoutSec 2 -ErrorAction Stop
    } catch {
        Write-UpdateMessage 'Servidor de atualizacoes indisponivel; iniciando a versao local.'
        return $false
    }

    $remoteVersion = ([string]$manifest.version).Trim()
    $localVersion = if (Test-Path -LiteralPath $versionPath) {
        ([string](Get-Content -LiteralPath $versionPath -Raw -ErrorAction SilentlyContinue)).Trim()
    } else { '' }
    if (-not $remoteVersion) { throw 'Manifesto de atualizacao sem versao.' }
    if (-not $Force -and $localVersion -eq $remoteVersion) {
        Write-UpdateMessage "Versao $localVersion ja esta atualizada."
        return $false
    }

    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("caij-update-" + [guid]::NewGuid().ToString('N'))
    $zipPath = Join-Path $tempRoot 'caij-app.zip'
    $stagePath = Join-Path $tempRoot 'stage'
    $backupPath = Join-Path $tempRoot 'backup'
    New-Item -ItemType Directory -Path $stagePath, $backupPath -Force | Out-Null
    $changed = New-Object System.Collections.Generic.List[string]
    $created = New-Object System.Collections.Generic.List[string]

    try {
        Write-UpdateMessage "Baixando a versao $remoteVersion..."
        $packageUrl = Resolve-UpdateUrl -BaseUrl $baseUrl -PackageUrl ([string]$manifest.packageUrl)
        Invoke-WebRequest -Uri $packageUrl -OutFile $zipPath -TimeoutSec 60 -UseBasicParsing -ErrorAction Stop
        $actualHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $expectedHash = ([string]$manifest.sha256).Trim().ToLowerInvariant()
        if (-not $expectedHash -or $actualHash -ne $expectedHash) { throw 'O pacote baixado falhou na verificacao de integridade.' }

        Expand-Archive -LiteralPath $zipPath -DestinationPath $stagePath -Force
        $files = @($manifest.files)
        if ($files.Count -eq 0) {
            $fileListPath = Join-Path $stagePath '_caij_update_files.txt'
            if (-not (Test-Path -LiteralPath $fileListPath)) { throw 'Pacote sem lista de arquivos.' }
            $files = @(Get-Content -LiteralPath $fileListPath | Where-Object { $_.Trim() })
        }

        foreach ($relativeRaw in $files) {
            $relative = ([string]$relativeRaw).Replace('/', [IO.Path]::DirectorySeparatorChar)
            if (-not (Test-SafeRelativePath -RelativePath $relative)) { throw "Caminho inseguro ou protegido no pacote: $relativeRaw" }
            $source = Join-Path $stagePath $relative
            $target = Join-Path $AppRoot $relative
            if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Arquivo ausente no pacote: $relativeRaw" }

            if (Test-Path -LiteralPath $target -PathType Leaf) {
                $backupTarget = Join-Path $backupPath $relative
                New-Item -ItemType Directory -Path (Split-Path -Parent $backupTarget) -Force | Out-Null
                Copy-Item -LiteralPath $target -Destination $backupTarget -Force
                $changed.Add($relative)
            } else {
                $created.Add($relative)
            }
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            Copy-Item -LiteralPath $source -Destination $target -Force
        }

        [IO.File]::WriteAllText($versionPath, $remoteVersion, (New-Object Text.UTF8Encoding($false)))
        Write-UpdateMessage "Atualizacao $remoteVersion instalada."
        return $true
    } catch {
        foreach ($relative in $changed) {
            $backupFile = Join-Path $backupPath $relative
            $targetFile = Join-Path $AppRoot $relative
            if (Test-Path -LiteralPath $backupFile) { Copy-Item -LiteralPath $backupFile -Destination $targetFile -Force -ErrorAction SilentlyContinue }
        }
        foreach ($relative in $created) {
            $targetFile = Join-Path $AppRoot $relative
            if (Test-Path -LiteralPath $targetFile -PathType Leaf) { Remove-Item -LiteralPath $targetFile -Force -ErrorAction SilentlyContinue }
        }
        Write-UpdateMessage "Atualizacao nao aplicada: $($_.Exception.Message)"
        return $false
    } finally {
        if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

[void](Invoke-CaijUpdate)
New-CaijWindowsShortcut
Set-CaijLauncherVisibility

if (-not $NoLaunch) {
    if (-not (Test-Path -LiteralPath $appScriptPath)) { throw "InfoNotebook nao encontrado em $appScriptPath" }
    $quotedScript = '"' + $appScriptPath.Replace('"', '""') + '"'
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File $quotedScript"
}
