param([string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
function Assert-True([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAIL: $Name" }
}

$updaterText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'AtualizarCAIJ.ps1') -Raw
$macUpdaterText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'AtualizarCAIJ.command') -Raw
$publisherText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'PublicarAtualizacao.ps1') -Raw
$usbInstallerText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'AtualizarPendrives.ps1') -Raw
$serverText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'ServidorImpressao.ps1') -Raw
$vbsText = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'InfoNotebook.vbs') -Raw
$macLauncherText = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'InfoNotebookMac.command') -Raw
$lenovoPreflightText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'PrepararLenovo.ps1') -Raw
$infoNotebookText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'InfoNotebook.ps1') -Raw

Assert-True ($updaterText -match '/atualizacao/manifesto') 'Windows consulta manifesto no servidor CAIJ'
Assert-True ($updaterText -match 'Get-FileHash.+SHA256') 'Windows valida SHA256 do pacote'
Assert-True ($updaterText -match 'caij_historico_notebooks') 'Windows protege historico local'
Assert-True ($updaterText -match 'function\s+Set-CaijLauncherVisibility') 'Windows restaura arquivos tecnicos como ocultos'
Assert-True ($updaterText -match 'function\s+New-CaijWindowsShortcut') 'Windows cria atalho local sem caminho fixo'
Assert-True ($updaterText -match 'manifesto"\s+-Method Get\s+-TimeoutSec 2') 'Windows limita espera do servidor indisponivel'
Assert-True ($macUpdaterText -match 'shasum -a 256') 'Mac valida SHA256 do pacote'
Assert-True ($macUpdaterText -match 'caij_os_counter') 'Mac protege contador local'
Assert-True ($publisherText -notmatch "'CoreCAIJ/caij_servidor_url\.txt'") 'publicacao nao inclui configuracao do servidor'
Assert-True ($serverText -match "\$rota -eq '/atualizacao/manifesto'") 'servidor expoe manifesto'
Assert-True ($serverText -match "\$rota -eq '/atualizacao/pacote'") 'servidor expoe pacote'
Assert-True ($vbsText -match 'AtualizarCAIJ\.ps1') 'Windows atualiza antes de iniciar'
Assert-True ($vbsText -match 'shell\.Run updateCommand, 0, True') 'Windows espera atualizacao terminar'
Assert-True ($vbsText -match 'Function NeedsUpdate\(\)') 'Windows faz consulta leve antes de abrir outro PowerShell'
Assert-True ($vbsText -match 'MSXML2\.ServerXMLHTTP\.6\.0') 'Windows consulta manifesto sem carregar PowerShell'
Assert-True ($vbsText -match 'setTimeouts 300, 300, 700, 700') 'consulta leve nao segura a abertura quando servidor falha'
Assert-True ($vbsText -match 'fso\.FileExists\(updaterPath\) And NeedsUpdate\(\)') 'atualizador pesado abre somente quando necessario'
Assert-True ($macLauncherText -match 'AtualizarCAIJ\.command') 'Mac atualiza antes de iniciar'
Assert-True ($usbInstallerText -match 'Get-ChildItem.+-Directory.+-Force') 'instalador localiza o app dentro de uma pasta do pendrive'
Assert-True ($usbInstallerText -match '\$target\s*=\s*Join-Path \$appRoot') 'instalador copia para a pasta real do app'
Assert-True ($usbInstallerText -match "'InfoNotebook\.bat'") 'instalador substitui o launcher antigo que ignorava o atualizador'
Assert-True ($usbInstallerText -match "'CoreCAIJ'.*'\.gitattributes'.*'\.gitignore'") 'instalador oculta infraestrutura tecnica'
Assert-True ($usbInstallerText -match 'CreateShortcut\(\$shortcutPath\)') 'instalador cria atalho dentro do pendrive'
Assert-True ($lenovoPreflightText -match 'SystemManufacturer') 'preflight identifica fabricante pelo Registro rapidamente'
Assert-True ($lenovoPreflightText -match 'Win32_ComputerSystem') 'preflight mantem CIM como contingencia'
Assert-True ($lenovoPreflightText -match "Keyboard Layout'[\s\S]*'Scancode Map'") 'preflight confere o mapeamento efetivo da tecla'
Assert-True ($lenovoPreflightText -match [regex]::Escape('6C4165F5BF6F93D211F43BFB061354278120F52862B2282443BF182A9F1236A2')) 'preflight fixa hash do utilitario oficial'
Assert-True ($lenovoPreflightText -match 'Get-AuthenticodeSignature') 'preflight exige assinatura valida Lenovo'
Assert-True ($lenovoPreflightText -match 'Start-Process.+-Verb RunAs') 'preflight solicita elevacao para aplicar o registro'
Assert-True ($infoNotebookText -match 'PrepararLenovo\.ps1') 'InfoNotebook executa verificacao Lenovo antes da interface'
Assert-True ($infoNotebookText -match '\$runLenovoPreflight\s*=\s*\$false') 'InfoNotebook evita processo extra quando verificacao rapida esta concluida'
Assert-True ($publisherText -match 'download\.lenovo\.com/consumer/mobiles/portcoderev2\.exe') 'publicacao baixa patch somente da Lenovo'
Assert-True ($publisherText -match 'lenovoExpectedHash') 'publicacao valida integridade do patch Lenovo'

'OK: Atualizacao tests'
