# ================================================
#  CAIJ INFORMATICA - INFO NOTEBOOK v4
# ================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$NL = [Environment]::NewLine

. (Join-Path $PSScriptRoot 'GradeRules.ps1')

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

if (-not ('CaijGradeMenuRenderer' -as [type])) {
    $gradeMenuRendererSource = @'
using System;
using System.Drawing;
using System.Windows.Forms;

public sealed class CaijGradeMenuRenderer : ToolStripProfessionalRenderer
{
    private static readonly Color Background = Color.FromArgb(10, 20, 33);
    private static readonly Color Hover = Color.FromArgb(20, 48, 70);
    private static readonly Color Border = Color.FromArgb(36, 70, 104);
    private static readonly Color Text = Color.FromArgb(236, 245, 255);

    public CaijGradeMenuRenderer()
    {
        RoundedEdges = false;
    }

    private static Color GetAccent(object rawTag)
    {
        string tag = Convert.ToString(rawTag).Trim().ToUpperInvariant();
        if (tag == "A") return Color.FromArgb(66, 232, 176);
        if (tag == "B") return Color.FromArgb(255, 208, 96);
        if (tag.StartsWith("C - PINTURA")) return Color.FromArgb(255, 156, 98);
        if (tag.StartsWith("T - TRIAGEM")) return Color.FromArgb(24, 185, 255);
        if (tag == "RMA") return Color.FromArgb(241, 95, 122);
        return Color.FromArgb(102, 134, 165);
    }

    protected override void OnRenderToolStripBackground(ToolStripRenderEventArgs e)
    {
        using (var brush = new SolidBrush(Background))
            e.Graphics.FillRectangle(brush, e.AffectedBounds);
    }

    protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e)
    {
        Rectangle bounds = new Rectangle(Point.Empty, e.Item.Size);
        using (var brush = new SolidBrush(e.Item.Selected ? Hover : Background))
            e.Graphics.FillRectangle(brush, bounds);

        using (var accent = new SolidBrush(GetAccent(e.Item.Tag)))
            e.Graphics.FillRectangle(accent, 3, 5, 4, Math.Max(1, bounds.Height - 10));

        ToolStripMenuItem menuItem = e.Item as ToolStripMenuItem;
        if (menuItem != null && menuItem.Checked)
        {
            using (var marker = new SolidBrush(Text))
                e.Graphics.FillEllipse(marker, bounds.Width - 12, Math.Max(2, (bounds.Height - 5) / 2), 5, 5);
        }
    }

    protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
    {
        e.TextColor = e.Item.Enabled ? Text : Color.FromArgb(102, 134, 165);
        base.OnRenderItemText(e);
    }

    protected override void OnRenderToolStripBorder(ToolStripRenderEventArgs e)
    {
        Rectangle border = new Rectangle(0, 0, e.ToolStrip.Width - 1, e.ToolStrip.Height - 1);
        using (var pen = new Pen(Border))
            e.Graphics.DrawRectangle(pen, border);
    }
}
'@
    Add-Type -TypeDefinition $gradeMenuRendererSource -ReferencedAssemblies @('System.Windows.Forms', 'System.Drawing') -WarningAction SilentlyContinue
}

function Set-DoubleBuffered {
    param([System.Windows.Forms.Control]$Control)
    if (-not $Control) { return }
    $prop = [System.Windows.Forms.Control].GetProperty(
        'DoubleBuffered',
        [System.Reflection.BindingFlags]'Instance,NonPublic'
    )
    if ($prop) {
        $prop.SetValue($Control, $true, $null) | Out-Null
    }
}

# ================================================
# SPLASH SCREEN - aparece imediatamente
# ================================================
$splash = New-Object System.Windows.Forms.Form
$splash.Text            = 'Caij Informatica'
$splash.Size            = New-Object System.Drawing.Size(560, 360)
$splash.StartPosition   = 'CenterScreen'
$splash.BackColor       = [System.Drawing.Color]::FromArgb(15, 24, 36)
$splash.FormBorderStyle = 'None'
$splash.MaximizeBox     = $false
$splash.MinimizeBox     = $false
$splash.TopMost         = $true
Set-DoubleBuffered $splash

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
$splashCard.Location  = New-Object System.Drawing.Point(0, 0)
$splashCard.Size      = New-Object System.Drawing.Size(560, 360)
$splashCard.BorderStyle = 'None'
$splash.Controls.Add($splashCard)

$splashAccent = New-Object System.Windows.Forms.Panel
$splashAccent.BackColor = [System.Drawing.Color]::FromArgb(0, 166, 255)
$splashAccent.Location  = New-Object System.Drawing.Point(0, 0)
$splashAccent.Size      = New-Object System.Drawing.Size(4, 360)
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
function Get-EquipamentoTipo {
    param(
        $ComputerSystem,
        $SystemEnclosure
    )

    $desktopPcTypes = @(2, 4, 5, 6, 7)
    $mobilePcTypes  = @(3)
    $desktopChassis = @(3, 4, 5, 6, 7, 13, 15, 16, 35)
    $mobileChassis  = @(8, 9, 10, 11, 12, 14, 30, 31, 32)

    $pcType = $null
    try {
        if ($null -ne $ComputerSystem.PCSystemType) { $pcType = [int]$ComputerSystem.PCSystemType }
    } catch {}

    $chassisTypes = @()
    try {
        if ($SystemEnclosure -and $SystemEnclosure.ChassisTypes) {
            $chassisTypes = @($SystemEnclosure.ChassisTypes | ForEach-Object { [int]$_ })
        }
    } catch {}

    $isMobile = ($pcType -in $mobilePcTypes) -or (@($chassisTypes | Where-Object { $_ -in $mobileChassis }).Count -gt 0)
    $isDesktop = ($pcType -in $desktopPcTypes) -or (@($chassisTypes | Where-Object { $_ -in $desktopChassis }).Count -gt 0)

    if ($isMobile) { return 'Notebook' }
    if ($isDesktop) { return 'CPU' }
    return 'Notebook'
}

function Get-NotebookInfo {
    $info = [ordered]@{}
    & $script:UpdateSplashProgress 8 'Lendo BIOS e identificacao do notebook...'

    try {
        $bios = Get-CimInstance Win32_BIOS
        $cs   = Get-CimInstance Win32_ComputerSystem
        $csp  = Get-CimInstance Win32_ComputerSystemProduct
        $enc  = Get-CimInstance Win32_SystemEnclosure -ErrorAction SilentlyContinue | Select-Object -First 1
        $fab  = $cs.Manufacturer.Trim()
        $mod  = $cs.Model.Trim()
        $ver  = if ($csp.Version) { $csp.Version.Trim() } else { '' }
        if ($fab -match 'Lenovo' -and $ver -and $ver -notmatch 'Default|O\.E\.M' -and $ver -ne 'Lenovo') {
            $info.Modelo = $fab + ' ' + $ver
        } else {
            $info.Modelo = $fab + ' ' + $mod
        }
        $info.Serial = $bios.SerialNumber.Trim()
        $info.TipoEquipamento = Get-EquipamentoTipo -ComputerSystem $cs -SystemEnclosure $enc
        $info.MostrarBateria = ($info.TipoEquipamento -ne 'CPU')
    } catch { $info.Modelo = 'N/A'; $info.Serial = 'N/A'; $info.TipoEquipamento = 'Notebook'; $info.MostrarBateria = $true }
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
    if ($info.MostrarBateria) {
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
    } else {
        & $script:UpdateSplashProgress 78 'CPU detectada, ignorando bateria...'
        $info.BatSaude = $null
    }
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
$script:modelosManuaisArquivo = Join-Path (Split-Path -Parent $PSCommandPath) 'caij_modelos_manuais.json'
$script:modelosManuaisHistorico = @()
$script:registroBaseDir = $null
$script:registroBaseDirFallback = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'CAIJ\Registros'
$script:ultimoStatusServidor = 'nao verificado'
$script:ultimaSincronizacaoOs = ''
$script:osNumero  = 235
$script:osDefinidaPorAltertag = $false
$script:osDefinidaManual = $false
$script:altertagOsAtual = $null
$script:altertagOsDetalheConfirmado = $null
$script:maiorOsVistaAltertag = 0
$script:ultimoAlertaOsNumero = 0
$script:ultimoConfirmadoServidor = 0
$script:osAlertMonitorBusy = $false
$script:alertaOsAtual = $null
if (Test-Path $script:osArquivo) {
    try { $script:osNumero = [int]((Get-Content $script:osArquivo -Raw -ErrorAction Stop).Trim()) } catch {}
}
if ($script:osNumero -lt 235) { $script:osNumero = 235 }

function Save-OsNumero {
    param([int]$Numero)
    try { Set-Content -Path $script:osArquivo -Value $Numero -Encoding UTF8 } catch {}
}

function Import-ModelosManuaisHistorico {
    $script:modelosManuaisHistorico = @()
    if (-not (Test-Path -LiteralPath $script:modelosManuaisArquivo)) { return }
    try {
        $raw = Get-Content -LiteralPath $script:modelosManuaisArquivo -Raw -ErrorAction Stop
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $script:modelosManuaisHistorico = @(
                $raw |
                    ConvertFrom-Json -ErrorAction Stop |
                    ForEach-Object { ([string]$_).Trim() } |
                    Where-Object { $_ -and $_ -notmatch '^(?i:N/?A)$' } |
                    Select-Object -Unique -First 200
            )
        }
    } catch {
        $script:modelosManuaisHistorico = @()
    }
}

function Add-ModeloManualHistorico {
    param([string]$Modelo)

    $modeloLimpo = if ($Modelo) { $Modelo.Trim() } else { '' }
    if (-not $modeloLimpo -or $modeloLimpo -match '^(?i:N/?A)$') { return }

    $restantes = @(
        $script:modelosManuaisHistorico |
            Where-Object { -not [string]::Equals(([string]$_).Trim(), $modeloLimpo, [System.StringComparison]::OrdinalIgnoreCase) }
    )
    $script:modelosManuaisHistorico = @($modeloLimpo) + $restantes
    if ($script:modelosManuaisHistorico.Count -gt 200) {
        $script:modelosManuaisHistorico = @($script:modelosManuaisHistorico | Select-Object -First 200)
    }
    try {
        $script:modelosManuaisHistorico |
            ConvertTo-Json -Depth 3 |
            Set-Content -LiteralPath $script:modelosManuaisArquivo -Encoding UTF8 -ErrorAction Stop
    } catch {}
}

Import-ModelosManuaisHistorico

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
        if ($script:botDot) { $script:botDotColor = $Cor; $script:botDot.Invalidate() }
        # Esconde o botao de configurar quando servidor volta
        if ($script:btnConfigurarSrv -and -not $script:btnConfigurarSrv.IsDisposed) {
            $isOnline = ($Cor.ToArgb() -eq $cGreen.ToArgb())
            if ($isOnline -and $script:btnConfigurarSrv.Visible) { $script:btnConfigurarSrv.Visible = $false }
        }
    } catch {}
}

function Set-AppStatusTemporario {
    param(
        [string]$Texto,
        [System.Drawing.Color]$Cor,
        [string]$TextoDepois,
        [System.Drawing.Color]$CorDepois,
        [int]$IntervaloMs = 3500
    )
    Set-AppStatus -Texto $Texto -Cor $Cor
    try {
        if ($script:statusResetTimer) {
            $script:statusResetTimer.Stop()
            $script:statusResetTimer.Dispose()
        }
    } catch {}
    $script:statusResetTimer = New-Object System.Windows.Forms.Timer
    $script:statusResetTimer.Interval = $IntervaloMs
    $script:statusResetTimer.Add_Tick({
        $this.Stop()
        Set-AppStatus -Texto $TextoDepois -Cor $CorDepois
        try { $this.Dispose() } catch {}
        $script:statusResetTimer = $null
    })
    $script:statusResetTimer.Start()
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
        bateria = if ($info.MostrarBateria) { $info.BatSaude } else { $null }
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

    # IP do PC principal.
    [void]$candidatos.Add(('http://{0}:{1}' -f '192.168.15.127', $portaServidor))

    # Tenta o final .127 em cada rede IPv4 local do notebook.
    try {
        $ipsLocais = @(Get-CimInstance Win32_NetworkAdapterConfiguration -ErrorAction SilentlyContinue |
            Where-Object { $_.IPEnabled -and $_.IPAddress } |
            ForEach-Object { $_.IPAddress } |
            Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' -and $_ -notmatch '^169\.254\.' -and $_ -ne '127.0.0.1' })

        foreach ($ipLocal in $ipsLocais) {
            $parts = $ipLocal.Split('.')
            if ($parts.Count -eq 4) {
                [void]$candidatos.Add(('http://{0}.{1}.{2}.127:{3}' -f $parts[0], $parts[1], $parts[2], $portaServidor))
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

function Show-OsAltertagDetalheConfirm {
    param($Os)

    if (-not $Os) { return $false }
    $script:altertagOsDetalheConfirmado = $null
    $idOrdem = 0
    $osNumero = 0
    try { if ($Os.idOrdem) { $idOrdem = [int]$Os.idOrdem } } catch {}
    try { if ($Os.numero) { $osNumero = [int]$Os.numero } } catch {}

    $path = ''
    if ($idOrdem -gt 0) {
        $path = "/os-detalhe?idOrdem=$idOrdem&produtos=1"
    } elseif ($osNumero -gt 0) {
        $path = "/os-detalhe?osNumero=$osNumero&produtos=1"
    } else {
        return $true
    }

    try {
        $resp = Invoke-CaijServer -Path $path -Method GET -TimeoutSec 22 -Retries 1
        if (-not $resp -or [string]$resp.status -ne 'ok' -or -not $resp.ordem) {
            throw "Resposta invalida do servidor ao consultar detalhe da OS."
        }
        $det = $resp.ordem
        $script:altertagOsDetalheConfirmado = $det
        $msg = "Conferir OS antes de vincular:`n`n"
        $msg += "OS: $(Format-OsCodigo -Numero ([int]$det.numero))`n"
        $msg += "Cliente: $([string]$det.cliente)`n"
        $msg += "Status: $([string]$det.statusOs)`n"
        $msg += "Tecnico: $([string]$det.tecnico)`n"
        $msg += "Produto/equipamento: $([string]$det.equipamento)`n"
        if ($det.garantia) { $msg += "Serial: $([string]$det.garantia)`n" }
        if ($det.referencia) { $msg += "Referencia: $([string]$det.referencia)`n" }
        if ($det.problema) { $msg += "Problema: $([string]$det.problema)`n" }
        $msg += "`nUsar esta OS no InfoNotebook?"
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            $msg,
            'Confirmar OS Altertag',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        return ($confirm -eq [System.Windows.Forms.DialogResult]::Yes)
    } catch {
        $confirmErro = [System.Windows.Forms.MessageBox]::Show(
            "Nao foi possivel consultar os detalhes da OS no Altertag:`n$($_.Exception.Message)`n`nContinuar usando a OS da lista?",
            'Detalhe da OS indisponivel',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return ($confirmErro -eq [System.Windows.Forms.DialogResult]::Yes)
    }
}

function Register-OsAltertagStatusImpressao {
    param(
        [string]$Grade = '',
        [string]$Obs = ''
    )

    if (-not $script:incluirOSAtual -or -not $script:osDefinidaPorAltertag) { return $false }
    $idOrdem = 0
    try { if ($script:altertagOsAtual -and $script:altertagOsAtual.idOrdem) { $idOrdem = [int]$script:altertagOsAtual.idOrdem } } catch {}
    $obsPartes = @(
        "Serial: $($info.Serial)",
        "Modelo: $($info.Modelo)",
        "Grade: $Grade"
    )
    if ($Obs -and $Obs.Trim()) { $obsPartes += "Obs: $($Obs.Trim())" }
    $payloadObj = @{
        idOrdem = $idOrdem
        osNumero = [int]$script:osNumero
        tipoStatus = 'Etiqueta CAIJ impressa'
        observacao = ($obsPartes -join ' | ')
    }
    $payload = $payloadObj | ConvertTo-Json -Depth 4 -Compress
    try {
        $resp = Invoke-CaijServer -Path '/os-status' -Method POST -Body $payload -TimeoutSec 22 -Retries 1
        return ($resp -and [string]$resp.status -eq 'ok')
    } catch {
        Set-AppStatusTemporario -Texto 'Impresso | aviso: status nao registrado na OS' -Cor $cYellow -TextoDepois "Impresso | historico salvo | OS $(Format-OsCodigo -Numero $script:osNumero)" -CorDepois $cGreen
        return $false
    }
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

    $script:servidorBaseUrlCache = 'http://192.168.15.127:9100'
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
# ================================================
# TOP BAR
# ================================================
$topBar = New-Object System.Windows.Forms.Panel
$topBar.BackColor = [System.Drawing.Color]::FromArgb(5, 10, 18)
$topBar.Location  = New-Object System.Drawing.Point(0, 0)
$topBar.Size      = New-Object System.Drawing.Size($W, 30)
$form.Controls.Add($topBar)

# Linha inferior accent (cyan sutil)
$topBarLine = New-Object System.Windows.Forms.Panel
$topBarLine.BackColor = [System.Drawing.Color]::FromArgb(0, 140, 200)
$topBarLine.Location  = New-Object System.Drawing.Point(0, 29)
$topBarLine.Size      = New-Object System.Drawing.Size($W, 1)
$topBar.Controls.Add($topBarLine)

# Dot status
$tdot = New-Object System.Windows.Forms.Label
$tdot.BackColor = $cGreen
$tdot.Location  = New-Object System.Drawing.Point(16, 11)
$tdot.Size      = New-Object System.Drawing.Size(8, 8)
$topBar.Controls.Add($tdot)

$tlbl = New-Object System.Windows.Forms.Label
$tlbl.Text      = 'CAU INFORMATICA   |   PAINEL TECNICO'
$tlbl.Font      = New-Object System.Drawing.Font('Segoe UI', 7.5, [System.Drawing.FontStyle]::Bold)
$tlbl.ForeColor = [System.Drawing.Color]::FromArgb(110, 155, 192)
$tlbl.Location  = New-Object System.Drawing.Point(32, 8)
$tlbl.Size      = New-Object System.Drawing.Size(310, 14)
$topBar.Controls.Add($tlbl)

$ttime = New-Object System.Windows.Forms.Label
$ttime.Text      = 'Atualizado: ' + $dataHora
$ttime.Font      = New-Object System.Drawing.Font('Segoe UI', 7.5)
$ttime.ForeColor = [System.Drawing.Color]::FromArgb(76, 110, 140)
$ttime.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$ttime.Location  = New-Object System.Drawing.Point(390, 8)
$ttime.Size      = New-Object System.Drawing.Size(282, 14)
$topBar.Controls.Add($ttime)

# ================================================
# HEADER
# ================================================
$hH = 88
$hPanel = New-Object System.Windows.Forms.Panel
$hPanel.BackColor = [System.Drawing.Color]::FromArgb(10, 18, 28)
$hPanel.Location  = New-Object System.Drawing.Point(0, 30)
$hPanel.Size      = New-Object System.Drawing.Size($W, $hH)
$form.Controls.Add($hPanel)

$hPanel.Add_Paint({
    param($sender, $e)
    $g = $e.Graphics
    $g.SmoothingMode = 'AntiAlias'
    # Gradient fundo
    $r = New-Object System.Drawing.Rectangle(0, 0, $sender.Width, $sender.Height)
    $b = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $r,
        [System.Drawing.Color]::FromArgb(14, 26, 42),
        [System.Drawing.Color]::FromArgb(7, 13, 22),
        [System.Drawing.Drawing2D.LinearGradientMode]::Vertical
    )
    $g.FillRectangle($b, $r)
    $b.Dispose()
    # Sublinhado gradiente sob o titulo (cyan -> transparente)
    $underRect = New-Object System.Drawing.Rectangle(20, 41, 260, 2)
    $underBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $underRect,
        [System.Drawing.Color]::FromArgb(210, 0, 168, 232),
        [System.Drawing.Color]::FromArgb(0, 0, 168, 232),
        [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal
    )
    $g.FillRectangle($underBrush, $underRect)
    $underBrush.Dispose()
    # Linhas diagonais decorativas discretas (lado direito, atras da caixa serial)
    $diagPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(14, 0, 168, 232), 1)
    for ($xd = ($sender.Width - 260); $xd -lt $sender.Width; $xd += 14) {
        $g.DrawLine($diagPen, $xd, $sender.Height, ($xd + 30), 0)
    }
    $diagPen.Dispose()
    # Linha separadora inferior sutil
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(22, 50, 78), 1)
    $g.DrawLine($pen, 0, ($sender.Height - 1), $sender.Width, ($sender.Height - 1))
    $pen.Dispose()
})

# Barra accent esquerda (cyan vivo)
$hAccL = New-Object System.Windows.Forms.Panel
$hAccL.BackColor = $cAccent
$hAccL.Location  = New-Object System.Drawing.Point(0, 0)
$hAccL.Size      = New-Object System.Drawing.Size(3, $hH)
$hPanel.Controls.Add($hAccL)

# Titulo
$hTitle = New-Object System.Windows.Forms.Label
$hTitle.Text      = 'Inventario de Hardware'
$hTitle.Font      = New-Object System.Drawing.Font('Segoe UI', 17, [System.Drawing.FontStyle]::Bold)
$hTitle.ForeColor = [System.Drawing.Color]::FromArgb(220, 240, 255)
$hTitle.Location  = New-Object System.Drawing.Point(20, 10)
$hTitle.Size      = New-Object System.Drawing.Size(480, 30)
$hPanel.Controls.Add($hTitle)

# Modelo (linha 2) — pill com fundo tintado e cantos arredondados
$hModel = New-Object System.Windows.Forms.Label
$hModel.Text      = $info.Modelo.ToUpper()
$hModel.Font      = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
$hModel.ForeColor = $cAccent
$hModel.BackColor = [System.Drawing.Color]::FromArgb(11, 34, 52)
$hModel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$hModelW = [Math]::Min(400, ([System.Windows.Forms.TextRenderer]::MeasureText($hModel.Text, $hModel.Font)).Width + 20)
$hModel.Location  = New-Object System.Drawing.Point(20, 48)
$hModel.Size      = New-Object System.Drawing.Size($hModelW, 18)
$hPanel.Controls.Add($hModel)

# Data hora (linha 3) — ao lado do pill do modelo
$hDate = New-Object System.Windows.Forms.Label
$hDate.Text      = $dataHora
$hDate.Font      = New-Object System.Drawing.Font('Segoe UI', 7)
$hDate.ForeColor = [System.Drawing.Color]::FromArgb(58, 90, 118)
$hDate.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$hDate.Location  = New-Object System.Drawing.Point((20 + $hModelW + 12), 48)
$hDate.Size      = New-Object System.Drawing.Size(200, 18)
$hPanel.Controls.Add($hDate)

# ---- Caixa serial (direita) ----
$sBox = New-Object System.Windows.Forms.Panel
$sBox.BackColor   = [System.Drawing.Color]::FromArgb(6, 18, 32)
$sBox.Location    = New-Object System.Drawing.Point(490, 6)
$sBox.Size        = New-Object System.Drawing.Size(192, 76)
$sBox.BorderStyle = 'None'
$hPanel.Controls.Add($sBox)

$sBox.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $g.SmoothingMode = 'AntiAlias'
    # Fundo arredondado
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $r2 = 10
    $w2 = $s.Width; $h2 = $s.Height
    $path.AddArc(0, 0, $r2*2, $r2*2, 180, 90)
    $path.AddArc($w2-$r2*2, 0, $r2*2, $r2*2, 270, 90)
    $path.AddArc($w2-$r2*2, $h2-$r2*2, $r2*2, $r2*2, 0, 90)
    $path.AddArc(0, $h2-$r2*2, $r2*2, $r2*2, 90, 90)
    $path.CloseFigure()
    $bg = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(6, 18, 32))
    $g.FillPath($bg, $path)
    $bg.Dispose()
    # Borda cyan brilhante
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(0, 168, 232), 1.5)
    $g.DrawPath($pen, $path)
    $pen.Dispose()
    # Barra superior cyan (destaque)
    $topAccent = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0, 168, 232))
    $g.FillRectangle($topAccent, 10, 0, ($w2-20), 2)
    $topAccent.Dispose()
    $path.Dispose()
})

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
function New-SectionHairline {
    param(
        [Parameter(Mandatory=$true)]$Parent,
        [int]$X, [int]$Y, [int]$W,
        [System.Drawing.Color]$Cor = ([System.Drawing.Color]::FromArgb(0, 168, 232))
    )
    $ln = New-Object System.Windows.Forms.Panel
    $ln.BackColor = [System.Drawing.Color]::Transparent
    $ln.Location  = New-Object System.Drawing.Point($X, $Y)
    $ln.Size      = New-Object System.Drawing.Size($W, 1)
    $corCap = $Cor
    $ln.Add_Paint({
        param($s, $e)
        $rct = New-Object System.Drawing.Rectangle(0, 0, $s.Width, 1)
        $br = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            $rct,
            [System.Drawing.Color]::FromArgb(110, $corCap.R, $corCap.G, $corCap.B),
            [System.Drawing.Color]::FromArgb(0, $corCap.R, $corCap.G, $corCap.B),
            [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal
        )
        $e.Graphics.FillRectangle($br, $rct)
        $br.Dispose()
    }.GetNewClosure())
    [void]$Parent.Controls.Add($ln)
    return $ln
}

Set-RoundedControl -Control $sBox -Radius 8
$sBox.Add_SizeChanged({ Set-RoundedControl -Control $sBox -Radius 8 })
Set-RoundedControl -Control $hModel -Radius 9

# Label "NUMERO DE SERIE"
$sLbl = New-Object System.Windows.Forms.Label
$sLbl.Text      = 'NUMERO DE SERIE'
$sLbl.Font      = New-Object System.Drawing.Font('Segoe UI', 6.5, [System.Drawing.FontStyle]::Bold)
$sLbl.ForeColor = [System.Drawing.Color]::FromArgb(0, 168, 232)
$sLbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$sLbl.Location  = New-Object System.Drawing.Point(0, 10)
$sLbl.Size      = New-Object System.Drawing.Size(192, 14)
$sBox.Controls.Add($sLbl)

# Valor serial (grande e destacado)
$sVal = New-Object System.Windows.Forms.Label
$sVal.Text      = $info.Serial
$sVal.Font      = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
$sVal.ForeColor = [System.Drawing.Color]::FromArgb(220, 245, 255)
$sVal.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$sVal.Location  = New-Object System.Drawing.Point(0, 22)
$sVal.Size      = New-Object System.Drawing.Size(192, 25)
$sBox.Controls.Add($sVal)

# Divisor
$sDivider = New-Object System.Windows.Forms.Panel
$sDivider.BackColor = [System.Drawing.Color]::FromArgb(22, 55, 82)
$sDivider.Location  = New-Object System.Drawing.Point(24, 51)
$sDivider.Size      = New-Object System.Drawing.Size(144, 1)
$sBox.Controls.Add($sDivider)

# Numero da OS centralizado no rodape da caixa
$script:osValLabel = New-Object System.Windows.Forms.Label
$script:osValLabel.Text      = 'C000' + $script:osNumero.ToString()
$script:osValLabel.Font      = New-Object System.Drawing.Font('Segoe UI Semibold', 9, [System.Drawing.FontStyle]::Bold)
$script:osValLabel.ForeColor = $cGreen
$script:osValLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$script:osValLabel.Location  = New-Object System.Drawing.Point(0, 55)
$script:osValLabel.Size      = New-Object System.Drawing.Size(192, 16)
$script:osValLabel.Cursor    = [System.Windows.Forms.Cursors]::Hand
$sBox.Controls.Add($script:osValLabel)

# Botao Sync compacto (icone ciclico) no canto superior direito da caixa
$osSyncBtn = New-Object System.Windows.Forms.Button
$osSyncBtn.Text = [string][char]0x21BB
$osSyncBtn.Font = New-Object System.Drawing.Font('Segoe UI Symbol', 9, [System.Drawing.FontStyle]::Bold)
$osSyncBtn.ForeColor = [System.Drawing.Color]::FromArgb(0, 168, 232)
$osSyncBtn.BackColor = [System.Drawing.Color]::FromArgb(6, 18, 32)
$osSyncBtn.FlatStyle = 'Flat'
$osSyncBtn.FlatAppearance.BorderSize = 0
$osSyncBtn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(14, 40, 62)
$osSyncBtn.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(20, 55, 82)
$osSyncBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
$osSyncBtn.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$osSyncBtn.Location = New-Object System.Drawing.Point(166, 5)
$osSyncBtn.Size = New-Object System.Drawing.Size(21, 21)
$sBox.Controls.Add($osSyncBtn)
$osSyncBtn.BringToFront()
Set-RoundedControl -Control $osSyncBtn -Radius 10
$syncTip = New-Object System.Windows.Forms.ToolTip
$syncTip.SetToolTip($osSyncBtn, 'Sincronizar numero da OS')

function Format-OsCodigo {
    param([int]$Numero)
    if ($Numero -lt 1) { return '' }
    return ('C000{0}' -f $Numero)
}

function Set-OsNumeroAtual {
    param(
        [int]$Numero,
        [string]$Fonte = 'local'
    )
    if ($Numero -lt 1) { return }
    $script:osNumero = $Numero
    if ($Fonte -eq 'altertag') {
        $script:osDefinidaPorAltertag = $true
        $script:osDefinidaManual = $false
    } elseif ($Fonte -eq 'manual') {
        $script:osDefinidaPorAltertag = $false
        $script:osDefinidaManual = $true
    } elseif ($Fonte -ne 'sync') {
        $script:osDefinidaPorAltertag = $false
        $script:osDefinidaManual = $false
    }
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
    Set-OsNumeroAtual -Numero ([int]$entrada.Trim()) -Fonte 'manual'
}

$script:osValLabel.Add_Click({ Prompt-OsManual })

