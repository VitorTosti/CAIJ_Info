param()

$ErrorActionPreference = 'Stop'

# Preserva o pre-check do InfoNotebook classico antes de abrir a interface web.
# Em equipamentos que nao sao Lenovo, ou cuja tecla ja esta corrigida, a
# verificacao termina somente com leituras rapidas do Registro.
$lenovoPreflightPath = Join-Path $PSScriptRoot 'PrepararLenovo.ps1'
$runLenovoPreflight = $true
try {
    $manufacturerFast = ([string](Get-ItemPropertyValue `
        -LiteralPath 'HKLM:\HARDWARE\DESCRIPTION\System\BIOS' `
        -Name 'SystemManufacturer' `
        -ErrorAction Stop)).Trim()
    if ($manufacturerFast -and $manufacturerFast -notmatch '(?i)Lenovo') {
        $runLenovoPreflight = $false
    } elseif ($manufacturerFast -match '(?i)Lenovo') {
        $desiredLenovoMap = [byte[]](
            0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00,
            0x02,0x00,0x00,0x00, 0x73,0x00,0x1D,0xE0,
            0x00,0x00,0x00,0x00
        )
        $currentLenovoMap = [byte[]](Get-ItemPropertyValue `
            -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout' `
            -Name 'Scancode Map' `
            -ErrorAction Stop)
        if ($currentLenovoMap.Length -eq $desiredLenovoMap.Length) {
            $mapMatches = $true
            for ($mapIndex = 0; $mapIndex -lt $desiredLenovoMap.Length; $mapIndex++) {
                if ($currentLenovoMap[$mapIndex] -ne $desiredLenovoMap[$mapIndex]) {
                    $mapMatches = $false
                    break
                }
            }
            if ($mapMatches) { $runLenovoPreflight = $false }
        }
    }
} catch {
    # Sem uma leitura confiavel, deixa PrepararLenovo fazer a verificacao completa.
    $runLenovoPreflight = $true
}

if ($runLenovoPreflight) {
    if (-not (Test-Path -LiteralPath $lenovoPreflightPath -PathType Leaf)) {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show(
            'O verificador da tecla de interrogacao Lenovo nao foi encontrado. O InfoNotebook nao sera aberto.',
            'InfoNotebook - Verificacao Lenovo',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        exit 24
    }
    try {
        $appRootPreflight = Split-Path -Parent $PSScriptRoot
        $preflightArgs = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -AppRoot "{1}"' -f `
            $lenovoPreflightPath.Replace('"', '""'), $appRootPreflight.Replace('"', '""')
        $preflightProcess = Start-Process powershell.exe -ArgumentList $preflightArgs -WindowStyle Hidden -Wait -PassThru
        if ($preflightProcess.ExitCode -ne 0) { exit $preflightProcess.ExitCode }
    } catch {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show(
            "Nao foi possivel verificar a correcao do teclado Lenovo.`n`n$($_.Exception.Message)",
            'InfoNotebook - Verificacao Lenovo',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        exit 24
    }
}

function Get-FirstCimInstance {
    param([string]$ClassName, [string]$Namespace = 'root\cimv2')
    try { return Get-CimInstance -Namespace $Namespace -ClassName $ClassName -ErrorAction Stop | Select-Object -First 1 } catch { return $null }
}

function Get-CaijServer {
    $savedPath = Join-Path $PSScriptRoot 'caij_servidor_url.txt'
    $saved = if (Test-Path -LiteralPath $savedPath) { ([string](Get-Content -LiteralPath $savedPath -Raw)).Trim().TrimEnd('/') } else { '' }
    $candidates = @($saved, 'http://INFOCAIJ:9100', 'http://192.168.15.11:9100') | Where-Object { $_ } | Select-Object -Unique
    foreach ($candidate in $candidates) {
        try {
            $status = Invoke-RestMethod -Uri "$candidate/status" -TimeoutSec 2
            if ([string]$status.status -eq 'ok') { return $candidate }
        } catch {}
    }
    throw 'Servidor CAIJ indisponivel. Confirme a rede e tente novamente.'
}

function ConvertTo-MarketedStorage {
    param([double]$SizeGb, [string]$Kind = 'SSD')
    if ($SizeGb -lt 1) { return 'N/A' }
    $sizes = @(32, 64, 128, 256, 512, 1024, 2048)
    $marketed = $sizes | Sort-Object { [math]::Abs([double]$_ - $SizeGb) } | Select-Object -First 1
    $capacity = if ([int]$marketed -ge 1024) { "$([int]$marketed / 1024)TB" } else { "$marketed`GB" }
    return "$capacity $Kind".Trim()
}

function Invoke-CaijUsbTool {
    param([string]$FilePath, [string]$Arguments, [int]$TimeoutMs = 10000)
    if (-not (Test-Path -LiteralPath $FilePath)) { throw 'Leitor USB do InfoNotebook não foi encontrado.' }
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = $Arguments
    $startInfo.WorkingDirectory = Split-Path -Parent $FilePath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw 'Não foi possível iniciar a leitura USB.' }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutMs)) { try { $process.Kill() } catch {}; throw 'A leitura USB excedeu o tempo limite.' }
        $stdout = [string]$stdoutTask.Result
        $stderr = [string]$stderrTask.Result
        if ($process.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($stdout)) { throw $(if ($stderr.Trim()) { $stderr.Trim() } else { 'Aparelho indisponível para leitura USB.' }) }
        return $stdout
    } finally { $process.Dispose() }
}

