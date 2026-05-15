# ================================================
#  CAIJ INFORMATICA - INFO NOTEBOOK v4
# ================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$TELEGRAM_BOT_TOKEN = '8778529890:AAG97EZiatunvP1rbTGT28cY11gJYjxpCPs'
$TELEGRAM_CHAT_ID   = '-5056520058'
$NL = [Environment]::NewLine

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

# ================================================
# SPLASH SCREEN - aparece imediatamente
# ================================================
$splash = New-Object System.Windows.Forms.Form
$splash.Text            = 'Caij Informatica'
$splash.Size            = New-Object System.Drawing.Size(560, 360)
$splash.StartPosition   = 'CenterScreen'
$splash.BackColor       = [System.Drawing.Color]::FromArgb(6, 10, 18)
$splash.FormBorderStyle = 'None'
$splash.MaximizeBox     = $false
$splash.MinimizeBox     = $false
$splash.TopMost         = $true
$splash.DoubleBuffered  = $true

$splash.Add_Paint({
    param($sender, $e)
    $rect = New-Object System.Drawing.Rectangle(0, 0, $sender.ClientSize.Width, $sender.ClientSize.Height)
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $rect,
        [System.Drawing.Color]::FromArgb(8, 14, 24),
        [System.Drawing.Color]::FromArgb(3, 8, 14),
        [System.Drawing.Drawing2D.LinearGradientMode]::Vertical
    )
    $e.Graphics.FillRectangle($brush, $rect)
    $brush.Dispose()
})

$splashCard = New-Object System.Windows.Forms.Panel
$splashCard.BackColor = [System.Drawing.Color]::FromArgb(15, 24, 36)
$splashCard.Location  = New-Object System.Drawing.Point(20, 24)
$splashCard.Size      = New-Object System.Drawing.Size(520, 308)
$splashCard.BorderStyle = 'FixedSingle'
$splash.Controls.Add($splashCard)

$splashAccent = New-Object System.Windows.Forms.Panel
$splashAccent.BackColor = [System.Drawing.Color]::FromArgb(0, 166, 255)
$splashAccent.Location  = New-Object System.Drawing.Point(0, 0)
$splashAccent.Size      = New-Object System.Drawing.Size(4, 308)
$splashCard.Controls.Add($splashAccent)

$baseDir = Split-Path -Parent $PSCommandPath
$logoCandidates = @(
    'caij-logo.png','caij_logo.png','logo-caij.png','logo_caij.png','logo.png',
    'caij-logo.jpg','caij_logo.jpg','logo-caij.jpg','logo_caij.jpg','logo.jpg',
    'caij-logo.jpeg','caij_logo.jpeg','logo-caij.jpeg','logo_caij.jpeg','logo.jpeg',
    'caij-logo.bmp','caij_logo.bmp','logo-caij.bmp','logo_caij.bmp','logo.bmp'
)
$logoPath = $null
foreach ($cand in $logoCandidates) {
    $pathTry = Join-Path $baseDir $cand
    if (Test-Path $pathTry) {
        $logoPath = $pathTry
        break
    }
}
if (-not $logoPath) {
    try {
        $pickLogo = New-Object System.Windows.Forms.OpenFileDialog
        $pickLogo.Title = 'Selecionar logo da CAIJ'
        $pickLogo.Filter = 'Imagens (*.png;*.jpg;*.jpeg;*.bmp)|*.png;*.jpg;*.jpeg;*.bmp'
        $pickLogo.InitialDirectory = $baseDir
        $pickLogo.Multiselect = $false
        if ($pickLogo.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK -and (Test-Path $pickLogo.FileName)) {
            $destLogo = Join-Path $baseDir 'caij-logo.png'
            Copy-Item -Path $pickLogo.FileName -Destination $destLogo -Force
            if (Test-Path $destLogo) { $logoPath = $destLogo }
        }
    } catch {}
}
$splashLogoImg = New-Object System.Windows.Forms.PictureBox
$splashLogoImg.Location = New-Object System.Drawing.Point(120, 22)
$splashLogoImg.Size = New-Object System.Drawing.Size(280, 120)
$splashLogoImg.SizeMode = 'Zoom'
$splashLogoImg.BackColor = [System.Drawing.Color]::Transparent
$splashCard.Controls.Add($splashLogoImg)

$splashLogo = New-Object System.Windows.Forms.Label
$splashLogo.Text      = 'CAIJ'
$splashLogo.Font      = New-Object System.Drawing.Font('Segoe UI Semibold', 36, [System.Drawing.FontStyle]::Bold)
$splashLogo.ForeColor = [System.Drawing.Color]::FromArgb(236, 246, 255)
$splashLogo.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$splashLogo.Location  = New-Object System.Drawing.Point(120, 44)
$splashLogo.Size      = New-Object System.Drawing.Size(280, 66)
$splashCard.Controls.Add($splashLogo)
if (Test-Path $logoPath) {
    try {
        $splashLogoImg.Image = [System.Drawing.Image]::FromFile($logoPath)
        $splashLogo.Visible = $false
    } catch {}
}

$splashSub = New-Object System.Windows.Forms.Label
$splashSub.Text      = 'INFORMATICA'
$splashSub.Font      = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$splashSub.ForeColor = [System.Drawing.Color]::FromArgb(70, 184, 255)
$splashSub.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$splashSub.Location  = New-Object System.Drawing.Point(120, 118)
$splashSub.Size      = New-Object System.Drawing.Size(280, 20)
$splashCard.Controls.Add($splashSub)

$splashTagline = New-Object System.Windows.Forms.Label
$splashTagline.Text      = 'InfoNotebook - Diagnostico e Etiquetagem'
$splashTagline.Font      = New-Object System.Drawing.Font('Segoe UI', 9)
$splashTagline.ForeColor = [System.Drawing.Color]::FromArgb(146, 173, 198)
$splashTagline.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$splashTagline.Location  = New-Object System.Drawing.Point(54, 150)
$splashTagline.Size      = New-Object System.Drawing.Size(412, 18)
$splashCard.Controls.Add($splashTagline)

$splashSpinner = New-Object System.Windows.Forms.Label
$splashSpinner.Text      = '●'
$splashSpinner.Font      = New-Object System.Drawing.Font('Segoe UI Symbol', 13, [System.Drawing.FontStyle]::Bold)
$splashSpinner.ForeColor = [System.Drawing.Color]::FromArgb(0, 166, 255)
$splashSpinner.Location  = New-Object System.Drawing.Point(54, 196)
$splashSpinner.Size      = New-Object System.Drawing.Size(18, 20)
$splashCard.Controls.Add($splashSpinner)

$splashMsg = New-Object System.Windows.Forms.Label
$splashMsg.Text      = 'Coletando informacoes de hardware...'
$splashMsg.Font      = New-Object System.Drawing.Font('Segoe UI', 10)
$splashMsg.ForeColor = [System.Drawing.Color]::FromArgb(193, 215, 233)
$splashMsg.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$splashMsg.Location  = New-Object System.Drawing.Point(78, 196)
$splashMsg.Size      = New-Object System.Drawing.Size(388, 22)
$splashCard.Controls.Add($splashMsg)

$splashPercent = New-Object System.Windows.Forms.Label
$splashPercent.Text      = '0%'
$splashPercent.Font      = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$splashPercent.ForeColor = [System.Drawing.Color]::FromArgb(128, 204, 255)
$splashPercent.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$splashPercent.Location  = New-Object System.Drawing.Point(426, 232)
$splashPercent.Size      = New-Object System.Drawing.Size(54, 16)
$splashCard.Controls.Add($splashPercent)

$splashBarTrack = New-Object System.Windows.Forms.Panel
$splashBarTrack.BackColor = [System.Drawing.Color]::FromArgb(20, 36, 52)
$splashBarTrack.Location  = New-Object System.Drawing.Point(54, 234)
$splashBarTrack.Size      = New-Object System.Drawing.Size(366, 10)
$splashBarTrack.BorderStyle = 'FixedSingle'
$splashCard.Controls.Add($splashBarTrack)

$splashBar = New-Object System.Windows.Forms.Label
$splashBar.BackColor = [System.Drawing.Color]::FromArgb(0, 166, 255)
$splashBar.Location  = New-Object System.Drawing.Point(1, 1)
$splashBar.Size      = New-Object System.Drawing.Size(0, 6)
$splashBarTrack.Controls.Add($splashBar)

$splashFoot = New-Object System.Windows.Forms.Label
$splashFoot.Text      = 'Inicializando modulos e verificando ambiente...'
$splashFoot.Font      = New-Object System.Drawing.Font('Segoe UI', 8)
$splashFoot.ForeColor = [System.Drawing.Color]::FromArgb(98, 124, 147)
$splashFoot.Location  = New-Object System.Drawing.Point(54, 254)
$splashFoot.Size      = New-Object System.Drawing.Size(412, 16)
$splashCard.Controls.Add($splashFoot)

$splash.Show()
[System.Windows.Forms.Application]::DoEvents()

# Animacao da barra de progresso
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 32
$script:barW = 0
$script:splashProgress = 0
$script:spinnerFrames = @('●','◕','◑','◔')
$script:spinnerIdx = 0
$script:splashSteps = @(
    'Carregando interfaces...',
    'Lendo hardware e BIOS...',
    'Preparando dados da etiqueta...',
    'Conectando aos servicos...'
)
$script:splashStepIdx = 0
$timer.Add_Tick({
    $script:spinnerIdx = ($script:spinnerIdx + 1) % $script:spinnerFrames.Count
    $splashSpinner.Text = $script:spinnerFrames[$script:spinnerIdx]
    [System.Windows.Forms.Application]::DoEvents()
})
$timer.Start()
$script:splashBarMaxW = 364
$script:UpdateSplashProgress = {
    param([int]$Percent, [string]$Message)
    $pct = [math]::Max($script:splashProgress, [math]::Min(100, $Percent))
    $script:splashProgress = $pct
    $script:barW = [math]::Round(($script:splashBarMaxW * $pct) / 100)
    $splashBar.Width = $script:barW
    $splashPercent.Text = "$pct%"
    if ($Message) { $splashMsg.Text = $Message }
    [System.Windows.Forms.Application]::DoEvents()
}
$splash.Add_FormClosed({
    try { $timer.Stop(); $timer.Dispose() } catch {}
    try { if ($splashLogoImg.Image) { $splashLogoImg.Image.Dispose() } } catch {}
})


# ================================================
# COLETA DE DADOS
# ================================================
function Get-NotebookInfo {
    $info = [ordered]@{}
    & $script:UpdateSplashProgress 8 'Lendo BIOS e identificacao do notebook...'

    try {
        $bios = Get-CimInstance Win32_BIOS
        $cs   = Get-CimInstance Win32_ComputerSystem
        $csp  = Get-CimInstance Win32_ComputerSystemProduct
        $fab  = $cs.Manufacturer.Trim()
        $mod  = $cs.Model.Trim()
        $ver  = if ($csp.Version) { $csp.Version.Trim() } else { '' }
        if ($fab -match 'Lenovo' -and $ver -and $ver -notmatch 'Default|O\.E\.M' -and $ver -ne 'Lenovo') {
            $info.Modelo = $fab + ' ' + $ver
        } else {
            $info.Modelo = $fab + ' ' + $mod
        }
        $info.Serial = $bios.SerialNumber.Trim()
    } catch { $info.Modelo = 'N/A'; $info.Serial = 'N/A' }
    & $script:UpdateSplashProgress 18 'Coletando dados do processador...'

    try {
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        $info.CPU      = $cpu.Name.Trim()
        $info.Nucleos  = $cpu.NumberOfCores.ToString() + ' nucleos / ' + $cpu.NumberOfLogicalProcessors.ToString() + ' threads'
        $info.ClockMax = [math]::Round($cpu.MaxClockSpeed / 1000, 1).ToString() + ' GHz'
    } catch { $info.CPU = 'N/A'; $info.Nucleos = 'N/A'; $info.ClockMax = 'N/A' }
    & $script:UpdateSplashProgress 28 'Analisando placa de video...'

    try {
        $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object {
            $_ -and $_.Name -and $_.Name.ToString().Trim() -ne '' -and
            $_.Name -notmatch '(?i)(Citrix|Microsoft Basic|LogMeIn|TeamViewer|Virtual)'
        })
        $gpuList = @(); $hasDedicated = $false; $gpuDedicada = $null

        function Get-VramTexto($gpuObj) {
            try {
                if ($null -ne $gpuObj.AdapterRAM -and [double]$gpuObj.AdapterRAM -gt 0) {
                    $vramGb = [math]::Round(([double]$gpuObj.AdapterRAM / 1GB), 1)
                    if ($vramGb -ge 1) {
                        if (($vramGb % 1) -eq 0) { return ('{0}GB' -f [int]$vramGb) }
                        return ('{0}GB' -f $vramGb.ToString('0.#', [System.Globalization.CultureInfo]::InvariantCulture))
                    }
                }
            } catch {}
            return ''
        }

        foreach ($g in $gpus) {
            $nomeGpu = $g.Name.Trim()
            $vramTxt = Get-VramTexto $g
            $gpuList += [pscustomobject]@{ Nome = $nomeGpu; Vram = $vramTxt }
            if ($nomeGpu -match '(?i)(NVIDIA|GeForce|RTX|GTX|Quadro|Radeon RX|Radeon Pro|Radeon R[579])') {
                $hasDedicated = $true
                $gpuDedicada = [pscustomobject]@{ Nome = $nomeGpu; Vram = $vramTxt }
            }
        }
        $gpuList = $gpuList | Group-Object Nome | ForEach-Object { $_.Group[0] }
        if ($hasDedicated) {
            $nomeBase = $gpuDedicada.Nome
            $info.GPU = if ($gpuDedicada.Vram) { "$nomeBase $($gpuDedicada.Vram) (Dedicada)" } else { "$nomeBase (Dedicada)" }
        } elseif ($gpuList.Count -gt 0) {
            $nomeBase = (($gpuList[0].Nome) -replace '\(TM\)','' -replace '\(R\)','').Trim()
            $info.GPU = if ($gpuList[0].Vram) { "$nomeBase $($gpuList[0].Vram) (Integrada)" } else { "$nomeBase (Integrada)" }
        } else {
            # Fallback robusto para casos em que o Win32_VideoController nao retorna adequadamente.
            $gpuFallback = $null
            try {
                $pnp = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue |
                    Where-Object {
                        $_ -and $_.FriendlyName -and
                        $_.FriendlyName -notmatch '(?i)(Citrix|Microsoft Basic|Remote|Virtual)' -and
                        $_.Status -ne 'Unknown'
                    } |
                    Select-Object -First 1
                if ($pnp -and $pnp.FriendlyName) { $gpuFallback = [string]$pnp.FriendlyName }
            } catch {}

            if (-not $gpuFallback) {
                try {
                    $vc2 = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -and $_.Name -notmatch '(?i)Microsoft Basic' } |
                        Select-Object -First 1
                    if ($vc2 -and $vc2.Name) { $gpuFallback = [string]$vc2.Name }
                } catch {}
            }

            if ($gpuFallback) {
                $nomeBase = ($gpuFallback -replace '\(TM\)','' -replace '\(R\)','').Trim()
                $info.GPU = "$nomeBase (Integrada)"
            } else {
                $info.GPU = 'Nao identificada'
            }
        }
    } catch { $info.GPU = 'N/A' }
    & $script:UpdateSplashProgress 42 'Verificando memoria RAM...'

    try {
        $ramArray   = @(Get-CimInstance Win32_PhysicalMemory)
        $totalGB    = 0
        foreach ($r in $ramArray) { $totalGB += $r.Capacity }
        $totalGB    = [math]::Round($totalGB / 1GB)
        $ramFirst   = $ramArray[0]
        $memTypeVal = if ($ramFirst.SMBIOSMemoryType) { $ramFirst.SMBIOSMemoryType } else { $ramFirst.MemoryType }
        $tipo  = switch ($memTypeVal) { 24{'DDR3'} 26{'DDR4'} 30{'LPDDR4'} 34{'DDR5'} 35{'LPDDR5'} default{'DDR4'} }
        $speed = $ramFirst.Speed
        $modsLista = @()
        $modsMeta  = @()
        foreach ($m in $ramArray) {
            $cap   = [math]::Round($m.Capacity / 1GB).ToString() + 'GB'
            $ff    = [int]($m.FormFactor)
            $loc   = if ($m.DeviceLocator) { $m.DeviceLocator.ToString().ToLower() } else { '' }
            $bank  = if ($m.BankLabel)     { $m.BankLabel.ToString().ToLower()     } else { '' }
            $mtype = if ($m.SMBIOSMemoryType) { [int]$m.SMBIOSMemoryType } else { [int]$m.MemoryType }
            $isOnboard = $false
            if     ($ff -eq 15)                              { $isOnboard = $true }  # Row Of Chips = soldado
            elseif ($mtype -eq 30 -or $mtype -eq 35)        { $isOnboard = $true }  # LPDDR4/LPDDR5
            elseif ($loc  -match 'soldered|onboard|row')    { $isOnboard = $true }
            elseif ($bank -match 'soldered|onboard')         { $isOnboard = $true }
            $modsMeta += [pscustomobject]@{
                CapGb = [int]([math]::Round($m.Capacity / 1GB))
                Loc = $loc
                Bank = $bank
                IsOnboard = $isOnboard
            }
        }

        # Heuristica Lenovo ThinkPad E14/T14:
        # em varios modelos, ChannelA-DIMM0 costuma ser memoria soldada
        # e ChannelB-DIMM0 costuma ser o slot expansivel.
        $modeloAtual = if ($info.Modelo) { $info.Modelo.ToLower() } else { '' }
        if (
            $modsMeta.Count -eq 2 -and
            $modeloAtual -match 'thinkpad (e14|t14)' -and
            ($modsMeta | Where-Object { $_.Loc -match 'channela' }).Count -eq 1 -and
            ($modsMeta | Where-Object { $_.Loc -match 'channelb' }).Count -eq 1
        ) {
            foreach ($mm in $modsMeta) {
                if ($mm.Loc -match 'channela') { $mm.IsOnboard = $true }
                elseif ($mm.Loc -match 'channelb') { $mm.IsOnboard = $false }
            }
        }

        foreach ($mm in $modsMeta) {
            $capTxt = "$($mm.CapGb)GB"
            if ($mm.IsOnboard) { $modsLista += $capTxt + ' (Onboard)' } else { $modsLista += $capTxt + ' (Slot)' }
        }

        # Corrige quirk de BIOS (ex: Positivo) que reporta 1 modulo fisico como varios de 1GB
        $onboardMods = @($modsLista | Where-Object { $_ -match '\(Onboard\)' })
        $slotMods    = @($modsLista | Where-Object { $_ -match '\(Slot\)' })
        if ($onboardMods.Count -ge 2) {
            $tamanhos = $onboardMods | ForEach-Object { [int]($_ -replace 'GB.*', '') }
            $unicos   = @($tamanhos | Select-Object -Unique)
            # Consolida se todos onboard tem mesmo tamanho pequeno (<=2GB) - split virtual de BIOS
            if ($unicos.Count -eq 1 -and $unicos[0] -le 2) {
                $totalOnboard = ($tamanhos | Measure-Object -Sum).Sum
                $modsLista    = @("${totalOnboard}GB (Onboard)") + $slotMods
            }
        }

        $info.RAM     = $totalGB.ToString() + 'GB ' + $tipo + ' ' + $speed.ToString() + ' MHz'
        $info.RAMMods = $modsLista -join ' + '
    } catch { $info.RAM = 'N/A'; $info.RAMMods = 'N/A' }
    & $script:UpdateSplashProgress 54 'Detectando resolucao de tela...'

    try {
        $videoRes = Get-CimInstance Win32_VideoController | Where-Object { $_.CurrentHorizontalResolution -ne $null } | Select-Object -First 1
        if ($videoRes) {
            $w = $videoRes.CurrentHorizontalResolution; $h = $videoRes.CurrentVerticalResolution; $hz = $videoRes.CurrentRefreshRate
            $tipoTela = switch ("${w}x${h}") {
                '1280x720'{' (HD)'} '1366x768'{' (HD)'} '1600x900'{' (HD+)'}
                '1920x1080'{' (Full HD)'} '1920x1200'{' (WUXGA)'} '2560x1440'{' (2K)'} '3840x2160'{' (4K)'} default{ if ($w -gt 1920){' (Alta Resolucao)'}else{''} }
            }
            $info.Tela = "${w} x ${h}${tipoTela}"
            if ($hz) { $info.Tela += " @ ${hz}Hz" }
        } else { $info.Tela = 'Nao detectada' }
    } catch { $info.Tela = 'N/A' }
    & $script:UpdateSplashProgress 66 'Mapeando discos instalados...'

    try {
        $physMap = @{}
        try {
            Get-PhysicalDisk -ErrorAction Stop | ForEach-Object { $physMap[$_.FriendlyName.Trim()] = $_.MediaType }
        } catch {}
        $discos = Get-CimInstance Win32_DiskDrive | Where-Object { $_.InterfaceType -ne 'USB' -and $_.MediaType -notmatch 'Removable' }
        $lista  = @()
        foreach ($d in $discos) {
            $rawGB = $d.Size / 1GB; $gbRound = [math]::Round($rawGB)
            if     ($gbRound -ge 110 -and $gbRound -le 130)  { $gb = '128' }
            elseif ($gbRound -ge 220 -and $gbRound -le 260)  { $gb = '256' }
            elseif ($gbRound -ge 460 -and $gbRound -le 520)  { $gb = '512' }
            elseif ($gbRound -ge 900 -and $gbRound -le 1050) { $gb = '1000' }
            elseif ($gbRound -ge 1800 -and $gbRound -le 2100){ $gb = '2000' }
            else   { $gb = $gbRound.ToString() }
            $nome     = $d.Model.Trim()
            $physType = $physMap[$nome]
            if     ($physType -eq 'SSD') { $tipo = 'SSD' }
            elseif ($physType -eq 'HDD') { $tipo = 'HDD' }
            elseif ($nome -match 'NVMe|SSD|M\.2|SSSTC|MZV|MZN|KBG|HFM|SN\d{3}|KIOXIA|THNSN|HFS|SSDPE|SSDSC|WDS' -or $d.MediaType -match 'SSD') { $tipo = 'SSD' }
            else   { $tipo = 'HDD' }
            $lista += $gb + 'GB ' + $tipo + ' - ' + $nome
        }
        $info.Discos = if ($lista.Count -gt 0) { $lista -join $NL } else { 'Nenhum disco encontrado' }
    } catch { $info.Discos = 'N/A' }
    & $script:UpdateSplashProgress 78 'Calculando saude da bateria...'

    try {
        $batStatic = $null; $batFull = $null
        # Tenta CimInstance primeiro
        try {
            $batStatic = Get-CimInstance -Namespace 'root\wmi' -Class BatteryStaticData -ErrorAction Stop | Select-Object -First 1
            $batFull   = Get-CimInstance -Namespace 'root\wmi' -Class BatteryFullChargedCapacity -ErrorAction Stop | Select-Object -First 1
        } catch {
            # Fallback WmiObject
            try {
                $batStatic = Get-WmiObject -Namespace 'root\wmi' -Class BatteryStaticData -ErrorAction Stop | Select-Object -First 1
                $batFull   = Get-WmiObject -Namespace 'root\wmi' -Class BatteryFullChargedCapacity -ErrorAction Stop | Select-Object -First 1
            } catch {}
        }
        if ($batStatic -and $batFull) {
            $designCap = $batStatic.DesignedCapacity; $fullCap = $batFull.FullChargedCapacity
            if ($designCap -gt 0) {
                $saude = [math]::Round(($fullCap / $designCap) * 100)
                $statusSaude = 'Ruim'
                if ($saude -ge 80) { $statusSaude = 'Excellent' }
                elseif ($saude -ge 65) { $statusSaude = 'Good' }
                elseif ($saude -ge 50) { $statusSaude = 'Fair' }
                $info.BatSaude = $statusSaude + ' (' + $saude.ToString() + '%)'
            } else { $info.BatSaude = 'N/A' }
        } else {
            # Tenta via Win32_Battery como ultimo recurso
            $bat32 = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($bat32) {
                $info.BatSaude = 'Detectada (' + $bat32.EstimatedChargeRemaining.ToString() + '% carga)'
            } else {
                $info.BatSaude = 'Sem bateria detectada'
            }
        }
    } catch { $info.BatSaude = 'Sem bateria detectada' }
    & $script:UpdateSplashProgress 90 'Coletando versao do Windows...'

    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $info.Windows = $os.Caption + ' - Build ' + $os.BuildNumber
    } catch { $info.Windows = 'N/A' }
    & $script:UpdateSplashProgress 98 'Finalizando inicializacao...'

    return $info
}