function Select-OsFromAltertagRecentes {
    param([object[]]$Ordens)

    if (-not $Ordens -or $Ordens.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('A API nao retornou ordens de servico recentes.', 'OS Altertag', 'OK', 'Warning') | Out-Null
        return $false
    }

    # ---- helpers locais do dialog ----
    function New-DlgBtn {
        param([string]$txt, [int]$x, [int]$y, [int]$w, [int]$h,
              [System.Drawing.Color]$bg, [System.Drawing.Color]$fg,
              [System.Drawing.Color]$bgH, [System.Drawing.Color]$border)
        $b = New-Object System.Windows.Forms.Button
        $b.Text = $txt
        $b.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5, [System.Drawing.FontStyle]::Bold)
        $b.ForeColor = $fg; $b.BackColor = $bg; $b.FlatStyle = 'Flat'
        $b.FlatAppearance.BorderSize = 1; $b.FlatAppearance.BorderColor = $border
        $b.FlatAppearance.MouseOverBackColor = $bgH
        $b.Location = New-Object System.Drawing.Point($x, $y)
        $b.Size = New-Object System.Drawing.Size($w, $h)
        $b.Cursor = [System.Windows.Forms.Cursors]::Hand
        return $b
    }

    $dlgW = 900; $dlgH = 520
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Selecionar OS Altertag'
    $dlg.StartPosition = 'CenterParent'
    $dlg.Size = New-Object System.Drawing.Size($dlgW, $dlgH)
    $dlg.BackColor = [System.Drawing.Color]::FromArgb(7, 14, 22)
    $dlg.ForeColor = $cMain
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false

    # Faixa superior colorida
    $dlgHeader = New-Object System.Windows.Forms.Panel
    $dlgHeader.Location = New-Object System.Drawing.Point(0, 0)
    $dlgHeader.Size = New-Object System.Drawing.Size($dlgW, 68)
    $dlgHeader.BackColor = [System.Drawing.Color]::FromArgb(10, 22, 34)
    [void]$dlg.Controls.Add($dlgHeader)
    $dlgHeader.Add_Paint({
        param($s,$e)
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(0, 168, 80), 3)
        $e.Graphics.DrawLine($pen, 0, ($s.Height-1), $s.Width, ($s.Height-1))
        $pen.Dispose()
    })
    # Barra accent esquerda
    $dlgAccL = New-Object System.Windows.Forms.Panel
    $dlgAccL.Location = New-Object System.Drawing.Point(0, 0)
    $dlgAccL.Size = New-Object System.Drawing.Size(4, 68)
    $dlgAccL.BackColor = $cGreen
    [void]$dlgHeader.Controls.Add($dlgAccL)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'OS Altertag'
    $title.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = [System.Drawing.Color]::FromArgb(220, 255, 220)
    $title.Location = New-Object System.Drawing.Point(18, 8)
    $title.Size = New-Object System.Drawing.Size(700, 26)
    [void]$dlgHeader.Controls.Add($title)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = 'Selecione a OS que voce acabou de criar. Duplo clique para confirmar rapidamente.'
    $hint.Font = New-Object System.Drawing.Font('Segoe UI', 8)
    $hint.ForeColor = [System.Drawing.Color]::FromArgb(110, 158, 128)
    $hint.Location = New-Object System.Drawing.Point(18, 38)
    $hint.Size = New-Object System.Drawing.Size(820, 16)
    [void]$dlgHeader.Controls.Add($hint)

    # Contador de OS no canto direito do header
    $dlgCount = New-Object System.Windows.Forms.Label
    $dlgCount.Text = "$($Ordens.Count) OS"
    $dlgCount.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
    $dlgCount.ForeColor = [System.Drawing.Color]::FromArgb(60, 180, 100)
    $dlgCount.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
    $dlgCount.Location = New-Object System.Drawing.Point(740, 24)
    $dlgCount.Size = New-Object System.Drawing.Size(130, 20)
    [void]$dlgHeader.Controls.Add($dlgCount)

    # Lista
    $listShell = New-Object System.Windows.Forms.Panel
    $listShell.Location = New-Object System.Drawing.Point(16, 78)
    $listShell.Size = New-Object System.Drawing.Size(858, 340)
    $listShell.BackColor = [System.Drawing.Color]::FromArgb(0, 140, 80)
    $listShell.BorderStyle = 'None'
    [void]$dlg.Controls.Add($listShell)

    $list = New-Object System.Windows.Forms.ListView
    $list.View = 'Details'
    $list.FullRowSelect = $true
    $list.GridLines = $false
    $list.MultiSelect = $false
    $list.HideSelection = $false
    $list.BorderStyle = 'None'
    $list.OwnerDraw = $true
    $list.BackColor = [System.Drawing.Color]::FromArgb(9, 18, 28)
    $list.ForeColor = [System.Drawing.Color]::White
    $list.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
    $list.HeaderStyle = 'Clickable'
    $list.Location = New-Object System.Drawing.Point(1, 1)
    $list.Size = New-Object System.Drawing.Size(856, 338)
    [void]$list.Columns.Add('OS', 88)
    [void]$list.Columns.Add('Tecnico', 112)
    [void]$list.Columns.Add('Status', 110)
    [void]$list.Columns.Add('Criada em', 154)
    [void]$list.Columns.Add('Equipamento', 392)

    $list.Add_DrawColumnHeader({
        param($s, $e)
        $bg = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(12, 28, 42))
        $e.Graphics.FillRectangle($bg, $e.Bounds)
        $bg.Dispose()
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(0, 100, 60))
        $e.Graphics.DrawLine($pen, $e.Bounds.Left, ($e.Bounds.Bottom-1), $e.Bounds.Right, ($e.Bounds.Bottom-1))
        $pen.Dispose()
        $rect = New-Object System.Drawing.Rectangle(($e.Bounds.Left+8), $e.Bounds.Top, ($e.Bounds.Width-10), $e.Bounds.Height)
        [System.Windows.Forms.TextRenderer]::DrawText(
            $e.Graphics, $e.Header.Text,
            (New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)),
            $rect,
            [System.Drawing.Color]::FromArgb(100, 200, 140),
            ([System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::Left -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis)
        )
    })
    $list.Add_DrawItem({ param($s,$e) })
    $list.Add_DrawSubItem({
        param($s, $e)
        $sel = $e.Item.Selected
        $even = ($e.ItemIndex % 2) -eq 0
        $bg = if ($sel) {
            [System.Drawing.Color]::FromArgb(0, 90, 50)
        } elseif ($even) {
            [System.Drawing.Color]::FromArgb(9, 18, 28)
        } else {
            [System.Drawing.Color]::FromArgb(11, 22, 34)
        }
        $fg = if ($sel) { [System.Drawing.Color]::FromArgb(200, 255, 210) } else { [System.Drawing.Color]::FromArgb(200, 228, 210) }
        # Coluna OS: destaque especial
        if ($e.ColumnIndex -eq 0 -and -not $sel) { $fg = [System.Drawing.Color]::FromArgb(80, 210, 130) }
        # Coluna Status: colorir por estado
        if ($e.ColumnIndex -eq 2 -and -not $sel) {
            $st = $e.SubItem.Text.ToLower()
            $fg = if ($st -like '*aberto*') { [System.Drawing.Color]::FromArgb(80, 200, 255) }
                  elseif ($st -like '*conclu*') { [System.Drawing.Color]::FromArgb(80, 210, 130) }
                  else { [System.Drawing.Color]::FromArgb(255, 200, 80) }
        }
        $b = New-Object System.Drawing.SolidBrush($bg)
        $e.Graphics.FillRectangle($b, $e.Bounds)
        $b.Dispose()
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(16, 38, 28))
        $e.Graphics.DrawLine($pen, $e.Bounds.Left, ($e.Bounds.Bottom-1), $e.Bounds.Right, ($e.Bounds.Bottom-1))
        $pen.Dispose()
        $rect = New-Object System.Drawing.Rectangle(($e.Bounds.Left+8), $e.Bounds.Top, ($e.Bounds.Width-12), $e.Bounds.Height)
        $flags = [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::Left -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis
        $fnt = if ($e.ColumnIndex -eq 0) { New-Object System.Drawing.Font('Segoe UI', 8.5, [System.Drawing.FontStyle]::Bold) } else { $list.Font }
        [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, $e.SubItem.Text, $fnt, $rect, $fg, $flags)
    })

    foreach ($os in @($Ordens)) {
        $num = [int]$os.numero
        if ($num -lt 1) { continue }
        $row = New-Object System.Windows.Forms.ListViewItem((Format-OsCodigo -Numero $num))
        [void]$row.SubItems.Add([string]$os.tecnico)
        [void]$row.SubItems.Add([string]$os.statusOs)
        [void]$row.SubItems.Add([string]$os.dataCadastro)
        [void]$row.SubItems.Add([string]$os.equipamento)
        $row.Tag = $os
        [void]$list.Items.Add($row)
    }
    if ($list.Items.Count -gt 0) { $list.Items[0].Selected = $true }
    $listShell.Controls.Add($list)

    # ---- Botoes inferiores ----
    $btnY = 432

    $manual = New-DlgBtn 'Digitar manual' 16 $btnY 148 36 `
        ([System.Drawing.Color]::FromArgb(16, 30, 46)) `
        ([System.Drawing.Color]::FromArgb(130, 175, 210)) `
        ([System.Drawing.Color]::FromArgb(28, 50, 72)) `
        ([System.Drawing.Color]::FromArgb(40, 80, 116))
    [void]$dlg.Controls.Add($manual)

    # Botao Editar OS
    $btnEdit = New-DlgBtn 'Editar OS' 174 $btnY 132 36 `
        ([System.Drawing.Color]::FromArgb(36, 28, 6)) `
        ([System.Drawing.Color]::FromArgb(255, 196, 60)) `
        ([System.Drawing.Color]::FromArgb(64, 48, 6)) `
        ([System.Drawing.Color]::FromArgb(120, 90, 10))
    [void]$dlg.Controls.Add($btnEdit)

    $cancel = New-DlgBtn 'Cancelar' 596 $btnY 126 36 `
        ([System.Drawing.Color]::FromArgb(44, 18, 22)) `
        ([System.Drawing.Color]::FromArgb(220, 110, 120)) `
        ([System.Drawing.Color]::FromArgb(66, 24, 30)) `
        ([System.Drawing.Color]::FromArgb(110, 50, 60))
    [void]$dlg.Controls.Add($cancel)

    $ok = New-DlgBtn 'Usar OS selecionada' 732 $btnY 142 36 `
        ([System.Drawing.Color]::FromArgb(0, 80, 46)) `
        ([System.Drawing.Color]::White) `
        ([System.Drawing.Color]::FromArgb(0, 110, 62)) `
        ([System.Drawing.Color]::FromArgb(30, 200, 110))
    [void]$dlg.Controls.Add($ok)

    # ---- Handler Editar OS ----
    $btnEdit.Add_Click({
        if ($list.SelectedItems.Count -lt 1) {
            [System.Windows.Forms.MessageBox]::Show('Selecione uma OS para editar.', 'Editar OS', 'OK', 'Warning') | Out-Null
            return
        }
        $osObj = $list.SelectedItems[0].Tag
        $selIdx = $list.SelectedItems[0].Index

        $ed = New-Object System.Windows.Forms.Form
        $ed.Text = 'Editar OS ' + (Format-OsCodigo -Numero ([int]$osObj.numero))
        $ed.Size = New-Object System.Drawing.Size(480, 340)
        $ed.StartPosition = 'CenterParent'
        $ed.BackColor = [System.Drawing.Color]::FromArgb(8, 16, 26)
        $ed.FormBorderStyle = 'FixedDialog'
        $ed.MaximizeBox = $false; $ed.MinimizeBox = $false

        # Header do popup
        $edHead = New-Object System.Windows.Forms.Panel
        $edHead.Location = New-Object System.Drawing.Point(0,0)
        $edHead.Size = New-Object System.Drawing.Size(480, 52)
        $edHead.BackColor = [System.Drawing.Color]::FromArgb(12, 24, 38)
        [void]$ed.Controls.Add($edHead)
        $edAccL = New-Object System.Windows.Forms.Panel
        $edAccL.Location = New-Object System.Drawing.Point(0,0)
        $edAccL.Size = New-Object System.Drawing.Size(3, 52)
        $edAccL.BackColor = [System.Drawing.Color]::FromArgb(255, 196, 60)
        [void]$edHead.Controls.Add($edAccL)
        $edTitle = New-Object System.Windows.Forms.Label
        $edTitle.Text = 'Editar OS ' + (Format-OsCodigo -Numero ([int]$osObj.numero))
        $edTitle.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
        $edTitle.ForeColor = [System.Drawing.Color]::FromArgb(255, 210, 80)
        $edTitle.Location = New-Object System.Drawing.Point(14, 8)
        $edTitle.Size = New-Object System.Drawing.Size(420, 20)
        [void]$edHead.Controls.Add($edTitle)
        $edSub = New-Object System.Windows.Forms.Label
        $edSub.Text = [string]$osObj.equipamento
        $edSub.Font = New-Object System.Drawing.Font('Segoe UI', 7.5)
        $edSub.ForeColor = [System.Drawing.Color]::FromArgb(100, 148, 178)
        $edSub.Location = New-Object System.Drawing.Point(14, 32)
        $edSub.Size = New-Object System.Drawing.Size(420, 14)
        [void]$edHead.Controls.Add($edSub)

        function Ed-Field {
            param([string]$lbl, [string]$val, [int]$y)
            $lbF = New-Object System.Windows.Forms.Label
            $lbF.Text = $lbl
            $lbF.Font = New-Object System.Drawing.Font('Segoe UI', 7.5, [System.Drawing.FontStyle]::Bold)
            $lbF.ForeColor = [System.Drawing.Color]::FromArgb(100, 148, 178)
            $lbF.Location = New-Object System.Drawing.Point(20, $y)
            $lbF.Size = New-Object System.Drawing.Size(420, 14)
            [void]$ed.Controls.Add($lbF)
            $tb = New-Object System.Windows.Forms.TextBox
            $tb.Text = $val
            $tb.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
            $tb.ForeColor = [System.Drawing.Color]::FromArgb(220, 240, 255)
            $tb.BackColor = [System.Drawing.Color]::FromArgb(14, 28, 44)
            $tb.BorderStyle = 'FixedSingle'
            $tb.Location = New-Object System.Drawing.Point(20, ($y+16))
            $tb.Size = New-Object System.Drawing.Size(430, 26)
            [void]$ed.Controls.Add($tb)
            return $tb
        }

        $tbTec  = Ed-Field 'TECNICO'    ([string]$osObj.tecnico)    64
        $tbStat = Ed-Field 'STATUS'     ([string]$osObj.statusOs)  118
        $tbEq   = Ed-Field 'EQUIPAMENTO' ([string]$osObj.equipamento) 172

        $edSave = New-Object System.Windows.Forms.Button
        $edSave.Text = 'Salvar alteracoes'
        $edSave.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9, [System.Drawing.FontStyle]::Bold)
        $edSave.ForeColor = [System.Drawing.Color]::White
        $edSave.BackColor = [System.Drawing.Color]::FromArgb(0, 80, 46)
        $edSave.FlatStyle = 'Flat'
        $edSave.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(30, 200, 110)
        $edSave.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(0, 110, 62)
        $edSave.Location = New-Object System.Drawing.Point(20, 260)
        $edSave.Size = New-Object System.Drawing.Size(200, 34)
        $edSave.Cursor = [System.Windows.Forms.Cursors]::Hand
        [void]$ed.Controls.Add($edSave)

        $edCancel = New-Object System.Windows.Forms.Button
        $edCancel.Text = 'Cancelar'
        $edCancel.Font = New-Object System.Drawing.Font('Segoe UI', 8.5, [System.Drawing.FontStyle]::Bold)
        $edCancel.ForeColor = [System.Drawing.Color]::FromArgb(180, 110, 118)
        $edCancel.BackColor = [System.Drawing.Color]::FromArgb(36, 16, 20)
        $edCancel.FlatStyle = 'Flat'
        $edCancel.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(90, 40, 50)
        $edCancel.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(54, 22, 28)
        $edCancel.Location = New-Object System.Drawing.Point(250, 260)
        $edCancel.Size = New-Object System.Drawing.Size(120, 34)
        $edCancel.Cursor = [System.Windows.Forms.Cursors]::Hand
        [void]$ed.Controls.Add($edCancel)
        $edCancel.Add_Click({ $ed.Close() })

        $tbTecRef = $tbTec; $tbStatRef = $tbStat; $tbEqRef = $tbEq
        $edSave.Add_Click({
            # Atualiza o objeto local e o item da lista
            $osObj.tecnico    = $tbTecRef.Text.Trim()
            $osObj.statusOs   = $tbStatRef.Text.Trim()
            $osObj.equipamento = $tbEqRef.Text.Trim()
            $listItem = $list.Items[$selIdx]
            $listItem.SubItems[1].Text = $osObj.tecnico
            $listItem.SubItems[2].Text = $osObj.statusOs
            $listItem.SubItems[4].Text = $osObj.equipamento
            $list.Invalidate()
            # Tenta enviar para o servidor
            try {
                $payload = @{ tecnico=$osObj.tecnico; statusOs=$osObj.statusOs; equipamento=$osObj.equipamento } | ConvertTo-Json -Compress
                Invoke-RestMethod -Uri ('{0}/editar-os/{1}' -f (Get-ServidorBaseUrl), ([int]$osObj.numero)) `
                    -Method Put -Body $payload -ContentType 'application/json; charset=utf-8' -TimeoutSec 10 -ErrorAction Stop | Out-Null
                [System.Windows.Forms.MessageBox]::Show('OS atualizada com sucesso!', 'Editar OS', 'OK', 'Information') | Out-Null
            } catch {
                [System.Windows.Forms.MessageBox]::Show("Alteracao salva localmente.`nNao foi possivel sincronizar com o servidor: $_", 'Editar OS', 'OK', 'Warning') | Out-Null
            }
            $ed.Close()
        }.GetNewClosure())

        $ed.ShowDialog() | Out-Null
    }.GetNewClosure())

    $script:selectedAltertagOs = $null
    $ok.Add_Click({
        if ($list.SelectedItems.Count -lt 1) {
            [System.Windows.Forms.MessageBox]::Show('Selecione uma OS da lista.', 'OS Altertag', 'OK', 'Warning') | Out-Null
            return
        }
        $selecionada = $list.SelectedItems[0].Tag
        if (-not (Show-OsAltertagDetalheConfirm -Os $selecionada)) { return }
        $script:selectedAltertagOs = if ($script:altertagOsDetalheConfirmado) { $script:altertagOsDetalheConfirmado } else { $selecionada }
        $dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $dlg.Close()
    })
    $list.Add_DoubleClick({ $ok.PerformClick() })
    $cancel.Add_Click({ $dlg.DialogResult = [System.Windows.Forms.DialogResult]::Cancel; $dlg.Close() })
    $manual.Add_Click({
        $dlg.DialogResult = [System.Windows.Forms.DialogResult]::Retry
        $dlg.Close()
    })
    $res = $dlg.ShowDialog()
    if ($res -eq [System.Windows.Forms.DialogResult]::Retry) {
        Prompt-OsManual
        return $true
    }
    if ($res -ne [System.Windows.Forms.DialogResult]::OK -or -not $script:selectedAltertagOs) { return $false }

    $sel = $script:selectedAltertagOs
    Set-OsNumeroAtual -Numero ([int]$sel.numero) -Fonte 'altertag'
    $script:altertagOsAtual = $sel
    $script:ultimaSincronizacaoOs = Get-Date -Format 'dd/MM HH:mm'
    Set-AppStatus -Texto "OS Altertag selecionada: $(Format-OsCodigo -Numero ([int]$sel.numero)) | $([string]$sel.statusOs)" -Cor $cGreen
    return $true
}

function Sync-OsFromAltertag {
    param([switch]$Silent)
    try {
        $erroServidor = ''
        try {
            if (-not $Silent) {
                $respRecentes = Invoke-CaijServer -Path '/os-recentes?limit=15&produtos=1' -Method GET -TimeoutSec 25 -Retries 2
                if ($respRecentes -and [string]$respRecentes.status -eq 'ok') {
                    $selecionouOs = Select-OsFromAltertagRecentes -Ordens @($respRecentes.ordens)
                    if (-not $selecionouOs) {
                        Set-AppStatus -Texto 'Selecao de OS Altertag cancelada' -Cor $cMuted
                    }
                    return
                } elseif ($respRecentes -and $respRecentes.mensagem) {
                    $erroServidor = [string]$respRecentes.mensagem
                }
            } else {
                $respOs = Invoke-CaijServer -Path '/status-os' -Method GET -TimeoutSec 12 -Retries 2
                if ($respOs -and [string]$respOs.status -eq 'ok' -and $respOs.proximoDisponivel) {
                    $proximaSrv = [int]$respOs.proximoDisponivel
                    if (-not $script:osDefinidaPorAltertag -and -not $script:osDefinidaManual) {
                        Set-OsNumeroAtual -Numero $proximaSrv -Fonte 'sync'
                    }
                    $script:ultimaSincronizacaoOs = Get-Date -Format 'dd/MM HH:mm'
                    $syncLabel = if ($respOs.sincronizacao) { [string]$respOs.sincronizacao } else { 'ok' }
                    Set-AppStatus -Texto "Servidor online | ultima API: $(Format-OsCodigo -Numero ([int]$respOs.ultimoConfirmado)) | proxima sugerida: $(Format-OsCodigo -Numero $proximaSrv)" -Cor $cGreen
                    return
                }
                if ($respOs -and $respOs.mensagem) { $erroServidor = [string]$respOs.mensagem }
            }

            $respOs = Invoke-CaijServer -Path '/status-os' -Method GET -TimeoutSec 12 -Retries 2
            if ($respOs -and [string]$respOs.status -eq 'ok' -and $respOs.proximoDisponivel) {
                $proximaSrv = [int]$respOs.proximoDisponivel
                if (-not $script:osDefinidaPorAltertag -and -not $script:osDefinidaManual) {
                    Set-OsNumeroAtual -Numero $proximaSrv -Fonte 'sync'
                }
                $script:ultimaSincronizacaoOs = Get-Date -Format 'dd/MM HH:mm'
                $syncLabel = if ($respOs.sincronizacao) { [string]$respOs.sincronizacao } else { 'ok' }
                Set-AppStatus -Texto "Servidor online | proxima sugerida: $(Format-OsCodigo -Numero $proximaSrv) | sync: $syncLabel" -Cor $cGreen
                if (-not $Silent) {
                    [System.Windows.Forms.MessageBox]::Show(
                        "Nao foi possivel abrir a lista de OS recentes.`n`nProxima OS sugerida pelo servidor: $(Format-OsCodigo -Numero $proximaSrv)`nSincronizacao: $syncLabel",
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

        Set-AppStatus -Texto "Servidor offline ou OS indisponivel | OS local: $(Format-OsCodigo -Numero $script:osNumero) | clique em [Configurar] para definir o IP" -Cor $cYellow
        Show-BotaoConfigurarServidor
        if (-not $Silent) {
            $resConf = [System.Windows.Forms.MessageBox]::Show(
                "Nao foi possivel consultar o servidor de OS.`n`nO app continuara usando o contador local ($(Format-OsCodigo -Numero $script:osNumero)).`n`nDeseja configurar o endereco do servidor agora?",
                'Servidor nao encontrado',
                'YesNo',
                'Warning'
            )
            if ($resConf -eq [System.Windows.Forms.DialogResult]::Yes) { Show-DialogConfigurarServidor }
        }
    } catch {
        Set-AppStatus -Texto "Erro de conexao | OS local: $(Format-OsCodigo -Numero $script:osNumero)" -Cor $cYellow
        Show-BotaoConfigurarServidor
        if (-not $Silent) {
            $resConf = [System.Windows.Forms.MessageBox]::Show(
                "Erro ao conectar ao servidor:`n$($_.Exception.Message)`n`nDeseja configurar o endereco do servidor?",
                'Erro de conexao',
                'YesNo',
                'Warning'
            )
            if ($resConf -eq [System.Windows.Forms.DialogResult]::Yes) { Show-DialogConfigurarServidor }
        }
    }
}

function Show-BotaoConfigurarServidor {
    try {
        if ($script:btnConfigurarSrv -and -not $script:btnConfigurarSrv.IsDisposed) {
            $script:btnConfigurarSrv.Visible = $true
        }
    } catch {}
}

function Show-DialogConfigurarServidor {
    $cfgPath = Join-Path (Split-Path -Parent $PSCommandPath) 'caij_servidor_url.txt'
    $urlAtual = ''
    if ($script:servidorBaseUrlCache) { $urlAtual = $script:servidorBaseUrlCache }
    elseif (Test-Path $cfgPath) { try { $urlAtual = (Get-Content $cfgPath -Raw).Trim() } catch {} }
    if (-not $urlAtual) { $urlAtual = 'http://192.168.15.127:9100' }

    $f = New-Object System.Windows.Forms.Form
    $f.Text = 'Configurar Servidor CAIJ'
    $f.Size = New-Object System.Drawing.Size(460, 220)
    $f.StartPosition = 'CenterScreen'
    $f.BackColor = [System.Drawing.Color]::FromArgb(8, 16, 26)
    $f.FormBorderStyle = 'FixedDialog'
    $f.MaximizeBox = $false; $f.MinimizeBox = $false

    $lHead = New-Object System.Windows.Forms.Label
    $lHead.Text = 'Endereco do servidor CAIJ'
    $lHead.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $lHead.ForeColor = [System.Drawing.Color]::FromArgb(0, 180, 240)
    $lHead.Location = New-Object System.Drawing.Point(16, 14)
    $lHead.Size = New-Object System.Drawing.Size(410, 22)
    [void]$f.Controls.Add($lHead)

    $lHint = New-Object System.Windows.Forms.Label
    $lHint.Text = 'Digite o IP ou URL completa do servidor (ex: http://192.168.15.127:9100)'
    $lHint.Font = New-Object System.Drawing.Font('Segoe UI', 8)
    $lHint.ForeColor = [System.Drawing.Color]::FromArgb(90, 140, 175)
    $lHint.Location = New-Object System.Drawing.Point(16, 40)
    $lHint.Size = New-Object System.Drawing.Size(420, 16)
    [void]$f.Controls.Add($lHint)

    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Text = $urlAtual
    $tb.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $tb.ForeColor = [System.Drawing.Color]::FromArgb(220, 240, 255)
    $tb.BackColor = [System.Drawing.Color]::FromArgb(12, 26, 42)
    $tb.BorderStyle = 'FixedSingle'
    $tb.Location = New-Object System.Drawing.Point(16, 62)
    $tb.Size = New-Object System.Drawing.Size(416, 26)
    [void]$f.Controls.Add($tb)

    $lStatus = New-Object System.Windows.Forms.Label
    $lStatus.Text = ''
    $lStatus.Font = New-Object System.Drawing.Font('Segoe UI', 8)
    $lStatus.ForeColor = [System.Drawing.Color]::FromArgb(255, 200, 60)
    $lStatus.Location = New-Object System.Drawing.Point(16, 96)
    $lStatus.Size = New-Object System.Drawing.Size(420, 16)
    [void]$f.Controls.Add($lStatus)

    $btnTestar = New-Object System.Windows.Forms.Button
    $btnTestar.Text = 'Testar conexao'
    $btnTestar.Font = New-Object System.Drawing.Font('Segoe UI', 8.5, [System.Drawing.FontStyle]::Bold)
    $btnTestar.ForeColor = [System.Drawing.Color]::FromArgb(140, 200, 255)
    $btnTestar.BackColor = [System.Drawing.Color]::FromArgb(10, 36, 60)
    $btnTestar.FlatStyle = 'Flat'
    $btnTestar.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(30, 90, 140)
    $btnTestar.Location = New-Object System.Drawing.Point(16, 122)
    $btnTestar.Size = New-Object System.Drawing.Size(138, 34)
    $btnTestar.Cursor = [System.Windows.Forms.Cursors]::Hand
    [void]$f.Controls.Add($btnTestar)

    $btnSalvar = New-Object System.Windows.Forms.Button
    $btnSalvar.Text = 'Salvar e reconectar'
    $btnSalvar.Font = New-Object System.Drawing.Font('Segoe UI', 8.5, [System.Drawing.FontStyle]::Bold)
    $btnSalvar.ForeColor = [System.Drawing.Color]::White
    $btnSalvar.BackColor = [System.Drawing.Color]::FromArgb(0, 80, 46)
    $btnSalvar.FlatStyle = 'Flat'
    $btnSalvar.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(30, 200, 110)
    $btnSalvar.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(0, 110, 62)
    $btnSalvar.Location = New-Object System.Drawing.Point(166, 122)
    $btnSalvar.Size = New-Object System.Drawing.Size(170, 34)
    $btnSalvar.Cursor = [System.Windows.Forms.Cursors]::Hand
    [void]$f.Controls.Add($btnSalvar)

    $tbRef = $tb; $lRef = $lStatus; $fRef = $f
    $btnTestar.Add_Click({
        $url = $tbRef.Text.Trim().TrimEnd('/')
        if (-not $url.StartsWith('http')) { $url = 'http://' + $url }
        $lRef.ForeColor = [System.Drawing.Color]::FromArgb(255, 200, 60)
        $lRef.Text = 'Testando...'
        $fRef.Refresh()
        if (Test-ServidorUrl -BaseUrl $url -TimeoutSec 4) {
            $lRef.ForeColor = [System.Drawing.Color]::FromArgb(60, 210, 120)
            $lRef.Text = 'Conexao OK!'
        } else {
            $lRef.ForeColor = [System.Drawing.Color]::FromArgb(230, 80, 80)
            $lRef.Text = 'Sem resposta nesse endereco.'
        }
    }.GetNewClosure())

    $btnSalvar.Add_Click({
        $url = $tbRef.Text.Trim().TrimEnd('/')
        if (-not $url.StartsWith('http')) { $url = 'http://' + $url }
        $script:servidorBaseUrlCache = $url
        try { Set-Content -Path $cfgPath -Value $url -Encoding UTF8 } catch {}
        $fRef.Close()
        Sync-OsFromAltertag -Silent
        if ($script:btnConfigurarSrv -and -not $script:btnConfigurarSrv.IsDisposed) {
            $script:btnConfigurarSrv.Visible = $false
        }
    }.GetNewClosure())

    $f.ShowDialog() | Out-Null
}

$osSyncBtn.Add_Click({ Sync-OsFromAltertag })

$hLineY = 30 + $hH
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

$script:py = 10
$CW = 660  # content width

# ---- secao ----
function Add-Sec {
    param([string]$label, [System.Drawing.Color]$cor)
    $script:py += 5
    $sp = New-Object System.Windows.Forms.Panel
    $sp.BackColor   = [System.Drawing.Color]::FromArgb(7, 13, 22)
    $sp.Location    = New-Object System.Drawing.Point(16, $script:py)
    $sp.Size        = New-Object System.Drawing.Size($CW, 18)
    $sp.BorderStyle = 'None'
    [void]$scroll.Controls.Add($sp)
    $abar = New-Object System.Windows.Forms.Panel
    $abar.BackColor = $cor
    $abar.Location  = New-Object System.Drawing.Point(0, 0)
    $abar.Size      = New-Object System.Drawing.Size(3, 18)
    [void]$sp.Controls.Add($abar)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text      = $label.ToUpper()
    $lbl.Font      = New-Object System.Drawing.Font('Segoe UI', 7, [System.Drawing.FontStyle]::Bold)
    $lbl.ForeColor = $cor
    $lbl.Location  = New-Object System.Drawing.Point(10, 2)
    $lbl.Size      = New-Object System.Drawing.Size(500, 14)
    [void]$sp.Controls.Add($lbl)
    $script:py += 20
}

# ---- linha simples: label esquerda | valor direita, altura compacta ----
function Add-Row {
    param([string]$k, [string]$v, [System.Drawing.Color]$vc, [System.Drawing.Color]$ac)
    if (-not $vc) { $vc = $cMain }
    if (-not $ac) { $ac = $cBorder }

    $p = New-Object System.Windows.Forms.Panel
    $p.BackColor   = [System.Drawing.Color]::FromArgb(11, 20, 31)
    $p.Location    = New-Object System.Drawing.Point(16, $script:py)
    $p.Size        = New-Object System.Drawing.Size($CW, 24)
    $p.BorderStyle = 'None'
    [void]$scroll.Controls.Add($p)

    $abar = New-Object System.Windows.Forms.Panel
    $abar.BackColor = $ac
    $abar.Location  = New-Object System.Drawing.Point(0, 3)
    $abar.Size      = New-Object System.Drawing.Size(3, 18)
    [void]$p.Controls.Add($abar)

    $lk = New-Object System.Windows.Forms.Label
    $lk.Text      = $k
    $lk.Font      = New-Object System.Drawing.Font('Segoe UI', 8)
    $lk.ForeColor = [System.Drawing.Color]::FromArgb(96, 138, 172)
    $lk.Location  = New-Object System.Drawing.Point(10, 4)
    $lk.Size      = New-Object System.Drawing.Size(138, 16)
    [void]$p.Controls.Add($lk)

    $lv = New-Object System.Windows.Forms.Label
    $lv.Text         = $v
    $lv.Font         = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5, [System.Drawing.FontStyle]::Bold)
    $lv.ForeColor    = $vc
    $lv.Location     = New-Object System.Drawing.Point(150, 4)
    $lv.Size         = New-Object System.Drawing.Size(490, 16)
    $lv.AutoEllipsis = $true
    [void]$p.Controls.Add($lv)

    $div = New-Object System.Windows.Forms.Panel
    $div.BackColor = [System.Drawing.Color]::FromArgb(14, 26, 40)
    $div.Location  = New-Object System.Drawing.Point(3, 23)
    $div.Size      = New-Object System.Drawing.Size(($CW - 3), 1)
    [void]$p.Controls.Add($div)

    $script:py += 25
}

# ---- duas colunas compactas ----
function Add-Row2 {
    param(
        [string]$k1, [string]$v1, [System.Drawing.Color]$c1,
        [string]$k2, [string]$v2, [System.Drawing.Color]$c2,
        [System.Drawing.Color]$ac
    )
    if (-not $ac) { $ac = $cBorder }
    $half = [int](($CW - 4) / 2)

    foreach ($side in @(
        @{ k=$k1; v=$v1; c=$c1; X=16 },
        @{ k=$k2; v=$v2; c=$c2; X=(16 + $half + 4) }
    )) {
        $p = New-Object System.Windows.Forms.Panel
        $p.BackColor   = [System.Drawing.Color]::FromArgb(11, 20, 31)
        $p.Location    = New-Object System.Drawing.Point([int]$side.X, $script:py)
        $p.Size        = New-Object System.Drawing.Size($half, 24)
        $p.BorderStyle = 'None'
        [void]$scroll.Controls.Add($p)

        $abar = New-Object System.Windows.Forms.Panel
        $abar.BackColor = $ac
        $abar.Location  = New-Object System.Drawing.Point(0, 3)
        $abar.Size      = New-Object System.Drawing.Size(3, 18)
        [void]$p.Controls.Add($abar)

        $lk = New-Object System.Windows.Forms.Label
        $lk.Text      = [string]$side.k
        $lk.Font      = New-Object System.Drawing.Font('Segoe UI', 8)
        $lk.ForeColor = [System.Drawing.Color]::FromArgb(96, 138, 172)
        $lk.Location  = New-Object System.Drawing.Point(10, 4)
        $lk.Size      = New-Object System.Drawing.Size(96, 16)
        [void]$p.Controls.Add($lk)

        $lv = New-Object System.Windows.Forms.Label
        $lv.Text         = [string]$side.v
        $lv.Font         = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5, [System.Drawing.FontStyle]::Bold)
        $lv.ForeColor    = [System.Drawing.Color]$side.c
        $lv.Location     = New-Object System.Drawing.Point(108, 4)
        $lv.Size         = New-Object System.Drawing.Size(($half - 112), 16)
        $lv.AutoEllipsis = $true
        [void]$p.Controls.Add($lv)

        $div = New-Object System.Windows.Forms.Panel
        $div.BackColor = [System.Drawing.Color]::FromArgb(14, 26, 40)
        $div.Location  = New-Object System.Drawing.Point(3, 23)
        $div.Size      = New-Object System.Drawing.Size(($half - 3), 1)
        [void]$p.Controls.Add($div)
    }

    $script:py += 25
}

function Gap { $script:py += 4 }

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
Add-Sec $(if ($info.MostrarBateria) { 'Sistema & Bateria' } else { 'Sistema' }) $cPurple
Add-Row 'Windows' $info.Windows $cMain $cPurple
# Hostname removido para manter layout mais limpo
if ($info.MostrarBateria) {
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
        $script:py += 6
    }
}
Gap

$contentH = $script:py + 4
$scroll.Size = New-Object System.Drawing.Size($W, $contentH)

# ================================================
# BARRA DE ACOES
# ================================================
$actY = $scrollY + $contentH

$actBar = New-Object System.Windows.Forms.Panel
$actBar.BackColor = [System.Drawing.Color]::FromArgb(8, 16, 26)
$actBar.Location  = New-Object System.Drawing.Point(0, $actY)
$actBar.Size      = New-Object System.Drawing.Size($W, 82)
$form.Controls.Add($actBar)

$actBar.Add_Paint({
    param($s, $e)
    $r = New-Object System.Drawing.Rectangle(0, 0, $s.Width, $s.Height)
    $b = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $r,
        [System.Drawing.Color]::FromArgb(12, 24, 38),
        [System.Drawing.Color]::FromArgb(6, 12, 20),
        [System.Drawing.Drawing2D.LinearGradientMode]::Vertical
    )
    $e.Graphics.FillRectangle($b, $r)
    $b.Dispose()
    # linha topo cyan
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(0, 140, 200), 1)
    $e.Graphics.DrawLine($pen, 0, 0, $s.Width, 0)
    $pen.Dispose()
})

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
    $b.FlatAppearance.BorderSize  = 1
    $b.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb([int][math]::Min($bg.R + 40, 255), [int][math]::Min($bg.G + 40, 255), [int][math]::Min($bg.B + 55, 255))
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
    Set-RoundedControl -Control $b -Radius 12
    $b.Add_SizeChanged({ Set-RoundedControl -Control $this -Radius 12 })
    $actBar.Controls.Add($b)
    return $b
}

$bY1 = 8
$bH  = 30
$g   = 7

$tooltip = New-Object System.Windows.Forms.ToolTip
$tooltip.BackColor = [System.Drawing.Color]::FromArgb(20, 30, 44)
$tooltip.ForeColor = [System.Drawing.Color]::White
$tooltip.InitialDelay = 400
$tooltip.ReshowDelay  = 200

$fBtn  = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5, [System.Drawing.FontStyle]::Bold)
$fBtnL = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5, [System.Drawing.FontStyle]::Bold)

# Linha 1 — Central de Testes (destaque primario, borda cyan)
$btnTestes = New-Btn ([string][char]0x26A1 + '  Central de Testes') 12 $bY1 676 $bH `
    ([System.Drawing.Color]::FromArgb(0, 32, 58)) `
    ([System.Drawing.Color]::FromArgb(0, 188, 255)) `
    ([System.Drawing.Color]::FromArgb(0, 58, 100)) `
    $fBtnL
$tooltip.SetToolTip($btnTestes, 'Abre a central completa de testes')

# Linha 2 — 3 botoes uniformes
$row2Y = ($bY1 + $bH + $g)
$b2H   = 30
$b2W1  = 168   # OS Altertag
$b2W2  = 168   # Cadastrar OS
$b2W3  = [int](676 - $b2W1 - $b2W2 - 8)  # Imprimir (resto)
$b2X2  = 12 + $b2W1 + 4
$b2X3  = $b2X2 + $b2W2 + 4

$btnOsAltertag = New-Btn ([string][char]0x2261 + '  OS Altertag') 12 $row2Y $b2W1 $b2H `
    ([System.Drawing.Color]::FromArgb(4, 44, 32)) `
    ([System.Drawing.Color]::FromArgb(80, 220, 160)) `
    ([System.Drawing.Color]::FromArgb(0, 88, 60)) `
    $fBtn
$tooltip.SetToolTip($btnOsAltertag, 'Abre a lista de OS recentes do Altertag para escolher a OS real')

$btnCadastrarOs = New-Btn ('+  Cadastrar OS') $b2X2 $row2Y $b2W2 $b2H `
    ([System.Drawing.Color]::FromArgb(46, 28, 4)) `
    ([System.Drawing.Color]::FromArgb(255, 200, 80)) `
    ([System.Drawing.Color]::FromArgb(100, 60, 0)) `
    $fBtn
$tooltip.SetToolTip($btnCadastrarOs, 'Abre a preparacao do cadastro da OS pelo Altertag')

$btnImprimir = New-Btn ([string][char]0x2399 + '  Imprimir Etiqueta via Rede') $b2X3 $row2Y $b2W3 $b2H `
    ([System.Drawing.Color]::FromArgb(0, 28, 58)) `
    ([System.Drawing.Color]::FromArgb(140, 210, 255)) `
    ([System.Drawing.Color]::FromArgb(0, 60, 110)) `
    $fBtnL

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
    if ($info.MostrarBateria) { $txt += "Bateria: $($info.BatSaude)`n" }
    $txt += "Windows: $($info.Windows)`n"
    return $txt
}