function Get-PlistInteger {
    param([xml]$Xml, [string]$Key)
    $keyNode = @($Xml.SelectNodes("//key[text()='$Key']")) | Select-Object -First 1
    if (-not $keyNode) { return 0 }
    $valueNode = $keyNode.NextSibling
    while ($valueNode -and $valueNode.NodeType -ne [System.Xml.XmlNodeType]::Element) { $valueNode = $valueNode.NextSibling }
    [int64]$parsed = 0
    if ($valueNode -and [int64]::TryParse($valueNode.InnerText.Trim(), [ref]$parsed)) { return $parsed }
    return 0
}

function Get-Windows3uToolsInfo {
    $installDirs = @('C:\Program Files\3uTools9','C:\Program Files (x86)\3uTools9','C:\Program Files\3uTools','C:\Program Files (x86)\3uTools') |
        Where-Object { Test-Path -LiteralPath $_ }
    $infoExe = Join-Path $PSScriptRoot 'tools\libimobiledevice\ideviceinfo.exe'
    $currentSerial = ([string](Invoke-CaijUsbTool -FilePath $infoExe -Arguments '-k SerialNumber' -TimeoutMs 8000)).Trim()
    if (-not $currentSerial) { throw 'Nenhum iPhone ou iPad conectado foi identificado. Reconecte o cabo e tente novamente.' }

    $infoFiles = @(foreach ($installDir in $installDirs) {
        Get-ChildItem -LiteralPath (Join-Path $installDir 'cache') -Filter '*_info.txt' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Length -gt 0 -and $_.BaseName -ne '_info' }
    })
    $infoFile = $infoFiles | Where-Object { $_.BaseName -ieq "${currentSerial}_info" } | Select-Object -First 1
    if (-not $infoFile) {
        throw "O aparelho conectado ($currentSerial) ainda não foi atualizado no 3uTools. Abra as informações do aparelho e tente novamente."
    }

    $values = @{}
    foreach ($line in Get-Content -LiteralPath $infoFile.FullName) {
        if ([string]$line -match '^\s*(\S+)\s{2,}(.+?)\s*$') { $values[$matches[1]] = $matches[2].Trim() }
    }
    $productType = [string]$values['ProductType']
    $modelName = ''
    foreach ($installDir in $installDirs) {
        $deviceTable = Join-Path $installDir 'cache\devices_table\devices_table.txt'
        if (-not $productType -or -not (Test-Path -LiteralPath $deviceTable)) { continue }
        $modelLine = Get-Content -LiteralPath $deviceTable -ErrorAction SilentlyContinue |
            Where-Object { $_ -match '"ProductName"' -and $_ -match ('"ProductType"\s*:\s*"' + [regex]::Escape($productType) + '"') } |
            Select-Object -First 1
        if ($modelLine -and $modelLine -match '"ProductName"\s*:\s*"([^"]+)"') { $modelName = $matches[1].Trim(); break }
    }
    if (-not $modelName) { $modelName = if ($productType) { $productType } else { 'iPhone' } }

    $serial = ([string]$values['SerialNumber']).Trim()
    $imei = (([string]$values['InternationalMobileEquipmentIdentity']) -replace '[^0-9]', '')
    $udid = ([string]$values['UniqueDeviceID']).Trim()
    if (-not $serial -or $serial -ine $currentSerial -or $imei.Length -ne 15) { throw 'Atualize a tela Informações do aparelho no 3uTools e tente novamente.' }

    $storage = ''
    try {
        $storageRaw = Invoke-CaijUsbTool -FilePath $infoExe -Arguments ('-u "{0}" -q com.apple.disk_usage -k TotalDataCapacity' -f ($udid -replace '"',''))
        $bytes = @([regex]::Matches($storageRaw, '(?<!\d)\d{8,15}(?!\d)') | ForEach-Object { [double]$_.Value } | Sort-Object -Descending) | Select-Object -First 1
        if ($bytes -gt 8GB) { $storage = (ConvertTo-MarketedStorage -SizeGb ([double]$bytes / 1GB) -Kind '').Trim() }
    } catch {}

    $batteryText = ''
    $cycles = 0
    try {
        $diagExe = Join-Path $PSScriptRoot 'tools\libimobiledevice\idevicediagnostics.exe'
        [xml]$batteryXml = Invoke-CaijUsbTool -FilePath $diagExe -Arguments ('-u "{0}" ioregentry AppleSmartBattery' -f ($udid -replace '"',''))
        $nominal = Get-PlistInteger -Xml $batteryXml -Key 'NominalChargeCapacity'
        $design = Get-PlistInteger -Xml $batteryXml -Key 'DesignCapacity'
        $cycles = [int](Get-PlistInteger -Xml $batteryXml -Key 'CycleCount')
        if ($nominal -gt 0 -and $design -gt 0) { $batteryText = "$([math]::Min(100,[math]::Round(100 * $nominal / $design)))%" }
    } catch {}

    $ramMap = @{
        'iPhone12,1'=4;'iPhone12,3'=4;'iPhone12,5'=4;'iPhone12,8'=3
        'iPhone13,1'=4;'iPhone13,2'=4;'iPhone13,3'=6;'iPhone13,4'=6
        'iPhone14,2'=6;'iPhone14,3'=6;'iPhone14,4'=4;'iPhone14,5'=4;'iPhone14,6'=4;'iPhone14,7'=6;'iPhone14,8'=6
        'iPhone15,2'=6;'iPhone15,3'=6;'iPhone15,4'=6;'iPhone15,5'=6
        'iPhone16,1'=8;'iPhone16,2'=8;'iPhone17,1'=8;'iPhone17,2'=8;'iPhone17,3'=8;'iPhone17,4'=8;'iPhone17,5'=8
        'iPad12,1'=3;'iPad12,2'=3;'iPad13,18'=4;'iPad13,19'=4;'iPad14,8'=8;'iPad14,9'=8
    }
    $ram = if ($ramMap.ContainsKey($productType)) { "$($ramMap[$productType])GB" } else { '' }
    return [ordered]@{ modelo=$modelName; productType=$productType; serial=$serial; imei=$imei; armazenamento=$storage; ram=$ram; bateria=$batteryText; ciclos=$cycles }
}