$info     = Get-NotebookInfo
$dataHora = Get-Date -Format 'dd/MM/yyyy HH:mm'

# Numero da Ordem de Servico (OS) - persistido em arquivo local
$script:osArquivo = Join-Path (Split-Path -Parent $PSCommandPath) 'caij_os_counter.txt'
$script:historicoArquivo = Join-Path (Split-Path -Parent $PSCommandPath) 'caij_historico_notebooks.json'
$script:registroBaseDir = $null
$script:registroBaseDirFallback = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'CAIJ\Registros'
$script:ultimoStatusServidor = 'nao verificado'
$script:ultimaSincronizacaoOs = ''
$script:osNumero  = 235
if (Test-Path $script:osArquivo) {
    try { $script:osNumero = [int]((Get-Content $script:osArquivo -Raw -ErrorAction Stop).Trim()) } catch {}
}
if ($script:osNumero -lt 235) { $script:osNumero = 235 }

function Save-OsNumero {
    param([int]$Numero)
    try { Set-Content -Path $script:osArquivo -Value $Numero -Encoding UTF8 } catch {}
}

function Get-RegistroBaseDir {
    if ($script:registroBaseDir -and $script:registroBaseDir.Trim() -ne '') { return $script:registroBaseDir }

    try {
        # Prioridade: salvar no proprio pendrive, fora da pasta do projeto.
        $driveRoot = [System.IO.Path]::GetPathRoot($PSCommandPath)
        if ($driveRoot -and $driveRoot.Trim() -ne '') {
            $dirPendrive = Join-Path $driveRoot 'CAIJ-Registros'
            if (-not (Test-Path $dirPendrive)) { New-Item -ItemType Directory -Path $dirPendrive -Force | Out-Null }
            $teste = Join-Path $dirPendrive '.write-test'
            Set-Content -Path $teste -Value 'ok' -Encoding ASCII -ErrorAction Stop
            Remove-Item -LiteralPath $teste -Force -ErrorAction SilentlyContinue
            $script:registroBaseDir = $dirPendrive
            return $script:registroBaseDir
        }
    } catch {}

    try {
        if (-not (Test-Path $script:registroBaseDirFallback)) {
            New-Item -ItemType Directory -Path $script:registroBaseDirFallback -Force | Out-Null
        }
        $script:registroBaseDir = $script:registroBaseDirFallback
    } catch {
        $script:registroBaseDir = Split-Path -Parent $PSCommandPath
    }
    return $script:registroBaseDir
}

function Set-AppStatus {
    param(
        [string]$Texto,
        [System.Drawing.Color]$Cor
    )
    if (-not $Cor) { $Cor = $cMuted }
    try {
        if ($script:botTxt) { $script:botTxt.Text = $Texto; $script:botTxt.ForeColor = $Cor }
        if ($script:botDot) { $script:botDot.BackColor = $Cor }
    } catch {}
}

function Test-ServidorPrincipal {
    param([switch]$Quiet)
    try {
        $baseUrl = Get-ServidorBaseUrl
        $resp = Invoke-RestMethod -Uri ('{0}/status' -f $baseUrl) -Method Get -TimeoutSec 3 -ErrorAction Stop
        $script:ultimoStatusServidor = if ($resp.status -eq 'ok') { 'online' } else { 'resposta inesperada' }
        if (-not $Quiet) { Set-AppStatus -Texto "Servidor online | OS $(Format-OsCodigo -Numero $script:osNumero)" -Cor $cGreen }
        return $true
    } catch {
        $script:ultimoStatusServidor = 'offline'
        if (-not $Quiet) { Set-AppStatus -Texto 'Servidor principal offline | usando dados locais' -Cor $cYellow }
        return $false
    }
}

function Add-HistoricoNotebook {
    param(
        [string]$Acao,
        [string]$Status,
        [string]$Mensagem,
        [string]$Grade,
        [string]$Obs
    )
    $registro = [ordered]@{
        dataHora = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        acao = $Acao
        status = $Status
        mensagem = $Mensagem
        os = (Format-OsCodigo -Numero $script:osNumero)
        osNumero = $script:osNumero
        serial = $info.Serial
        modelo = $info.Modelo
        cpu = $info.CPU
        ram = $info.RAM
        disco = (($info.Discos -split $NL) | Where-Object { $_.Trim() -ne '' } | Select-Object -First 1)
        gpu = $info.GPU
        bateria = $info.BatSaude
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
        $linhaLog = [ordered]@{
            dataHora = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
            os = (Format-OsCodigo -Numero $script:osNumero)
            osNumero = $script:osNumero
            status = $Status
            acao = $Acao
            mensagem = $Mensagem
            serial = if ($script:serialEtiqueta -and $script:serialEtiqueta.Trim() -ne '') { $script:serialEtiqueta } else { $info.Serial }
            modelo = if ($script:modeloEtiqueta -and $script:modeloEtiqueta.Trim() -ne '') { $script:modeloEtiqueta } else { $info.Modelo }
            grade = $Grade
            observacoes = $Obs
            servidor = $script:ultimoStatusServidor
            osSincronizadaEm = $script:ultimaSincronizacaoOs
            computador = $env:COMPUTERNAME
            usuario = $env:USERNAME
        } | ConvertTo-Json -Compress

        Add-Content -Path $logArquivo -Value $linhaLog -Encoding UTF8
    } catch {}
}

# Memoria de produto por assinatura (modelo+cpu+ram+disco)
$script:produtoMemArquivo = Join-Path (Split-Path -Parent $PSCommandPath) 'caij_produto_por_assinatura.json'
$script:produtoMemoria = @{}
if (Test-Path $script:produtoMemArquivo) {
    try {
        $rawMem = Get-Content $script:produtoMemArquivo -Raw -ErrorAction Stop
        if ($rawMem -and $rawMem.Trim()) {
            $objMem = $rawMem | ConvertFrom-Json -ErrorAction Stop
            $ht = @{}
            if ($objMem -is [System.Collections.IDictionary]) {
                foreach ($k in $objMem.Keys) { $ht[[string]$k] = [string]$objMem[$k] }
            } elseif ($objMem.PSObject -and $objMem.PSObject.Properties) {
                foreach ($p in $objMem.PSObject.Properties) { $ht[[string]$p.Name] = [string]$p.Value }
            }
            $script:produtoMemoria = $ht
        }
    } catch {}
}

function Get-ProdutoAssinatura {
    param([string]$Modelo, [string]$Cpu, [string]$Ram, [string]$Disco)
    $m = if ($Modelo) { $Modelo.Trim().ToUpper() } else { '' }
    $c = if ($Cpu) { $Cpu.Trim().ToUpper() } else { '' }
    $r = if ($Ram) { $Ram.Trim().ToUpper() } else { '' }
    $d = if ($Disco) { $Disco.Trim().ToUpper() } else { '' }
    return "$m|$c|$r|$d"
}

function Save-ProdutoMemoria {
    try {
        ($script:produtoMemoria | ConvertTo-Json -Compress) | Set-Content -Path $script:produtoMemArquivo -Encoding UTF8
    } catch {}
}

