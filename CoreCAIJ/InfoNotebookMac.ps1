param(
    [switch]$Library
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$NL = [Environment]::NewLine
$script:baseDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $PSCommandPath }
$script:osArquivo = Join-Path $script:baseDir 'caij_os_counter.txt'
$script:historicoArquivo = Join-Path $script:baseDir 'caij_historico_notebooks.json'
$script:registroBaseDir = $null
$script:registroBaseDirFallback = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'CAIJ/Registros'
$script:ultimoStatusServidor = 'nao verificado'
$script:ultimaSincronizacaoOs = ''
$script:servidorBaseUrlCache = $null
$script:osNumero = 235

if (Test-Path $script:osArquivo) {
    try { $script:osNumero = [int]((Get-Content $script:osArquivo -Raw -ErrorAction Stop).Trim()) } catch {}
}
if ($script:osNumero -lt 235) { $script:osNumero = 235 }

function Format-OsCodigo {
    param([int]$Numero)
    if ($Numero -lt 1) { return '' }
    return ('C000{0}' -f $Numero)
}

function Save-OsNumero {
    param([int]$Numero)
    try { Set-Content -Path $script:osArquivo -Value $Numero -Encoding UTF8 } catch {}
}

function Set-OsNumeroAtual {
    param([int]$Numero)
    if ($Numero -lt 1) { return }
    $script:osNumero = $Numero
    Save-OsNumero -Numero $script:osNumero
}

function Get-LaunchVolumeRoot {
    param([string]$Path)
    $full = try { [System.IO.Path]::GetFullPath($Path) } catch { $Path }
    if ($IsMacOS -and $full -match '^/Volumes/[^/]+') { return $matches[0] }
    $root = [System.IO.Path]::GetPathRoot($full)
    if ($root) { return $root }
    return $script:baseDir
}

function Get-RegistroBaseDir {
    if ($script:registroBaseDir -and $script:registroBaseDir.Trim() -ne '') { return $script:registroBaseDir }

    try {
        $volumeRoot = Get-LaunchVolumeRoot -Path $script:baseDir
        if ($volumeRoot -and $volumeRoot.Trim() -ne '') {
            $dirPortatil = Join-Path $volumeRoot 'CAIJ-Registros'
            if (-not (Test-Path $dirPortatil)) { New-Item -ItemType Directory -Path $dirPortatil -Force | Out-Null }
            $teste = Join-Path $dirPortatil '.write-test'
            Set-Content -Path $teste -Value 'ok' -Encoding ASCII -ErrorAction Stop
            Remove-Item -LiteralPath $teste -Force -ErrorAction SilentlyContinue
            $script:registroBaseDir = $dirPortatil
            return $script:registroBaseDir
        }
    } catch {}

    try {
        if (-not (Test-Path $script:registroBaseDirFallback)) {
            New-Item -ItemType Directory -Path $script:registroBaseDirFallback -Force | Out-Null
        }
        $script:registroBaseDir = $script:registroBaseDirFallback
    } catch {
        $script:registroBaseDir = $script:baseDir
    }
    return $script:registroBaseDir
}

function Get-FirstValue {
    param(
        [object]$Object,
        [string[]]$Names
    )
    foreach ($name in $Names) {
        try {
            $prop = $Object.PSObject.Properties[$name]
            if ($prop -and $null -ne $prop.Value -and [string]$prop.Value -ne '') {
                return [string]$prop.Value
            }
        } catch {}
    }
    return ''
}