function Test-LocalClientDisconnect {
    param([Exception]$Exception)
    $current = $Exception
    while ($current) {
        if ($current -is [System.IO.IOException] -or
            $current -is [System.Net.Sockets.SocketException] -or
            $current -is [System.ObjectDisposedException]) {
            return $true
        }
        $current = $current.InnerException
    }
    return $false
}

function Send-LocalBytesResponse {
    param($Client, [int]$StatusCode, [byte[]]$Bytes, [string]$ContentType)
    $reason = if ($StatusCode -eq 200) { 'OK' } elseif ($StatusCode -eq 204) { 'No Content' } else { 'Error' }
    $header = "HTTP/1.1 $StatusCode $reason`r`nContent-Type: $ContentType`r`nContent-Length: $($Bytes.Length)`r`nAccess-Control-Allow-Origin: *`r`nAccess-Control-Allow-Methods: GET, POST, OPTIONS`r`nAccess-Control-Allow-Headers: Content-Type`r`nAccess-Control-Allow-Private-Network: true`r`nCache-Control: no-store`r`nConnection: close`r`n`r`n"
    try {
        $stream = $Client.GetStream()
        $headerBytes = [Text.Encoding]::ASCII.GetBytes($header)
        $stream.Write($headerBytes, 0, $headerBytes.Length)
        if ($Bytes.Length) { $stream.Write($Bytes, 0, $Bytes.Length) }
        $stream.Flush()
    } catch {
        if (-not (Test-LocalClientDisconnect -Exception $_.Exception)) { throw }
    }
}

