param(
    [string]$AppRoot = '',
    [string]$OutputDirectory = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'CAIJ-Atualizacoes'),
    [string]$Version = (Get-Date -Format 'yyyy.MM.dd.HHmmss')
)

$ErrorActionPreference = 'Stop'
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $AppRoot) { $AppRoot = Split-Path -Parent $scriptDirectory }
$rootFiles = @(
    'InfoNotebook.bat',
    'InfoNotebook.vbs',
    'TestarNotebook.bat',
    'TestarNotebook.vbs',
    'InfoNotebookMac.command',
    '.hidden'
)
$coreFiles = @(
    'CoreCAIJ/InfoNotebook.ps1',
    'CoreCAIJ/InfoNotebookMac.ps1',
    'CoreCAIJ/TestarNotebook.ps1',
    'CoreCAIJ/GradeRules.ps1',
    'CoreCAIJ/PrepararLenovo.ps1',
    'CoreCAIJ/DiagnosticoConexaoCAIJ.ps1',
    'CoreCAIJ/AtualizarCAIJ.ps1',
    'CoreCAIJ/AtualizarCAIJ.command'
)
$coreDirectories = @('CoreCAIJ/mac-ui', 'CoreCAIJ/assets', 'CoreCAIJ/tools')
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("caij-publish-" + [guid]::NewGuid().ToString('N'))
$stagePath = Join-Path $tempRoot 'stage'
New-Item -ItemType Directory -Path $stagePath, $OutputDirectory -Force | Out-Null

try {
    $relativeFiles = New-Object System.Collections.Generic.List[string]
    foreach ($relative in @($rootFiles + $coreFiles)) {
        $source = Join-Path $AppRoot ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Arquivo obrigatorio nao encontrado: $relative" }
        $destination = Join-Path $stagePath ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination -Force
        $relativeFiles.Add($relative)
    }

    foreach ($relativeDirectory in $coreDirectories) {
        $sourceDirectory = Join-Path $AppRoot ($relativeDirectory.Replace('/', [IO.Path]::DirectorySeparatorChar))
        if (-not (Test-Path -LiteralPath $sourceDirectory -PathType Container)) { continue }
        foreach ($file in Get-ChildItem -LiteralPath $sourceDirectory -File -Recurse | Where-Object { $_.Name -notlike '*.pyc' -and $_.FullName -notmatch '[\\/]__pycache__[\\/]' }) {
            $relative = $file.FullName.Substring($AppRoot.TrimEnd('\').Length).TrimStart('\').Replace('\', '/')
            $destination = Join-Path $stagePath ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))
            New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
            Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
            $relativeFiles.Add($relative)
        }
    }

    # O patch oficial Lenovo e validado e armazenado no servidor de atualizacoes.
    # Assim todos os pendrives recebem a mesma copia integra, mesmo que a copia
    # antiga na raiz do pendrive esteja ausente ou corrompida.
    $lenovoExpectedHash = '6C4165F5BF6F93D211F43BFB061354278120F52862B2282443BF182A9F1236A2'
    $lenovoDownloadUrl = 'https://download.lenovo.com/consumer/mobiles/portcoderev2.exe'
    $lenovoCachePath = Join-Path $OutputDirectory 'vendor\portcoderev2.exe'
    $lenovoCacheValid = $false
    if (Test-Path -LiteralPath $lenovoCachePath -PathType Leaf) {
        $lenovoCacheValid = ((Get-FileHash -LiteralPath $lenovoCachePath -Algorithm SHA256).Hash -eq $lenovoExpectedHash)
    }
    if (-not $lenovoCacheValid) {
        $lenovoDownloadPath = Join-Path $tempRoot 'portcoderev2.exe.download'
        Invoke-WebRequest -Uri $lenovoDownloadUrl -OutFile $lenovoDownloadPath -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
        $downloadHash = (Get-FileHash -LiteralPath $lenovoDownloadPath -Algorithm SHA256).Hash
        $downloadSignature = Get-AuthenticodeSignature -LiteralPath $lenovoDownloadPath
        $downloadSigner = if ($downloadSignature.SignerCertificate) { [string]$downloadSignature.SignerCertificate.Subject } else { '' }
        if ($downloadHash -ne $lenovoExpectedHash -or $downloadSignature.Status -ne 'Valid' -or $downloadSigner -notmatch '(?i)(CN|O)=Lenovo') {
            throw 'O download do patch Lenovo falhou na validacao de integridade ou assinatura.'
        }
        New-Item -ItemType Directory -Path (Split-Path -Parent $lenovoCachePath) -Force | Out-Null
        Copy-Item -LiteralPath $lenovoDownloadPath -Destination $lenovoCachePath -Force
    }
    $lenovoRelative = 'CoreCAIJ/tools/lenovo/portcoderev2.exe'
    $lenovoStagePath = Join-Path $stagePath ($lenovoRelative.Replace('/', [IO.Path]::DirectorySeparatorChar))
    New-Item -ItemType Directory -Path (Split-Path -Parent $lenovoStagePath) -Force | Out-Null
    Copy-Item -LiteralPath $lenovoCachePath -Destination $lenovoStagePath -Force
    if (-not $relativeFiles.Contains($lenovoRelative)) { $relativeFiles.Add($lenovoRelative) }

    $fileList = (($relativeFiles | Sort-Object -Unique) -join "`n") + "`n"
    [IO.File]::WriteAllText((Join-Path $stagePath '_caij_update_files.txt'), $fileList, (New-Object Text.UTF8Encoding($false)))

    # Compress-Archive ignora arquivos com o atributo Hidden. Os launchers do
    # Windows sao ocultos no pendrive, entao remova o atributo apenas da copia
    # temporaria usada para montar o pacote.
    foreach ($stagedItem in Get-ChildItem -LiteralPath $stagePath -Force -Recurse) {
        if (($stagedItem.Attributes -band [IO.FileAttributes]::Hidden) -ne 0) {
            $stagedItem.Attributes = $stagedItem.Attributes -band (-bnot [IO.FileAttributes]::Hidden)
        }
    }

    $safeVersion = $Version -replace '[^0-9A-Za-z._-]', '-'
    $packageName = "caij-app-$safeVersion.zip"
    $packagePath = Join-Path $OutputDirectory $packageName
    if (Test-Path -LiteralPath $packagePath) { Remove-Item -LiteralPath $packagePath -Force }
    Compress-Archive -Path (Join-Path $stagePath '*') -DestinationPath $packagePath -CompressionLevel Optimal
    $hash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $manifest = [ordered]@{
        status = 'ok'
        version = $Version
        sha256 = $hash
        size = (Get-Item -LiteralPath $packagePath).Length
        packageUrl = '/atualizacao/pacote'
        packageName = $packageName
        files = @($relativeFiles | Sort-Object -Unique)
        publishedAt = (Get-Date).ToString('o')
    }
    $manifestJson = $manifest | ConvertTo-Json -Depth 4 -Compress
    [IO.File]::WriteAllText((Join-Path $OutputDirectory 'manifesto.json'), $manifestJson, (New-Object Text.UTF8Encoding($false)))

    Write-Host "[OK] Atualizacao $Version publicada."
    Write-Host "     Pasta: $OutputDirectory"
    Write-Host "     Pacote: $packageName"
    Write-Host "     Arquivos: $($relativeFiles.Count)"
} finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