function ConvertTo-CaijStorageSize {
    param([string]$SizeText)
    if (-not $SizeText) { return '' }
    $t = $SizeText.Trim() -replace ',', '.'
    if ($t -match '([0-9]+(?:\.[0-9]+)?)\s*(TB|GB)') {
        $value = [double]::Parse($matches[1], [System.Globalization.CultureInfo]::InvariantCulture)
        $unit = $matches[2].ToUpperInvariant()
        if ($unit -eq 'TB') {
            if ($value -ge 0.9 -and $value -le 1.1) { return '1TB' }
            return ('{0}TB' -f ([math]::Round($value, 1).ToString('0.#', [System.Globalization.CultureInfo]::InvariantCulture)))
        }
        $gbRound = [math]::Round($value)
        if     ($gbRound -ge 110 -and $gbRound -le 130)  { return '128GB' }
        elseif ($gbRound -ge 220 -and $gbRound -le 260)  { return '256GB' }
        elseif ($gbRound -ge 460 -and $gbRound -le 520)  { return '512GB' }
        elseif ($gbRound -ge 900 -and $gbRound -le 1050) { return '1TB' }
        elseif ($gbRound -ge 1800 -and $gbRound -le 2100){ return '2TB' }
        return ('{0}GB' -f $gbRound)
    }
    return $t
}

function ConvertFrom-MacSystemProfilerJson {
    param([Parameter(Mandatory=$true)][string]$JsonText)

    $json = $JsonText | ConvertFrom-Json -ErrorAction Stop
    $hw = $json.SPHardwareDataType | Where-Object { $_ } | Select-Object -First 1
    $disp = $json.SPDisplaysDataType | Where-Object { $_ } | Select-Object -First 1
    $store = $json.SPStorageDataType | Where-Object { $_ } | Select-Object -First 1
    $power = $json.SPPowerDataType | Where-Object { $_ } | Select-Object -First 1

    $machineName = Get-FirstValue $hw @('machine_name')
    $machineModel = Get-FirstValue $hw @('machine_model', 'platform_UUID')
    $serial = Get-FirstValue $hw @('serial_number', 'serial_number_system')
    $chip = Get-FirstValue $hw @('chip_type', 'processor_name')
    if (-not $chip) { $chip = 'N/A' }
    $cores = Get-FirstValue $hw @('total_number_cores', 'number_cores')
    $memory = Get-FirstValue $hw @('physical_memory')

    $info = [ordered]@{}
    $info.Modelo = if ($machineName -and $machineModel) { "Apple $machineName ($machineModel)" } elseif ($machineName) { "Apple $machineName" } else { 'Apple MacBook' }
    $info.Serial = if ($serial) { $serial.Trim() } else { 'N/A' }
    $info.CPU = $chip.Trim()
    $info.Nucleos = if ($cores -match '\d+') { "$($matches[0]) nucleos" } else { 'N/A' }
    $info.ClockMax = 'N/A'

    if ($memory -match '(?i)(\d+)\s*GB') {
        $info.RAM = "$($matches[1])GB Unificada"
        $info.RAMMods = "$($matches[1])GB (Unificada)"
    } elseif ($memory) {
        $info.RAM = $memory.Trim()
        $info.RAMMods = $memory.Trim()
    } else {
        $info.RAM = 'N/A'
        $info.RAMMods = 'N/A'
    }

    $gpuName = Get-FirstValue $disp @('sppci_model', '_name')
    if (-not $gpuName -and $chip -match '(?i)Apple') { $gpuName = $chip }
    $info.GPU = if ($gpuName) { "$(($gpuName -replace '\s+', ' ').Trim()) (Integrada)" } else { 'Nao identificada' }

    $drivers = @()
    try { $drivers = @($disp.spdisplays_ndrvs | Where-Object { $_ }) } catch {}
    $mainDisplay = $drivers | Where-Object { $_.spdisplays_resolution } | Select-Object -First 1
    $resolution = Get-FirstValue $mainDisplay @('spdisplays_resolution')
    $info.Tela = if ($resolution) { $resolution.Trim() } else { 'Nao detectada' }

    $storageName = Get-FirstValue $store @('_name', 'device_name')
    $storageSize = ConvertTo-CaijStorageSize (Get-FirstValue $store @('size', 'capacity'))
    $physical = $null
    try { $physical = $store.physical_drive } catch {}
    $deviceName = Get-FirstValue $physical @('device_name', 'media_name')
    $mediaType = Get-FirstValue $physical @('media_type', 'medium_type')
    if (-not $mediaType) { $mediaType = 'SSD' }
    if (-not $deviceName) { $deviceName = $storageName }
    if ($storageSize) { $info.Discos = "$storageSize $mediaType - $deviceName".Trim() } else { $info.Discos = 'N/A' }

    $health = ''
    $capacity = ''
    try { $health = [string]$power.sppower_battery_health_info.sppower_battery_health } catch {}
    try { $capacity = [string]$power.sppower_battery_charge_info.sppower_battery_max_capacity } catch {}
    if ($capacity -match '\d+') {
        $info.BatSaude = if ($health) { "$($matches[0])% ($health)" } else { "$($matches[0])%" }
    } else {
        $info.BatSaude = if ($health) { $health } else { 'N/A' }
    }

    return [pscustomobject]$info
}

