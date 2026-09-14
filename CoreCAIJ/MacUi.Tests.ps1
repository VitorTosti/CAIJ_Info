param(
    [string]$ServerPath = (Join-Path $PSScriptRoot 'mac-ui/server.py'),
    [string]$IndexPath = (Join-Path $PSScriptRoot 'mac-ui/index.html'),
    [string]$ScriptPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'InfoNotebookMac.command'),
    [string]$CentralServerPath = (Join-Path $PSScriptRoot 'ServidorImpressao.ps1')
)

$ErrorActionPreference = 'Stop'

function Assert-Equal {
    param([object]$Actual, [object]$Expected, [string]$Name)
    if ($Actual -ne $Expected) { throw "FAIL: $Name | esperado=[$Expected] atual=[$Actual]" }
}

function Assert-True {
    param([bool]$Condition, [string]$Name)
    if (-not $Condition) { throw "FAIL: $Name" }
}

Assert-True (Test-Path $ServerPath) 'servidor local da UI existe'
Assert-True (Test-Path $IndexPath) 'html da UI existe'
$indexText = Get-Content -Path $IndexPath -Raw
Assert-True ($indexText -match '<option>GRADE C</option>') 'cadastro Mac oferece Grade C unica'
Assert-True ($indexText -notmatch 'GRADE C - PINTURA|data-paint|paintRow') 'interface Mac nao possui variacoes de Grade C'
Assert-True ((Get-Content -Path $ScriptPath -Raw) -match 'launch_web_ui') 'launcher tenta abrir UI web'
Assert-True ((Get-Content -Path $ScriptPath -Raw) -match 'launch_dialog_ui') 'launcher tem fallback grafico sem python'
Assert-True ((Get-Content -Path $ScriptPath -Raw) -match 'dialog_set_os_manual') 'launcher tem acao grafica para OS manual'
Assert-True (-not ((Get-Content -Path $ScriptPath -Raw) -match 'command -v python3')) 'launcher nao chama stub python3 do macOS'

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) { $python = Get-Command python3 -ErrorAction SilentlyContinue }
if ($python) {
    $testCode = @'
import importlib.util
import pathlib
import sys
import tempfile

server_path = pathlib.Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("mac_ui_server", server_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

info = {
    "modelo": "Apple MacBook Pro M1",
    "serial": "ABC1234567",
    "cpu": "Apple M1 Pro",
    "gpu": "Apple M1 Pro (Integrada)",
    "ram": "16GB Unificada",
    "disco": "512GB SSD - Apple Storage",
    "bateria": "91% (Normal)",
}

payload = mod.build_print_payload(info, 235, "C", "Pintura tampa", True)
assert payload["os"] == 235
assert payload["modelo"] == "Apple MacBook Pro M1"
assert payload["serial"] == "ABC1234567"
assert payload["cpu"] == "Apple M1"
assert payload["gpu"] == "Apple M1"
assert payload["ram"] == "16GB Unificada"
assert payload["disco"] == "512GB SSD"
assert payload["tipoEquipamento"] == "Notebook"
assert payload["fichaCpu"] == "Apple M1 Pro"
assert payload["fichaGpu"] == "Apple M1 Pro (Integrada)"
assert payload["fichaRam"] == "16GB Unificada"
assert payload["fichaDisco"] == "512GB SSD - Apple Storage"
assert payload["grade"] == "C"
assert payload["obs"] == "Pintura tampa"
assert mod.cpu_short("Intel(R) Core(TM) i5-8259U CPU") == "i5 8th"
assert mod.cpu_short("Intel(R) Core(TM) i5-1035G1 CPU") == "i5 10th"
assert mod.cpu_short("Intel(R) Core(TM) i7-1165G7 CPU") == "i7 11th"

assert mod.validate_print_request("A", "") == ""
assert mod.validate_print_request("B", "") != ""
assert mod.validate_print_request("C - PINTURA 2", "") != ""
assert mod.validate_print_request("C", "") != ""
assert mod.validate_print_request("T - TRIAGEM", "") == ""
assert mod.validate_print_request("T - TRIAGEM", "Triagem inicial") == ""
assert mod.normalize_server_url("192.168.15.11") == "http://192.168.15.11:9100"
assert mod.normalize_server_url("INFOCAIJ") == "http://INFOCAIJ:9100"
assert mod.format_os(1384) == "C001384"

with tempfile.TemporaryDirectory() as temp:
    root = pathlib.Path(temp)
    core = root / "CoreCAIJ"
    core.mkdir()
    runtime = root / "runtime.json"
    runtime.write_text('{"osNumero":1384,"info":{}}', encoding="utf-8")
    (core / "caij_os_counter.txt").write_text("1384", encoding="utf-8")
    (core / "caij_servidor_url.txt").write_text("http://127.0.0.1:9100", encoding="utf-8")
    app = mod.AppState(core, runtime)
    candidates = app.server_candidates()
    assert candidates[0] == "http://127.0.0.1:9100"
    assert "http://INFOCAIJ.local:9100" in candidates
    assert "http://INFOCAIJ:9100" in candidates
    assert "http://192.168.15.11:9100" in candidates
    replies = iter([
        {"ultimoConfirmado": 1383, "proximoDisponivel": 1384},
        {"ultimoConfirmado": 1384, "proximoDisponivel": 1385},
    ])
    app.request_server = lambda *args, **kwargs: next(replies)
    assert app.watch_os()["event"] is False
    event = app.watch_os()
    assert event["event"] is True
    assert event["osCriada"] == "C001384"
    assert event["proximaOs"] == "C001385"

    def fake_server(path, method="GET", payload=None, timeout=12):
        if path == "/buscar-opcoes-altertag":
            return {
                "status": "ok",
                "mensagem": "Produtos encontrados.",
                "fonte": "catalogo",
                "produtos": [{"idProduto": 74, "codigo": "T074", "descricao": "Apple MacBook Pro", "valor": "0.00"}],
            }
        if path == "/criar-os-altertag":
            assert payload["tecnico"] == "Vitor"
            assert payload["serial"] == "MAC123"
            assert payload["produtoCodigo"] == "T074"
            return {"status": "ok", "osNumero": 1385, "proximoDisponivel": 1386, "mensagem": "OS criada."}
        if path == "/imprimir":
            assert payload["os"] == 1385
            return {"status": "ok"}
        if path == "/status-os":
            return {"proximoDisponivel": 1386}
        if path == "/proxima-os":
            raise AssertionError("OS criada nao deve reservar outro numero antes da impressao")
        raise AssertionError(path)

    app.request_server = fake_server
    products = app.search_products("MacBook")
    assert products["ok"] is True
    assert products["produtos"][0]["codigo"] == "T074"
    created = app.create_os({
        "tecnico": "Vitor",
        "serial": "MAC123",
        "referencia": "GRADE T - TRIAGEM",
        "produto": products["produtos"][0],
        "observacao": "",
    })
    assert created["ok"] is True
    assert created["osCriada"] == "C001385"
    assert app.public_state()["osNumero"] == 1385
    assert app.public_state()["pendingCreatedOs"] == 1385
    printed = app.print_label({"grade": "T - TRIAGEM", "obs": "", "includeOs": True, "info": info})
    assert printed["ok"] is True
    assert app.public_state()["osNumero"] == 1386
    assert app.public_state()["pendingCreatedOs"] == 0

    app.set_os_number(1221, manual=True)
    assert app.public_state()["manualOsSet"] is True
    def fake_existing_os_server(path, method="GET", payload=None, timeout=12):
        if path == "/imprimir":
            assert payload["os"] == 1221
            return {
                "status": "ok",
                "mensagem": "Impresso com sucesso e rastreador atualizado.",
                "rastreador": {"status": "updated", "os": "C001221"},
            }
        if path == "/status-os":
            return {"proximoDisponivel": 1386}
        if path == "/proxima-os":
            raise AssertionError("OS existente digitada manualmente nao pode reservar outro numero")
        raise AssertionError(path)
    app.request_server = fake_existing_os_server
    reprinted = app.print_label({"grade": "B", "obs": "TESTES: OK", "includeOs": True, "info": info})
    assert reprinted["ok"] is True
    assert reprinted["tracker"]["status"] == "updated"
    assert reprinted["syncWarning"] is False
    assert app.public_state()["manualOsSet"] is False
print("OK: python mac-ui helpers")
'@

    $tmp = Join-Path $PSScriptRoot '.caij_mac_ui_test.py'
    Set-Content -Path $tmp -Value $testCode -Encoding UTF8
    try {
        & $python.Source $tmp $ServerPath
        if ($LASTEXITCODE -ne 0) { throw "FAIL: python mac-ui helpers" }
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

$indexText = Get-Content -LiteralPath $IndexPath -Raw
$serverText = Get-Content -LiteralPath $ServerPath -Raw
$appText = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $ServerPath) 'app.js') -Raw
$portableText = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $ServerPath) 'portable.js') -Raw
$runtimeLoaderText = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $ServerPath) 'runtime-loader.js') -Raw
$styleText = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $ServerPath) 'style.css') -Raw
$commandText = Get-Content -LiteralPath $ScriptPath -Raw
$centralServerText = Get-Content -LiteralPath $CentralServerPath -Raw
$macPowerShellText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'InfoNotebookMac.ps1') -Raw
Assert-True ($indexText -match 'data-grade="T"') 'interface web oferece Grade T'
Assert-True ($indexText -match '<span>Triagem</span>') 'Grade T identifica Triagem'
Assert-True ($serverText -match '"/status-os-local"') 'servidor Mac acompanha OS em tempo real'
Assert-True ($serverText -match '"/api/os-watch"') 'servidor Mac expoe consulta de alerta'
Assert-True ($serverText -match '"/api/products"') 'servidor Mac expoe busca de produtos'
Assert-True ($serverText -match '"/api/create-os"') 'servidor Mac expoe criacao de OS'
Assert-True ($serverText -match 'subprocess\.Popen[\s\S]*osascript') 'alerta Mac usa dialogo nativo em primeiro plano'
Assert-True ($serverText -match 'target=monitor_os') 'monitor de OS roda independente da aba do navegador'
Assert-True ($appText -match 'setInterval\(watchOs,\s*4000\)') 'interface consulta novas OS periodicamente'
Assert-True ($appText -match 'testsOnlyMode[\s\S]*showAppView\("tests"\)') 'central abre diretamente como pagina no modo independente'
Assert-True ($appText -match 'window\.location\.protocol\s*===\s*"file:"\s*&&\s*!window\.CAIJ_NATIVE_RUNTIME') 'arquivo local sem dados abre somente a central de testes'
Assert-True ($indexText -match 'src="caij-runtime\.js"[\s\S]*src="portable\.js"[\s\S]*src="app\.js"') 'interface carrega runtime portatil antes do aplicativo'
Assert-True ($portableText -match 'window\.CAIJ_PORTABLE_API\s*=\s*portableApi') 'modo portatil fornece API local no navegador'
Assert-True ($runtimeLoaderText -match 'window\.location\.hash[\s\S]*TextDecoder\("utf-8"\)[\s\S]*CAIJ_NATIVE_RUNTIME') 'interface recebe os dados do Mac sem gravar no servidor'
Assert-True ($portableText -match 'window\.location\.origin') 'interface hospedada usa o proprio servidor como primeira opcao'
Assert-True ($portableText -match 'INFOCAIJ\.local:9100[\s\S]*INFOCAIJ:9100[\s\S]*192\.168\.15\.11:9100') 'modo portatil possui contingencias de servidor'
Assert-True ($portableText -match '"/buscar-opcoes-altertag"') 'modo portatil busca produtos no servidor CAIJ'
Assert-True ($portableText -match '"/criar-os-altertag"') 'modo portatil cadastra OS pelo servidor CAIJ'
Assert-True ($portableText -match '"/imprimir"') 'modo portatil envia etiqueta ao servidor CAIJ'
Assert-True ($centralServerText -match 'Access-Control-Allow-Origin') 'servidor permite acesso da interface portatil do Safari'
Assert-True ($centralServerText -match '\$metodo -eq ''OPTIONS''') 'servidor responde preflight da interface portatil'
Assert-True ($centralServerText -match '\$rota -match ''\^/mac') 'servidor publica a interface Mac na rede local'
Assert-True ($appText -match 'function\s+closeTestsPanel[\s\S]*document\.title\s*=\s*"CAIJ_TESTES_CONCLUIDOS"') 'central avisa ao launcher quando o tecnico volta ao app'
Assert-True ($appText -match 'closeTests.*textContent\s*=\s*"Voltar ao InfoNotebook"') 'central independente possui retorno explicito ao aplicativo'
Assert-True ($appText -match 'showOsAlert') 'interface mostra alerta visual de nova OS'
Assert-True ($indexText -match 'id="openCreateOs"') 'interface Mac oferece cadastro de OS'
Assert-True ($indexText -match 'id="openTests"') 'interface Mac oferece central de testes'
Assert-True ($indexText -match 'id="printOsInput"[\s\S]*id="toggleLabelEditor"[\s\S]*id="labelEditForm"') 'pagina de etiqueta permite alterar OS e dados manualmente'
Assert-True ($appText -match 'labelEditForm[\s\S]*api\("/api/info"[\s\S]*renderPreview\(\)') 'dados manuais sao aplicados na previa antes da impressao'
Assert-True ($indexText -match 'id="refreshReading"[\s\S]*id="copyDeviceInfo"[\s\S]*id="sessionClock"') 'faixa superior oferece acoes uteis sem repetir a ficha tecnica'
Assert-True ($indexText -notmatch 'id="newMachine"|Nova máquina') 'faixa superior nao oferece acao redundante de nova maquina'
Assert-True (($indexText | Select-String -Pattern 'class="test-row"' -AllMatches).Matches.Count -eq 5) 'central possui os cinco testes tecnicos previstos'
Assert-True ($indexText -match 'data-test="camera"[\s\S]*data-test="keyboard"[\s\S]*data-test="audio"[\s\S]*data-test="screen"[\s\S]*data-test="trackpad"') 'central organiza camera teclado audio tela e trackpad'
Assert-True ($appText -match 'requestUserMedia\(\{ video: true') 'camera usa captura local segura do navegador'
Assert-True ($appText -match 'requestUserMedia\(\{ audio: true') 'microfone usa captura local segura do navegador'
Assert-True ($appText -match 'navigator\.mediaDevices\s*&&\s*typeof navigator\.mediaDevices\.getUserMedia') 'camera trata Safari sem mediaDevices sem erro undefined'
Assert-True ($appText -match 'function\s+openKeyboardTest') 'teclado possui mapa interativo local'
Assert-True ($appText -match '"ESC","F1","F2","F3","F4","F5","F6"[\s\S]*"F12"') 'mapa do teclado inclui Esc e F1 ate F12'
$macRowsMatch = [regex]::Match($appText, 'const macKeyboardRows = \[(?<rows>[\s\S]*?)\n\s*\];')
$macRowCount = @($macRowsMatch.Groups['rows'].Value -split "`r?`n" | Where-Object { $_ -match '^\s+\[' }).Count
Assert-True ($macRowsMatch.Success -and $macRowCount -eq 5) 'teclado do Mac possui exatamente cinco linhas fixas'
Assert-True ($styleText -match '\.keyboard-row\s*\{[\s\S]*min-width:\s*760px') 'linhas do teclado preservam a disposicao em telas estreitas'
Assert-True ($appText -match 'Quote:\s*"''"[\s\S]*Slash:\s*"/"') 'pontuacao usa codigo fisico para apostrofo e barra'
Assert-True ($appText -match 'event\.preventDefault\(\)[\s\S]*event\.stopPropagation\(\)') 'Esc nao fecha o teste durante a validacao do teclado'
Assert-True ($appText -match 'use Fn \+ F1') 'teste orienta o uso de Fn nas teclas de funcao do Mac'
Assert-True ($appText -match 'function\s+openScreenTest') 'tela possui teste dedicado de cores'
Assert-True ($appText -match 'function\s+openTrackpadTest') 'trackpad mede movimento clique e rolagem'
Assert-True ($appText -match 'const testLabels\s*=\s*\{[\s\S]*camera:\s*"Camera"[\s\S]*keyboard:\s*"Teclado"[\s\S]*audio:\s*"Som/Mic"[\s\S]*screen:\s*"Tela"[\s\S]*trackpad:\s*"Trackpad"') 'resumo possui rotulo para cada teste realizado'
Assert-True ($appText -match 'return `TESTES: \$\{overall\} \| \$\{details\}`') 'resumo combina status geral e resultados individuais sem rotulo exclusivo do Mac'
Assert-True ($appText -match 'return `TESTES: \$\{testsOverall\(\)\}`') 'etiqueta recebe somente o resultado compacto dos testes'
Assert-True ($appText -match 'function\s+syncCompletedTestsToObservations[\s\S]*appendTestsReport') 'resultado final entra automaticamente nas observacoes'
Assert-True ($appText -match 'if \(testsOnlyMode\)[\s\S]*copyText\(report\)[\s\S]*caij:mac-tests-observation') 'central independente prepara a observacao para o app nativo ao finalizar'
Assert-True ($indexText -match 'id="testsActionStatus"') 'central confirma visualmente a inclusao da observacao'
Assert-True ($indexText -match 'id="finishTests">Testes finalizados</button>') 'central exibe acao clara quando todos os testes terminam'
Assert-True ($indexText -notmatch 'id="addTestsToObs"|Adicionar a observa') 'central nao exige inclusao manual nas observacoes'
Assert-True ($styleText -match '\.test-row\.passed') 'central diferencia visualmente teste aprovado'
Assert-True ($styleText -match '\.test-row\.failed') 'central diferencia visualmente teste reprovado'
Assert-True ($styleText -match '@media \(max-width: 560px\)') 'central se adapta a janela estreita'
Assert-True ($indexText -match 'class="device-table-wrap"') 'leitura do Mac possui area para tabela tecnica'
Assert-True ($appText -match '<table class="device-table">') 'leitura do Mac renderiza tabela tecnica'
Assert-True ($appText -match '<th>Informacao</th><th>Valor detectado</th>') 'tabela tecnica possui cabecalhos claros'
Assert-True ($styleText -match '\.device-table\s*\{') 'tabela tecnica possui estilo dedicado'
Assert-True ($indexText -match 'data-technician="Vitor"[\s\S]*data-technician="Outro"') 'cadastro exige identificacao do tecnico'
Assert-True ($appText -match 'api\("/api/create-os"') 'interface envia cadastro ao backend local'
Assert-True ($appText -match 'function\s+sortProductsWithTFirst') 'busca possui ordenacao dedicada de produtos'
Assert-True ($appText -match 'leftIsT\s*=\s*/\^T\\d/[\s\S]*return leftIsT \? -1 : 1') 'codigos T aparecem antes das demais familias'
Assert-True ($appText -match 'localeCompare\(rightCode,\s*"pt-BR",\s*\{ numeric: true') 'codigos T sao ordenados numericamente'
Assert-True ($serverText -match 'FALLBACK_SERVER_LOCAL\s*=\s*"http://INFOCAIJ\.local:9100"') 'Mac tenta nome mDNS do servidor'
Assert-True ($serverText -match 'FALLBACK_SERVER_IP\s*=\s*"http://192\.168\.15\.11:9100"') 'Mac preserva IP atual como contingencia'
Assert-True ($serverText -match 'def server_candidates') 'Mac monta lista de servidores alternativos'
Assert-True ($serverText -match 'socket\.getaddrinfo') 'Mac ignora nomes que nao resolvem antes do envio'
Assert-True ($commandText -match 'check_os_alert') 'fallback nativo acompanha novas OS'
Assert-True ($commandText -match 'start_native_os_monitor') 'fallback nativo monitora OS em segundo plano'
Assert-True ($commandText -match 'check_internet_connection\(\)') 'Mac possui verificacao dedicada de internet'
Assert-True ($commandText -match 'captive\.apple\.com/hotspot-detect\.html') 'verificacao usa endpoint de conectividade da Apple'
Assert-True ($commandText -match 'cloudflare\.com/cdn-cgi/trace') 'verificacao possui segundo endpoint independente'
Assert-True ($commandText -match 'curl -fsS --connect-timeout 1 --max-time 3') 'verificacao de internet possui limite curto'
Assert-True ($commandText -match 'dialog_message "Mac sem internet"') 'Mac alerta claramente quando esta offline'
Assert-True ($commandText -match 'warn_if_no_internet \|\| true[\s\S]*collect_info') 'alerta nao impede a abertura nem a coleta do aplicativo'
Assert-True ($commandText -match 'dialog_create_os') 'fallback nativo permite cadastrar OS'
Assert-True ($commandText -match 'clipboard_tests_observation[\s\S]*pbpaste') 'fallback nativo recupera o resultado copiado dos testes'
Assert-True ($commandText -match 'dialog_input "Observacao" "\$suggested_obs"') 'cadastro nativo sugere o resultado dos testes na observacao'
Assert-True ($commandText -notmatch 'Testes do Mac\|Cadastrar OS\|Imprimir etiqueta\|Editar dados\|Definir OS manual') 'menu principal nativo nao exibe definicao manual de OS'
Assert-True ($commandText -match 'action="\$\(dialog_choose "\$preview"') 'impressao nativa abre resumo interativo'
Assert-True ($commandText -match 'RESUMO DA ETIQUETA[\s\S]*Modelo:[\s\S]*Serial:[\s\S]*CPU:[\s\S]*RAM:[\s\S]*Armazenamento:[\s\S]*GPU:[\s\S]*Bateria:[\s\S]*Ciclos:') 'resumo nativo mostra dados curtos e ciclos separados'
Assert-True ($commandText -match 'Armazenamento: \$\(disk_short "\$DISK"\)') 'resumos nativos mostram somente capacidade e tipo do disco'
Assert-True ($commandText -match 'OS atual: \$\(format_os "\$OS_NUMBER"\)\|Grade: \$grade\|Observacao: \$obs_option\|Incluir OS: \$include_label\|IMPRIMIR ETIQUETA') 'resumo nativo oferece campos clicaveis'
Assert-True ($commandText -match 'dialog_set_os_manual "sim"[\s\S]*skip_reserve="sim"') 'OS escolhida no resumo nao e substituida pela reserva automatica'
Assert-True ($commandText -notmatch 'Selecione o tipo de pintura') 'impressao nativa usa Grade C unica'
Assert-True ($commandText -match '"Testes do Mac"\)\s*open_native_tests') 'fallback mantem o processo vivo ao abrir a central de testes'
Assert-True ($commandText -match 'tests_file="\$CORE/mac-ui/index\.html"') 'fallback usa a interface presente em todas as instalacoes'
Assert-True ($commandText -match 'open -a Safari "\$tests_url"') 'fallback abre os testes locais no Safari'
Assert-True ($commandText -match 'write_portable_runtime_data') 'launcher gera dados para a interface portatil'
Assert-True ($commandText -match 'launch_portable_web_ui[\s\S]*portable\.js') 'launcher abre interface completa sem depender de Python'
Assert-True ($commandText -match 'ui_url="file://\$ui_file\?app=\$cache_key"[\s\S]*ui_url="\$\{ui_url// /%20\}"[\s\S]*open -a Safari "\$ui_url"') 'launcher abre caminho de pendrive com espacos e evita cache no Safari'
Assert-True ($commandText -match 'launch_local_static_ui[\s\S]*http://127\.0\.0\.1:\$port/') 'launcher oferece origem local segura para camera e microfone'
Assert-True ($commandText -match 'if launch_web_ui; then[\s\S]*if launch_local_static_ui; then[\s\S]*if launch_portable_web_ui; then') 'origens locais seguras tem prioridade na abertura do Mac'
Assert-True ($appText -match '!window\.isSecureContext[\s\S]*interface local segura') 'testes explicam quando camera e microfone estao em origem insegura'
Assert-True ($commandText -match '! -w "\$DIR" \|\| ! -w "\$CORE"') 'launcher detecta pendrive somente leitura no macOS'
Assert-True ($commandText -match 'Library/Application Support/CAIJ/InfoNotebook') 'launcher usa copia local gravavel para pendrive NTFS'
Assert-True ($commandText -match 'exec /bin/zsh "\$UPDATE_ROOT/InfoNotebookMac\.command" --caij-after-update') 'launcher executa imediatamente a copia local atualizada'
Assert-True ($indexText -match 'id="internetBadge"[\s\S]*id="serverBadge"[\s\S]*id="versionBadge"') 'cabecalho mostra internet servidor e versao'
Assert-True ($indexText -match 'id="osInput"') 'OS pode ser editada diretamente no resumo'
Assert-True ($indexText -match 'id="brandLogo"[\s\S]*id="fullscreenBtn"') 'cabecalho mostra logo e controle de tela cheia'
Assert-True ($appText -match 'persistEditedOs') 'alteracao visual da OS e aplicada antes da impressao'
Assert-True ($appText -match 'document\.documentElement\.requestFullscreen') 'interface permite tela cheia por acao direta'
Assert-True ($commandText -match '\$server_url/mac/\?app=\$cache_key#runtime=\$runtime_token') 'launcher prefere interface hospedada no servidor CAIJ'
Assert-True ($commandText -match 'set bounds of front window to screenBounds') 'launcher amplia a janela do Safari ao abrir'
Assert-True ($appText -notmatch 'command:\s*"open-tests"') 'botao de testes nao abre outro link no Mac'
Assert-True ($indexText -match 'class="app-view tests-page hidden" id="testsView"') 'testes possuem pagina propria dentro da interface'
Assert-True ($indexText -match 'class="app-view create-os-page hidden" id="createOsView"') 'cadastro de OS possui pagina propria dentro da interface'
Assert-True ($appText -match 'openTests[\s\S]*showAppView\("tests"\)') 'botao abre a pagina de testes dentro da mesma interface'
Assert-True ($appText -match 'function\s+openCreateOs[\s\S]*showAppView\("createOs"\)') 'botao abre a pagina de cadastro dentro da mesma interface'
Assert-True ($indexText -notmatch 'id="testsDialog"|id="createOsDialog"') 'testes e cadastro nao usam mais pop-up'
Assert-True ($portableText -match '"/mac/comando"') 'interface envia comando nativo ao launcher Mac'
Assert-True ($centralServerText -match "'/mac/comando'") 'servidor encaminha comando da central de testes'
Assert-True ($commandText -match 'native_command[\s\S]*open_native_tests "hosted"') 'launcher abre testes locais quando solicitado pela interface'
Assert-True ($commandText -match 'tell application "Safari" to activate') 'fallback entrega o foco ao Safari sem dialogo sobreposto'
Assert-True ($commandText -match 'set miniaturized of front window to true') 'fallback recolhe a janela do InfoNotebook durante os testes'
Assert-True ($commandText -match 'CAIJ_TESTES_CONCLUIDOS[\s\S]*set miniaturized of front window to false[\s\S]*activate') 'fallback restaura o mesmo InfoNotebook ao concluir os testes'
Assert-True ($commandText -match 'Memoria: \$\{RAM:-Nao detectada\}') 'janela nativa mostra memoria diretamente'
Assert-True ($commandText -match 'Armazenamento: \$\(disk_short "\$DISK"\)') 'janela nativa mostra armazenamento resumido'
Assert-True ($commandText -match 'Bateria: \$battery_summary') 'janela nativa mostra bateria diretamente'
Assert-True ($commandText -match 'Ciclos: \$cycles_summary') 'janela nativa mostra ciclos diretamente'
Assert-True ($commandText -notmatch '"Ver tabela de informacoes\|Cadastrar OS') 'janela nativa nao depende de abrir navegador'
Assert-True ($commandText -match 'http://INFOCAIJ\.local:9100') 'fallback nativo tenta o nome mDNS do servidor'
Assert-True ($commandText -notmatch 'Grade T - Triagem\."') 'fallback nao exige observacoes para Grade T'
Assert-True ($commandText -match '"fichaCpu":"\$\(json_escape "\$CHIP"\)"') 'fallback envia CPU completa para ficha QR'
Assert-True ($commandText -match '"fichaGpu":"\$\(json_escape "\$GPU"\)"') 'fallback envia GPU completa para ficha QR'
Assert-True ($commandText -match '"fichaDisco":"\$\(json_escape "\$DISK"\)"') 'fallback envia disco completo para ficha QR'
Assert-True ($commandText -match 'chip_label="I\$\{match\[1\]\}"') 'fallback identifica Mac Intel pelo processador'
Assert-True ($commandText -match 'MODEL="\$MODEL_NAME"[\s\S]*MODEL="\$MODEL \$chip_label"') 'fallback exibe modelo amigavel com processador'
Assert-True ($commandText -match 'mac_model_year\(\)') 'fallback identifica o ano do modelo Mac'
Assert-True ($commandText -match 'MacBookPro15,2\) echo "2018"') 'fallback reconhece o MacBookPro15,2 como 2018'
Assert-True ($commandText -match 'sysctl -n machdep\.cpu\.brand_string') 'fallback consulta modelo completo da CPU Intel'
Assert-True ($commandText -match 'if \[\[ "\$CHIP" == Apple\* \]\]; then[\s\S]*?RAM="\$\{match\[1\]\}GB Unificada"[\s\S]*?else[\s\S]*?RAM="\$\{match\[1\]\}GB"') 'fallback usa memoria unificada somente em Apple Silicon'
Assert-True ($commandText -match 'ioreg -r -c AppleSmartBattery') 'fallback consulta bateria pelo ioreg'
Assert-True ($commandText -match 'StateOfHealth') 'fallback aceita saude direta informada pela bateria'
Assert-True ($commandText -match 'Cycle Count') 'fallback consulta ciclos no system_profiler'
Assert-True ($commandText -match 'CycleCount') 'fallback consulta ciclos no ioreg'
Assert-True ($commandText -match 'NominalChargeCapacity') 'fallback aceita capacidade nominal em Macs Intel'
Assert-True ($commandText -match 'if\s*\(n\s*>\s*max\)\s*max=n') 'fallback escolhe maior capacidade positiva repetida no ioreg'
Assert-True ($commandText -match 'battery-diagnostic\.txt') 'fallback salva diagnostico quando a bateria permanece indisponivel'
Assert-True ($commandText -match '\$bat_max" == <-> && "\$bat_max" -gt 0') 'fallback ignora capacidade maxima zerada'
Assert-True ($macPowerShellText -match 'function\s+Get-MacBatteryHealthFallback') 'PowerShell possui fallback de bateria do Mac'
Assert-True ($macPowerShellText -match 'function\s+Get-MacBatteryCycleCountFallback') 'PowerShell possui fallback dos ciclos da bateria do Mac'
Assert-True ($macPowerShellText -match 'StateOfHealth') 'PowerShell aceita saude direta informada pela bateria'
Assert-True ($macPowerShellText -match 'NominalChargeCapacity') 'PowerShell aceita capacidade nominal em Macs Intel'
Assert-True ($macPowerShellText -match 'function\s+Get-IoregPositiveValue') 'PowerShell percorre valores repetidos da bateria'
Assert-True ($macPowerShellText -match '\$maxCapacity\s+-le\s+0') 'PowerShell rejeita capacidade maxima zerada'
Assert-True ($macPowerShellText -match "\`$chip\s+-match\s+'\(\?i\)Apple\\s\+M'") 'PowerShell usa memoria unificada somente em Apple Silicon'

'OK: MacUi tests'