function Show-CadastroOsConfirm {
    param(
        [System.Windows.Forms.Form]$Owner,
        [string]$OsCodigo,
        [string]$Produto,
        [string]$Quantidade,
        [string]$Serial,
        [string]$Referencia,
        [string]$Servicos,
        [string]$Localizacao
    )

    $formConfirm = New-Object System.Windows.Forms.Form
    $formConfirm.Text = 'Confirmar cadastro'
    $formConfirm.ClientSize = New-Object System.Drawing.Size(600, 470)
    $formConfirm.StartPosition = 'CenterParent'
    $formConfirm.BackColor = [System.Drawing.Color]::FromArgb(6, 13, 22)
    $formConfirm.ForeColor = [System.Drawing.Color]::FromArgb(236, 245, 255)
    $formConfirm.FormBorderStyle = 'None'
    $formConfirm.ShowInTaskbar = $false
    $formConfirm.MaximizeBox = $false
    $formConfirm.MinimizeBox = $false
    $formConfirm.KeyPreview = $true
    Set-DoubleBuffered $formConfirm
    Set-RoundedControl -Control $formConfirm -Radius 12
    $formConfirm.Add_SizeChanged({ Set-RoundedControl -Control $this -Radius 12 })
    $formConfirm.Add_Paint({
        param($s, $e)
        $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $border = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(40, 116, 158), 1)
        $e.Graphics.DrawRectangle($border, 0, 0, ($s.ClientSize.Width - 1), ($s.ClientSize.Height - 1))
        $border.Dispose()
    })

    $headerConfirm = New-Object System.Windows.Forms.Panel
    $headerConfirm.Location = New-Object System.Drawing.Point(0, 0)
    $headerConfirm.Size = New-Object System.Drawing.Size(600, 78)
    $headerConfirm.BackColor = [System.Drawing.Color]::FromArgb(9, 21, 34)
    [void]$formConfirm.Controls.Add($headerConfirm)
    $headerConfirm.Add_Paint({
        param($s, $e)
        $line = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(24, 185, 255), 2)
        $e.Graphics.DrawLine($line, 0, ($s.Height - 2), $s.Width, ($s.Height - 2))
        $line.Dispose()
        $dimLine = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(22, 55, 78), 1)
        $e.Graphics.DrawLine($dimLine, 380, 12, 430, 12)
        $e.Graphics.DrawLine($dimLine, 392, 18, 430, 18)
        $dimLine.Dispose()
    })

    $headerRail = New-Object System.Windows.Forms.Panel
    $headerRail.Location = New-Object System.Drawing.Point(0, 0)
    $headerRail.Size = New-Object System.Drawing.Size(4, 78)
    $headerRail.BackColor = [System.Drawing.Color]::FromArgb(24, 185, 255)
    [void]$headerConfirm.Controls.Add($headerRail)

    $eyebrow = New-Object System.Windows.Forms.Label
    $eyebrow.Text = 'ALTERTAG / NOVA OS'
    $eyebrow.Font = New-Object System.Drawing.Font('Segoe UI', 6.8, [System.Drawing.FontStyle]::Bold)
    $eyebrow.ForeColor = [System.Drawing.Color]::FromArgb(80, 184, 230)
    $eyebrow.Location = New-Object System.Drawing.Point(22, 11)
    $eyebrow.Size = New-Object System.Drawing.Size(260, 14)
    [void]$headerConfirm.Controls.Add($eyebrow)

    $titleConfirm = New-Object System.Windows.Forms.Label
    $titleConfirm.Text = 'Confirmar cadastro'
    $titleConfirm.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 15, [System.Drawing.FontStyle]::Bold)
    $titleConfirm.ForeColor = [System.Drawing.Color]::FromArgb(236, 245, 255)
    $titleConfirm.Location = New-Object System.Drawing.Point(20, 29)
    $titleConfirm.Size = New-Object System.Drawing.Size(360, 30)
    [void]$headerConfirm.Controls.Add($titleConfirm)

    $subtitleConfirm = New-Object System.Windows.Forms.Label
    $subtitleConfirm.Text = 'Revise os dados antes de enviar'
    $subtitleConfirm.Font = New-Object System.Drawing.Font('Segoe UI', 7.5)
    $subtitleConfirm.ForeColor = [System.Drawing.Color]::FromArgb(105, 145, 178)
    $subtitleConfirm.Location = New-Object System.Drawing.Point(23, 57)
    $subtitleConfirm.Size = New-Object System.Drawing.Size(320, 14)
    [void]$headerConfirm.Controls.Add($subtitleConfirm)

    $osChip = New-Object System.Windows.Forms.Panel
    $osChip.Location = New-Object System.Drawing.Point(438, 27)
    $osChip.Size = New-Object System.Drawing.Size(132, 36)
    $osChip.BackColor = [System.Drawing.Color]::FromArgb(5, 42, 38)
    [void]$headerConfirm.Controls.Add($osChip)
    Set-RoundedControl -Control $osChip -Radius 8

    $osChipCaption = New-Object System.Windows.Forms.Label
    $osChipCaption.Text = 'OS'
    $osChipCaption.Font = New-Object System.Drawing.Font('Segoe UI', 6.5, [System.Drawing.FontStyle]::Bold)
    $osChipCaption.ForeColor = [System.Drawing.Color]::FromArgb(66, 232, 176)
    $osChipCaption.Location = New-Object System.Drawing.Point(10, 4)
    $osChipCaption.Size = New-Object System.Drawing.Size(32, 12)
    [void]$osChip.Controls.Add($osChipCaption)

    $osChipValue = New-Object System.Windows.Forms.Label
    $osChipValue.Text = $OsCodigo
    $osChipValue.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10, [System.Drawing.FontStyle]::Bold)
    $osChipValue.ForeColor = [System.Drawing.Color]::FromArgb(180, 255, 225)
    $osChipValue.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
    $osChipValue.Location = New-Object System.Drawing.Point(38, 7)
    $osChipValue.Size = New-Object System.Drawing.Size(84, 22)
    [void]$osChip.Controls.Add($osChipValue)

    $closeConfirm = New-Object System.Windows.Forms.Button
    $closeConfirm.Text = 'X'
    $closeConfirm.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
    $closeConfirm.ForeColor = [System.Drawing.Color]::FromArgb(112, 150, 180)
    $closeConfirm.BackColor = [System.Drawing.Color]::FromArgb(9, 21, 34)
    $closeConfirm.FlatStyle = 'Flat'
    $closeConfirm.FlatAppearance.BorderSize = 0
    $closeConfirm.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(68, 24, 34)
    $closeConfirm.Location = New-Object System.Drawing.Point(570, 5)
    $closeConfirm.Size = New-Object System.Drawing.Size(24, 24)
    $closeConfirm.Cursor = [System.Windows.Forms.Cursors]::Hand
    $closeConfirm.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    [void]$headerConfirm.Controls.Add($closeConfirm)

    function Add-ConfirmField {
        param(
            [string]$Label,
            [string]$Value,
            [int]$X,
            [int]$Y,
            [int]$Width,
            [int]$Height,
            [System.Drawing.Color]$Accent,
            [float]$ValueSize = 9
        )

        $field = New-Object System.Windows.Forms.Panel
        $field.Location = New-Object System.Drawing.Point($X, $Y)
        $field.Size = New-Object System.Drawing.Size($Width, $Height)
        $field.BackColor = [System.Drawing.Color]::FromArgb(11, 23, 37)
        [void]$formConfirm.Controls.Add($field)
        Set-RoundedControl -Control $field -Radius 6

        $rail = New-Object System.Windows.Forms.Panel
        $rail.Location = New-Object System.Drawing.Point(0, 0)
        $rail.Size = New-Object System.Drawing.Size(3, $Height)
        $rail.BackColor = $Accent
        [void]$field.Controls.Add($rail)

        $caption = New-Object System.Windows.Forms.Label
        $caption.Text = $Label
        $caption.Font = New-Object System.Drawing.Font('Segoe UI', 6.5, [System.Drawing.FontStyle]::Bold)
        $caption.ForeColor = $Accent
        $caption.Location = New-Object System.Drawing.Point(12, 8)
        $caption.Size = New-Object System.Drawing.Size(($Width - 22), 13)
        [void]$field.Controls.Add($caption)

        $valueLabel = New-Object System.Windows.Forms.Label
        $valueLabel.Text = if ([string]::IsNullOrWhiteSpace($Value)) { '-' } else { $Value }
        $valueLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', $ValueSize)
        $valueLabel.ForeColor = [System.Drawing.Color]::FromArgb(226, 240, 252)
        $valueLabel.Location = New-Object System.Drawing.Point(12, 25)
        $valueLabel.Size = New-Object System.Drawing.Size(($Width - 24), ($Height - 31))
        $valueLabel.AutoEllipsis = $true
        [void]$field.Controls.Add($valueLabel)
    }

    Add-ConfirmField 'PRODUTO' $Produto 20 92 560 70 ([System.Drawing.Color]::FromArgb(24, 185, 255)) 9.2
    Add-ConfirmField 'SERIAL' $Serial 20 174 270 62 ([System.Drawing.Color]::FromArgb(132, 148, 255)) 10
    Add-ConfirmField 'REFERENCIA' $Referencia 302 174 278 62 ([System.Drawing.Color]::FromArgb(255, 208, 96)) 9
    Add-ConfirmField 'QUANTIDADE' $Quantidade 20 248 170 58 ([System.Drawing.Color]::FromArgb(24, 185, 255)) 9
    Add-ConfirmField 'LOCALIZACAO' $Localizacao 202 248 378 58 ([System.Drawing.Color]::FromArgb(66, 232, 176)) 9
    Add-ConfirmField 'SERVICOS' $Servicos 20 318 560 62 ([System.Drawing.Color]::FromArgb(255, 156, 98)) 8.5

    $footerConfirm = New-Object System.Windows.Forms.Panel
    $footerConfirm.Location = New-Object System.Drawing.Point(0, 396)
    $footerConfirm.Size = New-Object System.Drawing.Size(600, 74)
    $footerConfirm.BackColor = [System.Drawing.Color]::FromArgb(8, 17, 28)
    [void]$formConfirm.Controls.Add($footerConfirm)
    $footerConfirm.Add_Paint({
        param($s, $e)
        $line = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(22, 55, 78), 1)
        $e.Graphics.DrawLine($line, 20, 0, ($s.Width - 20), 0)
        $line.Dispose()
    })

    $footerStatus = New-Object System.Windows.Forms.Label
    $footerStatus.Text = 'PRONTO PARA CADASTRAR'
    $footerStatus.Font = New-Object System.Drawing.Font('Segoe UI', 6.5, [System.Drawing.FontStyle]::Bold)
    $footerStatus.ForeColor = [System.Drawing.Color]::FromArgb(66, 232, 176)
    $footerStatus.Location = New-Object System.Drawing.Point(22, 27)
    $footerStatus.Size = New-Object System.Drawing.Size(190, 15)
    [void]$footerConfirm.Controls.Add($footerStatus)

    $btnBackConfirm = New-Object System.Windows.Forms.Button
    $btnBackConfirm.Text = 'Voltar'
    $btnBackConfirm.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
    $btnBackConfirm.ForeColor = [System.Drawing.Color]::FromArgb(155, 187, 212)
    $btnBackConfirm.BackColor = [System.Drawing.Color]::FromArgb(14, 28, 43)
    $btnBackConfirm.FlatStyle = 'Flat'
    $btnBackConfirm.FlatAppearance.BorderSize = 1
    $btnBackConfirm.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(36, 70, 104)
    $btnBackConfirm.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(22, 43, 62)
    $btnBackConfirm.Location = New-Object System.Drawing.Point(352, 18)
    $btnBackConfirm.Size = New-Object System.Drawing.Size(96, 38)
    $btnBackConfirm.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnBackConfirm.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    [void]$footerConfirm.Controls.Add($btnBackConfirm)
    Set-RoundedControl -Control $btnBackConfirm -Radius 7

    $btnCreateConfirm = New-Object System.Windows.Forms.Button
    $btnCreateConfirm.Text = 'Criar OS'
    $btnCreateConfirm.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9, [System.Drawing.FontStyle]::Bold)
    $btnCreateConfirm.ForeColor = [System.Drawing.Color]::White
    $btnCreateConfirm.BackColor = [System.Drawing.Color]::FromArgb(0, 110, 78)
    $btnCreateConfirm.FlatStyle = 'Flat'
    $btnCreateConfirm.FlatAppearance.BorderSize = 1
    $btnCreateConfirm.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(66, 232, 176)
    $btnCreateConfirm.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(0, 145, 96)
    $btnCreateConfirm.Location = New-Object System.Drawing.Point(458, 18)
    $btnCreateConfirm.Size = New-Object System.Drawing.Size(120, 38)
    $btnCreateConfirm.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnCreateConfirm.DialogResult = [System.Windows.Forms.DialogResult]::OK
    [void]$footerConfirm.Controls.Add($btnCreateConfirm)
    Set-RoundedControl -Control $btnCreateConfirm -Radius 7

    $formConfirm.AcceptButton = $btnCreateConfirm
    $formConfirm.CancelButton = $btnBackConfirm
    $resultConfirm = if ($Owner) { $formConfirm.ShowDialog($Owner) } else { $formConfirm.ShowDialog() }
    $formConfirm.Dispose()
    return ($resultConfirm -eq [System.Windows.Forms.DialogResult]::OK)
}

function Show-CadastroOsResult {
    param(
        [System.Windows.Forms.Form]$Owner,
        [string]$OsCodigo,
        [string]$ProdutoErro,
        [string]$ServicosErro
    )

    $avisos = @()
    if (-not [string]::IsNullOrWhiteSpace($ProdutoErro)) {
        $avisos += "Produto nao adicionado automaticamente: $ProdutoErro"
    }
    if (-not [string]::IsNullOrWhiteSpace($ServicosErro)) {
        $avisos += "Servicos nao adicionados automaticamente: $ServicosErro"
    }
    $temAviso = ($avisos.Count -gt 0)
    $altura = if ($temAviso) { 350 } else { 292 }

    $formResult = New-Object System.Windows.Forms.Form
    $formResult.Text = 'OS cadastrada'
    $formResult.ClientSize = New-Object System.Drawing.Size(520, $altura)
    $formResult.StartPosition = 'CenterParent'
    $formResult.BackColor = [System.Drawing.Color]::FromArgb(6, 13, 22)
    $formResult.ForeColor = [System.Drawing.Color]::FromArgb(236, 245, 255)
    $formResult.FormBorderStyle = 'None'
    $formResult.ShowInTaskbar = $false
    $formResult.KeyPreview = $true
    Set-DoubleBuffered $formResult
    Set-RoundedControl -Control $formResult -Radius 12
    $formResult.Add_SizeChanged({ Set-RoundedControl -Control $this -Radius 12 })
    $formResult.Add_Paint({
        param($s, $e)
        $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $border = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(34, 114, 94), 1)
        $e.Graphics.DrawRectangle($border, 0, 0, ($s.ClientSize.Width - 1), ($s.ClientSize.Height - 1))
        $border.Dispose()
    })

    $header = New-Object System.Windows.Forms.Panel
    $header.Location = New-Object System.Drawing.Point(0, 0)
    $header.Size = New-Object System.Drawing.Size(520, 82)
    $header.BackColor = [System.Drawing.Color]::FromArgb(8, 22, 32)
    [void]$formResult.Controls.Add($header)
    $header.Add_Paint({
        param($s, $e)
        $line = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(66, 232, 176), 2)
        $e.Graphics.DrawLine($line, 0, ($s.Height - 2), $s.Width, ($s.Height - 2))
        $line.Dispose()
    })

    $rail = New-Object System.Windows.Forms.Panel
    $rail.Location = New-Object System.Drawing.Point(0, 0)
    $rail.Size = New-Object System.Drawing.Size(4, 82)
    $rail.BackColor = [System.Drawing.Color]::FromArgb(66, 232, 176)
    [void]$header.Controls.Add($rail)

    $eyebrow = New-Object System.Windows.Forms.Label
    $eyebrow.Text = 'ALTERTAG / CADASTRO'
    $eyebrow.Font = New-Object System.Drawing.Font('Segoe UI', 7, [System.Drawing.FontStyle]::Bold)
    $eyebrow.ForeColor = [System.Drawing.Color]::FromArgb(66, 232, 176)
    $eyebrow.Location = New-Object System.Drawing.Point(24, 13)
    $eyebrow.Size = New-Object System.Drawing.Size(250, 15)
    [void]$header.Controls.Add($eyebrow)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'OS cadastrada'
    $title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 16, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = [System.Drawing.Color]::FromArgb(236, 245, 255)
    $title.Location = New-Object System.Drawing.Point(21, 34)
    $title.Size = New-Object System.Drawing.Size(330, 31)
    [void]$header.Controls.Add($title)

    $close = New-Object System.Windows.Forms.Button
    $close.Text = 'X'
    $close.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
    $close.ForeColor = [System.Drawing.Color]::FromArgb(112, 150, 180)
    $close.BackColor = [System.Drawing.Color]::FromArgb(8, 22, 32)
    $close.FlatStyle = 'Flat'
    $close.FlatAppearance.BorderSize = 0
    $close.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(24, 55, 52)
    $close.Location = New-Object System.Drawing.Point(486, 8)
    $close.Size = New-Object System.Drawing.Size(26, 26)
    $close.Cursor = [System.Windows.Forms.Cursors]::Hand
    $close.DialogResult = [System.Windows.Forms.DialogResult]::OK
    [void]$header.Controls.Add($close)

    $statusPanel = New-Object System.Windows.Forms.Panel
    $statusPanel.Location = New-Object System.Drawing.Point(20, 102)
    $statusPanel.Size = New-Object System.Drawing.Size(480, 88)
    $statusPanel.BackColor = [System.Drawing.Color]::FromArgb(5, 42, 38)
    [void]$formResult.Controls.Add($statusPanel)
    Set-RoundedControl -Control $statusPanel -Radius 8

    $statusCaption = New-Object System.Windows.Forms.Label
    $statusCaption.Text = 'CADASTRO CONCLUIDO'
    $statusCaption.Font = New-Object System.Drawing.Font('Segoe UI', 7, [System.Drawing.FontStyle]::Bold)
    $statusCaption.ForeColor = [System.Drawing.Color]::FromArgb(66, 232, 176)
    $statusCaption.Location = New-Object System.Drawing.Point(18, 13)
    $statusCaption.Size = New-Object System.Drawing.Size(220, 16)
    [void]$statusPanel.Controls.Add($statusCaption)

    $osValue = New-Object System.Windows.Forms.Label
    $osValue.Text = $OsCodigo
    $osValue.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 21, [System.Drawing.FontStyle]::Bold)
    $osValue.ForeColor = [System.Drawing.Color]::FromArgb(191, 255, 226)
    $osValue.Location = New-Object System.Drawing.Point(15, 34)
    $osValue.Size = New-Object System.Drawing.Size(270, 40)
    [void]$statusPanel.Controls.Add($osValue)

    $statusText = New-Object System.Windows.Forms.Label
    $statusText.Text = if ($temAviso) { 'Criada com pendencias' } else { 'Criada com sucesso' }
    $statusText.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
    $statusText.ForeColor = if ($temAviso) {
        [System.Drawing.Color]::FromArgb(255, 208, 96)
    } else {
        [System.Drawing.Color]::FromArgb(144, 218, 190)
    }
    $statusText.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
    $statusText.Location = New-Object System.Drawing.Point(290, 38)
    $statusText.Size = New-Object System.Drawing.Size(168, 30)
    [void]$statusPanel.Controls.Add($statusText)

    if ($temAviso) {
        $warningPanel = New-Object System.Windows.Forms.Panel
        $warningPanel.Location = New-Object System.Drawing.Point(20, 204)
        $warningPanel.Size = New-Object System.Drawing.Size(480, 64)
        $warningPanel.BackColor = [System.Drawing.Color]::FromArgb(42, 34, 14)
        [void]$formResult.Controls.Add($warningPanel)
        Set-RoundedControl -Control $warningPanel -Radius 7

        $warningLabel = New-Object System.Windows.Forms.Label
        $warningLabel.Text = $avisos -join "`n"
        $warningLabel.Font = New-Object System.Drawing.Font('Segoe UI', 8)
        $warningLabel.ForeColor = [System.Drawing.Color]::FromArgb(255, 220, 132)
        $warningLabel.Location = New-Object System.Drawing.Point(14, 10)
        $warningLabel.Size = New-Object System.Drawing.Size(450, 44)
        $warningLabel.AutoEllipsis = $true
        [void]$warningPanel.Controls.Add($warningLabel)
    }

    $footerY = if ($temAviso) { 286 } else { 208 }
    $footer = New-Object System.Windows.Forms.Panel
    $footer.Location = New-Object System.Drawing.Point(0, $footerY)
    $footer.Size = New-Object System.Drawing.Size(520, ($altura - $footerY))
    $footer.BackColor = [System.Drawing.Color]::FromArgb(8, 17, 28)
    [void]$formResult.Controls.Add($footer)

    $btnDone = New-Object System.Windows.Forms.Button
    $btnDone.Text = 'Concluir'
    $btnDone.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9, [System.Drawing.FontStyle]::Bold)
    $btnDone.ForeColor = [System.Drawing.Color]::White
    $btnDone.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 82)
    $btnDone.FlatStyle = 'Flat'
    $btnDone.FlatAppearance.BorderSize = 1
    $btnDone.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(66, 232, 176)
    $btnDone.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(0, 150, 100)
    $btnDone.Location = New-Object System.Drawing.Point(364, 18)
    $btnDone.Size = New-Object System.Drawing.Size(136, 40)
    $btnDone.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnDone.DialogResult = [System.Windows.Forms.DialogResult]::OK
    [void]$footer.Controls.Add($btnDone)
    Set-RoundedControl -Control $btnDone -Radius 7

    $formResult.AcceptButton = $btnDone
    $formResult.CancelButton = $close
    if ($Owner) { [void]$formResult.ShowDialog($Owner) } else { [void]$formResult.ShowDialog() }
    $formResult.Dispose()
}