function Invoke-SystemProfilerJson {
    $args = @('SPHardwareDataType', 'SPDisplaysDataType', 'SPStorageDataType', 'SPPowerDataType', '-json')
    $jsonText = & system_profiler @args 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $jsonText) {
        throw 'Falha ao executar system_profiler no macOS.'
    }
    return ($jsonText -join [Environment]::NewLine)
}

function Get-MacNotebookInfo {
    try {
        return ConvertFrom-MacSystemProfilerJson -JsonText (Invoke-SystemProfilerJson)
    } catch {
        Write-Host "Nao foi possivel coletar todos os dados automaticamente: $($_.Exception.Message)" -ForegroundColor Yellow
        return [pscustomobject][ordered]@{
            Modelo = 'Apple MacBook'
            Serial = 'N/A'
            CPU = 'N/A'
            Nucleos = 'N/A'
            ClockMax = 'N/A'
            RAM = 'N/A'
            RAMMods = 'N/A'
            GPU = 'Nao identificada'
            Tela = 'N/A'
            Discos = 'N/A'
            BatSaude = 'N/A'
        }
    }
}

function Get-IntelCpuShort {
    param([string]$Cpu)
    $t = if ($Cpu) { [string]$Cpu.Trim() } else { '' }
    if ($t -match '(?i)\b(i[3579])(?:[- ]?)(\d{4,5})') {
        $prefix = $matches[1].ToUpper()
        $modelo = [string]$matches[2]
        $gen = $null
        if ($modelo.Length -ge 4) {
            $primeirosDois = [int]$modelo.Substring(0, 2)
            $primeiro = [int]$modelo.Substring(0, 1)
            if ($primeirosDois -ge 10 -and $primeirosDois -le 19) { $gen = $primeirosDois }
            elseif ($primeiro -ge 2 -and $primeiro -le 9) { $gen = $primeiro }
        }
        if ($gen) { return "$prefix $gen" }
        return $prefix
    }
    return $t
}

function Get-RamShort {
    param([string]$Ram)
    $t = if ($Ram) { [string]$Ram.Trim() } else { '' }
    if (-not $t -or $t -match '^(?i:N/?A)$') { return 'N/A' }
    $cap = if ($t -match '(?i)\b(\d+)\s*GB\b') { "$($matches[1])GB" } else { ($t -split '\s+')[0] }
    $tipo = if ($t -match '(?i)\b(LPDDR[345]|DDR[345]|Unificada)\b') { $matches[1] } else { '' }
    if ($tipo) {
        if ($tipo -match '^(?i:unificada)$') { return "$cap Unificada" }
        return "$cap $($tipo.ToUpper())"
    }
    return $cap
}

function Get-DiskShort {
    param([string]$Disco)
    $pd = if ($Disco) { $Disco.Trim() } else { '' }
    if (-not $pd) { return 'N/A' }
    if ($pd -match '(?i)\b(931|1000|1024)GB\b|1TB') { return '1TB SSD' }
    if ($pd -match '(?i)\b(476|480|494|500|512)GB\b') { return '512GB SSD' }
    if ($pd -match '(?i)\b(238|240|250|256)GB\b') { return '256GB SSD' }
    if ($pd -match '(?i)\b(119|120|128)GB\b') { return '128GB SSD' }
    if ($pd -match '^(\d+GB)\s+(SSD|HDD)') { return "$($matches[1]) $($matches[2])" }
    return $pd.Substring(0, [math]::Min($pd.Length, 18))
}