function Send-LocalJsonResponse {
    param($Client, [int]$StatusCode, $Body)
    $json = $Body | ConvertTo-Json -Depth 8 -Compress
    Send-LocalBytesResponse -Client $Client -StatusCode $StatusCode -Bytes ([Text.Encoding]::UTF8.GetBytes($json)) -ContentType 'application/json; charset=utf-8'
}

function Send-LocalUiFile {
    param($Client, [string]$UiDirectory, [string]$RequestPath)
    $route = ($RequestPath -split '\?')[0]
    $files = @{
        '/' = @('index.html', 'text/html; charset=utf-8')
        '/index.html' = @('index.html', 'text/html; charset=utf-8')
        '/style.css' = @('style.css', 'text/css; charset=utf-8')
        '/app.js' = @('app.js', 'text/javascript; charset=utf-8')
        '/portable.js' = @('portable.js', 'text/javascript; charset=utf-8')
        '/runtime-loader.js' = @('runtime-loader.js', 'text/javascript; charset=utf-8')
        '/caij-runtime.js' = @('caij-runtime.js', 'text/javascript; charset=utf-8')
        '/logo.png' = @('..\caij-logo.png', 'image/png')
    }
    if (-not $files.ContainsKey($route)) { return $false }
    $entry = $files[$route]
    $path = Join-Path $UiDirectory $entry[0]
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
    Send-LocalBytesResponse -Client $Client -StatusCode 200 -Bytes ([IO.File]::ReadAllBytes($path)) -ContentType $entry[1]
    return $true
}

function Get-WindowsBatterySummary {
    $health = 0
    $cycles = 0

    try {
        $design = Get-FirstCimInstance 'BatteryStaticData' 'root\wmi'
        $full = Get-FirstCimInstance 'BatteryFullChargedCapacity' 'root\wmi'
        $cycleData = Get-FirstCimInstance 'BatteryCycleCount' 'root\wmi'
        if ($design.DesignedCapacity -and $full.FullChargedCapacity) {
            $health = [math]::Min(100, [math]::Round(100 * [double]$full.FullChargedCapacity / [double]$design.DesignedCapacity))
        }
        if ($cycleData.CycleCount) { $cycles = [int]$cycleData.CycleCount }
    } catch {}

    if ($health -le 0 -or $cycles -le 0) {
        $reportPath = Join-Path ([IO.Path]::GetTempPath()) ('caij-battery-' + [guid]::NewGuid().ToString('N') + '.xml')
        try {
            $powercfg = Join-Path $env:SystemRoot 'System32\powercfg.exe'
            & $powercfg /batteryreport /output $reportPath /xml 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
                [xml]$report = Get-Content -LiteralPath $reportPath -Raw
                $batteryNodes = @($report.SelectNodes("/*[local-name()='BatteryReport']/*[local-name()='Batteries']/*[local-name()='Battery']"))
                [double]$designTotal = 0
                [double]$fullTotal = 0
                $reportCycles = @()
                foreach ($batteryNode in $batteryNodes) {
                    $designNode = $batteryNode.SelectSingleNode("*[local-name()='DesignCapacity']")
                    $fullNode = $batteryNode.SelectSingleNode("*[local-name()='FullChargeCapacity']")
                    $cycleNode = $batteryNode.SelectSingleNode("*[local-name()='CycleCount']")
                    [double]$designValue = 0
                    [double]$fullValue = 0
                    [int]$cycleValue = 0
                    if ($designNode) { [void][double]::TryParse($designNode.InnerText, [ref]$designValue) }
                    if ($fullNode) { [void][double]::TryParse($fullNode.InnerText, [ref]$fullValue) }
                    if ($cycleNode) { [void][int]::TryParse($cycleNode.InnerText, [ref]$cycleValue) }
                    if ($designValue -gt 0 -and $fullValue -gt 0) {
                        $designTotal += $designValue
                        $fullTotal += $fullValue
                    }
                    if ($cycleValue -gt 0) { $reportCycles += $cycleValue }
                }
                if ($health -le 0 -and $designTotal -gt 0 -and $fullTotal -gt 0) {
                    $health = [math]::Min(100, [math]::Round(100 * $fullTotal / $designTotal))
                }
                if ($cycles -le 0 -and $reportCycles.Count -gt 0) {
                    $cycles = [int]($reportCycles | Measure-Object -Maximum).Maximum
                }
            }
        } catch {
        } finally {
            if (Test-Path -LiteralPath $reportPath) { Remove-Item -LiteralPath $reportPath -Force -ErrorAction SilentlyContinue }
        }
    }

    # Windows PowerShell 5 pode interpretar scripts UTF-8 sem BOM como ANSI.
    # Monte os textos acentuados em runtime para evitar caracteres corrompidos.
    $healthWord = [string]::Concat('sa', [char]0x00FA, 'de')
    $parts = @()
    if ($health -gt 0) { $parts += "$health% de $healthWord" }
    elseif ($cycles -gt 0) { $parts += ([string]::Concat('Sa', [char]0x00FA, 'de indispon', [char]0x00ED, 'vel')) }
    if ($cycles -gt 0) { $parts += "$cycles ciclos" }
    return ($parts -join ' | ')
}