function Show-CadastroOsAltertagDraft {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Cadastrar OS Altertag'
    $dlg.Size = New-Object System.Drawing.Size(860, 665)
    $dlg.StartPosition = 'CenterParent'
    $dlg.BackColor = [System.Drawing.Color]::FromArgb(7, 13, 22)
    $dlg.ForeColor = $cMain
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false

    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'Preparar cadastro da OS'
    $title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 13, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = $cGreen
    $title.Location = New-Object System.Drawing.Point(18, 14)
    $title.Size = New-Object System.Drawing.Size(420, 26)
    $dlg.Controls.Add($title)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = 'Busca o produto no Altertag. O cadastro real sera ativado depois de validarmos o envio final da OS.'
    $hint.Font = New-Object System.Drawing.Font('Segoe UI', 8)
    $hint.ForeColor = $cMuted
    $hint.Location = New-Object System.Drawing.Point(20, 42)
    $hint.Size = New-Object System.Drawing.Size(800, 18)
    $dlg.Controls.Add($hint)

    $infoOsPanel = New-Object System.Windows.Forms.Panel
    $infoOsPanel.BackColor = [System.Drawing.Color]::FromArgb(9, 18, 29)
    $infoOsPanel.BorderStyle = 'FixedSingle'
    $infoOsPanel.Location = New-Object System.Drawing.Point(620, 78)
    $infoOsPanel.Size = New-Object System.Drawing.Size(200, 228)
    $dlg.Controls.Add($infoOsPanel)

    # Accent top bar
    $infoOsAccent = New-Object System.Windows.Forms.Panel
    $infoOsAccent.BackColor = $cAccent
    $infoOsAccent.Location = New-Object System.Drawing.Point(0, 0)
    $infoOsAccent.Size = New-Object System.Drawing.Size(200, 3)
    [void]$infoOsPanel.Controls.Add($infoOsAccent)

    # --- Card Tecnico (botoes toggle) ---
    $cardTec = New-Object System.Windows.Forms.Panel
    $cardTec.BackColor = [System.Drawing.Color]::FromArgb(12, 22, 35)
    $cardTec.Location = New-Object System.Drawing.Point(10, 8)
    $cardTec.Size = New-Object System.Drawing.Size(178, 62)
    [void]$infoOsPanel.Controls.Add($cardTec)
    $cardTecBar = New-Object System.Windows.Forms.Panel
    $cardTecBar.BackColor = $cAccent
    $cardTecBar.Location = New-Object System.Drawing.Point(0, 0)
    $cardTecBar.Size = New-Object System.Drawing.Size(3, 62)
    [void]$cardTec.Controls.Add($cardTecBar)
    $lblTecCaption = New-Object System.Windows.Forms.Label
    $lblTecCaption.Text = 'TECNICO'
    $lblTecCaption.Font = New-Object System.Drawing.Font('Segoe UI', 6.5, [System.Drawing.FontStyle]::Bold)
    $lblTecCaption.ForeColor = [System.Drawing.Color]::FromArgb(80, 160, 210)
    $lblTecCaption.Location = New-Object System.Drawing.Point(8, 6)
    $lblTecCaption.Size = New-Object System.Drawing.Size(162, 12)
    [void]$cardTec.Controls.Add($lblTecCaption)

    # Wrapper compativel com .SelectedItem usado no resto do codigo
    $cmbTec = [PSCustomObject]@{ SelectedItem = 'Lucas' }
    $script:tecnicoSelecionado = 'Lucas'
    $script:tecBtns = @{}
    $tecNomes = @('Lucas', 'Hyrides', 'Vitor', 'Erick')
    $tecX = 6
    foreach ($tec in $tecNomes) {
        $btn = New-Object System.Windows.Forms.Button
        $btn.Text      = $tec
        $btn.Font      = New-Object System.Drawing.Font('Segoe UI Semibold', 6.5)
        $btn.FlatStyle = 'Flat'
        $btn.FlatAppearance.BorderSize = 1
        $btn.Location  = New-Object System.Drawing.Point($tecX, 20)
        $btn.Size      = New-Object System.Drawing.Size(40, 34)
        $btn.Cursor    = [System.Windows.Forms.Cursors]::Hand
        $script:tecBtns[$tec] = $btn
        [void]$cardTec.Controls.Add($btn)
        $tecX += 42

        $btn.Add_Click({
            $nomeTec = $this.Text
            $script:tecnicoSelecionado = $nomeTec
            $cmbTec.SelectedItem = $nomeTec
            foreach ($t in $tecNomes) {
                $b = $script:tecBtns[$t]
                if ($t -eq $nomeTec) {
                    $b.BackColor = [System.Drawing.Color]::FromArgb(0, 88, 148)
                    $b.ForeColor = [System.Drawing.Color]::White
                    $b.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(0, 166, 255)
                } else {
                    $b.BackColor = [System.Drawing.Color]::FromArgb(10, 20, 33)
                    $b.ForeColor = [System.Drawing.Color]::FromArgb(100, 148, 185)
                    $b.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(22, 44, 66)
                }
            }
            Update-ResumoOs -Produto $listProd.SelectedItem
        })
    }
    # Estado inicial
    $script:tecBtns['Lucas'].BackColor = [System.Drawing.Color]::FromArgb(0, 88, 148)
    $script:tecBtns['Lucas'].ForeColor = [System.Drawing.Color]::White
    $script:tecBtns['Lucas'].FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(0, 166, 255)
    foreach ($t in @('Hyrides', 'Vitor', 'Erick')) {
        $script:tecBtns[$t].BackColor = [System.Drawing.Color]::FromArgb(10, 20, 33)
        $script:tecBtns[$t].ForeColor = [System.Drawing.Color]::FromArgb(100, 148, 185)
        $script:tecBtns[$t].FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(22, 44, 66)
    }

    # --- Card Serial ---
    $cardSerial = New-Object System.Windows.Forms.Panel
    $cardSerial.BackColor = [System.Drawing.Color]::FromArgb(12, 22, 35)
    $cardSerial.Location = New-Object System.Drawing.Point(10, 76)
    $cardSerial.Size = New-Object System.Drawing.Size(178, 42)
    [void]$infoOsPanel.Controls.Add($cardSerial)
    $cardSerialBar = New-Object System.Windows.Forms.Panel
    $cardSerialBar.BackColor = $cPurple
    $cardSerialBar.Location = New-Object System.Drawing.Point(0, 0)
    $cardSerialBar.Size = New-Object System.Drawing.Size(3, 42)
    [void]$cardSerial.Controls.Add($cardSerialBar)
    $lblSerialCaption = New-Object System.Windows.Forms.Label
    $lblSerialCaption.Text = 'SERIAL'
    $lblSerialCaption.Font = New-Object System.Drawing.Font('Segoe UI', 6.5, [System.Drawing.FontStyle]::Bold)
    $lblSerialCaption.ForeColor = [System.Drawing.Color]::FromArgb(120, 120, 210)
    $lblSerialCaption.Location = New-Object System.Drawing.Point(8, 5)
    $lblSerialCaption.Size = New-Object System.Drawing.Size(162, 12)
    [void]$cardSerial.Controls.Add($lblSerialCaption)
    $txtSerialOs = New-Object System.Windows.Forms.TextBox
    $txtSerialOs.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
    $txtSerialOs.BackColor = [System.Drawing.Color]::FromArgb(12, 22, 35)
    $txtSerialOs.ForeColor = [System.Drawing.Color]::White
    $txtSerialOs.BorderStyle = 'None'
    $txtSerialOs.Location = New-Object System.Drawing.Point(8, 22)
    $txtSerialOs.Size = New-Object System.Drawing.Size(162, 18)
    $txtSerialOs.Text = $info.Serial
    [void]$cardSerial.Controls.Add($txtSerialOs)

    # --- Card Referencia ---
    $cardGrade = New-Object System.Windows.Forms.Panel
    $cardGrade.BackColor = [System.Drawing.Color]::FromArgb(12, 22, 35)
    $cardGrade.Location = New-Object System.Drawing.Point(10, 124)
    $cardGrade.Size = New-Object System.Drawing.Size(178, 42)
    [void]$infoOsPanel.Controls.Add($cardGrade)
    $cardGradeBar = New-Object System.Windows.Forms.Panel
    $cardGradeBar.BackColor = $cYellow
    $cardGradeBar.Location = New-Object System.Drawing.Point(0, 0)
    $cardGradeBar.Size = New-Object System.Drawing.Size(3, 42)
    [void]$cardGrade.Controls.Add($cardGradeBar)
    $lblGradeCaption = New-Object System.Windows.Forms.Label
    $lblGradeCaption.Text = 'REFERENCIA'
    $lblGradeCaption.Font = New-Object System.Drawing.Font('Segoe UI', 6.5, [System.Drawing.FontStyle]::Bold)
    $lblGradeCaption.ForeColor = [System.Drawing.Color]::FromArgb(180, 148, 60)
    $lblGradeCaption.Location = New-Object System.Drawing.Point(8, 5)
    $lblGradeCaption.Size = New-Object System.Drawing.Size(162, 12)
    [void]$cardGrade.Controls.Add($lblGradeCaption)
    $script:gradeCadastroOs = if ($script:rnaAtivo) { 'RMA' } elseif ($script:gradeAtual) { [string]$script:gradeAtual } else { 'A' }
    $btnGradeOs = New-Object System.Windows.Forms.Button
    $btnGradeOs.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 7.5)
    $btnGradeOs.BackColor = [System.Drawing.Color]::FromArgb(12, 22, 35)
    $btnGradeOs.ForeColor = [System.Drawing.Color]::White
    $btnGradeOs.FlatStyle = 'Flat'
    $btnGradeOs.FlatAppearance.BorderSize = 0
    $btnGradeOs.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $btnGradeOs.Location = New-Object System.Drawing.Point(5, 18)
    $btnGradeOs.Size = New-Object System.Drawing.Size(168, 23)
    $btnGradeOs.Text = (Format-CaijGradeReference $script:gradeCadastroOs)
    $btnGradeOs.Cursor = [System.Windows.Forms.Cursors]::Hand
    [void]$cardGrade.Controls.Add($btnGradeOs)

    $gradeMenuOs = New-Object System.Windows.Forms.ContextMenuStrip
    $gradeMenuOs.AutoSize = $true
    $gradeMenuOs.BackColor = [System.Drawing.Color]::FromArgb(10, 20, 33)
    $gradeMenuOs.ForeColor = [System.Drawing.Color]::FromArgb(236, 245, 255)
    $gradeMenuOs.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5)
    $gradeMenuOs.ShowImageMargin = $false
    $gradeMenuOs.ShowCheckMargin = $false
    $gradeMenuOs.DropShadowEnabled = $true
    $gradeMenuOs.Padding = New-Object System.Windows.Forms.Padding(1, 4, 1, 4)
    $gradeMenuOs.MinimumSize = New-Object System.Drawing.Size(178, 0)
    $gradeMenuOs.Renderer = New-Object CaijGradeMenuRenderer
    foreach ($gradeOpcao in @(Get-CaijGradeOptions)) {
        $gradeItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $gradeItem.Text = (Format-CaijGradeReference $gradeOpcao)
        $gradeItem.Tag = $gradeOpcao
        $gradeItem.AutoSize = $false
        $gradeItem.Size = New-Object System.Drawing.Size(176, 30)
        $gradeItem.Padding = New-Object System.Windows.Forms.Padding(18, 0, 6, 0)
        $gradeItem.Margin = [System.Windows.Forms.Padding]::Empty
        $gradeItem.CheckOnClick = $false
        $gradeItem.Add_Click({
            $script:gradeCadastroOs = [string]$this.Tag
            $script:gradeAtual = [string]$this.Tag
            $btnGradeOs.Text = (Format-CaijGradeReference $script:gradeCadastroOs)
            Update-ResumoOs -Produto $listProd.SelectedItem
        })
        [void]$gradeMenuOs.Items.Add($gradeItem)
    }
    $gradeMenuOs.Add_Opening({
        foreach ($item in @($gradeMenuOs.Items)) {
            $item.Checked = ([string]$item.Tag -eq [string]$script:gradeCadastroOs)
        }
    })
    $btnGradeOs.Add_Click({
        $gradeMenuOs.Show($btnGradeOs, (New-Object System.Drawing.Point(0, $btnGradeOs.Height)))
    })

    # --- Card OS atual ---
    $cardOs = New-Object System.Windows.Forms.Panel
    $cardOs.BackColor = [System.Drawing.Color]::FromArgb(8, 28, 20)
    $cardOs.Location = New-Object System.Drawing.Point(10, 172)
    $cardOs.Size = New-Object System.Drawing.Size(178, 48)
    [void]$infoOsPanel.Controls.Add($cardOs)
    $cardOsBar = New-Object System.Windows.Forms.Panel
    $cardOsBar.BackColor = $cGreen
    $cardOsBar.Location = New-Object System.Drawing.Point(0, 0)
    $cardOsBar.Size = New-Object System.Drawing.Size(3, 48)
    [void]$cardOs.Controls.Add($cardOsBar)
    $lblOsCaption = New-Object System.Windows.Forms.Label
    $lblOsCaption.Text = 'OS ATUAL'
    $lblOsCaption.Font = New-Object System.Drawing.Font('Segoe UI', 6.5, [System.Drawing.FontStyle]::Bold)
    $lblOsCaption.ForeColor = [System.Drawing.Color]::FromArgb(60, 160, 110)
    $lblOsCaption.Location = New-Object System.Drawing.Point(8, 5)
    $lblOsCaption.Size = New-Object System.Drawing.Size(162, 12)
    [void]$cardOs.Controls.Add($lblOsCaption)
    $lblOsTopoValor = New-Object System.Windows.Forms.Label
    $lblOsTopoValor.Text = (Format-OsCodigo -Numero $script:osNumero)
    $lblOsTopoValor.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 11, [System.Drawing.FontStyle]::Bold)
    $lblOsTopoValor.ForeColor = $cGreen
    $lblOsTopoValor.BackColor = [System.Drawing.Color]::Transparent
    $lblOsTopoValor.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $lblOsTopoValor.Location = New-Object System.Drawing.Point(8, 20)
    $lblOsTopoValor.Size = New-Object System.Drawing.Size(162, 22)
    [void]$cardOs.Controls.Add($lblOsTopoValor)

    # --- Header da secao de busca ---
    $buscaHeader = New-Object System.Windows.Forms.Panel
    $buscaHeader.BackColor = [System.Drawing.Color]::FromArgb(7, 14, 24)
    $buscaHeader.Location  = New-Object System.Drawing.Point(20, 72)
    $buscaHeader.Size      = New-Object System.Drawing.Size(580, 32)
    [void]$dlg.Controls.Add($buscaHeader)

    $buscaHeaderAccent = New-Object System.Windows.Forms.Panel
    $buscaHeaderAccent.BackColor = $cAccent
    $buscaHeaderAccent.Location  = New-Object System.Drawing.Point(0, 0)
    $buscaHeaderAccent.Size      = New-Object System.Drawing.Size(3, 32)
    [void]$buscaHeader.Controls.Add($buscaHeaderAccent)

    $lblBusca = New-Object System.Windows.Forms.Label
    $lblBusca.Text      = 'PRODUTO'
    $lblBusca.Font      = New-Object System.Drawing.Font('Segoe UI', 7, [System.Drawing.FontStyle]::Bold)
    $lblBusca.ForeColor = $cAccent
    $lblBusca.Location  = New-Object System.Drawing.Point(12, 10)
    $lblBusca.Size      = New-Object System.Drawing.Size(80, 14)
    [void]$buscaHeader.Controls.Add($lblBusca)

    $lblBuscaHint = New-Object System.Windows.Forms.Label
    $lblBuscaHint.Text      = 'Pesquise por modelo, processador ou codigo'
    $lblBuscaHint.Font      = New-Object System.Drawing.Font('Segoe UI', 7)
    $lblBuscaHint.ForeColor = [System.Drawing.Color]::FromArgb(80, 120, 155)
    $lblBuscaHint.Location  = New-Object System.Drawing.Point(92, 10)
    $lblBuscaHint.Size      = New-Object System.Drawing.Size(480, 14)
    [void]$buscaHeader.Controls.Add($lblBuscaHint)

    # --- Painel de busca (campo + botao) ---
    $buscaPanel = New-Object System.Windows.Forms.Panel
    $buscaPanel.BackColor   = [System.Drawing.Color]::FromArgb(10, 20, 33)
    $buscaPanel.BorderStyle = 'FixedSingle'
    $buscaPanel.Location    = New-Object System.Drawing.Point(20, 104)
    $buscaPanel.Size        = New-Object System.Drawing.Size(580, 46)
    [void]$dlg.Controls.Add($buscaPanel)

    # Icone lupa
    $lblLupa = New-Object System.Windows.Forms.Label
    $lblLupa.Text      = [char]::ConvertFromUtf32(0x1F50D)
    $lblLupa.Font      = New-Object System.Drawing.Font('Segoe UI Symbol', 11)
    $lblLupa.ForeColor = [System.Drawing.Color]::FromArgb(60, 130, 180)
    $lblLupa.Location  = New-Object System.Drawing.Point(10, 10)
    $lblLupa.Size      = New-Object System.Drawing.Size(28, 26)
    [void]$buscaPanel.Controls.Add($lblLupa)

    $txtBuscaProd = New-Object System.Windows.Forms.TextBox
    $txtBuscaProd.Font        = New-Object System.Drawing.Font('Segoe UI', 10)
    $txtBuscaProd.BackColor   = [System.Drawing.Color]::FromArgb(10, 20, 33)
    $txtBuscaProd.ForeColor   = [System.Drawing.Color]::FromArgb(220, 238, 255)
    $txtBuscaProd.BorderStyle = 'None'
    $txtBuscaProd.Location    = New-Object System.Drawing.Point(42, 13)
    $txtBuscaProd.Size        = New-Object System.Drawing.Size(390, 22)
    $txtBuscaProd.Text        = ''
    $txtBuscaProd.Add_KeyDown({
        param($sender, $e)
        if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
            $e.SuppressKeyPress = $true
            $btnBuscaProd.PerformClick()
        }
    })
    [void]$buscaPanel.Controls.Add($txtBuscaProd)

    # Divisor vertical antes do botao
    $buscaDivider = New-Object System.Windows.Forms.Panel
    $buscaDivider.BackColor = [System.Drawing.Color]::FromArgb(28, 52, 78)
    $buscaDivider.Location  = New-Object System.Drawing.Point(442, 8)
    $buscaDivider.Size      = New-Object System.Drawing.Size(1, 30)
    [void]$buscaPanel.Controls.Add($buscaDivider)

    $btnBuscaProd = New-Object System.Windows.Forms.Button
    $btnBuscaProd.Text      = 'Buscar'
    $btnBuscaProd.Font      = New-Object System.Drawing.Font('Segoe UI Semibold', 9, [System.Drawing.FontStyle]::Bold)
    $btnBuscaProd.ForeColor = [System.Drawing.Color]::FromArgb(220, 244, 255)
    $btnBuscaProd.BackColor = [System.Drawing.Color]::FromArgb(0, 100, 148)
    $btnBuscaProd.FlatStyle = 'Flat'
    $btnBuscaProd.FlatAppearance.BorderSize            = 0
    $btnBuscaProd.FlatAppearance.MouseOverBackColor    = [System.Drawing.Color]::FromArgb(0, 130, 185)
    $btnBuscaProd.FlatAppearance.MouseDownBackColor    = [System.Drawing.Color]::FromArgb(0, 80, 120)
    $btnBuscaProd.Location  = New-Object System.Drawing.Point(443, 1)
    $btnBuscaProd.Size      = New-Object System.Drawing.Size(134, 42)
    [void]$buscaPanel.Controls.Add($btnBuscaProd)

    # --- Painel de resultados ---
    $prodPanel = New-Object System.Windows.Forms.Panel
    $prodPanel.BackColor   = [System.Drawing.Color]::FromArgb(7, 14, 24)
    $prodPanel.BorderStyle = 'FixedSingle'
    $prodPanel.Location    = New-Object System.Drawing.Point(20, 152)
    $prodPanel.Size        = New-Object System.Drawing.Size(580, 136)
    [void]$dlg.Controls.Add($prodPanel)

    # Header da lista com gradiente simulado
    $prodHead = New-Object System.Windows.Forms.Panel
    $prodHead.BackColor = [System.Drawing.Color]::FromArgb(9, 26, 44)
    $prodHead.Location  = New-Object System.Drawing.Point(0, 0)
    $prodHead.Size      = New-Object System.Drawing.Size(578, 26)
    [void]$prodPanel.Controls.Add($prodHead)

    $prodHeadAccent = New-Object System.Windows.Forms.Panel
    $prodHeadAccent.BackColor = $cAccent
    $prodHeadAccent.Location  = New-Object System.Drawing.Point(0, 0)
    $prodHeadAccent.Size      = New-Object System.Drawing.Size(578, 2)
    [void]$prodHead.Controls.Add($prodHeadAccent)

    foreach ($col in @(
        @{ Texto='CODIGO'; X=10; W=88 },
        @{ Texto='PRODUTO'; X=108; W=345 },
        @{ Texto='ESTOQUE'; X=484; W=70 }
    )) {
        $h = New-Object System.Windows.Forms.Label
        $h.Text      = [string]$col.Texto
        $h.Font      = New-Object System.Drawing.Font('Segoe UI', 6.5, [System.Drawing.FontStyle]::Bold)
        $h.ForeColor = [System.Drawing.Color]::FromArgb(80, 150, 200)
        $h.Location  = New-Object System.Drawing.Point([int]$col.X, 7)
        $h.Size      = New-Object System.Drawing.Size([int]$col.W, 13)
        [void]$prodHead.Controls.Add($h)
    }

    # Divisores verticais no header
    foreach ($xDiv in @(100, 460)) {
        $dv = New-Object System.Windows.Forms.Panel
        $dv.BackColor = [System.Drawing.Color]::FromArgb(22, 48, 70)
        $dv.Location  = New-Object System.Drawing.Point($xDiv, 5)
        $dv.Size      = New-Object System.Drawing.Size(1, 16)
        [void]$prodHead.Controls.Add($dv)
    }

    $listProd = New-Object System.Windows.Forms.ListBox
    $listProd.DisplayMember = 'texto'
    $listProd.DrawMode      = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
    $listProd.ItemHeight    = 28
    $listProd.Font          = New-Object System.Drawing.Font('Segoe UI', 8.5)
    $listProd.BackColor     = [System.Drawing.Color]::FromArgb(7, 14, 24)
    $listProd.ForeColor     = [System.Drawing.Color]::White
    $listProd.BorderStyle   = 'None'
    $listProd.Location      = New-Object System.Drawing.Point(1, 27)
    # Largura extra: empurra o scrollbar nativo para fora do painel (que corta o excesso)
    $listProd.Size          = New-Object System.Drawing.Size((576 + [System.Windows.Forms.SystemInformation]::VerticalScrollBarWidth + 2), 107)
    [void]$prodPanel.Controls.Add($listProd)

    # --- Scrollbar customizado (trilho fino + polegar arredondado) ---
    $scrollProd = New-Object System.Windows.Forms.Panel
    $scrollProd.BackColor = [System.Drawing.Color]::FromArgb(7, 14, 24)
    $scrollProd.Location  = New-Object System.Drawing.Point(568, 29)
    $scrollProd.Size      = New-Object System.Drawing.Size(8, 103)
    [void]$prodPanel.Controls.Add($scrollProd)
    $scrollProd.BringToFront()

    $script:scrollProdDrag = $false
    $script:scrollProdTopIndex = -1

    function Get-ScrollProdMetrics {
        $total = $listProd.Items.Count
        $vis = [Math]::Max(1, [int][Math]::Floor($listProd.ClientSize.Height / $listProd.ItemHeight))
        if ($total -le $vis) { return $null }
        $trackH = $scrollProd.Height
        $thumbH = [Math]::Max(24, [int]($trackH * $vis / $total))
        $maxTop = $total - $vis
        return @{ Total = $total; Vis = $vis; TrackH = $trackH; ThumbH = $thumbH; MaxTop = $maxTop }
    }

    $scrollProd.Add_Paint({
        param($s, $e)
        $m = Get-ScrollProdMetrics
        $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        # Trilho
        $trackBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(14, 28, 44))
        $trackPath = New-Object System.Drawing.Drawing2D.GraphicsPath
        $trackPath.AddArc(2, 0, 4, 4, 180, 180)
        $trackPath.AddArc(2, ($s.Height - 5), 4, 4, 0, 180)
        $trackPath.CloseFigure()
        $e.Graphics.FillPath($trackBrush, $trackPath)
        $trackPath.Dispose(); $trackBrush.Dispose()
        if (-not $m) { return }
        # Polegar
        $topIdx = [Math]::Min($listProd.TopIndex, $m.MaxTop)
        $y = [int](($m.TrackH - $m.ThumbH) * ($topIdx / $m.MaxTop))
        $thumbColor = if ($script:scrollProdDrag) { [System.Drawing.Color]::FromArgb(0, 150, 210) } else { [System.Drawing.Color]::FromArgb(45, 95, 140) }
        $thumbBrush = New-Object System.Drawing.SolidBrush($thumbColor)
        $thumbPath = New-Object System.Drawing.Drawing2D.GraphicsPath
        $thumbPath.AddArc(0, $y, 8, 8, 180, 180)
        $thumbPath.AddArc(0, ($y + $m.ThumbH - 9), 8, 8, 0, 180)
        $thumbPath.CloseFigure()
        $e.Graphics.FillPath($thumbBrush, $thumbPath)
        $thumbPath.Dispose(); $thumbBrush.Dispose()
    })

    $setScrollProdFromY = {
        param([int]$Y)
        $m = Get-ScrollProdMetrics
        if (-not $m) { return }
        $faixa = [Math]::Max(1, $m.TrackH - $m.ThumbH)
        $ratio = [Math]::Max(0.0, [Math]::Min(1.0, (($Y - ($m.ThumbH / 2)) / $faixa)))
        $novoTop = [int][Math]::Round($ratio * $m.MaxTop)
        if ($novoTop -ne $listProd.TopIndex) { $listProd.TopIndex = $novoTop }
        $scrollProd.Invalidate()
    }

    $scrollProd.Add_MouseDown({
        param($s, $e)
        $script:scrollProdDrag = $true
        & $setScrollProdFromY $e.Y
    })
    $scrollProd.Add_MouseMove({
        param($s, $e)
        if ($script:scrollProdDrag) { & $setScrollProdFromY $e.Y }
    })
    $scrollProd.Add_MouseUp({
        $script:scrollProdDrag = $false
        $scrollProd.Invalidate()
    })

    # Timer leve: redesenha o polegar quando a lista rola (roda do mouse / teclado)
    $scrollProdTimer = New-Object System.Windows.Forms.Timer
    $scrollProdTimer.Interval = 120
    $scrollProdTimer.Add_Tick({
        if ($listProd.IsDisposed) { return }
        if ($listProd.TopIndex -ne $script:scrollProdTopIndex) {
            $script:scrollProdTopIndex = $listProd.TopIndex
            $scrollProd.Invalidate()
        }
    })
    $scrollProdTimer.Start()
    $dlg.Add_FormClosed({
        $scrollProdTimer.Stop()
        $scrollProdTimer.Dispose()
    })

    $lblListaVazia = New-Object System.Windows.Forms.Label
    $lblListaVazia.Text      = 'Digite um termo e clique Buscar'
    $lblListaVazia.Font      = New-Object System.Drawing.Font('Segoe UI', 9)
    $lblListaVazia.ForeColor = [System.Drawing.Color]::FromArgb(60, 100, 135)
    $lblListaVazia.BackColor = [System.Drawing.Color]::FromArgb(7, 14, 24)
    $lblListaVazia.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $lblListaVazia.Location  = New-Object System.Drawing.Point(1, 27)
    $lblListaVazia.Size      = New-Object System.Drawing.Size(576, 107)
    [void]$prodPanel.Controls.Add($lblListaVazia)
    $lblListaVazia.BringToFront()

    # --- Header da secao de servicos (mesmo estilo do header PRODUTO) ---
    $servHeader = New-Object System.Windows.Forms.Panel
    $servHeader.BackColor = [System.Drawing.Color]::FromArgb(7, 14, 24)
    $servHeader.Location  = New-Object System.Drawing.Point(20, 290)
    $servHeader.Size      = New-Object System.Drawing.Size(800, 22)
    [void]$dlg.Controls.Add($servHeader)

    $servHeaderAccent = New-Object System.Windows.Forms.Panel
    $servHeaderAccent.BackColor = $cAccent
    $servHeaderAccent.Location  = New-Object System.Drawing.Point(0, 0)
    $servHeaderAccent.Size      = New-Object System.Drawing.Size(3, 22)
    [void]$servHeader.Controls.Add($servHeaderAccent)

    $lblServ = New-Object System.Windows.Forms.Label
    $lblServ.Text = 'SERVICOS REALIZADOS'
    $lblServ.Font = New-Object System.Drawing.Font('Segoe UI', 7, [System.Drawing.FontStyle]::Bold)
    $lblServ.ForeColor = $cAccent
    $lblServ.Location = New-Object System.Drawing.Point(12, 5)
    $lblServ.Size = New-Object System.Drawing.Size(160, 14)
    [void]$servHeader.Controls.Add($lblServ)

    $lblServHint = New-Object System.Windows.Forms.Label
    $lblServHint.Text      = 'Marque os servicos executados neste equipamento'
    $lblServHint.Font      = New-Object System.Drawing.Font('Segoe UI', 7)
    $lblServHint.ForeColor = [System.Drawing.Color]::FromArgb(80, 120, 155)
    $lblServHint.Location  = New-Object System.Drawing.Point(172, 5)
    $lblServHint.Size      = New-Object System.Drawing.Size(400, 14)
    [void]$servHeader.Controls.Add($lblServHint)

    $servChecks = @()
    $servPanel = New-Object System.Windows.Forms.Panel
    $servPanel.BackColor = [System.Drawing.Color]::FromArgb(7, 14, 24)
    $servPanel.BorderStyle = 'None'
    $servPanel.Location = New-Object System.Drawing.Point(20, 314)
    $servPanel.Size = New-Object System.Drawing.Size(800, 126)
    [void]$dlg.Controls.Add($servPanel)

    # Grupos de servicos: cada grupo tem cor propria, coluna de checkboxes e header
    $servGrupos = @(
        @{
            Titulo = 'Pecas e manutencao'
            Cor    = [System.Drawing.Color]::FromArgb(0, 166, 255)
            X      = 6; W = 192
            Itens  = @('Troca de bateria','Troca SSD','Troca de tela','Troca de memoria RAM')
        }
        @{
            Titulo = 'Estrutura'
            Cor    = [System.Drawing.Color]::FromArgb(132, 148, 255)
            X      = 206; W = 192
            Itens  = @('Troca de moldura','Troca de teclado','Troca de touchpad','Troca de dobradica')
        }
        @{
            Titulo = 'Estrutura II'
            Cor    = [System.Drawing.Color]::FromArgb(0, 206, 190)
            X      = 406; W = 192
            Itens  = @('Troca de carcaca','Troca de tampa','Troca de base','Troca de cooler')
        }
        @{
            Titulo = 'Pintura'
            Cor    = [System.Drawing.Color]::FromArgb(255, 156, 98)
            X      = 606; W = 186
            Itens  = @('Pintura 1','Pintura 2','Pintura 3','Pintura geral')
        }
    )

    foreach ($grupo in $servGrupos) {
        # Card do grupo
        $gCard = New-Object System.Windows.Forms.Panel
        $gCard.BackColor = [System.Drawing.Color]::FromArgb(11, 20, 32)
        $gCard.Location  = New-Object System.Drawing.Point([int]$grupo.X, 4)
        $gCard.Size      = New-Object System.Drawing.Size([int]$grupo.W, 116)
        [void]$servPanel.Controls.Add($gCard)

        # Accent bar topo
        $gBar = New-Object System.Windows.Forms.Panel
        $gBar.BackColor = [System.Drawing.Color]$grupo.Cor
        $gBar.Location  = New-Object System.Drawing.Point(0, 0)
        $gBar.Size      = New-Object System.Drawing.Size([int]$grupo.W, 3)
        [void]$gCard.Controls.Add($gBar)

        # Titulo do grupo
        $gTit = New-Object System.Windows.Forms.Label
        $gTit.Text      = [string]$grupo.Titulo
        $gTit.Font      = New-Object System.Drawing.Font('Segoe UI', 7, [System.Drawing.FontStyle]::Bold)
        $gTit.ForeColor = [System.Drawing.Color]$grupo.Cor
        $gTit.Location  = New-Object System.Drawing.Point(10, 7)
        $gTit.Size      = New-Object System.Drawing.Size(([int]$grupo.W - 12), 14)
        [void]$gCard.Controls.Add($gTit)

        # Linha separadora abaixo do titulo
        $gLine = New-Object System.Windows.Forms.Panel
        $gLine.BackColor = [System.Drawing.Color]::FromArgb(22, 40, 60)
        $gLine.Location  = New-Object System.Drawing.Point(10, 23)
        $gLine.Size      = New-Object System.Drawing.Size(([int]$grupo.W - 20), 1)
        [void]$gCard.Controls.Add($gLine)

        # Checkboxes do grupo
        $yChk = 28
        foreach ($itemTxt in @($grupo.Itens)) {
            $chk = New-Object System.Windows.Forms.CheckBox
            $chk.Text      = [string]$itemTxt
            $chk.Font      = New-Object System.Drawing.Font('Segoe UI', 8)
            $chk.ForeColor = [System.Drawing.Color]::FromArgb(200, 226, 244)
            $chk.BackColor = [System.Drawing.Color]::FromArgb(11, 20, 32)
            $chk.Location  = New-Object System.Drawing.Point(10, $yChk)
            $chk.Size      = New-Object System.Drawing.Size(([int]$grupo.W - 16), 20)
            $chk.FlatStyle = 'Flat'
            # Feedback visual: texto acende na cor do grupo quando marcado
            $corGrupo = [System.Drawing.Color]$grupo.Cor
            $chk.Add_CheckedChanged({
                param($s, $ev)
                if ($s.Checked) {
                    $s.ForeColor = $corGrupo
                    $s.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8, [System.Drawing.FontStyle]::Bold)
                } else {
                    $s.ForeColor = [System.Drawing.Color]::FromArgb(200, 226, 244)
                    $s.Font = New-Object System.Drawing.Font('Segoe UI', 8)
                }
            }.GetNewClosure())
            [void]$gCard.Controls.Add($chk)
            $servChecks += $chk
            $yChk += 21
        }
    }

    # --- Header da secao de resumo (mesmo estilo do header PRODUTO) ---
    $resumoHeader = New-Object System.Windows.Forms.Panel
    $resumoHeader.BackColor = [System.Drawing.Color]::FromArgb(7, 14, 24)
    $resumoHeader.Location  = New-Object System.Drawing.Point(20, 446)
    $resumoHeader.Size      = New-Object System.Drawing.Size(800, 22)
    [void]$dlg.Controls.Add($resumoHeader)

    $resumoHeaderAccent = New-Object System.Windows.Forms.Panel
    $resumoHeaderAccent.BackColor = $cGreen
    $resumoHeaderAccent.Location  = New-Object System.Drawing.Point(0, 0)
    $resumoHeaderAccent.Size      = New-Object System.Drawing.Size(3, 22)
    [void]$resumoHeader.Controls.Add($resumoHeaderAccent)

    $lblLoc = New-Object System.Windows.Forms.Label
    $lblLoc.Text      = 'RESUMO DO CADASTRO'
    $lblLoc.Font      = New-Object System.Drawing.Font('Segoe UI', 7, [System.Drawing.FontStyle]::Bold)
    $lblLoc.ForeColor = $cGreen
    $lblLoc.Location  = New-Object System.Drawing.Point(12, 5)
    $lblLoc.Size      = New-Object System.Drawing.Size(160, 14)
    [void]$resumoHeader.Controls.Add($lblLoc)

    $lblLocHint = New-Object System.Windows.Forms.Label
    $lblLocHint.Text      = 'Confira os dados antes de criar a OS'
    $lblLocHint.Font      = New-Object System.Drawing.Font('Segoe UI', 7)
    $lblLocHint.ForeColor = [System.Drawing.Color]::FromArgb(80, 120, 155)
    $lblLocHint.Location  = New-Object System.Drawing.Point(172, 5)
    $lblLocHint.Size      = New-Object System.Drawing.Size(400, 14)
    [void]$resumoHeader.Controls.Add($lblLocHint)

    $resumoPanel = New-Object System.Windows.Forms.Panel
    $resumoPanel.BackColor   = [System.Drawing.Color]::FromArgb(9, 18, 29)
    $resumoPanel.BorderStyle = 'FixedSingle'
    $resumoPanel.Location    = New-Object System.Drawing.Point(20, 468)
    $resumoPanel.Size        = New-Object System.Drawing.Size(800, 112)
    [void]$dlg.Controls.Add($resumoPanel)

    $resumoTopBar = New-Object System.Windows.Forms.Panel
    $resumoTopBar.BackColor = $cGreen
    $resumoTopBar.Location  = New-Object System.Drawing.Point(0, 0)
    $resumoTopBar.Size      = New-Object System.Drawing.Size(800, 2)
    [void]$resumoPanel.Controls.Add($resumoTopBar)

    $resumoValores = @{}

    # Linha 1: labels em cinza + valores em branco, separados por pipes discretos
    $campos1 = @(
        @{ Chave='tecnico';     Titulo='Tecnico';     X=12;  W=90  }
        @{ Chave='osAtual';     Titulo='OS atual';    X=110; W=90  }
        @{ Chave='serial';      Titulo='Serial';      X=208; W=130 }
        @{ Chave='referencia';  Titulo='Referencia';  X=346; W=110 }
        @{ Chave='quantidade';  Titulo='Qtd';         X=464; W=64  }
        @{ Chave='localizacao'; Titulo='Localizacao'; X=536; W=256 }
    )
    foreach ($c in $campos1) {
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text      = [string]$c.Titulo
        $lbl.Font      = New-Object System.Drawing.Font('Segoe UI', 7)
        $lbl.ForeColor = [System.Drawing.Color]::FromArgb(80, 120, 158)
        $lbl.Location  = New-Object System.Drawing.Point([int]$c.X, 10)
        $lbl.Size      = New-Object System.Drawing.Size([int]$c.W, 13)
        [void]$resumoPanel.Controls.Add($lbl)

        $val = New-Object System.Windows.Forms.Label
        $val.Text         = '-'
        $val.Font         = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
        $val.ForeColor    = if ($c.Chave -eq 'osAtual') { $cGreen } else { [System.Drawing.Color]::FromArgb(216, 236, 252) }
        $val.Location     = New-Object System.Drawing.Point([int]$c.X, 24)
        $val.Size         = New-Object System.Drawing.Size([int]$c.W, 18)
        $val.AutoEllipsis = $true
        [void]$resumoPanel.Controls.Add($val)
        $resumoValores[[string]$c.Chave] = $val
    }

    # Pipes separadores linha 1
    foreach ($xPipe in @(102, 200, 338, 456, 528)) {
        $pipe = New-Object System.Windows.Forms.Panel
        $pipe.BackColor = [System.Drawing.Color]::FromArgb(24, 48, 70)
        $pipe.Location  = New-Object System.Drawing.Point($xPipe, 12)
        $pipe.Size      = New-Object System.Drawing.Size(1, 28)
        [void]$resumoPanel.Controls.Add($pipe)
    }

    # Divisor horizontal
    $resumoDivider = New-Object System.Windows.Forms.Panel
    $resumoDivider.BackColor = [System.Drawing.Color]::FromArgb(18, 36, 54)
    $resumoDivider.Location  = New-Object System.Drawing.Point(0, 50)
    $resumoDivider.Size      = New-Object System.Drawing.Size(798, 1)
    [void]$resumoPanel.Controls.Add($resumoDivider)

    # Linha 2: produto (largo) + servicos
    $lblProdTit = New-Object System.Windows.Forms.Label
    $lblProdTit.Text      = 'Produto'
    $lblProdTit.Font      = New-Object System.Drawing.Font('Segoe UI', 7)
    $lblProdTit.ForeColor = [System.Drawing.Color]::FromArgb(80, 120, 158)
    $lblProdTit.Location  = New-Object System.Drawing.Point(12, 57)
    $lblProdTit.Size      = New-Object System.Drawing.Size(580, 13)
    [void]$resumoPanel.Controls.Add($lblProdTit)

    $valProd = New-Object System.Windows.Forms.Label
    $valProd.Text         = '-'
    $valProd.Font         = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
    $valProd.ForeColor    = [System.Drawing.Color]::FromArgb(120, 200, 255)
    $valProd.Location     = New-Object System.Drawing.Point(12, 71)
    $valProd.Size         = New-Object System.Drawing.Size(576, 18)
    $valProd.AutoEllipsis = $true
    [void]$resumoPanel.Controls.Add($valProd)
    $resumoValores['produto'] = $valProd

    $pipe2 = New-Object System.Windows.Forms.Panel
    $pipe2.BackColor = [System.Drawing.Color]::FromArgb(24, 48, 70)
    $pipe2.Location  = New-Object System.Drawing.Point(596, 56)
    $pipe2.Size      = New-Object System.Drawing.Size(1, 32)
    [void]$resumoPanel.Controls.Add($pipe2)

    $lblSvcTit = New-Object System.Windows.Forms.Label
    $lblSvcTit.Text      = 'Servicos'
    $lblSvcTit.Font      = New-Object System.Drawing.Font('Segoe UI', 7)
    $lblSvcTit.ForeColor = [System.Drawing.Color]::FromArgb(80, 120, 158)
    $lblSvcTit.Location  = New-Object System.Drawing.Point(604, 57)
    $lblSvcTit.Size      = New-Object System.Drawing.Size(188, 13)
    [void]$resumoPanel.Controls.Add($lblSvcTit)

    $valSvc = New-Object System.Windows.Forms.Label
    $valSvc.Text         = 'nenhum'
    $valSvc.Font         = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
    $valSvc.ForeColor    = [System.Drawing.Color]::FromArgb(216, 236, 252)
    $valSvc.Location     = New-Object System.Drawing.Point(604, 71)
    $valSvc.Size         = New-Object System.Drawing.Size(188, 18)
    $valSvc.AutoEllipsis = $true
    [void]$resumoPanel.Controls.Add($valSvc)
    $resumoValores['servicos'] = $valSvc

    $txtResumo = New-Object System.Windows.Forms.Label
    $txtResumo.Text         = 'Selecione um produto para preparar o cadastro.'
    $txtResumo.Font         = New-Object System.Drawing.Font('Segoe UI', 7)
    $txtResumo.ForeColor    = [System.Drawing.Color]::FromArgb(54, 90, 122)
    $txtResumo.Location     = New-Object System.Drawing.Point(12, 95)
    $txtResumo.Size         = New-Object System.Drawing.Size(780, 14)
    $txtResumo.AutoEllipsis = $true
    [void]$resumoPanel.Controls.Add($txtResumo)

    function Split-ProdutoOpcaoTexto {
        param([string]$Texto)
        $clean = ([string]$Texto -replace '\s+', ' ').Trim()
        if (-not $clean) { return @() }
        $pattern = '(?=(?:^|\s)(?:(?:[A-Z]\d{2,5}-+(?:[A-Z0-9]{2,4})?)\s+(?:-\s+)?|(?:\d{2,5}-\d{2,5}-\d{2,5}|\d{2,5}(?:_\d+)?)\s+-\s+))'
        $parts = @($clean -split $pattern | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        if ($parts.Count -gt 1) { return $parts }
        return @($clean)
    }

    function Resolve-ProdutoBuscaTermosLocal {
        param([string]$Termo)
        $original = ([string]$Termo).Trim()
        $t = $original.ToUpper() -replace '[^A-Z0-9 ]', ' '

        $cpu = ''
        if    ($t -match '\bI3\b')            { $cpu = 'I3' }
        elseif ($t -match '\bI5\b')            { $cpu = 'I5' }
        elseif ($t -match '\bI7\b')            { $cpu = 'I7' }
        elseif ($t -match 'RYZEN\s*5|\bR5\b') { $cpu = 'Ryzen 5' }
        elseif ($t -match 'RYZEN\s*7|\bR7\b') { $cpu = 'Ryzen 7' }
        elseif ($t -match '\bULTRA\s*7\b')    { $cpu = 'ULTRA 7' }
        elseif ($t -match '\bULTRA\s*5\b')    { $cpu = 'ULTRA 5' }

        $gen = ''
        if    ($t -match '\b13(TH|A)?\b') { $gen = '13th' }
        elseif ($t -match '\b12(TH|A)?\b') { $gen = '12th' }
        elseif ($t -match '\b11(TH|A)?\b') { $gen = '11th' }
        elseif ($t -match '\b10(TH|A)?\b') { $gen = '10th' }
        elseif ($t -match '\b08(TH|A)?\b|\b8(TH|A)?\b') { $gen = '08th' }
        elseif ($t -match '\b07(TH|A)?\b|\b7(TH|A)?\b') { $gen = '07th' }

        # Usa apenas CPU como qualificador — geração não é necessária e torna a API lenta
        $qual = $cpu

        # Helper: monta termo de busca com prefixo completo (como o Altertag web usa)
        function mkTermo { param($base) if ($qual) { return "Notebook $base $qual" } else { return "Notebook $base" } }

        # ─── Dell Latitude ────────────────────────────────────────────────────
        foreach ($modelo in @('3420','3410','3440','3400','3450','3480','3490','3550',
                               '5420','5410','5430','5450','5480','5490','5400',
                               '5300','5320','5340',
                               '7280','7300','7310','7320','7390','7400','7410','7420','7430','7480')) {
            if ($t -match "\b$modelo\b") { return @(mkTermo "Dell Latitude $modelo") }
        }
        # ─── Dell Latitude E-series ───────────────────────────────────────────
        foreach ($modelo in @('E5430','E5440','E5450','E5470','E7450','E7470')) {
            if ($t -match "\b$modelo\b") { return @(mkTermo "Dell Latitude $modelo") }
        }
        # ─── Dell Inspiron ───────────────────────────────────────────────────
        foreach ($modelo in @('3520','3567','3583','5566','5570','5510')) {
            if ($t -match "\b$modelo\b") { return @(mkTermo "Dell Inspiron $modelo") }
        }
        # ─── Dell Vostro ─────────────────────────────────────────────────────
        foreach ($modelo in @('3400','3401','3468','3481','3501','3510','5402')) {
            if ($t -match 'VOSTRO' -and $t -match "\b$modelo\b") { return @(mkTermo "Dell Vostro $modelo") }
        }
        # ─── Dell Precision ──────────────────────────────────────────────────
        foreach ($modelo in @('3571','5520','7540')) {
            if ($t -match "\b$modelo\b") { return @(mkTermo "Dell Precision $modelo") }
        }
        # ─── Dell G-series / XPS ─────────────────────────────────────────────
        if ($t -match 'G15')  { return @(mkTermo 'Dell G15 5530') }
        if ($t -match '\bG3\b') { return @(mkTermo 'Dell G3 3500') }
        if ($t -match '\bG5\b') { return @(mkTermo 'Dell G5') }
        if ($t -match '\bXPS\b') { return @(mkTermo 'Dell XPS') }
        # ─── Lenovo ThinkPad E14 ─────────────────────────────────────────────
        if ($t -match '\bE14\b') {
            if ($cpu -eq 'Ryzen 5') { return @('Notebook Lenovo E14 Ryzen 5') }
            if ($cpu -eq 'Ryzen 7') { return @('Notebook Lenovo E14 Ryzen 7') }
            return @(mkTermo 'Lenovo E14')
        }
        # ─── Lenovo ThinkPad T14 ─────────────────────────────────────────────
        if ($t -match '\bT14\b') {
            if ($cpu -eq 'Ryzen 5') { return @('Notebook Lenovo T14 Ryzen 5') }
            return @(mkTermo 'Lenovo T14')
        }
        # ─── Lenovo ThinkPad outros ──────────────────────────────────────────
        if ($t -match '\bT15\b')  { return @('Notebook Lenovo T15') }
        if ($t -match '\bT16\b')  { return @('Notebook Lenovo T16') }
        if ($t -match '\bT480\b') { return @('Notebook Lenovo Thinkpad E480') }
        if ($t -match '\bT490\b') { return @('Notebook Thinkpad T490') }
        if ($t -match '\bX13\b')  { return @('Notebook Lenovo X13 YOGA') }
        if ($t -match '\bX280\b') { return @('Notebook Lenovo X280') }
        if ($t -match '\bX390\b') { return @('Notebook Thinkpad X390') }
        if ($t -match '\bX1\b')   { return @('Notebook Lenovo X1 Yoga') }
        if ($t -match '\bV15\b')  { return @(mkTermo 'Lenovo V15') }
        if ($t -match '\bP15\b')  { return @('Notebook Lenovo P15') }
        if ($t -match '\bL14\b')  { return @('Notebook Thinkpad L14') }
        # ─── Lenovo IdeaPad / Yoga ────────────────────────────────────────────
        if ($t -match 'S145')      { return @(mkTermo 'Lenovo IdeaPad s145') }
        if ($t -match 'YOGA\s*SLIM') { return @('Notebook Lenovo Yoga Slim') }
        if ($t -match 'IDEAPAD') {
            foreach ($sub in @('330','3','1')) {
                if ($t -match "\b$sub\b") { return @(mkTermo "Lenovo IdeaPad $sub") }
            }
            return @(mkTermo 'Lenovo IdeaPad')
        }
        # ─── Apple MacBook ────────────────────────────────────────────────────
        if ($t -match 'MACBOOK|MAC\s*BOOK') {
            if ($t -match 'AIR')  { return @('Apple Macbook AIR') }
            if ($t -match '16')   { return @('Apple MacBook Pro 16') }
            if ($t -match 'M1')   { return @('Apple Macbook Pro M1') }
            if ($cpu)             { return @("Notebook Apple MacBook Pro $cpu") }
            return @('Apple Macbook Pro')
        }
        # ─── Samsung ──────────────────────────────────────────────────────────
        if ($t -match 'SAMSUNG|GALAXY\s*BOOK') {
            if ($t -match 'GALAXY\s*BOOK\s*4') { return @('Notebook SAMSUNG Galaxy book 4') }
            if ($t -match 'GALAXY\s*BOOK\s*2') { return @('Notebook SAMSUNG Galaxy BOOK2') }
            if ($cpu) { return @("Notebook SAMSUNG BOOK $cpu") }
            return @('Notebook SAMSUNG BOOK')
        }
        # ─── HP EliteBook / ProBook ───────────────────────────────────────────
        if ($t -match 'ELITEBOOK') {
            foreach ($modelo in @('830','840','850')) {
                if ($t -match "\b$modelo\b") {
                    $gen2 = if ($t -match 'G8') { 'G8' } elseif ($t -match 'G6') { 'G6' } else { '' }
                    $base = "HP EliteBook $modelo $gen2".Trim()
                    return @(mkTermo $base)
                }
            }
            return @(mkTermo 'HP EliteBook')
        }
        if ($t -match 'DRAGONFLY') { return @('Notebook HP Dragonfly') }
        if ($t -match 'PROBOOK')   { return @(mkTermo 'HP Probook') }
        # ─── Acer ─────────────────────────────────────────────────────────────
        if ($t -match 'NITRO\s*5')   { return @(mkTermo 'Acer NITRO 5') }
        if ($t -match 'TRAVELMATE')  { return @(mkTermo 'Acer travelmate') }
        # ─── Positivo ─────────────────────────────────────────────────────────
        if ($t -match 'N2240|MASTER\s*N2240') { return @('Notebook Positivo Master N2240') }
        if ($t -match 'N1140') { return @('Notebook Positivo N1140') }
        if ($t -match 'N1240') { return @('Notebook Positivo N1240') }
        if ($t -match 'N1250') { return @('Notebook Positivo N1250') }
        if ($t -match 'POSITIVO') { return @('Notebook Positivo') }
        # ─── VAIO ─────────────────────────────────────────────────────────────
        if ($t -match '\bVAIO\b') {
            if ($t -match 'FE14')     { return @('Notebook VAIO FE14') }
            if ($t -match 'FE15')     { return @('Notebook VAIO FE15') }
            if ($t -match 'FIT')      { return @('Notebook VAIO FIT') }
            if ($t -match 'PRO\s*PX') { return @('Notebook VAIO pro PX') }
            if ($t -match 'PRO\s*PW') { return @('Notebook VAIO pro PW') }
            return @(mkTermo 'VAIO')
        }
        # ─── Surface ──────────────────────────────────────────────────────────
        if ($t -match 'SURFACE') { return @(mkTermo 'MICROSOFT SURFACE') }
        # ─── Asus Vivobook ────────────────────────────────────────────────────
        if ($t -match 'VIVOBOOK|ASUS') { return @(mkTermo 'Asus vivobook') }
        # ─── Nenhuma regra casou — usa termo original ─────────────────────────
        return @($original)
    }

    # Catálogo local de produtos baseado no CSV Altertag
    $script:catalogoProdutosLocal = @(
        # ── Codigos T (avulsos Altertag, com ID VHSys) ──────────────────────
        @{c='T023';n='Notebook Dell Latitude 3420 I5 11th';e='0';i=83020915}
        @{c='T029';n='CPU DELL OptiPlex 3050 i5 07th';e='1';i=83145792}
        @{c='T032';n='Notebook Lenovo T14 i5 11th';e='0';i=83064775}
        @{c='T034';n='CPU DELL OptiPlex 3090 i5 10th';e='1';i=83267127}
        @{c='T035';n='Notebook Dell Latitude 5420 i5 11th';e='1';i=80612872}
        @{c='T047';n='Notebook DELL Latitude 7320 I7 11th';e='1';i=83011147}
        @{c='T049';n='Notebook Thinkpad T490 I7 08th';e='1';i=83049161}
        @{c='T052';n='Mini Desktop DELL OptiPlex 3070 i5 09th';e='1';i=80934460}
        @{c='T086';n='CPU DELL OptiPlex 3070 i5 09th';e='1';i=83145726}
        @{c='T090';n='CPU Lenovo ThinkCentre M93p I5 04th';e='1';i=83241902}
        # ── Dell Latitude 3400 ──────────────────────────────────────────────
        @{c='A001-C2F';n='Notebook Dell Latitude 3400 I5 08th 8GB SSD 256 W10P';e='1'}
        @{c='A001-D3B';n='Notebook Dell Latitude 3400 I7 08th 16GB HD 500 W10P';e='0'}
        @{c='A001-D3F';n='Notebook Dell Latitude 3400 I7 08th 16GB SSD 256 W10P';e='0'}
        @{c='A001-D2F';n='Notebook Dell Latitude 3400 I7 08th 8GB SSD 256 W10P';e='6'}
        # ── Dell Latitude 3410 ──────────────────────────────────────────────
        @{c='P040';n='Notebook Dell Latitude 3410 I5 10th';e='0'}
        @{c='A040-C2F';n='Notebook Dell Latitude 3410 I5 10th 8GB RAM SSD 256 W11P';e='3'}
        @{c='P040-D';n='Notebook Dell Latitude 3410 I7 10th';e='0'}
        @{c='A040-D3F';n='Notebook Dell Latitude 3410 I7 10th 16GB RAM SSD 256 W11P';e='14'}
        @{c='A040-D2F';n='Notebook Dell Latitude 3410 I7 10th 8GB RAM SSD 256 W11P';e='1'}
        # ── Dell Latitude 3420 ──────────────────────────────────────────────
        @{c='A023-B2F';n='Notebook Dell Latitude 3420 I3 11th 8GB SSD 256GB W11P';e='0'}
        @{c='P023--';n='Notebook Dell Latitude 3420 I5 11th';e='0'}
        @{c='A023-C2F';n='Notebook Dell Latitude 3420 I5 11th 8GB SSD 256 W11P';e='71'}
        @{c='P023-C2F';n='Notebook Dell Latitude 3420 I5 11th 8GB SSD 256 W11P';e='0'}
        @{c='A023-C2G';n='Notebook Dell Latitude 3420 I5 11th 8GB SSD 512GB W11P';e='9'}
        @{c='A023-C3F';n='Notebook Dell Latitude 3420 I5 11th 16GB SSD 256 W11P';e='26'}
        @{c='A023-C3H';n='Notebook Dell Latitude 3420 I5 11th 16GB SSD 512GB W11P';e='2'}
        @{c='P023';n='Notebook Dell Latitude 3420 I7 11th';e='0'}
        @{c='A023-D2F';n='Notebook Dell Latitude 3420 I7 11th 8GB SSD 256 W11P';e='10'}
        @{c='A023-D3F';n='Notebook Dell Latitude 3420 I7 11th 16GB SSD 256 W11P';e='7'}
        @{c='A023-D3H';n='Notebook Dell Latitude 3420 I7 11th 16GB SSD 512 W11P';e='1'}
        # ── Dell Latitude 3440 ──────────────────────────────────────────────
        @{c='A002-C3F';n='Notebook Dell Latitude 3440 I5 13th 16GB SSD 256 W11P';e='1'}
        @{c='A002-C3H';n='Notebook Dell Latitude 3440 I5 13th 16GB SSD 512GB W11P';e='1'}
        @{c='A002-D3F';n='Notebook Dell Latitude 3440 I7 13th 16GB SSD 256 W11P';e='0'}
        # ── Dell Latitude 3450 ──────────────────────────────────────────────
        @{c='A096-D3H';n='Notebook Dell Latitude 3450 I7 13th 16GB 512GB W11P';e='0'}
        # ── Dell Latitude 3480/3490 ─────────────────────────────────────────
        @{c='100-0008-02';n='Notebook Dell Latitude 3490 I5 07th 8GB RAM 256SSD W11P';e='10'}
        @{c='100-0010-03';n='Notebook Dell Latitude 3490 I7 08th 8GB RAM SSD 256GB W11P';e='8'}
        @{c='100-0180-03';n='Notebook Dell Latitude 3490 I7 08th 16GB RAM SSD 256GB W11P';e='0'}
        @{c='100-0007-03';n='Notebook Dell Latitude 3480 I7 07th 8GB RAM SSD 240 W11P';e='1'}
        # ── Dell Latitude 3550 ──────────────────────────────────────────────
        @{c='A057-D3H';n='Notebook Dell Latitude 3550 I7 13th 16GB RAM SSD 512GB W11P';e='0'}
        # ── Dell Latitude 5410 ──────────────────────────────────────────────
        @{c='A045-C2F';n='Notebook Dell Latitude 5410 I5 10th 8GB SSD 256GB W11P';e='4'}
        @{c='A045-C3F';n='Notebook Dell Latitude 5410 I5 10th 16GB SSD 256GB';e='0'}
        @{c='A045-C3I';n='Notebook Dell Latitude 5410 I5 10th 16GB SSD 1TB W11P';e='0'}
        @{c='A045-D3F';n='Notebook Dell Latitude 5410 I7 10th 16GB SSD 256GB W11P';e='2'}
        @{c='000-0185-02';n='Notebook Dell Latitude 5410 I7 10th 8GB SSD 256GB';e='27'}
        @{c='000-0187-03';n='Notebook Dell Latitude 5410 I7 10th 16GB SSD 512GB';e='25'}
        # ── Dell Latitude 5420 ──────────────────────────────────────────────
        @{c='P035';n='Notebook Dell Latitude 5420 I5 11th';e='205'}
        @{c='A035-C2F';n='Notebook Dell Latitude 5420 I5 11th 8GB SSD 256 W11P';e='1'}
        @{c='P035-C2F';n='Notebook Dell Latitude 5420 I5 11th 8GB 256GB W11P';e='1'}
        @{c='A035-C3F';n='Notebook Dell Latitude 5420 I5 11th 16GB SSD 256 W11P';e='23'}
        @{c='P035-C3F';n='Notebook Dell Latitude 5420 I5 11th 16GB SSD 256 W11P';e='3'}
        @{c='A035-C3H';n='Notebook Dell Latitude 5420 I5 11th 16GB SSD 512GB W11P';e='0'}
        @{c='A035-D2F';n='Notebook Dell Latitude 5420 I7 11th 8GB SSD 256 W11P';e='0'}
        @{c='A035-D3F';n='Notebook Dell Latitude 5420 I7 11th 16GB SSD 256GB';e='4'}
        @{c='A035-D4I';n='Notebook Dell Latitude 5420 I7 11th 32GB SSD 1TB W11P';e='1'}
        # ── Dell Latitude 5430 ──────────────────────────────────────────────
        @{c='100-0184-02';n='Notebook Dell Latitude 5430 I5 12th 16GB RAM SSD 512GB W11P';e='0'}
        @{c='100-0184-03';n='Notebook Dell Latitude 5430 I7 12th 16GB RAM SSD 512GB W11P';e='0'}
        # ── Dell Latitude 5450 ──────────────────────────────────────────────
        @{c='P103-';n='Notebook Dell Latitude 5450 ULTRA 5';e='0'}
        @{c='100-0219-02';n='Notebook Dell Latitude 5450 ULTRA 5 135U 8GB RAM SSD 256GB W11P';e='0'}
        @{c='100-0260-02';n='Notebook Dell Latitude 5450 ULTRA 5 16GB RAM SSD 512GB W11P';e='0'}
        @{c='P103';n='Notebook Dell Latitude 5450 ULTRA 7';e='0'}
        @{c='C103-D3H';n='Notebook Dell Latitude 5450 ULTRA 7 165U 16GB 512GB W11P';e='0'}
        # ── Dell Latitude 5480/5490 ─────────────────────────────────────────
        @{c='A004-C2F';n='Notebook Dell Latitude 5480 I5 07th 8GB SSD 256GB';e='0'}
        @{c='A004-D2F';n='Notebook Dell Latitude 5480 I7 07th 8GB SSD 256GB';e='0'}
        @{c='A005-C2F';n='Notebook Dell Latitude 5490 I5 08th 8GB SSD 256GB';e='0'}
        @{c='A005-C3F';n='Notebook Dell Latitude 5490 I5 08th 16GB SSD 256GB';e='0'}
        @{c='A005-C3G';n='Notebook Dell Latitude 5490 I5 08th 16GB SSD 480GB W10P';e='0'}
        # ── Dell Latitude 5400 ──────────────────────────────────────────────
        @{c='C063-C2F';n='Notebook Dell Latitude 5400 I5 08th 8GB RAM SSD 256 W11P';e='5'}
        @{c='C063-C3F';n='Notebook Dell Latitude 5400 I5 08th 16GB RAM SSD 256 W11P';e='0'}
        @{c='P063';n='Notebook Dell Latitude 5400 I7 08th';e='0'}
        @{c='C063-D2F';n='Notebook Dell Latitude 5400 I7 08th 8GB RAM SSD 256 W11P';e='0'}
        @{c='C063-D3F';n='Notebook Dell Latitude 5400 I7 08th 16GB RAM SSD 256';e='3'}
        @{c='C063-D3H';n='Notebook Dell Latitude 5400 I7 08th 16GB SSD 512 W11P';e='0'}
        # ── Dell Latitude 5320 ──────────────────────────────────────────────
        @{c='100-0021-03';n='Notebook Dell Latitude 5320 I7 11th VPRO 16GB RAM SSD 256 W11P';e='2'}
        # ── Dell Latitude 5340 ──────────────────────────────────────────────
        @{c='A003-D3H';n='Notebook Dell Latitude 5340 I7 13th 16GB SSD 512';e='0'}
        # ── Dell Latitude 7310 ──────────────────────────────────────────────
        @{c='A038-C3H';n='Notebook Dell Latitude 7310 I5 10th 16GB RAM SSD 512GB W11P';e='0'}
        @{c='A038-D2F';n='Notebook Dell Latitude 7310 I7 10th 8GB RAM SSD 256GB W11P';e='0'}
        # ── Dell Latitude 7320 ──────────────────────────────────────────────
        @{c='C047-C3H';n='Notebook DELL Latitude 7320 I5 11th 16GB SSD 512GB W11P';e='0'}
        @{c='P047';n='Notebook DELL Latitude 7320 I7 11th';e='0'}
        @{c='C047-D3H';n='Notebook DELL Latitude 7320 I7 11th 16GB SSD 512GB W11P';e='0'}
        @{c='P046-D3H';n='Notebook DELL Latitude 7320 I7 11th 16GB SSD 512GB TABLET 2 EM 1 W11P';e='0'}
        # ── Dell Latitude 7390/7400/7420/7430 ──────────────────────────────
        @{c='A007-C2F';n='Notebook Dell Latitude 7390 I5 08th 8GB SSD 256GB W10P';e='0'}
        @{c='P008-D3F';n='Notebook Dell Latitude 7400 I7 08th 16GB SSD 256GB W10P';e='0'}
        @{c='100-0207-02';n='Notebook Dell Latitude 7420 I5 11th 16GB RAM SSD 256GB';e='0'}
        @{c='100-0047-03';n='Notebook Dell Latitude 7420 I7 11th 16GB RAM SSD 256GB 2 em 1 W11P';e='0'}
        @{c='A043-D3H';n='Notebook Dell Latitude 7430 I7 12th 16GB RAM SSD 512GB W11P';e='0'}
        # ── Dell Latitude E-series ──────────────────────────────────────────
        @{c='100-0042-02';n='Notebook Dell Latitude E5430 I5 03rd 8GB RAM SSD 128GB W11P';e='0'}
        @{c='100-0043-02';n='Notebook Dell Latitude E5440 I5 04th 8GB RAM SSD 256GB W11P';e='0'}
        @{c='A018-C2F';n='Notebook Dell Latitude E5450 I5 05th 8GB SSD 256GB W10P';e='0'}
        @{c='200-0167-02';n='Notebook DELL Latitude E5470 I5 06th 8GB RAM SSD 240GB';e='0'}
        # ── Dell Inspiron ───────────────────────────────────────────────────
        @{c='A014-B2F';n='Notebook Dell Inspiron 3520 I3 12th 8GB SSD 256GB W11P';e='0'}
        @{c='A015-C2E';n='Notebook Dell Inspiron 3583 I5 08th 8GB SSD 240GB W10P';e='0'}
        @{c='A016-C2F';n='Notebook Dell Inspiron 5566 I5 07th 8GB SSD 256GB W10P';e='0'}
        @{c='A016-D2F';n='Notebook Dell Inspiron 5566 I7 07th 8GB SSD 256GB W10P';e='0'}
        # ── Dell Vostro ─────────────────────────────────────────────────────
        @{c='A013-C3F';n='Notebook Dell Vostro 5402 I5 11th 16GB SSD 256GB W11P';e='0'}
        @{c='A013-D3F';n='Notebook Dell Vostro 5402 I7 11th 16GB SSD 256GB W11P';e='0'}
        @{c='A010-D2F';n='Notebook Dell Vostro 3400 I7 11th 8GB SSD 256GB W11P';e='0'}
        @{c='400-0055-02';n='Notebook Dell Vostro 3401 I5 10th 8GB RAM SSD 256GB';e='0'}
        @{c='100-0053-02';n='Notebook Dell Vostro 3510 I5 10th 8GB RAM SSD 256GB';e='0'}
        # ── Dell Precision ──────────────────────────────────────────────────
        @{c='100-0231-03';n='Notebook Dell Precision 3571 I7 12th 32GB RAM SSD 512GB';e='0'}
        @{c='A017-D3F';n='Notebook Dell Precision 5520 I7 07th 16GB SSD 256GB W10P';e='0'}
        # ── Dell XPS ────────────────────────────────────────────────────────
        @{c='200-0249-03';n='Notebook Dell XPS 13 9310 I7 11th 16GB SSD 1T';e='0'}
        # ── Lenovo ThinkPad E14 ─────────────────────────────────────────────
        @{c='P019-';n='Notebook Lenovo E14 I5 10th';e='0'}
        @{c='C019-C2F';n='Notebook Lenovo E14 I5 10th 8GB 256GB W11P';e='0'}
        @{c='P019';n='Notebook Lenovo E14 I7 10th';e='0'}
        @{c='C019-D2F';n='Notebook Lenovo E14 I7 10th 8GB SSD 256GB W11P';e='0'}
        @{c='C019-D3F';n='Notebook Lenovo E14 I7 10th 16GB SSD 256GB W11P';e='0'}
        @{c='C019-D3H';n='Notebook Lenovo E14 I7 10th 16GB SSD 512GB W11P';e='0'}
        @{c='P020';n='Notebook Lenovo E14 I5 11th';e='0'}
        @{c='C020-C2F';n='Notebook Lenovo E14 I5 11th 8GB SSD 256GB W11P';e='0'}
        @{c='C020-C3F';n='Notebook Lenovo E14 I5 11th 16GB SSD 256GB';e='0'}
        @{c='P020-';n='Notebook Lenovo E14 I7 11th';e='0'}
        @{c='C020-D2F';n='Notebook Lenovo E14 I7 11th 8GB SSD 256GB W11P';e='0'}
        @{c='C020-D3F';n='Notebook Lenovo E14 I7 11th 16GB SSD 256GB W11P';e='0'}
        @{c='P019--';n='Notebook Lenovo E14 Ryzen';e='0'}
        @{c='C019-G2F';n='Notebook Lenovo E14 Ryzen 5 5500 8GB SSD 256GB W11P';e='0'}
        @{c='C019-H3G';n='Notebook Lenovo E14 Ryzen 7 5700 16GB SSD 480GB W11P';e='0'}
        # ── Lenovo ThinkPad T14 ─────────────────────────────────────────────
        @{c='P031';n='Notebook Lenovo T14 I5 10th';e='0'}
        @{c='A031-C2F';n='Notebook Lenovo T14 I5 10th 8GB 256GB W11P';e='0'}
        @{c='A031-C3F';n='Notebook Lenovo T14 I5 10th 16GB SSD 256 W11P';e='0'}
        @{c='A031-C3H';n='Notebook Lenovo T14 I5 10th 16GB SSD 512 W11P';e='0'}
        @{c='P031-';n='Notebook Lenovo T14 I7 10th';e='0'}
        @{c='A031-D3F';n='Notebook Lenovo T14 I7 10th 16GB SSD 256 W11P';e='0'}
        @{c='P032';n='Notebook Lenovo T14 I5 11th';e='0'}
        @{c='A032-C2F';n='Notebook Lenovo T14 I5 11th 8GB 256GB W11P';e='0'}
        @{c='A032-C3F';n='Notebook Lenovo T14 I5 11th 16GB SSD 256GB W11P';e='0'}
        @{c='P032-';n='Notebook Lenovo T14 I7 11th';e='0'}
        @{c='A032-D3F';n='Notebook Lenovo T14 I7 11th 16GB SSD 256 W11P';e='0'}
        @{c='A032-G3F';n='Notebook Lenovo T14 AMD Ryzen 5 PRO 4650U 16GB SSD 256GB W11P';e='0'}
        # ── Lenovo ThinkPad T/X/V ───────────────────────────────────────────
        @{c='P065';n='Notebook Lenovo T15 I7 10th';e='0'}
        @{c='P066';n='Notebook Lenovo T16 I7 12th';e='0'}
        @{c='P049-D3F';n='Notebook Thinkpad T490 I7 08th 16GB RAM SSD 256GB W10P';e='0'}
        @{c='A050-C2F';n='Notebook Lenovo Thinkpad E480 I5 08th 8GB RAM SSD 256GB W10P';e='0'}
        @{c='P067-C3F';n='Notebook Thinkpad X390 I5 08th 16GB RAM SSD 256GB';e='0'}
        @{c='C100-D3F';n='Notebook Lenovo X1 Yoga G6 Evo I7 11th 16GB RAM SSD 256GB W11P';e='0'}
        @{c='A051-C3F';n='Notebook Lenovo X13 YOGA I5 11th 16GB SSD 256 2in1 W11P';e='0'}
        @{c='A037-C3H';n='Notebook Lenovo V15 I5 13th 16GB SSD 512GB W11P';e='0'}
        @{c='000-0075-02';n='Notebook Thinkpad V15 G2 I5 11th 8GB RAM SSD 256GB';e='0'}
        @{c='500-0257-02';n='Notebook Thinkpad V15 G3 I5 12th 8GB RAM SSD 256GB W11P';e='0'}
        @{c='A048-D4H';n='Notebook Lenovo P15 I7 10th 32GB SSD 512 W11P';e='0'}
        # ── Lenovo IdeaPad ──────────────────────────────────────────────────
        @{c='000-0064-02';n='Notebook Lenovo IdeaPad s145 I5 08th 8GB RAM SSD 256GB W11P';e='0'}
        @{c='000-0065-02';n='Notebook Lenovo IdeaPad s145 I5 10th 8GB RAM SSD 256GB';e='0'}
        @{c='200-0116-02';n='Notebook Lenovo IdeaPad 3 I5 11th 8GB RAM SSD 256GB';e='0'}
        @{c='200-0190-02';n='Notebook Lenovo IdeaPad 3 I5 11th 8GB RAM SSD 512GB';e='0'}
        @{c='000-0068-01';n='Notebook Lenovo IdeaPad 1 I3 12th 8GB RAM SSD 256GB';e='0'}
        @{c='000-0222-02';n='Notebook Lenovo IdeaPad 1 I5 12th 8GB RAM SSD 512GB';e='0'}
        @{c='000-0067-12';n='Notebook Lenovo IdeaPad 1 AMD Ryzen 5 7520 8GB RAM SSD 256GB';e='0'}
        @{c='200-0109-02';n='Notebook Lenovo Yoga Slim 6 Evo I5 12th 16GB RAM SSD 512GB W11P';e='0'}
        # ── Apple MacBook ────────────────────────────────────────────────────
        @{c='A099-J2F';n='Apple Macbook AIR 13 M1 2020 8GB 256GB';e='0'}
        @{c='A098-J2F';n='Apple Macbook Pro 13 M1 2020 8GB 256GB';e='0'}
        @{c='R097-D3F';n='Apple Macbook Pro 13 I7 2018 16GB 256GB';e='0'}
        @{c='000-0143-04';n='Apple MacBook Pro 16 I9 16GB SSD 1TB';e='0'}
        @{c='600-0110-02';n='Notebook Apple MacBook Pro 13 I5 8GB SSD 256';e='0'}
        # ── Samsung ──────────────────────────────────────────────────────────
        @{c='000-0148-02';n='Notebook SAMSUNG BOOK I5 11th 8GB RAM 256GB SSD';e='0'}
        @{c='000-0146-01';n='Notebook SAMSUNG Galaxy BOOK2 I3 12th 8GB RAM 256GB SSD';e='0'}
        @{c='500-0100-02';n='Notebook SAMSUNG Galaxy BOOK2 I5 12th 8GB RAM 256GB SSD';e='0'}
        @{c='100-0256-01';n='Notebook SAMSUNG Galaxy book 4 I3 13th 8GB SSD 256GB W11P';e='0'}
        # ── HP ───────────────────────────────────────────────────────────────
        @{c='300-0125-02';n='Notebook HP EliteBook 840 G6 I5 08th 8GB SSD 256GB';e='0'}
        @{c='200-0131-03';n='Notebook HP EliteBook 840 G6 I7 08th 8GB SSD 256GB';e='0'}
        @{c='200-0130-03';n='Notebook HP EliteBook 840 G8 I7 11th 32GB SSD 512GB';e='0'}
        @{c='300-0124-03';n='Notebook HP EliteBook 830 G8 I7 11th 16GB SSD 512GB';e='0'}
        @{c='200-0129-02';n='Notebook HP Probook 640 G8 I5 11th 16GB SSD 256GB';e='0'}
        @{c='000-0123-11';n='Notebook HP Probook 445 G7 AMD Ryzen 3 4300 16GB SSD 256GB';e='0'}
        # ── Acer ─────────────────────────────────────────────────────────────
        @{c='400-0058-02';n='Notebook Acer NITRO 5 I5 08th 16GB RAM SSD 480GB';e='0'}
        @{c='400-0254-02';n='Notebook Acer NITRO 5 I5 11th 16GB RAM SSD 512GB GTX 1620 4GB';e='0'}
        @{c='500-0154-02';n='Notebook Acer travelmate P2 14 I5 13th 8GB SSD 256GB';e='0'}
        # ── VAIO ─────────────────────────────────────────────────────────────
        @{c='000-0158-01';n='Notebook VAIO FE14 I3 10th 8GB SSD 256GB';e='0'}
        @{c='000-0160-02';n='Notebook VAIO FE14 I5 10th 8GB SSD 256GB';e='0'}
        @{c='000-0208-01';n='Notebook VAIO FE15 I3 11th 8GB SSD 256GB';e='0'}
        @{c='000-0161-02';n='Notebook VAIO FE15 I5 12th 8GB SSD 256GB';e='0'}
        @{c='000-0163-02';n='Notebook VAIO FIT 15s I5 07th 8GB SSD 240GB';e='0'}
        @{c='000-0162-02';n='Notebook VAIO pro PW I5 12th 8GB SSD 256GB';e='0'}
        @{c='000-0157-01';n='Notebook VAIO pro PX I3 11th 8GB SSD 256GB';e='0'}
        @{c='000-0209-02';n='Notebook VAIO pro PX I5 12th 8GB SSD 256GB';e='0'}
        # ── Positivo ─────────────────────────────────────────────────────────
        @{c='P059-B2D';n='Notebook Positivo Master N2240 I3 11th 8GB SSD 128GB W11P';e='0'}
        @{c='P-97';n='Notebook Positivo Master N2240 I5 11th 8GB SSD 256GB W11P';e='0'}
        @{c='P062-A1D';n='Notebook Positivo N1140 Celeron 4GB RAM W11P';e='0'}
        @{c='P064-A1D';n='Notebook Positivo N1240 Dual Core 4GB RAM 128GB SSD W11P';e='0'}
        @{c='P063-A1D';n='Notebook Positivo N1250 Pentium 4GB RAM 128GB SSD W11P';e='0'}
        # ── Surface ──────────────────────────────────────────────────────────
        @{c='P-96';n='NOTEBOOK MICROSOFT SURFACE 1951 I5 11th 16GB SSD 256 W11P';e='0'}
        # ── Asus ─────────────────────────────────────────────────────────────
        @{c='000-0153-02';n='Notebook Asus vivobook x1504Z I5 12th 8GB SSD 256GB';e='0'}
        @{c='000-0152-01';n='Notebook Asus vivobook Go E1504G I3 N305 4GB SSD 256GB';e='0'}
        # ── ThinkPad L/P ─────────────────────────────────────────────────────
        @{c='000-0070-12';n='Notebook Thinkpad L14 AMD Ryzen 5 Pro 4650 16GB RAM SSD 512';e='0'}
        @{c='300-0076-03';n='Notebook Thinkpad P52 I7 08th 32GB RAM SSD 512GB NVIDIA Quadro p1000 4GB';e='0'}
    )

    function Search-CatalogoProdutosLocal {
        param([string]$Termo)
        $palavras = ($Termo.ToUpper() -replace '[^A-Z0-9]', ' ' -split '\s+') | Where-Object { $_.Length -ge 2 }
        if ($palavras.Count -eq 0) { return @() }
        $resultados = $script:catalogoProdutosLocal | Where-Object {
            $nomeUpper = $_.n.ToUpper()
            $codigoUpper = $_.c.ToUpper()
            $todosPresentes = $true
            foreach ($p in $palavras) {
                if ($nomeUpper -notmatch [regex]::Escape($p) -and $codigoUpper -notmatch [regex]::Escape($p)) {
                    $todosPresentes = $false
                    break
                }
            }
            $todosPresentes
        }
        $itensLocais = @($resultados | ForEach-Object {
            $textoExib = "$($_.c) - $($_.n)"
            [pscustomobject]@{
                texto        = $textoExib
                codigo       = $_.c
                idProduto    = if ($_.ContainsKey('i')) { [int]$_.i } else { 0 }
                descricao    = $_.n
                valor        = '0.00'
                estoque      = $_.e
                estoqueDisplay = if ($_.e -and $_.e -ne '0') { $_.e } else { '' }
            }
        })
        return @($itensLocais | Sort-Object -Property @{ Expression = { Get-ProdutoSortKeyLocal $_ } })
    }

    function Normalize-ProdutoQuantidade {
        param([string]$Quantidade)
        $q = ([string]$Quantidade).Trim()
        if (-not $q) { return '' }
        if ($q -match '\s') { return '' }
        if ($q -notmatch '^-?\d+(?:[,.]\d+)?$') { return '' }
        return $q
    }

    function Format-ProdutoQuantidadeDisplay {
        param([string]$Quantidade)
        $q = Normalize-ProdutoQuantidade $Quantidade
        if (-not $q) { return '' }
        [decimal]$decimal = 0
        if ([decimal]::TryParse($q.Replace(',', '.'), [System.Globalization.NumberStyles]::Number, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$decimal)) {
            return $decimal.ToString('0.00', [System.Globalization.CultureInfo]::GetCultureInfo('pt-BR'))
        }
        return $q.Replace('.', ',')
    }

    function Get-ProdutoCodigoLocal {
        param($Produto)
        $codigoLocal = ''
        if ($Produto.PSObject.Properties['codigo'] -and $Produto.codigo) { $codigoLocal = ([string]$Produto.codigo).Trim().ToUpper() }
        if (-not $codigoLocal -and $Produto.PSObject.Properties['texto'] -and [string]$Produto.texto -match '^([A-Z]*\d+[A-Z0-9._/-]*)\s+(?:-\s+)?') { $codigoLocal = $matches[1].ToUpper() }
        if (-not $codigoLocal -and $Produto.PSObject.Properties['descricao'] -and [string]$Produto.descricao -match '^([A-Z]*\d+[A-Z0-9._/-]*)\s+(?:-\s+)?') { $codigoLocal = $matches[1].ToUpper() }
        if (-not $codigoLocal -and [string]$Produto.texto -match '^([A-Z]*\d+[A-Z0-9._/-]*)\s+(?:-\s+)?') { $codigoLocal = $matches[1].ToUpper() }
        return $codigoLocal
    }

    function Get-ProdutoQuantidadeDisplayLocal {
        param($Produto)
        if (-not $Produto -or -not $Produto.PSObject) { return '' }
        if ($Produto.PSObject.Properties['estoqueDisplay'] -and $Produto.estoqueDisplay) { return [string]$Produto.estoqueDisplay }
        if ($Produto.PSObject.Properties['estoque'] -and $Produto.estoque) { return (Format-ProdutoQuantidadeDisplay ([string]$Produto.estoque)) }
        if ([string]$Produto.texto -match '(?i)\|\s*un\s*(-?[\d.,]+)\s*$') { return (Format-ProdutoQuantidadeDisplay $matches[1]) }
        return ''
    }

    function Get-ProdutoQuantidadeOsDisplayLocal {
        param($Produto)
        $qtdBusca = Get-ProdutoQuantidadeDisplayLocal $Produto
        if ($qtdBusca) { return $qtdBusca }
        if ($Produto) { return '1,00' }
        return ''
    }

    function Remove-ProdutoQuantidadeTexto {
        param([string]$Texto)
        return (([string]$Texto) -replace '(?i)\s*\|\s*un\s*-?[\d.,]+\s*$', '').Trim()
    }

    function Test-ProdutoSelecionavel {
        param($Produto)
        if (-not $Produto) { return $false }
        if ([int]$Produto.idProduto -gt 0) { return $true }
        return ((Get-ProdutoCodigoLocal $Produto) -match '^[A-Z]')
    }

    function Update-ResumoOs {
        param($Produto)
        $servicosMarcados = @($servChecks | Where-Object { $_.Checked } | ForEach-Object { [string]$_.Text })
        $qtdSel = Get-ProdutoQuantidadeOsDisplayLocal $Produto
        $resumoValores['tecnico'].Text = [string]$cmbTec.SelectedItem
        $resumoValores['osAtual'].Text = (Format-OsCodigo -Numero $script:osNumero)
        $resumoValores['serial'].Text = [string]$txtSerialOs.Text
        $resumoValores['referencia'].Text = [string]$btnGradeOs.Text
        $resumoValores['quantidade'].Text = if ($qtdSel) { $qtdSel } else { '-' }
        $resumoValores['localizacao'].Text = 'Bancada tecnica'
        $resumoValores['produto'].Text = if ($Produto) { [string]$Produto.texto } else { '-' }
        $resumoValores['servicos'].Text = if ($servicosMarcados.Count -gt 0) { $servicosMarcados -join ', ' } else { 'nenhum' }
        if ($Produto) {
            $codigoResumo = Get-ProdutoCodigoLocal $Produto
            if ([int]$Produto.idProduto -gt 0) {
                $txtResumo.Text = "Produto pronto para criar OS. Codigo: $codigoResumo | ID: $([int]$Produto.idProduto)"
            } elseif ($codigoResumo -match '^[A-Z]') {
                $txtResumo.Text = "Produto sem ID na lista; o servidor vai resolver pelo codigo $codigoResumo ao criar."
            } else {
                $txtResumo.Text = 'Selecione um produto com codigo Altertag (P/A/T) ou com ID valido.'
            }
        }
    }

    function Get-ProdutoSortKeyLocal {
        param($Produto)
        $codigo = ''
        if ([string]$Produto.texto -match '^([A-Z]*\d+[A-Z0-9._/-]*)\s+(?:-\s+)?') { $codigo = $matches[1].ToUpper() }
        if ($codigo -match '^T') { return '0_' + $codigo }
        if ($codigo -match '^P') { return '1_' + $codigo }
        if ($codigo -match '^A') { return '2_' + $codigo }
        if ($codigo) { return '3_' + $codigo }
        return '9_' + ([string]$Produto.texto).ToUpper()
    }

    function Convert-ProdutoResponseToItems {
        param($Resp)

        $items = @()
        foreach ($p in @($Resp.produtos)) {
            $textoProduto = [string]$p.descricao
            if ($p.texto) { $textoProduto = [string]$p.texto }
            $partesProduto = @(Split-ProdutoOpcaoTexto -Texto $textoProduto)
            foreach ($parteProduto in $partesProduto) {
                $idParte = 0
                if ($partesProduto.Count -eq 1 -and $p.idProduto) { $idParte = [int]$p.idProduto }
                $qtdRaw = ''
                if ($p.estoque) { $qtdRaw = [string]$p.estoque } elseif ($p.quantidade) { $qtdRaw = [string]$p.quantidade }
                if (-not $qtdRaw -and [string]$parteProduto -match '(?i)\|\s*un\s*(-?[\d.,]+)\s*$') { $qtdRaw = $matches[1] }
                $qtdParte = Normalize-ProdutoQuantidade $qtdRaw
                $descricaoParte = [string]$parteProduto
                if ($partesProduto.Count -eq 1 -and $p.descricao) { $descricaoParte = [string]$p.descricao }
                $valorParte = '0.00'
                if ($p.valor) { $valorParte = [string]$p.valor }
                $textoLista = Remove-ProdutoQuantidadeTexto ([string]$parteProduto)
                $qtdDisplay = Format-ProdutoQuantidadeDisplay $qtdParte
                $codigoParte = ''
                if ([string]$parteProduto -match '^([A-Z]*\d+[A-Z0-9._/-]*)\s+(?:-\s+)?') {
                    $codigoParte = $matches[1].ToUpper()
                } elseif ($partesProduto.Count -eq 1) {
                    $codigoParte = Get-ProdutoCodigoLocal $p
                }
                $items += [pscustomobject]@{
                    texto = $textoLista
                    codigo = $codigoParte
                    idProduto = $idParte
                    descricao = $descricaoParte
                    valor = $valorParte
                    estoque = $qtdParte
                    estoqueDisplay = $qtdDisplay
                }
            }
        }
        if ($items.Count -eq 0) {
            foreach ($op in @($Resp.opcoes)) {
                foreach ($parteOpcao in @(Split-ProdutoOpcaoTexto -Texto ([string]$op))) {
                    $items += [pscustomobject]@{
                        texto = Remove-ProdutoQuantidadeTexto ([string]$parteOpcao)
                        codigo = ''
                        idProduto = 0
                        descricao = [string]$parteOpcao
                        valor = '0.00'
                        estoque = ''
                        estoqueDisplay = ''
                    }
                }
            }
        }
        $preferenciais = @($items | Where-Object { (Get-ProdutoCodigoLocal $_) -match '^[A-Z]' })
        if ($preferenciais.Count -gt 0) { $items = $preferenciais }
        return @($items | Sort-Object -Property @{ Expression = { Get-ProdutoSortKeyLocal $_ }; Descending = $false })
    }

    function Set-ProdutoItems {
        param(
            [object[]]$Items,
            [string]$Fonte = '',
            [string]$Mensagem = ''
        )

        $listProd.Items.Clear()
        foreach ($itemProd in @($Items)) { [void]$listProd.Items.Add($itemProd) }
        if ($listProd.Items.Count -gt 0) { $listProd.SelectedIndex = 0 }
        $scrollProd.Invalidate()
        $lblListaVazia.Visible = ($listProd.Items.Count -eq 0)
        if ($lblListaVazia.Visible) {
            $lblListaVazia.Text = 'Nenhum produto encontrado'
            $lblListaVazia.BringToFront()
        }
        $txtResumo.Text = "$(if ($Fonte) { "Fonte: $Fonte" } else { 'Fonte: aguardando' }) | Resultado(s): $($listProd.Items.Count)$(if ($Mensagem) { " | $Mensagem" } else { '' })"
    }

    $listProd.Add_DrawItem({
        param($sender, $e)
        if ($e.Index -lt 0) { return }
        $item = $sender.Items[$e.Index]
        $isSelected = (($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -eq [System.Windows.Forms.DrawItemState]::Selected)

        $back = if ($isSelected) {
            [System.Drawing.Color]::FromArgb(0, 88, 148)
        } elseif (($e.Index % 2) -eq 0) {
            [System.Drawing.Color]::FromArgb(9, 17, 28)
        } else {
            [System.Drawing.Color]::FromArgb(11, 22, 34)
        }

        $brush = New-Object System.Drawing.SolidBrush($back)
        $e.Graphics.FillRectangle($brush, $e.Bounds)
        $brush.Dispose()

        $textoItem  = [string]$item.texto
        $codigoItem = Get-ProdutoCodigoLocal $item
        if (-not $codigoItem -and $textoItem -match '^([A-Z]*\d+[A-Z0-9._/-]*)\s+(?:-\s+)?') { $codigoItem = $matches[1] }
        $descItem = $textoItem
        if ($codigoItem -and $descItem -match '^[A-Z]*\d+[A-Z0-9._/-]*\s+(?:-\s+)?(.+)$') { $descItem = $matches[1] }
        $qtdItem  = Get-ProdutoQuantidadeDisplayLocal $item
        $qtdTexto = if ($qtdItem) { $qtdItem } else { '-' }

        # Barra lateral colorida por tipo de codigo
        $tagColor = if ($codigoItem -match '^P') {
            [System.Drawing.Color]::FromArgb(0, 200, 120)
        } elseif ($codigoItem -match '^A') {
            [System.Drawing.Color]::FromArgb(100, 160, 255)
        } elseif ($codigoItem -match '^T') {
            [System.Drawing.Color]::FromArgb(255, 190, 70)
        } else {
            [System.Drawing.Color]::FromArgb(255, 140, 90)
        }
        $tagBrush = New-Object System.Drawing.SolidBrush($tagColor)
        $tagRect  = New-Object System.Drawing.Rectangle($e.Bounds.Left, $e.Bounds.Top, 3, $e.Bounds.Height)
        $e.Graphics.FillRectangle($tagBrush, $tagRect)
        $tagBrush.Dispose()

        # Codigo em badge arredondado
        $codeColor = if ($isSelected) { [System.Drawing.Color]::White } else { $tagColor }
        $codeRect  = New-Object System.Drawing.Rectangle(($e.Bounds.Left + 10), ($e.Bounds.Top + 5), 88, 18)
        if ($codigoItem) {
            $badgeBack = [System.Drawing.Color]::FromArgb(34, $tagColor.R, $tagColor.G, $tagColor.B)
            $badgeBrush = New-Object System.Drawing.SolidBrush($badgeBack)
            $badgeW = [Math]::Min(86, [int][System.Windows.Forms.TextRenderer]::MeasureText($codigoItem, (New-Object System.Drawing.Font('Segoe UI Semibold', 8.5, [System.Drawing.FontStyle]::Bold))).Width + 10)
            $badgeRect = New-Object System.Drawing.Rectangle(($e.Bounds.Left + 8), ($e.Bounds.Top + 4), $badgeW, 20)
            $e.Graphics.FillRectangle($badgeBrush, $badgeRect)
            $badgeBrush.Dispose()
            $codeRect = New-Object System.Drawing.Rectangle(($e.Bounds.Left + 13), ($e.Bounds.Top + 5), ($badgeW - 8), 18)
        }
        [System.Windows.Forms.TextRenderer]::DrawText(
            $e.Graphics, $codigoItem,
            (New-Object System.Drawing.Font('Segoe UI Semibold', 8.5, [System.Drawing.FontStyle]::Bold)),
            $codeRect, $codeColor,
            ([System.Windows.Forms.TextFormatFlags]::Left -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis)
        )

        # Descricao
        $fore = if ($isSelected) { [System.Drawing.Color]::White } else { [System.Drawing.Color]::FromArgb(210, 230, 248) }
        $textRect = New-Object System.Drawing.Rectangle(($e.Bounds.Left + 108), ($e.Bounds.Top + 5), 348, 18)
        [System.Windows.Forms.TextRenderer]::DrawText(
            $e.Graphics, $descItem, $listProd.Font, $textRect, $fore,
            ([System.Windows.Forms.TextFormatFlags]::Left -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis)
        )

        # Estoque: verde quando ha unidades, apagado quando zerado
        $temEstoque = ($qtdItem -and $qtdItem -notmatch '^[0.,\s-]*$')
        $qtyColor = if ($isSelected) {
            [System.Drawing.Color]::FromArgb(220, 244, 255)
        } elseif ($temEstoque) {
            [System.Drawing.Color]::FromArgb(90, 220, 150)
        } else {
            [System.Drawing.Color]::FromArgb(60, 100, 130)
        }
        $qtyFontStyle = if ($temEstoque) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
        $qtyRect = New-Object System.Drawing.Rectangle(($e.Bounds.Left + 464), ($e.Bounds.Top + 5), 88, 18)
        [System.Windows.Forms.TextRenderer]::DrawText(
            $e.Graphics, $qtdTexto,
            (New-Object System.Drawing.Font('Segoe UI', 8, $qtyFontStyle)),
            $qtyRect, $qtyColor,
            ([System.Windows.Forms.TextFormatFlags]::Right -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis)
        )

        # Linha separadora
        $linePen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(16, 36, 54))
        $e.Graphics.DrawLine($linePen, ($e.Bounds.Left + 4), ($e.Bounds.Bottom - 1), $e.Bounds.Right, ($e.Bounds.Bottom - 1))
        $linePen.Dispose()
    })

    $btnCriar = New-Object System.Windows.Forms.Button
    $btnCriar.Text = 'Criar OS  >'
    $btnCriar.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5, [System.Drawing.FontStyle]::Bold)
    $btnCriar.ForeColor = [System.Drawing.Color]::White
    $btnCriar.BackColor = [System.Drawing.Color]::FromArgb(16, 130, 78)
    $btnCriar.FlatStyle = 'Flat'
    $btnCriar.FlatAppearance.BorderSize = 0
    $btnCriar.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(22, 160, 96)
    $btnCriar.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(10, 100, 60)
    $btnCriar.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnCriar.Enabled = $false
    $btnCriar.Location = New-Object System.Drawing.Point(620, 582)
    $btnCriar.Size = New-Object System.Drawing.Size(200, 38)
    $dlg.Controls.Add($btnCriar)

    $script:cadastroOsProdutoBuscaClient = $null
    $script:cadastroOsProdutoBuscaClients = @()
    $script:cadastroOsProdutoBuscaTask = $null
    $script:cadastroOsProdutoBuscaTasks = @()
    $script:cadastroOsProdutoBuscaInicio = $null
    $script:cadastroOsProdutoBuscaTimer = New-Object System.Windows.Forms.Timer
    $script:cadastroOsProdutoBuscaTimer.Interval = 120
    $script:cadastroOsProdutoBuscaTimer.Add_Tick({
        $multiTasks = @($script:cadastroOsProdutoBuscaTasks)
        $isMultiBusca = ($multiTasks.Count -gt 0)
        if (-not $script:cadastroOsProdutoBuscaTask -and -not $isMultiBusca) {
            $script:cadastroOsProdutoBuscaTimer.Stop()
            return
        }
        $buscaCompleta = if ($isMultiBusca) {
            (@($multiTasks | Where-Object { -not $_.IsCompleted }).Count -eq 0)
        } else {
            $script:cadastroOsProdutoBuscaTask.IsCompleted
        }
        if (-not $buscaCompleta) {
            if ($script:cadastroOsProdutoBuscaInicio -and ((Get-Date) - $script:cadastroOsProdutoBuscaInicio).TotalSeconds -gt 10) {
                try { if ($script:cadastroOsProdutoBuscaClient) { $script:cadastroOsProdutoBuscaClient.CancelAsync() } } catch {}
                foreach ($clientBusca in @($script:cadastroOsProdutoBuscaClients)) {
                    try { if ($clientBusca) { $clientBusca.CancelAsync() } } catch {}
                }
                $lblListaVazia.Text = 'A busca demorou demais'
                $lblListaVazia.Visible = $true
                $lblListaVazia.BringToFront()
                $txtResumo.Text = "Falha na busca:`r`nO catalogo demorou demais para responder."
                $btnBuscaProd.Enabled = $true
                $btnBuscaProd.Text = 'Buscar'
                try { if ($script:cadastroOsProdutoBuscaClient) { $script:cadastroOsProdutoBuscaClient.Dispose() } } catch {}
                foreach ($clientBusca in @($script:cadastroOsProdutoBuscaClients)) {
                    try { if ($clientBusca) { $clientBusca.Dispose() } } catch {}
                }
                $script:cadastroOsProdutoBuscaClient = $null
                $script:cadastroOsProdutoBuscaClients = @()
                $script:cadastroOsProdutoBuscaTask = $null
                $script:cadastroOsProdutoBuscaTasks = @()
                $script:cadastroOsProdutoBuscaInicio = $null
                $script:cadastroOsProdutoBuscaTimer.Stop()
            }
            return
        }

        $script:cadastroOsProdutoBuscaTimer.Stop()
        try {
            if ($isMultiBusca) {
                $produtosBusca = @()
                $fontesBusca = @()
                $mensagensBusca = @()
                $errosBusca = @()
                foreach ($taskBusca in $multiTasks) {
                    if ($taskBusca.IsFaulted) {
                        $errosBusca += $taskBusca.Exception.GetBaseException().Message
                        continue
                    }
                    if ($taskBusca.IsCanceled) {
                        $errosBusca += 'Busca cancelada por demora.'
                        continue
                    }
                    $respParcial = $taskBusca.Result | ConvertFrom-Json
                    if ($respParcial.status -and [string]$respParcial.status -ne 'ok') {
                        if ($respParcial.mensagem) { $errosBusca += [string]$respParcial.mensagem }
                        continue
                    }
                    $produtosBusca += @($respParcial.produtos)
                    if ($respParcial.fonte) { $fontesBusca += [string]$respParcial.fonte }
                    if ($respParcial.mensagem) { $mensagensBusca += [string]$respParcial.mensagem }
                }
                if ($produtosBusca.Count -gt 0) {
                    $resp = [pscustomobject]@{
                        status = 'ok'
                        produtos = @($produtosBusca)
                        opcoes = @($produtosBusca | ForEach-Object { [string]$_.texto })
                        fonte = (@($fontesBusca | Where-Object { $_ } | Select-Object -Unique) -join '+')
                        mensagem = (@($mensagensBusca | Where-Object { $_ } | Select-Object -Unique) -join ' | ')
                    }
                    $items = @(Convert-ProdutoResponseToItems -Resp $resp)
                    Set-ProdutoItems -Items $items -Fonte ([string]$resp.fonte) -Mensagem ([string]$resp.mensagem)
                } else {
                    $lblListaVazia.Text = 'Nenhum produto encontrado'
                    $lblListaVazia.Visible = $true
                    $lblListaVazia.BringToFront()
                    $txtResumo.Text = "Falha na busca:`r`n$(if ($errosBusca.Count -gt 0) { $errosBusca -join ' | ' } else { 'Nenhum produto encontrado.' })"
                }
            } elseif ($script:cadastroOsProdutoBuscaTask.IsFaulted) {
                $erroBusca = $script:cadastroOsProdutoBuscaTask.Exception.GetBaseException().Message
                $lblListaVazia.Text = 'Falha na busca. Tente novamente.'
                $lblListaVazia.Visible = $true
                $lblListaVazia.BringToFront()
                $txtResumo.Text = "Falha na busca:`r`n$erroBusca"
            } elseif ($script:cadastroOsProdutoBuscaTask.IsCanceled) {
                $lblListaVazia.Text = 'Busca cancelada por demora'
                $lblListaVazia.Visible = $true
                $lblListaVazia.BringToFront()
                $txtResumo.Text = "Falha na busca:`r`nBusca cancelada por demora no catalogo."
            } else {
                $resp = $script:cadastroOsProdutoBuscaTask.Result | ConvertFrom-Json
                if ($resp.status -and [string]$resp.status -ne 'ok') {
                    $lblListaVazia.Text = 'Nenhum produto encontrado'
                    $lblListaVazia.Visible = $true
                    $lblListaVazia.BringToFront()
                    $txtResumo.Text = "Falha na busca:`r`n$([string]$resp.mensagem)"
                } else {
                    $items = @(Convert-ProdutoResponseToItems -Resp $resp)
                    Set-ProdutoItems -Items $items -Fonte ([string]$resp.fonte) -Mensagem ([string]$resp.mensagem)
                }
            }
        } catch {
            $lblListaVazia.Text = 'Falha na busca. Tente novamente.'
            $lblListaVazia.Visible = $true
            $lblListaVazia.BringToFront()
            $txtResumo.Text = "Falha na busca:`r`n$($_.Exception.Message)"
        } finally {
            $btnBuscaProd.Enabled = $true
            $btnBuscaProd.Text = 'Buscar'
            try { if ($script:cadastroOsProdutoBuscaClient) { $script:cadastroOsProdutoBuscaClient.Dispose() } } catch {}
            foreach ($clientBusca in @($script:cadastroOsProdutoBuscaClients)) {
                try { if ($clientBusca) { $clientBusca.Dispose() } } catch {}
            }
            $script:cadastroOsProdutoBuscaClient = $null
            $script:cadastroOsProdutoBuscaClients = @()
            $script:cadastroOsProdutoBuscaTask = $null
            $script:cadastroOsProdutoBuscaTasks = @()
            $script:cadastroOsProdutoBuscaInicio = $null
        }
    })

    $btnBuscaProd.Add_Click({
        $termo = $txtBuscaProd.Text.Trim()
        if ($termo.Length -lt 3) {
            $listProd.Items.Clear()
            $lblListaVazia.Text = 'Digite pelo menos 3 caracteres'
            $lblListaVazia.Visible = $true
            $lblListaVazia.BringToFront()
            $txtResumo.Text = 'Digite pelo menos 3 caracteres para buscar.'
            return
        }
        $multiEmAndamento = (@($script:cadastroOsProdutoBuscaTasks | Where-Object { $_ -and -not $_.IsCompleted }).Count -gt 0)
        if (($script:cadastroOsProdutoBuscaTask -and -not $script:cadastroOsProdutoBuscaTask.IsCompleted) -or $multiEmAndamento) {
            $txtResumo.Text = "Busca em andamento:`r`n$termo"
            return
        }
        $btnBuscaProd.Enabled = $false
        $btnBuscaProd.Text = 'Buscando...'
        try {
            $lblListaVazia.Visible = $false
            # Tenta catálogo local primeiro — retorna códigos Altertag precisos sem chamar API
            $itensLocais = @(Search-CatalogoProdutosLocal -Termo $termo)
            if ($itensLocais.Count -gt 0) {
                Set-ProdutoItems -Items $itensLocais -Fonte 'catalogo-local' -Mensagem ''
                $btnBuscaProd.Enabled = $true
                $btnBuscaProd.Text = 'Buscar'
                return
            }
            $termosServidor = @(Resolve-ProdutoBuscaTermosLocal -Termo $termo)
            $urlBuscaProd = '{0}/buscar-opcoes-altertag' -f (Get-ServidorBaseUrl)
            $txtResumo.Text = "Buscando produtos no catalogo:`r`n$termo$(if ($termosServidor.Count -gt 1) { " -> $($termosServidor -join ', ')" } elseif ($termosServidor[0] -ne $termo) { " -> $($termosServidor[0])" } else { '' })"
            $script:cadastroOsProdutoBuscaInicio = Get-Date
            if ($termosServidor.Count -gt 1) {
                $script:cadastroOsProdutoBuscaClients = @()
                $script:cadastroOsProdutoBuscaTasks = @()
                $script:cadastroOsProdutoBuscaClient = $null
                $script:cadastroOsProdutoBuscaTask = $null
                foreach ($termoBusca in @($termosServidor | Where-Object { $_ -and $_.Trim() } | Select-Object -Unique)) {
                    $payloadBusca = @{ tipo='produto'; termo=$termoBusca; modo='catalogo' } | ConvertTo-Json -Compress
                    $clientBusca = New-Object System.Net.WebClient
                    $clientBusca.Encoding = [System.Text.Encoding]::UTF8
                    $clientBusca.Headers[[System.Net.HttpRequestHeader]::ContentType] = 'application/json; charset=utf-8'
                    $script:cadastroOsProdutoBuscaClients += $clientBusca
                    $script:cadastroOsProdutoBuscaTasks += $clientBusca.UploadStringTaskAsync([Uri]$urlBuscaProd, 'POST', $payloadBusca)
                }
            } else {
                $payload = @{ tipo='produto'; termo=$termosServidor[0]; modo='catalogo' } | ConvertTo-Json -Compress
                $script:cadastroOsProdutoBuscaClient = New-Object System.Net.WebClient
                $script:cadastroOsProdutoBuscaClient.Encoding = [System.Text.Encoding]::UTF8
                $script:cadastroOsProdutoBuscaClient.Headers[[System.Net.HttpRequestHeader]::ContentType] = 'application/json; charset=utf-8'
                $script:cadastroOsProdutoBuscaTask = $script:cadastroOsProdutoBuscaClient.UploadStringTaskAsync([Uri]$urlBuscaProd, 'POST', $payload)
            }
            $script:cadastroOsProdutoBuscaTimer.Start()
        } catch {
            $lblListaVazia.Text = 'Falha na busca. Tente novamente.'
            $lblListaVazia.Visible = $true
            $lblListaVazia.BringToFront()
            $txtResumo.Text = "Falha na busca:`r`n$($_.Exception.Message)"
            $btnBuscaProd.Enabled = $true
            $btnBuscaProd.Text = 'Buscar'
            try { if ($script:cadastroOsProdutoBuscaClient) { $script:cadastroOsProdutoBuscaClient.Dispose() } } catch {}
            $script:cadastroOsProdutoBuscaClient = $null
            $script:cadastroOsProdutoBuscaTask = $null
            $script:cadastroOsProdutoBuscaInicio = $null
        }
    })

    $listProd.Add_SelectedIndexChanged({
        if ($listProd.SelectedItem) {
            $prodSel = $listProd.SelectedItem
            $btnCriar.Enabled = (Test-ProdutoSelecionavel $prodSel)
            Update-ResumoOs -Produto $prodSel
        }
    })

    foreach ($chkSvc in $servChecks) {
        $chkSvc.Add_CheckedChanged({
            Update-ResumoOs -Produto $listProd.SelectedItem
        })
    }

    # $cmbTec e PSCustomObject — atualizacao do resumo feita no Add_Click de cada botao toggle
    $txtSerialOs.Add_TextChanged({ Update-ResumoOs -Produto $listProd.SelectedItem })

    $btnFecharDlg = New-Object System.Windows.Forms.Button
    $btnFecharDlg.Text = 'Fechar'
    $btnFecharDlg.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $btnFecharDlg.ForeColor = [System.Drawing.Color]::FromArgb(200, 160, 165)
    $btnFecharDlg.BackColor = [System.Drawing.Color]::FromArgb(14, 20, 30)
    $btnFecharDlg.FlatStyle = 'Flat'
    $btnFecharDlg.FlatAppearance.BorderSize = 1
    $btnFecharDlg.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(84, 36, 46)
    $btnFecharDlg.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(52, 18, 26)
    $btnFecharDlg.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(70, 22, 32)
    $btnFecharDlg.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnFecharDlg.Location = New-Object System.Drawing.Point(20, 582)
    $btnFecharDlg.Size = New-Object System.Drawing.Size(150, 38)
    $btnFecharDlg.Add_Click({ $dlg.Close() })
    $dlg.Controls.Add($btnFecharDlg)

    $btnCriar.Add_Click({
        if (-not $listProd.SelectedItem) { return }
        $prodSel = $listProd.SelectedItem
        $codigoProdutoSel = Get-ProdutoCodigoLocal $prodSel
        if (-not (Test-ProdutoSelecionavel $prodSel)) {
            [System.Windows.Forms.MessageBox]::Show('Selecione um produto com codigo Altertag (P/A/T) ou retornado com ID pela API antes de criar a OS.', 'Cadastrar OS', 'OK', 'Warning') | Out-Null
            return
        }
        if (-not $txtSerialOs.Text.Trim()) {
            [System.Windows.Forms.MessageBox]::Show('Informe o serial antes de criar a OS.', 'Cadastrar OS', 'OK', 'Warning') | Out-Null
            return
        }
        $servicosMarcados = @($servChecks | Where-Object { $_.Checked } | ForEach-Object { [string]$_.Text })
        $qtdSel = Get-ProdutoQuantidadeOsDisplayLocal $prodSel
        $confirm = Show-CadastroOsConfirm `
            -Owner $dlg `
            -OsCodigo (Format-OsCodigo -Numero $script:osNumero) `
            -Produto ([string]$prodSel.texto) `
            -Quantidade $(if ($qtdSel) { $qtdSel } else { '1,00' }) `
            -Serial ($txtSerialOs.Text.Trim()) `
            -Referencia ($btnGradeOs.Text.Trim()) `
            -Servicos $(if ($servicosMarcados.Count -gt 0) { $servicosMarcados -join ', ' } else { 'nenhum' }) `
            -Localizacao 'Bancada tecnica'
        if (-not $confirm) { return }

        $btnCriar.Enabled = $false
        $btnCriar.Text = 'Criando...'
        [System.Windows.Forms.Application]::DoEvents()
        try {
            $payloadObj = @{
                tecnico = [string]$cmbTec.SelectedItem
                serial = $txtSerialOs.Text.Trim()
                referencia = $btnGradeOs.Text.Trim()
                idProduto = [int]$prodSel.idProduto
                produtoCodigo = $codigoProdutoSel
                produtoDescricao = [string]$prodSel.descricao
                produtoValor = [string]$prodSel.valor
                servicos = @($servicosMarcados)
            }
            $payload = $payloadObj | ConvertTo-Json -Depth 5 -Compress
            $resp = Invoke-RestMethod -Uri ('{0}/criar-os-altertag' -f (Get-ServidorBaseUrl)) -Method Post -Body $payload -ContentType 'application/json; charset=utf-8' -TimeoutSec 45 -ErrorAction Stop
            if ([string]$resp.status -ne 'ok') { throw [Exception]::new([string]$resp.mensagem) }
            Set-OsNumeroAtual -Numero ([int]$resp.osNumero) -Fonte 'altertag'
            $script:altertagOsAtual = [pscustomobject]@{
                idOrdem = [int]$resp.idOrdem
                numero = [int]$resp.osNumero
                osCodigo = [string]$resp.osCodigo
                cliente = [string]$resp.cliente
                tecnico = [string]$resp.tecnico
                statusOs = 'Em Aberto'
                equipamento = ''
                garantia = [string]$resp.garantia
                referencia = [string]$resp.referencia
            }
            $script:incluirOSAtual = $true
            Set-AppStatus -Texto "OS criada no Altertag: $($resp.osCodigo)" -Cor $cGreen
            Show-CadastroOsResult `
                -Owner $dlg `
                -OsCodigo ([string]$resp.osCodigo) `
                -ProdutoErro ([string]$resp.produtoErro) `
                -ServicosErro ([string]$resp.servicosErro)
            $dlg.Close()
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Falha ao criar OS:`n$($_.Exception.Message)", 'Cadastrar OS', 'OK', 'Error') | Out-Null
        } finally {
            $btnCriar.Enabled = ($listProd.SelectedItem -and (Test-ProdutoSelecionavel $listProd.SelectedItem))
            $btnCriar.Text = 'Criar OS  >'
        }
    })

    Update-ResumoOs -Produto $null

    $dlg.Add_Shown({
        $txtBuscaProd.Focus() | Out-Null
    })

    $dlg.Add_FormClosed({
        try { if ($script:cadastroOsProdutoBuscaTimer) { $script:cadastroOsProdutoBuscaTimer.Stop(); $script:cadastroOsProdutoBuscaTimer.Dispose() } } catch {}
        try { if ($script:cadastroOsProdutoBuscaClient) { $script:cadastroOsProdutoBuscaClient.CancelAsync(); $script:cadastroOsProdutoBuscaClient.Dispose() } } catch {}
        $script:cadastroOsProdutoBuscaClient = $null
        $script:cadastroOsProdutoBuscaTask = $null
        $script:cadastroOsProdutoBuscaInicio = $null
    })

    [void]$dlg.ShowDialog($form)
}

$btnOsAltertag.Add_Click({ Sync-OsFromAltertag })
$btnCadastrarOs.Add_Click({ Show-CadastroOsAltertagDraft })

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


$btnImprimir.Add_Click({
    $btnImprimir.Enabled = $false
    $reusarPreviaManual = [bool]$script:reabrindoPreviaManual
    $script:reabrindoPreviaManual = $false
    $impressaoConcluida = $false
    [System.Windows.Forms.Application]::DoEvents()

    # Prepara dados
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
                if ($primeirosDois -ge 10 -and $primeirosDois -le 19) {
                    $gen = $primeirosDois
                } elseif ($primeiro -ge 2 -and $primeiro -le 9) {
                    $gen = $primeiro
                }
            }
            if ($gen) { return "$prefix $gen" }
            return $prefix
        }
        return $t
    }
    $cpuCurto = Get-IntelCpuShort $info.CPU
    if (-not $cpuCurto -or $cpuCurto -eq $info.CPU) {
        if      ($cpuCurto -match '(?i)Ryzen\s+(\d)\s+(\d)\d{3}')    { $cpuCurto = 'Ryzen ' + $matches[1] + ' ' + $matches[2] + '000' }
        elseif  ($cpuCurto -match '(?i)(Celeron|Pentium)')            { $cpuCurto = $matches[1] }
    }
    function Get-RamShort {
        param([string]$Ram)
        $t = if ($Ram) { [string]$Ram.Trim() } else { '' }
        if (-not $t -or $t -match '^(?i:N/?A)$') { return 'N/A' }
        $cap = if ($t -match '(?i)\b(\d+)\s*GB\b') { "$($matches[1])GB" } else { ($t -split '\s+')[0] }
        $tipo = if ($t -match '(?i)\b(LPDDR[345]|DDR[345])\b') { $matches[1].ToUpper() } else { '' }
        if ($tipo) { return "$cap $tipo" }
        return $cap
    }
    $ramCurto   = Get-RamShort $info.RAM
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
    $script:IsGpuEtiquetaVisivel = {
        param([string]$Gpu)
        $g = if ($Gpu) { $Gpu.Trim() } else { '' }
        return ($g -ne '' -and $g -notmatch '^(?i:N/?A|Nao identificada|Não identificada)$')
    }
    $script:IsBateriaEtiquetaVisivel = {
        param([string]$Bateria)
        return ([bool]$info.MostrarBateria)
    }

    # ================================================
    # POPUP PREVIA DE IMPRESSAO
    # ================================================
    $popup = New-Object System.Windows.Forms.Form
    $popup.Text            = 'Previa de Impressao'
    $popup.AutoScaleMode   = [System.Windows.Forms.AutoScaleMode]::None
    $popup.ClientSize      = New-Object System.Drawing.Size(920, 660)
    $popup.StartPosition   = 'CenterScreen'
    $popup.BackColor       = [System.Drawing.Color]::FromArgb(5, 11, 19)
    $popup.FormBorderStyle = 'None'
    $popup.MaximizeBox     = $false
    $popup.MinimizeBox     = $false
    $popup.TopMost         = $true
    $popup.Font            = $fUI
    $popup.KeyPreview      = $true
    Set-DoubleBuffered $popup
    Set-RoundedControl -Control $popup -Radius 12
    $popup.Add_SizeChanged({ Set-RoundedControl -Control $this -Radius 12 })
    $popup.Add_Paint({
        param($s, $e)
        $border = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(31, 91, 126), 1)
        $e.Graphics.DrawRectangle($border, 0, 0, ($s.ClientSize.Width - 1), ($s.ClientSize.Height - 1))
        $border.Dispose()
    })

    $headerAccent = New-Object System.Windows.Forms.Panel
    $headerAccent.Location = New-Object System.Drawing.Point(0, 0)
    $headerAccent.Size = New-Object System.Drawing.Size(5, 72)
    $headerAccent.BackColor = $cAccent
    $popup.Controls.Add($headerAccent)

    $headerSurface = New-Object System.Windows.Forms.Panel
    $headerSurface.Location = New-Object System.Drawing.Point(5, 0)
    $headerSurface.Size = New-Object System.Drawing.Size(915, 72)
    $headerSurface.BackColor = [System.Drawing.Color]::FromArgb(8, 20, 32)
    $popup.Controls.Add($headerSurface)
    $headerSurface.Add_Paint({
        param($s, $e)
        $line = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(24, 185, 255), 2)
        $e.Graphics.DrawLine($line, 0, ($s.Height - 2), $s.Width, ($s.Height - 2))
        $line.Dispose()
    })

    $popEyebrow = New-Object System.Windows.Forms.Label
    $popEyebrow.Text = 'IMPRESSAO / ETIQUETA TERMICA'
    $popEyebrow.Font = New-Object System.Drawing.Font('Segoe UI', 6.8, [System.Drawing.FontStyle]::Bold)
    $popEyebrow.ForeColor = [System.Drawing.Color]::FromArgb(79, 185, 231)
    $popEyebrow.Location = New-Object System.Drawing.Point(19, 9)
    $popEyebrow.Size = New-Object System.Drawing.Size(260, 14)
    $headerSurface.Controls.Add($popEyebrow)

    $popTitle = New-Object System.Windows.Forms.Label
    $popTitle.Text = 'Previa de impressao'
    $popTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 15, [System.Drawing.FontStyle]::Bold)
    $popTitle.ForeColor = [System.Drawing.Color]::FromArgb(224, 244, 255)
    $popTitle.Location = New-Object System.Drawing.Point(17, 25)
    $popTitle.Size = New-Object System.Drawing.Size(310, 28)
    $headerSurface.Controls.Add($popTitle)

    $popSub = New-Object System.Windows.Forms.Label
    $popSub.Text = 'A imagem abaixo acompanha o layout enviado para a impressora'
    $popSub.Font = New-Object System.Drawing.Font('Segoe UI', 7.5)
    $popSub.ForeColor = $cMuted
    $popSub.Location = New-Object System.Drawing.Point(20, 52)
    $popSub.Size = New-Object System.Drawing.Size(410, 15)
    $headerSurface.Controls.Add($popSub)

    $popChip = New-Object System.Windows.Forms.Panel
    $popChip.Location = New-Object System.Drawing.Point(718, 21)
    $popChip.Size = New-Object System.Drawing.Size(142, 32)
    $popChip.BackColor = [System.Drawing.Color]::FromArgb(7, 42, 54)
    $popChip.BorderStyle = 'None'
    $headerSurface.Controls.Add($popChip)
    Set-RoundedControl -Control $popChip -Radius 8

    $popChipText = New-Object System.Windows.Forms.Label
    $popChipText.Text = '80 x 50 mm'
    $popChipText.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5, [System.Drawing.FontStyle]::Bold)
    $popChipText.ForeColor = [System.Drawing.Color]::FromArgb(132, 231, 255)
    $popChipText.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $popChipText.Location = New-Object System.Drawing.Point(0, 7)
    $popChipText.Size = New-Object System.Drawing.Size(142, 18)
    $popChip.Controls.Add($popChipText)

    $popClose = New-Object System.Windows.Forms.Button
    $popClose.Text = 'X'
    $popClose.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
    $popClose.ForeColor = [System.Drawing.Color]::FromArgb(124, 160, 188)
    $popClose.BackColor = $headerSurface.BackColor
    $popClose.FlatStyle = 'Flat'
    $popClose.FlatAppearance.BorderSize = 0
    $popClose.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(68, 24, 34)
    $popClose.Location = New-Object System.Drawing.Point(878, 8)
    $popClose.Size = New-Object System.Drawing.Size(28, 28)
    $popClose.Cursor = [System.Windows.Forms.Cursors]::Hand
    $popClose.Add_Click({ $popup.DialogResult = 'Cancel'; $popup.Close() })
    $headerSurface.Controls.Add($popClose)

    $previewBack = New-Object System.Windows.Forms.Panel
    $previewBack.Location = New-Object System.Drawing.Point(20, 88)
    $previewBack.Size = New-Object System.Drawing.Size(592, 376)
    $previewBack.BackColor = [System.Drawing.Color]::FromArgb(15, 27, 40)
    $previewBack.BorderStyle = 'None'
    $popup.Controls.Add($previewBack)
    Set-RoundedControl -Control $previewBack -Radius 8

    # Painel previa
    $prevPanel = New-Object System.Windows.Forms.Panel
    $prevPanel.Location = New-Object System.Drawing.Point(28, 96)
    $prevPanel.Size = New-Object System.Drawing.Size(576, 360)
    $prevPanel.BackColor = [System.Drawing.Color]::White
    $prevPanel.BorderStyle = 'None'
    $popup.Controls.Add($prevPanel)

    $previewBack.SendToBack()

    $controlDeck = New-Object System.Windows.Forms.Panel
    $controlDeck.Location = New-Object System.Drawing.Point(628, 88)
    $controlDeck.Size = New-Object System.Drawing.Size(272, 486)
    $controlDeck.BackColor = [System.Drawing.Color]::FromArgb(8, 18, 29)
    $popup.Controls.Add($controlDeck)
    Set-RoundedControl -Control $controlDeck -Radius 8
    $controlDeck.SendToBack()

    if (-not $reusarPreviaManual) {
        $script:gradeAtual = 'A'
        $script:obsAtual   = ''
        $script:incluirOSAtual = $false
        $script:triagemServicos = @()
        $script:osDefinidaPorTriagem = $false
        $script:modeloEtiqueta = $info.Modelo
        $script:serialEtiqueta = $info.Serial
        $script:cpuEtiqueta    = $cpuCurto
        $script:memEtiqueta    = $discoCurto
        $script:ramEtiqueta    = $ramCurto
        $script:gpuEtiqueta    = $gpuCurta
        $script:bateriaEtiqueta = if ($info.MostrarBateria) { $info.BatSaude } else { $null }
        $script:modoManualEtiqueta = $false
        $script:rnaAtivo = $false
        $script:rnaItensOk = @()
        $script:gradeAnteriorRma = 'A'
        $script:pinturaOpcaoAtual = ''
    }

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
        $scaleX = $prevPanel.ClientSize.Width / 640.0
        $scaleY = $prevPanel.ClientSize.Height / 400.0
        $f1 = New-Object System.Drawing.Font('Cascadia Mono', 5.8, [System.Drawing.FontStyle]::Bold)
        $f2 = New-Object System.Drawing.Font('Cascadia Mono', 7.2, [System.Drawing.FontStyle]::Bold)
        $f3 = New-Object System.Drawing.Font('Cascadia Mono', 9.4, [System.Drawing.FontStyle]::Bold)
        $f4 = New-Object System.Drawing.Font('Cascadia Mono', 13.2, [System.Drawing.FontStyle]::Bold)
        $preto = [System.Drawing.Color]::Black
        $cinza = [System.Drawing.Color]::FromArgb(72, 72, 72)
        $gradeEfetiva = if ($script:rnaAtivo) { 'RMA' } elseif ($grade) { [string]$grade } else { '' }

        function L($txt, $x, $y, $w, $h, $f, $fc) {
            $l = New-Object System.Windows.Forms.Label
            $l.Text = [string]$txt
            $l.Font = $f
            $l.ForeColor = $fc
            $l.Location = New-Object System.Drawing.Point(
                [int][math]::Round($x * $scaleX),
                [int][math]::Round($y * $scaleY)
            )
            $l.Size = New-Object System.Drawing.Size(
                [int][math]::Max(1, [math]::Round($w * $scaleX)),
                [int][math]::Max(1, [math]::Round($h * $scaleY))
            )
            $l.BackColor = [System.Drawing.Color]::Transparent
            $l.AutoEllipsis = $true
            [void]$prevPanel.Controls.Add($l)
        }

        function B($x, $y, $w, $h) {
            $b = New-Object System.Windows.Forms.Panel
            $b.BackColor = $preto
            $b.Location = New-Object System.Drawing.Point(
                [int][math]::Round($x * $scaleX),
                [int][math]::Round($y * $scaleY)
            )
            $b.Size = New-Object System.Drawing.Size(
                [int][math]::Max(1, [math]::Round($w * $scaleX)),
                [int][math]::Max(1, [math]::Round($h * $scaleY))
            )
            [void]$prevPanel.Controls.Add($b)
        }

        function BoxPreview($x1, $y1, $x2, $y2, $thickness) {
            B $x1 $y1 ($x2 - $x1) $thickness
            B $x1 ($y2 - $thickness) ($x2 - $x1) $thickness
            B $x1 $y1 $thickness ($y2 - $y1)
            B ($x2 - $thickness) $y1 $thickness ($y2 - $y1)
        }

        function Wrap-TextLines {
            param(
                [string]$Text,
                [int]$MaxLen = 46,
                [int]$MaxLines = 3
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
                if ($last.Length -gt $MaxLen) {
                    $cutLen = [math]::Min($last.Length, [math]::Max(0, $MaxLen - 3))
                    $lines[$MaxLines - 1] = $last.Substring(0, $cutLen) + '...'
                }
            }
            return @($lines)
        }

        # Replica o canvas TSPL 640x400 usado pela impressora 80x50mm.
        BoxPreview 2 4 638 398 2

        $modeloTxt = ([string]$script:modeloEtiqueta -replace '\s+', ' ').Trim()
        if ($modeloTxt.Length -le 16) {
            $modeloTop = $modeloTxt
            $modeloFont = $f4
            $modeloY = 22
        } elseif ($modeloTxt.Length -le 25) {
            $modeloTop = $modeloTxt
            $modeloFont = $f3
            $modeloY = 29
        } else {
            $modeloTop = if ($modeloTxt.Length -gt 42) { $modeloTxt.Substring(0, 42) } else { $modeloTxt }
            $modeloFont = $f2
            $modeloY = 29
        }
        BoxPreview 10 14 430 74 2
        L $modeloTop 24 $modeloY 394 38 $modeloFont $preto

        $gradeTxt = ''
        if ($gradeEfetiva) {
            $gradeTxt = if ($gradeEfetiva -eq 'RMA') {
                'RMA'
            } elseif ($gradeEfetiva -match '^C\s*-\s*PINTURA\s*([123])$') {
                "GRADE C - PINTURA $($matches[1])"
            } elseif ($gradeEfetiva -match '^T\s*-\s*TRIAGEM$') {
                'T - TRIAGEM'
            } else {
                [string]$gradeEfetiva
            }
            if ($gradeTxt.Length -gt 22) { $gradeTxt = $gradeTxt.Substring(0, 22) }
            BoxPreview 442 14 630 74 3
            if ($gradeTxt -match '^GRADE C') {
                L $gradeTxt 452 27 166 24 $f1 $preto
            } elseif ($gradeTxt.Length -le 3) {
                L $gradeTxt 508 23 92 38 $f4 $preto
            } else {
                L $gradeTxt 472 27 146 28 $f2 $preto
            }
        }

        $serialTop = ([string]$script:serialEtiqueta -replace '\s+', '').Trim()
        $serialBar = ($serialTop -replace '[^A-Za-z0-9]', '').ToUpper()
        if ($incluirOS) {
            if ($serialTop.Length -gt 15) { $serialTop = $serialTop.Substring(0, 15) }
            BoxPreview 10 84 410 154 3
            L $serialTop 28 89 368 34 $f4 $preto
            if ($serialBar.Length -ge 4) {
                $cx = 28
                $bk = $true
                foreach ($pw in @(3,2,1,2,4,1,2,3,1,2,4,2,1,3,2,1,4,2,1,3,1,2,4,1,2,3,1,2,1,3,2,1)) {
                    if ($bk) { B $cx 128 $pw 18 }
                    $cx += $pw
                    $bk = -not $bk
                }
            }
            BoxPreview 430 84 630 154 3
            L (Format-OsCodigo -Numero $script:osNumero) 454 98 162 38 $f4 $preto
        } else {
            if ($serialTop.Length -gt 22) { $serialTop = $serialTop.Substring(0, 22) }
            BoxPreview 10 84 630 154 3
            L $serialTop 28 89 580 34 $f4 $preto
            if ($serialBar.Length -ge 4) {
                $cx = 28
                $bk = $true
                foreach ($pw in @(3,2,1,2,4,1,2,3,1,2,4,2,1,3,2,1,4,2,1,3,1,2,4,1,2,3,1,2,1,3,2,1)) {
                    if ($bk) { B $cx 128 $pw 18 }
                    $cx += $pw
                    $bk = -not $bk
                }
            }
        }

        BoxPreview 10 166 630 384 2
        B 318 166 2 218
        B 10 194 620 2
        L 'CONFIGURACAO' 22 173 270 20 $f2 $preto
        L 'OBSERVACOES' 334 173 270 20 $f2 $preto

        $specRows = @(
            @('CPU', [string]$script:cpuEtiqueta),
            @('RAM', [string]$script:ramEtiqueta),
            @('DISCO', [string]$script:memEtiqueta),
            @('GPU', $(if (& $script:IsGpuEtiquetaVisivel $script:gpuEtiqueta) { [string]$script:gpuEtiqueta } else { 'N/A' })),
            @('BAT', $(if (& $script:IsBateriaEtiquetaVisivel $script:bateriaEtiqueta) { [string]$script:bateriaEtiqueta } else { 'N/A' }))
        )
        $specY = 204
        foreach ($row in $specRows) {
            $specValue = ([string]$row[1] -replace '\s+', ' ').Trim()
            if ($specValue.Length -gt 16) { $specValue = $specValue.Substring(0, 16) }
            L ([string]$row[0]) 22 $specY 48 16 $f1 $preto
            L $specValue 76 ($specY - 4) 222 24 $f2 $preto
            if ($specY -lt 332) { B 20 ($specY + 22) 282 1 }
            $specY += 32
        }

        $obsLines = @()
        if ($obs -and $obs.Trim()) {
            $obsLines = Wrap-TextLines -Text $obs.Trim() -MaxLen 19 -MaxLines 5
        }
        $obsY = 204
        foreach ($line in $obsLines) {
            L $line 336 $obsY 280 28 $f3 $preto
            $obsY += 30
        }

        $diasSemana = @('DOM','SEG','TER','QUA','QUI','SEX','SAB')
        $dataCurta = "$($diasSemana[[int](Get-Date).DayOfWeek]) $(Get-Date -Format 'dd/MM HH:mm')"
        L $dataCurta 438 354 178 23 $f2 $cinza

        $prevPanel.Refresh()
    }
    & $script:DesenharPrevia 'A' (& $script:GetObsImpressao) $script:incluirOSAtual

    # Grade — header com barra de destaque
    $gradeAccentBar = New-Object System.Windows.Forms.Panel
    $gradeAccentBar.BackColor = $cAccent
    $gradeAccentBar.Location  = New-Object System.Drawing.Point(644, 102)
    $gradeAccentBar.Size      = New-Object System.Drawing.Size(3, 18)
    $popup.Controls.Add($gradeAccentBar)

    $gradeLabel = New-Object System.Windows.Forms.Label
    $gradeLabel.Text = 'CLASSIFICACAO'
    $gradeLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5, [System.Drawing.FontStyle]::Bold)
    $gradeLabel.ForeColor = $cAccent
    $gradeLabel.Location = New-Object System.Drawing.Point(656, 101)
    $gradeLabel.Size = New-Object System.Drawing.Size(126, 20)
    $popup.Controls.Add($gradeLabel)
    $gradeHairline = New-SectionHairline -Parent $popup -X 788 -Y 111 -W 96

    $gradeIdleColor = [System.Drawing.Color]::FromArgb(13, 26, 40)
    $gradeHoverColor = [System.Drawing.Color]::FromArgb(23, 42, 60)
    $gradeDownColor = [System.Drawing.Color]::FromArgb(18, 34, 52)
    $coresGrade = @{
        'A' = [System.Drawing.Color]::FromArgb(18, 160, 92)
        'B' = [System.Drawing.Color]::FromArgb(214, 154, 36)
        'C' = [System.Drawing.Color]::FromArgb(232, 102, 34)
        'T' = [System.Drawing.Color]::FromArgb(39, 164, 186)
        'RMA' = [System.Drawing.Color]::FromArgb(208, 58, 82)
    }
    # Variacoes derivadas: fundo tintado (escuro na cor da grade) e texto claro na cor da grade
    $coresGradeIdle = @{}
    $coresGradeTexto = @{}
    $coresGradeBorda = @{}
    foreach ($kG in @($coresGrade.Keys)) {
        $cG = $coresGrade[$kG]
        $coresGradeIdle[$kG]  = [System.Drawing.Color]::FromArgb(([int]($cG.R * 0.13) + 8), ([int]($cG.G * 0.13) + 14), ([int]($cG.B * 0.13) + 22))
        $coresGradeTexto[$kG] = [System.Drawing.Color]::FromArgb([Math]::Min($cG.R + 120, 255), [Math]::Min($cG.G + 110, 255), [Math]::Min($cG.B + 110, 255))
        $coresGradeBorda[$kG] = [System.Drawing.Color]::FromArgb([int]($cG.R * 0.55), [int]($cG.G * 0.55), [int]($cG.B * 0.55))
    }
    $gradesInfo = @(
        @{L='A'; D='Perfeito'},
        @{L='B'; D='Detalhes'},
        @{L='C'; D='Pintura'},
        @{L='T'; D='Triagem'},
        @{L='RMA'; D='Defeitos'}
    )

    $script:SelecionarPintura = {
        $corPintura      = [System.Drawing.Color]::FromArgb(232, 102, 34)
        $corPinturaClara = [System.Drawing.Color]::FromArgb(255, 180, 120)

        $pForm = New-Object System.Windows.Forms.Form
        $pForm.Text = 'Grade C - Pintura'
        $pForm.Size = New-Object System.Drawing.Size(400, 330)
        $pForm.StartPosition = 'CenterParent'
        $pForm.BackColor = [System.Drawing.Color]::FromArgb(7, 15, 24)
        $pForm.FormBorderStyle = 'FixedDialog'
        $pForm.MaximizeBox = $false
        $pForm.MinimizeBox = $false

        # Header: barra de destaque + titulo + hairline
        $pAccent = New-Object System.Windows.Forms.Panel
        $pAccent.BackColor = $corPintura
        $pAccent.Location  = New-Object System.Drawing.Point(20, 18)
        $pAccent.Size      = New-Object System.Drawing.Size(3, 22)
        $pForm.Controls.Add($pAccent)

        $pTitle = New-Object System.Windows.Forms.Label
        $pTitle.Text = 'GRADE C - PINTURA'
        $pTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 11, [System.Drawing.FontStyle]::Bold)
        $pTitle.ForeColor = [System.Drawing.Color]::FromArgb(255, 180, 92)
        $pTitle.Location = New-Object System.Drawing.Point(30, 16)
        $pTitle.Size = New-Object System.Drawing.Size(190, 24)
        $pForm.Controls.Add($pTitle)
        [void](New-SectionHairline -Parent $pForm -X 226 -Y 29 -W 138 -Cor $corPintura)

        $pSub = New-Object System.Windows.Forms.Label
        $pSub.Text = 'Escolha o nivel de pintura que vai aparecer na etiqueta.'
        $pSub.Font = New-Object System.Drawing.Font('Segoe UI', 8)
        $pSub.ForeColor = $cMuted
        $pSub.Location = New-Object System.Drawing.Point(30, 42)
        $pSub.Size = New-Object System.Drawing.Size(334, 16)
        $pForm.Controls.Add($pSub)

        # Cards de opcao (estilo radio)
        $script:pinturaSelecionadaTemp = $null
        if ($script:pinturaOpcaoAtual) { $script:pinturaSelecionadaTemp = $script:pinturaOpcaoAtual }

        $script:pinturaCardsUi = @()
        $script:pinturaDescsUi = @{
            'PINTURA 1' = 'Retoque pontual'
            'PINTURA 2' = 'Pintura parcial'
            'PINTURA 3' = 'Pintura completa'
        }

        $script:AtualizarPinturaCards = {
            foreach ($card in @($script:pinturaCardsUi)) {
                $opcaoCard = [string]$card.Tag
                $selecionado = ($opcaoCard -eq [string]$script:pinturaSelecionadaTemp)
                if ($selecionado) {
                    $card.BackColor = [System.Drawing.Color]::FromArgb(64, 30, 12)
                    $card.ForeColor = [System.Drawing.Color]::White
                    $card.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(232, 102, 34)
                    $card.FlatAppearance.BorderSize = 2
                    $card.Text = ([string][char]0x25CF + '   ' + $opcaoCard + '   -   ' + $script:pinturaDescsUi[$opcaoCard])
                } else {
                    $card.BackColor = [System.Drawing.Color]::FromArgb(12, 22, 34)
                    $card.ForeColor = [System.Drawing.Color]::FromArgb(210, 190, 170)
                    $card.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(52, 40, 30)
                    $card.FlatAppearance.BorderSize = 1
                    $card.Text = ([string][char]0x25CB + '   ' + $opcaoCard + '   -   ' + $script:pinturaDescsUi[$opcaoCard])
                }
            }
            if ($script:pinturaConfirmBtn) {
                $temSel = [bool]$script:pinturaSelecionadaTemp
                $script:pinturaConfirmBtn.Enabled = $temSel
                $script:pinturaConfirmBtn.BackColor = if ($temSel) { [System.Drawing.Color]::FromArgb(0, 126, 72) } else { [System.Drawing.Color]::FromArgb(14, 34, 26) }
                $script:pinturaConfirmBtn.ForeColor = if ($temSel) { [System.Drawing.Color]::White } else { [System.Drawing.Color]::FromArgb(70, 110, 90) }
            }
        }

        $yCard = 68
        foreach ($opcaoPintura in @('PINTURA 1', 'PINTURA 2', 'PINTURA 3')) {
            $card = New-Object System.Windows.Forms.Button
            $card.Tag = $opcaoPintura
            $card.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9, [System.Drawing.FontStyle]::Bold)
            $card.FlatStyle = 'Flat'
            $card.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
            $card.Padding = New-Object System.Windows.Forms.Padding(12, 0, 0, 0)
            $card.Location = New-Object System.Drawing.Point(20, $yCard)
            $card.Size = New-Object System.Drawing.Size(344, 40)
            $card.Cursor = [System.Windows.Forms.Cursors]::Hand
            $card.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(34, 26, 18)
            $card.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(52, 28, 14)
            $card.Add_Click({
                param($s, $e)
                $script:pinturaSelecionadaTemp = [string]$s.Tag
                & $script:AtualizarPinturaCards
            })
            $pForm.Controls.Add($card)
            Set-RoundedControl -Control $card -Radius 10
            $script:pinturaCardsUi += $card
            $yCard += 46
        }

        # Rodape
        $pFooterLine = New-Object System.Windows.Forms.Panel
        $pFooterLine.BackColor = [System.Drawing.Color]::FromArgb(24, 40, 56)
        $pFooterLine.Location  = New-Object System.Drawing.Point(20, 216)
        $pFooterLine.Size      = New-Object System.Drawing.Size(344, 1)
        $pForm.Controls.Add($pFooterLine)

        $cancel = New-Object System.Windows.Forms.Button
        $cancel.Text = 'Cancelar'
        $cancel.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
        $cancel.ForeColor = [System.Drawing.Color]::FromArgb(200, 160, 165)
        $cancel.BackColor = [System.Drawing.Color]::FromArgb(14, 20, 30)
        $cancel.FlatStyle = 'Flat'
        $cancel.FlatAppearance.BorderSize = 1
        $cancel.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(84, 36, 46)
        $cancel.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(52, 18, 26)
        $cancel.Cursor = [System.Windows.Forms.Cursors]::Hand
        $cancel.Location = New-Object System.Drawing.Point(20, 230)
        $cancel.Size = New-Object System.Drawing.Size(112, 36)
        $cancel.Add_Click({
            $script:pinturaSelecionadaTemp = $null
            $pForm.Tag = 'Cancel'
            $pForm.Close()
        })
        $pForm.Controls.Add($cancel)
        Set-RoundedControl -Control $cancel -Radius 8

        $confirm = New-Object System.Windows.Forms.Button
        $confirm.Text = 'Confirmar  >'
        $confirm.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9, [System.Drawing.FontStyle]::Bold)
        $confirm.ForeColor = [System.Drawing.Color]::White
        $confirm.BackColor = [System.Drawing.Color]::FromArgb(0, 126, 72)
        $confirm.FlatStyle = 'Flat'
        $confirm.FlatAppearance.BorderSize = 0
        $confirm.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(0, 148, 84)
        $confirm.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(0, 104, 60)
        $confirm.Cursor = [System.Windows.Forms.Cursors]::Hand
        $confirm.Location = New-Object System.Drawing.Point(232, 230)
        $confirm.Size = New-Object System.Drawing.Size(132, 36)
        $confirm.Add_Click({
            if (-not $script:pinturaSelecionadaTemp) { return }
            $pForm.Tag = 'OK'
            $pForm.Close()
        })
        $pForm.Controls.Add($confirm)
        Set-RoundedControl -Control $confirm -Radius 8
        $script:pinturaConfirmBtn = $confirm

        & $script:AtualizarPinturaCards
        [void]$pForm.ShowDialog($popup)
        if ($pForm.Tag -eq 'OK' -and $script:pinturaSelecionadaTemp) {
            return [string]$script:pinturaSelecionadaTemp
        }
        return $null
    }

    $script:btnGrades = @{}
    $gradeIndex = 0
    foreach ($g in $gradesInfo) {
        $btnG = New-Object System.Windows.Forms.Button
        $btnG.Text = "$($g.L)`r`n$($g.D)"
        $btnG.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8, [System.Drawing.FontStyle]::Bold)
        $btnG.ForeColor = if ($g.L -eq 'A') { [System.Drawing.Color]::White } else { $coresGradeTexto[$g.L] }
        $btnG.BackColor = if ($g.L -eq 'A') { $coresGrade[$g.L] } else { $coresGradeIdle[$g.L] }
        $btnG.FlatStyle = 'Flat'
        $btnG.FlatAppearance.BorderColor = if ($g.L -eq 'A') { $coresGrade[$g.L] } else { $coresGradeBorda[$g.L] }
        $btnG.FlatAppearance.BorderSize  = if ($g.L -eq 'A') { 2 } else { 1 }
        $btnG.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        if ($g.L -eq 'RMA') {
            $btnG.Location = New-Object System.Drawing.Point(644, 238)
            $btnG.Size = New-Object System.Drawing.Size(240, 44)
        } else {
            $btnG.Location = New-Object System.Drawing.Point((644 + (($gradeIndex % 2) * 124)), (128 + ([math]::Floor($gradeIndex / 2) * 54)))
            $btnG.Size = New-Object System.Drawing.Size(116, 46)
        }
        $btnG.Tag      = $g.L
        $btnG.Cursor   = [System.Windows.Forms.Cursors]::Hand
        $btnG.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(([int]($coresGrade[$g.L].R * 0.24) + 8), ([int]($coresGrade[$g.L].G * 0.24) + 14), ([int]($coresGrade[$g.L].B * 0.24) + 22))
        $btnG.FlatAppearance.MouseDownBackColor = $gradeDownColor
        $origPos = $btnG.Location
        $btnG.Add_Click({
            $gradeBtn = $this
            $letraSel = [string]$gradeBtn.Tag
            if ($letraSel -eq 'RMA') {
                $chkRNA.Checked = -not $chkRNA.Checked
                & $script:UpdateRnaToggle
                return
            }
            if ($script:rnaAtivo) {
                $chkRNA.Checked = $false
            }
            if ($letraSel -eq 'C') {
                $pintura = & $script:SelecionarPintura
                if (-not $pintura) { return }
                $script:pinturaOpcaoAtual = $pintura
                $script:gradeAtual = "C - $pintura"
                Set-AppStatus -Texto "Grade C selecionada: $pintura" -Cor $cYellow
            } elseif ($letraSel -eq 'T') {
                $script:pinturaOpcaoAtual = ''
                $script:gradeAtual = 'T - TRIAGEM'
                Set-AppStatus -Texto 'Grade T selecionada: Triagem' -Cor $cAccent
            } else {
                $script:pinturaOpcaoAtual = ''
                $script:gradeAtual = $letraSel
            }
            & $script:AtualizarGradeState
            & $script:DesenharPrevia $script:gradeAtual (& $script:GetObsImpressao) $script:incluirOSAtual
            & $script:UpdateConfirmState
        })
        $btnG.Add_MouseEnter({
            $isSelected = (($this.Tag -eq $script:gradeAtual) -or ($this.Tag -eq 'C' -and ([string]$script:gradeAtual) -match '^C\s*-\s*PINTURA') -or ($this.Tag -eq 'T' -and ([string]$script:gradeAtual) -match '^T\s*-\s*TRIAGEM') -or ($this.Tag -eq 'RMA' -and $script:rnaAtivo))
            if (-not $isSelected) {
                $this.Location = New-Object System.Drawing.Point($origPos.X, ($origPos.Y - 1))
                $this.FlatAppearance.BorderSize = 2
            }
        }.GetNewClosure())
        $btnG.Add_MouseLeave({
            $isSelected = (($this.Tag -eq $script:gradeAtual) -or ($this.Tag -eq 'C' -and ([string]$script:gradeAtual) -match '^C\s*-\s*PINTURA') -or ($this.Tag -eq 'T' -and ([string]$script:gradeAtual) -match '^T\s*-\s*TRIAGEM') -or ($this.Tag -eq 'RMA' -and $script:rnaAtivo))
            if (-not $isSelected) {
                $this.Location = $origPos
                $this.FlatAppearance.BorderSize = 1
            }
        }.GetNewClosure())
        $script:btnGrades[$g.L] = $btnG
        $popup.Controls.Add($btnG)
        Set-RoundedControl -Control $btnG -Radius 10
        $gradeIndex++
    }

    $script:AtualizarGradeState = {
        $gradeLabel.Text = if ($script:rnaAtivo) { 'RMA ATIVO' } else { 'CLASSIFICACAO' }
        foreach ($key in $script:btnGrades.Keys) {
            $btn = $script:btnGrades[$key]
            if ($key -eq 'C') {
                $btn.Text = if ($script:pinturaOpcaoAtual) { "C`r`n$($script:pinturaOpcaoAtual)" } else { "C`r`nPintura" }
            } elseif ($key -eq 'T') {
                $btn.Text = "T`r`nTriagem"
            } elseif ($key -eq 'RMA') {
                $btn.Text = "RMA`r`nDefeitos"
            }
            if ($script:rnaAtivo) {
                $btn.Enabled = $true
                $btn.BackColor = $gradeIdleColor
                $btn.FlatAppearance.BorderSize = 1
                $btn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(30, 48, 66)
                $btn.ForeColor = [System.Drawing.Color]::FromArgb(120, 140, 160)
                if ($key -eq 'RMA') {
                    $btn.BackColor = $coresGrade['RMA']
                    $btn.FlatAppearance.BorderSize = 2
                    $btn.FlatAppearance.BorderColor = $coresGrade['RMA']
                    $btn.ForeColor = [System.Drawing.Color]::White
                }
            } elseif (($btn.Tag -eq $script:gradeAtual) -or ($btn.Tag -eq 'C' -and ([string]$script:gradeAtual) -match '^C\s*-\s*PINTURA') -or ($btn.Tag -eq 'T' -and ([string]$script:gradeAtual) -match '^T\s*-\s*TRIAGEM')) {
                $btn.Enabled = $true
                $btn.BackColor = $coresGrade[$key]
                $btn.FlatAppearance.BorderSize = 2
                $btn.FlatAppearance.BorderColor = $coresGrade[$key]
                $btn.ForeColor = [System.Drawing.Color]::White
            } else {
                $btn.Enabled = $true
                $btn.BackColor = $coresGradeIdle[$key]
                $btn.FlatAppearance.BorderSize = 1
                $btn.FlatAppearance.BorderColor = $coresGradeBorda[$key]
                $btn.ForeColor = $coresGradeTexto[$key]
            }
        }
    }
    & $script:AtualizarGradeState

    # Observacoes
    $obsPanel = New-Object System.Windows.Forms.Panel
    $obsPanel.Location = New-Object System.Drawing.Point(644, 298)
    $obsPanel.Size = New-Object System.Drawing.Size(240, 110)
    $obsPanel.BackColor = [System.Drawing.Color]::FromArgb(10, 23, 36)
    $obsPanel.BorderStyle = 'None'
    $popup.Controls.Add($obsPanel)
    Set-RoundedControl -Control $obsPanel -Radius 8

    $obsAccent = New-Object System.Windows.Forms.Panel
    $obsAccent.Location = New-Object System.Drawing.Point(0, 0)
    $obsAccent.Size = New-Object System.Drawing.Size(4, 110)
    $obsAccent.BackColor = $cAccent
    $obsPanel.Controls.Add($obsAccent)

    $obsLabel = New-Object System.Windows.Forms.Label
    $obsLabel.Text = 'OBSERVAÇÕES'
    $obsLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5, [System.Drawing.FontStyle]::Bold)
    $obsLabel.ForeColor = $cAccent
    $obsLabel.Location = New-Object System.Drawing.Point(14, 5)
    $obsLabel.Size = New-Object System.Drawing.Size(110, 16)
    $obsPanel.Controls.Add($obsLabel)
    [void](New-SectionHairline -Parent $obsPanel -X 120 -Y 13 -W 48)

    $obsCount = New-Object System.Windows.Forms.Label
    $obsCount.Text = '0/220'
    $obsCount.Font = New-Object System.Drawing.Font('Segoe UI', 7.5)
    $obsCount.ForeColor = $cDim
    $obsCount.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
    $obsCount.Location = New-Object System.Drawing.Point(174, 5)
    $obsCount.Size = New-Object System.Drawing.Size(52, 15)
    $obsPanel.Controls.Add($obsCount)

    $obsBox = New-Object System.Windows.Forms.TextBox
    $obsBox.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $obsBox.BackColor = [System.Drawing.Color]::FromArgb(10, 20, 32)
    $obsBox.ForeColor = [System.Drawing.Color]::FromArgb(214, 232, 246)
    $obsBox.BorderStyle = 'None'
    $obsBox.Location = New-Object System.Drawing.Point(14, 27)
    $obsBox.Size = New-Object System.Drawing.Size(212, 72)
    $obsBox.Multiline = $true
    $obsBox.ScrollBars = 'None'
    $obsBox.MaxLength = 220
    $obsBox.Cursor = [System.Windows.Forms.Cursors]::IBeam
    $obsBox.Text = if ($script:obsAtual) { [string]$script:obsAtual } else { '' }
    $obsCount.Text = "$($obsBox.Text.Length)/220"
    $obsBox.Add_Enter({ $obsAccent.BackColor = [System.Drawing.Color]::FromArgb(86, 213, 255) })
    $obsBox.Add_Leave({ $obsAccent.BackColor = $cAccent })
    $obsBox.Add_TextChanged({
        $script:obsAtual = $obsBox.Text
        $obsCount.Text = "$($obsBox.Text.Length)/220"
        $obsCount.ForeColor = if ($obsBox.Text.Length -ge 200) { $cYellow } else { $cDim }
        & $script:DesenharPrevia $script:gradeAtual (& $script:GetObsImpressao) $script:incluirOSAtual
        & $script:UpdateConfirmState
    })
    $obsPanel.Controls.Add($obsBox)

    $osCard = New-Object System.Windows.Forms.Panel
    $osCard.Location = New-Object System.Drawing.Point(644, 420)
    $osCard.Size = New-Object System.Drawing.Size(240, 52)
    $osCard.BackColor = $cCard
    $osCard.BorderStyle = 'None'
    $osCard.Cursor = [System.Windows.Forms.Cursors]::Hand
    $popup.Controls.Add($osCard)
    Set-RoundedControl -Control $osCard -Radius 8

    $osCardBar = New-Object System.Windows.Forms.Panel
    $osCardBar.Location = New-Object System.Drawing.Point(0, 0)
    $osCardBar.Size = New-Object System.Drawing.Size(4, 52)
    $osCardBar.BackColor = $cAccent
    $osCard.Controls.Add($osCardBar)

    $osCardTitle = New-Object System.Windows.Forms.Label
    $osCardTitle.Text = 'OS NA ETIQUETA'
    $osCardTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 7.5, [System.Drawing.FontStyle]::Bold)
    $osCardTitle.ForeColor = $cAccent
    $osCardTitle.Location = New-Object System.Drawing.Point(14, 7)
    $osCardTitle.Size = New-Object System.Drawing.Size(210, 16)
    $osCardTitle.Cursor = [System.Windows.Forms.Cursors]::Hand
    $osCard.Controls.Add($osCardTitle)

    $osCardDesc = New-Object System.Windows.Forms.Label
    $osCardDesc.Text = ''
    $osCardDesc.Font = New-Object System.Drawing.Font('Segoe UI', 7)
    $osCardDesc.ForeColor = $cMuted
    $osCardDesc.Location = New-Object System.Drawing.Point(14, 23)
    $osCardDesc.Size = New-Object System.Drawing.Size(280, 14)
    $osCardDesc.Visible = $false
    $osCard.Controls.Add($osCardDesc)

    $btnAlterarOsPreview = New-Object System.Windows.Forms.Button
    $btnAlterarOsPreview.Text = (Format-OsCodigo -Numero $script:osNumero)
    $btnAlterarOsPreview.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 7.5, [System.Drawing.FontStyle]::Bold)
    $btnAlterarOsPreview.ForeColor = [System.Drawing.Color]::FromArgb(162, 224, 255)
    $btnAlterarOsPreview.BackColor = [System.Drawing.Color]::FromArgb(11, 38, 56)
    $btnAlterarOsPreview.FlatStyle = 'Flat'
    $btnAlterarOsPreview.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(38, 104, 142)
    $btnAlterarOsPreview.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(17, 55, 78)
    $btnAlterarOsPreview.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnAlterarOsPreview.Location = New-Object System.Drawing.Point(14, 24)
    $btnAlterarOsPreview.Size = New-Object System.Drawing.Size(86, 22)
    $btnAlterarOsPreview.Add_Click({
        $popup.TopMost = $false
        Prompt-OsManual
        $popup.TopMost = $true
        $popup.Activate() | Out-Null
        $btnAlterarOsPreview.Text = (Format-OsCodigo -Numero $script:osNumero)
        $chkOS.Checked = $true
        & $script:UpdateOsToggle
        & $script:DesenharPrevia $script:gradeAtual (& $script:GetObsImpressao) $script:incluirOSAtual
    })
    $osCard.Controls.Add($btnAlterarOsPreview)
    Set-RoundedControl -Control $btnAlterarOsPreview -Radius 5
    $osPreviewTip = New-Object System.Windows.Forms.ToolTip
    $osPreviewTip.SetToolTip($btnAlterarOsPreview, 'Alterar o numero da OS')

    $chkOS = New-Object System.Windows.Forms.CheckBox
    $chkOS.Text = 'Ativo'
    $chkOS.Checked = [bool]$script:incluirOSAtual
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

    $osStatusPill = New-Object System.Windows.Forms.Panel
    $osStatusPill.Location = New-Object System.Drawing.Point(106, 24)
    $osStatusPill.Size = New-Object System.Drawing.Size(70, 22)
    $osStatusPill.BackColor = [System.Drawing.Color]::FromArgb(9, 64, 43)
    $osStatusPill.BorderStyle = 'None'
    $osCard.Controls.Add($osStatusPill)
    Set-RoundedControl -Control $osStatusPill -Radius 12

    $osStatusDot = New-Object System.Windows.Forms.Panel
    $osStatusDot.Location = New-Object System.Drawing.Point(8, 7)
    $osStatusDot.Size = New-Object System.Drawing.Size(8, 8)
    $osStatusDot.BackColor = [System.Drawing.Color]::FromArgb(128, 255, 206)
    $osStatusPill.Controls.Add($osStatusDot)
    Set-RoundedControl -Control $osStatusDot -Radius 4

    $osToggleTxt = New-Object System.Windows.Forms.Label
    $osToggleTxt.Text = 'ATIVO'
    $osToggleTxt.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 7.5, [System.Drawing.FontStyle]::Bold)
    $osToggleTxt.ForeColor = [System.Drawing.Color]::FromArgb(192, 255, 225)
    $osToggleTxt.Location = New-Object System.Drawing.Point(21, 3)
    $osToggleTxt.Size = New-Object System.Drawing.Size(42, 15)
    $osStatusPill.Controls.Add($osToggleTxt)

    $osToggleWrap = New-Object System.Windows.Forms.Panel
    $osToggleWrap.Location = New-Object System.Drawing.Point(182, 23)
    $osToggleWrap.Size = New-Object System.Drawing.Size(50, 24)
    $osToggleWrap.BackColor = [System.Drawing.Color]::FromArgb(12, 92, 58)
    $osToggleWrap.BorderStyle = 'None'
    $osToggleWrap.Cursor = [System.Windows.Forms.Cursors]::Hand
    $osCard.Controls.Add($osToggleWrap)
    Set-RoundedControl -Control $osToggleWrap -Radius 12

    $osToggleKnob = New-Object System.Windows.Forms.Panel
    $osToggleKnob.Size = New-Object System.Drawing.Size(18, 18)
    $osToggleKnob.Location = New-Object System.Drawing.Point(28, 3)
    $osToggleKnob.BackColor = [System.Drawing.Color]::FromArgb(216, 244, 255)
    $osToggleKnob.Cursor = [System.Windows.Forms.Cursors]::Hand
    $osToggleWrap.Controls.Add($osToggleKnob)
    Set-RoundedControl -Control $osToggleKnob -Radius 10

    $script:UpdateOsToggle = {
        if ($chkOS.Checked) {
            $osCardBar.BackColor = $cAccent
            $osStatusPill.BackColor = [System.Drawing.Color]::FromArgb(9, 64, 43)
            $osStatusDot.BackColor = [System.Drawing.Color]::FromArgb(128, 255, 206)
            $osToggleTxt.Text = 'ATIVO'
            $osToggleTxt.ForeColor = [System.Drawing.Color]::FromArgb(192, 255, 225)
            $osToggleWrap.BackColor = [System.Drawing.Color]::FromArgb(12, 92, 58)
            $osToggleKnob.Location = New-Object System.Drawing.Point(28, 3)
            $osToggleKnob.BackColor = [System.Drawing.Color]::FromArgb(222, 247, 255)
        } else {
            $osCardBar.BackColor = [System.Drawing.Color]::FromArgb(90, 110, 130)
            $osStatusPill.BackColor = [System.Drawing.Color]::FromArgb(36, 40, 48)
            $osStatusDot.BackColor = [System.Drawing.Color]::FromArgb(148, 158, 172)
            $osToggleTxt.Text = 'OFF'
            $osToggleTxt.ForeColor = [System.Drawing.Color]::FromArgb(198, 204, 214)
            $osToggleWrap.BackColor = [System.Drawing.Color]::FromArgb(50, 56, 66)
            $osToggleKnob.Location = New-Object System.Drawing.Point(4, 3)
            $osToggleKnob.BackColor = [System.Drawing.Color]::FromArgb(232, 236, 242)
        }
    }
    $toggleClick = { $chkOS.Checked = -not $chkOS.Checked; & $script:UpdateOsToggle }
    $osCard.Add_Click($toggleClick)
    $osCardTitle.Add_Click($toggleClick)
    $osToggleWrap.Add_Click($toggleClick)
    $osStatusPill.Add_Click($toggleClick)
    $osStatusDot.Add_Click($toggleClick)
    $osToggleTxt.Add_Click($toggleClick)
    $osToggleKnob.Add_Click($toggleClick)
    & $script:UpdateOsToggle

    # Card RMA (nao liga)
    $rnaCard = New-Object System.Windows.Forms.Panel
    $rnaCard.Location = New-Object System.Drawing.Point(16, 514)
    $rnaCard.Size = New-Object System.Drawing.Size(478, 36)
    $rnaCard.BackColor = [System.Drawing.Color]::FromArgb(16, 22, 34)
    $rnaCard.BorderStyle = 'None'
    $rnaCard.Cursor = [System.Windows.Forms.Cursors]::Hand
    $popup.Controls.Add($rnaCard)
    Set-RoundedControl -Control $rnaCard -Radius 8

    $rnaBar = New-Object System.Windows.Forms.Panel
    $rnaBar.Location = New-Object System.Drawing.Point(0, 0)
    $rnaBar.Size = New-Object System.Drawing.Size(5, 36)
    $rnaBar.BackColor = [System.Drawing.Color]::FromArgb(190, 105, 22)
    $rnaCard.Controls.Add($rnaBar)

    $rnaTitle = New-Object System.Windows.Forms.Label
    $rnaTitle.Text = 'RMA'
    $rnaTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5, [System.Drawing.FontStyle]::Bold)
    $rnaTitle.ForeColor = [System.Drawing.Color]::FromArgb(255, 212, 146)
    $rnaTitle.BackColor = [System.Drawing.Color]::Transparent
    $rnaTitle.Location = New-Object System.Drawing.Point(14, 8)
    $rnaTitle.Size = New-Object System.Drawing.Size(70, 20)
    $rnaTitle.Cursor = [System.Windows.Forms.Cursors]::Hand
    $rnaCard.Controls.Add($rnaTitle)

    $chkRNA = New-Object System.Windows.Forms.CheckBox
    $chkRNA.Checked = $false
    $chkRNA.Visible = $false
    $rnaCard.Controls.Add($chkRNA)

    $rnaResumoLbl = New-Object System.Windows.Forms.Label
    $rnaResumoLbl.Text = 'Nao liga / defeitos'
    $rnaResumoLbl.Font = New-Object System.Drawing.Font('Segoe UI', 7.5)
    $rnaResumoLbl.ForeColor = [System.Drawing.Color]::FromArgb(216, 190, 140)
    $rnaResumoLbl.Location = New-Object System.Drawing.Point(14, 27)
    $rnaResumoLbl.Size = New-Object System.Drawing.Size(280, 12)
    $rnaResumoLbl.Visible = $false
    $rnaResumoLbl.AutoEllipsis = $true
    $rnaResumoLbl.Anchor = 'Top,Left'
    $rnaResumoLbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $rnaCard.Controls.Add($rnaResumoLbl)

    $rnaStatusPill = New-Object System.Windows.Forms.Panel
    $rnaStatusPill.Location = New-Object System.Drawing.Point(304, 6)
    $rnaStatusPill.Size = New-Object System.Drawing.Size(78, 24)
    $rnaStatusPill.BackColor = [System.Drawing.Color]::FromArgb(44, 40, 34)
    $rnaStatusPill.BorderStyle = 'None'
    $rnaCard.Controls.Add($rnaStatusPill)
    Set-RoundedControl -Control $rnaStatusPill -Radius 12

    $rnaStatusDot = New-Object System.Windows.Forms.Panel
    $rnaStatusDot.Location = New-Object System.Drawing.Point(9, 8)
    $rnaStatusDot.Size = New-Object System.Drawing.Size(8, 8)
    $rnaStatusDot.BackColor = [System.Drawing.Color]::FromArgb(165, 152, 132)
    $rnaStatusPill.Controls.Add($rnaStatusDot)
    Set-RoundedControl -Control $rnaStatusDot -Radius 4

    $rnaToggleTxt = New-Object System.Windows.Forms.Label
    $rnaToggleTxt.Text = 'OFF'
    $rnaToggleTxt.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 7.5, [System.Drawing.FontStyle]::Bold)
    $rnaToggleTxt.ForeColor = [System.Drawing.Color]::FromArgb(210, 205, 198)
    $rnaToggleTxt.Location = New-Object System.Drawing.Point(22, 4)
    $rnaToggleTxt.Size = New-Object System.Drawing.Size(48, 15)
    $rnaStatusPill.Controls.Add($rnaToggleTxt)

    $rnaToggleWrap = New-Object System.Windows.Forms.Panel
    $rnaToggleWrap.Location = New-Object System.Drawing.Point(408, 6)
    $rnaToggleWrap.Size = New-Object System.Drawing.Size(50, 24)
    $rnaToggleWrap.BackColor = [System.Drawing.Color]::FromArgb(52, 48, 44)
    $rnaToggleWrap.BorderStyle = 'None'
    $rnaToggleWrap.Cursor = [System.Windows.Forms.Cursors]::Hand
    $rnaCard.Controls.Add($rnaToggleWrap)
    Set-RoundedControl -Control $rnaToggleWrap -Radius 12

    $rnaToggleKnob = New-Object System.Windows.Forms.Panel
    $rnaToggleKnob.Size = New-Object System.Drawing.Size(18, 18)
    $rnaToggleKnob.Location = New-Object System.Drawing.Point(4, 3)
    $rnaToggleKnob.BackColor = [System.Drawing.Color]::FromArgb(232, 236, 242)
    $rnaToggleKnob.Cursor = [System.Windows.Forms.Cursors]::Hand
    $rnaToggleWrap.Controls.Add($rnaToggleKnob)
    Set-RoundedControl -Control $rnaToggleKnob -Radius 10

    $script:UpdateRnaToggle = {
        if ($chkRNA.Checked) {
            $rnaStatusPill.BackColor = [System.Drawing.Color]::FromArgb(84, 58, 20)
            $rnaStatusDot.BackColor = [System.Drawing.Color]::FromArgb(255, 207, 112)
            $rnaToggleTxt.Text = 'ATIVO'
            $rnaToggleTxt.ForeColor = [System.Drawing.Color]::FromArgb(255, 230, 176)
            $rnaToggleWrap.BackColor = [System.Drawing.Color]::FromArgb(124, 82, 22)
            $rnaToggleKnob.Location = New-Object System.Drawing.Point(28, 3)
            $rnaToggleKnob.BackColor = [System.Drawing.Color]::FromArgb(255, 244, 228)
        } else {
            $rnaStatusPill.BackColor = [System.Drawing.Color]::FromArgb(44, 40, 34)
            $rnaStatusDot.BackColor = [System.Drawing.Color]::FromArgb(165, 152, 132)
            $rnaToggleTxt.Text = 'OFF'
            $rnaToggleTxt.ForeColor = [System.Drawing.Color]::FromArgb(210, 205, 198)
            $rnaToggleWrap.BackColor = [System.Drawing.Color]::FromArgb(52, 48, 44)
            $rnaToggleKnob.Location = New-Object System.Drawing.Point(4, 3)
            $rnaToggleKnob.BackColor = [System.Drawing.Color]::FromArgb(232, 236, 242)
        }
    }

    $script:AbrirRnaPopup = {
        $rnaForm = New-Object System.Windows.Forms.Form
        $rnaForm.Text = 'RMA - Defeitos identificados'
        $rnaForm.Size = New-Object System.Drawing.Size(520, 520)
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

        $opcoesRNA = @('Tela','Tampa frontal','Tampa traseira','Teclado','Touchpad','Carcaca','Dobradiças','Rede','USB','Camera','Gravador de voz')
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
        $btnNenhum.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 7.5, [System.Drawing.FontStyle]::Bold)
        $btnNenhum.ForeColor = [System.Drawing.Color]::FromArgb(214, 226, 240)
        $btnNenhum.BackColor = [System.Drawing.Color]::FromArgb(28, 36, 50)
        $btnNenhum.FlatStyle = 'Flat'
        $btnNenhum.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(66, 84, 108)
        $btnNenhum.Location = New-Object System.Drawing.Point(10, 4)
        $btnNenhum.Size = New-Object System.Drawing.Size(112, 24)
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
        $btnTodos.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 7.5, [System.Drawing.FontStyle]::Bold)
        $btnTodos.ForeColor = [System.Drawing.Color]::FromArgb(255, 226, 230)
        $btnTodos.BackColor = [System.Drawing.Color]::FromArgb(68, 22, 28)
        $btnTodos.FlatStyle = 'Flat'
        $btnTodos.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(126, 42, 52)
        $btnTodos.Location = New-Object System.Drawing.Point(128, 4)
        $btnTodos.Size = New-Object System.Drawing.Size(112, 24)
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
        $btnRnaCancel.Location = New-Object System.Drawing.Point(16, 448)
        $btnRnaCancel.Size = New-Object System.Drawing.Size(148, 34)
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
        $btnRnaSave.Location = New-Object System.Drawing.Point(356, 448)
        $btnRnaSave.Size = New-Object System.Drawing.Size(148, 34)
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
            $script:gradeAnteriorRma = if ([string]::IsNullOrWhiteSpace($script:gradeAtual)) { 'A' } else { $script:gradeAtual }
            $script:gradeAtual = ''
            & $script:AtualizarGradeState
            $resRna = & $script:AbrirRnaPopup
            if ($resRna -ne 'OK') {
                $script:rnaAtivo = $false
                $script:rnaItensOk = @()
                $chkRNA.Checked = $false
                $script:gradeAtual = if ([string]::IsNullOrWhiteSpace($script:gradeAnteriorRma)) { 'A' } else { $script:gradeAnteriorRma }
                & $script:AtualizarGradeState
                return
            }
        } else {
            $script:rnaAtivo = $false
            $script:rnaItensOk = @()
            $script:gradeAtual = if ([string]::IsNullOrWhiteSpace($script:gradeAnteriorRma)) { 'A' } else { $script:gradeAnteriorRma }
        }
        if ($script:rnaAtivo -and $script:rnaItensOk.Count -gt 0) {
            $rnaResumoLbl.Text = ($script:rnaItensOk -join ', ')
            if ($rnaResumoLbl.Text.Length -gt 22) { $rnaResumoLbl.Text = $rnaResumoLbl.Text.Substring(0,22) + '...' }
            $rnaResumoLbl.ForeColor = [System.Drawing.Color]::FromArgb(255, 214, 142)
        } elseif ($script:rnaAtivo) {
            $rnaResumoLbl.Text = 'Sem defeitos marcados'
            $rnaResumoLbl.ForeColor = [System.Drawing.Color]::FromArgb(255, 214, 142)
        } else {
            $rnaResumoLbl.Text = 'Nao liga / defeitos'
            $rnaResumoLbl.ForeColor = [System.Drawing.Color]::FromArgb(216, 190, 140)
        }
        & $script:AtualizarGradeState
        & $script:DesenharPrevia $script:gradeAtual (& $script:GetObsImpressao) $script:incluirOSAtual
        & $script:UpdateConfirmState
    })
    $rnaToggleClick = { $chkRNA.Checked = -not $chkRNA.Checked; & $script:UpdateRnaToggle }
    $rnaCard.Add_Click($rnaToggleClick)
    $rnaTitle.Add_Click($rnaToggleClick)
    $rnaToggleWrap.Add_Click($rnaToggleClick)
    $rnaStatusPill.Add_Click($rnaToggleClick)
    $rnaStatusDot.Add_Click($rnaToggleClick)
    $rnaToggleTxt.Add_Click($rnaToggleClick)
    $rnaToggleKnob.Add_Click($rnaToggleClick)
    & $script:UpdateRnaToggle
    $rnaCard.Visible = $false

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
    [void]$cmbTecnico.Items.Add('Hyrides')
    [void]$cmbTecnico.Items.Add('Vitor')
    [void]$cmbTecnico.Items.Add('Lucas')
    [void]$cmbTecnico.Items.Add('Erick')
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
        if ((Test-CaijGradeRequiresObs $script:gradeAtual) -and [string]::IsNullOrWhiteSpace($obsTexto)) {
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
            # Para produtos: tenta catálogo local primeiro
            if ($tipo -eq 'produto') {
                $itensLocaisBusca = @(Search-CatalogoProdutosLocal -Termo $termo)
                if ($itensLocaisBusca.Count -gt 0) {
                    $opcoes = @($itensLocaisBusca | ForEach-Object { [string]$_.texto })
                    if ($opcoes.Count -eq 0) { throw 'Nenhuma opcao encontrada no catalogo local.' }
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
                    $list2 = New-Object System.Windows.Forms.ListBox
                    $list2.Font = New-Object System.Drawing.Font('Segoe UI', 9)
                    $list2.BackColor = [System.Drawing.Color]::FromArgb(14, 24, 36)
                    $list2.ForeColor = [System.Drawing.Color]::White
                    $list2.Location = New-Object System.Drawing.Point(14, 14)
                    $list2.Size = New-Object System.Drawing.Size(516, 250)
                    foreach ($op2 in $opcoes) { [void]$list2.Items.Add([string]$op2) }
                    if ($list2.Items.Count -gt 0) { $list2.SelectedIndex = 0 }
                    $pick.Controls.Add($list2)
                    $pick.Add_Shown({ $pick.Activate() | Out-Null; $list2.Focus() | Out-Null })
                    $okPick2 = New-Object System.Windows.Forms.Button
                    $okPick2.Text = 'Usar selecionado'
                    $okPick2.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
                    $okPick2.ForeColor = [System.Drawing.Color]::White
                    $okPick2.BackColor = [System.Drawing.Color]::FromArgb(0, 112, 64)
                    $okPick2.FlatStyle = 'Flat'
                    $okPick2.Location = New-Object System.Drawing.Point(316, 276)
                    $okPick2.Size = New-Object System.Drawing.Size(214, 34)
                    $okPick2.Add_Click({ $pick.DialogResult = 'OK'; $pick.Close() })
                    $pick.Controls.Add($okPick2)
                    $cancelPick2 = New-Object System.Windows.Forms.Button
                    $cancelPick2.Text = 'Cancelar'
                    $cancelPick2.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
                    $cancelPick2.ForeColor = [System.Drawing.Color]::FromArgb(220, 120, 120)
                    $cancelPick2.BackColor = [System.Drawing.Color]::FromArgb(34, 12, 18)
                    $cancelPick2.FlatStyle = 'Flat'
                    $cancelPick2.Location = New-Object System.Drawing.Point(14, 276)
                    $cancelPick2.Size = New-Object System.Drawing.Size(140, 34)
                    $cancelPick2.Add_Click({ $pick.DialogResult = 'Cancel'; $pick.Close() })
                    $pick.Controls.Add($cancelPick2)
                    if ($pick.ShowDialog($popup) -eq 'OK' -and $list2.SelectedItem) {
                        $selecionado = [string]$list2.SelectedItem
                        $targetBox.Tag = $selecionado
                        $targetBox.Text = Extract-AltertagCodigo -Texto $selecionado
                    }
                    return
                }
            }
            $urlBusca = '{0}/buscar-opcoes-altertag' -f (Get-ServidorBaseUrl)
            $termosResolvidos = if ($tipo -eq 'produto') { @(Resolve-ProdutoBuscaTermosLocal -Termo $termo) } else { @($termo) }
            $opcoes = @()
            foreach ($termoBusca in @($termosResolvidos | Where-Object { $_ -and $_.Trim() } | Select-Object -Unique)) {
                $payloadObj = @{ tipo = $tipo; termo = $termoBusca }
                if ($tipo -eq 'produto') { $payloadObj.modo = 'catalogo' }
                $payload = $payloadObj | ConvertTo-Json -Compress
                try {
                    $respBusca = Invoke-RestMethod -Uri $urlBusca -Method Post -Body $payload -ContentType 'application/json; charset=utf-8' -TimeoutSec 25 -ErrorAction Stop
                    $opcoes += @($respBusca.opcoes)
                } catch { }
            }
            $opcoes = @($opcoes | Where-Object { $_ } | Select-Object -Unique)
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
    $btnCancelar.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5, [System.Drawing.FontStyle]::Bold)
    $btnCancelar.ForeColor = [System.Drawing.Color]::FromArgb(222, 118, 126)
    $btnCancelar.BackColor = [System.Drawing.Color]::FromArgb(28, 10, 16)
    $btnCancelar.FlatStyle = 'Flat'
    $btnCancelar.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(92, 28, 38)
    $btnCancelar.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(42, 14, 22)
    $btnCancelar.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnCancelar.Location = New-Object System.Drawing.Point(20, 608)
    $btnCancelar.Size = New-Object System.Drawing.Size(132, 36)
    $btnCancelar.Add_Click({ $popup.DialogResult = 'Cancel'; $popup.Close() })
    $popup.Controls.Add($btnCancelar)
    Set-RoundedControl -Control $btnCancelar -Radius 8

    $btnManual = New-Object System.Windows.Forms.Button
    $btnManual.Text = ([string][char]0x270E + '  Manual')
    $btnManual.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8, [System.Drawing.FontStyle]::Bold)
    $btnManual.ForeColor = [System.Drawing.Color]::FromArgb(150, 176, 198)
    $btnManual.BackColor = [System.Drawing.Color]::FromArgb(11, 22, 34)
    $btnManual.FlatStyle = 'Flat'
    $btnManual.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(34, 58, 82)
    $btnManual.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(20, 38, 56)
    $btnManual.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnManual.Location = New-Object System.Drawing.Point(796, 514)
    $btnManual.Size = New-Object System.Drawing.Size(88, 30)
    $btnManual.Add_Click({
        $manualForm = New-Object System.Windows.Forms.Form
        $manualForm.Text = 'Preencher dados manualmente'
        $manualForm.Size = New-Object System.Drawing.Size(440, 450)
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
            $txt.Size = New-Object System.Drawing.Size(282, 24)
            $txt.Text = $valor
            $manualForm.Controls.Add($txt)
            return $txt
        }

        function New-ManualQuickButton {
            param(
                [string]$texto,
                [int]$y,
                [System.Windows.Forms.TextBox]$target,
                [string]$valor
            )
            $btn = New-Object System.Windows.Forms.Button
            $btn.Text = $texto
            $btn.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 7.5, [System.Drawing.FontStyle]::Bold)
            $btn.ForeColor = [System.Drawing.Color]::FromArgb(210, 224, 238)
            $btn.BackColor = [System.Drawing.Color]::FromArgb(24, 38, 54)
            $btn.FlatStyle = 'Flat'
            $btn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(70, 105, 135)
            $btn.Location = New-Object System.Drawing.Point(306, ($y + 18))
            $btn.Size = New-Object System.Drawing.Size(102, 24)
            $btn.Tag = [pscustomobject]@{ Target = $target; Valor = $valor }
            $btn.Add_Click({ $this.Tag.Target.Text = $this.Tag.Valor })
            $manualForm.Controls.Add($btn)
            return $btn
        }

        $txtModelo = New-ManualField 'Nome do modelo' 12  $script:modeloEtiqueta
        $modeloAutoComplete = New-Object System.Windows.Forms.AutoCompleteStringCollection
        foreach ($modeloSalvo in @($script:modelosManuaisHistorico)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$modeloSalvo)) {
                [void]$modeloAutoComplete.Add([string]$modeloSalvo)
            }
        }
        $txtModelo.AutoCompleteMode = [System.Windows.Forms.AutoCompleteMode]::SuggestAppend
        $txtModelo.AutoCompleteSource = [System.Windows.Forms.AutoCompleteSource]::CustomSource
        $txtModelo.AutoCompleteCustomSource = $modeloAutoComplete
        $txtSerial = New-ManualField 'Serial'         62  $script:serialEtiqueta
        $txtCpu    = New-ManualField 'Processador'    112 $script:cpuEtiqueta
        $txtMem    = New-ManualField 'Memoria'        162 $script:memEtiqueta
        $txtRam    = New-ManualField 'RAM'            212 $script:ramEtiqueta
        $txtGpu    = New-ManualField 'GPU'            262 $script:gpuEtiqueta
        $txtBat    = $null
        if ($info.MostrarBateria) {
            $txtBat = New-ManualField 'Bateria'        312 $script:bateriaEtiqueta
        }

        New-ManualQuickButton 'Sem modelo' 12  $txtModelo 'N/A' | Out-Null
        New-ManualQuickButton 'Sem serial' 62  $txtSerial 'XXXXXX' | Out-Null
        New-ManualQuickButton 'Sem CPU'    112 $txtCpu    'N/A' | Out-Null
        New-ManualQuickButton 'Sem disco'  162 $txtMem    'N/A' | Out-Null
        New-ManualQuickButton 'Sem RAM'    212 $txtRam    'N/A' | Out-Null
        New-ManualQuickButton 'Sem GPU'    262 $txtGpu    '' | Out-Null
        if ($info.MostrarBateria) {
            New-ManualQuickButton 'Sem bateria' 312 $txtBat 'NA' | Out-Null
        }

        $btnManualCancelar = New-Object System.Windows.Forms.Button
        $btnManualCancelar.Text = 'Cancelar'
        $btnManualCancelar.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
        $btnManualCancelar.ForeColor = [System.Drawing.Color]::FromArgb(180, 60, 60)
        $btnManualCancelar.BackColor = [System.Drawing.Color]::FromArgb(20, 10, 12)
        $btnManualCancelar.FlatStyle = 'Flat'
        $btnManualCancelar.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(80, 30, 30)
        $btnManualCancelar.Location = New-Object System.Drawing.Point(16, 370)
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
        $btnManualSalvar.Location = New-Object System.Drawing.Point(286, 370)
        $btnManualSalvar.Size = New-Object System.Drawing.Size(122, 34)
        $btnManualSalvar.Add_Click({
            $modelo = $txtModelo.Text.Trim()
            $serial = $txtSerial.Text.Trim()
            $cpu    = $txtCpu.Text.Trim()
            $mem    = $txtMem.Text.Trim()
            $ram    = $txtRam.Text.Trim()
            $gpu    = $txtGpu.Text.Trim()
            $bat    = if ($info.MostrarBateria) { $txtBat.Text.Trim() } else { $null }
            if ([string]::IsNullOrWhiteSpace($modelo) -or
                [string]::IsNullOrWhiteSpace($serial) -or
                [string]::IsNullOrWhiteSpace($cpu) -or
                [string]::IsNullOrWhiteSpace($mem) -or
                [string]::IsNullOrWhiteSpace($ram) -or
                ($info.MostrarBateria -and [string]::IsNullOrWhiteSpace($bat))) {
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
            $script:gpuEtiqueta    = $gpu
            $script:bateriaEtiqueta = $bat
            $script:modoManualEtiqueta = $true
            Add-ModeloManualHistorico -Modelo $modelo
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
    Set-RoundedControl -Control $btnManual -Radius 14

    $btnAuto = New-Object System.Windows.Forms.Button
    $btnAuto.Text = ([string][char]0x21BB + '  Leitura automatica')
    $btnAuto.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8, [System.Drawing.FontStyle]::Bold)
    $btnAuto.ForeColor = [System.Drawing.Color]::FromArgb(190, 222, 246)
    $btnAuto.BackColor = [System.Drawing.Color]::FromArgb(13, 28, 44)
    $btnAuto.FlatStyle = 'Flat'
    $btnAuto.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(54, 96, 130)
    $btnAuto.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(18, 42, 64)
    $btnAuto.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnAuto.Location = New-Object System.Drawing.Point(644, 514)
    $btnAuto.Size = New-Object System.Drawing.Size(146, 30)
    $btnAuto.Add_Click({
        $script:modeloEtiqueta = $info.Modelo
        $script:serialEtiqueta = $info.Serial
        $script:cpuEtiqueta    = $cpuCurto
        $script:memEtiqueta    = $discoCurto
        $script:ramEtiqueta    = $ramCurto
        $script:gpuEtiqueta    = $gpuCurta
        $script:bateriaEtiqueta = if ($info.MostrarBateria) { $info.BatSaude } else { $null }
        $script:modoManualEtiqueta = $false
        & $script:DesenharPrevia $script:gradeAtual (& $script:GetObsImpressao) $script:incluirOSAtual
    })
    $popup.Controls.Add($btnAuto)
    Set-RoundedControl -Control $btnAuto -Radius 14

    # Caption da linha de fonte de dados
    $lblFonteDados = New-Object System.Windows.Forms.Label
    $lblFonteDados.Text      = 'FONTE DOS DADOS'
    $lblFonteDados.Font      = New-Object System.Drawing.Font('Segoe UI', 6.5, [System.Drawing.FontStyle]::Bold)
    $lblFonteDados.ForeColor = [System.Drawing.Color]::FromArgb(70, 105, 138)
    $lblFonteDados.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $lblFonteDados.Location  = New-Object System.Drawing.Point(644, 486)
    $lblFonteDados.Size      = New-Object System.Drawing.Size(240, 22)
    $popup.Controls.Add($lblFonteDados)

    # Divisor acima do rodape
    $footerDivider = New-Object System.Windows.Forms.Panel
    $footerDivider.BackColor = [System.Drawing.Color]::FromArgb(20, 42, 62)
    $footerDivider.Location  = New-Object System.Drawing.Point(20, 590)
    $footerDivider.Size      = New-Object System.Drawing.Size(880, 1)
    $popup.Controls.Add($footerDivider)

    # Estado visual do seletor de fonte (chip ativo acende)
    $script:UpdateFonteDados = {
        if ($script:modoManualEtiqueta) {
            $btnManual.ForeColor = [System.Drawing.Color]::FromArgb(255, 230, 170)
            $btnManual.BackColor = [System.Drawing.Color]::FromArgb(44, 32, 12)
            $btnManual.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(176, 122, 28)
            $btnAuto.ForeColor = [System.Drawing.Color]::FromArgb(150, 176, 198)
            $btnAuto.BackColor = [System.Drawing.Color]::FromArgb(11, 22, 34)
            $btnAuto.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(34, 58, 82)
        } else {
            $btnAuto.ForeColor = [System.Drawing.Color]::FromArgb(190, 222, 246)
            $btnAuto.BackColor = [System.Drawing.Color]::FromArgb(13, 38, 58)
            $btnAuto.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(0, 130, 190)
            $btnManual.ForeColor = [System.Drawing.Color]::FromArgb(150, 176, 198)
            $btnManual.BackColor = [System.Drawing.Color]::FromArgb(11, 22, 34)
            $btnManual.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(34, 58, 82)
        }
    }
    $btnAuto.Add_Click({ & $script:UpdateFonteDados })
    $btnManual.Add_Click({ & $script:UpdateFonteDados })
    & $script:UpdateFonteDados

    $btnConfirmar = New-Object System.Windows.Forms.Button
    $btnConfirmar.Text = 'Confirmar e Imprimir'
    $btnConfirmar.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5, [System.Drawing.FontStyle]::Bold)
    $btnConfirmar.ForeColor = [System.Drawing.Color]::White
    $btnConfirmar.BackColor = [System.Drawing.Color]::FromArgb(0, 126, 72)
    $btnConfirmar.FlatStyle = 'Flat'
    $btnConfirmar.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(24, 206, 126)
    $btnConfirmar.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(0, 148, 84)
    $btnConfirmar.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(0, 104, 60)
    $btnConfirmar.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnConfirmar.Location = New-Object System.Drawing.Point(738, 608)
    $btnConfirmar.Size = New-Object System.Drawing.Size(162, 36)
    $script:UpdateConfirmState = {
        $obsTextoSt = if ($script:obsAtual) { $script:obsAtual.Trim() } else { '' }
        $needsObs = Test-CaijGradeRequiresObs $script:gradeAtual
        if ($needsObs -and [string]::IsNullOrWhiteSpace($obsTextoSt)) {
            $btnConfirmar.Text = 'Falta OBS'
            $btnConfirmar.BackColor = [System.Drawing.Color]::FromArgb(95, 72, 12)
            $btnConfirmar.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(170, 128, 26)
        } else {
            $btnConfirmar.Text = 'Imprimir'
            $btnConfirmar.BackColor = [System.Drawing.Color]::FromArgb(0, 126, 72)
            $btnConfirmar.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(24, 206, 126)
        }
    }
    & $script:UpdateConfirmState
    $btnConfirmar.Add_Click({
        $btnConfirmar.Text = 'Validando...'
        [System.Windows.Forms.Application]::DoEvents()
        $obsTexto = if ($script:obsAtual) { $script:obsAtual.Trim() } else { '' }
        if ((Test-CaijGradeRequiresObs $script:gradeAtual) -and [string]::IsNullOrWhiteSpace($obsTexto)) {
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

    # O painel de fundo deve permanecer atras dos controles criados depois dele.
    $controlDeck.SendToBack()
    foreach ($previewControl in @(
        $gradeAccentBar,
        $gradeLabel,
        $gradeHairline,
        $obsPanel,
        $osCard,
        $lblFonteDados,
        $btnAuto,
        $btnManual
    )) {
        if ($previewControl) { $previewControl.BringToFront() }
    }
    foreach ($gradeControl in @($script:btnGrades.Values)) {
        if ($gradeControl) { $gradeControl.BringToFront() }
    }

    $resultado = $popup.ShowDialog()

    if ($resultado -ne 'OK') {
        $btnImprimir.Enabled = $true
        $btnImprimir.Text    = ([string][char]0x2399 + '  Imprimir Etiqueta via Rede')
        return
    }

    $btnImprimir.Text = 'Enviando...'
    Set-AppStatus -Texto 'Enviando etiqueta para o servidor...' -Cor $cAccent
    [System.Windows.Forms.Application]::DoEvents()

    # Monta JSON com dados + grade + obs
    if ($script:incluirOSAtual -and -not $script:osDefinidaPorTriagem -and -not $script:osDefinidaPorAltertag -and -not $script:osDefinidaManual) {
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
    } elseif ($script:incluirOSAtual -and $script:osDefinidaPorAltertag) {
        Set-AppStatus -Texto "OS Altertag confirmada para impressao: $(Format-OsCodigo -Numero $script:osNumero)" -Cor $cGreen
    }

    $dadosJson = @{
        os      = if ($script:incluirOSAtual) { $script:osNumero } else { $null }
        modelo  = $script:modeloEtiqueta
        serial  = $script:serialEtiqueta
        cpu     = $script:cpuEtiqueta
        gpu     = if (& $script:IsGpuEtiquetaVisivel $script:gpuEtiqueta) { $script:gpuEtiqueta } else { $null }
        ram     = $script:ramEtiqueta
        ramMods = $script:ramEtiqueta
        disco   = $script:memEtiqueta
        modoManual = [bool]$script:modoManualEtiqueta
        bateria = if (& $script:IsBateriaEtiquetaVisivel $script:bateriaEtiqueta) { $script:bateriaEtiqueta } else { $null }
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
        $impressaoConcluida = $true
        $btnImprimir.Text      = 'Etiqueta Enviada!'
        $btnImprimir.BackColor = [System.Drawing.Color]::FromArgb(0, 110, 50)
        Add-HistoricoNotebook -Acao 'impressao' -Status 'ok' -Mensagem 'Etiqueta enviada com sucesso' -Grade $script:gradeAtual -Obs $script:obsAtual
        $statusOsRegistrado = Register-OsAltertagStatusImpressao -Grade $script:gradeAtual -Obs $script:obsAtual
        if ($script:incluirOSAtual) { Sync-OsFromAltertag -Silent }
        if ($statusOsRegistrado) {
            Set-AppStatus -Texto "Impresso | status registrado na OS $(Format-OsCodigo -Numero $script:osNumero)" -Cor $cGreen
        } else {
            Set-AppStatus -Texto "Impresso | historico salvo | OS $(Format-OsCodigo -Numero $script:osNumero)" -Cor $cGreen
        }
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
                    "Servidor de impressao nao encontrado ou sem resposta.`nVerifique se o ServidorImpressao.ps1 esta rodando no PC principal (192.168.15.127).",
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
        $btnImprimir.Text      = ([string][char]0x2399 + '  Imprimir Etiqueta via Rede')
        $btnImprimir.BackColor = [System.Drawing.Color]::FromArgb(8, 44, 70)
        $this.Stop()
        $this.Dispose()
    })
    $resetImpTimer.Start()

    if ($impressaoConcluida -and $script:modoManualEtiqueta) {
        $script:reabrindoPreviaManual = $true
        if ($script:reabrirPreviaTimer) {
            try { $script:reabrirPreviaTimer.Stop(); $script:reabrirPreviaTimer.Dispose() } catch {}
        }
        $script:reabrirPreviaTimer = New-Object System.Windows.Forms.Timer
        $script:reabrirPreviaTimer.Interval = 250
        $script:reabrirPreviaTimer.Add_Tick({
            $this.Stop()
            $this.Dispose()
            $script:reabrirPreviaTimer = $null
            $btnImprimir.PerformClick()
        })
        $script:reabrirPreviaTimer.Start()
    }
})
# ================================================
# BARRA INFERIOR
# ================================================
$botY = $actY + 82