function Get-GpuShort {
    param([string]$Gpu)
    $gpuCurta = if ($Gpu) { $Gpu.Trim() } else { '' }
    if ($gpuCurta -eq '' -or $gpuCurta -match '^(?i:N/?A|Nao identificada|Não identificada)$') { return '' }
    if ($gpuCurta -match '(?i)Apple\s+(M[0-9][^\(]*)') { return "Apple $($matches[1].Trim())" }
    if ($gpuCurta -match '(?i)Iris\s*Xe') { return 'Intel Iris Xe' }
    if ($gpuCurta -match '(?i)UHD') { return 'Intel UHD' }
    if ($gpuCurta.Length -gt 28) { return $gpuCurta.Substring(0, 28) }
    return $gpuCurta
}

function New-CaijPrintPayload {
    param(
        [Parameter(Mandatory=$true)]$Info,
        [int]$OsNumero,
        [string]$Grade = 'A',
        [string]$Obs = '',
        [switch]$IncludeOs,
        [switch]$Manual
    )
    $gpu = Get-GpuShort $Info.GPU
    return [ordered]@{
        os = if ($IncludeOs) { $OsNumero } else { $null }
        modelo = $Info.Modelo
        serial = if ($Info.Serial -and $Info.Serial.Trim() -ne '') { $Info.Serial } else { 'XXXXXX' }
        cpu = Get-IntelCpuShort $Info.CPU
        gpu = if ($gpu) { $gpu } else { $null }
        ram = Get-RamShort $Info.RAM
        ramMods = Get-RamShort $Info.RAM
        disco = Get-DiskShort (($Info.Discos -split $NL) | Select-Object -First 1)
        modoManual = [bool]$Manual
        bateria = $Info.BatSaude
        grade = if ($Grade) { $Grade } else { 'A' }
        obs = if ($Obs) { $Obs } else { '' }
    }
}

function Get-ServidorCandidates {
    $portaServidor = 9100
    $candidatos = New-Object System.Collections.Generic.List[string]
    $cfgPath = Join-Path $script:baseDir 'caij_servidor_url.txt'

    if (Test-Path $cfgPath) {
        try {
            $cfg = (Get-Content -Path $cfgPath -Raw -ErrorAction Stop).Trim()
            if ($cfg) {
                if ($cfg -match '^https?://') { [void]$candidatos.Add($cfg.TrimEnd('/')) }
                else { [void]$candidatos.Add(('http://{0}:{1}' -f $cfg.Trim(), $portaServidor)) }
            }
        } catch {}
    }

    if ($env:CAIJ_SERVIDOR_URL) { [void]$candidatos.Add($env:CAIJ_SERVIDOR_URL.TrimEnd('/')) }
    if ($env:CAIJ_SERVIDOR_IP)  { [void]$candidatos.Add(('http://{0}:{1}' -f $env:CAIJ_SERVIDOR_IP.Trim(), $portaServidor)) }
    [void]$candidatos.Add(('http://{0}:{1}' -f '192.168.15.54', $portaServidor))

    if ($IsMacOS) {
        try {
            $ifconfig = & ifconfig 2>$null
            foreach ($line in $ifconfig) {
                if ($line -match 'inet\s+(\d{1,3}\.\d{1,3}\.\d{1,3})\.\d{1,3}\b' -and $matches[1] -ne '127.0.0') {
                    [void]$candidatos.Add(('http://{0}.54:{1}' -f $matches[1], $portaServidor))
                }
            }
        } catch {}
    }

    return @($candidatos | Where-Object { $_ } | Select-Object -Unique)
}

function Test-ServidorUrl {
    param(
        [string]$BaseUrl,
        [int]$TimeoutSec = 2
    )
    try {
        $resp = Invoke-RestMethod -Uri ('{0}/status' -f $BaseUrl.TrimEnd('/')) -Method Get -TimeoutSec $TimeoutSec -ErrorAction Stop
        return ($resp -and [string]$resp.status -eq 'ok')
    } catch {
        return $false
    }
}