function Get-ServidorCandidates {
    $portaServidor = 9100
    $candidatos = New-Object System.Collections.Generic.List[string]

    $cfgPath = Join-Path (Split-Path -Parent $PSCommandPath) 'caij_servidor_url.txt'
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

    # IP historico do PC principal.
    [void]$candidatos.Add(('http://{0}:{1}' -f '192.168.15.54', $portaServidor))

    # Tenta o final .54 em cada rede IPv4 local do notebook.
    try {
        $ipsLocais = @(Get-CimInstance Win32_NetworkAdapterConfiguration -ErrorAction SilentlyContinue |
            Where-Object { $_.IPEnabled -and $_.IPAddress } |
            ForEach-Object { $_.IPAddress } |
            Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' -and $_ -notmatch '^169\.254\.' -and $_ -ne '127.0.0.1' })

        foreach ($ipLocal in $ipsLocais) {
            $parts = $ipLocal.Split('.')
            if ($parts.Count -eq 4) {
                [void]$candidatos.Add(('http://{0}.{1}.{2}.54:{3}' -f $parts[0], $parts[1], $parts[2], $portaServidor))
            }
        }
    } catch {}

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

function Get-ServidorBaseUrl {
    $cfgPath = Join-Path (Split-Path -Parent $PSCommandPath) 'caij_servidor_url.txt'
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

function Extract-AltertagCodigo {
    param([string]$Texto)
    if (-not $Texto) { return '' }
    $valor = $Texto.Trim()
    if ($valor -match '^\s*([A-Z0-9][A-Z0-9\-]{2,})\b') {
        return $matches[1].ToUpper()
    }
    return $valor
}

function Select-CodigoProdutoAutomatico {
    param(
        [string[]]$Opcoes,
        [string]$Modelo,
        [string]$Cpu,
        [string]$Ram,
        [string]$Disco
    )
    if (-not $Opcoes -or $Opcoes.Count -eq 0) { return $null }
    $cpuUp = if ($Cpu) { $Cpu.ToUpper() } else { '' }
    $ramUp = if ($Ram) { $Ram.ToUpper() } else { '' }
    $discoUp = if ($Disco) { $Disco.ToUpper() } else { '' }
    $modeloUp = if ($Modelo) { $Modelo.ToUpper() } else { '' }
    $prefI7 = $cpuUp -match '\bI7\b'
    $prefI5 = $cpuUp -match '\bI5\b'
    $pref11 = $cpuUp -match '11'
    $pref10 = $cpuUp -match '10'
    $pref16 = $ramUp -match '\b16GB\b'
    $pref8  = $ramUp -match '\b8GB\b'
    $pref512 = $discoUp -match '\b(476|480|500|512)GB\b'
    $pref256 = $discoUp -match '\b(238|240|250|256)GB\b'

    $best = $null
    $bestScore = -999
    foreach ($op in $Opcoes) {
        $txt = [string]$op
        if (-not $txt) { continue }
        $u = $txt.ToUpper()
        $score = 0
        if ($modeloUp -match '\bE14\b' -and $u -match '\bE14\b') { $score += 4 }
        if ($modeloUp -match '\bT14\b' -and $u -match '\bT14\b') { $score += 4 }
        if ($prefI7 -and $u -match '\bI7\b') { $score += 4 }
        if ($prefI5 -and $u -match '\bI5\b') { $score += 4 }
        if ($pref11 -and $u -match '11') { $score += 3 }
        if ($pref10 -and $u -match '10') { $score += 3 }
        if ($pref16 -and $u -match '\b16GB\b') { $score += 3 }
        if ($pref8  -and $u -match '\b8GB\b')  { $score += 3 }
        if ($pref512 -and $u -match '\b(500|512)GB\b') { $score += 3 }
        if ($pref256 -and $u -match '\b(240|250|256)GB\b') { $score += 3 }
        if ($score -gt $bestScore) {
            $bestScore = $score
            $best = $txt
        }
    }
    if (-not $best) { return $null }
    if ($best -match '^\s*([A-Z0-9][A-Z0-9\-]{2,})') { return $matches[1].ToUpper() }
    return $null
}

# Fluxo sequencial global de OS (nao sobrescrever por serial)

# ================================================
# CORES E FONTES (tema preto + azul refinado)
# ================================================
$cBg      = [System.Drawing.Color]::FromArgb(6, 10, 18)
$cSurface = [System.Drawing.Color]::FromArgb(12, 19, 30)
$cCard    = [System.Drawing.Color]::FromArgb(16, 26, 40)
$cHeader  = [System.Drawing.Color]::FromArgb(10, 17, 28)
$cBar     = [System.Drawing.Color]::FromArgb(4, 8, 14)
$cBorder  = [System.Drawing.Color]::FromArgb(36, 70, 104)
$cAccent  = [System.Drawing.Color]::FromArgb(24, 185, 255)
$cGreen   = [System.Drawing.Color]::FromArgb(66, 232, 176)
$cPurple  = [System.Drawing.Color]::FromArgb(132, 148, 255)
$cYellow  = [System.Drawing.Color]::FromArgb(255, 208, 96)
$cOrange  = [System.Drawing.Color]::FromArgb(255, 156, 98)
$cRed     = [System.Drawing.Color]::FromArgb(241, 95, 122)
$cMain    = [System.Drawing.Color]::FromArgb(236, 245, 255)
$cMuted   = [System.Drawing.Color]::FromArgb(162, 192, 219)
$cDim     = [System.Drawing.Color]::FromArgb(102, 134, 165)

$fUI    = New-Object System.Drawing.Font('Segoe UI', 9)
$fBold  = New-Object System.Drawing.Font('Segoe UI', 9,  [System.Drawing.FontStyle]::Bold)
$fSm    = New-Object System.Drawing.Font('Segoe UI', 8)
$fMicro = New-Object System.Drawing.Font('Segoe UI', 7)
$fTitle = New-Object System.Drawing.Font('Segoe UI Semibold', 16, [System.Drawing.FontStyle]::Bold)
$fSer   = New-Object System.Drawing.Font('Segoe UI', 15, [System.Drawing.FontStyle]::Bold)

# ================================================
# FORM
# ================================================
$W = 700

$form = New-Object System.Windows.Forms.Form
$form.Text            = 'Caij Informatica'
$form.BackColor       = $cBg
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox     = $false
$form.StartPosition   = 'CenterScreen'
$form.Font            = $fUI

# ================================================
# BARRA SUPERIOR
# ================================================
$topBar = New-Object System.Windows.Forms.Panel
$topBar.BackColor = $cBar
$topBar.Location  = New-Object System.Drawing.Point(0, 0)
$topBar.Size      = New-Object System.Drawing.Size($W, 34)
$form.Controls.Add($topBar)

$topBarLine = New-Object System.Windows.Forms.Panel
$topBarLine.BackColor = [System.Drawing.Color]::FromArgb(20, 42, 66)
$topBarLine.Location  = New-Object System.Drawing.Point(0, 33)
$topBarLine.Size      = New-Object System.Drawing.Size($W, 1)
$topBar.Controls.Add($topBarLine)

$tdot = New-Object System.Windows.Forms.Label
$tdot.BackColor = $cGreen
$tdot.Location  = New-Object System.Drawing.Point(14, 13)
$tdot.Size      = New-Object System.Drawing.Size(8, 8)
$topBar.Controls.Add($tdot)

$tlbl = New-Object System.Windows.Forms.Label
$tlbl.Text      = 'CAIJ INFORMATICA  |  PAINEL TECNICO'
$tlbl.Font      = $fMicro
$tlbl.ForeColor = [System.Drawing.Color]::FromArgb(128, 166, 198)
$tlbl.Location  = New-Object System.Drawing.Point(30, 10)
$tlbl.Size      = New-Object System.Drawing.Size(310, 14)
$topBar.Controls.Add($tlbl)

$ttime = New-Object System.Windows.Forms.Label
$ttime.Text      = 'Atualizado: ' + $dataHora
$ttime.Font      = $fMicro
$ttime.ForeColor = [System.Drawing.Color]::FromArgb(128, 166, 198)
$ttime.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$ttime.Location  = New-Object System.Drawing.Point(408, 10)
$ttime.Size      = New-Object System.Drawing.Size(264, 14)
$topBar.Controls.Add($ttime)

# ================================================
# HEADER
# ================================================
$hH = 92
$hPanel = New-Object System.Windows.Forms.Panel
$hPanel.BackColor = $cHeader
$hPanel.Location  = New-Object System.Drawing.Point(0, 34)
$hPanel.Size      = New-Object System.Drawing.Size($W, $hH)
$form.Controls.Add($hPanel)

$hPanel.Add_Paint({
    param($sender, $e)
    $r = New-Object System.Drawing.Rectangle(0, 0, $sender.Width, $sender.Height)
    $b = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $r,
        [System.Drawing.Color]::FromArgb(12, 22, 36),
        [System.Drawing.Color]::FromArgb(8, 15, 24),
        [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal
    )
    $e.Graphics.FillRectangle($b, $r)
    $b.Dispose()
})

# Barra accent esquerda
$hAccL = New-Object System.Windows.Forms.Panel
$hAccL.BackColor = $cAccent
$hAccL.Location  = New-Object System.Drawing.Point(0, 0)
$hAccL.Size      = New-Object System.Drawing.Size(4, $hH)
$hPanel.Controls.Add($hAccL)

# Titulo
$hTitle = New-Object System.Windows.Forms.Label
$hTitle.Text      = 'Inventario de Hardware'
$hTitle.Font      = New-Object System.Drawing.Font('Segoe UI Semibold', 18, [System.Drawing.FontStyle]::Bold)
$hTitle.ForeColor = $cMain
$hTitle.Location  = New-Object System.Drawing.Point(22, 12)
$hTitle.Size      = New-Object System.Drawing.Size(460, 32)
$hPanel.Controls.Add($hTitle)

# Linha decorativa abaixo do titulo
$hTitleLine = New-Object System.Windows.Forms.Panel
$hTitleLine.BackColor = $cAccent
$hTitleLine.Location  = New-Object System.Drawing.Point(22, 44)
$hTitleLine.Size      = New-Object System.Drawing.Size(72, 2)
$hPanel.Controls.Add($hTitleLine)

$hSoftLine = New-Object System.Windows.Forms.Panel
$hSoftLine.BackColor = [System.Drawing.Color]::FromArgb(35, 60, 86)
$hSoftLine.Location  = New-Object System.Drawing.Point(22, 95)
$hSoftLine.Size      = New-Object System.Drawing.Size(446, 1)
$hPanel.Controls.Add($hSoftLine)

# Modelo
$hModel = New-Object System.Windows.Forms.Label
$hModel.Text      = $info.Modelo.ToUpper()
$hModel.Font      = New-Object System.Drawing.Font('Segoe UI Semibold', 8, [System.Drawing.FontStyle]::Bold)
$hModel.ForeColor = [System.Drawing.Color]::FromArgb(196, 224, 246)
$hModel.Location  = New-Object System.Drawing.Point(22, 58)
$hModel.Size      = New-Object System.Drawing.Size(460, 14)
$hPanel.Controls.Add($hModel)

# Data hora
$hDate = New-Object System.Windows.Forms.Label
$hDate.Text      = $dataHora
$hDate.Font      = New-Object System.Drawing.Font('Segoe UI', 7)
$hDate.ForeColor = [System.Drawing.Color]::FromArgb(74, 106, 136)
$hDate.Location  = New-Object System.Drawing.Point(22, 74)
$hDate.Size      = New-Object System.Drawing.Size(200, 12)
$hPanel.Controls.Add($hDate)

# Caixa serial
$sBox = New-Object System.Windows.Forms.Panel
$sBox.BackColor = [System.Drawing.Color]::FromArgb(8, 25, 42)
$sBox.Location  = New-Object System.Drawing.Point(500, 12)
$sBox.Size      = New-Object System.Drawing.Size(186, 82)
$sBox.BorderStyle = 'None'
$hPanel.Controls.Add($sBox)

function Set-RoundedControl {
    param(
        [Parameter(Mandatory=$true)]$Control,
        [int]$Radius = 10
    )
    try {
        $d = [math]::Max(2, $Radius * 2)
        $rect = New-Object System.Drawing.Rectangle(0, 0, $Control.Width, $Control.Height)
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $path.AddArc($rect.X, $rect.Y, $d, $d, 180, 90)
        $path.AddArc($rect.Right - $d, $rect.Y, $d, $d, 270, 90)
        $path.AddArc($rect.Right - $d, $rect.Bottom - $d, $d, $d, 0, 90)
        $path.AddArc($rect.X, $rect.Bottom - $d, $d, $d, 90, 90)
        $path.CloseFigure()
        $Control.Region = New-Object System.Drawing.Region($path)
        $path.Dispose()
    } catch {}
}
Set-RoundedControl -Control $sBox -Radius 8
$sBox.Add_SizeChanged({ Set-RoundedControl -Control $sBox -Radius 8 })

$sBoxLine = New-Object System.Windows.Forms.Panel
$sBoxLine.BackColor = [System.Drawing.Color]::FromArgb(34, 74, 108)
$sBoxLine.Location = New-Object System.Drawing.Point(0, 0)
$sBoxLine.Size = New-Object System.Drawing.Size(186, 1)
$sBox.Controls.Add($sBoxLine)

$sLbl = New-Object System.Windows.Forms.Label
$sLbl.Text      = 'N U M E R O   D E   S E R I E'
$sLbl.Font      = New-Object System.Drawing.Font('Segoe UI', 6)
$sLbl.ForeColor = [System.Drawing.Color]::FromArgb(108, 148, 182)
$sLbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$sLbl.Location  = New-Object System.Drawing.Point(0, 14)
$sLbl.Size      = New-Object System.Drawing.Size(186, 14)
$sBox.Controls.Add($sLbl)

$sVal = New-Object System.Windows.Forms.Label
$sVal.Text      = $info.Serial
$sVal.Font      = $fSer
$sVal.ForeColor = $cAccent
$sVal.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$sVal.Location  = New-Object System.Drawing.Point(0, 26)
$sVal.Size      = New-Object System.Drawing.Size(186, 30)
$sBox.Controls.Add($sVal)

# OS number na parte inferior da caixa
$script:osValLabel = New-Object System.Windows.Forms.Label
$script:osValLabel.Text      = 'C000' + $script:osNumero.ToString()
$script:osValLabel.Font      = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
$script:osValLabel.ForeColor = $cGreen
$script:osValLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$script:osValLabel.Location  = New-Object System.Drawing.Point(0, 62)
$script:osValLabel.Size      = New-Object System.Drawing.Size(186, 15)
$script:osValLabel.Cursor    = [System.Windows.Forms.Cursors]::Hand
$sBox.Controls.Add($script:osValLabel)

$osSyncBtn = New-Object System.Windows.Forms.Button
$osSyncBtn.Text = 'Sync'
$osSyncBtn.Font = New-Object System.Drawing.Font('Segoe UI', 6.5, [System.Drawing.FontStyle]::Bold)
$osSyncBtn.ForeColor = $cMain
$osSyncBtn.BackColor = [System.Drawing.Color]::FromArgb(12, 28, 44)
$osSyncBtn.FlatStyle = 'Flat'
$osSyncBtn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(24, 90, 148)
$osSyncBtn.Location = New-Object System.Drawing.Point(67, 62)
$osSyncBtn.Size = New-Object System.Drawing.Size(52, 16)
$sBox.Controls.Add($osSyncBtn)

function Format-OsCodigo {
    param([int]$Numero)
    if ($Numero -lt 1) { return '' }
    return ('C000{0}' -f $Numero)
}

function Set-OsNumeroAtual {
    param([int]$Numero)
    if ($Numero -lt 1) { return }
    $script:osNumero = $Numero
    if ($script:osValLabel) { $script:osValLabel.Text = (Format-OsCodigo -Numero $script:osNumero) }
    Save-OsNumero -Numero $script:osNumero
}

function Try-ReadOsFromClipboard {
    try {
        if (-not [System.Windows.Forms.Clipboard]::ContainsText()) { return $null }
        $clip = [System.Windows.Forms.Clipboard]::GetText().Trim()
        if (-not $clip) { return $null }
        if ($clip -match '(?i)(numero\s+da\s+os|os#?|ordem\s+de\s+servico)[^\d]{0,10}(\d{2,8})') { return [int]$matches[2] }
        if ($clip -match '(?<!\d)(\d{2,8})(?!\d)') { return [int]$matches[1] }
    } catch {}
    return $null
}

function Prompt-OsManual {
    $osSugerida = Try-ReadOsFromClipboard
    if (-not $osSugerida) { $osSugerida = $script:osNumero }
    $entrada = [Microsoft.VisualBasic.Interaction]::InputBox(
        "Informe o numero da OS gerado no Alterdata (se voce copiar o numero antes, ele ja vem sugerido):",
        "Definir Ordem de Servico",
        $osSugerida.ToString()
    )
    if (-not $entrada -or $entrada.Trim() -eq '') { return }
    if ($entrada.Trim() -notmatch '^\d{2,8}$') {
        [System.Windows.Forms.MessageBox]::Show('Numero de OS invalido. Digite somente numeros.', 'OS invalida', 'OK', 'Warning') | Out-Null
        return
    }
    Set-OsNumeroAtual -Numero ([int]$entrada.Trim())
}

$script:osValLabel.Add_Click({ Prompt-OsManual })

function Sync-OsFromAltertag {
    param([switch]$Silent)
    try {
        $erroServidor = ''
        try {
            $respOs = Invoke-CaijServer -Path '/status-os' -Method GET -TimeoutSec 12 -Retries 3
            if ($respOs -and [string]$respOs.status -eq 'ok' -and $respOs.proximoDisponivel) {
                $proximaSrv = [int]$respOs.proximoDisponivel
                Set-OsNumeroAtual -Numero $proximaSrv
                $script:ultimaSincronizacaoOs = Get-Date -Format 'dd/MM HH:mm'
                $syncLabel = if ($respOs.sincronizacao) { [string]$respOs.sincronizacao } else { 'ok' }
                Set-AppStatus -Texto "Servidor online | proxima OS: $(Format-OsCodigo -Numero $proximaSrv) | sync: $syncLabel" -Cor $cGreen
                if (-not $Silent) {
                    [System.Windows.Forms.MessageBox]::Show(
                        "Proxima OS disponivel: $(Format-OsCodigo -Numero $proximaSrv)`nSincronizacao: $syncLabel",
                        'Sincronizacao de OS',
                        'OK',
                        'Information'
                    ) | Out-Null
                }
                return
            }
            if ($respOs -and $respOs.mensagem) { $erroServidor = [string]$respOs.mensagem }
        } catch {
            $erroServidor = $_.Exception.Message
            try {
                if ($_.Exception.Response) {
                    $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                    $body = $reader.ReadToEnd()
                    $reader.Close()
                    if ($body) { $erroServidor = "$erroServidor`n$body" }
                }
            } catch {}
        }

        Set-AppStatus -Texto 'Falha ao consultar status de OS | usando contador local' -Cor $cYellow
        if (-not $Silent) {
            $detalheSrv = if ($erroServidor) { "`n`nDetalhe servidor /status-os:`n$erroServidor" } else { '' }
            [System.Windows.Forms.MessageBox]::Show(
                "Falha ao consultar OS pelo servidor.$detalheSrv`n`nDica: verifique se o ServidorImpressao.ps1 esta rodando no PC principal.",
                'Sincronizacao de OS',
                'OK',
                'Warning'
            ) | Out-Null
        }
    } catch {
        if (-not $Silent) {
            Set-AppStatus -Texto 'Erro ao sincronizar OS | usando contador local' -Cor $cYellow
            [System.Windows.Forms.MessageBox]::Show(
                "Erro ao sincronizar OS:`n$($_.Exception.Message)",
                'Sincronizacao de OS',
                'OK',
                'Warning'
            ) | Out-Null
        }
    }
}

$osSyncBtn.Add_Click({ Sync-OsFromAltertag })

$hLineY = 34 + $hH
$hLine = New-Object System.Windows.Forms.Label
$hLine.BackColor = $cAccent
$hLine.Location  = New-Object System.Drawing.Point(0, $hLineY)
$hLine.Size      = New-Object System.Drawing.Size($W, 2)
$hLine.Visible = $false
$form.Controls.Add($hLine)

# ================================================
# SCROLL CONTENT
# ================================================
$scrollY = $hLineY + 2
$scroll = New-Object System.Windows.Forms.Panel
$scroll.AutoScroll = $false
$scroll.Location   = New-Object System.Drawing.Point(0, $scrollY)
$scroll.BackColor  = [System.Drawing.Color]::FromArgb(7, 12, 20)
$form.Controls.Add($scroll)

$script:py = 16
$CW = 660  # content width

# ---- secao ----
function Add-Sec {
    param([string]$label, [System.Drawing.Color]$cor)

    $sp = New-Object System.Windows.Forms.Panel
    $sp.BackColor = [System.Drawing.Color]::FromArgb(8, 15, 24)
    $sp.Location  = New-Object System.Drawing.Point(16, $script:py)
    $sp.Size      = New-Object System.Drawing.Size($CW, 20)
    $sp.BorderStyle = 'None'
    $scroll.Controls.Add($sp)

    $abar = New-Object System.Windows.Forms.Panel
    $abar.BackColor = $cor
    $abar.Location  = New-Object System.Drawing.Point(0, 0)
    $abar.Size      = New-Object System.Drawing.Size(4, 20)
    $sp.Controls.Add($abar)

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text      = $label.ToUpper()
    $lbl.Font      = New-Object System.Drawing.Font('Segoe UI Semibold', 8, [System.Drawing.FontStyle]::Bold)
    $lbl.ForeColor = $cor
    $lbl.Location  = New-Object System.Drawing.Point(14, 2)
    $lbl.Size      = New-Object System.Drawing.Size(420, 13)
    $sp.Controls.Add($lbl)

    $script:py += 24
}

# ---- linha simples ----
function Add-Row {
    param([string]$k, [string]$v, [System.Drawing.Color]$vc, [System.Drawing.Color]$ac)
    if (-not $vc) { $vc = $cMain }
    if (-not $ac) { $ac = $cBorder }

    $p = New-Object System.Windows.Forms.Panel
    $p.BackColor = [System.Drawing.Color]::FromArgb(15, 25, 39)
    $p.Location  = New-Object System.Drawing.Point(16, $script:py)
    $p.Size      = New-Object System.Drawing.Size($CW, 28)
    $p.BorderStyle = 'None'
    $scroll.Controls.Add($p)

    $abar = New-Object System.Windows.Forms.Panel
    $abar.BackColor = $ac
    $abar.Location  = New-Object System.Drawing.Point(0, 5)
    $abar.Size      = New-Object System.Drawing.Size(4, 18)
    $p.Controls.Add($abar)

    $lk = New-Object System.Windows.Forms.Label
    $lk.Text = $k; $lk.Font = New-Object System.Drawing.Font('Segoe UI', 8.5); $lk.ForeColor = $cMuted
    $lk.Location = New-Object System.Drawing.Point(18, 5); $lk.Size = New-Object System.Drawing.Size(132, 16)
    $p.Controls.Add($lk)

    $lv = New-Object System.Windows.Forms.Label
    $lv.Text = $v; $lv.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5, [System.Drawing.FontStyle]::Bold); $lv.ForeColor = $vc
    $lv.Location = New-Object System.Drawing.Point(152, 5); $lv.Size = New-Object System.Drawing.Size(488, 16)
    $p.Controls.Add($lv)

    $script:py += 30
}

# ---- duas colunas ----
function Add-Row2 {
    param(
        [string]$k1, [string]$v1, [System.Drawing.Color]$c1,
        [string]$k2, [string]$v2, [System.Drawing.Color]$c2,
        [System.Drawing.Color]$ac
    )
    if (-not $ac) { $ac = $cBorder }
    $half = [int](($CW - 4) / 2)

    $p1 = New-Object System.Windows.Forms.Panel
    $p1.BackColor = [System.Drawing.Color]::FromArgb(15, 25, 39)
    $p1.Location  = New-Object System.Drawing.Point(16, $script:py)
    $p1.Size      = New-Object System.Drawing.Size($half, 28)
    $p1.BorderStyle = 'None'
    $scroll.Controls.Add($p1)

    $ab1 = New-Object System.Windows.Forms.Panel
    $ab1.BackColor = $ac; $ab1.Location = New-Object System.Drawing.Point(0, 5); $ab1.Size = New-Object System.Drawing.Size(4, 18)
    $p1.Controls.Add($ab1)

    $lk1 = New-Object System.Windows.Forms.Label
    $lk1.Text = $k1; $lk1.Font = New-Object System.Drawing.Font('Segoe UI', 8.5); $lk1.ForeColor = $cMuted
    $lk1.Location = New-Object System.Drawing.Point(18, 5); $lk1.Size = New-Object System.Drawing.Size(96, 16)
    $p1.Controls.Add($lk1)
    $lv1 = New-Object System.Windows.Forms.Label
    $lv1.Text = $v1; $lv1.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5, [System.Drawing.FontStyle]::Bold); $lv1.ForeColor = $c1
    $lv1.Location = New-Object System.Drawing.Point(116, 5); $lv1.Size = New-Object System.Drawing.Size(208, 16)
    $p1.Controls.Add($lv1)

    $p2 = New-Object System.Windows.Forms.Panel
    $p2.BackColor = [System.Drawing.Color]::FromArgb(15, 25, 39)
    $p2.Location  = New-Object System.Drawing.Point((16 + $half + 4), $script:py)
    $p2.Size      = New-Object System.Drawing.Size($half, 28)
    $p2.BorderStyle = 'None'
    $scroll.Controls.Add($p2)

    $ab2 = New-Object System.Windows.Forms.Panel
    $ab2.BackColor = $ac; $ab2.Location = New-Object System.Drawing.Point(0, 5); $ab2.Size = New-Object System.Drawing.Size(4, 18)
    $p2.Controls.Add($ab2)

    $lk2 = New-Object System.Windows.Forms.Label
    $lk2.Text = $k2; $lk2.Font = New-Object System.Drawing.Font('Segoe UI', 8.5); $lk2.ForeColor = $cMuted
    $lk2.Location = New-Object System.Drawing.Point(18, 5); $lk2.Size = New-Object System.Drawing.Size(96, 16)
    $p2.Controls.Add($lk2)
    $lv2 = New-Object System.Windows.Forms.Label
    $lv2.Text = $v2; $lv2.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5, [System.Drawing.FontStyle]::Bold); $lv2.ForeColor = $c2
    $lv2.Location = New-Object System.Drawing.Point(116, 5); $lv2.Size = New-Object System.Drawing.Size(208, 16)
    $p2.Controls.Add($lv2)

    $script:py += 30
}

