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
$serverInstallerText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'AplicarServidorLocal.ps1') -Raw
$watchdogText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'ServidorImpressaoWatchdog.ps1') -Raw
$publisherBatText = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'PublicarAtualizacao.bat') -Raw

Assert-True ($updaterText -match '/atualizacao/manifesto') 'Windows consulta manifesto no servidor CAIJ'
Assert-True ($updaterText -match 'Get-FileHash.+SHA256') 'Windows valida SHA256 do pacote'
Assert-True ($updaterText -match 'caij_historico_notebooks') 'Windows protege historico local'
Assert-True ($updaterText -match 'function\s+Get-CaijUpdateServerCandidates') 'Windows descobre o servidor mesmo com configuracao antiga'
Assert-True ($updaterText -match "candidates\.Add\('http://INFOCAIJ:9100'\)") 'Windows tenta o nome estavel do servidor primeiro'
Assert-True ($updaterText -match "candidates\.Add\('http://192\.168\.15\.11:9100'\)") 'Windows preserva o IP conhecido como contingencia'
Assert-True ($updaterText -match 'WriteAllText\(\$serverConfigPath,\s*\$candidate') 'Windows salva automaticamente o servidor encontrado'
Assert-True ($updaterText -match 'function\s+Set-CaijLauncherVisibility') 'Windows restaura arquivos tecnicos como ocultos'
Assert-True ($updaterText -match 'function\s+New-CaijWindowsShortcut') 'Windows cria atalho local sem caminho fixo'
Assert-True ($updaterText -match 'manifesto"\s+-Method Get\s+-TimeoutSec 5') 'Windows limita espera e tolera resposta momentaneamente lenta'
Assert-True ($macUpdaterText -match 'shasum -a 256') 'Mac valida SHA256 do pacote'
Assert-True ($macUpdaterText -match 'caij_os_counter') 'Mac protege contador local'
Assert-True ($macUpdaterText -match 'SERVER_CANDIDATES=') 'Mac tenta servidores alternativos antes de desistir'
Assert-True ($macUpdaterText -match 'http://INFOCAIJ\.local:9100') 'Mac tenta o nome mDNS compativel com macOS'
Assert-True ($macUpdaterText -match 'http://192\.168\.15\.11:9100') 'Mac preserva o IP atual como contingencia'
Assert-True ($macUpdaterText -match 'print -rn -- "\$BASE_URL" > "\$SERVER_FILE"') 'Mac salva automaticamente o servidor encontrado'
Assert-True ($macUpdaterText -match 'TEMP_TARGET="\$\{TARGET\}\.caij-new\.\$\$"[\s\S]*mv -f "\$TEMP_TARGET" "\$TARGET"') 'Mac substitui arquivos sem truncar o atualizador em execucao'
Assert-True ($macUpdaterText -match 'STATUS_FILE="\$CORE_DIR/caij_atualizacao_status\.txt"') 'Mac registra o resultado da tentativa de atualizacao'
Assert-True ($macUpdaterText -match 'exit 10') 'Mac informa ao launcher quando instalou uma versao nova'
Assert-True ($publisherText -notmatch "'CoreCAIJ/caij_servidor_url\.txt'") 'publicacao nao inclui configuracao do servidor'
Assert-True ($publisherText -match "'CoreCAIJ/InfoNotebookWindowsPreview\.ps1'") 'publicacao inclui o inicializador da interface web Windows'
Assert-True ($serverText -match "\$rota -eq '/atualizacao/manifesto'") 'servidor expoe manifesto'
Assert-True ($serverText -match "\$rota -eq '/atualizacao/pacote'") 'servidor expoe pacote'
Assert-True ($vbsText -match 'AtualizarCAIJ\.ps1') 'Windows atualiza antes de iniciar'
Assert-True ($vbsText -match 'scriptPath = fso\.BuildPath\(coreDir, "InfoNotebookWindowsPreview\.ps1"\)') 'atalho Windows abre a interface web nova'
Assert-True ($vbsText -match 'legacyScriptPath = fso\.BuildPath\(coreDir, "InfoNotebook\.ps1"\)') 'atalho Windows preserva a interface antiga como contingencia'
Assert-True ($updaterText -match 'Join-Path \$coreRoot ''InfoNotebookWindowsPreview\.ps1''') 'atualizador manual abre a interface web nova'
Assert-True ($vbsText -match 'shell\.Run updateCommand, 0, True') 'Windows espera atualizacao terminar'
Assert-True ($vbsText -match 'Function NeedsUpdate\(\)') 'Windows faz consulta leve antes de abrir outro PowerShell'
Assert-True ($vbsText -match 'Function ProbeUpdateServer\(baseUrl, localVersion\)') 'iniciador tenta recuperar configuracao antiga do servidor'
Assert-True ($vbsText -match 'fallbackUrl = "http://INFOCAIJ:9100"') 'iniciador consulta o nome estavel quando a configuracao salva falha'
Assert-True ($vbsText -match 'fallbackIpUrl = "http://192\.168\.15\.11:9100"') 'iniciador preserva o IP atual como contingencia'
Assert-True ($vbsText -match 'SaveServerUrl baseUrl') 'iniciador corrige o IP salvo depois de localizar o servidor'
Assert-True ($vbsText -match 'MSXML2\.ServerXMLHTTP\.6\.0') 'Windows consulta manifesto sem carregar PowerShell'
Assert-True ($vbsText -match 'setTimeouts 300, 300, 700, 700') 'consulta leve nao segura a abertura quando servidor falha'
Assert-True ($vbsText -match 'fso\.FileExists\(updaterPath\) And NeedsUpdate\(\)') 'atualizador pesado abre somente quando necessario'
Assert-True ($macLauncherText -match 'AtualizarCAIJ\.command') 'Mac atualiza antes de iniciar'
Assert-True ($macLauncherText -match 'UPDATE_EXIT=\$\?[\s\S]*exec /bin/zsh "\$DIR/InfoNotebookMac\.command" --caij-after-update') 'Mac reinicia no mesmo clique depois de atualizar'
Assert-True ($usbInstallerText -match 'Get-ChildItem.+-Directory.+-Force') 'instalador localiza o app dentro de uma pasta do pendrive'
Assert-True ($usbInstallerText -match '\$target\s*=\s*Join-Path \$appRoot') 'instalador copia para a pasta real do app'
Assert-True ($usbInstallerText -match "'InfoNotebook\.bat'") 'instalador substitui o launcher antigo que ignorava o atualizador'
Assert-True ($usbInstallerText -match "'CoreCAIJ/caij_servidor_url\.txt'") 'instalador grava endereco do servidor no pendrive'
Assert-True ($usbInstallerText -match 'function\s+Update-CaijPendriveNow') 'instalador atualiza o pendrive imediatamente'
Assert-True ($usbInstallerText -match '-ServerBaseUrl \$baseUrl') 'instalador repassa ao atualizador o servidor que acabou de validar'
Assert-True ($updaterText -match 'foreach \(\$attempt in 1\.\.3\)') 'atualizador repete descoberta em falhas momentaneas'
Assert-True ($usbInstallerText -match '/atualizacao/manifesto') 'instalador confirma a versao publicada pela rede'
Assert-True ($usbInstallerText -match 'versaoLocal\s+-ne\s+\$versaoRemota') 'instalador falha claramente se a versao nao for aplicada'
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
Assert-True ($publisherBatText -match 'CoreCAIJ\\AplicarServidorLocal\.ps1') 'publicacao tambem aplica mudancas do servidor central'
Assert-True ($serverInstallerText -match "function\s+Get-CaijFileSha256") 'instalador central compara SHA256 mesmo em PowerShell sem Get-FileHash'
Assert-True ($serverInstallerText -match 'ServidorImpressao\.backup-') 'instalador central preserva backup antes de substituir'
Assert-True ($serverInstallerText -match 'Get-CimInstance Win32_Process') 'instalador central identifica o processo exato antes de reiniciar'
Assert-True ($serverInstallerText -match 'ServidorImpressaoWatchdog\.ps1') 'instalador central aplica monitor de recuperacao'
Assert-True ($serverInstallerText -match 'http add urlacl') 'instalador autoriza o watchdog a reiniciar sem elevacao'
Assert-True ($watchdogText -match 'AddSeconds\(60\)') 'watchdog limita novas tentativas depois de uma falha'
Assert-True ($watchdogText -match '-NoFailurePrompt') 'watchdog nao deixa processos presos em prompt invisivel'
Assert-True ($serverInstallerText -match "GetFolderPath\('Startup'\)") 'monitor inicia automaticamente com o usuario'
Assert-True ($serverInstallerText -match 'CreateShortcut\(\$startupShortcutPath\)') 'instalador cria inicializacao invisivel sem exigir administrador'
Assert-True ($serverInstallerText -match "http://127\.0\.0\.1:9100/status") 'instalador central confirma o servidor apos reiniciar'

'OK: Atualizacao tests'