function Get-ServidorBaseUrl {
    $cfgPath = Join-Path $script:baseDir 'caij_servidor_url.txt'
    if ($script:servidorBaseUrlCache -and (Test-ServidorUrl -BaseUrl $script:servidorBaseUrlCache -TimeoutSec 1)) {
        return $script:servidorBaseUrlCache
    }

    foreach ($candidate in (Get-ServidorCandidates)) {
        if (Test-ServidorUrl -BaseUrl $candidate -TimeoutSec 2) {
            $script:servidorBaseUrlCache = $candidate.TrimEnd('/')
            try { Set-Content -Path $cfgPath -Value $script:servidorBaseUrlCache -Encoding UTF8 } catch {}
            return $script:servidorBaseUrlCache
        }
    }

    $script:servidorBaseUrlCache = 'http://192.168.15.54:9100'
    return $script:servidorBaseUrlCache
}

function Invoke-CaijServer {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [ValidateSet('GET','POST')][string]$Method = 'GET',
        [string]$Body = $null,
        [int]$TimeoutSec = 12,
        [int]$Retries = 2
    )
    $lastErr = $null
    for ($i = 1; $i -le $Retries; $i++) {
        try {
            $baseUrl = Get-ServidorBaseUrl
            $uri = '{0}{1}' -f $baseUrl, $Path
            if ($Method -eq 'POST') {
                return Invoke-RestMethod -Uri $uri -Method Post -Body $Body -ContentType 'application/json; charset=utf-8' -TimeoutSec $TimeoutSec -ErrorAction Stop
            }
            return Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec $TimeoutSec -ErrorAction Stop
        } catch {
            $lastErr = $_
            $script:servidorBaseUrlCache = $null
            if ($i -lt $Retries) { Start-Sleep -Milliseconds (350 * $i) }
        }
    }
    if ($lastErr) { throw $lastErr }
    throw "Falha ao acessar servidor CAIJ em $Path"
}

function Sync-OsFromAltertag {
    param([switch]$Silent)
    try {
        $respOs = Invoke-CaijServer -Path '/status-os' -Method GET -TimeoutSec 12 -Retries 3
        if ($respOs -and [string]$respOs.status -eq 'ok' -and $respOs.proximoDisponivel) {
            Set-OsNumeroAtual -Numero ([int]$respOs.proximoDisponivel)
            $script:ultimaSincronizacaoOs = Get-Date -Format 'dd/MM HH:mm'
            if (-not $Silent) { Write-Host "OS sincronizada: $(Format-OsCodigo -Numero $script:osNumero)" -ForegroundColor Green }
            return $true
        }
    } catch {
        if (-not $Silent) { Write-Host "Nao foi possivel sincronizar OS: $($_.Exception.Message)" -ForegroundColor Yellow }
    }
    return $false
}