function Get-WindowsDeviceInfo {
    $computer = Get-FirstCimInstance 'Win32_ComputerSystem'
    $computerProduct = Get-FirstCimInstance 'Win32_ComputerSystemProduct'
    $bios = Get-FirstCimInstance 'Win32_BIOS'
    $processor = Get-FirstCimInstance 'Win32_Processor'
    $disk = Get-FirstCimInstance 'Win32_DiskDrive'
    $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
        ForEach-Object { ([string]$_.Name).Trim() } |
        Where-Object { $_ -and $_ -notmatch '(?i)Microsoft Basic|Adaptador de Video Basico' } |
        Select-Object -Unique)

    $manufacturer = ([string]$computer.Manufacturer).Trim()
    if ($manufacturer -match '^(?i:lenovo)$') { $manufacturer = 'Lenovo' }
    $technicalModel = ([string]$computer.Model).Trim()
    $commercialModel = ([string]$computerProduct.Version).Trim()
    if (-not $commercialModel -or $commercialModel -match '^(?i:to be filled|system product|default string|none|n/?a)$') {
        $commercialModel = ([string](Get-ItemPropertyValue -LiteralPath 'HKLM:\HARDWARE\DESCRIPTION\System\BIOS' -Name 'SystemFamily' -ErrorAction SilentlyContinue)).Trim()
    }
    $model = if ($commercialModel -and $commercialModel -ne $technicalModel) { $commercialModel } else { $technicalModel }
    if ($manufacturer -and $model -and $model -notmatch [regex]::Escape($manufacturer)) { $model = "$manufacturer $model" }
    if (-not $model) { $model = 'Notebook Windows' }

    $ramGb = if ($computer.TotalPhysicalMemory) { [math]::Round([double]$computer.TotalPhysicalMemory / 1GB) } else { 0 }
    $diskGb = if ($disk.Size) { [double]$disk.Size / 1GB } else { 0 }
    $diskKind = if (([string]$disk.MediaType) -match '(?i)SSD|Solid') { 'SSD' } else { 'SSD' }

    $batteryText = Get-WindowsBatterySummary

    return [ordered]@{
        modelo = $model
        serial = if ($bios.SerialNumber) { ([string]$bios.SerialNumber).Trim() } else { 'N/A' }
        cpu = if ($processor.Name) { ([string]$processor.Name).Trim() } else { 'N/A' }
        gpu = if ($gpus.Count) { $gpus -join ' + ' } else { 'N/A' }
        ram = if ($ramGb -gt 0) { "${ramGb}GB" } else { 'N/A' }
        disco = ConvertTo-MarketedStorage -SizeGb $diskGb -Kind $diskKind
        bateria = if ($batteryText) { $batteryText } else { 'N/A' }
    }
}

