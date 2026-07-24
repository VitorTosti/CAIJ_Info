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
assert payload["grade"] == "C"
assert payload["obs"] == "Pintura tampa"

assert mod.validate_print_request("A", "") == ""
assert mod.validate_print_request("B", "") != ""
assert mod.validate_print_request("C - PINTURA 2", "") != ""
assert mod.validate_print_request("T - TRIAGEM", "") != ""
assert mod.validate_print_request("T - TRIAGEM", "Triagem inicial") == ""
assert mod.normalize_server_url("192.168.15.127") == "http://192.168.15.127:9100"
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

'OK: MacUi tests'