function Add-HistoricoNotebook {
    param(
        [Parameter(Mandatory=$true)]$Info,
        [string]$Acao,
        [string]$Status,
        [string]$Mensagem,
        [string]$Grade,
        [string]$Obs,
        [string]$SerialEtiqueta = '',
        [string]$ModeloEtiqueta = ''
    )
    $registro = [ordered]@{
        dataHora = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        acao = $Acao
        status = $Status
        mensagem = $Mensagem
        os = (Format-OsCodigo -Numero $script:osNumero)
        osNumero = $script:osNumero
        serial = $Info.Serial
        modelo = $Info.Modelo
        cpu = $Info.CPU
        ram = $Info.RAM
        disco = (($Info.Discos -split $NL) | Where-Object { $_.Trim() -ne '' } | Select-Object -First 1)
        gpu = $Info.GPU
        bateria = $Info.BatSaude
        grade = $Grade
        obs = $Obs
        servidor = $script:ultimoStatusServidor
        osSincronizadaEm = $script:ultimaSincronizacaoOs
    }
    try {
        $arr = @()
        if (Test-Path $script:historicoArquivo) {
            $raw = Get-Content -Path $script:historicoArquivo -Raw -ErrorAction Stop
            if ($raw -and $raw.Trim()) { $arr = @($raw | ConvertFrom-Json -ErrorAction Stop) }
        }
        $arr = @($registro) + $arr
        if ($arr.Count -gt 500) { $arr = $arr | Select-Object -First 500 }
        $arr | ConvertTo-Json -Depth 6 | Set-Content -Path $script:historicoArquivo -Encoding UTF8
    } catch {}

    try {
        $baseLog = Get-RegistroBaseDir
        if (-not (Test-Path $baseLog)) { New-Item -ItemType Directory -Path $baseLog -Force | Out-Null }
        $logArquivo = Join-Path $baseLog ("impressao-" + (Get-Date -Format 'yyyy-MM-dd') + ".log")
        $hostName = try { (& hostname 2>$null | Select-Object -First 1) } catch { $env:COMPUTERNAME }
        $linhaLog = [ordered]@{
            dataHora = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
            os = (Format-OsCodigo -Numero $script:osNumero)
            osNumero = $script:osNumero
            status = $Status
            acao = $Acao
            mensagem = $Mensagem
            serial = if ($SerialEtiqueta -and $SerialEtiqueta.Trim() -ne '') { $SerialEtiqueta } else { $Info.Serial }
            modelo = if ($ModeloEtiqueta -and $ModeloEtiqueta.Trim() -ne '') { $ModeloEtiqueta } else { $Info.Modelo }
            grade = $Grade
            observacoes = $Obs
            servidor = $script:ultimoStatusServidor
            osSincronizadaEm = $script:ultimaSincronizacaoOs
            computador = $hostName
            usuario = if ($env:USER) { $env:USER } else { $env:USERNAME }
        } | ConvertTo-Json -Compress

        Add-Content -Path $logArquivo -Value $linhaLog -Encoding UTF8
    } catch {}
}

function Show-NotebookInfo {
    param([Parameter(Mandatory=$true)]$Info)
    Write-Host ''
    Write-Host '=============================================' -ForegroundColor Cyan
    Write-Host ' CAIJ INFORMATICA - INFO NOTEBOOK MAC' -ForegroundColor Cyan
    Write-Host '=============================================' -ForegroundColor Cyan
    Write-Host "OS:       $(Format-OsCodigo -Numero $script:osNumero)"
    Write-Host "Modelo:   $($Info.Modelo)"
    Write-Host "Serial:   $($Info.Serial)"
    Write-Host "CPU:      $($Info.CPU)"
    Write-Host "Nucleos:  $($Info.Nucleos)"
    Write-Host "RAM:      $($Info.RAM)"
    Write-Host "GPU:      $($Info.GPU)"
    Write-Host "Tela:     $($Info.Tela)"
    Write-Host "Disco:    $($Info.Discos)"
    Write-Host "Bateria:  $($Info.BatSaude)"
    Write-Host '=============================================' -ForegroundColor Cyan
}

function Edit-NotebookInfoManual {
    param([Parameter(Mandatory=$true)]$Info)
    Write-Host ''
    Write-Host 'Edicao manual: Enter mantem o valor atual.' -ForegroundColor Yellow
    foreach ($field in @('Modelo','Serial','CPU','RAM','GPU','Discos','BatSaude')) {
        $current = [string]$Info.$field
        $value = Read-Host "$field [$current]"
        if ($value -and $value.Trim() -ne '') { $Info.$field = $value.Trim() }
    }
    if (-not $Info.Serial -or $Info.Serial.Trim() -eq '') { $Info.Serial = 'XXXXXX' }
    return $Info
}

