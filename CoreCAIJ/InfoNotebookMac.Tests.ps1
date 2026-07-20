param(
    [string]$ScriptPath = (Join-Path $PSScriptRoot 'InfoNotebookMac.ps1')
)

$ErrorActionPreference = 'Stop'

function Assert-Equal {
    param(
        [object]$Actual,
        [object]$Expected,
        [string]$Name
    )
    if ($Actual -ne $Expected) {
        throw "FAIL: $Name | esperado=[$Expected] atual=[$Actual]"
    }
}

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Name
    )
    if (-not $Condition) {
        throw "FAIL: $Name"
    }
}

. $ScriptPath -Library

$hardwareJson = @'
{
  "SPHardwareDataType": [
    {
      "machine_name": "MacBook Pro",
      "machine_model": "MacBookPro18,3",
      "serial_number": "ABC1234567",
      "chip_type": "Apple M1 Pro",
      "number_processors": "proc 1",
      "total_number_cores": "10",
      "physical_memory": "16 GB"
    }
  ],
  "SPDisplaysDataType": [
    {
      "sppci_model": "Apple M1 Pro",
      "spdisplays_ndrvs": [
        {
          "_name": "Color LCD",
          "spdisplays_resolution": "3024 x 1964 Retina"
        }
      ]
    }
  ],
  "SPStorageDataType": [
    {
      "_name": "Macintosh HD",
      "size": "494.38 GB",
      "physical_drive": {
        "device_name": "APPLE SSD AP0512R",
        "media_type": "SSD"
      }
    }
  ],
  "SPPowerDataType": [
    {
      "sppower_battery_health_info": {
        "sppower_battery_health": "Normal"
      },
      "sppower_battery_charge_info": {
        "sppower_battery_max_capacity": "91"
      }
    }
  ]
}
'@

$info = ConvertFrom-MacSystemProfilerJson -JsonText $hardwareJson
Assert-Equal $info.Modelo 'Apple MacBook Pro (MacBookPro18,3)' 'modelo'
Assert-Equal $info.Serial 'ABC1234567' 'serial'
Assert-Equal $info.CPU 'Apple M1 Pro' 'cpu'
Assert-Equal $info.Nucleos '10 nucleos' 'nucleos'
Assert-Equal $info.RAM '16GB Unificada' 'ram'
Assert-Equal $info.GPU 'Apple M1 Pro (Integrada)' 'gpu'
Assert-Equal $info.Tela '3024 x 1964 Retina' 'tela'
Assert-Equal $info.Discos '512GB SSD - APPLE SSD AP0512R' 'disco normalizado'
Assert-Equal $info.BatSaude '91% (Normal)' 'bateria'

Assert-Equal (Get-IntelCpuShort 'Intel(R) Core(TM) i5-1035G1 CPU') 'I5 10' 'intel curto'
Assert-Equal (Get-RamShort '16GB DDR4 3200 MHz') '16GB DDR4' 'ram curto ddr'
Assert-Equal (Get-RamShort '16GB Unificada') '16GB Unificada' 'ram curta unificada'
Assert-Equal (Get-DiskShort '512GB SSD - APPLE SSD AP0512R') '512GB SSD' 'disco curto'
Assert-Equal (Get-GpuShort 'Nao identificada') '' 'gpu desconhecida some'
Assert-Equal (Format-OsCodigo -Numero 235) 'C000235' 'formato os'
Assert-Equal (Resolve-CaijGradeSelection -Grade 'C' -Pintura '2') 'C - PINTURA 2' 'grade c pintura por numero'
Assert-Equal (Resolve-CaijGradeSelection -Grade 'C' -Pintura 'PINTURA 3') 'C - PINTURA 3' 'grade c pintura por texto'
Assert-Equal (Resolve-CaijGradeSelection -Grade 'C - PINTURA 1') 'C - PINTURA 1' 'grade c pintura ja normalizada'
Assert-Equal (Resolve-CaijGradeSelection -Grade 'B') 'B' 'grade b preservada'
Assert-True ((Get-ServidorCandidates) -contains 'http://192.168.15.127:9100') 'fallback do servidor usa IP atual'
Assert-True (-not ((Get-ServidorCandidates) -contains 'http://192.168.15.54:9100')) 'fallback do servidor nao usa IP antigo'

$payload = New-CaijPrintPayload -Info $info -OsNumero 235 -Grade 'A' -Obs 'Teste ok' -IncludeOs:$true -Manual:$false
Assert-Equal $payload.os 235 'payload os'
Assert-Equal $payload.modelo 'Apple MacBook Pro (MacBookPro18,3)' 'payload modelo'
Assert-Equal $payload.serial 'ABC1234567' 'payload serial'
Assert-Equal $payload.cpu 'Apple M1 Pro' 'payload cpu'
Assert-Equal $payload.gpu 'Apple M1 Pro' 'payload gpu'
Assert-Equal $payload.ram '16GB Unificada' 'payload ram'
Assert-Equal $payload.disco '512GB SSD' 'payload disco'

$info.GPU = 'Nao identificada'
$payloadSemGpu = New-CaijPrintPayload -Info $info -OsNumero 235 -Grade 'A' -Obs '' -IncludeOs:$true -Manual:$false
Assert-True ($null -eq $payloadSemGpu.gpu) 'payload sem gpu desconhecida'

'OK: InfoNotebookMac tests'