$botBar = New-Object System.Windows.Forms.Panel
$botBar.BackColor = [System.Drawing.Color]::FromArgb(4, 9, 16)
$botBar.Location  = New-Object System.Drawing.Point(0, $botY)
$botBar.Size      = New-Object System.Drawing.Size($W, 32)
$form.Controls.Add($botBar)

$botBar.Add_Paint({
    param($s, $e)
    # Linha superior com gradiente cyan que desvanece nas pontas
    $gradRect = New-Object System.Drawing.Rectangle(0, 0, $s.Width, 1)
    $gradBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $gradRect,
        [System.Drawing.Color]::FromArgb(0, 0, 168, 232),
        [System.Drawing.Color]::FromArgb(0, 0, 168, 232),
        [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal
    )
    $blend = New-Object System.Drawing.Drawing2D.ColorBlend(3)
    $blend.Colors = @(
        [System.Drawing.Color]::FromArgb(16, 38, 58),
        [System.Drawing.Color]::FromArgb(0, 140, 200),
        [System.Drawing.Color]::FromArgb(16, 38, 58)
    )
    $blend.Positions = @([single]0.0, [single]0.5, [single]1.0)
    $gradBrush.InterpolationColors = $blend
    $e.Graphics.FillRectangle($gradBrush, $gradRect)
    $gradBrush.Dispose()
})