function Send-CaijPrint {
    param(
        [Parameter(Mandatory=$true)]$Info,
        [string]$Grade,
        [string]$Obs,
        [switch]$IncludeOs,
        [switch]$Manual
    )

    if ($IncludeOs) {
        try {
            $respReserva = Invoke-CaijServer -Path '/proxima-os' -Method POST -Body '{}' -TimeoutSec 12 -Retries 3
            if ($respReserva -and [string]$respReserva.status -eq 'ok' -and $respReserva.osNumero) {
                Set-OsNumeroAtual -Numero ([int]$respReserva.osNumero)
                Write-Host "OS reservada: $(Format-OsCodigo -Numero $script:osNumero)" -ForegroundColor Green
            }
        } catch {
            Write-Host 'Falha ao reservar OS no servidor; usando OS local.' -ForegroundColor Yellow
        }
    }

    $payload = New-CaijPrintPayload -Info $Info -OsNumero $script:osNumero -Grade $Grade -Obs $Obs -IncludeOs:$IncludeOs -Manual:$Manual
    $body = $payload | ConvertTo-Json -Compress
    try {
        Invoke-CaijServer -Path '/imprimir' -Method POST -Body $body -TimeoutSec 20 -Retries 3 | Out-Null
        $script:ultimoStatusServidor = 'online'
        Add-HistoricoNotebook -Info $Info -Acao 'impressao' -Status 'ok' -Mensagem 'Etiqueta enviada com sucesso' -Grade $payload.grade -Obs $payload.obs -SerialEtiqueta $payload.serial -ModeloEtiqueta $payload.modelo
        Write-Host "Etiqueta enviada | historico salvo | OS $(Format-OsCodigo -Numero $script:osNumero)" -ForegroundColor Green
        if ($IncludeOs) { Sync-OsFromAltertag -Silent | Out-Null }
        return $true
    } catch {
        $script:ultimoStatusServidor = 'offline'
        Add-HistoricoNotebook -Info $Info -Acao 'impressao' -Status 'erro' -Mensagem $_.Exception.Message -Grade $payload.grade -Obs $payload.obs -SerialEtiqueta $payload.serial -ModeloEtiqueta $payload.modelo
        Write-Host "Falha ao imprimir: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Start-InfoNotebookMac {
    if (-not $IsMacOS) {
        Write-Host 'Aviso: esta versao foi feita para macOS. Os testes podem rodar no Windows, mas a coleta automatica usa system_profiler.' -ForegroundColor Yellow
    }

    $info = Get-MacNotebookInfo
    Sync-OsFromAltertag -Silent | Out-Null

    while ($true) {
        Show-NotebookInfo -Info $info
        Write-Host ''
        Write-Host '[1] Imprimir etiqueta via rede'
        Write-Host '[2] Editar dados manualmente'
        Write-Host '[3] Definir OS manual'
        Write-Host '[4] Sincronizar OS com servidor'
        Write-Host '[5] Recoletar dados do MacBook'
        Write-Host '[0] Sair'
        $op = Read-Host 'Opcao'

        switch ($op) {
            '1' {
                $grade = Read-Host 'Grade (A/B/C/RMA) [A]'
                if (-not $grade) { $grade = 'A' }
                $obs = Read-Host 'Observacoes para etiqueta'
                $inc = Read-Host 'Incluir OS na etiqueta? (S/n)'
                $includeOs = ($inc -notmatch '^(?i:n|nao|não)$')
                Write-Host ''
                Write-Host 'Previa da etiqueta:' -ForegroundColor Cyan
                $preview = New-CaijPrintPayload -Info $info -OsNumero $script:osNumero -Grade $grade -Obs $obs -IncludeOs:$includeOs -Manual:$false
                $preview.GetEnumerator() | ForEach-Object { Write-Host ("{0}: {1}" -f $_.Key, $_.Value) }
                $confirm = Read-Host 'Confirmar impressao? (S/n)'
                if ($confirm -notmatch '^(?i:n|nao|não)$') {
                    Send-CaijPrint -Info $info -Grade $grade -Obs $obs -IncludeOs:$includeOs -Manual:$false | Out-Null
                }
            }
            '2' { $info = Edit-NotebookInfoManual -Info $info }
            '3' {
                $entrada = Read-Host 'Numero da OS'
                if ($entrada -match '^\d{2,8}$') { Set-OsNumeroAtual -Numero ([int]$entrada) }
                else { Write-Host 'Numero de OS invalido.' -ForegroundColor Yellow }
            }
            '4' { Sync-OsFromAltertag | Out-Null }
            '5' { $info = Get-MacNotebookInfo }
            '0' { return }
            default { Write-Host 'Opcao invalida.' -ForegroundColor Yellow }
        }
    }
}

if ($Library) { return }
Start-InfoNotebookMac