try {
    $server = Get-CaijServer
    $localBridge = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $localBridge.Start()
    $localBridgePort = ([System.Net.IPEndPoint]$localBridge.LocalEndpoint).Port
    $versionPath = Join-Path $PSScriptRoot 'caij_versao_app.txt'
    $version = if (Test-Path -LiteralPath $versionPath) { ([string](Get-Content -LiteralPath $versionPath -Raw)).Trim() } else { 'preview' }
    $osPath = Join-Path $PSScriptRoot 'caij_os_counter.txt'
    $osDigits = if (Test-Path -LiteralPath $osPath) { ([string](Get-Content -LiteralPath $osPath -Raw)) -replace '\D', '' } else { '235' }
    if (-not $osDigits) { $osDigits = '235' }

    $runtime = [ordered]@{
        platform = 'windows'
        equipmentType = 'Notebook'
        info = Get-WindowsDeviceInfo
        osNumero = [int]$osDigits
        serverUrl = $server
        lastServerStatus = 'online'
        internetStatus = 'online'
        version = "$version-preview"
        localBridgeUrl = "http://127.0.0.1:$localBridgePort"
    }
    $json = $runtime | ConvertTo-Json -Depth 8 -Compress
    $token = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    $localUiDirectory = Join-Path $PSScriptRoot 'mac-ui'
    if (-not (Test-Path -LiteralPath (Join-Path $localUiDirectory 'index.html') -PathType Leaf)) {
        throw 'Arquivos da interface local nao foram encontrados.'
    }
    $url = "http://127.0.0.1:$localBridgePort/?windows-preview=1&v=$([uri]::EscapeDataString($version))#runtime=$token"

    $edgeCandidates = @(
        (Get-Command msedge.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1),
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique
    $edge = $edgeCandidates | Select-Object -First 1
    if (-not $edge) { throw 'Microsoft Edge nao foi encontrado neste computador.' }
    $previewProfile = Join-Path $env:LOCALAPPDATA "CAIJ\EdgeInfoNotebookPreview-$PID"

    $arguments = @(
        '--inprivate',
        '--new-window',
        '--start-maximized',
        '--no-first-run',
        '--disable-features=msEdgeFirstRunExperience',
        "--user-data-dir=$previewProfile",
        "--app=$url"
    )
    $edgeProcess = Start-Process -FilePath $edge -ArgumentList $arguments -PassThru
    while (-not $edgeProcess.HasExited) {
        if (-not $localBridge.Pending()) { Start-Sleep -Milliseconds 100; $edgeProcess.Refresh(); continue }
        $client = $localBridge.AcceptTcpClient()
        try {
            $reader = New-Object IO.StreamReader($client.GetStream(), [Text.Encoding]::ASCII, $false, 1024, $true)
            $requestLine = [string]$reader.ReadLine()
            while (($line = $reader.ReadLine()) -ne '') { if ($null -eq $line) { break } }
            if ($requestLine -match '^OPTIONS\s+') {
                Send-LocalJsonResponse -Client $client -StatusCode 204 -Body @{}
            } elseif ($requestLine -match '^POST\s+/3utools(?:\?|\s)') {
                try { Send-LocalJsonResponse -Client $client -StatusCode 200 -Body @{ ok=$true; device=(Get-Windows3uToolsInfo) } }
                catch { Send-LocalJsonResponse -Client $client -StatusCode 500 -Body @{ ok=$false; message=$_.Exception.Message } }
            } elseif ($requestLine -match '^GET\s+(\S+)\s+HTTP/') {
                if (-not (Send-LocalUiFile -Client $client -UiDirectory $localUiDirectory -RequestPath $Matches[1])) {
                    Send-LocalJsonResponse -Client $client -StatusCode 404 -Body @{ ok=$false; message='Arquivo local nao encontrado.' }
                }
            } else {
                Send-LocalJsonResponse -Client $client -StatusCode 404 -Body @{ ok=$false; message='Rota local não encontrada.' }
            }
        } catch {
            if (-not (Test-LocalClientDisconnect -Exception $_.Exception)) { throw }
        } finally {
            try { $client.Dispose() } catch {}
        }
        $edgeProcess.Refresh()
    }
    $localBridge.Stop()
} catch {
    try { if ($localBridge) { $localBridge.Stop() } } catch {}
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        $_.Exception.Message,
        'CAIJ - Previa da interface Windows',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    ) | Out-Null
    exit 1
}