# Dot de status (circulo renderizado via Paint)
$script:botDot = New-Object System.Windows.Forms.Panel
$script:botDot.BackColor = [System.Drawing.Color]::Transparent
$script:botDot.Location  = New-Object System.Drawing.Point(14, 12)
$script:botDot.Size      = New-Object System.Drawing.Size(8, 8)
$script:botDot.Add_Paint({
    param($s, $e)
    $e.Graphics.SmoothingMode = 'AntiAlias'
    $dotClr = if ($script:botDotColor) { $script:botDotColor } else { $cYellow }
    $b = New-Object System.Drawing.SolidBrush($dotClr)
    $e.Graphics.FillEllipse($b, 0, 0, 7, 7)
    $b.Dispose()
})
$botBar.Controls.Add($script:botDot)

$script:botTxt = New-Object System.Windows.Forms.Label
$script:botTxt.Text      = 'VERIFICANDO SERVIDOR E OS...'
$script:botTxt.Font      = New-Object System.Drawing.Font('Segoe UI', 7.5)
$script:botTxt.ForeColor = [System.Drawing.Color]::FromArgb(110, 152, 188)
$script:botTxt.Location  = New-Object System.Drawing.Point(28, 9)
$script:botTxt.Size      = New-Object System.Drawing.Size(546, 14)
$botBar.Controls.Add($script:botTxt)