function Gap { $script:py += 6 }

# ---- SECAO 1 ----
Add-Sec 'Processador & Memoria' $cAccent
Add-Row 'Processador' $info.CPU $cMain $cAccent
Add-Row2 'Nucleos' $info.Nucleos $cAccent 'Clock Max' $info.ClockMax $cAccent $cAccent
Add-Row 'RAM Total' $info.RAM $cYellow $cYellow
Add-Row 'Modulos' $info.RAMMods $cMuted $cYellow
Gap

# ---- SECAO 2 ----
Add-Sec 'Armazenamento & Video' $cGreen
foreach ($linha in ($info.Discos -split $NL)) {
    if ($linha.Trim() -ne '') { Add-Row 'Armazenamento' $linha $cGreen $cGreen }
}
$corGPU = if ($info.GPU -match 'Dedicada') { [System.Drawing.Color]::FromArgb(100, 220, 80) } else { $cMain }
Add-Row 'Placa de Video' $info.GPU $corGPU $cGreen
Add-Row 'Resolucao' $info.Tela $cMain $cGreen
Gap

# ---- SECAO 3 ----
Add-Sec 'Sistema & Bateria' $cPurple
Add-Row 'Windows' $info.Windows $cMain $cPurple
# Hostname removido para manter layout mais limpo
$corBat = $cMain
if     ($info.BatSaude -match 'Excelente|Excellent') { $corBat = $cGreen }
elseif ($info.BatSaude -match 'Boa|Good')            { $corBat = $cYellow }
elseif ($info.BatSaude -match 'Regular|Fair')        { $corBat = $cOrange }
elseif ($info.BatSaude -match 'Ruim|Poor')           { $corBat = $cRed }
Add-Row 'Bateria' $info.BatSaude $corBat $cPurple

if ($info.BatSaude -match '\((\d+)%\)') {
    $pct  = [int]$Matches[1]
    $barW = [math]::Max(1, [int](($CW * $pct) / 100))
    $bfg  = New-Object System.Windows.Forms.Panel
    $bfg.BackColor = $corBat
    $bfg.Location  = New-Object System.Drawing.Point(16, $script:py)
    $bfg.Size      = New-Object System.Drawing.Size($barW, 4)
    $scroll.Controls.Add($bfg)
    if ($barW -lt $CW) {
        $bbg = New-Object System.Windows.Forms.Panel
        $bbg.BackColor = [System.Drawing.Color]::FromArgb(18, 28, 40)
        $bbg.Location  = New-Object System.Drawing.Point((16 + $barW), $script:py)
        $bbg.Size      = New-Object System.Drawing.Size(($CW - $barW), 4)
        $scroll.Controls.Add($bbg)
    }
    $script:py += 7
}
Gap

$contentH = $script:py + 4
$scroll.Size = New-Object System.Drawing.Size($W, $contentH)

# ================================================
# BARRA DE ACOES
# ================================================
$actY = $scrollY + $contentH

$actBar = New-Object System.Windows.Forms.Panel
$actBar.BackColor = $cBar
$actBar.Location  = New-Object System.Drawing.Point(0, $actY)
$actBar.Size      = New-Object System.Drawing.Size($W, 108)
$form.Controls.Add($actBar)

$actTopLine = New-Object System.Windows.Forms.Label
$actTopLine.BackColor = [System.Drawing.Color]::FromArgb(24, 48, 72)
$actTopLine.Location  = New-Object System.Drawing.Point(0, 0)
$actTopLine.Size      = New-Object System.Drawing.Size($W, 1)
$actTopLine.Visible = $true
$actBar.Controls.Add($actTopLine)

# helper botao
function New-Btn {
    param(
        [string]$txt,
        [int]$x, [int]$y, [int]$w, [int]$h,
        [System.Drawing.Color]$bg,
        [System.Drawing.Color]$fg,
        [System.Drawing.Color]$bgH,
        [System.Drawing.Font]$font
    )
    if (-not $font) { $font = New-Object System.Drawing.Font('Segoe UI Semibold', 10, [System.Drawing.FontStyle]::Bold) }
    $b = New-Object System.Windows.Forms.Button
    $b.Text      = $txt
    $b.Font      = $font
    $b.ForeColor = $fg
    $b.BackColor = $bg
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize  = 2
    $b.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb([int][math]::Min($bg.R + 20, 255), [int][math]::Min($bg.G + 20, 255), [int][math]::Min($bg.B + 30, 255))
    $b.FlatAppearance.MouseOverBackColor = $bgH
    $b.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb([int][math]::Max($bg.R - 8, 0), [int][math]::Max($bg.G - 8, 0), [int][math]::Max($bg.B - 8, 0))
    $b.Location  = New-Object System.Drawing.Point($x, $y)
    $b.Size      = New-Object System.Drawing.Size($w, $h)
    $b.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $b.TextAlign  = [System.Drawing.ContentAlignment]::MiddleCenter
    $bgN = $bg
    $fgN = $fg
    $bgHov = $bgH
    $borderN = $b.FlatAppearance.BorderColor
    $borderH = [System.Drawing.Color]::FromArgb(
        [int][math]::Min($borderN.R + 35, 255),
        [int][math]::Min($borderN.G + 35, 255),
        [int][math]::Min($borderN.B + 35, 255)
    )
    $origY = $y
    $b.Add_MouseEnter({
        $this.BackColor = $bgHov
        $this.ForeColor = [System.Drawing.Color]::White
        $this.FlatAppearance.BorderColor = $borderH
        $this.Location = New-Object System.Drawing.Point($this.Location.X, [math]::Max(0, $origY - 2))
    }.GetNewClosure())
    $b.Add_MouseLeave({
        $this.BackColor = $bgN
        $this.ForeColor = $fgN
        $this.FlatAppearance.BorderColor = $borderN
        $this.Location = New-Object System.Drawing.Point($this.Location.X, $origY)
    }.GetNewClosure())
    Set-RoundedControl -Control $b -Radius 9
    $b.Add_SizeChanged({ Set-RoundedControl -Control $this -Radius 9 })
    $actBar.Controls.Add($b)
    return $b
}

# Linha 1 - 4 botoes: Copiar | Enviar | Atualizar | Fechar
# larguras: 155 | 155 | 155 | 50 | 109  + gaps de 7 = 155*3 + 50 + 109 + 7*4 = 779 -> ajustar
# total usavel: 700 - 14*2 = 672
# 3 botoes grandes + 1 pequeno + 1 medio com gap 6
# 672 com distribuicao mais equilibrada

$bY1 = 8
$bH  = 34
$g   = 5
$x   = 14

$tooltip = New-Object System.Windows.Forms.ToolTip
$tooltip.BackColor = [System.Drawing.Color]::FromArgb(20, 30, 44)
$tooltip.ForeColor = [System.Drawing.Color]::White
$tooltip.InitialDelay = 400
$tooltip.ReshowDelay  = 200

$btnCopiar = New-Btn 'Copiar Info' $x $bY1 126 $bH `
    ([System.Drawing.Color]::FromArgb(12, 40, 65)) $cMain ([System.Drawing.Color]::FromArgb(20, 58, 88))
$tooltip.SetToolTip($btnCopiar, 'Copia as informacoes de hardware para a area de transferencia')
$x += 126 + $g

$btnEnviar = New-Btn 'Enviar Estoque' $x $bY1 146 $bH `
    ([System.Drawing.Color]::FromArgb(10, 42, 30)) ([System.Drawing.Color]::FromArgb(196, 247, 227)) ([System.Drawing.Color]::FromArgb(14, 54, 37))
$tooltip.SetToolTip($btnEnviar, 'Envia as informacoes para o grupo do Telegram')
$x += 146 + $g

$btnAtualizar = New-Btn 'Atualizar' $x $bY1 98 $bH `
    ([System.Drawing.Color]::FromArgb(17, 24, 40)) $cMain ([System.Drawing.Color]::FromArgb(24, 36, 58))
$tooltip.SetToolTip($btnAtualizar, 'Reinicia o script para atualizar os dados')
$x += 98 + $g

$btnTestes = New-Btn 'Realizar Testes' $x $bY1 146 $bH `
    ([System.Drawing.Color]::FromArgb(18, 44, 68)) ([System.Drawing.Color]::FromArgb(218, 240, 255)) ([System.Drawing.Color]::FromArgb(24, 58, 86))
$tooltip.SetToolTip($btnTestes, 'Abre a central completa de testes')
$x += 146 + $g

$btnFechar = New-Btn 'Fechar' $x $bY1 132 $bH `
    ([System.Drawing.Color]::FromArgb(52, 14, 22)) ([System.Drawing.Color]::FromArgb(255, 205, 213)) ([System.Drawing.Color]::FromArgb(66, 18, 28))

# Linha 2 - Imprimir
$row2Y = ($bY1 + $bH + $g)
$btnImprimir = New-Btn 'Imprimir Etiqueta via Rede' 14 $row2Y 672 36 `
    ([System.Drawing.Color]::FromArgb(10, 56, 88)) ([System.Drawing.Color]::FromArgb(237, 248, 255)) ([System.Drawing.Color]::FromArgb(14, 72, 110))

# ================================================
# ACOES DOS BOTOES
# ================================================
$buildText = {
    $txt  = "CAIJ INFORMATICA - INVENTARIO`n"
    $txt += "================================`n"
    $txt += "Modelo:  $($info.Modelo)`n"
    $txt += "Serial:  $($info.Serial)`n"
    $txt += "OS:      $(Format-OsCodigo -Numero $script:osNumero)`n"
    $txt += "Data:    $dataHora`n"
    $txt += "--------------------------------`n"
    $txt += "CPU:     $($info.CPU)`n"
    $txt += "Nucleos: $($info.Nucleos)`n"
    $txt += "Clock:   $($info.ClockMax)`n"
    $txt += "RAM:     $($info.RAM)`n"
    $txt += "Modulos: $($info.RAMMods)`n"
    $txt += "GPU:     $($info.GPU)`n"
    $txt += "Tela:    $($info.Tela)`n"
    $txt += "Disco:   $($info.Discos -replace $NL, ' | ')`n"
    $txt += "Bateria: $($info.BatSaude)`n"
    $txt += "Windows: $($info.Windows)`n"
    return $txt
}

$btnCopiar.Add_Click({
    [System.Windows.Forms.Clipboard]::SetText((&$buildText))
    $btnCopiar.Text = 'Copiado!'
    $btnCopiar.ForeColor = $cGreen
    $resetTimer = New-Object System.Windows.Forms.Timer
    $resetTimer.Interval = 1200
    $resetTimer.Add_Tick({
        $btnCopiar.Text = 'Copiar Info'
        $btnCopiar.ForeColor = $cAccent
        $this.Stop()
        $this.Dispose()
    })
    $resetTimer.Start()
})

