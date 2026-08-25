param(
    [string]$ServerPath = (Join-Path $PSScriptRoot 'mac-ui/server.py'),
    [string]$IndexPath = (Join-Path $PSScriptRoot 'mac-ui/index.html'),
    [string]$ScriptPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'InfoNotebookMac.command')
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
Assert-True ((Get-Content -Path $ScriptPath -Raw) -match 'launch_web_ui') 'launcher tenta abrir UI web'
Assert-True ((Get-Content -Path $ScriptPath -Raw) -match 'launch_dialog_ui') 'launcher tem fallback grafico sem python'
Assert-True ((Get-Content -Path $ScriptPath -Raw) -match 'Definir OS manual') 'menu grafico permite definir OS manual'
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

assert mod.validate_print_request("A", "") == ""
assert mod.validate_print_request("B", "") != ""
assert mod.validate_print_request("C - PINTURA 2", "") != ""
assert mod.validate_print_request("T - TRIAGEM", "") == ""
assert mod.validate_print_request("T - TRIAGEM", "Triagem inicial") == ""
assert mod.normalize_server_url("192.168.15.127") == "http://192.168.15.127:9100"
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
$commandText = Get-Content -LiteralPath $ScriptPath -Raw
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
Assert-True ($appText -match 'showOsAlert') 'interface mostra alerta visual de nova OS'
Assert-True ($indexText -match 'id="openCreateOs"') 'interface Mac oferece cadastro de OS'
Assert-True ($indexText -match 'data-technician="Vitor"[\s\S]*data-technician="Outro"') 'cadastro exige identificacao do tecnico'
Assert-True ($appText -match 'api\("/api/create-os"') 'interface envia cadastro ao backend local'
Assert-True ($commandText -match 'check_os_alert') 'fallback nativo acompanha novas OS'
Assert-True ($commandText -match 'start_native_os_monitor') 'fallback nativo monitora OS em segundo plano'
Assert-True ($commandText -match 'dialog_create_os') 'fallback nativo permite cadastrar OS'
Assert-True ($commandText -notmatch 'Grade T - Triagem\."') 'fallback nao exige observacoes para Grade T'
Assert-True ($commandText -match '"fichaCpu":"\$\(json_escape "\$CHIP"\)"') 'fallback envia CPU completa para ficha QR'
Assert-True ($commandText -match '"fichaGpu":"\$\(json_escape "\$GPU"\)"') 'fallback envia GPU completa para ficha QR'
Assert-True ($commandText -match '"fichaDisco":"\$\(json_escape "\$DISK"\)"') 'fallback envia disco completo para ficha QR'
Assert-True ($commandText -match 'MODEL="Apple \$MODEL_NAME \(\$MODEL_ID\)"') 'fallback inclui identificador exato do modelo Mac'
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