# Badge versao (direita)
$botVerBadge = New-Object System.Windows.Forms.Panel
$botVerBadge.BackColor   = [System.Drawing.Color]::FromArgb(10, 24, 38)
$botVerBadge.Location    = New-Object System.Drawing.Point(588, 7)
$botVerBadge.Size        = New-Object System.Drawing.Size(88, 18)
$botVerBadge.BorderStyle = 'None'
$botBar.Controls.Add($botVerBadge)
$botVerBadge.Add_Paint({
    param($s, $e)
    $e.Graphics.SmoothingMode = 'AntiAlias'
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $r9 = 9; $w9 = $s.Width; $h9 = $s.Height
    $path.AddArc(0, 0, $r9*2, $r9*2, 180, 90)
    $path.AddArc($w9-$r9*2, 0, $r9*2, $r9*2, 270, 90)
    $path.AddArc($w9-$r9*2, $h9-$r9*2, $r9*2, $r9*2, 0, 90)
    $path.AddArc(0, $h9-$r9*2, $r9*2, $r9*2, 90, 90)
    $path.CloseFigure()
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(28, 58, 84), 1)
    $e.Graphics.DrawPath($pen, $path)
    $pen.Dispose(); $path.Dispose()
})

$botVer = New-Object System.Windows.Forms.Label
$botVer.Text      = 'v4.1'
$botVer.Font      = New-Object System.Drawing.Font('Segoe UI', 7.5, [System.Drawing.FontStyle]::Bold)
$botVer.ForeColor = [System.Drawing.Color]::FromArgb(60, 110, 155)
$botVer.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$botVer.Location  = New-Object System.Drawing.Point(0, 2)
$botVer.Size      = New-Object System.Drawing.Size(88, 14)
$botVerBadge.Controls.Add($botVer)

