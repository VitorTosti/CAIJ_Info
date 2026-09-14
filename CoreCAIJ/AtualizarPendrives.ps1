[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$SourceRoot = '',
    [string[]]$DriveRoots = @()
)

$ErrorActionPreference = 'Stop'
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $SourceRoot) { $SourceRoot = Split-Path -Parent $scriptDirectory }
$bootstrapFiles = @(
    'InfoNotebook.bat',
    'InfoNotebook.vbs',
    'InfoNotebookMac.command',
    '.hidden',
    'CoreCAIJ/AtualizarCAIJ.ps1',
    'CoreCAIJ/AtualizarCAIJ.command',
    'CoreCAIJ/PrepararLenovo.ps1',
    'CoreCAIJ/caij_servidor_url.txt'
)

function Update-CaijPendriveNow {
    param([string]$AppRoot)

    $updaterPath = Join-Path $AppRoot 'CoreCAIJ\AtualizarCAIJ.ps1'
    $serverConfigPath = Join-Path $AppRoot 'CoreCAIJ\caij_servidor_url.txt'
    if (-not (Test-Path -LiteralPath $updaterPath -PathType Leaf)) {
        throw "Atualizador nao encontrado depois da instalacao: $updaterPath"
    }
    if (-not (Test-Path -LiteralPath $serverConfigPath -PathType Leaf)) {
        throw "Endereco do servidor nao foi gravado no pendrive: $serverConfigPath"
    }

    $baseUrl = ([string](Get-Content -LiteralPath $serverConfigPath -Raw)).Trim().TrimEnd('/')
    if ($baseUrl -notmatch '^https?://') {
        throw "Endereco do servidor invalido no pendrive: $baseUrl"
    }

    try {
        $manifest = Invoke-RestMethod -Uri "$baseUrl/atualizacao/manifesto" -Method Get -TimeoutSec 5 -ErrorAction Stop
    } catch {
        throw "Pendrive preparado, mas o servidor $baseUrl nao respondeu: $($_.Exception.Message)"
    }
    $versaoRemota = ([string]$manifest.version).Trim()
    if (-not $versaoRemota) { throw 'Servidor retornou manifesto sem versao.' }

    # Reutilize exatamente o endpoint que acabou de responder acima. Fazer uma
    # segunda descoberta podia falhar por DNS/transiente mesmo com o servidor ativo.
    & powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $updaterPath -AppRoot $AppRoot -ServerBaseUrl $baseUrl -NoLaunch
    if ($LASTEXITCODE -ne 0) { throw "Atualizador do pendrive terminou com codigo $LASTEXITCODE." }

    $versionPath = Join-Path $AppRoot 'CoreCAIJ\caij_versao_app.txt'
    $versaoLocal = if (Test-Path -LiteralPath $versionPath -PathType Leaf) {
        ([string](Get-Content -LiteralPath $versionPath -Raw)).Trim()
    } else { '' }
    if ($versaoLocal -ne $versaoRemota) {
        throw "Pendrive ainda esta na versao '$versaoLocal'; servidor oferece '$versaoRemota'."
    }
    Write-Host "[OK] Versao $versaoLocal instalada agora em $AppRoot"
}

function Set-CaijLauncherVisibility {
    param([string]$AppRoot)
    foreach ($relative in @(
        '.git', 'CoreCAIJ', '.gitattributes', '.gitignore', '.hidden',
        'InfoNotebook.bat', 'InfoNotebook.vbs', 'TestarNotebook.bat', 'TestarNotebook.vbs'
    )) {
        $path = Join-Path $AppRoot $relative
        if (Test-Path -LiteralPath $path) {
            $item = Get-Item -LiteralPath $path -Force
            $item.Attributes = $item.Attributes -bor [IO.FileAttributes]::Hidden
        }
    }
    foreach ($relative in @('InfoNotebook.lnk', 'InfoNotebookMac.command')) {
        $path = Join-Path $AppRoot $relative
        if (Test-Path -LiteralPath $path) {
            $item = Get-Item -LiteralPath $path -Force
            $item.Attributes = $item.Attributes -band (-bnot [IO.FileAttributes]::Hidden)
        }
    }
}

function New-CaijWindowsShortcut {
    param([string]$AppRoot)
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
}

if ($DriveRoots.Count -eq 0) {
    $DriveRoots = @(
        Get-CimInstance Win32_LogicalDisk -Filter 'DriveType = 2' |
            Where-Object { $_.DeviceID } |
            ForEach-Object { $_.DeviceID + '\' }
    )
}

if ($DriveRoots.Count -eq 0) {
    Write-Host '[AVISO] Nenhum pendrive foi encontrado.'
    exit 2
}

$updated = 0
foreach ($driveRootRaw in $DriveRoots) {
    $driveRoot = [IO.Path]::GetFullPath($driveRootRaw)
    $candidateRoots = @($driveRoot)
    $candidateRoots += @(
        Get-ChildItem -LiteralPath $driveRoot -Directory -Force -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName
    )
    $appRoots = @(
        foreach ($candidateRoot in $candidateRoots) {
            $coreTarget = Join-Path $candidateRoot 'CoreCAIJ'
            $looksLikeCaij = (Test-Path -LiteralPath $coreTarget -PathType Container) -and (
                (Test-Path -LiteralPath (Join-Path $candidateRoot 'InfoNotebook.bat') -PathType Leaf) -or
                (Test-Path -LiteralPath (Join-Path $candidateRoot 'InfoNotebookMac.command') -PathType Leaf)
            )
            if ($looksLikeCaij) { $candidateRoot }
        }
    )
    if ($appRoots.Count -eq 0) {
        Write-Host "[IGNORADO] $driveRoot nao parece ser um pendrive do InfoNotebook."
        continue
    }

    foreach ($appRoot in $appRoots) {
        foreach ($relative in $bootstrapFiles) {
            $nativeRelative = $relative.Replace('/', [IO.Path]::DirectorySeparatorChar)
            $source = Join-Path $SourceRoot $nativeRelative
            $target = Join-Path $appRoot $nativeRelative
            if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Arquivo inicializador ausente: $source" }
            if ($PSCmdlet.ShouldProcess($target, 'Instalar inicializador com atualizacao automatica')) {
                New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
                Copy-Item -LiteralPath $source -Destination $target -Force
            }
        }
        New-CaijWindowsShortcut -AppRoot $appRoot
        Set-CaijLauncherVisibility -AppRoot $appRoot
        Write-Host "[OK] Inicializador instalado em $appRoot"
        Update-CaijPendriveNow -AppRoot $appRoot
        $updated++
    }
}

if ($updated -eq 0) { exit 3 }
Write-Host "[OK] $updated instalacao(oes) preparada(s) para atualizacao automatica."