$btnAtualizar.Add_Click({
    Start-Process powershell -ArgumentList ('-ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $PSCommandPath + '"')
    $form.Close()
})

$btnTestes.Add_Click({
    try {
        $scriptPathTeste = Join-Path (Split-Path -Parent $PSCommandPath) 'TestarNotebook.ps1'
        if (Test-Path $scriptPathTeste) {
            Start-Process powershell -ArgumentList ('-ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $scriptPathTeste + '"')
        } else {
            [System.Windows.Forms.MessageBox]::Show("Arquivo de testes nao encontrado:`n$scriptPathTeste", 'Central de Testes', 'OK', 'Warning') | Out-Null
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Falha ao abrir central de testes:`n$($_.Exception.Message)", 'Central de Testes', 'OK', 'Error') | Out-Null
    }
})

$btnFechar.Add_Click({ $form.Close() })

$btnEnviar.Add_Click({
    $btnEnviar.Text    = 'Enviando...'
    $btnEnviar.Enabled = $false
    [System.Windows.Forms.Application]::DoEvents()
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $e_predio = [char]::ConvertFromUtf32(0x1F3E2)
        $e_pranch = [char]::ConvertFromUtf32(0x1F4CB)
        $e_note   = [char]::ConvertFromUtf32(0x1F4BB)
        $e_chave  = [char]::ConvertFromUtf32(0x1F511)
        $e_calen  = [char]::ConvertFromUtf32(0x1F4C6)
        $e_engre  = [char]::ConvertFromUtf32(0x2699)
        $e_seta   = [char]0x21B3
        $e_bat    = [char]::ConvertFromUtf32(0x1F50B)
        $e_os     = [char]::ConvertFromUtf32(0x1F4CB)
        $msg  = "$e_predio <b>CAIJ INFORMATICA | INVENTARIO</b>`n"
        $msg += "------------------------------`n`n"
        $msg += "$e_pranch <b>IDENTIFICACAO</b>`n"
        $msg += "$e_note <b>Modelo:</b> $($info.Modelo)`n"
        $msg += "$e_chave <b>Serial:</b> $($info.Serial)`n"
        $msg += "$e_os <b>OS#:</b> $(Format-OsCodigo -Numero $script:osNumero)`n"
        $msg += "$e_calen <b>Registro:</b> $dataHora`n`n"
        $msg += "$e_engre <b>ESPECIFICACOES</b>`n"
        $msg += "<b>CPU:</b> $($info.CPU)`n"
        $msg += "<i>$e_seta $($info.Nucleos) | $($info.ClockMax)</i>`n`n"
        $msg += "<b>RAM:</b> $($info.RAM)`n"
        $msg += "<i>$e_seta $($info.RAMMods)</i>`n`n"
        $msg += "<b>GPU:</b> $($info.GPU)`n"
        $msg += "<b>Tela:</b> $($info.Tela)`n`n"
        $msg += "<b>Armazenamento:</b>`n"
        foreach ($d in ($info.Discos -split $NL)) {
            if ($d.Trim() -ne '') { $msg += "<i>$e_seta $d</i>`n" }
        }
        $msg += "`n$e_bat <b>Bateria:</b> $($info.BatSaude)`n"
        $msg += "<b>Windows:</b> $($info.Windows)`n"
        $msg += '------------------------------'
        $url  = "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage"
        $body = @{ chat_id = $TELEGRAM_CHAT_ID; text = $msg; parse_mode = 'HTML' } | ConvertTo-Json
        Invoke-RestMethod -Uri $url -Method Post -Body $body -ContentType 'application/json; charset=utf-8' -ErrorAction Stop
        $btnEnviar.Text      = 'Enviado!'
        $btnEnviar.ForeColor = [System.Drawing.Color]::White
        $btnEnviar.BackColor = [System.Drawing.Color]::FromArgb(0, 90, 40)
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Erro ao enviar para o Telegram:`n$($_.Exception.Message)", 'Erro', 'OK', 'Error') | Out-Null
        $btnEnviar.Text      = 'Falha!'
        $btnEnviar.BackColor = [System.Drawing.Color]::FromArgb(130, 30, 30)
    }
    $btnEnviar.Enabled = $true
    $resetEnviarTimer = New-Object System.Windows.Forms.Timer
    $resetEnviarTimer.Interval = 2500
    $resetEnviarTimer.Add_Tick({
        $btnEnviar.Text      = 'Enviar Estoque'
        $btnEnviar.ForeColor = $cGreen
        $btnEnviar.BackColor = [System.Drawing.Color]::FromArgb(8, 32, 22)
        $this.Stop()
        $this.Dispose()
    })
    $resetEnviarTimer.Start()
})

$btnImprimir.Add_Click({
    $btnImprimir.Enabled = $false
    [System.Windows.Forms.Application]::DoEvents()

    # Prepara dados
    $cpuCurto = $info.CPU
    if      ($cpuCurto -match '(?i)(i[3579])[- ](\d{1,2})\d{2}') { $cpuCurto = $matches[1].ToUpper() + ' ' + $matches[2] + 'th' }
    elseif  ($cpuCurto -match '(?i)Ryzen\s+(\d)\s+(\d)\d{3}')    { $cpuCurto = 'Ryzen ' + $matches[1] + ' ' + $matches[2] + '000' }
    elseif  ($cpuCurto -match '(?i)(Celeron|Pentium)')            { $cpuCurto = $matches[1] }
    $ramCurto   = ($info.RAM -split ' ')[0]
    $pd         = ($info.Discos -split $NL)[0]
    $discoCurto = if ($pd -match '^(\d+GB)\s+(SSD|HDD)') { $matches[2] + ' ' + $matches[1] } else { $pd.Substring(0, [math]::Min($pd.Length, 15)) }
    if ($pd -match '(?i)\b(931|1000|1024)GB\b') { $discoCurto = '1TB SSD' }
    elseif ($pd -match '(?i)\b(476|480|500|512)GB\b') { $discoCurto = '512GB SSD' }
    elseif ($pd -match '(?i)\b(238|240|250|256)GB\b') { $discoCurto = '256GB SSD' }
    elseif ($pd -match '(?i)\b(119|120|128)GB\b') { $discoCurto = '128GB SSD' }
    $gpuCurta = $info.GPU
    $gpuVramSuf = ''
    if ($gpuCurta -match '(?i)\b(\d+(?:[.,]\d+)?)\s*GB\b') {
        $gpuVramSuf = ' ' + ($matches[1] -replace ',', '.') + 'GB'
    }
    if ($gpuCurta -match '(?i)MX\s*450') { $gpuCurta = 'MX450 Dedicada' }
    elseif ($gpuCurta -match '(?i)MX\s*350') { $gpuCurta = 'MX350 Dedicada' }
    elseif ($gpuCurta -match '(?i)RTX\s*([0-9]{4})') { $gpuCurta = "RTX $($Matches[1]) Dedicada" }
    elseif ($gpuCurta -match '(?i)GTX\s*([0-9]{3,4})') { $gpuCurta = "GTX $($Matches[1]) Dedicada" }
    elseif ($gpuCurta -match '(?i)Iris\s*Xe') { $gpuCurta = 'Intel Iris Xe' }
    elseif ($gpuCurta -match '(?i)UHD') { $gpuCurta = 'Intel UHD' }
    elseif ($gpuCurta.Length -gt 28) { $gpuCurta = $gpuCurta.Substring(0, 28) }
    if ($gpuVramSuf -and $gpuCurta -notmatch '(?i)\bGB\b') { $gpuCurta += $gpuVramSuf }

    # ================================================
    # POPUP PREVIA DE IMPRESSAO
    # ================================================
    $popup = New-Object System.Windows.Forms.Form
    $popup.Text            = 'Previa de Impressao'
    $popup.Size            = New-Object System.Drawing.Size(530, 715)
    $popup.StartPosition   = 'CenterScreen'
    $popup.BackColor       = $cBg
    $popup.FormBorderStyle = 'FixedDialog'
    $popup.MaximizeBox     = $false
    $popup.MinimizeBox     = $false
    $popup.TopMost         = $true
    $popup.Font            = $fUI
    $popup.KeyPreview      = $true

    $popTitle = New-Object System.Windows.Forms.Label
    $popTitle.Text = 'PREVIA DA ETIQUETA'; $popTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 13, [System.Drawing.FontStyle]::Bold)
    $popTitle.ForeColor = $cAccent
    $popTitle.Location = New-Object System.Drawing.Point(16, 8); $popTitle.Size = New-Object System.Drawing.Size(380, 26)
    $popup.Controls.Add($popTitle)

    $popSub = New-Object System.Windows.Forms.Label
    $popSub.Text = 'Conferencia visual antes da impressao'
    $popSub.Font = New-Object System.Drawing.Font('Segoe UI', 8)
    $popSub.ForeColor = $cMuted
    $popSub.Location = New-Object System.Drawing.Point(16, 33)
    $popSub.Size = New-Object System.Drawing.Size(240, 16)
    $popup.Controls.Add($popSub)

    # Painel previa
    $prevPanel = New-Object System.Windows.Forms.Panel
    $prevPanel.Location = New-Object System.Drawing.Point(16, 58)
    $prevPanel.Size = New-Object System.Drawing.Size(478, 294)
    $prevPanel.BackColor = [System.Drawing.Color]::White
    $prevPanel.BorderStyle = 'FixedSingle'
    $popup.Controls.Add($prevPanel)
    Set-RoundedControl -Control $prevPanel -Radius 6

    $script:gradeAtual = 'A'
    $script:obsAtual   = ''
    $script:incluirOSAtual = $true
    $script:triagemServicos = @()
    $script:osDefinidaPorTriagem = $false
    $script:modeloEtiqueta = $info.Modelo
    $script:serialEtiqueta = $info.Serial
    $script:cpuEtiqueta    = $cpuCurto
    $script:memEtiqueta    = $discoCurto
    $script:ramEtiqueta    = $ramCurto
    $script:modoManualEtiqueta = $false
    $script:rnaAtivo = $false
    $script:rnaItensOk = @()

    $script:GetObsImpressao = {
        $baseObs = if ($script:obsAtual) { $script:obsAtual.Trim() } else { '' }
        if ($script:rnaAtivo) {
            $lista = if ($script:rnaItensOk -and $script:rnaItensOk.Count -gt 0) { ($script:rnaItensOk -join ', ') } else { 'Nenhum informado' }
            $rmaTxt = "Defeito: $lista"
            if ($baseObs) { return "$baseObs | $rmaTxt" }
            return $rmaTxt
        }
        return $baseObs
    }

    $script:DesenharPrevia = {
        param($grade, $obs, $incluirOS)
        $prevPanel.Controls.Clear()
        $fNorm   = New-Object System.Drawing.Font('Cascadia Mono', 6,  [System.Drawing.FontStyle]::Regular)
        $fNormB  = New-Object System.Drawing.Font('Cascadia Mono', 6,  [System.Drawing.FontStyle]::Bold)
        $fMed    = New-Object System.Drawing.Font('Cascadia Mono', 7,  [System.Drawing.FontStyle]::Regular)
        $fLarge  = New-Object System.Drawing.Font('Cascadia Mono', 11, [System.Drawing.FontStyle]::Bold)
        $fObs    = New-Object System.Drawing.Font('Cascadia Mono', 8,  [System.Drawing.FontStyle]::Bold)
        $fHeader = New-Object System.Drawing.Font('Cascadia Mono', 9,  [System.Drawing.FontStyle]::Bold)
        $preto   = [System.Drawing.Color]::Black
        $cinza   = [System.Drawing.Color]::FromArgb(80, 80, 80)
        $cinzaL  = [System.Drawing.Color]::FromArgb(160, 160, 160)

        function L($txt, $x, $y, $w, $h, $f, $fc) {
            $l = New-Object System.Windows.Forms.Label
            $l.Text = $txt; $l.Font = $f; $l.ForeColor = $fc
            $l.Location = New-Object System.Drawing.Point($x, $y)
            $l.Size     = New-Object System.Drawing.Size($w, $h)
            $l.BackColor = [System.Drawing.Color]::Transparent
            $prevPanel.Controls.Add($l)
        }
        function B($x, $y, $w, $h) {
            $b = New-Object System.Windows.Forms.Panel
            $b.BackColor = $preto
            $b.Location  = New-Object System.Drawing.Point($x, $y)
            $b.Size      = New-Object System.Drawing.Size($w, $h)
            $prevPanel.Controls.Add($b)
        }

        function Wrap-TextLines {
            param(
                [string]$Text,
                [int]$MaxLen = 48,
                [int]$MaxLines = 2
            )
            $clean = ([string]$Text -replace '\s+', ' ').Trim()
            if (-not $clean) { return @() }
            $words = $clean -split '\s+'
            $lines = New-Object System.Collections.Generic.List[string]
            $current = ''
            foreach ($word in $words) {
                $candidate = if ($current) { "$current $word" } else { $word }
                if ($candidate.Length -le $MaxLen) {
                    $current = $candidate
                    continue
                }
                if ($current) {
                    $lines.Add($current)
                    $current = ''
                    if ($lines.Count -ge $MaxLines) { break }
                }
                if ($word.Length -le $MaxLen) {
                    $current = $word
                } else {
                    $remaining = $word
                    while ($remaining.Length -gt $MaxLen -and $lines.Count -lt $MaxLines) {
                        $lines.Add($remaining.Substring(0, $MaxLen))
                        $remaining = $remaining.Substring($MaxLen)
                    }
                    $current = $remaining
                }
                if ($lines.Count -ge $MaxLines) { break }
            }
            if ($current -and $lines.Count -lt $MaxLines) { $lines.Add($current) }
            if ($lines.Count -gt $MaxLines) { $lines = @($lines[0..($MaxLines - 1)]) }
            if ($lines.Count -eq $MaxLines -and $current.Length -gt 0) {
                $last = $lines[$MaxLines - 1]
                if ($last.Length -gt 3) {
                    $lines[$MaxLines - 1] = $last.Substring(0, [math]::Max(0, $MaxLen - 3)) + '...'
                }
            }
            return @($lines)
        }

        # Moldura unica proporcional ao TSPL real da etiqueta 78x48mm
        B 1 3 476 2; B 1 289 476 2; B 1 3 2 288; B 475 3 2 288

        # Cabecalho
        L 'CAIJ INFORMATICA' 14 12 220 14 $fHeader $preto

        # Grade em caixa
        if ($grade) {
        $gradeTxt = if ($script:rnaAtivo) { 'RMA' } else { "GRADE: $([string]$grade)" }
            B 340 11 134 2
            B 340 34 134 2
            B 340 11 2 25
            B 472 11 2 25
            L $gradeTxt 348 16 116 14 $fHeader $preto
        }
        if ($incluirOS) {
            B 340 41 134 2
            B 340 62 134 2
            B 340 41 2 23
            B 472 41 2 23
            L (Format-OsCodigo -Numero $script:osNumero) 348 46 118 13 $fNormB $preto
        }
        if ($script:modoManualEtiqueta) {
            B 206 10 128 2
            B 206 30 128 2
            B 206 10 2 22
            B 332 10 2 22
            L 'MODO MANUAL' 214 15 112 12 $fNormB $preto
        }

        # Separador fino (somente na area esquerda para nao cruzar os boxes de grade/OS)
        B 14 42 320 1

        # Modelo
        L $script:modeloEtiqueta 18 48 440 13 $fMed $cinza

        # Separador duplo
        B 14 68 458 2

        # Serial grande
        L $script:serialEtiqueta 18 76 450 24 $fLarge $preto

        # Barcode simulado
        $cx = 18; $bk = $true
        foreach ($pw in @(2,1,3,1,2,2,1,3,1,2,3,1,2,1,3,2,1,3,1,2,1,3,2,1,2,3,1,2,1,3,2,1)) {
            if ($bk) { B $cx 108 $pw 22 }
            $cx += $pw; $bk = !$bk
        }
        L $script:serialEtiqueta 18 132 300 11 $fNorm $cinzaL

        # Separador specs
        B 14 144 458 2

        # Separador vertical
        B 72 148 1 92

        L 'CPU'   18 152 50 12 $fNormB $preto
        L 'RAM'   18 171 50 12 $fNormB $preto
        L 'DISCO' 18 190 50 12 $fNormB $preto
        L 'GPU'   18 209 50 12 $fNormB $preto
        L 'BAT'   18 228 50 12 $fNormB $preto

        L $script:cpuEtiqueta    78 152 390 12 $fNorm $preto
        L $script:ramEtiqueta    78 171 390 12 $fNorm $preto
        L $script:memEtiqueta    78 190 390 12 $fNorm $preto
        L $gpuCurta              78 209 390 12 $fNorm $preto
        L $($info.BatSaude)      78 228 390 12 $fNorm $preto

        # Observacao
        if ($obs -and $obs.Trim() -ne '') {
            B 14 254 458 1
            $obsLines = Wrap-TextLines -Text ("Obs: $($obs.Trim())") -MaxLen 48 -MaxLines 2
            if ($obsLines.Count -gt 0) {
                $obsY = 258
                foreach ($line in $obsLines) {
                    L $line 18 $obsY 450 12 $fObs $preto
                    $obsY += 12
                }
                L (Get-Date -Format 'dd/MM/yy HH:mm') 356 ($obsY + 2) 100 12 $fNorm $cinza
            } else {
                L (Get-Date -Format 'dd/MM/yy HH:mm') 356 270 100 12 $fNorm $cinza
            }
        } else {
            L (Get-Date -Format 'dd/MM/yy HH:mm') 356 270 100 12 $fNorm $cinza
        }

        $prevPanel.Refresh()
    }
    & $script:DesenharPrevia 'A' (& $script:GetObsImpressao) $script:incluirOSAtual

    # Grade
    $gradeLabel = New-Object System.Windows.Forms.Label
    $gradeLabel.Text = 'GRADE DO NOTEBOOK *'
    $gradeLabel.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $gradeLabel.ForeColor = $cAccent
    $gradeLabel.Location = New-Object System.Drawing.Point(16, 362); $gradeLabel.Size = New-Object System.Drawing.Size(480, 20)
    $popup.Controls.Add($gradeLabel)

    $coresGrade = @{
        'A' = [System.Drawing.Color]::FromArgb(0, 140, 60)
        'B' = [System.Drawing.Color]::FromArgb(180, 140, 0)
        'C' = [System.Drawing.Color]::FromArgb(180, 90, 0)
        'D' = [System.Drawing.Color]::FromArgb(160, 30, 30)
    }
    $gradesInfo = @(
        @{L='A'; D='Perfeito estado'},
        @{L='B'; D='Alguns detalhes'},
        @{L='C'; D='Detalhes carcaca'},
        @{L='D'; D='Precisa pintura'}
    )

    $script:btnGrades = @{}
    $gX = 16
    foreach ($g in $gradesInfo) {
        $btnG = New-Object System.Windows.Forms.Button
        $btnG.Text = "$($g.L) - $($g.D)"
        $btnG.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5, [System.Drawing.FontStyle]::Bold)
        $btnG.ForeColor = [System.Drawing.Color]::White
        $btnG.BackColor = if ($g.L -eq 'A') { $coresGrade[$g.L] } else { [System.Drawing.Color]::FromArgb(14, 24, 36) }
        $btnG.FlatStyle = 'Flat'
        $btnG.FlatAppearance.BorderColor = $coresGrade[$g.L]
        $btnG.FlatAppearance.BorderSize  = 2
        $btnG.Location = New-Object System.Drawing.Point($gX, 388)
        $btnG.Size     = New-Object System.Drawing.Size(114, 40)
        $btnG.Tag      = $g.L
        $btnG.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(20, 34, 52)
        $btnG.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(16, 28, 44)
        $origPos = $btnG.Location
        $btnG.Add_Click({
            $letraSel = $this.Tag
            $script:gradeAtual = $letraSel
            foreach ($key in $script:btnGrades.Keys) {
                $script:btnGrades[$key].BackColor = [System.Drawing.Color]::FromArgb(14, 24, 36)
                $script:btnGrades[$key].FlatAppearance.BorderSize = 1
            }
            $this.BackColor = $coresGrade[$letraSel]
            $this.FlatAppearance.BorderSize = 2
            & $script:DesenharPrevia $letraSel (& $script:GetObsImpressao) $script:incluirOSAtual
            & $script:UpdateConfirmState
        })
        $btnG.Add_MouseEnter({
            if ($this.Tag -ne $script:gradeAtual) {
                $this.Location = New-Object System.Drawing.Point($origPos.X, ($origPos.Y - 1))
                $this.FlatAppearance.BorderSize = 2
            }
        }.GetNewClosure())
        $btnG.Add_MouseLeave({
            if ($this.Tag -ne $script:gradeAtual) {
                $this.Location = $origPos
                $this.FlatAppearance.BorderSize = 1
            }
        }.GetNewClosure())
        $script:btnGrades[$g.L] = $btnG
        $popup.Controls.Add($btnG)
        Set-RoundedControl -Control $btnG -Radius 6
        $gX += 120
    }

    # Observacoes
    $obsLabel = New-Object System.Windows.Forms.Label
    $obsLabel.Text = 'OBSERVACOES'
    $obsLabel.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $obsLabel.ForeColor = $cAccent
    $obsLabel.Location = New-Object System.Drawing.Point(16, 438); $obsLabel.Size = New-Object System.Drawing.Size(480, 20)
    $popup.Controls.Add($obsLabel)

    $obsBox = New-Object System.Windows.Forms.TextBox
    $obsBox.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $obsBox.BackColor = [System.Drawing.Color]::FromArgb(14, 24, 36)
    $obsBox.ForeColor = [System.Drawing.Color]::FromArgb(190, 220, 238)
    $obsBox.BorderStyle = 'FixedSingle'
    $obsBox.Location = New-Object System.Drawing.Point(16, 460); $obsBox.Size = New-Object System.Drawing.Size(478, 54)
    $obsBox.Multiline = $true
    $obsBox.ScrollBars = 'Vertical'
    $obsBox.MaxLength = 220
    $obsBox.Add_TextChanged({
        $script:obsAtual = $obsBox.Text
        & $script:DesenharPrevia $script:gradeAtual (& $script:GetObsImpressao) $script:incluirOSAtual
        & $script:UpdateConfirmState
    })
    $popup.Controls.Add($obsBox)

    $obsHint = New-Object System.Windows.Forms.Label
    $obsHint.Text = 'Maximo 220 caracteres'
    $obsHint.Font = New-Object System.Drawing.Font('Segoe UI', 7)
    $obsHint.ForeColor = $cDim
    $obsHint.Location = New-Object System.Drawing.Point(16, 520); $obsHint.Size = New-Object System.Drawing.Size(200, 14)
    $popup.Controls.Add($obsHint)

    $osCard = New-Object System.Windows.Forms.Panel
    $osCard.Location = New-Object System.Drawing.Point(16, 544)
    $osCard.Size = New-Object System.Drawing.Size(478, 52)
    $osCard.BackColor = $cCard
    $osCard.BorderStyle = 'FixedSingle'
    $popup.Controls.Add($osCard)
    Set-RoundedControl -Control $osCard -Radius 8

    $osCardBar = New-Object System.Windows.Forms.Panel
    $osCardBar.Location = New-Object System.Drawing.Point(0, 0)
    $osCardBar.Size = New-Object System.Drawing.Size(5, 52)
    $osCardBar.BackColor = $cAccent
    $osCard.Controls.Add($osCardBar)

    $osCardTitle = New-Object System.Windows.Forms.Label
    $osCardTitle.Text = 'Imprimir OS na etiqueta'
    $osCardTitle.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $osCardTitle.ForeColor = $cAccent
    $osCardTitle.Location = New-Object System.Drawing.Point(14, 6)
    $osCardTitle.Size = New-Object System.Drawing.Size(260, 16)
    $osCard.Controls.Add($osCardTitle)

    $osCardDesc = New-Object System.Windows.Forms.Label
    $osCardDesc.Text = 'Quando marcado, imprime OS e avanca para a proxima.'
    $osCardDesc.Font = New-Object System.Drawing.Font('Segoe UI', 7)
    $osCardDesc.ForeColor = $cMuted
    $osCardDesc.Location = New-Object System.Drawing.Point(14, 26)
    $osCardDesc.Size = New-Object System.Drawing.Size(340, 14)
    $osCard.Controls.Add($osCardDesc)

    $chkOS = New-Object System.Windows.Forms.CheckBox
    $chkOS.Text = 'Ativo'
    $chkOS.Checked = $true
    $chkOS.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $chkOS.ForeColor = [System.Drawing.Color]::FromArgb(0, 220, 120)
    $chkOS.BackColor = [System.Drawing.Color]::FromArgb(12, 22, 34)
    $chkOS.FlatStyle = 'Flat'
    $chkOS.Location = New-Object System.Drawing.Point(380, 15)
    $chkOS.Size = New-Object System.Drawing.Size(82, 24)
    $chkOS.Visible = $false
    $chkOS.Add_CheckedChanged({
        $script:incluirOSAtual = [bool]$chkOS.Checked
        $osCardBar.BackColor = if ($chkOS.Checked) { [System.Drawing.Color]::FromArgb(0, 153, 255) } else { [System.Drawing.Color]::FromArgb(90, 110, 130) }
        & $script:DesenharPrevia $script:gradeAtual $script:obsAtual $script:incluirOSAtual
    })
    $osCard.Controls.Add($chkOS)

    $osToggleWrap = New-Object System.Windows.Forms.Panel
    $osToggleWrap.Location = New-Object System.Drawing.Point(380, 12)
    $osToggleWrap.Size = New-Object System.Drawing.Size(88, 26)
    $osToggleWrap.BackColor = [System.Drawing.Color]::FromArgb(26, 34, 44)
    $osToggleWrap.BorderStyle = 'None'
    $osCard.Controls.Add($osToggleWrap)
    Set-RoundedControl -Control $osToggleWrap -Radius 12

    $osToggleKnob = New-Object System.Windows.Forms.Panel
    $osToggleKnob.Size = New-Object System.Drawing.Size(20, 20)
    $osToggleKnob.Location = New-Object System.Drawing.Point(64, 3)
    $osToggleKnob.BackColor = [System.Drawing.Color]::FromArgb(216, 244, 255)
    $osToggleWrap.Controls.Add($osToggleKnob)
    Set-RoundedControl -Control $osToggleKnob -Radius 10

    $osToggleTxt = New-Object System.Windows.Forms.Label
    $osToggleTxt.Text = 'Ativo'
    $osToggleTxt.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5, [System.Drawing.FontStyle]::Bold)
    $osToggleTxt.ForeColor = [System.Drawing.Color]::FromArgb(140, 240, 192)
    $osToggleTxt.Location = New-Object System.Drawing.Point(10, 5)
    $osToggleTxt.Size = New-Object System.Drawing.Size(52, 16)
    $osToggleWrap.Controls.Add($osToggleTxt)

    $script:UpdateOsToggle = {
        if ($chkOS.Checked) {
            $osToggleWrap.BackColor = [System.Drawing.Color]::FromArgb(12, 72, 46)
            $osToggleTxt.Text = 'Ativo'
            $osToggleTxt.ForeColor = [System.Drawing.Color]::FromArgb(164, 246, 210)
            $osToggleKnob.Location = New-Object System.Drawing.Point(64, 3)
            $osToggleKnob.BackColor = [System.Drawing.Color]::FromArgb(222, 247, 255)
        } else {
            $osToggleWrap.BackColor = [System.Drawing.Color]::FromArgb(38, 42, 48)
            $osToggleTxt.Text = 'Off'
            $osToggleTxt.ForeColor = [System.Drawing.Color]::FromArgb(198, 204, 214)
            $osToggleKnob.Location = New-Object System.Drawing.Point(4, 3)
            $osToggleKnob.BackColor = [System.Drawing.Color]::FromArgb(232, 236, 242)
        }
    }
    $toggleClick = { $chkOS.Checked = -not $chkOS.Checked; & $script:UpdateOsToggle }
    $osToggleWrap.Add_Click($toggleClick)
    $osToggleTxt.Add_Click($toggleClick)
    $osToggleKnob.Add_Click($toggleClick)
    & $script:UpdateOsToggle

    # Card RMA (nao liga)
    $rnaCard = New-Object System.Windows.Forms.Panel
    $rnaCard.Location = New-Object System.Drawing.Point(16, 600)
    $rnaCard.Size = New-Object System.Drawing.Size(478, 40)
    $rnaCard.BackColor = [System.Drawing.Color]::FromArgb(16, 22, 34)
    $rnaCard.BorderStyle = 'FixedSingle'
    $popup.Controls.Add($rnaCard)
    Set-RoundedControl -Control $rnaCard -Radius 8

    $rnaBar = New-Object System.Windows.Forms.Panel
    $rnaBar.Location = New-Object System.Drawing.Point(0, 0)
    $rnaBar.Size = New-Object System.Drawing.Size(5, 40)
    $rnaBar.BackColor = [System.Drawing.Color]::FromArgb(190, 105, 22)
    $rnaCard.Controls.Add($rnaBar)

    $rnaTitle = New-Object System.Windows.Forms.Label
    $rnaTitle.Text = 'RMA'
    $rnaTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5, [System.Drawing.FontStyle]::Bold)
    $rnaTitle.ForeColor = [System.Drawing.Color]::FromArgb(255, 212, 146)
    $rnaTitle.BackColor = [System.Drawing.Color]::Transparent
    $rnaTitle.Location = New-Object System.Drawing.Point(12, 10)
    $rnaTitle.Size = New-Object System.Drawing.Size(70, 20)
    $rnaCard.Controls.Add($rnaTitle)

    $chkRNA = New-Object System.Windows.Forms.CheckBox
    $chkRNA.Checked = $false
    $chkRNA.Visible = $false
    $rnaCard.Controls.Add($chkRNA)

    $rnaResumoLbl = New-Object System.Windows.Forms.Label
    $rnaResumoLbl.Text = ''
    $rnaResumoLbl.Font = New-Object System.Drawing.Font('Segoe UI', 7.5)
    $rnaResumoLbl.ForeColor = [System.Drawing.Color]::FromArgb(216, 190, 140)
    $rnaResumoLbl.Location = New-Object System.Drawing.Point(92, 11)
    $rnaResumoLbl.Size = New-Object System.Drawing.Size(260, 18)
    $rnaResumoLbl.AutoEllipsis = $true
    $rnaResumoLbl.Anchor = 'Top,Left,Right'
    $rnaResumoLbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
    $rnaCard.Controls.Add($rnaResumoLbl)

    $rnaToggleWrap = New-Object System.Windows.Forms.Panel
    $rnaToggleWrap.Location = New-Object System.Drawing.Point(380, 7)
    $rnaToggleWrap.Size = New-Object System.Drawing.Size(88, 26)
    $rnaToggleWrap.BackColor = [System.Drawing.Color]::FromArgb(42, 40, 38)
    $rnaToggleWrap.BorderStyle = 'None'
    $rnaCard.Controls.Add($rnaToggleWrap)
    Set-RoundedControl -Control $rnaToggleWrap -Radius 12

    $rnaToggleKnob = New-Object System.Windows.Forms.Panel
    $rnaToggleKnob.Size = New-Object System.Drawing.Size(20, 20)
    $rnaToggleKnob.Location = New-Object System.Drawing.Point(4, 3)
    $rnaToggleKnob.BackColor = [System.Drawing.Color]::FromArgb(232, 236, 242)
    $rnaToggleWrap.Controls.Add($rnaToggleKnob)
    Set-RoundedControl -Control $rnaToggleKnob -Radius 10

    $rnaToggleTxt = New-Object System.Windows.Forms.Label
    $rnaToggleTxt.Text = 'Off'
    $rnaToggleTxt.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5, [System.Drawing.FontStyle]::Bold)
    $rnaToggleTxt.ForeColor = [System.Drawing.Color]::FromArgb(214, 206, 196)
    $rnaToggleTxt.Location = New-Object System.Drawing.Point(10, 5)
    $rnaToggleTxt.Size = New-Object System.Drawing.Size(52, 16)
    $rnaToggleWrap.Controls.Add($rnaToggleTxt)

    $script:UpdateRnaToggle = {
        if ($chkRNA.Checked) {
            $rnaToggleWrap.BackColor = [System.Drawing.Color]::FromArgb(92, 68, 24)
            $rnaToggleTxt.Text = 'Ativo'
            $rnaToggleTxt.ForeColor = [System.Drawing.Color]::FromArgb(255, 230, 176)
            $rnaToggleKnob.Location = New-Object System.Drawing.Point(64, 3)
            $rnaToggleKnob.BackColor = [System.Drawing.Color]::FromArgb(255, 244, 228)
        } else {
            $rnaToggleWrap.BackColor = [System.Drawing.Color]::FromArgb(42, 40, 38)
            $rnaToggleTxt.Text = 'Off'
            $rnaToggleTxt.ForeColor = [System.Drawing.Color]::FromArgb(210, 205, 198)
            $rnaToggleKnob.Location = New-Object System.Drawing.Point(4, 3)
            $rnaToggleKnob.BackColor = [System.Drawing.Color]::FromArgb(232, 236, 242)
        }
    }

    $script:AbrirRnaPopup = {
        $rnaForm = New-Object System.Windows.Forms.Form
        $rnaForm.Text = 'RMA - Defeitos identificados'
        $rnaForm.Size = New-Object System.Drawing.Size(520, 560)
        $rnaForm.StartPosition = 'CenterParent'
        $rnaForm.BackColor = $cBg
        $rnaForm.FormBorderStyle = 'FixedDialog'
        $rnaForm.MaximizeBox = $false
        $rnaForm.MinimizeBox = $false
        $rnaForm.TopMost = $true

        $rTitle = New-Object System.Windows.Forms.Label
        $rTitle.Text = 'Quais defeitos a maquina possui?'
        $rTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 13, [System.Drawing.FontStyle]::Bold)
        $rTitle.ForeColor = $cAccent
        $rTitle.Location = New-Object System.Drawing.Point(16, 12)
        $rTitle.Size = New-Object System.Drawing.Size(340, 26)
        $rnaForm.Controls.Add($rTitle)

        $rSub = New-Object System.Windows.Forms.Label
        $rSub.Text = 'Marque os componentes com defeito'
        $rSub.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
        $rSub.ForeColor = $cMuted
        $rSub.Location = New-Object System.Drawing.Point(16, 38)
        $rSub.Size = New-Object System.Drawing.Size(360, 18)
        $rnaForm.Controls.Add($rSub)

        $quickWrap = New-Object System.Windows.Forms.Panel
        $quickWrap.Location = New-Object System.Drawing.Point(16, 60)
        $quickWrap.Size = New-Object System.Drawing.Size(488, 34)
        $quickWrap.BackColor = [System.Drawing.Color]::FromArgb(10, 20, 32)
        $quickWrap.BorderStyle = 'FixedSingle'
        $rnaForm.Controls.Add($quickWrap)
        Set-RoundedControl -Control $quickWrap -Radius 8

        $opcoesRNA = @('Tela','Tampa frontal','Tampa traseira','Teclado','Touchpad','Carcaca','Dobradiças','Rede','USB','Camera','Gravador de voz','Microfone')
        $cardsRNA = @()
        $xOpt = 16; $yOpt = 102
        $col = 0
        $applyVisual = {
            param($it)
            if ($it.Selecionado) {
                $it.Card.BackColor = [System.Drawing.Color]::FromArgb(68, 22, 28)
                $it.Label.ForeColor = [System.Drawing.Color]::FromArgb(255, 220, 224)
            } else {
                $it.Card.BackColor = [System.Drawing.Color]::FromArgb(14, 24, 36)
                $it.Label.ForeColor = [System.Drawing.Color]::FromArgb(200, 224, 245)
            }
        }
        foreach ($o in $opcoesRNA) {
            $rowCard = New-Object System.Windows.Forms.Panel
            $rowCard.Location = New-Object System.Drawing.Point($xOpt, $yOpt)
            $rowCard.Size = New-Object System.Drawing.Size(228, 30)
            $rowCard.BackColor = [System.Drawing.Color]::FromArgb(14, 24, 36)
            $rowCard.BorderStyle = 'FixedSingle'
            $rnaForm.Controls.Add($rowCard)
            Set-RoundedControl -Control $rowCard -Radius 7

            $lblItem = New-Object System.Windows.Forms.Label
            $lblItem.Text = $o
            $lblItem.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9, [System.Drawing.FontStyle]::Bold)
            $lblItem.ForeColor = [System.Drawing.Color]::FromArgb(200, 224, 245)
            $lblItem.BackColor = [System.Drawing.Color]::Transparent
            $lblItem.Location = New-Object System.Drawing.Point(10, 5)
            $lblItem.Size = New-Object System.Drawing.Size(208, 20)
            $lblItem.Cursor = [System.Windows.Forms.Cursors]::Hand
            $rowCard.Controls.Add($lblItem)

            $itemState = [pscustomobject]@{
                Nome = $o
                Card = $rowCard
                Label = $lblItem
                Selecionado = ($script:rnaItensOk -contains $o)
            }
            $cardsRNA += $itemState

            & $applyVisual $itemState

            $toggleItem = {
                $itemState.Selecionado = -not $itemState.Selecionado
                & $applyVisual $itemState
            }.GetNewClosure()
            $rowCard.Cursor = [System.Windows.Forms.Cursors]::Hand
            $rowCard.Add_Click($toggleItem)
            $lblItem.Add_Click($toggleItem)

            $yOpt += 34
            if ($yOpt -gt 304 -and $col -eq 0) { $yOpt = 102; $xOpt = 258; $col = 1 }
        }

        $btnNenhum = New-Object System.Windows.Forms.Button
        $btnNenhum.Text = 'Nenhum defeito'
        $btnNenhum.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5, [System.Drawing.FontStyle]::Bold)
        $btnNenhum.ForeColor = [System.Drawing.Color]::FromArgb(214, 226, 240)
        $btnNenhum.BackColor = [System.Drawing.Color]::FromArgb(28, 36, 50)
        $btnNenhum.FlatStyle = 'Flat'
        $btnNenhum.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(66, 84, 108)
        $btnNenhum.Location = New-Object System.Drawing.Point(10, 4)
        $btnNenhum.Size = New-Object System.Drawing.Size(92, 24)
        $btnNenhum.Add_Click({
            foreach ($it in $cardsRNA) {
                $it.Selecionado = $false
                & $applyVisual $it
            }
        })
        $quickWrap.Controls.Add($btnNenhum)
        Set-RoundedControl -Control $btnNenhum -Radius 7

        $btnTodos = New-Object System.Windows.Forms.Button
        $btnTodos.Text = 'Todos defeitos'
        $btnTodos.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5, [System.Drawing.FontStyle]::Bold)
        $btnTodos.ForeColor = [System.Drawing.Color]::FromArgb(255, 226, 230)
        $btnTodos.BackColor = [System.Drawing.Color]::FromArgb(68, 22, 28)
        $btnTodos.FlatStyle = 'Flat'
        $btnTodos.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(126, 42, 52)
        $btnTodos.Location = New-Object System.Drawing.Point(108, 4)
        $btnTodos.Size = New-Object System.Drawing.Size(92, 24)
        $btnTodos.Add_Click({
            foreach ($it in $cardsRNA) {
                $it.Selecionado = $true
                & $applyVisual $it
            }
        })
        $quickWrap.Controls.Add($btnTodos)
        Set-RoundedControl -Control $btnTodos -Radius 7

        $btnRnaCancel = New-Object System.Windows.Forms.Button
        $btnRnaCancel.Text = 'Cancelar'
        $btnRnaCancel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5, [System.Drawing.FontStyle]::Bold)
        $btnRnaCancel.ForeColor = [System.Drawing.Color]::FromArgb(220, 130, 130)
        $btnRnaCancel.BackColor = [System.Drawing.Color]::FromArgb(34, 12, 18)
        $btnRnaCancel.FlatStyle = 'Flat'
        $btnRnaCancel.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(100, 34, 42)
        $btnRnaCancel.Location = New-Object System.Drawing.Point(16, 500)
        $btnRnaCancel.Size = New-Object System.Drawing.Size(148, 36)
        $btnRnaCancel.Add_Click({ $rnaForm.DialogResult = 'Cancel'; $rnaForm.Close() })
        $rnaForm.Controls.Add($btnRnaCancel)
        Set-RoundedControl -Control $btnRnaCancel -Radius 7

        $btnRnaSave = New-Object System.Windows.Forms.Button
        $btnRnaSave.Text = 'Salvar'
        $btnRnaSave.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5, [System.Drawing.FontStyle]::Bold)
        $btnRnaSave.ForeColor = [System.Drawing.Color]::White
        $btnRnaSave.BackColor = [System.Drawing.Color]::FromArgb(0, 112, 64)
        $btnRnaSave.FlatStyle = 'Flat'
        $btnRnaSave.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(0, 180, 95)
        $btnRnaSave.Location = New-Object System.Drawing.Point(356, 500)
        $btnRnaSave.Size = New-Object System.Drawing.Size(148, 36)
        $btnRnaSave.Add_Click({
            $sel = @($cardsRNA | Where-Object { $_.Selecionado } | ForEach-Object { [string]$_.Nome })
            $script:rnaItensOk = $sel
            $rnaForm.DialogResult = 'OK'
            $rnaForm.Close()
        })
        $rnaForm.Controls.Add($btnRnaSave)
        Set-RoundedControl -Control $btnRnaSave -Radius 7

        return $rnaForm.ShowDialog($popup)
    }

    $chkRNA.Add_CheckedChanged({
        if ($chkRNA.Checked) {
            $script:rnaAtivo = $true
            $resRna = & $script:AbrirRnaPopup
            if ($resRna -ne 'OK') {
                $script:rnaAtivo = $false
                $script:rnaItensOk = @()
                $chkRNA.Checked = $false
                return
            }
        } else {
            $script:rnaAtivo = $false
            $script:rnaItensOk = @()
        }
        if ($script:rnaAtivo -and $script:rnaItensOk.Count -gt 0) {
            $rnaResumoLbl.Text = ($script:rnaItensOk -join ', ')
            if ($rnaResumoLbl.Text.Length -gt 22) { $rnaResumoLbl.Text = $rnaResumoLbl.Text.Substring(0,22) + '...' }
        } else {
            $rnaResumoLbl.Text = ''
        }
        & $script:DesenharPrevia $script:gradeAtual (& $script:GetObsImpressao) $script:incluirOSAtual
        & $script:UpdateConfirmState
    })
    $rnaToggleClick = { $chkRNA.Checked = -not $chkRNA.Checked; & $script:UpdateRnaToggle }
    $rnaToggleWrap.Add_Click($rnaToggleClick)
    $rnaToggleTxt.Add_Click($rnaToggleClick)
    $rnaToggleKnob.Add_Click($rnaToggleClick)
    & $script:UpdateRnaToggle

    if ($false) {
    # Triagem Altertag (desativada)
    $triCard = New-Object System.Windows.Forms.Panel
    $triCard.Location = New-Object System.Drawing.Point(16, 476)
    $triCard.Size = New-Object System.Drawing.Size(478, 134)
    $triCard.BackColor = [System.Drawing.Color]::FromArgb(12, 22, 34)
    $triCard.BorderStyle = 'FixedSingle'
    $popup.Controls.Add($triCard)
    $triCard.Visible = $false

    $triBar = New-Object System.Windows.Forms.Panel
    $triBar.Location = New-Object System.Drawing.Point(0, 0)
    $triBar.Size = New-Object System.Drawing.Size(4, 134)
    $triBar.BackColor = $cYellow
    $triCard.Controls.Add($triBar)

    $triTitle = New-Object System.Windows.Forms.Label
    $triTitle.Text = 'Triagem Altertag'
    $triTitle.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $triTitle.ForeColor = $cYellow
    $triTitle.Location = New-Object System.Drawing.Point(12, 6)
    $triTitle.Size = New-Object System.Drawing.Size(160, 18)
    $triCard.Controls.Add($triTitle)

    $cmbTecnico = New-Object System.Windows.Forms.ComboBox
    $cmbTecnico.DropDownStyle = 'DropDownList'
    $cmbTecnico.BackColor = [System.Drawing.Color]::FromArgb(14, 24, 36)
    $cmbTecnico.ForeColor = [System.Drawing.Color]::White
    $cmbTecnico.Location = New-Object System.Drawing.Point(14, 30)
    $cmbTecnico.Size = New-Object System.Drawing.Size(120, 24)
    [void]$cmbTecnico.Items.Add('Hyuri')
    [void]$cmbTecnico.Items.Add('Vitor')
    [void]$cmbTecnico.Items.Add('Lucas')
    $cmbTecnico.SelectedIndex = 1
    $triCard.Controls.Add($cmbTecnico)

    $produtoBox = New-Object System.Windows.Forms.TextBox
    $produtoBox.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $produtoBox.BackColor = [System.Drawing.Color]::FromArgb(14, 24, 36)
    $produtoBox.ForeColor = [System.Drawing.Color]::FromArgb(190, 220, 238)
    $produtoBox.BorderStyle = 'FixedSingle'
    $produtoBox.Location = New-Object System.Drawing.Point(146, 31)
    $produtoBox.Size = New-Object System.Drawing.Size(230, 23)
    $produtoBox.Text = ''
    $triCard.Controls.Add($produtoBox)

    $btnBuscarProduto = New-Object System.Windows.Forms.Button
    $btnBuscarProduto.Text = 'Buscar'
    $btnBuscarProduto.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
    $btnBuscarProduto.ForeColor = [System.Drawing.Color]::White
    $btnBuscarProduto.BackColor = [System.Drawing.Color]::FromArgb(20, 58, 72)
    $btnBuscarProduto.FlatStyle = 'Flat'
    $btnBuscarProduto.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(0, 153, 255)
    $btnBuscarProduto.Location = New-Object System.Drawing.Point(384, 30)
    $btnBuscarProduto.Size = New-Object System.Drawing.Size(80, 25)
    $triCard.Controls.Add($btnBuscarProduto)

    $servicoBox = New-Object System.Windows.Forms.TextBox
    $servicoBox.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $servicoBox.BackColor = [System.Drawing.Color]::FromArgb(14, 24, 36)
    $servicoBox.ForeColor = [System.Drawing.Color]::FromArgb(190, 220, 238)
    $servicoBox.BorderStyle = 'FixedSingle'
    $servicoBox.Location = New-Object System.Drawing.Point(146, 62)
    $servicoBox.Size = New-Object System.Drawing.Size(230, 23)
    $servicoBox.Text = ''
    $triCard.Controls.Add($servicoBox)

    $servicoLbl = New-Object System.Windows.Forms.Label
    $servicoLbl.Text = 'Servico extra'
    $servicoLbl.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
    $servicoLbl.ForeColor = [System.Drawing.Color]::FromArgb(160, 190, 215)
    $servicoLbl.Location = New-Object System.Drawing.Point(14, 65)
    $servicoLbl.Size = New-Object System.Drawing.Size(120, 18)
    $triCard.Controls.Add($servicoLbl)

    $btnBuscarServico = New-Object System.Windows.Forms.Button
    $btnBuscarServico.Text = 'Buscar'
    $btnBuscarServico.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
    $btnBuscarServico.ForeColor = [System.Drawing.Color]::White
    $btnBuscarServico.BackColor = [System.Drawing.Color]::FromArgb(58, 42, 12)
    $btnBuscarServico.FlatStyle = 'Flat'
    $btnBuscarServico.FlatAppearance.BorderColor = $cYellow
    $btnBuscarServico.Location = New-Object System.Drawing.Point(384, 61)
    $btnBuscarServico.Size = New-Object System.Drawing.Size(80, 25)
    $triCard.Controls.Add($btnBuscarServico)

    $servicosNomes = @('Troca Bateria', 'Troca Memoria', 'Troca SSD', 'Troca Tela')
    $sx = 14
    foreach ($svc in $servicosNomes) {
        $chkSvc = New-Object System.Windows.Forms.CheckBox
        $chkSvc.Text = $svc
        $chkSvc.Font = New-Object System.Drawing.Font('Segoe UI', 7)
        $chkSvc.ForeColor = [System.Drawing.Color]::FromArgb(180, 210, 230)
        $chkSvc.BackColor = [System.Drawing.Color]::FromArgb(12, 22, 34)
        $chkSvc.FlatStyle = 'Flat'
        $chkSvc.Location = New-Object System.Drawing.Point($sx, 100)
        $chkSvc.Size = New-Object System.Drawing.Size(112, 20)
        $triCard.Controls.Add($chkSvc)
        $sx += 112
    }

    # Botoes
    $btnCancelar = New-Object System.Windows.Forms.Button
    $btnCancelar.Text = 'Cancelar'
    $btnCancelar.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $btnCancelar.ForeColor = [System.Drawing.Color]::FromArgb(180, 60, 60)
    $btnCancelar.BackColor = [System.Drawing.Color]::FromArgb(20, 10, 12)
    $btnCancelar.FlatStyle = 'Flat'
    $btnCancelar.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(80, 30, 30)
    $btnCancelar.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(34, 12, 18)
    $btnCancelar.Location = New-Object System.Drawing.Point(16, 634); $btnCancelar.Size = New-Object System.Drawing.Size(150, 44)
    $btnCancelar.Add_Click({ $popup.DialogResult = 'Cancel'; $popup.Close() })
    $popup.Controls.Add($btnCancelar)

    $btnTriagemAltertag = New-Object System.Windows.Forms.Button
    $btnTriagemAltertag.Text = 'Cadastrar Triagem'
    $btnTriagemAltertag.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $btnTriagemAltertag.ForeColor = [System.Drawing.Color]::FromArgb(255, 230, 170)
    $btnTriagemAltertag.BackColor = [System.Drawing.Color]::FromArgb(42, 30, 12)
    $btnTriagemAltertag.FlatStyle = 'Flat'
    $btnTriagemAltertag.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(150, 105, 30)
    $btnTriagemAltertag.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(58, 40, 16)
    $btnTriagemAltertag.Location = New-Object System.Drawing.Point(174, 650)
    $btnTriagemAltertag.Size = New-Object System.Drawing.Size(150, 44)
    $popup.Controls.Add($btnTriagemAltertag)
    $btnTriagemAltertag.Visible = $false
    $btnTriagemAltertag.Enabled = $false

    $btnConfirmar = New-Object System.Windows.Forms.Button
    $btnConfirmar.Text = 'Confirmar e Imprimir'
    $btnConfirmar.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $btnConfirmar.ForeColor = [System.Drawing.Color]::White
    $btnConfirmar.BackColor = [System.Drawing.Color]::FromArgb(0, 112, 64)
    $btnConfirmar.FlatStyle = 'Flat'
    $btnConfirmar.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(0, 180, 95)
    $btnConfirmar.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(0, 135, 76)
    $btnConfirmar.Location = New-Object System.Drawing.Point(332, 650); $btnConfirmar.Size = New-Object System.Drawing.Size(162, 44)
    $btnConfirmar.Add_Click({
        $obsTexto = if ($script:obsAtual) { $script:obsAtual.Trim() } else { '' }
        if ($script:gradeAtual -in @('B', 'C', 'D') -and [string]::IsNullOrWhiteSpace($obsTexto)) {
            [System.Windows.Forms.MessageBox]::Show(
                "Para imprimir com grade $($script:gradeAtual), descreva os detalhes encontrados em OBSERVACOES.",
                'Observacao obrigatoria',
                'OK',
                'Warning'
            ) | Out-Null
            $obsBox.Focus() | Out-Null
            return
        }
        $popup.DialogResult = 'OK'
        $popup.Close()
    })
    $popup.Controls.Add($btnConfirmar)

    $buscarAltertag = {
        param([string]$tipo, [System.Windows.Forms.TextBox]$targetBox)
        $termo = $targetBox.Text.Trim()
        if (-not $termo) {
            [System.Windows.Forms.MessageBox]::Show('Digite um termo para buscar no Altertag.', 'Busca Altertag', 'OK', 'Warning') | Out-Null
            return
        }
        $btnBuscarProduto.Enabled = $false
        $btnBuscarServico.Enabled = $false
        $textoOriginalProduto = $btnBuscarProduto.Text
        $textoOriginalServico = $btnBuscarServico.Text
        if ($tipo -eq 'produto') { $btnBuscarProduto.Text = 'Buscando...' } else { $btnBuscarServico.Text = 'Buscando...' }
        $popup.UseWaitCursor = $true
        [System.Windows.Forms.Application]::DoEvents()
        try {
            $urlBusca = '{0}/buscar-opcoes-altertag' -f (Get-ServidorBaseUrl)
            $payload = @{ tipo = $tipo; termo = $termo } | ConvertTo-Json -Compress
            $respBusca = Invoke-RestMethod -Uri $urlBusca -Method Post -Body $payload -ContentType 'application/json; charset=utf-8' -TimeoutSec 25 -ErrorAction Stop
            $opcoes = @($respBusca.opcoes)
            if ($opcoes.Count -eq 0) {
                [System.Windows.Forms.MessageBox]::Show('Nenhuma opcao encontrada no Altertag para esse termo.', 'Busca Altertag', 'OK', 'Information') | Out-Null
                return
            }

            $pick = New-Object System.Windows.Forms.Form
            $pick.Text = "Selecionar $tipo"
            $pick.Size = New-Object System.Drawing.Size(560, 360)
            $pick.StartPosition = 'CenterParent'
            $pick.BackColor = [System.Drawing.Color]::FromArgb(8, 12, 18)
            $pick.FormBorderStyle = 'FixedDialog'
            $pick.MaximizeBox = $false
            $pick.MinimizeBox = $false
            $pick.TopMost = $true
            $pick.ShowInTaskbar = $false

            $list = New-Object System.Windows.Forms.ListBox
            $list.Font = New-Object System.Drawing.Font('Segoe UI', 9)
            $list.BackColor = [System.Drawing.Color]::FromArgb(14, 24, 36)
            $list.ForeColor = [System.Drawing.Color]::White
            $list.Location = New-Object System.Drawing.Point(14, 14)
            $list.Size = New-Object System.Drawing.Size(516, 250)
            foreach ($op in $opcoes) { [void]$list.Items.Add([string]$op) }
            if ($list.Items.Count -gt 0) { $list.SelectedIndex = 0 }
            $pick.Controls.Add($list)
            $pick.Add_Shown({
                $pick.Activate() | Out-Null
                $list.Focus() | Out-Null
            })

            $okPick = New-Object System.Windows.Forms.Button
            $okPick.Text = 'Usar selecionado'
            $okPick.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
            $okPick.ForeColor = [System.Drawing.Color]::White
            $okPick.BackColor = [System.Drawing.Color]::FromArgb(0, 112, 64)
            $okPick.FlatStyle = 'Flat'
            $okPick.Location = New-Object System.Drawing.Point(316, 276)
            $okPick.Size = New-Object System.Drawing.Size(214, 34)
            $okPick.Add_Click({ $pick.DialogResult = 'OK'; $pick.Close() })
            $pick.Controls.Add($okPick)

            $cancelPick = New-Object System.Windows.Forms.Button
            $cancelPick.Text = 'Cancelar'
            $cancelPick.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
            $cancelPick.ForeColor = [System.Drawing.Color]::FromArgb(220, 120, 120)
            $cancelPick.BackColor = [System.Drawing.Color]::FromArgb(34, 12, 18)
            $cancelPick.FlatStyle = 'Flat'
            $cancelPick.Location = New-Object System.Drawing.Point(14, 276)
            $cancelPick.Size = New-Object System.Drawing.Size(140, 34)
            $cancelPick.Add_Click({ $pick.DialogResult = 'Cancel'; $pick.Close() })
            $pick.Controls.Add($cancelPick)

            if ($pick.ShowDialog($popup) -eq 'OK' -and $list.SelectedItem) {
                $selecionado = [string]$list.SelectedItem
                $targetBox.Tag = $selecionado
                if ($tipo -eq 'produto') {
                    $targetBox.Text = Extract-AltertagCodigo -Texto $selecionado
                } else {
                    $targetBox.Text = $selecionado
                }
            }
        } catch {
            $msg = $_.Exception.Message
            try {
                if ($_.Exception.Response) {
                    $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                    $body = $reader.ReadToEnd()
                    $reader.Close()
                    if ($body) { $msg += "`n$body" }
                }
            } catch {}
            [System.Windows.Forms.MessageBox]::Show("Falha ao buscar no Altertag:`n$msg`n`nDica: tente buscar por 'Notebook Lenovo E14' quando usar modelos curtos como E14/T14.", 'Busca Altertag', 'OK', 'Warning') | Out-Null
        } finally {
            $popup.UseWaitCursor = $false
            $btnBuscarProduto.Enabled = $true
            $btnBuscarServico.Enabled = $true
            $btnBuscarProduto.Text = $textoOriginalProduto
            $btnBuscarServico.Text = $textoOriginalServico
            [System.Windows.Forms.Application]::DoEvents()
        }
    }

    $btnBuscarProduto.Add_Click({ & $buscarAltertag 'produto' $produtoBox })
    $btnBuscarServico.Add_Click({ & $buscarAltertag 'servico' $servicoBox })

    $triagemJobId = $null
    $triagemPollTimer = New-Object System.Windows.Forms.Timer
    $triagemPollTimer.Interval = 2500
    $triagemPollTimer.Add_Tick({
        if (-not $triagemJobId) { return }
        try {
            $urlStatusTriagem = ('{0}/triagem/status?id={1}' -f (Get-ServidorBaseUrl), $triagemJobId)
            $st = Invoke-RestMethod -Uri $urlStatusTriagem -Method Get -TimeoutSec 8 -ErrorAction Stop
            if (-not $st -or [string]$st.status -ne 'ok') { return }
            $ts = [string]$st.triagemStatus
            if ($ts -eq 'queued' -or $ts -eq 'running') {
                $btnTriagemAltertag.Text = "Na fila ($([int]$st.tentativas)/$([int]$st.maxTentativas))"
                return
            }
            $triagemPollTimer.Stop()
            if ($ts -eq 'ok') {
                if ($st.osNumero -and [string]$st.osNumero -match '^\d+$') {
                    Set-OsNumeroAtual -Numero ([int]$st.osNumero)
                    $script:osDefinidaPorTriagem = $true
                }
                $btnTriagemAltertag.Text = 'OS capturada'
                [System.Windows.Forms.MessageBox]::Show(
                    "Triagem concluida pelo agente do PC principal.`n`nOS: $(Format-OsCodigo -Numero $script:osNumero)",
                    'Triagem concluida',
                    'OK',
                    'Information'
                ) | Out-Null
            } else {
                $erroMsg = if ($st.erro) { [string]$st.erro } else { 'Falha sem detalhe.' }
                $btnTriagemAltertag.Text = 'Falha'
                [System.Windows.Forms.MessageBox]::Show("Triagem nao concluida:`n$erroMsg", 'Falha na triagem', 'OK', 'Warning') | Out-Null
            }
            $btnTriagemAltertag.Enabled = $true
            $triagemJobId = $null
        } catch {
            # segue tentando; evita quebrar o fluxo por falha pontual de rede
        }
    })

    $btnTriagemAltertag.Add_Click({
        try {
            # Novo fluxo: enfileira no agente do servidor e acompanha por polling.
            $produtoCodQ = Extract-AltertagCodigo -Texto $produtoBox.Text
            $assinaturaProdutoQ = Get-ProdutoAssinatura -Modelo $info.Modelo -Cpu $info.CPU -Ram $info.RAM -Disco ($info.Discos -split $NL | Select-Object -First 1)
            if (-not $produtoCodQ -and $script:produtoMemoria.ContainsKey($assinaturaProdutoQ)) {
                $produtoCodQ = [string]$script:produtoMemoria[$assinaturaProdutoQ]
                $produtoBox.Text = $produtoCodQ
            }
            $servicosSelQ = @()
            foreach ($ctrlQ in $triCard.Controls) {
                if ($ctrlQ -is [System.Windows.Forms.CheckBox] -and $ctrlQ.Checked) { $servicosSelQ += [string]$ctrlQ.Text }
            }
            if ($servicoBox.Text.Trim()) { $servicosSelQ += $servicoBox.Text.Trim() }

            $btnTriagemAltertag.Enabled = $false
            $btnTriagemAltertag.Text = 'Enfileirando...'
            [System.Windows.Forms.Application]::DoEvents()
            $baseUrlQ = Get-ServidorBaseUrl
            Invoke-RestMethod -Uri ('{0}/status' -f $baseUrlQ) -Method Get -TimeoutSec 6 -ErrorAction Stop | Out-Null

            $bodyQ = @{
                serial        = $info.Serial
                tecnico       = [string]$cmbTecnico.SelectedItem
                produtoCodigo = $produtoCodQ
                grade         = $script:gradeAtual
                servicos      = $servicosSelQ
                modelo        = $info.Modelo
                cpu           = $info.CPU
                ram           = $info.RAM
                disco         = ($info.Discos -split $NL | Select-Object -First 1)
            } | ConvertTo-Json -Compress

            $respQ = Invoke-RestMethod -Uri ('{0}/triagem/enfileirar' -f $baseUrlQ) -Method Post -Body $bodyQ -ContentType 'application/json; charset=utf-8' -TimeoutSec 12 -ErrorAction Stop
            if ([string]$respQ.status -eq 'ok' -and $respQ.jobId) {
                if ($respQ.produtoCodigo) {
                    $produtoBox.Text = [string]$respQ.produtoCodigo
                    $script:produtoMemoria[$assinaturaProdutoQ] = [string]$respQ.produtoCodigo
                    Save-ProdutoMemoria
                }
                $triagemJobId = [string]$respQ.jobId
                $btnTriagemAltertag.Text = 'Na fila (0/4)'
                $triagemPollTimer.Start()
                return
            }
            if ([string]$respQ.status -eq 'pendente') {
                $det = if ($respQ.opcoesProdutoCodigo) { (@($respQ.opcoesProdutoCodigo) -join ', ') } else { '' }
                [System.Windows.Forms.MessageBox]::Show("Triagem pendente:`n$($respQ.mensagem)`n$det", 'Triagem pendente', 'OK', 'Warning') | Out-Null
                $btnTriagemAltertag.Text = 'Pendente'
                $btnTriagemAltertag.Enabled = $true
                return
            }
            [System.Windows.Forms.MessageBox]::Show("Triagem nao concluida:`n$($respQ.mensagem)", 'Falha na triagem', 'OK', 'Warning') | Out-Null
            $btnTriagemAltertag.Text = 'Falha'
            $btnTriagemAltertag.Enabled = $true
            return
        } catch {
            $msgErr = $_.Exception.Message
            try {
                if ($_.Exception.Response) {
                    $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                    $bodyErr = $reader.ReadToEnd()
                    $reader.Close()
                    if ($bodyErr) { $msgErr += "`n$bodyErr" }
                }
            } catch {}
            [System.Windows.Forms.MessageBox]::Show("Falha ao enviar triagem:`n$msgErr", 'Erro na triagem', 'OK', 'Warning') | Out-Null
            $btnTriagemAltertag.Text = 'Cadastrar Triagem'
            $btnTriagemAltertag.Enabled = $true
        }
    })
    }

    # Botoes da previa (ativos mesmo com triagem desativada)
    $btnCancelar = New-Object System.Windows.Forms.Button
    $btnCancelar.Text = 'Cancelar'
    $btnCancelar.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $btnCancelar.ForeColor = [System.Drawing.Color]::FromArgb(180, 60, 60)
    $btnCancelar.BackColor = [System.Drawing.Color]::FromArgb(20, 10, 12)
    $btnCancelar.FlatStyle = 'Flat'
    $btnCancelar.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(80, 30, 30)
    $btnCancelar.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(34, 12, 18)
    $btnCancelar.Location = New-Object System.Drawing.Point(16, 650)
    $btnCancelar.Size = New-Object System.Drawing.Size(158, 44)
    $btnCancelar.Add_Click({ $popup.DialogResult = 'Cancel'; $popup.Close() })
    $popup.Controls.Add($btnCancelar)
    Set-RoundedControl -Control $btnCancelar -Radius 8

    $btnManual = New-Object System.Windows.Forms.Button
    $btnManual.Text = 'Adicionar Manual'
    $btnManual.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5, [System.Drawing.FontStyle]::Bold)
    $btnManual.ForeColor = [System.Drawing.Color]::FromArgb(255, 230, 170)
    $btnManual.BackColor = [System.Drawing.Color]::FromArgb(42, 30, 12)
    $btnManual.FlatStyle = 'Flat'
    $btnManual.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(150, 105, 30)
    $btnManual.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(58, 40, 16)
    $btnManual.Location = New-Object System.Drawing.Point(176, 650)
    $btnManual.Size = New-Object System.Drawing.Size(158, 44)
    $btnManual.Add_Click({
        $manualForm = New-Object System.Windows.Forms.Form
        $manualForm.Text = 'Preencher dados manualmente'
        $manualForm.Size = New-Object System.Drawing.Size(440, 340)
        $manualForm.StartPosition = 'CenterParent'
        $manualForm.BackColor = $cBg
        $manualForm.FormBorderStyle = 'FixedDialog'
        $manualForm.MaximizeBox = $false
        $manualForm.MinimizeBox = $false
        $manualForm.TopMost = $true

        function New-ManualField {
            param([string]$titulo, [int]$y, [string]$valor)
            $lbl = New-Object System.Windows.Forms.Label
            $lbl.Text = $titulo
            $lbl.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
            $lbl.ForeColor = $cAccent
            $lbl.Location = New-Object System.Drawing.Point(16, $y)
            $lbl.Size = New-Object System.Drawing.Size(160, 18)
            $manualForm.Controls.Add($lbl)

            $txt = New-Object System.Windows.Forms.TextBox
            $txt.Font = New-Object System.Drawing.Font('Segoe UI', 9)
            $txt.BackColor = [System.Drawing.Color]::FromArgb(14, 24, 36)
            $txt.ForeColor = [System.Drawing.Color]::FromArgb(190, 220, 238)
            $txt.BorderStyle = 'FixedSingle'
            $txt.Location = New-Object System.Drawing.Point(16, ($y + 18))
            $txt.Size = New-Object System.Drawing.Size(392, 24)
            $txt.Text = $valor
            $manualForm.Controls.Add($txt)
            return $txt
        }

        $txtModelo = New-ManualField 'Nome do modelo' 12  $script:modeloEtiqueta
        $txtSerial = New-ManualField 'Serial'         62  $script:serialEtiqueta
        $txtCpu    = New-ManualField 'Processador'    112 $script:cpuEtiqueta
        $txtMem    = New-ManualField 'Memoria'        162 $script:memEtiqueta
        $txtRam    = New-ManualField 'RAM'            212 $script:ramEtiqueta

        $btnManualCancelar = New-Object System.Windows.Forms.Button
        $btnManualCancelar.Text = 'Cancelar'
        $btnManualCancelar.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
        $btnManualCancelar.ForeColor = [System.Drawing.Color]::FromArgb(180, 60, 60)
        $btnManualCancelar.BackColor = [System.Drawing.Color]::FromArgb(20, 10, 12)
        $btnManualCancelar.FlatStyle = 'Flat'
        $btnManualCancelar.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(80, 30, 30)
        $btnManualCancelar.Location = New-Object System.Drawing.Point(16, 260)
        $btnManualCancelar.Size = New-Object System.Drawing.Size(120, 34)
        $btnManualCancelar.Add_Click({ $manualForm.DialogResult = 'Cancel'; $manualForm.Close() })
        $manualForm.Controls.Add($btnManualCancelar)

        $btnManualSalvar = New-Object System.Windows.Forms.Button
        $btnManualSalvar.Text = 'Salvar dados'
        $btnManualSalvar.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
        $btnManualSalvar.ForeColor = [System.Drawing.Color]::White
        $btnManualSalvar.BackColor = [System.Drawing.Color]::FromArgb(0, 112, 64)
        $btnManualSalvar.FlatStyle = 'Flat'
        $btnManualSalvar.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(0, 180, 95)
        $btnManualSalvar.Location = New-Object System.Drawing.Point(286, 260)
        $btnManualSalvar.Size = New-Object System.Drawing.Size(122, 34)
        $btnManualSalvar.Add_Click({
            $modelo = $txtModelo.Text.Trim()
            $serial = $txtSerial.Text.Trim()
            $cpu    = $txtCpu.Text.Trim()
            $mem    = $txtMem.Text.Trim()
            $ram    = $txtRam.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($modelo) -or
                [string]::IsNullOrWhiteSpace($serial) -or
                [string]::IsNullOrWhiteSpace($cpu) -or
                [string]::IsNullOrWhiteSpace($mem) -or
                [string]::IsNullOrWhiteSpace($ram)) {
                [System.Windows.Forms.MessageBox]::Show(
                    'Preencha todos os campos para salvar os dados manuais.',
                    'Campos obrigatorios',
                    'OK',
                    'Warning'
                ) | Out-Null
                return
            }
            $script:modeloEtiqueta = $modelo
            $script:serialEtiqueta = $serial
            $script:cpuEtiqueta    = $cpu
            $script:memEtiqueta    = $mem
            $script:ramEtiqueta    = $ram
            $script:modoManualEtiqueta = $true
            $manualForm.DialogResult = 'OK'
            $manualForm.Close()
        })
        $manualForm.Controls.Add($btnManualSalvar)

        $resManual = $manualForm.ShowDialog($popup)
        if ($resManual -eq 'OK') {
            & $script:DesenharPrevia $script:gradeAtual $script:obsAtual $script:incluirOSAtual
        }
    })
    $popup.Controls.Add($btnManual)
    Set-RoundedControl -Control $btnManual -Radius 8

    $btnAuto = New-Object System.Windows.Forms.Button
    $btnAuto.Text = 'Usar leitura automatica'
    $btnAuto.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5, [System.Drawing.FontStyle]::Bold)
    $btnAuto.ForeColor = [System.Drawing.Color]::FromArgb(180, 210, 235)
    $btnAuto.BackColor = [System.Drawing.Color]::FromArgb(16, 26, 38)
    $btnAuto.FlatStyle = 'Flat'
    $btnAuto.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(70, 105, 135)
    $btnAuto.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(24, 38, 54)
    $btnAuto.Location = New-Object System.Drawing.Point(176, 650)
    $btnAuto.Size = New-Object System.Drawing.Size(158, 28)
    $btnAuto.Add_Click({
        $script:modeloEtiqueta = $info.Modelo
        $script:serialEtiqueta = $info.Serial
        $script:cpuEtiqueta    = $cpuCurto
        $script:memEtiqueta    = $discoCurto
        $script:ramEtiqueta    = $ramCurto
        $script:modoManualEtiqueta = $false
        & $script:DesenharPrevia $script:gradeAtual (& $script:GetObsImpressao) $script:incluirOSAtual
    })
    $popup.Controls.Add($btnAuto)
    Set-RoundedControl -Control $btnAuto -Radius 7

    $btnConfirmar = New-Object System.Windows.Forms.Button
    $btnConfirmar.Text = 'Confirmar e Imprimir'
    $btnConfirmar.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5, [System.Drawing.FontStyle]::Bold)
    $btnConfirmar.ForeColor = [System.Drawing.Color]::White
    $btnConfirmar.BackColor = [System.Drawing.Color]::FromArgb(0, 112, 64)
    $btnConfirmar.FlatStyle = 'Flat'
    $btnConfirmar.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(0, 180, 95)
    $btnConfirmar.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(0, 135, 76)
    $btnConfirmar.Location = New-Object System.Drawing.Point(336, 650)
    $btnConfirmar.Size = New-Object System.Drawing.Size(158, 44)
    $script:UpdateConfirmState = {
        $obsTextoSt = if ($script:obsAtual) { $script:obsAtual.Trim() } else { '' }
        $needsObs = ($script:gradeAtual -in @('B', 'C', 'D'))
        if ($needsObs -and [string]::IsNullOrWhiteSpace($obsTextoSt)) {
            $btnConfirmar.Text = 'Preencha OBS'
            $btnConfirmar.BackColor = [System.Drawing.Color]::FromArgb(95, 72, 12)
            $btnConfirmar.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(170, 128, 26)
        } else {
            $btnConfirmar.Text = 'Pronto para Imprimir'
            $btnConfirmar.BackColor = [System.Drawing.Color]::FromArgb(0, 112, 64)
            $btnConfirmar.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(0, 180, 95)
        }
    }
    & $script:UpdateConfirmState
    $btnConfirmar.Add_Click({
        $btnConfirmar.Text = 'Validando...'
        [System.Windows.Forms.Application]::DoEvents()
        $obsTexto = if ($script:obsAtual) { $script:obsAtual.Trim() } else { '' }
        if ($script:gradeAtual -in @('B', 'C', 'D') -and [string]::IsNullOrWhiteSpace($obsTexto)) {
            [System.Windows.Forms.MessageBox]::Show(
                "Para imprimir com grade $($script:gradeAtual), voce precisa preencher OBSERVACOES com os detalhes encontrados na maquina.",
                'Observacao obrigatoria',
                'OK',
                'Warning'
            ) | Out-Null
            & $script:UpdateConfirmState
            $obsBox.Focus() | Out-Null
            return
        }
        $popup.DialogResult = 'OK'
        $popup.Close()
    })
    $popup.Controls.Add($btnConfirmar)
    Set-RoundedControl -Control $btnConfirmar -Radius 8

    $popup.Add_KeyDown({
        if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
            $popup.DialogResult = 'Cancel'
            $popup.Close()
            return
        }
        if ($_.Control -and $_.KeyCode -eq [System.Windows.Forms.Keys]::M) {
            $btnManual.PerformClick()
            return
        }
        if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
            $btnConfirmar.PerformClick()
            return
        }
    })

    $resultado = $popup.ShowDialog()

    if ($resultado -ne 'OK') {
        $btnImprimir.Enabled = $true
        $btnImprimir.Text    = 'Imprimir Etiqueta via Rede'
        return
    }

    $btnImprimir.Text = 'Enviando...'
    Set-AppStatus -Texto 'Enviando etiqueta para o servidor...' -Cor $cAccent
    [System.Windows.Forms.Application]::DoEvents()

    # Monta JSON com dados + grade + obs
    if ($script:incluirOSAtual -and -not $script:osDefinidaPorTriagem) {
        try {
            $respReserva = Invoke-CaijServer -Path '/proxima-os' -Method POST -Body '{}' -TimeoutSec 12 -Retries 3
            if ($respReserva -and [string]$respReserva.status -eq 'ok' -and $respReserva.osNumero) {
                Set-OsNumeroAtual -Numero ([int]$respReserva.osNumero)
                Set-AppStatus -Texto "OS reservada para impressao: $(Format-OsCodigo -Numero ([int]$respReserva.osNumero))" -Cor $cAccent
            }
        } catch {
            Set-AppStatus -Texto 'Falha ao reservar OS no servidor | usando OS local' -Cor $cYellow
        }
    } elseif ($script:incluirOSAtual -and $script:osDefinidaPorTriagem) {
        Set-AppStatus -Texto "OS da triagem aplicada: $(Format-OsCodigo -Numero $script:osNumero)" -Cor $cGreen
    }

    $dadosJson = @{
        os      = if ($script:incluirOSAtual) { $script:osNumero } else { $null }
        modelo  = $script:modeloEtiqueta
        serial  = $script:serialEtiqueta
        cpu     = $script:cpuEtiqueta
        gpu     = $gpuCurta
        ram     = $script:ramEtiqueta
        ramMods = $script:ramEtiqueta
        disco   = $script:memEtiqueta
        bateria = $info.BatSaude
        grade   = if ($script:rnaAtivo) { 'RMA' } elseif ($script:gradeAtual) { $script:gradeAtual } else { 'A' }
        obs     = (& $script:GetObsImpressao)
    } | ConvertTo-Json -Compress

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $printSent = $false
        $lastErr = $null
        foreach ($tentativa in @(1,2,3)) {
            try {
                if ($tentativa -gt 1) {
                    Set-AppStatus -Texto "Reenviando etiqueta (tentativa $tentativa/3)..." -Cor $cYellow
                    Start-Sleep -Milliseconds (450 * ($tentativa - 1))
                }
                Invoke-CaijServer -Path '/imprimir' -Method POST -Body $dadosJson -TimeoutSec 20 -Retries 1 | Out-Null
                $printSent = $true
                break
            } catch {
                $lastErr = $_
            }
        }
        if (-not $printSent) {
            if ($lastErr) { throw $lastErr } else { throw 'Falha ao enviar etiqueta apos 2 tentativas.' }
        }
        $btnImprimir.Text      = 'Etiqueta Enviada!'
        $btnImprimir.BackColor = [System.Drawing.Color]::FromArgb(0, 110, 50)
        Add-HistoricoNotebook -Acao 'impressao' -Status 'ok' -Mensagem 'Etiqueta enviada com sucesso' -Grade $script:gradeAtual -Obs $script:obsAtual
        Set-AppStatus -Texto "Impresso | historico salvo | OS $(Format-OsCodigo -Numero $script:osNumero)" -Cor $cGreen
        if ($script:incluirOSAtual) { Sync-OsFromAltertag -Silent }
    } catch {
        $erro = $_.Exception.Message
        if ($erro -match 'refused|recusada|Unable to connect|nao foi possivel|timed out|tempo') {
            $srvOnline = $false
            try {
                Invoke-RestMethod -Uri ('{0}/status' -f (Get-ServidorBaseUrl)) -Method Get -TimeoutSec 3 -ErrorAction Stop | Out-Null
                $srvOnline = $true
            } catch {}
            if ($srvOnline) {
                [System.Windows.Forms.MessageBox]::Show(
                    "O servidor respondeu, mas a impressao falhou/atrasou.`nVerifique impressora, fila de spool e compartilhamento da impressora no PC principal.",
                    "Falha de impressao",
                    "OK",
                    "Warning"
                ) | Out-Null
            } else {
                [System.Windows.Forms.MessageBox]::Show(
                    "Servidor de impressao nao encontrado ou sem resposta.`nVerifique se o ServidorImpressao.ps1 esta rodando no PC principal (192.168.15.54).",
                    "Servidor offline",
                    "OK",
                    "Warning"
                ) | Out-Null
            }
        } else {
            [System.Windows.Forms.MessageBox]::Show("Erro: $erro", "Erro de impressao", "OK", "Error") | Out-Null
        }
        Add-HistoricoNotebook -Acao 'impressao' -Status 'erro' -Mensagem $erro -Grade $script:gradeAtual -Obs $script:obsAtual
        Set-AppStatus -Texto 'Falha ao imprimir | historico salvo' -Cor $cRed
        $btnImprimir.Text      = 'Erro ao enviar!'
        $btnImprimir.BackColor = [System.Drawing.Color]::FromArgb(130, 30, 30)
    }

    $btnImprimir.Enabled = $true
    $resetImpTimer = New-Object System.Windows.Forms.Timer
    $resetImpTimer.Interval = 1500
    $resetImpTimer.Add_Tick({
        $btnImprimir.Text      = 'Imprimir Etiqueta via Rede'
        $btnImprimir.BackColor = [System.Drawing.Color]::FromArgb(8, 44, 70)
        $this.Stop()
        $this.Dispose()
    })
    $resetImpTimer.Start()
})
# ================================================
# BARRA INFERIOR
# ================================================
$botY = $actY + 108