# Botao "Configurar servidor" — aparece so quando ha falha de conexao
$script:btnConfigurarSrv = New-Object System.Windows.Forms.Button
$script:btnConfigurarSrv.Text = 'Configurar servidor'
$script:btnConfigurarSrv.Font = New-Object System.Drawing.Font('Segoe UI', 7.5, [System.Drawing.FontStyle]::Bold)
$script:btnConfigurarSrv.ForeColor = [System.Drawing.Color]::FromArgb(255, 196, 60)
$script:btnConfigurarSrv.BackColor = [System.Drawing.Color]::FromArgb(44, 30, 4)
$script:btnConfigurarSrv.FlatStyle = 'Flat'
$script:btnConfigurarSrv.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(120, 80, 10)
$script:btnConfigurarSrv.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(64, 44, 6)
$script:btnConfigurarSrv.Location = New-Object System.Drawing.Point(470, 6)
$script:btnConfigurarSrv.Size = New-Object System.Drawing.Size(126, 20)
$script:btnConfigurarSrv.Cursor = [System.Windows.Forms.Cursors]::Hand
$script:btnConfigurarSrv.Visible = $false
$botBar.Controls.Add($script:btnConfigurarSrv)
$script:btnConfigurarSrv.Add_Click({ Show-DialogConfigurarServidor })

# Variavel auxiliar para cor do dot
$script:botDotColor = $cYellow
# Manter compatibilidade: botStatusPill ficticio para Set-AppStatus nao quebrar
$script:botStatusPill = $botBar

$script:osAlertPanel = New-Object System.Windows.Forms.Panel
$script:osAlertPanel.BackColor = [System.Drawing.Color]::FromArgb(58, 42, 10)
$script:osAlertPanel.Location  = New-Object System.Drawing.Point(14, 4)
$script:osAlertPanel.Size      = New-Object System.Drawing.Size(658, 26)
$script:osAlertPanel.Visible   = $false
$botBar.Controls.Add($script:osAlertPanel)
Set-RoundedControl -Control $script:osAlertPanel -Radius 12
$script:osAlertPanel.BringToFront()

$script:osAlertDot = New-Object System.Windows.Forms.Label
$script:osAlertDot.BackColor = $cYellow
$script:osAlertDot.Location  = New-Object System.Drawing.Point(10, 10)
$script:osAlertDot.Size      = New-Object System.Drawing.Size(7, 7)
$script:osAlertPanel.Controls.Add($script:osAlertDot)

$script:osAlertText = New-Object System.Windows.Forms.Label
$script:osAlertText.Text      = ''
$script:osAlertText.Font      = New-Object System.Drawing.Font('Segoe UI', 7.5, [System.Drawing.FontStyle]::Bold)
$script:osAlertText.ForeColor = [System.Drawing.Color]::FromArgb(255, 238, 190)
$script:osAlertText.Location  = New-Object System.Drawing.Point(24, 5)
$script:osAlertText.Size      = New-Object System.Drawing.Size(360, 16)
$script:osAlertPanel.Controls.Add($script:osAlertText)

$script:btnUsarOsNova = New-Object System.Windows.Forms.Button
$script:btnUsarOsNova.Text = 'Usar'
$script:btnUsarOsNova.Font = New-Object System.Drawing.Font('Segoe UI', 7, [System.Drawing.FontStyle]::Bold)
$script:btnUsarOsNova.ForeColor = [System.Drawing.Color]::White
$script:btnUsarOsNova.BackColor = [System.Drawing.Color]::FromArgb(0, 116, 72)
$script:btnUsarOsNova.FlatStyle = 'Flat'
$script:btnUsarOsNova.FlatAppearance.BorderSize = 0
$script:btnUsarOsNova.Location = New-Object System.Drawing.Point(396, 3)
$script:btnUsarOsNova.Size = New-Object System.Drawing.Size(70, 20)
$script:osAlertPanel.Controls.Add($script:btnUsarOsNova)

$script:btnListaOsNova = New-Object System.Windows.Forms.Button
$script:btnListaOsNova.Text = 'Lista'
$script:btnListaOsNova.Font = New-Object System.Drawing.Font('Segoe UI', 7, [System.Drawing.FontStyle]::Bold)
$script:btnListaOsNova.ForeColor = [System.Drawing.Color]::White
$script:btnListaOsNova.BackColor = [System.Drawing.Color]::FromArgb(22, 74, 104)
$script:btnListaOsNova.FlatStyle = 'Flat'
$script:btnListaOsNova.FlatAppearance.BorderSize = 0
$script:btnListaOsNova.Location = New-Object System.Drawing.Point(472, 3)
$script:btnListaOsNova.Size = New-Object System.Drawing.Size(70, 20)
$script:osAlertPanel.Controls.Add($script:btnListaOsNova)

$script:btnIgnorarOsNova = New-Object System.Windows.Forms.Button
$script:btnIgnorarOsNova.Text = 'Ignorar'
$script:btnIgnorarOsNova.Font = New-Object System.Drawing.Font('Segoe UI', 7, [System.Drawing.FontStyle]::Bold)
$script:btnIgnorarOsNova.ForeColor = [System.Drawing.Color]::FromArgb(255, 230, 220)
$script:btnIgnorarOsNova.BackColor = [System.Drawing.Color]::FromArgb(76, 30, 28)
$script:btnIgnorarOsNova.FlatStyle = 'Flat'
$script:btnIgnorarOsNova.FlatAppearance.BorderSize = 0
$script:btnIgnorarOsNova.Location = New-Object System.Drawing.Point(548, 3)
$script:btnIgnorarOsNova.Size = New-Object System.Drawing.Size(84, 20)
$script:osAlertPanel.Controls.Add($script:btnIgnorarOsNova)

function Hide-NewOsAlert {
    if ($script:osAlertPanel) { $script:osAlertPanel.Visible = $false }
}

function Show-NewOsAlert {
    param($Os, [int]$NovasCount = 1)
    if (-not $Os -or -not $script:osAlertPanel) { return }
    $numero = [int]$Os.numero
    if ($numero -lt 1) { return }
    $script:alertaOsAtual = $Os
    $tec = ([string]$Os.tecnico).Trim()
    if (-not $tec) { $tec = 'tecnico nao informado' }
    $hora = ''
    try {
        if ($Os.dataCadastro) { $hora = ([datetime]::Parse([string]$Os.dataCadastro)).ToString('HH:mm:ss') }
    } catch {}
    if (-not $hora) { $hora = (Get-Date).ToString('HH:mm:ss') }
    $extra = if ($NovasCount -gt 1) { " (+$($NovasCount - 1) novas)" } else { '' }
    $script:osAlertText.Text = "OS $(Format-OsCodigo -Numero $numero) adicionada por $tec as $hora$extra"
    $script:osAlertPanel.Visible = $true
    $script:osAlertPanel.BringToFront()
}

$script:btnUsarOsNova.Add_Click({
    if (-not $script:alertaOsAtual) { return }
    Set-OsNumeroAtual -Numero ([int]$script:alertaOsAtual.numero) -Fonte 'altertag'
    Set-AppStatus -Texto "OS nova aplicada: $(Format-OsCodigo -Numero ([int]$script:alertaOsAtual.numero))" -Cor $cGreen
    Hide-NewOsAlert
})

$script:btnListaOsNova.Add_Click({
    Hide-NewOsAlert
    Sync-OsFromAltertag
})

$script:btnIgnorarOsNova.Add_Click({
    if ($script:alertaOsAtual -and $script:alertaOsAtual.numero) {
        $script:ultimoAlertaOsNumero = [int]$script:alertaOsAtual.numero
    }
    Hide-NewOsAlert
})

function Update-OsRecentesMonitor {
    param([switch]$PrimeiraLeitura)
    if ($script:osAlertMonitorBusy) { return }
    $script:osAlertMonitorBusy = $true
    try {
        $resp = Invoke-CaijServer -Path '/status-os' -Method GET -TimeoutSec 5 -Retries 1
        if ($resp -and [string]$resp.status -eq 'ok' -and $resp.ultimoConfirmado) {
            $maiorStatus = [int]$resp.ultimoConfirmado
            $anteriorConfirmado = [int]$script:ultimoConfirmadoServidor
            $script:ultimoConfirmadoServidor = $maiorStatus
            if ($resp.proximoDisponivel -and -not $script:osDefinidaPorAltertag -and -not $script:osDefinidaManual) {
                Set-OsNumeroAtual -Numero ([int]$resp.proximoDisponivel) -Fonte 'sync'
            }
            if ($PrimeiraLeitura -or $script:maiorOsVistaAltertag -lt 1) {
                $script:maiorOsVistaAltertag = $maiorStatus
                return
            }
            if ($maiorStatus -le $script:maiorOsVistaAltertag -and $maiorStatus -le $anteriorConfirmado) { return }
        }

        $resp = Invoke-CaijServer -Path '/os-recentes?limit=3' -Method GET -TimeoutSec 12 -Retries 1
        if (-not $resp -or [string]$resp.status -ne 'ok' -or -not $resp.ordens) { return }
        $ordens = @($resp.ordens | Where-Object { $_ -and $_.numero } | Sort-Object -Property numero -Descending)
        if (-not $ordens -or $ordens.Count -eq 0) { return }
        $maior = [int]$ordens[0].numero
        if ($PrimeiraLeitura -or $script:maiorOsVistaAltertag -lt 1) {
            $script:maiorOsVistaAltertag = $maior
            $script:ultimoConfirmadoServidor = $maior
            return
        }
        if ($maior -gt $script:maiorOsVistaAltertag -and $maior -gt $script:ultimoAlertaOsNumero) {
            $baseAnterior = [int]$script:maiorOsVistaAltertag
            $novas = @($ordens | Where-Object { [int]$_.numero -gt $baseAnterior })
            $script:maiorOsVistaAltertag = $maior
            $script:ultimoConfirmadoServidor = $maior
            Show-NewOsAlert -Os $ordens[0] -NovasCount $novas.Count
        } elseif ($maior -gt $script:maiorOsVistaAltertag) {
            $script:maiorOsVistaAltertag = $maior
            $script:ultimoConfirmadoServidor = $maior
        }
    } catch {
        # Monitor discreto: falhas ficam no status normal do servidor, sem interromper a bancada.
    } finally {
        $script:osAlertMonitorBusy = $false
    }
}

# ================================================
# TAMANHO FINAL
# ================================================
$form.ClientSize = New-Object System.Drawing.Size($W, ($botY + 34))

# Fecha splash e abre o form principal
& $script:UpdateSplashProgress 100 'Pronto!'
$splash.Close()
$splash.Dispose()

$form.Add_Shown({
    try {
        $script:startupTimer = New-Object System.Windows.Forms.Timer
        $script:startupTimer.Interval = 250
        $script:startupTimer.Add_Tick({
            $this.Stop()
            try {
                Test-ServidorPrincipal -Quiet | Out-Null
                Sync-OsFromAltertag -Silent
                Update-OsRecentesMonitor -PrimeiraLeitura
                $script:osRecentesTimer = New-Object System.Windows.Forms.Timer
                $script:osRecentesTimer.Interval = 15000
                $script:osRecentesTimer.Add_Tick({
                    Update-OsRecentesMonitor
                })
                $script:osRecentesTimer.Start()
            } catch {}
            try { $this.Dispose() } catch {}
        })
        $script:startupTimer.Start()
    } catch {}
})

$form.Add_FormClosed({
    try { if ($script:osRecentesTimer) { $script:osRecentesTimer.Stop(); $script:osRecentesTimer.Dispose() } } catch {}
})

$form.ShowDialog() | Out-Null