$botBar = New-Object System.Windows.Forms.Panel
$botBar.BackColor = $cBar
$botBar.Location  = New-Object System.Drawing.Point(0, $botY)
$botBar.Size      = New-Object System.Drawing.Size($W, 26)
$form.Controls.Add($botBar)

$botTopLine = New-Object System.Windows.Forms.Label
$botTopLine.BackColor = [System.Drawing.Color]::FromArgb(24, 48, 72)
$botTopLine.Location  = New-Object System.Drawing.Point(0, 0)
$botTopLine.Size      = New-Object System.Drawing.Size($W, 1)
$botBar.Controls.Add($botTopLine)

$script:botDot = New-Object System.Windows.Forms.Label
$script:botDot.BackColor = $cYellow
$script:botDot.Location  = New-Object System.Drawing.Point(14, 12)
$script:botDot.Size      = New-Object System.Drawing.Size(6, 6)
$botBar.Controls.Add($script:botDot)

$script:botTxt = New-Object System.Windows.Forms.Label
$script:botTxt.Text      = 'VERIFICANDO SERVIDOR E OS...'
$script:botTxt.Font      = $fMicro
$script:botTxt.ForeColor = [System.Drawing.Color]::FromArgb(86, 120, 154)
$script:botTxt.Location  = New-Object System.Drawing.Point(28, 7)
$script:botTxt.Size      = New-Object System.Drawing.Size(500, 14)
$botBar.Controls.Add($script:botTxt)

$botVer = New-Object System.Windows.Forms.Label
$botVer.Text      = 'v4.1'
$botVer.Font      = $fMicro
$botVer.ForeColor = [System.Drawing.Color]::FromArgb(86, 120, 154)
$botVer.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$botVer.Location  = New-Object System.Drawing.Point(580, 7)
$botVer.Size      = New-Object System.Drawing.Size(100, 14)
$botBar.Controls.Add($botVer)

# ================================================
# TAMANHO FINAL
# ================================================
$form.ClientSize = New-Object System.Drawing.Size($W, ($botY + 26))

# Fecha splash e abre o form principal
& $script:UpdateSplashProgress 100 'Pronto!'
$splash.Close()
$splash.Dispose()

$form.Add_Shown({
    try {
        Test-ServidorPrincipal -Quiet | Out-Null
        Sync-OsFromAltertag -Silent
    } catch {}
})

$form.ShowDialog() | Out-Null
