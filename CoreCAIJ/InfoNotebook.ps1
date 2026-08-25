# ================================================
#  CAIJ INFORMATICA - INFO NOTEBOOK v4
# ================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$NL = [Environment]::NewLine

$lenovoPreflightPath = Join-Path $PSScriptRoot 'PrepararLenovo.ps1'
$runLenovoPreflight = $true
try {
    # Caminho rapido: o fabricante e o mapeamento ficam no Registro e podem ser
    # conferidos sem abrir outro PowerShell nem inicializar o provedor CIM/WMI.
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
    # Sem informacao confiavel no Registro, preserva a verificacao completa.
    $runLenovoPreflight = $true
}

if ($runLenovoPreflight -and (Test-Path -LiteralPath $lenovoPreflightPath -PathType Leaf)) {
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

. (Join-Path $PSScriptRoot 'GradeRules.ps1')

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

if (-not ('CaijDpiAwareness' -as [type])) {
    $dpiAwarenessSource = @'
using System;
using System.Runtime.InteropServices;

public static class CaijDpiAwareness
{
    [DllImport("user32.dll")]
    private static extern bool SetProcessDpiAwarenessContext(IntPtr value);

    [DllImport("shcore.dll")]
    private static extern int SetProcessDpiAwareness(int value);

    [DllImport("user32.dll")]
    private static extern bool SetProcessDPIAware();

    public static void Enable()
    {
        try {
            if (SetProcessDpiAwarenessContext(new IntPtr(-4))) return;
        } catch { }
        try {
            if (SetProcessDpiAwareness(2) == 0) return;
        } catch { }
        try { SetProcessDPIAware(); } catch { }
    }
}
'@
    Add-Type -TypeDefinition $dpiAwarenessSource -WarningAction SilentlyContinue
}

try { [CaijDpiAwareness]::Enable() } catch {}

$script:caijPrivateFonts = New-Object System.Drawing.Text.PrivateFontCollection
$script:caijInterFamily = $null
$script:caijOrbitronFamily = $null
foreach ($fontSpec in @(
    @{ Path = (Join-Path $PSScriptRoot 'assets\fonts\Inter-Variable.ttf'); Target = 'Inter' },
    @{ Path = (Join-Path $PSScriptRoot 'assets\fonts\Orbitron-Variable.ttf'); Target = 'Orbitron' }
)) {
    try {
        if (Test-Path -LiteralPath $fontSpec.Path) {
            $script:caijPrivateFonts.AddFontFile($fontSpec.Path)
            $family = @($script:caijPrivateFonts.Families | Where-Object { $_.Name -eq $fontSpec.Target } | Select-Object -First 1)
            if ($fontSpec.Target -eq 'Inter' -and $family.Count -gt 0) { $script:caijInterFamily = $family[0] }
            if ($fontSpec.Target -eq 'Orbitron' -and $family.Count -gt 0) { $script:caijOrbitronFamily = $family[0] }
        }
    } catch {}
}

function New-CaijFont {
    param(
        [ValidateSet('UI','Display')][string]$Kind = 'UI',
        [float]$Size = 9,
        [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular
    )

    # Fontes nativas ficam mais nitidas no WinForms do que fontes variaveis privadas.
    $fontName = if ($Kind -eq 'Display') {
        'Segoe UI Variable Display'
    } elseif ($Size -le 8) {
        'Segoe UI Variable Small'
    } else {
        'Segoe UI Variable Text'
    }
    try {
        $nativeFont = New-Object System.Drawing.Font($fontName, $Size, $Style, [System.Drawing.GraphicsUnit]::Point)
        if ($nativeFont.Name -eq $fontName) { return $nativeFont }
        $nativeFont.Dispose()
    } catch {}

    $fallback = if ($Kind -eq 'Display') { 'Segoe UI Semibold' } else { 'Segoe UI' }
    try {
        return New-Object System.Drawing.Font($fallback, $Size, $Style, [System.Drawing.GraphicsUnit]::Point)
    } catch {
        return New-Object System.Drawing.Font('Arial', $Size, $Style, [System.Drawing.GraphicsUnit]::Point)
    }
}

function Set-CaijWindowsTypography {
    param([System.Windows.Forms.Control]$Root)
    if (-not $Root) { return }

    $queue = New-Object System.Collections.Queue
    $queue.Enqueue($Root)
    while ($queue.Count -gt 0) {
        $control = [System.Windows.Forms.Control]$queue.Dequeue()
        foreach ($child in $control.Controls) { $queue.Enqueue($child) }
        if (-not $control.Font -or $control.Font.Name -match 'Symbol|Barcode|Code 128') { continue }

        $kind = 'UI'
        if (
            $control -is [System.Windows.Forms.Label] -and
            $control.Font.Bold -and
            $control.Font.Size -ge 13 -and
            ([string]$control.Text).Length -ge 10 -and
            [string]$control.Text -match '[A-Za-z]'
        ) {
            $kind = 'Display'
        }
        try {
            $fontSize = [float]$control.Font.Size
            $newFont = New-CaijFont -Kind $kind -Size $fontSize -Style $control.Font.Style
            if ($kind -eq 'Display' -and $control.Width -gt 20 -and [string]$control.Text) {
                $maxWidth = [Math]::Max(16, $control.Width - 6)
                while (
                    $fontSize -gt 9 -and
                    [System.Windows.Forms.TextRenderer]::MeasureText([string]$control.Text, $newFont).Width -gt $maxWidth
                ) {
                    $newFont.Dispose()
                    $fontSize -= 0.5
                    $newFont = New-CaijFont -Kind $kind -Size $fontSize -Style $control.Font.Style
                }
            }
            $control.Font = $newFont
            if ($control -is [System.Windows.Forms.Button]) {
                $control.UseCompatibleTextRendering = $false
                Set-DoubleBuffered -Control $control
            }
        } catch {}
    }

    if ($Root -is [System.Windows.Forms.Form]) {
        Set-CaijDpiLayout -Form $Root
    }
}

function Get-CaijDpiScale {
    $graphics = $null
    try {
        $graphics = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
        return [Math]::Max(1.0, [Math]::Min(2.0, ([double]$graphics.DpiX / 96.0)))
    } catch {
        return 1.0
    } finally {
        if ($graphics) { $graphics.Dispose() }
    }
}

function Set-CaijDpiLayout {
    param([System.Windows.Forms.Form]$Form)
    if (-not $Form) { return }
    if ($Form.PSObject.Properties['CaijDpiLayoutApplied']) { return }

    $dpiScale = Get-CaijDpiScale
    $Form | Add-Member -NotePropertyName CaijDpiLayoutApplied -NotePropertyValue $true
    if ($dpiScale -le 1.01) { return }

    $workingArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $maxScaleX = [Math]::Max(1.0, (($workingArea.Width - 32.0) / [Math]::Max(1, $Form.Width)))
    $maxScaleY = [Math]::Max(1.0, (($workingArea.Height - 32.0) / [Math]::Max(1, $Form.Height)))
    $scale = [Math]::Min($dpiScale, [Math]::Min($maxScaleX, $maxScaleY))

    # Se uma janela alta precisar de escala menor, fonte e geometria continuam proporcionais.
    $fontRatio = $scale / $dpiScale
    if ($fontRatio -lt 0.995) {
        $fontQueue = New-Object System.Collections.Queue
        $fontQueue.Enqueue($Form)
        while ($fontQueue.Count -gt 0) {
            $fontControl = [System.Windows.Forms.Control]$fontQueue.Dequeue()
            foreach ($child in $fontControl.Controls) { $fontQueue.Enqueue($child) }
            if (-not $fontControl.Font -or $fontControl.Font.Name -match 'Symbol|Barcode|Code 128') { continue }
            try {
                $fontControl.Font = New-Object System.Drawing.Font(
                    $fontControl.Font.FontFamily,
                    ([float]($fontControl.Font.Size * $fontRatio)),
                    $fontControl.Font.Style,
                    [System.Drawing.GraphicsUnit]::Point
                )
            } catch {}
        }
    }

    $hadMinimumSize = ($Form.MinimumSize.Width -gt 0 -or $Form.MinimumSize.Height -gt 0)
    if ($Form.Name -eq 'InfoNotebookMain') { $script:mainLayoutSuspended = $true }
    try {
        $Form.SuspendLayout()
        $Form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
        $Form.Scale((New-Object System.Drawing.SizeF([float]$scale, [float]$scale)))
        if ($hadMinimumSize) { $Form.MinimumSize = $Form.Size }
    } finally {
        $Form.ResumeLayout($true)
    }

    if ($Form.Name -eq 'InfoNotebookMain') {
        $script:mainLayoutWidth = $Form.ClientSize.Width
        $script:mainLayoutHeight = $Form.ClientSize.Height
        $script:mainDpiScaleApplied = $scale
        $script:mainResponsiveScaleX = 1.0
        $script:mainResponsiveScaleY = 1.0
        foreach ($item in $script:mainLayoutControls) {
            $item.X = $item.Control.Left
            $item.Y = $item.Control.Top
        }
        $script:mainLayoutSuspended = $false
    }

    # Regions do WinForms nao acompanham Control.Scale; recria os recortes no tamanho novo.
    $regionQueue = New-Object System.Collections.Queue
    $regionQueue.Enqueue($Form)
    while ($regionQueue.Count -gt 0) {
        $regionControl = [System.Windows.Forms.Control]$regionQueue.Dequeue()
        foreach ($child in $regionControl.Controls) { $regionQueue.Enqueue($child) }
        $radiusProperty = $regionControl.PSObject.Properties['CaijBaseCornerRadius']
        if ($radiusProperty) {
            Set-RoundedControl -Control $regionControl -Radius ([Math]::Max(1, [int][Math]::Round(([int]$radiusProperty.Value * $scale))))
        }
    }
}

if (-not ('CaijGradeMenuRenderer' -as [type])) {
    $gradeMenuRendererSource = @'
using System;
using System.Drawing;
using System.Windows.Forms;

public sealed class CaijGradeMenuRenderer : ToolStripProfessionalRenderer
{
    private static readonly Color Background = Color.FromArgb(9, 14, 29);
    private static readonly Color Hover = Color.FromArgb(38, 27, 70);
    private static readonly Color Border = Color.FromArgb(53, 45, 79);
    private static readonly Color Text = Color.FromArgb(244, 241, 255);

    public CaijGradeMenuRenderer()
    {
        RoundedEdges = false;
    }

    private static Color GetAccent(object rawTag)
    {
        string tag = Convert.ToString(rawTag).Trim().ToUpperInvariant();
        if (tag == "A") return Color.FromArgb(34, 197, 94);
        if (tag == "B") return Color.FromArgb(245, 158, 11);
        if (tag.StartsWith("C - PINTURA")) return Color.FromArgb(249, 115, 22);
        if (tag.StartsWith("T - TRIAGEM")) return Color.FromArgb(139, 92, 246);
        if (tag == "RMA") return Color.FromArgb(244, 63, 94);
        return Color.FromArgb(112, 105, 133);
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
        e.TextColor = e.Item.Enabled ? Text : Color.FromArgb(112, 105, 133);
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

if (-not ('CaijWindowTheme' -as [type])) {
    $windowThemeSource = @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public static class CaijWindowTheme
{
    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

    public static void UseDarkTitleBar(Form form)
    {
        if (form == null) return;
        int enabled = 1;
        IntPtr handle = form.Handle;
        if (DwmSetWindowAttribute(handle, 20, ref enabled, sizeof(int)) != 0)
            DwmSetWindowAttribute(handle, 19, ref enabled, sizeof(int));
    }
}
'@
    Add-Type -TypeDefinition $windowThemeSource -ReferencedAssemblies @('System.Windows.Forms') -WarningAction SilentlyContinue
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
$splash.Text            = 'InfoNotebook'
$splash.ClientSize      = New-Object System.Drawing.Size(520, 300)
$splash.StartPosition   = 'CenterScreen'
$splash.BackColor       = [System.Drawing.Color]::FromArgb(7, 9, 17)
$splash.FormBorderStyle = 'None'
$splash.MaximizeBox     = $false
$splash.MinimizeBox     = $false
$splash.TopMost         = $true
Set-DoubleBuffered $splash

$splash.Add_Paint({
    param($sender, $e)
    $border = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(42, 46, 63), 1)
    $e.Graphics.DrawRectangle($border, 0, 0, $sender.ClientSize.Width - 1, $sender.ClientSize.Height - 1)
    $border.Dispose()
})

$splashCard = New-Object System.Windows.Forms.Panel
$splashCard.BackColor = [System.Drawing.Color]::FromArgb(7, 9, 17)
$splashCard.Location  = New-Object System.Drawing.Point(1, 1)
$splashCard.Size      = New-Object System.Drawing.Size(518, 298)
$splashCard.BorderStyle = 'None'
$splash.Controls.Add($splashCard)

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
    $logoPath = $null
}

$splashEyebrow = New-Object System.Windows.Forms.Label
$splashEyebrow.Text      = 'CAIJ INFORMATICA  /  GESTAO TECNICA'
$splashEyebrow.Font      = New-CaijFont -Kind UI -Size 8 -Style ([System.Drawing.FontStyle]::Bold)
$splashEyebrow.ForeColor = [System.Drawing.Color]::FromArgb(112, 124, 228)
$splashEyebrow.Location  = New-Object System.Drawing.Point(34, 24)
$splashEyebrow.Size      = New-Object System.Drawing.Size(330, 18)
$splashCard.Controls.Add($splashEyebrow)
$splashLogoImg = New-Object System.Windows.Forms.PictureBox
$splashLogoImg.Location = New-Object System.Drawing.Point(384, 20)
$splashLogoImg.Size = New-Object System.Drawing.Size(100, 48)
$splashLogoImg.SizeMode = 'Zoom'
$splashLogoImg.BackColor = [System.Drawing.Color]::Transparent
$splashCard.Controls.Add($splashLogoImg)

$splashLogo = New-Object System.Windows.Forms.Label
$splashLogo.Text      = 'IN'
$splashLogo.Font      = New-CaijFont -Kind Display -Size 18 -Style ([System.Drawing.FontStyle]::Bold)
$splashLogo.ForeColor = [System.Drawing.Color]::FromArgb(240, 242, 248)
$splashLogo.BackColor = [System.Drawing.Color]::FromArgb(21, 24, 38)
$splashLogo.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$splashLogo.Location  = New-Object System.Drawing.Point(438, 20)
$splashLogo.Size      = New-Object System.Drawing.Size(46, 46)
$splashCard.Controls.Add($splashLogo)
if (Test-Path $logoPath) {
    try {
        $splashLogoImg.Image = [System.Drawing.Image]::FromFile($logoPath)
        $splashLogo.Visible = $false
    } catch {}
}

$splashTagline = New-Object System.Windows.Forms.Label
$splashTagline.Text      = 'Preparando o InfoNotebook'
$splashTagline.Font      = New-CaijFont -Kind Display -Size 22 -Style ([System.Drawing.FontStyle]::Bold)
$splashTagline.ForeColor = [System.Drawing.Color]::FromArgb(240, 242, 248)
$splashTagline.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$splashTagline.Location  = New-Object System.Drawing.Point(34, 58)
$splashTagline.Size      = New-Object System.Drawing.Size(390, 42)
$splashCard.Controls.Add($splashTagline)

$splashSub = New-Object System.Windows.Forms.Label
$splashSub.Text      = 'Inventario, diagnostico e etiquetagem em um unico fluxo.'
$splashSub.Font      = New-CaijFont -Kind UI -Size 9
$splashSub.ForeColor = [System.Drawing.Color]::FromArgb(166, 170, 184)
$splashSub.Location  = New-Object System.Drawing.Point(36, 101)
$splashSub.Size      = New-Object System.Drawing.Size(448, 20)
$splashCard.Controls.Add($splashSub)

$splashStatusCard = New-Object System.Windows.Forms.Panel
$splashStatusCard.BackColor = [System.Drawing.Color]::FromArgb(15, 18, 29)
$splashStatusCard.Location  = New-Object System.Drawing.Point(34, 142)
$splashStatusCard.Size      = New-Object System.Drawing.Size(450, 76)
$splashCard.Controls.Add($splashStatusCard)

$splashSpinner = New-Object System.Windows.Forms.Label
$splashSpinner.Text      = '●'
$splashSpinner.Font      = New-Object System.Drawing.Font('Segoe UI Symbol', 11, [System.Drawing.FontStyle]::Bold)
$splashSpinner.ForeColor = [System.Drawing.Color]::FromArgb(94, 106, 210)
$splashSpinner.Location  = New-Object System.Drawing.Point(18, 17)
$splashSpinner.Size      = New-Object System.Drawing.Size(18, 20)
$splashStatusCard.Controls.Add($splashSpinner)

$splashMsg = New-Object System.Windows.Forms.Label
$splashMsg.Text      = 'Coletando informacoes de hardware...'
$splashMsg.Font      = New-CaijFont -Kind UI -Size 9 -Style ([System.Drawing.FontStyle]::Bold)
$splashMsg.ForeColor = [System.Drawing.Color]::FromArgb(240, 242, 248)
$splashMsg.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$splashMsg.Location  = New-Object System.Drawing.Point(42, 14)
$splashMsg.Size      = New-Object System.Drawing.Size(340, 24)
$splashStatusCard.Controls.Add($splashMsg)

$splashPercent = New-Object System.Windows.Forms.Label
$splashPercent.Text      = '0%'
$splashPercent.Font      = New-CaijFont -Kind UI -Size 9 -Style ([System.Drawing.FontStyle]::Bold)
$splashPercent.ForeColor = [System.Drawing.Color]::FromArgb(166, 170, 184)
$splashPercent.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$splashPercent.Location  = New-Object System.Drawing.Point(384, 17)
$splashPercent.Size      = New-Object System.Drawing.Size(48, 20)
$splashStatusCard.Controls.Add($splashPercent)

$splashBarTrack = New-Object System.Windows.Forms.Panel
$splashBarTrack.BackColor = [System.Drawing.Color]::FromArgb(28, 32, 48)
$splashBarTrack.Location  = New-Object System.Drawing.Point(18, 51)
$splashBarTrack.Size      = New-Object System.Drawing.Size(414, 6)
$splashBarTrack.BorderStyle = 'None'
$splashStatusCard.Controls.Add($splashBarTrack)

$splashBar = New-Object System.Windows.Forms.Label
$splashBar.BackColor = [System.Drawing.Color]::FromArgb(94, 106, 210)
$splashBar.Location  = New-Object System.Drawing.Point(0, 0)
$splashBar.Size      = New-Object System.Drawing.Size(0, 6)
$splashBarTrack.Controls.Add($splashBar)

$splashFoot = New-Object System.Windows.Forms.Label
$splashFoot.Text      = 'Leitura local e segura do equipamento'
$splashFoot.Font      = New-CaijFont -Kind UI -Size 8
$splashFoot.ForeColor = [System.Drawing.Color]::FromArgb(112, 117, 133)
$splashFoot.Location  = New-Object System.Drawing.Point(34, 238)
$splashFoot.Size      = New-Object System.Drawing.Size(330, 18)
$splashCard.Controls.Add($splashFoot)

$splashVersion = New-Object System.Windows.Forms.Label
$splashVersion.Text      = 'v4.1'
$splashVersion.Font      = New-CaijFont -Kind UI -Size 8 -Style ([System.Drawing.FontStyle]::Bold)
$splashVersion.ForeColor = [System.Drawing.Color]::FromArgb(166, 170, 184)
$splashVersion.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$splashVersion.Location  = New-Object System.Drawing.Point(418, 238)
$splashVersion.Size      = New-Object System.Drawing.Size(66, 18)
$splashCard.Controls.Add($splashVersion)

Set-CaijWindowsTypography -Root $splash
$splash.Show()
[System.Windows.Forms.Application]::DoEvents()

# Animacao da barra de progresso
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 80
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
$script:splashBarMaxW = 414
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

function Test-IsGenericVideoAdapterName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { return $true }
    return ($Name -match '(?i)(Citrix|LogMeIn|TeamViewer|Remote|Virtual|Microsoft\s+Basic|Basic\s+Display|Adaptador\s+de\s+V.deo\s+B.sico)')
}

function Get-NotebookInfo {
    $info = [ordered]@{}
    $videoControllers = @()
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
        $videoControllers = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)
        $gpus = @($videoControllers | Where-Object {
            $_ -and $_.Name -and -not (Test-IsGenericVideoAdapterName ([string]$_.Name))
        })
        $gpuList = @(); $hasDedicated = $false; $gpuDedicada = $null
        $nvidiaGpuMemorias = @()

        # AdapterRAM e um UInt32 e pode saturar perto de 4 GB em placas maiores.
        # Para NVIDIA, o driver fornece a VRAM real pelo nvidia-smi.
        try {
            $nvidiaSmiCmd = Get-Command 'nvidia-smi.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
            $nvidiaSmiPath = if ($nvidiaSmiCmd) { [string]$nvidiaSmiCmd.Source } else { '' }
            if (-not $nvidiaSmiPath) {
                $nvidiaSmiPadrao = Join-Path $env:ProgramFiles 'NVIDIA Corporation\NVSMI\nvidia-smi.exe'
                if (Test-Path -LiteralPath $nvidiaSmiPadrao) {
                    $nvidiaSmiPath = $nvidiaSmiPadrao
                }
            }
            if ($nvidiaSmiPath) {
                $linhasNvidiaSmi = @(& $nvidiaSmiPath '--query-gpu=name,memory.total' '--format=csv,noheader,nounits' 2>$null)
                foreach ($linhaNvidiaSmi in $linhasNvidiaSmi) {
                    $partesNvidiaSmi = @([string]$linhaNvidiaSmi -split ',', 2)
                    if ($partesNvidiaSmi.Count -lt 2) { continue }
                    $memoriaMbTexto = ([string]$partesNvidiaSmi[1]).Trim()
                    if ($memoriaMbTexto -notmatch '^\d+$') { continue }
                    $nvidiaGpuMemorias += [pscustomobject]@{
                        Nome = ([string]$partesNvidiaSmi[0]).Trim()
                        MemoriaMb = [int64]$memoriaMbTexto
                    }
                }
            }
        } catch {}

        function Get-VramTexto($gpuObj) {
            try {
                $nomeGpuVram = ([string]$gpuObj.Name).Trim()
                if ($nomeGpuVram -match '(?i)NVIDIA|GeForce|RTX|GTX|Quadro' -and $nvidiaGpuMemorias.Count -gt 0) {
                    $memoriaNvidia = @($nvidiaGpuMemorias | Where-Object {
                        ([string]$_.Nome).Equals($nomeGpuVram, [System.StringComparison]::OrdinalIgnoreCase) -or
                        $nomeGpuVram.IndexOf([string]$_.Nome, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                        ([string]$_.Nome).IndexOf($nomeGpuVram, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
                    } | Select-Object -First 1)
                    if ($memoriaNvidia.Count -eq 0 -and $nvidiaGpuMemorias.Count -eq 1) {
                        $memoriaNvidia = @($nvidiaGpuMemorias[0])
                    }
                    if ($memoriaNvidia.Count -gt 0 -and [int64]$memoriaNvidia[0].MemoriaMb -gt 0) {
                        $vramNvidiaGb = [math]::Round(([double]$memoriaNvidia[0].MemoriaMb / 1024), 1)
                        if (($vramNvidiaGb % 1) -eq 0) { return ('{0}GB' -f [int]$vramNvidiaGb) }
                        return ('{0}GB' -f $vramNvidiaGb.ToString('0.#', [System.Globalization.CultureInfo]::InvariantCulture))
                    }
                }
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
                        -not (Test-IsGenericVideoAdapterName ([string]$_.FriendlyName)) -and
                        $_.Status -ne 'Unknown'
                    } |
                    Select-Object -First 1
                if ($pnp -and $pnp.FriendlyName) { $gpuFallback = [string]$pnp.FriendlyName }
            } catch {}

            if (-not $gpuFallback) {
                try {
                    $vc2 = $videoControllers |
                        Where-Object { $_.Name -and -not (Test-IsGenericVideoAdapterName ([string]$_.Name)) } |
                        Select-Object -First 1
                    if ($vc2 -and $vc2.Name) { $gpuFallback = [string]$vc2.Name }
                } catch {}
            }

            if ($gpuFallback) {
                $nomeBase = ($gpuFallback -replace '\(TM\)','' -replace '\(R\)','').Trim()
                $info.GPU = "$nomeBase (Integrada)"
            } elseif ($info.CPU -match '(?i)\b(AMD|Ryzen)\b') {
                $info.GPU = 'AMD Radeon Graphics (Integrada)'
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
        $videoRes = $videoControllers | Where-Object { $_.CurrentHorizontalResolution -ne $null } | Select-Object -First 1
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
$script:modeloManualUltimoArquivo = Join-Path (Split-Path -Parent $PSCommandPath) 'caij_ultimo_modelo_manual.json'
$script:modelosManuaisHistorico = @()
$script:modelosManuaisUltimos = @{}
$script:registroBaseDir = $null
$script:registroBaseDirFallback = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'CAIJ\Registros'
$script:ultimoStatusServidor = 'nao verificado'
$script:ultimaSincronizacaoOs = ''
$script:osNumero  = 235
$script:osDefinidaPorAltertag = $false
$script:osDefinidaManual = $false
$script:altertagOsAtual = $null
$script:osImpressaoPendente = $null
$script:altertagOsDetalheConfirmado = $null
$script:maiorOsVistaAltertag = 0
$script:ultimoAlertaOsNumero = 0
$script:ultimoConfirmadoServidor = 0
$script:osAlertMonitorBusy = $false
$script:alertaOsAtual = $null
$script:osGlobalAlertOpen = $false
$script:osNumeroControls = New-Object System.Collections.ArrayList
$script:osPreviewRefreshAction = $null
$script:tecnicoCadastroOsPersistido = ''
$script:abrirManualNaProximaPrevia = $false
$script:abrirManualPorOsSelecionada = $false
$script:ultimaEtiquetaPayload = $null
$script:ultimaEtiquetaResumo = $null
$script:celularImeiEtiqueta = ''
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
            $modelosImportados = @(
                $raw |
                    ConvertFrom-Json -ErrorAction Stop |
                    ForEach-Object { ([string]$_).Trim() } |
                    Where-Object {
                        $_ -and
                        $_ -notmatch '^(?i:N/?A)$' -and
                        $_.Length -le 80
                    } |
                    Select-Object -Unique -First 200
            )
            $script:modelosManuaisHistorico = @($modelosImportados)

            # Remove entradas antigas em que varios modelos foram gravados como uma unica sugestao.
            $quantidadeOriginal = @($raw | ConvertFrom-Json -ErrorAction Stop).Count
            if ($script:modelosManuaisHistorico.Count -ne $quantidadeOriginal) {
                $script:modelosManuaisHistorico |
                    ConvertTo-Json -Depth 3 |
                    Set-Content -LiteralPath $script:modelosManuaisArquivo -Encoding UTF8 -ErrorAction Stop
            }
        }
    } catch {
        $script:modelosManuaisHistorico = @()
    }
}

function Add-ModeloManualHistorico {
    param([string]$Modelo)

    $modeloLimpo = if ($Modelo) { $Modelo.Trim() } else { '' }
    if (
        -not $modeloLimpo -or
        $modeloLimpo -match '^(?i:N/?A)$' -or
        $modeloLimpo.Length -gt 80
    ) { return }

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

function Import-ModelosManuaisUltimos {
    $script:modelosManuaisUltimos = @{}
    if (-not (Test-Path -LiteralPath $script:modeloManualUltimoArquivo)) { return }
    try {
        $salvos = Get-Content -LiteralPath $script:modeloManualUltimoArquivo -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        foreach ($tipo in @('Notebook', 'Desktop', 'Monitor', 'Celular')) {
            $prop = $salvos.PSObject.Properties[$tipo]
            $modelo = if ($prop) { ([string]$prop.Value).Trim() } else { '' }
            if ($modelo -and $modelo.Length -le 80) { $script:modelosManuaisUltimos[$tipo] = $modelo }
        }
    } catch {
        $script:modelosManuaisUltimos = @{}
    }
}

function Get-ModeloManualUltimo {
    param([string]$Tipo)
    $tipoNormalizado = if ($Tipo -in @('Notebook', 'Desktop', 'Monitor', 'Celular')) { $Tipo } else { 'Notebook' }
    if ($script:modelosManuaisUltimos.ContainsKey($tipoNormalizado)) {
        return ([string]$script:modelosManuaisUltimos[$tipoNormalizado]).Trim()
    }
    return ''
}

function Save-ModeloManualUltimo {
    param([string]$Tipo, [string]$Modelo)
    $tipoNormalizado = if ($Tipo -in @('Notebook', 'Desktop', 'Monitor', 'Celular')) { $Tipo } else { 'Notebook' }
    $modeloLimpo = if ($Modelo) { $Modelo.Trim() } else { '' }
    if (-not $modeloLimpo -or $modeloLimpo.Length -gt 80) { return $false }

    $script:modelosManuaisUltimos[$tipoNormalizado] = $modeloLimpo
    $dadosPersistidos = [ordered]@{}
    foreach ($tipoConhecido in @('Notebook', 'Desktop', 'Monitor', 'Celular')) {
        $dadosPersistidos[$tipoConhecido] = Get-ModeloManualUltimo -Tipo $tipoConhecido
    }
    try {
        [pscustomobject]$dadosPersistidos |
            ConvertTo-Json -Depth 3 |
            Set-Content -LiteralPath $script:modeloManualUltimoArquivo -Encoding UTF8 -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Get-IPhoneBatteryUsb {
    param([string]$Udid = '')

    $diagnosticsExe = Join-Path $PSScriptRoot 'tools\libimobiledevice\idevicediagnostics.exe'
    if (-not (Test-Path -LiteralPath $diagnosticsExe)) {
        throw 'Leitor USB de bateria nao encontrado.'
    }

    $arguments = if ($Udid) {
        '-u "{0}" ioregentry AppleSmartBattery' -f ($Udid -replace '"', '')
    } else {
        'ioregentry AppleSmartBattery'
    }
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $diagnosticsExe
    $startInfo.Arguments = $arguments
    $startInfo.WorkingDirectory = Split-Path -Parent $diagnosticsExe
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw 'Nao foi possivel iniciar a leitura USB.' }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(10000)) {
            try { $process.Kill() } catch {}
            throw 'A leitura da bateria excedeu 10 segundos.'
        }
        $stdout = [string]$stdoutTask.Result
        $stderr = [string]$stderrTask.Result
        if ($process.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($stdout)) {
            $details = if ($stderr.Trim()) { $stderr.Trim() } else { 'iPhone indisponivel para diagnostico.' }
            throw $details
        }
    } finally {
        $process.Dispose()
    }

    try { [xml]$batteryXml = $stdout } catch { throw 'O diagnostico USB retornou dados de bateria invalidos.' }
    function Get-BatteryInteger {
        param([string]$Key)
        $keyNode = @($batteryXml.SelectNodes("//key[text()='$Key']")) | Select-Object -First 1
        if (-not $keyNode) { return 0 }
        $valueNode = $keyNode.NextSibling
        while ($valueNode -and $valueNode.NodeType -ne [System.Xml.XmlNodeType]::Element) {
            $valueNode = $valueNode.NextSibling
        }
        $parsed = 0
        if ($valueNode -and [int]::TryParse($valueNode.InnerText.Trim(), [ref]$parsed)) { return $parsed }
        return 0
    }

    $nominal = Get-BatteryInteger -Key 'NominalChargeCapacity'
    $design = Get-BatteryInteger -Key 'DesignCapacity'
    $cycles = Get-BatteryInteger -Key 'CycleCount'
    if ($nominal -lt 1 -or $design -lt 1) { throw 'O iPhone nao informou a capacidade nominal da bateria.' }

    $percent = [int][Math]::Round((100.0 * $nominal / $design), 0, [MidpointRounding]::AwayFromZero)
    $percent = [Math]::Max(1, [Math]::Min(100, $percent))
    $quality = if ($percent -ge 90) { 'Excellent' } elseif ($percent -ge 75) { 'Good' } elseif ($percent -ge 50) { 'Fair' } else { 'Poor' }
    return [pscustomobject]@{
        Percentual = $percent
        Qualidade = "$quality ($percent%)"
        Ciclos = $cycles
        CapacidadeNominal = $nominal
        CapacidadeProjeto = $design
    }
}

function Get-IPhoneStorageUsb {
    param([string]$Udid = '')

    $deviceInfoExe = Join-Path $PSScriptRoot 'tools\libimobiledevice\ideviceinfo.exe'
    if (-not (Test-Path -LiteralPath $deviceInfoExe)) {
        throw 'Leitor USB de armazenamento nao encontrado.'
    }

    $arguments = if ($Udid) {
        '-u "{0}" -q com.apple.disk_usage -k TotalDataCapacity' -f ($Udid -replace '"', '')
    } else {
        '-q com.apple.disk_usage -k TotalDataCapacity'
    }
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $deviceInfoExe
    $startInfo.Arguments = $arguments
    $startInfo.WorkingDirectory = Split-Path -Parent $deviceInfoExe
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw 'Nao foi possivel iniciar a leitura do armazenamento.' }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(10000)) {
            try { $process.Kill() } catch {}
            throw 'A leitura do armazenamento excedeu 10 segundos.'
        }
        $stdout = [string]$stdoutTask.Result
        $stderr = [string]$stderrTask.Result
        if ($process.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($stdout)) {
            $details = if ($stderr.Trim()) { $stderr.Trim() } else { 'Armazenamento do iPhone indisponivel.' }
            throw $details
        }
    } finally {
        $process.Dispose()
    }

    $capacityBytes = @(
        [regex]::Matches($stdout, '(?<!\d)\d{8,15}(?!\d)') |
            ForEach-Object { [double]$_.Value } |
            Sort-Object -Descending
    ) | Select-Object -First 1
    if (-not $capacityBytes -or $capacityBytes -lt 8GB) {
        throw 'O iPhone nao informou a capacidade total do armazenamento.'
    }

    $capacityGb = [double]$capacityBytes / 1GB
    $marketedGb = @(16, 32, 64, 128, 256, 512, 1024, 2048) |
        Sort-Object { [math]::Abs([double]$_ - $capacityGb) } |
        Select-Object -First 1
    return if ([int]$marketedGb -ge 1024) { "$([int]$marketedGb / 1024)TB" } else { "$marketedGb`GB" }
}

function Get-3uToolsDeviceInfo {
    $installDirs = New-Object System.Collections.Generic.List[string]
    foreach ($candidate in @(
        'C:\Program Files\3uTools9',
        'C:\Program Files (x86)\3uTools9',
        'C:\Program Files\3uTools',
        'C:\Program Files (x86)\3uTools'
    )) {
        if (Test-Path -LiteralPath $candidate) { [void]$installDirs.Add($candidate) }
    }
    foreach ($uninstallRoot in @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )) {
        foreach ($entry in @(Get-ItemProperty $uninstallRoot -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match '^3uTools' })) {
            $iconPath = (([string]$entry.DisplayIcon) -replace ',\d+$', '').Trim('"')
            if ($iconPath) {
                $dir = Split-Path -Parent $iconPath
                if ($dir -and (Test-Path -LiteralPath $dir) -and -not $installDirs.Contains($dir)) {
                    [void]$installDirs.Add($dir)
                }
            }
        }
    }

    $infoFile = @(
        foreach ($installDir in $installDirs) {
            $cacheDir = Join-Path $installDir 'cache'
            if (Test-Path -LiteralPath $cacheDir) {
                Get-ChildItem -LiteralPath $cacheDir -Filter '*_info.txt' -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Length -gt 0 -and $_.BaseName -ne '_info' }
            }
        }
    ) | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $infoFile) { throw 'Nenhum iPhone foi localizado no cache do 3uTools.' }

    $values = @{}
    foreach ($line in @(Get-Content -LiteralPath $infoFile.FullName -ErrorAction Stop)) {
        if ([string]$line -match '^\s*(\S+)\s{2,}(.+?)\s*$') {
            $values[$matches[1]] = $matches[2].Trim()
        }
    }

    $productType = [string]$values['ProductType']
    $modelName = ''
    foreach ($installDir in $installDirs) {
        $deviceTable = Join-Path $installDir 'cache\devices_table\devices_table.txt'
        if (-not $productType -or -not (Test-Path -LiteralPath $deviceTable)) { continue }
        $modelLine = Get-Content -LiteralPath $deviceTable -ErrorAction SilentlyContinue |
            Where-Object { $_ -match '"ProductName"' -and $_ -match ('"ProductType"\s*:\s*"' + [regex]::Escape($productType) + '"') } |
            Select-Object -First 1
        if ($modelLine -and $modelLine -match '"ProductName"\s*:\s*"([^"]+)"') {
            $modelName = $matches[1].Trim()
            break
        }
    }
    if (-not $modelName) { $modelName = if ($productType) { $productType } else { 'iPhone' } }

    $serial = ([string]$values['SerialNumber']).Trim()
    $imei = (([string]$values['InternationalMobileEquipmentIdentity']) -replace '[^0-9]', '')
    if ($serial -and $imei.Length -ne 15) {
        $udidNormalizado = (([string]$values['UniqueDeviceID']) -replace '[^A-Za-z0-9]', '').ToUpperInvariant()
        foreach ($installDir in $installDirs) {
            $deviceInfoPath = Join-Path $installDir 'cache\files\deviceinfo.txt'
            if (-not (Test-Path -LiteralPath $deviceInfoPath)) { continue }
            $registroDispositivo = @(
                Get-Content -LiteralPath $deviceInfoPath -ErrorAction SilentlyContinue | Where-Object {
                    $colunas = @([string]$_ -split "`t")
                    if ($colunas.Count -lt 4) { return $false }
                    $serialLinha = ([string]$colunas[2]).Trim()
                    $udidLinha = (([string]$colunas[1]) -replace '[^A-Za-z0-9]', '').ToUpperInvariant()
                    return ($serialLinha -eq $serial -or ($udidNormalizado -and $udidLinha -eq $udidNormalizado))
                }
            ) | Select-Object -Last 1
            if ($registroDispositivo) {
                $imeiAlternativo = @([regex]::Matches([string]$registroDispositivo, '(?<!\d)\d{15}(?!\d)') | ForEach-Object { $_.Value }) | Select-Object -First 1
                if ($imeiAlternativo) {
                    $imei = [string]$imeiAlternativo
                    break
                }
            }
        }
    }
    if (-not $serial -or $imei.Length -ne 15) {
        throw 'O cache do 3uTools nao possui Serial Number e IMEI1 validos. Atualize a tela do aparelho e tente novamente.'
    }

    $battery = $null
    $batteryError = ''
    try {
        $battery = Get-IPhoneBatteryUsb -Udid ([string]$values['UniqueDeviceID'])
    } catch {
        $batteryError = $_.Exception.Message
    }

    $storage = ''
    $storageError = ''
    try {
        $storage = Get-IPhoneStorageUsb -Udid ([string]$values['UniqueDeviceID'])
    } catch {
        $storageError = $_.Exception.Message
    }

    return [pscustomobject]@{
        Modelo = $modelName
        Serial = $serial
        Imei = $imei
        Bateria = if ($battery) { [string]$battery.Qualidade } else { '' }
        Ciclos = if ($battery) { [int]$battery.Ciclos } else { 0 }
        BateriaErro = $batteryError
        Armazenamento = [string]$storage
        ArmazenamentoErro = $storageError
        Arquivo = $infoFile.FullName
        AtualizadoEm = $infoFile.LastWriteTime
    }
}

Import-ModelosManuaisHistorico
Import-ModelosManuaisUltimos

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
        $Cor
    )
    if ($Cor -isnot [System.Drawing.Color]) {
        $Cor = if ($cMuted -is [System.Drawing.Color]) { $cMuted } else { [System.Drawing.Color]::FromArgb(145, 137, 163) }
    }
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
        $Cor,
        [string]$TextoDepois,
        $CorDepois,
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
        [string]$Obs,
        [int]$OsNumero = 0,
        [string]$Serial = '',
        [string]$Modelo = '',
        [string]$Cpu = '',
        [string]$Ram = '',
        [string]$Disco = '',
        [string]$Gpu = '',
        [string]$Bateria = ''
    )
    if ($OsNumero -lt 1) { $OsNumero = [int]$script:osNumero }
    if (-not $PSBoundParameters.ContainsKey('Serial')) {
        $Serial = if ($script:serialEtiqueta -and $script:serialEtiqueta.Trim()) { $script:serialEtiqueta } else { $info.Serial }
    }
    if (-not $PSBoundParameters.ContainsKey('Modelo')) {
        $Modelo = if ($script:modeloEtiqueta -and $script:modeloEtiqueta.Trim()) { $script:modeloEtiqueta } else { $info.Modelo }
    }
    if (-not $PSBoundParameters.ContainsKey('Cpu')) { $Cpu = $info.CPU }
    if (-not $PSBoundParameters.ContainsKey('Ram')) { $Ram = $info.RAM }
    if (-not $PSBoundParameters.ContainsKey('Disco')) {
        $Disco = (($info.Discos -split $NL) | Where-Object { $_.Trim() -ne '' } | Select-Object -First 1)
    }
    if (-not $PSBoundParameters.ContainsKey('Gpu')) { $Gpu = $info.GPU }
    if (-not $PSBoundParameters.ContainsKey('Bateria') -and $info.MostrarBateria) { $Bateria = $info.BatSaude }

    $registro = [ordered]@{
        dataHora = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        acao = $Acao
        status = $Status
        mensagem = $Mensagem
        os = (Format-OsCodigo -Numero $OsNumero)
        osNumero = $OsNumero
        serial = $Serial
        modelo = $Modelo
        cpu = $Cpu
        ram = $Ram
        disco = $Disco
        gpu = $Gpu
        bateria = if ([string]::IsNullOrWhiteSpace($Bateria)) { $null } else { $Bateria }
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
            os = (Format-OsCodigo -Numero $OsNumero)
            osNumero = $OsNumero
            status = $Status
            acao = $Acao
            mensagem = $Mensagem
            serial = $Serial
            modelo = $Modelo
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

function Find-SerialManualNoHistorico {
    param([string]$Serial)

    $serialNormalizado = if ($Serial) { ($Serial -replace '\s+', '').Trim().ToUpperInvariant() } else { '' }
    if (-not $serialNormalizado -or $serialNormalizado -match '^(N/?A|X+)$') { return $null }
    if (-not (Test-Path -LiteralPath $script:historicoArquivo)) { return $null }
    try {
        $registros = @(Get-Content -LiteralPath $script:historicoArquivo -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)
        return @(
            $registros |
                Where-Object {
                    $serialRegistro = (([string]$_.serial) -replace '\s+', '').Trim().ToUpperInvariant()
                    ([string]$_.status -eq 'ok') -and $serialRegistro -eq $serialNormalizado
                } |
                Select-Object -First 1
        )[0]
    } catch {
        return $null
    }
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

function Get-OsAltertagResumoPreview {
    param(
        [int]$OsNumero,
        $OrdemFallback = $null,
        [switch]$ConsultarOnline
    )

    $ordem = $OrdemFallback
    $mensagem = ''
    $online = $false
    if ($ConsultarOnline -and $OsNumero -gt 0) {
        try {
            $resp = Invoke-CaijServer -Path "/os-detalhe?osNumero=$OsNumero&produtos=1" -Method GET -TimeoutSec 3 -Retries 1
            if ($resp -and [string]$resp.status -eq 'ok' -and $resp.ordem) {
                $ordem = $resp.ordem
                $online = $true
            } else {
                $mensagem = 'Detalhes nao encontrados no Altertag'
            }
        } catch {
            $mensagem = 'Altertag indisponivel para conferencia'
        }
    } elseif ($OsNumero -gt 0 -and -not $ordem) {
        $mensagem = 'Conferencia sera carregada apos abrir'
    }

    $produto = ''
    if ($ordem) {
        $produto = ([string]$ordem.equipamento).Trim()
        if (-not $produto -and $ordem.produtos) {
            $produto = @(
                $ordem.produtos |
                    ForEach-Object { ([string]$_.descricao).Trim() } |
                    Where-Object { $_ }
            ) -join ' | '
        }
    }
    [pscustomobject]@{
        osNumero = $OsNumero
        osCodigo = if ($OsNumero -gt 0) { Format-OsCodigo -Numero $OsNumero } else { '-' }
        produto = if ($produto) { $produto } else { 'Produto nao informado' }
        tecnico = if ($ordem -and ([string]$ordem.tecnico).Trim()) { ([string]$ordem.tecnico).Trim() } else { '-' }
        serial = if ($ordem -and ([string]$ordem.garantia).Trim()) { ([string]$ordem.garantia).Trim() } else { '-' }
        statusOs = if ($ordem -and ([string]$ordem.statusOs).Trim()) { ([string]$ordem.statusOs).Trim() } else { '' }
        online = $online
        mensagem = $mensagem
        ordem = $ordem
    }
}

function Register-OsAltertagStatusImpressao {
    param(
        [string]$Grade = '',
        [string]$Obs = '',
        [int]$OsNumero = 0,
        $Ordem = $null,
        [switch]$ForcarAltertag
    )

    if (-not $script:incluirOSAtual) { return $false }
    if (-not $ForcarAltertag -and -not $script:osDefinidaPorAltertag) { return $false }
    if ($OsNumero -lt 1) { $OsNumero = [int]$script:osNumero }
    if (-not $Ordem) { $Ordem = $script:altertagOsAtual }
    $idOrdem = 0
    try { if ($Ordem -and $Ordem.idOrdem) { $idOrdem = [int]$Ordem.idOrdem } } catch {}
    $obsPartes = @(
        "Serial: $($info.Serial)",
        "Modelo: $($info.Modelo)",
        "Grade: $Grade"
    )
    if ($Obs -and $Obs.Trim()) { $obsPartes += "Obs: $($Obs.Trim())" }
    $payloadObj = @{
        idOrdem = $idOrdem
        osNumero = $OsNumero
        tipoStatus = 'Etiqueta CAIJ impressa'
        observacao = ($obsPartes -join ' | ')
    }
    $payload = $payloadObj | ConvertTo-Json -Depth 4 -Compress
    try {
        $resp = Invoke-CaijServer -Path '/os-status' -Method POST -Body $payload -TimeoutSec 22 -Retries 1
        return ($resp -and [string]$resp.status -eq 'ok')
    } catch {
        Set-AppStatusTemporario -Texto 'Impresso | aviso: status nao registrado na OS' -Cor $cYellow -TextoDepois "Impresso | historico salvo | OS $(Format-OsCodigo -Numero $OsNumero)" -CorDepois $cGreen
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
        if ($u -match '^\s*T') { $score += 20 }
        elseif ($u -match '^\s*P') { $score += 10 }
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
# CORES E FONTES (mesma linguagem visual da criacao de OS)
# ================================================
$cBg      = [System.Drawing.Color]::FromArgb(7, 9, 17)
$cSurface = [System.Drawing.Color]::FromArgb(15, 18, 29)
$cCard    = [System.Drawing.Color]::FromArgb(21, 24, 38)
$cHeader  = [System.Drawing.Color]::FromArgb(15, 18, 29)
$cBar     = [System.Drawing.Color]::FromArgb(10, 12, 20)
$cBorder  = [System.Drawing.Color]::FromArgb(42, 46, 63)
$cAccent  = [System.Drawing.Color]::FromArgb(94, 106, 210)
$cAccentHover = [System.Drawing.Color]::FromArgb(112, 124, 228)
$cGreen   = [System.Drawing.Color]::FromArgb(34, 197, 94)
$cPurple  = [System.Drawing.Color]::FromArgb(208, 214, 234)
$cYellow  = [System.Drawing.Color]::FromArgb(245, 158, 11)
$cOrange  = [System.Drawing.Color]::FromArgb(249, 115, 22)
$cRed     = [System.Drawing.Color]::FromArgb(244, 63, 94)
$cMain    = [System.Drawing.Color]::FromArgb(240, 242, 248)
$cMuted   = [System.Drawing.Color]::FromArgb(166, 170, 184)
$cDim     = [System.Drawing.Color]::FromArgb(112, 117, 133)

$fUI    = New-CaijFont -Kind UI -Size 9
$fBold  = New-CaijFont -Kind UI -Size 9 -Style ([System.Drawing.FontStyle]::Bold)
$fSm    = New-CaijFont -Kind UI -Size 8
$fMicro = New-CaijFont -Kind UI -Size 7
$fTitle = New-CaijFont -Kind Display -Size 16 -Style ([System.Drawing.FontStyle]::Bold)
$fSer   = New-CaijFont -Kind UI -Size 15 -Style ([System.Drawing.FontStyle]::Bold)

# ================================================
# FORM
# ================================================
$W = 700

$form = New-Object System.Windows.Forms.Form
$form.Name            = 'InfoNotebookMain'
$form.Text            = 'InfoNotebook'
$form.BackColor       = $cBg
$form.FormBorderStyle = 'Sizable'
$form.MaximizeBox     = $true
$form.StartPosition   = 'CenterScreen'
$form.Font            = $fUI
$form.KeyPreview      = $true

# ================================================
# BARRA SUPERIOR
# ================================================
# ================================================
# TOP BAR
# ================================================
$topBar = New-Object System.Windows.Forms.Panel
$topBar.BackColor = $cSurface
$topBar.Location  = New-Object System.Drawing.Point(0, 0)
$topBar.Size      = New-Object System.Drawing.Size($W, 30)
$form.Controls.Add($topBar)

# Linha inferior accent (violeta sutil)
$topBarLine = New-Object System.Windows.Forms.Panel
$topBarLine.BackColor = $cBorder
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
$tlbl.Text      = 'CAIJ INFORMATICA   |   GESTAO TECNICA'
$tlbl.Font      = New-Object System.Drawing.Font('Segoe UI', 7.5, [System.Drawing.FontStyle]::Bold)
$tlbl.ForeColor = $cMuted
$tlbl.Location  = New-Object System.Drawing.Point(32, 8)
$tlbl.Size      = New-Object System.Drawing.Size(310, 14)
$topBar.Controls.Add($tlbl)

$ttime = New-Object System.Windows.Forms.Label
$ttime.Text      = 'Atualizado: ' + $dataHora
$ttime.Font      = New-Object System.Drawing.Font('Segoe UI', 7.5)
$ttime.ForeColor = $cDim
$ttime.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$ttime.Location  = New-Object System.Drawing.Point(390, 8)
$ttime.Size      = New-Object System.Drawing.Size(282, 14)
$topBar.Controls.Add($ttime)

# ================================================
# HEADER
# ================================================
$hH = 88
$hPanel = New-Object System.Windows.Forms.Panel
$hPanel.BackColor = $cBg
$hPanel.Location  = New-Object System.Drawing.Point(0, 30)
$hPanel.Size      = New-Object System.Drawing.Size($W, $hH)
$form.Controls.Add($hPanel)

$hPanel.Add_Paint({
    param($sender, $e)
    $g = $e.Graphics
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear($cBg)
    $pen = New-Object System.Drawing.Pen($cBorder, 1)
    $g.DrawLine($pen, 0, ($sender.Height - 1), $sender.Width, ($sender.Height - 1))
    $pen.Dispose()
})

# Barra accent esquerda (violeta vivo)
$hAccL = New-Object System.Windows.Forms.Panel
$hAccL.BackColor = $cAccent
$hAccL.Location  = New-Object System.Drawing.Point(0, 0)
$hAccL.Size      = New-Object System.Drawing.Size(3, $hH)
$hAccL.Visible   = $false
$hPanel.Controls.Add($hAccL)

# Titulo
$hEyebrow = New-Object System.Windows.Forms.Label
$hEyebrow.Text      = 'INFONOTEBOOK  /  VISAO GERAL'
$hEyebrow.Font      = New-Object System.Drawing.Font('Segoe UI Semibold', 6.5, [System.Drawing.FontStyle]::Bold)
$hEyebrow.ForeColor = $cAccentHover
$hEyebrow.BackColor = [System.Drawing.Color]::Transparent
$hEyebrow.Location  = New-Object System.Drawing.Point(20, 6)
$hEyebrow.Size      = New-Object System.Drawing.Size(310, 12)
$hPanel.Controls.Add($hEyebrow)

$hTitle = New-Object System.Windows.Forms.Label
$hTitle.Text      = 'Inventario do equipamento'
$hTitle.Font      = New-CaijFont -Kind Display -Size 15.5 -Style ([System.Drawing.FontStyle]::Bold)
$hTitle.ForeColor = $cMain
$hTitle.BackColor = [System.Drawing.Color]::Transparent
$hTitle.Location  = New-Object System.Drawing.Point(20, 19)
$hTitle.Size      = New-Object System.Drawing.Size(460, 29)
$hPanel.Controls.Add($hTitle)

# Modelo (linha 2) — pill com fundo tintado e cantos arredondados
$hModel = New-Object System.Windows.Forms.Label
$hModel.Text      = $info.Modelo.ToUpper()
$hModel.Font      = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
$hModel.ForeColor = [System.Drawing.Color]::FromArgb(208, 214, 234)
$hModel.BackColor = $cCard
$hModel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$hModelW = [Math]::Min(400, ([System.Windows.Forms.TextRenderer]::MeasureText($hModel.Text, $hModel.Font)).Width + 20)
$hModel.Location  = New-Object System.Drawing.Point(20, 58)
$hModel.Size      = New-Object System.Drawing.Size($hModelW, 18)
$hPanel.Controls.Add($hModel)

# Data hora (linha 3) — ao lado do pill do modelo
$hDate = New-Object System.Windows.Forms.Label
$hDate.Text      = $dataHora
$hDate.Font      = New-Object System.Drawing.Font('Segoe UI', 7)
$hDate.ForeColor = $cDim
$hDate.BackColor = [System.Drawing.Color]::Transparent
$hDate.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$hDate.Location  = New-Object System.Drawing.Point((20 + $hModelW + 12), 58)
$hDate.Size      = New-Object System.Drawing.Size(200, 18)
$hPanel.Controls.Add($hDate)

# ---- Caixa serial (direita) ----
$sBox = New-Object System.Windows.Forms.Panel
$sBox.BackColor   = $cSurface
$sBox.Location    = New-Object System.Drawing.Point(490, 6)
$sBox.Size        = New-Object System.Drawing.Size(192, 76)
$sBox.BorderStyle = 'None'
$hPanel.Controls.Add($sBox)

$sBox.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $g.SmoothingMode = 'AntiAlias'
    # Superficie arredondada com borda fina, igual aos cards da criacao de OS.
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $r2 = 10
    $w2 = $s.Width; $h2 = $s.Height
    $path.AddArc(0, 0, $r2*2, $r2*2, 180, 90)
    $path.AddArc($w2-$r2*2, 0, $r2*2, $r2*2, 270, 90)
    $path.AddArc($w2-$r2*2, $h2-$r2*2, $r2*2, $r2*2, 0, 90)
    $path.AddArc(0, $h2-$r2*2, $r2*2, $r2*2, 90, 90)
    $path.CloseFigure()
    $bg = New-Object System.Drawing.SolidBrush($cSurface)
    $g.FillPath($bg, $path)
    $bg.Dispose()
    $pen = New-Object System.Drawing.Pen($cBorder, 1)
    $g.DrawPath($pen, $path)
    $pen.Dispose()
    $path.Dispose()
})

function Set-RoundedControl {
    param(
        [Parameter(Mandatory=$true)]$Control,
        [int]$Radius = 10
    )
    try {
        if (-not $Control.PSObject.Properties['CaijBaseCornerRadius']) {
            $Control | Add-Member -NotePropertyName CaijBaseCornerRadius -NotePropertyValue $Radius
        }
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
        [System.Drawing.Color]$Cor = ([System.Drawing.Color]::FromArgb(139, 92, 246))
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
$sLbl.ForeColor = $cMuted
$sLbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$sLbl.Location  = New-Object System.Drawing.Point(0, 10)
$sLbl.Size      = New-Object System.Drawing.Size(192, 14)
$sBox.Controls.Add($sLbl)

# Valor serial (grande e destacado)
$sVal = New-Object System.Windows.Forms.Label
$sVal.Text      = $info.Serial
$sVal.Font      = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
$sVal.ForeColor = [System.Drawing.Color]::FromArgb(244, 241, 255)
$sVal.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$sVal.Location  = New-Object System.Drawing.Point(0, 22)
$sVal.Size      = New-Object System.Drawing.Size(192, 25)
$sBox.Controls.Add($sVal)

# Divisor
$sDivider = New-Object System.Windows.Forms.Panel
$sDivider.BackColor = $cBorder
$sDivider.Location  = New-Object System.Drawing.Point(24, 51)
$sDivider.Size      = New-Object System.Drawing.Size(144, 1)
$sBox.Controls.Add($sDivider)

# Numero da OS centralizado no rodape da caixa
$script:osValLabel = New-Object System.Windows.Forms.Label
$script:osValLabel.Text      = ('C{0:D6}' -f [int]$script:osNumero)
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
$osSyncBtn.ForeColor = $cAccentHover
$osSyncBtn.BackColor = $cSurface
$osSyncBtn.FlatStyle = 'Flat'
$osSyncBtn.FlatAppearance.BorderSize = 0
$osSyncBtn.FlatAppearance.MouseOverBackColor = $cCard
$osSyncBtn.FlatAppearance.MouseDownBackColor = $cBorder
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
    return ('C{0:D6}' -f $Numero)
}

function Register-OsNumeroControl {
    param([System.Windows.Forms.Control]$Control)
    if (-not $Control -or $Control.IsDisposed) { return }
    if (-not $script:osNumeroControls) {
        $script:osNumeroControls = New-Object System.Collections.ArrayList
    }
    if (-not $script:osNumeroControls.Contains($Control)) {
        [void]$script:osNumeroControls.Add($Control)
    }
    $Control.Text = (Format-OsCodigo -Numero $script:osNumero)
}

function Update-OsNumeroInterface {
    $ativos = New-Object System.Collections.ArrayList
    foreach ($control in @($script:osNumeroControls)) {
        try {
            if ($control -and -not $control.IsDisposed) {
                $control.Text = (Format-OsCodigo -Numero $script:osNumero)
                [void]$ativos.Add($control)
            }
        } catch {}
    }
    $script:osNumeroControls = $ativos
    try {
        if ($script:osPreviewRefreshAction) {
            & $script:osPreviewRefreshAction
        }
    } catch {}
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
    Update-OsNumeroInterface
    Save-OsNumero -Numero $script:osNumero
}

Register-OsNumeroControl -Control $script:osValLabel

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
    param([System.Windows.Forms.Form]$Owner)

    $osSugerida = Try-ReadOsFromClipboard
    $sugeridaClipboard = [bool]$osSugerida
    if (-not $osSugerida) { $osSugerida = $script:osNumero }

    $osDialog = New-Object System.Windows.Forms.Form
    $osDialog.Text = 'Alterar ordem de servico'
    $osDialog.ClientSize = New-Object System.Drawing.Size(520, 318)
    $osDialog.StartPosition = 'CenterParent'
    $osDialog.BackColor = [System.Drawing.Color]::FromArgb(7, 9, 17)
    $osDialog.ForeColor = [System.Drawing.Color]::FromArgb(240, 242, 248)
    $osDialog.FormBorderStyle = 'None'
    $osDialog.ShowInTaskbar = $false
    $osDialog.MaximizeBox = $false
    $osDialog.MinimizeBox = $false
    $osDialog.KeyPreview = $true
    Set-DoubleBuffered $osDialog
    Set-RoundedControl -Control $osDialog -Radius 12
    $osDialog.Add_SizeChanged({ Set-RoundedControl -Control $this -Radius 12 })
    $osDialog.Add_Paint({
        param($s, $e)
        $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $border = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(42, 46, 63), 1)
        $e.Graphics.DrawRectangle($border, 0, 0, ($s.ClientSize.Width - 1), ($s.ClientSize.Height - 1))
        $border.Dispose()
    })

    $osHeader = New-Object System.Windows.Forms.Panel
    $osHeader.Location = New-Object System.Drawing.Point(0, 0)
    $osHeader.Size = New-Object System.Drawing.Size(520, 78)
    $osHeader.BackColor = [System.Drawing.Color]::FromArgb(15, 18, 29)
    [void]$osDialog.Controls.Add($osHeader)
    $osHeader.Add_Paint({
        param($s, $e)
        $line = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(42, 46, 63), 1)
        $e.Graphics.DrawLine($line, 0, ($s.Height - 1), $s.Width, ($s.Height - 1))
        $line.Dispose()
    })

    $osHeaderRail = New-Object System.Windows.Forms.Panel
    $osHeaderRail.Location = New-Object System.Drawing.Point(0, 0)
    $osHeaderRail.Size = New-Object System.Drawing.Size(0, 78)
    $osHeaderRail.BackColor = [System.Drawing.Color]::FromArgb(94, 106, 210)
    [void]$osHeader.Controls.Add($osHeaderRail)

    $osEyebrow = New-Object System.Windows.Forms.Label
    $osEyebrow.Text = 'ETIQUETA / ORDEM DE SERVICO'
    $osEyebrow.Font = New-Object System.Drawing.Font('Segoe UI', 6.8, [System.Drawing.FontStyle]::Bold)
    $osEyebrow.ForeColor = [System.Drawing.Color]::FromArgb(112, 124, 228)
    $osEyebrow.Location = New-Object System.Drawing.Point(22, 11)
    $osEyebrow.Size = New-Object System.Drawing.Size(300, 14)
    [void]$osHeader.Controls.Add($osEyebrow)

    $osTitle = New-Object System.Windows.Forms.Label
    $osTitle.Text = 'Alterar OS da etiqueta'
    $osTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 15, [System.Drawing.FontStyle]::Bold)
    $osTitle.ForeColor = [System.Drawing.Color]::FromArgb(240, 242, 248)
    $osTitle.Location = New-Object System.Drawing.Point(20, 29)
    $osTitle.Size = New-Object System.Drawing.Size(350, 30)
    [void]$osHeader.Controls.Add($osTitle)

    $osSubtitle = New-Object System.Windows.Forms.Label
    $osSubtitle.Text = 'Use o numero gerado no Alterdata'
    $osSubtitle.Font = New-Object System.Drawing.Font('Segoe UI', 7.5)
    $osSubtitle.ForeColor = [System.Drawing.Color]::FromArgb(166, 170, 184)
    $osSubtitle.Location = New-Object System.Drawing.Point(23, 57)
    $osSubtitle.Size = New-Object System.Drawing.Size(300, 14)
    [void]$osHeader.Controls.Add($osSubtitle)

    $osClose = New-Object System.Windows.Forms.Button
    $osClose.Text = 'X'
    $osClose.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
    $osClose.ForeColor = [System.Drawing.Color]::FromArgb(166, 170, 184)
    $osClose.BackColor = $osHeader.BackColor
    $osClose.FlatStyle = 'Flat'
    $osClose.FlatAppearance.BorderSize = 0
    $osClose.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(21, 24, 38)
    $osClose.Location = New-Object System.Drawing.Point(486, 7)
    $osClose.Size = New-Object System.Drawing.Size(26, 26)
    $osClose.Cursor = [System.Windows.Forms.Cursors]::Hand
    $osClose.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    [void]$osHeader.Controls.Add($osClose)

    $osHint = New-Object System.Windows.Forms.Label
    $osHint.Text = if ($sugeridaClipboard) {
        'Numero identificado na area de transferencia. Confira antes de aplicar.'
    } else {
        'Digite somente os numeros da ordem de servico.'
    }
    $osHint.Font = New-Object System.Drawing.Font('Segoe UI', 8)
    $osHint.ForeColor = [System.Drawing.Color]::FromArgb(166, 170, 184)
    $osHint.Location = New-Object System.Drawing.Point(24, 94)
    $osHint.Size = New-Object System.Drawing.Size(470, 34)
    [void]$osDialog.Controls.Add($osHint)

    $osField = New-Object System.Windows.Forms.Panel
    $osField.Location = New-Object System.Drawing.Point(24, 134)
    $osField.Size = New-Object System.Drawing.Size(472, 72)
    $osField.BackColor = [System.Drawing.Color]::FromArgb(21, 24, 38)
    [void]$osDialog.Controls.Add($osField)
    Set-RoundedControl -Control $osField -Radius 8

    $osFieldRail = New-Object System.Windows.Forms.Panel
    $osFieldRail.Location = New-Object System.Drawing.Point(0, 0)
    $osFieldRail.Size = New-Object System.Drawing.Size(4, 72)
    $osFieldRail.BackColor = [System.Drawing.Color]::FromArgb(94, 106, 210)
    [void]$osField.Controls.Add($osFieldRail)

    $osFieldLabel = New-Object System.Windows.Forms.Label
    $osFieldLabel.Text = 'NUMERO DA OS'
    $osFieldLabel.Font = New-Object System.Drawing.Font('Segoe UI', 6.8, [System.Drawing.FontStyle]::Bold)
    $osFieldLabel.ForeColor = [System.Drawing.Color]::FromArgb(166, 170, 184)
    $osFieldLabel.Location = New-Object System.Drawing.Point(16, 9)
    $osFieldLabel.Size = New-Object System.Drawing.Size(150, 14)
    [void]$osField.Controls.Add($osFieldLabel)

    $osPrefix = New-Object System.Windows.Forms.Label
    $osPrefix.Text = 'C'
    $osPrefix.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 13, [System.Drawing.FontStyle]::Bold)
    $osPrefix.ForeColor = [System.Drawing.Color]::FromArgb(112, 124, 228)
    $osPrefix.Location = New-Object System.Drawing.Point(16, 33)
    $osPrefix.Size = New-Object System.Drawing.Size(22, 26)
    [void]$osField.Controls.Add($osPrefix)

    $osInput = New-Object System.Windows.Forms.TextBox
    $osInput.Text = $osSugerida.ToString('D6')
    $osInput.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 13, [System.Drawing.FontStyle]::Bold)
    $osInput.BackColor = [System.Drawing.Color]::FromArgb(15, 18, 29)
    $osInput.ForeColor = [System.Drawing.Color]::FromArgb(240, 242, 248)
    $osInput.BorderStyle = 'FixedSingle'
    $osInput.Location = New-Object System.Drawing.Point(42, 31)
    $osInput.Size = New-Object System.Drawing.Size(408, 30)
    $osInput.MaxLength = 8
    [void]$osField.Controls.Add($osInput)

    $osValidation = New-Object System.Windows.Forms.Label
    $osValidation.Text = ''
    $osValidation.Font = New-Object System.Drawing.Font('Segoe UI', 7.5, [System.Drawing.FontStyle]::Bold)
    $osValidation.ForeColor = [System.Drawing.Color]::FromArgb(236, 112, 124)
    $osValidation.Location = New-Object System.Drawing.Point(26, 211)
    $osValidation.Size = New-Object System.Drawing.Size(460, 18)
    [void]$osDialog.Controls.Add($osValidation)

    $osCancel = New-Object System.Windows.Forms.Button
    $osCancel.Text = 'Cancelar'
    $osCancel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
    $osCancel.ForeColor = [System.Drawing.Color]::FromArgb(240, 242, 248)
    $osCancel.BackColor = [System.Drawing.Color]::FromArgb(21, 24, 38)
    $osCancel.FlatStyle = 'Flat'
    $osCancel.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(42, 46, 63)
    $osCancel.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(31, 35, 51)
    $osCancel.Location = New-Object System.Drawing.Point(270, 252)
    $osCancel.Size = New-Object System.Drawing.Size(100, 40)
    $osCancel.Cursor = [System.Windows.Forms.Cursors]::Hand
    $osCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    [void]$osDialog.Controls.Add($osCancel)
    Set-RoundedControl -Control $osCancel -Radius 7

    $osApply = New-Object System.Windows.Forms.Button
    $osApply.Text = 'Aplicar OS'
    $osApply.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9, [System.Drawing.FontStyle]::Bold)
    $osApply.ForeColor = [System.Drawing.Color]::White
    $osApply.BackColor = [System.Drawing.Color]::FromArgb(94, 106, 210)
    $osApply.FlatStyle = 'Flat'
    $osApply.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(94, 106, 210)
    $osApply.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(112, 124, 228)
    $osApply.Location = New-Object System.Drawing.Point(380, 252)
    $osApply.Size = New-Object System.Drawing.Size(116, 40)
    $osApply.Cursor = [System.Windows.Forms.Cursors]::Hand
    [void]$osDialog.Controls.Add($osApply)
    Set-RoundedControl -Control $osApply -Radius 7

    $osInput.Add_KeyPress({
        if (-not [char]::IsControl($_.KeyChar) -and -not [char]::IsDigit($_.KeyChar)) {
            $_.Handled = $true
        }
    })
    $osInput.Add_TextChanged({
        $osValidation.Text = ''
        $osFieldRail.BackColor = [System.Drawing.Color]::FromArgb(94, 106, 210)
    })
    $osApply.Add_Click({
        $valorOs = $osInput.Text.Trim()
        if ($valorOs -notmatch '^\d{2,8}$') {
            $osValidation.Text = 'Digite de 2 a 8 numeros para continuar.'
            $osFieldRail.BackColor = [System.Drawing.Color]::FromArgb(236, 112, 124)
            $osInput.Focus() | Out-Null
            $osInput.SelectAll()
            return
        }
        $osDialog.Tag = [int]$valorOs
        $osDialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $osDialog.Close()
    })

    $osDialog.AcceptButton = $osApply
    $osDialog.CancelButton = $osCancel
    $osDialog.Add_Shown({
        $osInput.Focus() | Out-Null
        $osInput.SelectAll()
    })

    $osDrag = @{ Active = $false; Mouse = [System.Drawing.Point]::Empty; Form = [System.Drawing.Point]::Empty }
    $osHeader.Add_MouseDown({
        if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            $osDrag.Active = $true
            $osDrag.Mouse = [System.Windows.Forms.Cursor]::Position
            $osDrag.Form = $osDialog.Location
        }
    })
    $osHeader.Add_MouseMove({
        if ($osDrag.Active) {
            $agora = [System.Windows.Forms.Cursor]::Position
            $osDialog.Location = New-Object System.Drawing.Point(
                ($osDrag.Form.X + $agora.X - $osDrag.Mouse.X),
                ($osDrag.Form.Y + $agora.Y - $osDrag.Mouse.Y)
            )
        }
    })
    $osHeader.Add_MouseUp({ $osDrag.Active = $false })

    Set-CaijWindowsTypography -Root $osDialog
    $resultadoOs = if ($Owner) { $osDialog.ShowDialog($Owner) } else { $osDialog.ShowDialog() }
    $novoNumeroOs = $osDialog.Tag
    $osDialog.Dispose()
    if ($resultadoOs -eq [System.Windows.Forms.DialogResult]::OK -and $novoNumeroOs) {
        Set-OsNumeroAtual -Numero ([int]$novoNumeroOs) -Fonte 'manual'
        return $true
    }
    return $false
}

function Get-MonitorTamanhoNumero {
    param([string]$Valor)

    $texto = if ($Valor) { $Valor.Trim() } else { '' }
    if ($texto -match '(?i)(\d{1,3}(?:[.,]\d)?)\s*(?:"|Â?°|polegadas?)?') {
        return ($matches[1] -replace '\.', ',')
    }
    return ''
}

function Format-MonitorTamanhoEtiqueta {
    param([string]$Valor)

    $numero = Get-MonitorTamanhoNumero -Valor $Valor
    if (-not $numero) { return '' }
    return "$numero polegadas"
}

function Test-DesktopProduto {
    param([string]$Descricao)

    $texto = (([string]$Descricao) -replace '\s+', ' ').Trim()
    return ($texto -match '(?i)\b(?:CPU|DESKTOP|MINI\s+DESKTOP|COMPUTADOR\s+DESKTOP)\b')
}

function Test-CelularProduto {
    param([string]$Descricao)

    $texto = (([string]$Descricao) -replace '\s+', ' ').Trim()
    return ($texto -match '(?i)\b(?:SMARTPHONE|CELULAR|TELEFONE|IPHONE|IPAD|TABLET|SAMSUNG|GALAXY|MOTOROLA|XIAOMI)\b')
}

function Get-ModeloEtiquetaProduto {
    param(
        [string]$Descricao,
        [string]$CodigoProduto = ''
    )

    $modelo = (([string]$Descricao) -replace '\s+', ' ').Trim()
    if ($CodigoProduto) {
        $codigoEscapado = [regex]::Escape($CodigoProduto.Trim())
        $modelo = ($modelo -replace ("(?i)^\s*{0}\s*(?:[-:|]\s*)?" -f $codigoEscapado), '').Trim()
    }
    # O Altertag pode antepor a categoria comercial ao nome do aparelho.
    # Ela serve para classificar o produto, mas nao faz parte do modelo impresso.
    $modelo = ($modelo -replace '(?i)^\s*(?:SMARTPHONE|CELULAR|TELEFONE|TABLET)\s*(?:[-:|]\s*)?', '').Trim()
    # Protege cadastros antigos em que o codigo Txxx foi salvo junto do nome.
    $modelo = ($modelo -replace '(?i)^\s*T\d{3}(?:-+)?\s*(?:[-:|]\s*)?(?=(?:CPU|DESKTOP|MINI\s+DESKTOP|COMPUTADOR\s+DESKTOP)\b)', '').Trim()
    return $modelo
}

function Apply-OsAltertagNaEtiqueta {
    param($Ordem)

    if (-not $Ordem) { return }
    $equipamentoOs = Get-ModeloEtiquetaProduto -Descricao (([string]$Ordem.equipamento) -replace 'Â°|°', '')
    $serialOs = ([string]$Ordem.garantia).Trim()
    $referenciaOs = ([string]$Ordem.referencia).Trim().ToUpperInvariant()
    if ($equipamentoOs) { $script:modeloEtiqueta = $equipamentoOs }
    if ($serialOs) { $script:serialEtiqueta = $serialOs }

    foreach ($gradeOpcaoOs in @(@(Get-CaijGradeOptions) + @(Get-CaijGradeOptions -EquipmentType 'Celular') | Select-Object -Unique)) {
        if ((Format-CaijGradeReference $gradeOpcaoOs).ToUpperInvariant() -eq $referenciaOs) {
            $script:gradeAtual = $gradeOpcaoOs
            break
        }
    }

    if (Test-CelularProduto -Descricao $equipamentoOs) {
        $script:tipoEtiqueta = 'Celular'
        $script:monitorTamanhoEtiqueta = ''
        $script:monitorEntradasEtiqueta = ''
        $script:celularImeiEtiqueta = ''
        $script:cpuEtiqueta = ''
        $script:memEtiqueta = ''
        $script:ramEtiqueta = ''
        $script:gpuEtiqueta = ''
        $script:bateriaEtiqueta = $null
        $script:modoManualEtiqueta = $true
    } elseif ($equipamentoOs -match '(?i)\bmonitor\b') {
        $script:tipoEtiqueta = 'Monitor'
        $script:monitorTamanhoEtiqueta = Format-MonitorTamanhoEtiqueta -Valor $equipamentoOs
        $script:monitorEntradasEtiqueta = ''
        $script:celularImeiEtiqueta = ''
        $script:cpuEtiqueta = ''
        $script:memEtiqueta = ''
        $script:ramEtiqueta = ''
        $script:gpuEtiqueta = ''
        $script:bateriaEtiqueta = $null
        $script:modoManualEtiqueta = $true
        $script:abrirManualPorOsSelecionada = $true
    } elseif (Test-DesktopProduto -Descricao $equipamentoOs) {
        $script:tipoEtiqueta = 'Desktop'
        $script:monitorTamanhoEtiqueta = ''
        $script:monitorEntradasEtiqueta = ''
        $script:celularImeiEtiqueta = ''
        $script:cpuEtiqueta = ''
        $script:memEtiqueta = ''
        $script:ramEtiqueta = ''
        $script:gpuEtiqueta = ''
        $script:bateriaEtiqueta = $null
        $script:modoManualEtiqueta = $true
    }
}

function Apply-CadastroOsEtiquetaNaImpressao {
    param($Etiqueta)

    if (-not $Etiqueta) { return }

    $tipoCadastro = [string]$Etiqueta.tipoEquipamento
    if ($tipoCadastro -eq 'Desktop') {
        $script:tipoEtiqueta = 'Desktop'
        $script:modeloEtiqueta = Get-ModeloEtiquetaProduto -Descricao ([string]$Etiqueta.modelo) -CodigoProduto ([string]$Etiqueta.produtoCodigo)
        $script:serialEtiqueta = [string]$Etiqueta.serial
        $script:celularImeiEtiqueta = ''
        $script:bateriaEtiqueta = $null
        $script:monitorTamanhoEtiqueta = ''
        $script:monitorEntradasEtiqueta = ''
        $script:cpuEtiqueta = [string]$Etiqueta.cpu
        $script:memEtiqueta = [string]$Etiqueta.armazenamento
        $script:ramEtiqueta = [string]$Etiqueta.ram
        $script:gpuEtiqueta = [string]$Etiqueta.gpu
        $script:modoManualEtiqueta = $true
        return
    }

    if ($tipoCadastro -ne 'Celular') { return }

    $script:tipoEtiqueta = 'Celular'
    $script:modeloEtiqueta = Get-ModeloEtiquetaProduto -Descricao ([string]$Etiqueta.modelo) -CodigoProduto ([string]$Etiqueta.produtoCodigo)
    $script:serialEtiqueta = [string]$Etiqueta.serial
    $script:celularImeiEtiqueta = [string]$Etiqueta.imei
    $script:bateriaEtiqueta = [string]$Etiqueta.bateria
    $script:monitorTamanhoEtiqueta = ''
    $script:monitorEntradasEtiqueta = ''
    $script:cpuEtiqueta = ''
    $script:memEtiqueta = [string]$Etiqueta.armazenamento
    $script:ramEtiqueta = ''
    $script:gpuEtiqueta = ''
    $script:modoManualEtiqueta = $true
}

$script:osValLabel.Add_Click({ Prompt-OsManual -Owner $form | Out-Null })

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
        ([System.Drawing.Color]::FromArgb(174, 165, 194)) `
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
        $ed.BackColor = [System.Drawing.Color]::FromArgb(8, 12, 27)
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
        $edSub.ForeColor = [System.Drawing.Color]::FromArgb(145, 137, 163)
        $edSub.Location = New-Object System.Drawing.Point(14, 32)
        $edSub.Size = New-Object System.Drawing.Size(420, 14)
        [void]$edHead.Controls.Add($edSub)

        function Ed-Field {
            param([string]$lbl, [string]$val, [int]$y)
            $lbF = New-Object System.Windows.Forms.Label
            $lbF.Text = $lbl
            $lbF.Font = New-Object System.Drawing.Font('Segoe UI', 7.5, [System.Drawing.FontStyle]::Bold)
            $lbF.ForeColor = [System.Drawing.Color]::FromArgb(145, 137, 163)
            $lbF.Location = New-Object System.Drawing.Point(20, $y)
            $lbF.Size = New-Object System.Drawing.Size(420, 14)
            [void]$ed.Controls.Add($lbF)
            $tb = New-Object System.Windows.Forms.TextBox
            $tb.Text = $val
            $tb.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
            $tb.ForeColor = [System.Drawing.Color]::FromArgb(239, 233, 255)
            $tb.BackColor = [System.Drawing.Color]::FromArgb(19, 17, 40)
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

        Set-CaijWindowsTypography -Root $ed
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
    Set-CaijWindowsTypography -Root $dlg
    $res = $dlg.ShowDialog()
    if ($res -eq [System.Windows.Forms.DialogResult]::Retry) {
        return [bool](Prompt-OsManual -Owner $form)
    }
    if ($res -ne [System.Windows.Forms.DialogResult]::OK -or -not $script:selectedAltertagOs) { return $false }

    $sel = $script:selectedAltertagOs
    Set-OsNumeroAtual -Numero ([int]$sel.numero) -Fonte 'altertag'
    $script:altertagOsAtual = $sel
    Apply-OsAltertagNaEtiqueta -Ordem $sel
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
    $f.BackColor = [System.Drawing.Color]::FromArgb(8, 12, 27)
    $f.FormBorderStyle = 'FixedDialog'
    $f.MaximizeBox = $false; $f.MinimizeBox = $false

    $lHead = New-Object System.Windows.Forms.Label
    $lHead.Text = 'Endereco do servidor CAIJ'
    $lHead.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $lHead.ForeColor = [System.Drawing.Color]::FromArgb(139, 92, 246)
    $lHead.Location = New-Object System.Drawing.Point(16, 14)
    $lHead.Size = New-Object System.Drawing.Size(410, 22)
    [void]$f.Controls.Add($lHead)

    $lHint = New-Object System.Windows.Forms.Label
    $lHint.Text = 'Digite o IP ou URL completa do servidor (ex: http://192.168.15.127:9100)'
    $lHint.Font = New-Object System.Drawing.Font('Segoe UI', 8)
    $lHint.ForeColor = [System.Drawing.Color]::FromArgb(139, 130, 158)
    $lHint.Location = New-Object System.Drawing.Point(16, 40)
    $lHint.Size = New-Object System.Drawing.Size(420, 16)
    [void]$f.Controls.Add($lHint)

    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Text = $urlAtual
    $tb.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $tb.ForeColor = [System.Drawing.Color]::FromArgb(239, 233, 255)
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

    Set-CaijWindowsTypography -Root $f
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
$scroll.BackColor  = $cBg
$form.Controls.Add($scroll)

$script:py = 10
$script:sectionNumber = 0
$CW = 660  # content width

# ---- secao ----
function Add-Sec {
    param([string]$label, [System.Drawing.Color]$cor)
    $script:py += 4
    $script:sectionRowIndex = 0
    $script:sectionNumber++
    $sp = New-Object System.Windows.Forms.Panel
    $sp.BackColor   = $cSurface
    $sp.Location    = New-Object System.Drawing.Point(16, $script:py)
    $sp.Size        = New-Object System.Drawing.Size($CW, 22)
    $sp.BorderStyle = 'None'
    [void]$scroll.Controls.Add($sp)
    Set-RoundedControl -Control $sp -Radius 4

    $abar = New-Object System.Windows.Forms.Panel
    $abar.BackColor = $cor
    $abar.Location  = New-Object System.Drawing.Point(0, 3)
    $abar.Size      = New-Object System.Drawing.Size(4, 16)
    $abar.Visible   = $false
    [void]$sp.Controls.Add($abar)

    $indexBadge = New-Object System.Windows.Forms.Label
    $indexBadge.Text = ('{0:D2}' -f $script:sectionNumber)
    $indexBadge.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 7, [System.Drawing.FontStyle]::Bold)
    $indexBadge.ForeColor = $cAccentHover
    $indexBadge.BackColor = $cCard
    $indexBadge.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $indexBadge.Location = New-Object System.Drawing.Point(10, 3)
    $indexBadge.Size = New-Object System.Drawing.Size(28, 16)
    [void]$sp.Controls.Add($indexBadge)
    Set-RoundedControl -Control $indexBadge -Radius 3

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text      = $label.ToUpper()
    $lbl.Font      = New-Object System.Drawing.Font('Segoe UI Semibold', 7.2, [System.Drawing.FontStyle]::Bold)
    $lbl.ForeColor = $cMuted
    $lbl.Location  = New-Object System.Drawing.Point(46, 4)
    $lbl.Size      = New-Object System.Drawing.Size(204, 15)
    [void]$sp.Controls.Add($lbl)

    $hairline = New-Object System.Windows.Forms.Panel
    $hairline.BackColor = $cBorder
    $hairline.Location = New-Object System.Drawing.Point(250, 10)
    $hairline.Size = New-Object System.Drawing.Size(($CW - 264), 1)
    [void]$sp.Controls.Add($hairline)
    $script:py += 24
}

# ---- linha simples: label esquerda | valor direita, altura compacta ----
function Add-Row {
    param([string]$k, [string]$v, [System.Drawing.Color]$vc, [System.Drawing.Color]$ac)
    if (-not $vc) { $vc = $cMain }
    if (-not $ac) { $ac = $cBorder }

    $p = New-Object System.Windows.Forms.Panel
    $rowBack = $cCard
    $p.BackColor   = $rowBack
    $p.Location    = New-Object System.Drawing.Point(16, $script:py)
    $p.Size        = New-Object System.Drawing.Size($CW, 26)
    $p.BorderStyle = 'None'
    [void]$scroll.Controls.Add($p)
    Set-RoundedControl -Control $p -Radius 6
    $p.Add_Paint({
        $rowPen = New-Object System.Drawing.Pen($cBorder, 1)
        $_.Graphics.DrawRectangle($rowPen, 0, 0, ($this.Width - 1), ($this.Height - 1))
        $rowPen.Dispose()
    })

    $abar = New-Object System.Windows.Forms.Panel
    $abar.BackColor = $ac
    $abar.Location  = New-Object System.Drawing.Point(0, 5)
    $abar.Size      = New-Object System.Drawing.Size(3, 16)
    $abar.Visible   = $false
    [void]$p.Controls.Add($abar)

    $lk = New-Object System.Windows.Forms.Label
    $lk.Text      = $k.ToUpperInvariant()
    $lk.Font      = New-Object System.Drawing.Font('Segoe UI Semibold', 7.4)
    $lk.ForeColor = $cMuted
    $lk.Location  = New-Object System.Drawing.Point(12, 5)
    $lk.Size      = New-Object System.Drawing.Size(132, 16)
    [void]$p.Controls.Add($lk)

    $keyDivider = New-Object System.Windows.Forms.Panel
    $keyDivider.BackColor = $cBorder
    $keyDivider.Location = New-Object System.Drawing.Point(144, 5)
    $keyDivider.Size = New-Object System.Drawing.Size(1, 16)
    [void]$p.Controls.Add($keyDivider)

    $lv = New-Object System.Windows.Forms.Label
    $lv.Text         = $v
    $lv.Font         = New-Object System.Drawing.Font('Segoe UI Semibold', 8.8, [System.Drawing.FontStyle]::Bold)
    $lv.ForeColor    = $vc
    $lv.Location     = New-Object System.Drawing.Point(150, 5)
    $lv.Size         = New-Object System.Drawing.Size(494, 17)
    $lv.AutoEllipsis = $true
    [void]$p.Controls.Add($lv)

    $script:sectionRowIndex++
    $script:py += 27
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
        $p.BackColor   = $cCard
        $p.Location    = New-Object System.Drawing.Point([int]$side.X, $script:py)
        $p.Size        = New-Object System.Drawing.Size($half, 26)
        $p.BorderStyle = 'None'
        [void]$scroll.Controls.Add($p)
        Set-RoundedControl -Control $p -Radius 6
        $p.Add_Paint({
            $rowPen = New-Object System.Drawing.Pen($cBorder, 1)
            $_.Graphics.DrawRectangle($rowPen, 0, 0, ($this.Width - 1), ($this.Height - 1))
            $rowPen.Dispose()
        })

        $abar = New-Object System.Windows.Forms.Panel
        $abar.BackColor = $ac
        $abar.Location  = New-Object System.Drawing.Point(0, 5)
        $abar.Size      = New-Object System.Drawing.Size(3, 16)
        $abar.Visible   = $false
        [void]$p.Controls.Add($abar)

        $lk = New-Object System.Windows.Forms.Label
        $lk.Text      = ([string]$side.k).ToUpperInvariant()
        $lk.Font      = New-Object System.Drawing.Font('Segoe UI Semibold', 7.4)
        $lk.ForeColor = $cMuted
        $lk.Location  = New-Object System.Drawing.Point(12, 5)
        $lk.Size      = New-Object System.Drawing.Size(86, 16)
        [void]$p.Controls.Add($lk)

        $keyDivider = New-Object System.Windows.Forms.Panel
        $keyDivider.BackColor = $cBorder
        $keyDivider.Location = New-Object System.Drawing.Point(94, 5)
        $keyDivider.Size = New-Object System.Drawing.Size(1, 16)
        [void]$p.Controls.Add($keyDivider)

        $lv = New-Object System.Windows.Forms.Label
        $lv.Text         = [string]$side.v
        $lv.Font         = New-Object System.Drawing.Font('Segoe UI Semibold', 8.8, [System.Drawing.FontStyle]::Bold)
        $lv.ForeColor    = [System.Drawing.Color]$side.c
        $lv.Location     = New-Object System.Drawing.Point(100, 5)
        $lv.Size         = New-Object System.Drawing.Size(($half - 108), 17)
        $lv.AutoEllipsis = $true
        [void]$p.Controls.Add($lv)
    }

    $script:sectionRowIndex++
    $script:py += 27
}

function Gap { $script:py += 6 }

# Valores tecnicos usam uma unica voz visual; cor permanece apenas para status semantico.
$cCpuValue = $cMain
$cRamValue = $cMain
$cStorageValue = $cMain
$cGpuValue = $cMain

# ---- SECAO 1 ----
Add-Sec 'Processamento e memoria' $cAccent
Add-Row 'Processador' $info.CPU $cCpuValue $cAccent
Add-Row2 'Nucleos' $info.Nucleos $cMain 'Clock max.' $info.ClockMax $cMain $cAccent
Add-Row2 'Memoria' $info.RAM $cRamValue 'Modulos' $info.RAMMods $cMuted $cAccent
Gap

# ---- SECAO 2 ----
Add-Sec 'Armazenamento e video' $cAccent
foreach ($linha in ($info.Discos -split $NL)) {
    if ($linha.Trim() -ne '') { Add-Row 'Armazenamento' $linha $cStorageValue $cAccent }
}
Add-Row 'Placa de Video' $info.GPU $cGpuValue $cAccent
Add-Row 'Resolucao' $info.Tela $cMain $cAccent
Gap

# ---- SECAO 3 ----
Add-Sec $(if ($info.MostrarBateria) { 'Sistema e bateria' } else { 'Sistema operacional' }) $cAccent
Add-Row 'Windows' $info.Windows $cMain $cAccent
# Hostname removido para manter layout mais limpo
if ($info.MostrarBateria) {
    $corBat = $cMain
    if     ($info.BatSaude -match 'Excelente|Excellent') { $corBat = $cGreen }
    elseif ($info.BatSaude -match 'Boa|Good')            { $corBat = $cYellow }
    elseif ($info.BatSaude -match 'Regular|Fair')        { $corBat = $cOrange }
    elseif ($info.BatSaude -match 'Ruim|Poor')           { $corBat = $cRed }
    Add-Row 'Bateria' $info.BatSaude $corBat $cAccent

    if ($info.BatSaude -match '\((\d+)%\)') {
        $pct  = [int]$Matches[1]
        $barW = [math]::Max(1, [int](($CW * $pct) / 100))
        $barTrack = New-Object System.Windows.Forms.Panel
        $barTrack.BackColor = $cCard
        $barTrack.Location = New-Object System.Drawing.Point(16, $script:py)
        $barTrack.Size = New-Object System.Drawing.Size($CW, 6)
        $scroll.Controls.Add($barTrack)
        Set-RoundedControl -Control $barTrack -Radius 3

        $bfg  = New-Object System.Windows.Forms.Panel
        $bfg.BackColor = $corBat
        $bfg.Location  = New-Object System.Drawing.Point(0, 0)
        $bfg.Size      = New-Object System.Drawing.Size($barW, 6)
        $barTrack.Controls.Add($bfg)
        Set-RoundedControl -Control $bfg -Radius 3
        $script:py += 8
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
$actBar.BackColor = $cSurface
$actBar.Location  = New-Object System.Drawing.Point(0, $actY)
$actBarH = 50
$actBar.Size      = New-Object System.Drawing.Size($W, $actBarH)
$form.Controls.Add($actBar)

$actBar.Add_Paint({
    param($s, $e)
    $pen = New-Object System.Drawing.Pen($cBorder, 1)
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
    $b.FlatAppearance.BorderColor = $cBorder
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
    $borderH = $cAccent
    $b.Add_MouseEnter({
        $this.BackColor = $bgHov
        $this.ForeColor = [System.Drawing.Color]::White
        $this.FlatAppearance.BorderColor = $borderH
    }.GetNewClosure())
    $b.Add_MouseLeave({
        $this.BackColor = $bgN
        $this.ForeColor = $fgN
        $this.FlatAppearance.BorderColor = $borderN
    }.GetNewClosure())
    Set-RoundedControl -Control $b -Radius 8
    $b.Add_SizeChanged({ Set-RoundedControl -Control $this -Radius 8 })
    $actBar.Controls.Add($b)
    return $b
}

$bY1 = 8
$bH  = 34
$g   = 6

$tooltip = New-Object System.Windows.Forms.ToolTip
$tooltip.BackColor = [System.Drawing.Color]::FromArgb(20, 30, 44)
$tooltip.ForeColor = [System.Drawing.Color]::White
$tooltip.InitialDelay = 400
$tooltip.ReshowDelay  = 200

$fBtn  = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5, [System.Drawing.FontStyle]::Bold)
$fBtnL = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5, [System.Drawing.FontStyle]::Bold)

# Uma unica linha — diagnostico, cadastro e impressao
$b2W1 = 180
$b2W2 = 236
$b2W3 = [int](676 - $b2W1 - $b2W2 - (2 * $g))
$b2X2 = 12 + $b2W1 + $g
$b2X3 = $b2X2 + $b2W2 + $g

$btnTestes = New-Btn ([string][char]0x26A1 + '  Testes') 12 $bY1 $b2W1 $bH `
    ([System.Drawing.Color]::FromArgb(21, 24, 38)) `
    ([System.Drawing.Color]::FromArgb(240, 242, 248)) `
    ([System.Drawing.Color]::FromArgb(31, 35, 52)) `
    $fBtnL
$tooltip.SetToolTip($btnTestes, 'Abre a central completa de testes')

$btnCadastrarOs = New-Btn ('+  Criar OS') $b2X2 $bY1 $b2W2 $bH `
    ([System.Drawing.Color]::FromArgb(21, 24, 38)) `
    ([System.Drawing.Color]::FromArgb(240, 242, 248)) `
    ([System.Drawing.Color]::FromArgb(31, 35, 52)) `
    $fBtnL
$tooltip.SetToolTip($btnCadastrarOs, 'Abre a preparacao do cadastro da OS pelo Altertag')

$btnImprimir = New-Btn ([string][char]0x2399 + '  Imprimir etiqueta') $b2X3 $bY1 $b2W3 $bH `
    ([System.Drawing.Color]::FromArgb(94, 106, 210)) `
    ([System.Drawing.Color]::White) `
    ([System.Drawing.Color]::FromArgb(112, 124, 228)) `
    $fBtnL
$tooltip.SetToolTip($btnImprimir, 'Abre a previa e envia a etiqueta para a impressora')

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
        [string]$Localizacao,
        [string]$Observacao
    )

    $formConfirm = New-Object System.Windows.Forms.Form
    $formConfirm.Text = 'Confirmar cadastro'
    $formConfirm.ClientSize = New-Object System.Drawing.Size(600, 548)
    $formConfirm.StartPosition = 'CenterParent'
    $formConfirm.BackColor = [System.Drawing.Color]::FromArgb(5, 8, 20)
    $formConfirm.ForeColor = [System.Drawing.Color]::FromArgb(244, 241, 255)
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
        $border = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(69, 57, 99), 1)
        $e.Graphics.DrawRectangle($border, 0, 0, ($s.ClientSize.Width - 1), ($s.ClientSize.Height - 1))
        $border.Dispose()
    })

    $headerConfirm = New-Object System.Windows.Forms.Panel
    $headerConfirm.Location = New-Object System.Drawing.Point(0, 0)
    $headerConfirm.Size = New-Object System.Drawing.Size(600, 78)
    $headerConfirm.BackColor = [System.Drawing.Color]::FromArgb(12, 16, 34)
    [void]$formConfirm.Controls.Add($headerConfirm)
    $headerConfirm.Add_Paint({
        param($s, $e)
        $line = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(139, 92, 246), 2)
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
    $headerRail.BackColor = [System.Drawing.Color]::FromArgb(139, 92, 246)
    [void]$headerConfirm.Controls.Add($headerRail)

    $eyebrow = New-Object System.Windows.Forms.Label
    $eyebrow.Text = 'ALTERTAG / NOVA OS'
    $eyebrow.Font = New-Object System.Drawing.Font('Segoe UI', 6.8, [System.Drawing.FontStyle]::Bold)
    $eyebrow.ForeColor = [System.Drawing.Color]::FromArgb(167, 139, 250)
    $eyebrow.Location = New-Object System.Drawing.Point(22, 11)
    $eyebrow.Size = New-Object System.Drawing.Size(260, 14)
    [void]$headerConfirm.Controls.Add($eyebrow)

    $titleConfirm = New-Object System.Windows.Forms.Label
    $titleConfirm.Text = 'Confirmar cadastro'
    $titleConfirm.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 15, [System.Drawing.FontStyle]::Bold)
    $titleConfirm.ForeColor = [System.Drawing.Color]::FromArgb(244, 241, 255)
    $titleConfirm.Location = New-Object System.Drawing.Point(20, 29)
    $titleConfirm.Size = New-Object System.Drawing.Size(360, 30)
    [void]$headerConfirm.Controls.Add($titleConfirm)

    $subtitleConfirm = New-Object System.Windows.Forms.Label
    $subtitleConfirm.Text = 'Revise os dados antes de enviar'
    $subtitleConfirm.Font = New-Object System.Drawing.Font('Segoe UI', 7.5)
    $subtitleConfirm.ForeColor = [System.Drawing.Color]::FromArgb(145, 137, 163)
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
    $osChipCaption.ForeColor = [System.Drawing.Color]::FromArgb(34, 197, 94)
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
    Register-OsNumeroControl -Control $osChipValue

    $closeConfirm = New-Object System.Windows.Forms.Button
    $closeConfirm.Text = 'X'
    $closeConfirm.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
    $closeConfirm.ForeColor = [System.Drawing.Color]::FromArgb(139, 130, 158)
    $closeConfirm.BackColor = [System.Drawing.Color]::FromArgb(12, 16, 34)
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
        $field.BackColor = [System.Drawing.Color]::FromArgb(13, 18, 37)
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

    Add-ConfirmField 'PRODUTO' $Produto 20 92 560 70 ([System.Drawing.Color]::FromArgb(139, 92, 246)) 9.2
    Add-ConfirmField 'SERIAL' $Serial 20 174 270 62 ([System.Drawing.Color]::FromArgb(196, 181, 253)) 10
    Add-ConfirmField 'REFERENCIA' $Referencia 302 174 278 62 ([System.Drawing.Color]::FromArgb(245, 158, 11)) 9
    Add-ConfirmField 'QUANTIDADE' $Quantidade 20 248 170 58 ([System.Drawing.Color]::FromArgb(139, 92, 246)) 9
    Add-ConfirmField 'LOCALIZACAO' $Localizacao 202 248 378 58 ([System.Drawing.Color]::FromArgb(34, 197, 94)) 9
    Add-ConfirmField 'OBSERVACAO' $Observacao 20 318 560 136 ([System.Drawing.Color]::FromArgb(34, 211, 238)) 8.5

    $footerConfirm = New-Object System.Windows.Forms.Panel
    $footerConfirm.Location = New-Object System.Drawing.Point(0, 474)
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
    $footerStatus.ForeColor = [System.Drawing.Color]::FromArgb(34, 197, 94)
    $footerStatus.Location = New-Object System.Drawing.Point(22, 27)
    $footerStatus.Size = New-Object System.Drawing.Size(190, 15)
    [void]$footerConfirm.Controls.Add($footerStatus)

    $btnBackConfirm = New-Object System.Windows.Forms.Button
    $btnBackConfirm.Text = 'Voltar'
    $btnBackConfirm.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
    $btnBackConfirm.ForeColor = [System.Drawing.Color]::FromArgb(155, 187, 212)
    $btnBackConfirm.BackColor = [System.Drawing.Color]::FromArgb(18, 16, 38)
    $btnBackConfirm.FlatStyle = 'Flat'
    $btnBackConfirm.FlatAppearance.BorderSize = 1
    $btnBackConfirm.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(53, 45, 79)
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
    $btnCreateConfirm.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(34, 197, 94)
    $btnCreateConfirm.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(0, 145, 96)
    $btnCreateConfirm.Location = New-Object System.Drawing.Point(458, 18)
    $btnCreateConfirm.Size = New-Object System.Drawing.Size(120, 38)
    $btnCreateConfirm.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnCreateConfirm.DialogResult = [System.Windows.Forms.DialogResult]::OK
    [void]$footerConfirm.Controls.Add($btnCreateConfirm)
    Set-RoundedControl -Control $btnCreateConfirm -Radius 7

    $formConfirm.AcceptButton = $btnCreateConfirm
    $formConfirm.CancelButton = $btnBackConfirm
    Set-CaijWindowsTypography -Root $formConfirm
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
    $formResult.BackColor = [System.Drawing.Color]::FromArgb(5, 8, 20)
    $formResult.ForeColor = [System.Drawing.Color]::FromArgb(244, 241, 255)
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
        $line = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(34, 197, 94), 2)
        $e.Graphics.DrawLine($line, 0, ($s.Height - 2), $s.Width, ($s.Height - 2))
        $line.Dispose()
    })

    $rail = New-Object System.Windows.Forms.Panel
    $rail.Location = New-Object System.Drawing.Point(0, 0)
    $rail.Size = New-Object System.Drawing.Size(4, 82)
    $rail.BackColor = [System.Drawing.Color]::FromArgb(34, 197, 94)
    [void]$header.Controls.Add($rail)

    $eyebrow = New-Object System.Windows.Forms.Label
    $eyebrow.Text = 'ALTERTAG / CADASTRO'
    $eyebrow.Font = New-Object System.Drawing.Font('Segoe UI', 7, [System.Drawing.FontStyle]::Bold)
    $eyebrow.ForeColor = [System.Drawing.Color]::FromArgb(34, 197, 94)
    $eyebrow.Location = New-Object System.Drawing.Point(24, 13)
    $eyebrow.Size = New-Object System.Drawing.Size(250, 15)
    [void]$header.Controls.Add($eyebrow)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'OS cadastrada'
    $title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 16, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = [System.Drawing.Color]::FromArgb(244, 241, 255)
    $title.Location = New-Object System.Drawing.Point(21, 34)
    $title.Size = New-Object System.Drawing.Size(330, 31)
    [void]$header.Controls.Add($title)

    $close = New-Object System.Windows.Forms.Button
    $close.Text = 'X'
    $close.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
    $close.ForeColor = [System.Drawing.Color]::FromArgb(139, 130, 158)
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
    $statusCaption.ForeColor = [System.Drawing.Color]::FromArgb(34, 197, 94)
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
        [System.Drawing.Color]::FromArgb(245, 158, 11)
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
    $btnDone.Text = 'Continuar'
    $btnDone.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9, [System.Drawing.FontStyle]::Bold)
    $btnDone.ForeColor = [System.Drawing.Color]::FromArgb(205, 198, 222)
    $btnDone.BackColor = [System.Drawing.Color]::FromArgb(20, 17, 42)
    $btnDone.FlatStyle = 'Flat'
    $btnDone.FlatAppearance.BorderSize = 1
    $btnDone.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(69, 57, 99)
    $btnDone.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(38, 28, 68)
    $btnDone.Location = New-Object System.Drawing.Point(20, 18)
    $btnDone.Size = New-Object System.Drawing.Size(136, 40)
    $btnDone.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnDone.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    [void]$footer.Controls.Add($btnDone)
    Set-RoundedControl -Control $btnDone -Radius 7

    $btnPrint = New-Object System.Windows.Forms.Button
    $btnPrint.Text = 'Imprimir etiqueta'
    $btnPrint.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9, [System.Drawing.FontStyle]::Bold)
    $btnPrint.ForeColor = [System.Drawing.Color]::White
    $btnPrint.BackColor = [System.Drawing.Color]::FromArgb(124, 58, 237)
    $btnPrint.FlatStyle = 'Flat'
    $btnPrint.FlatAppearance.BorderSize = 1
    $btnPrint.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(167, 139, 250)
    $btnPrint.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(139, 92, 246)
    $btnPrint.Location = New-Object System.Drawing.Point(304, 18)
    $btnPrint.Size = New-Object System.Drawing.Size(196, 40)
    $btnPrint.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnPrint.DialogResult = [System.Windows.Forms.DialogResult]::Yes
    [void]$footer.Controls.Add($btnPrint)
    Set-RoundedControl -Control $btnPrint -Radius 7

    $formResult.AcceptButton = $btnPrint
    $formResult.CancelButton = $close
    Set-CaijWindowsTypography -Root $formResult
    $result = if ($Owner) { $formResult.ShowDialog($Owner) } else { $formResult.ShowDialog() }
    $formResult.Dispose()
    return $(if ($result -eq [System.Windows.Forms.DialogResult]::Yes) { 'imprimir' } else { 'continuar' })
}


function Show-TecnicoCadastroOs {
    param([System.Windows.Forms.IWin32Window]$Owner)

    $techCanvas = [System.Drawing.Color]::FromArgb(7, 9, 17)
    $techSurface = [System.Drawing.Color]::FromArgb(15, 18, 29)
    $techRaised = [System.Drawing.Color]::FromArgb(21, 24, 38)
    $techBorder = [System.Drawing.Color]::FromArgb(42, 46, 63)
    $techBorderStrong = [System.Drawing.Color]::FromArgb(94, 106, 210)
    $techPrimary = [System.Drawing.Color]::FromArgb(94, 106, 210)
    $techPrimaryHover = [System.Drawing.Color]::FromArgb(112, 124, 228)
    $techText = [System.Drawing.Color]::FromArgb(247, 248, 248)
    $techMuted = [System.Drawing.Color]::FromArgb(150, 155, 168)

    $seletor = New-Object System.Windows.Forms.Form
    $seletor.Text = 'Identificar tecnico'
    $seletor.ClientSize = New-Object System.Drawing.Size(640, 440)
    $seletor.StartPosition = 'CenterParent'
    $seletor.BackColor = $techCanvas
    $seletor.FormBorderStyle = 'None'
    $seletor.MaximizeBox = $false
    $seletor.MinimizeBox = $false
    $seletor.KeyPreview = $true
    Set-RoundedControl -Control $seletor -Radius 14
    $seletor.Add_SizeChanged({ Set-RoundedControl -Control $this -Radius 14 })
    $seletor.Add_Paint({
        param($s, $e)
        $border = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(54, 59, 79), 1)
        $e.Graphics.DrawRectangle($border, 0, 0, ($s.ClientSize.Width - 1), ($s.ClientSize.Height - 1))
        $border.Dispose()
    })

    $estadoTecnico = [pscustomobject]@{
        Nome = ''
        OutroAtivo = $false
        Botoes = @{}
    }

    $headerTecnico = New-Object System.Windows.Forms.Panel
    $headerTecnico.BackColor = $techSurface
    $headerTecnico.Location = New-Object System.Drawing.Point(0, 0)
    $headerTecnico.Size = New-Object System.Drawing.Size(640, 98)
    [void]$seletor.Controls.Add($headerTecnico)

    $eyebrowTecnico = New-Object System.Windows.Forms.Label
    $eyebrowTecnico.Text = 'NOVA ORDEM DE SERVICO'
    $eyebrowTecnico.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 7, [System.Drawing.FontStyle]::Bold)
    $eyebrowTecnico.ForeColor = [System.Drawing.Color]::FromArgb(139, 148, 238)
    $eyebrowTecnico.Location = New-Object System.Drawing.Point(32, 16)
    $eyebrowTecnico.Size = New-Object System.Drawing.Size(230, 14)
    [void]$headerTecnico.Controls.Add($eyebrowTecnico)

    $tituloTecnico = New-Object System.Windows.Forms.Label
    $tituloTecnico.Text = 'Identifique o tecnico'
    $tituloTecnico.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 17, [System.Drawing.FontStyle]::Bold)
    $tituloTecnico.ForeColor = $techText
    $tituloTecnico.Location = New-Object System.Drawing.Point(30, 34)
    $tituloTecnico.Size = New-Object System.Drawing.Size(480, 30)
    [void]$headerTecnico.Controls.Add($tituloTecnico)

    $subtituloTecnico = New-Object System.Windows.Forms.Label
    $subtituloTecnico.Text = 'Escolha o responsavel pelo cadastro antes de continuar.'
    $subtituloTecnico.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $subtituloTecnico.ForeColor = $techMuted
    $subtituloTecnico.Location = New-Object System.Drawing.Point(32, 68)
    $subtituloTecnico.Size = New-Object System.Drawing.Size(500, 18)
    [void]$headerTecnico.Controls.Add($subtituloTecnico)

    $btnFecharTecnico = New-Object System.Windows.Forms.Button
    $btnFecharTecnico.Text = [string][char]0x00D7
    $btnFecharTecnico.Font = New-Object System.Drawing.Font('Segoe UI', 13)
    $btnFecharTecnico.ForeColor = $techMuted
    $btnFecharTecnico.BackColor = $techSurface
    $btnFecharTecnico.FlatStyle = 'Flat'
    $btnFecharTecnico.FlatAppearance.BorderSize = 0
    $btnFecharTecnico.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(37, 30, 45)
    $btnFecharTecnico.Location = New-Object System.Drawing.Point(594, 12)
    $btnFecharTecnico.Size = New-Object System.Drawing.Size(32, 32)
    $btnFecharTecnico.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnFecharTecnico.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    [void]$headerTecnico.Controls.Add($btnFecharTecnico)

    $dragTecnico = [pscustomobject]@{ Ativo=$false; Origem=[System.Drawing.Point]::Empty }
    $headerTecnico.Add_MouseDown({
        if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) { $dragTecnico.Ativo=$true; $dragTecnico.Origem=$_.Location }
    })
    $headerTecnico.Add_MouseMove({
        if ($dragTecnico.Ativo) { $seletor.Location = New-Object System.Drawing.Point(($seletor.Left + $_.X - $dragTecnico.Origem.X), ($seletor.Top + $_.Y - $dragTecnico.Origem.Y)) }
    })
    $headerTecnico.Add_MouseUp({ $dragTecnico.Ativo=$false })

    $txtOutroTecnico = New-Object System.Windows.Forms.TextBox
    $txtOutroTecnico.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $txtOutroTecnico.BackColor = $techRaised
    $txtOutroTecnico.ForeColor = $techText
    $txtOutroTecnico.BorderStyle = 'FixedSingle'
    $txtOutroTecnico.Location = New-Object System.Drawing.Point(32, 308)
    $txtOutroTecnico.Size = New-Object System.Drawing.Size(576, 30)
    $txtOutroTecnico.Visible = $false
    [void]$seletor.Controls.Add($txtOutroTecnico)

    $lblSelecaoTecnico = New-Object System.Windows.Forms.Label
    $lblSelecaoTecnico.Text = 'Selecione uma opcao para habilitar a continuacao.'
    $lblSelecaoTecnico.Font = New-Object System.Drawing.Font('Segoe UI', 8)
    $lblSelecaoTecnico.ForeColor = $techMuted
    $lblSelecaoTecnico.Location = New-Object System.Drawing.Point(32, 344)
    $lblSelecaoTecnico.Size = New-Object System.Drawing.Size(576, 18)
    [void]$seletor.Controls.Add($lblSelecaoTecnico)

    $btnConfirmarTecnico = New-Object System.Windows.Forms.Button
    $btnConfirmarTecnico.Text = 'Continuar  >'
    $btnConfirmarTecnico.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5, [System.Drawing.FontStyle]::Bold)
    $btnConfirmarTecnico.ForeColor = [System.Drawing.Color]::FromArgb(112, 116, 132)
    $btnConfirmarTecnico.BackColor = [System.Drawing.Color]::FromArgb(29, 32, 47)
    $btnConfirmarTecnico.FlatStyle = 'Flat'
    $btnConfirmarTecnico.FlatAppearance.BorderSize = 1
    $btnConfirmarTecnico.FlatAppearance.BorderColor = $techBorder
    $btnConfirmarTecnico.FlatAppearance.MouseOverBackColor = $techPrimaryHover
    $btnConfirmarTecnico.Location = New-Object System.Drawing.Point(428, 378)
    $btnConfirmarTecnico.Size = New-Object System.Drawing.Size(180, 42)
    $btnConfirmarTecnico.Enabled = $false
    $btnConfirmarTecnico.Cursor = [System.Windows.Forms.Cursors]::Hand
    [void]$seletor.Controls.Add($btnConfirmarTecnico)
    Set-RoundedControl -Control $btnConfirmarTecnico -Radius 6

    $tecnicosFixos = @('Vitor', 'Lucas', 'Hyrides', 'Erick', 'Outro')
    for ($i = 0; $i -lt $tecnicosFixos.Count; $i++) {
        $nomeTecnico = [string]$tecnicosFixos[$i]
        $btnTecnico = New-Object System.Windows.Forms.Button
        $btnTecnico.Text = $nomeTecnico
        $btnTecnico.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5)
        $btnTecnico.ForeColor = [System.Drawing.Color]::FromArgb(211, 214, 224)
        $btnTecnico.BackColor = $techRaised
        $btnTecnico.FlatStyle = 'Flat'
        $btnTecnico.FlatAppearance.BorderColor = $techBorder
        $btnTecnico.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(29, 33, 51)
        if ($i -lt 4) {
            $btnTecnico.Location = New-Object System.Drawing.Point((32 + (($i % 2) * 294)), (120 + ([Math]::Floor($i / 2) * 62)))
            $btnTecnico.Size = New-Object System.Drawing.Size(282, 50)
        } else {
            $btnTecnico.Location = New-Object System.Drawing.Point(32, 244)
            $btnTecnico.Size = New-Object System.Drawing.Size(576, 50)
        }
        $btnTecnico.Cursor = [System.Windows.Forms.Cursors]::Hand
        $estadoTecnico.Botoes[$nomeTecnico] = $btnTecnico
        $btnTecnico.Tag = [pscustomobject]@{
            Estado = $estadoTecnico
            Nome = $nomeTecnico
            CampoOutro = $txtOutroTecnico
            Confirmar = $btnConfirmarTecnico
        }
        [void]$seletor.Controls.Add($btnTecnico)
        Set-RoundedControl -Control $btnTecnico -Radius 8
        $btnTecnico.Add_Click({
            $ctx = $this.Tag
            $ctx.Estado.OutroAtivo = ([string]$ctx.Nome -eq 'Outro')
            $ctx.Estado.Nome = if ($ctx.Estado.OutroAtivo) { $ctx.CampoOutro.Text.Trim() } else { [string]$ctx.Nome }
            foreach ($nome in @($ctx.Estado.Botoes.Keys)) {
                $botao = $ctx.Estado.Botoes[$nome]
                $ativo = ($nome -eq [string]$ctx.Nome)
                $botao.BackColor = if ($ativo) { $techPrimary } else { $techRaised }
                $botao.ForeColor = if ($ativo) { [System.Drawing.Color]::White } else { [System.Drawing.Color]::FromArgb(211, 214, 224) }
                $botao.FlatAppearance.BorderColor = if ($ativo) { $techBorderStrong } else { $techBorder }
                $botao.Text = if ($ativo) { ([string][char]0x2713 + '  ' + $nome) } else { $nome }
            }
            $ctx.CampoOutro.Visible = $ctx.Estado.OutroAtivo
            $lblSelecaoTecnico.Text = if ($ctx.Estado.OutroAtivo) { 'Digite o nome do tecnico para continuar.' } else { "Responsavel selecionado: $($ctx.Estado.Nome)" }
            $ctx.Confirmar.Enabled = (-not [string]::IsNullOrWhiteSpace([string]$ctx.Estado.Nome))
            if ($ctx.Confirmar.Enabled) {
                $ctx.Confirmar.BackColor = $techPrimary
                $ctx.Confirmar.ForeColor = [System.Drawing.Color]::White
                $ctx.Confirmar.FlatAppearance.BorderColor = $techBorderStrong
            }
            if ($ctx.Estado.OutroAtivo) { $ctx.CampoOutro.Focus() }
        })
    }

    $txtOutroTecnico.Add_TextChanged({
        if ($estadoTecnico.OutroAtivo) {
            $estadoTecnico.Nome = $txtOutroTecnico.Text.Trim()
            $btnConfirmarTecnico.Enabled = (-not [string]::IsNullOrWhiteSpace($estadoTecnico.Nome))
            $lblSelecaoTecnico.Text = if ($btnConfirmarTecnico.Enabled) { "Responsavel selecionado: $($estadoTecnico.Nome)" } else { 'Digite o nome do tecnico para continuar.' }
            $btnConfirmarTecnico.BackColor = if ($btnConfirmarTecnico.Enabled) { $techPrimary } else { [System.Drawing.Color]::FromArgb(29, 32, 47) }
            $btnConfirmarTecnico.ForeColor = if ($btnConfirmarTecnico.Enabled) { [System.Drawing.Color]::White } else { [System.Drawing.Color]::FromArgb(112, 116, 132) }
        }
    })

    $btnCancelarTecnico = New-Object System.Windows.Forms.Button
    $btnCancelarTecnico.Text = 'Cancelar'
    $btnCancelarTecnico.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $btnCancelarTecnico.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5)
    $btnCancelarTecnico.ForeColor = [System.Drawing.Color]::FromArgb(205, 208, 218)
    $btnCancelarTecnico.BackColor = $techSurface
    $btnCancelarTecnico.FlatStyle = 'Flat'
    $btnCancelarTecnico.FlatAppearance.BorderColor = $techBorder
    $btnCancelarTecnico.FlatAppearance.MouseOverBackColor = $techRaised
    $btnCancelarTecnico.Location = New-Object System.Drawing.Point(32, 378)
    $btnCancelarTecnico.Size = New-Object System.Drawing.Size(130, 42)
    [void]$seletor.Controls.Add($btnCancelarTecnico)
    Set-RoundedControl -Control $btnCancelarTecnico -Radius 6

    $btnConfirmarTecnico.Add_Click({
        if (-not [string]::IsNullOrWhiteSpace($estadoTecnico.Nome)) {
            $seletor.Tag = $estadoTecnico.Nome.Trim()
            $seletor.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $seletor.Close()
        }
    })
    $seletor.AcceptButton = $btnConfirmarTecnico
    $seletor.CancelButton = $btnCancelarTecnico
    Set-CaijWindowsTypography -Root $seletor
    $resultadoTecnico = if ($Owner) { $seletor.ShowDialog($Owner) } else { $seletor.ShowDialog() }
    $tecnicoEscolhido = if ($resultadoTecnico -eq [System.Windows.Forms.DialogResult]::OK) { [string]$seletor.Tag } else { '' }
    $seletor.Dispose()
    return $tecnicoEscolhido
}

function Show-CadastroOsAltertagDraft {
    param([Parameter(Mandatory=$true)][string]$TecnicoInicial)
    if ([string]::IsNullOrWhiteSpace($TecnicoInicial)) { return }
    $osUiBg = [System.Drawing.Color]::FromArgb(7, 9, 17)
    $osUiSurface = [System.Drawing.Color]::FromArgb(15, 18, 29)
    $osUiSurfaceRaised = [System.Drawing.Color]::FromArgb(21, 24, 38)
    $osUiBorder = [System.Drawing.Color]::FromArgb(42, 46, 63)
    $osUiBorderStrong = [System.Drawing.Color]::FromArgb(94, 106, 210)
    $osUiPrimary = [System.Drawing.Color]::FromArgb(94, 106, 210)
    $osUiPrimaryHover = [System.Drawing.Color]::FromArgb(112, 124, 228)
    $osUiText = [System.Drawing.Color]::FromArgb(240, 242, 248)
    $osUiMuted = [System.Drawing.Color]::FromArgb(166, 170, 184)
    $osUiDim = [System.Drawing.Color]::FromArgb(112, 117, 133)

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Cadastrar OS Altertag'
    $dlg.ClientSize = New-Object System.Drawing.Size(920, 700)
    $dlg.StartPosition = 'CenterParent'
    $dlg.BackColor = $osUiBg
    $dlg.ForeColor = $cMain
    $dlg.FormBorderStyle = 'None'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.KeyPreview = $true
    Set-RoundedControl -Control $dlg -Radius 14
    $dlg.Add_Paint({
        $penCadastro = New-Object System.Drawing.Pen($osUiBorder, 1)
        $_.Graphics.DrawRectangle($penCadastro, 0, 0, ($this.ClientSize.Width - 1), ($this.ClientSize.Height - 1))
        $penCadastro.Dispose()
    })

    $cadastroHeader = New-Object System.Windows.Forms.Panel
    $cadastroHeader.BackColor = $osUiSurface
    $cadastroHeader.Location = New-Object System.Drawing.Point(0, 0)
    $cadastroHeader.Size = New-Object System.Drawing.Size(920, 88)
    [void]$dlg.Controls.Add($cadastroHeader)

    $cadastroHeaderRail = New-Object System.Windows.Forms.Panel
    $cadastroHeaderRail.BackColor = $cGreen
    $cadastroHeaderRail.Location = New-Object System.Drawing.Point(0, 0)
    $cadastroHeaderRail.Size = New-Object System.Drawing.Size(5, 88)
    $cadastroHeaderRail.Visible = $false
    [void]$cadastroHeader.Controls.Add($cadastroHeaderRail)

    $cadastroHeaderLine = New-Object System.Windows.Forms.Panel
    $cadastroHeaderLine.BackColor = $osUiBorder
    $cadastroHeaderLine.Location = New-Object System.Drawing.Point(0, 87)
    $cadastroHeaderLine.Size = New-Object System.Drawing.Size(920, 1)
    [void]$cadastroHeader.Controls.Add($cadastroHeaderLine)

    $cadastroEyebrow = New-Object System.Windows.Forms.Label
    $cadastroEyebrow.Text = 'ALTERTAG  /  NOVA OS'
    $cadastroEyebrow.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 7, [System.Drawing.FontStyle]::Bold)
    $cadastroEyebrow.ForeColor = $osUiPrimaryHover
    $cadastroEyebrow.Location = New-Object System.Drawing.Point(28, 12)
    $cadastroEyebrow.Size = New-Object System.Drawing.Size(260, 14)
    [void]$cadastroHeader.Controls.Add($cadastroEyebrow)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'Criar ordem de servico'
    $title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 17, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = $osUiText
    $title.Location = New-Object System.Drawing.Point(27, 28)
    $title.Size = New-Object System.Drawing.Size(500, 30)
    [void]$cadastroHeader.Controls.Add($title)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = 'Localize o produto, confira os dados e revise tudo antes de enviar.'
    $hint.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
    $hint.ForeColor = $osUiMuted
    $hint.Location = New-Object System.Drawing.Point(28, 61)
    $hint.Size = New-Object System.Drawing.Size(760, 18)
    [void]$cadastroHeader.Controls.Add($hint)

    $btnFecharCadastroTopo = New-Object System.Windows.Forms.Button
    $btnFecharCadastroTopo.Text = [char]0x00D7
    $btnFecharCadastroTopo.Font = New-Object System.Drawing.Font('Segoe UI', 16)
    $btnFecharCadastroTopo.ForeColor = $osUiMuted
    $btnFecharCadastroTopo.BackColor = $osUiSurface
    $btnFecharCadastroTopo.FlatStyle = 'Flat'
    $btnFecharCadastroTopo.FlatAppearance.BorderSize = 0
    $btnFecharCadastroTopo.FlatAppearance.MouseOverBackColor = $osUiSurfaceRaised
    $btnFecharCadastroTopo.Location = New-Object System.Drawing.Point(872, 12)
    $btnFecharCadastroTopo.Size = New-Object System.Drawing.Size(36, 36)
    $btnFecharCadastroTopo.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnFecharCadastroTopo.Add_Click({ $dlg.Close() })
    [void]$cadastroHeader.Controls.Add($btnFecharCadastroTopo)

    $script:cadastroDragAtivo = $false
    $script:cadastroDragOrigem = [System.Drawing.Point]::Empty
    $cadastroHeader.Add_MouseDown({
        if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            $script:cadastroDragAtivo = $true
            $script:cadastroDragOrigem = $_.Location
        }
    })
    $cadastroHeader.Add_MouseMove({
        if ($script:cadastroDragAtivo) {
            $p = [System.Windows.Forms.Cursor]::Position
            $dlg.Location = New-Object System.Drawing.Point(($p.X - $script:cadastroDragOrigem.X), ($p.Y - $script:cadastroDragOrigem.Y))
        }
    })
    $cadastroHeader.Add_MouseUp({ $script:cadastroDragAtivo = $false })

    $infoOsPanel = New-Object System.Windows.Forms.Panel
    $infoOsPanel.BackColor = $osUiSurface
    $infoOsPanel.BorderStyle = 'None'
    $infoOsPanel.Location = New-Object System.Drawing.Point(620, 78)
    $infoOsPanel.Size = New-Object System.Drawing.Size(200, 254)
    $dlg.Controls.Add($infoOsPanel)
    Set-RoundedControl -Control $infoOsPanel -Radius 7
    $infoOsPanel.Add_Paint({
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(62, 52, 88), 1)
        $_.Graphics.DrawRectangle($pen, 0, 0, ($this.Width - 1), ($this.Height - 1))
        $pen.Dispose()
    })

    # Accent top bar
    $infoOsAccent = New-Object System.Windows.Forms.Panel
    $infoOsAccent.BackColor = $cAccent
    $infoOsAccent.Location = New-Object System.Drawing.Point(0, 0)
    $infoOsAccent.Size = New-Object System.Drawing.Size(200, 3)
    [void]$infoOsPanel.Controls.Add($infoOsAccent)

    # --- Card Tecnico (botoes toggle) ---
    $cardTec = New-Object System.Windows.Forms.Panel
    $cardTec.BackColor = $osUiSurfaceRaised
    $cardTec.Location = New-Object System.Drawing.Point(10, 8)
    $cardTec.Size = New-Object System.Drawing.Size(178, 88)
    [void]$infoOsPanel.Controls.Add($cardTec)
    Set-RoundedControl -Control $cardTec -Radius 5
    $cardTecBar = New-Object System.Windows.Forms.Panel
    $cardTecBar.BackColor = $cAccent
    $cardTecBar.Location = New-Object System.Drawing.Point(0, 0)
    $cardTecBar.Size = New-Object System.Drawing.Size(3, 88)
    [void]$cardTec.Controls.Add($cardTecBar)
    $lblTecCaption = New-Object System.Windows.Forms.Label
    $lblTecCaption.Text = 'TECNICO'
    $lblTecCaption.Font = New-Object System.Drawing.Font('Segoe UI', 6.5, [System.Drawing.FontStyle]::Bold)
    $lblTecCaption.ForeColor = [System.Drawing.Color]::FromArgb(112, 199, 236)
    $lblTecCaption.Location = New-Object System.Drawing.Point(8, 6)
    $lblTecCaption.Size = New-Object System.Drawing.Size(162, 12)
    [void]$cardTec.Controls.Add($lblTecCaption)

    # Wrapper compativel com .SelectedItem usado no restante do cadastro
    $cmbTec = [PSCustomObject]@{ SelectedItem = $TecnicoInicial.Trim() }
    $script:tecnicoSelecionado = [string]$cmbTec.SelectedItem

    $lblTecnicoEscolhido = New-Object System.Windows.Forms.Label
    $lblTecnicoEscolhido.Text = [string]$cmbTec.SelectedItem
    $lblTecnicoEscolhido.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10, [System.Drawing.FontStyle]::Bold)
    $lblTecnicoEscolhido.ForeColor = [System.Drawing.Color]::White
    $lblTecnicoEscolhido.Location = New-Object System.Drawing.Point(10, 28)
    $lblTecnicoEscolhido.Size = New-Object System.Drawing.Size(100, 28)
    $lblTecnicoEscolhido.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $lblTecnicoEscolhido.AutoEllipsis = $true
    [void]$cardTec.Controls.Add($lblTecnicoEscolhido)

    $btnTrocarTecnico = New-Object System.Windows.Forms.Button
    $btnTrocarTecnico.Text = 'Trocar'
    $btnTrocarTecnico.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 7.5)
    $btnTrocarTecnico.ForeColor = [System.Drawing.Color]::FromArgb(216, 205, 244)
    $btnTrocarTecnico.BackColor = [System.Drawing.Color]::FromArgb(38, 30, 65)
    $btnTrocarTecnico.FlatStyle = 'Flat'
    $btnTrocarTecnico.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(107, 82, 160)
    $btnTrocarTecnico.Location = New-Object System.Drawing.Point(112, 28)
    $btnTrocarTecnico.Size = New-Object System.Drawing.Size(58, 28)
    $btnTrocarTecnico.Cursor = [System.Windows.Forms.Cursors]::Hand
    [void]$cardTec.Controls.Add($btnTrocarTecnico)
    Set-RoundedControl -Control $btnTrocarTecnico -Radius 4
    $btnTrocarTecnico.Add_Click({
        $novoTecnico = Show-TecnicoCadastroOs -Owner $dlg
        if (-not [string]::IsNullOrWhiteSpace($novoTecnico)) {
            $cmbTec.SelectedItem = $novoTecnico
            $script:tecnicoSelecionado = $novoTecnico
            $lblTecnicoEscolhido.Text = $novoTecnico
            Update-ResumoOs -Produto $listProd.SelectedItem
        }
    })

    # --- Card Serial ---
    $cardSerial = New-Object System.Windows.Forms.Panel
    $cardSerial.BackColor = $osUiSurfaceRaised
    $cardSerial.Location = New-Object System.Drawing.Point(10, 102)
    $cardSerial.Size = New-Object System.Drawing.Size(178, 42)
    [void]$infoOsPanel.Controls.Add($cardSerial)
    Set-RoundedControl -Control $cardSerial -Radius 5
    $cardSerialBar = New-Object System.Windows.Forms.Panel
    $cardSerialBar.BackColor = $cPurple
    $cardSerialBar.Location = New-Object System.Drawing.Point(0, 0)
    $cardSerialBar.Size = New-Object System.Drawing.Size(3, 42)
    [void]$cardSerial.Controls.Add($cardSerialBar)
    $lblSerialCaption = New-Object System.Windows.Forms.Label
    $lblSerialCaption.Text = 'SERIAL'
    $lblSerialCaption.Font = New-Object System.Drawing.Font('Segoe UI', 6.5, [System.Drawing.FontStyle]::Bold)
    $lblSerialCaption.ForeColor = [System.Drawing.Color]::FromArgb(166, 176, 255)
    $lblSerialCaption.Location = New-Object System.Drawing.Point(8, 5)
    $lblSerialCaption.Size = New-Object System.Drawing.Size(162, 12)
    [void]$cardSerial.Controls.Add($lblSerialCaption)
    $txtSerialOs = New-Object System.Windows.Forms.TextBox
    $txtSerialOs.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
    $txtSerialOs.BackColor = $osUiSurfaceRaised
    $txtSerialOs.ForeColor = [System.Drawing.Color]::White
    $txtSerialOs.BorderStyle = 'None'
    $txtSerialOs.Location = New-Object System.Drawing.Point(8, 22)
    $txtSerialOs.Size = New-Object System.Drawing.Size(162, 18)
    $txtSerialOs.Text = $info.Serial
    [void]$cardSerial.Controls.Add($txtSerialOs)

    # --- Card Referencia ---
    $cardGrade = New-Object System.Windows.Forms.Panel
    $cardGrade.BackColor = $osUiSurfaceRaised
    $cardGrade.Location = New-Object System.Drawing.Point(10, 150)
    $cardGrade.Size = New-Object System.Drawing.Size(178, 42)
    [void]$infoOsPanel.Controls.Add($cardGrade)
    Set-RoundedControl -Control $cardGrade -Radius 5
    $cardGradeBar = New-Object System.Windows.Forms.Panel
    $cardGradeBar.BackColor = $cYellow
    $cardGradeBar.Location = New-Object System.Drawing.Point(0, 0)
    $cardGradeBar.Size = New-Object System.Drawing.Size(3, 42)
    [void]$cardGrade.Controls.Add($cardGradeBar)
    $lblGradeCaption = New-Object System.Windows.Forms.Label
    $lblGradeCaption.Text = 'REFERENCIA'
    $lblGradeCaption.Font = New-Object System.Drawing.Font('Segoe UI', 6.5, [System.Drawing.FontStyle]::Bold)
    $lblGradeCaption.ForeColor = [System.Drawing.Color]::FromArgb(255, 211, 103)
    $lblGradeCaption.Location = New-Object System.Drawing.Point(8, 5)
    $lblGradeCaption.Size = New-Object System.Drawing.Size(162, 12)
    [void]$cardGrade.Controls.Add($lblGradeCaption)
    $script:gradeCadastroOs = if ($script:rnaAtivo) { 'RMA' } elseif ($script:gradeAtual) { [string]$script:gradeAtual } else { 'A' }
    $btnGradeOs = New-Object System.Windows.Forms.Button
    $btnGradeOs.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 7.5)
    $btnGradeOs.BackColor = $osUiSurfaceRaised
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
    $gradeMenuOs.BackColor = [System.Drawing.Color]::FromArgb(9, 14, 29)
    $gradeMenuOs.ForeColor = [System.Drawing.Color]::FromArgb(244, 241, 255)
    $gradeMenuOs.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5)
    $gradeMenuOs.ShowImageMargin = $false
    $gradeMenuOs.ShowCheckMargin = $false
    $gradeMenuOs.DropShadowEnabled = $true
    $gradeMenuOs.Padding = New-Object System.Windows.Forms.Padding(1, 4, 1, 4)
    $gradeMenuOs.MinimumSize = New-Object System.Drawing.Size(178, 0)
    $gradeMenuOs.Renderer = New-Object CaijGradeMenuRenderer
    foreach ($gradeOpcao in @(@(Get-CaijGradeOptions) + @(Get-CaijGradeOptions -EquipmentType 'Celular') | Select-Object -Unique)) {
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
    $cardOs.BackColor = [System.Drawing.Color]::FromArgb(8, 42, 33)
    $cardOs.Location = New-Object System.Drawing.Point(10, 198)
    $cardOs.Size = New-Object System.Drawing.Size(178, 48)
    [void]$infoOsPanel.Controls.Add($cardOs)
    Set-RoundedControl -Control $cardOs -Radius 5
    $cardOsBar = New-Object System.Windows.Forms.Panel
    $cardOsBar.BackColor = $cGreen
    $cardOsBar.Location = New-Object System.Drawing.Point(0, 0)
    $cardOsBar.Size = New-Object System.Drawing.Size(3, 48)
    [void]$cardOs.Controls.Add($cardOsBar)
    $lblOsCaption = New-Object System.Windows.Forms.Label
    $lblOsCaption.Text = 'OS ATUAL'
    $lblOsCaption.Font = New-Object System.Drawing.Font('Segoe UI', 6.5, [System.Drawing.FontStyle]::Bold)
    $lblOsCaption.ForeColor = [System.Drawing.Color]::FromArgb(99, 225, 169)
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
    Register-OsNumeroControl -Control $lblOsTopoValor

    # --- Header da secao de busca ---
    $buscaHeader = New-Object System.Windows.Forms.Panel
    $buscaHeader.BackColor = $osUiSurface
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
    $lblBuscaHint.ForeColor = $osUiMuted
    $lblBuscaHint.Location  = New-Object System.Drawing.Point(92, 10)
    $lblBuscaHint.Size      = New-Object System.Drawing.Size(480, 14)
    [void]$buscaHeader.Controls.Add($lblBuscaHint)

    # --- Painel de busca (campo + botao) ---
    $buscaPanel = New-Object System.Windows.Forms.Panel
    $buscaPanel.BackColor   = $osUiSurfaceRaised
    $buscaPanel.BorderStyle = 'None'
    $buscaPanel.Location    = New-Object System.Drawing.Point(20, 104)
    $buscaPanel.Size        = New-Object System.Drawing.Size(580, 46)
    [void]$dlg.Controls.Add($buscaPanel)

    # Icone lupa
    $lblLupa = New-Object System.Windows.Forms.Label
    $lblLupa.Text      = [char]::ConvertFromUtf32(0x1F50D)
    $lblLupa.Font      = New-Object System.Drawing.Font('Segoe UI Symbol', 11)
    $lblLupa.ForeColor = [System.Drawing.Color]::FromArgb(167, 139, 250)
    $lblLupa.Location  = New-Object System.Drawing.Point(10, 10)
    $lblLupa.Size      = New-Object System.Drawing.Size(28, 26)
    [void]$buscaPanel.Controls.Add($lblLupa)

    $txtBuscaProd = New-Object System.Windows.Forms.TextBox
    $txtBuscaProd.Font        = New-Object System.Drawing.Font('Segoe UI', 10)
    $txtBuscaProd.BackColor   = $osUiSurfaceRaised
    $txtBuscaProd.ForeColor   = [System.Drawing.Color]::FromArgb(238, 234, 250)
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
    $buscaDivider.BackColor = $osUiBorder
    $buscaDivider.Location  = New-Object System.Drawing.Point(442, 8)
    $buscaDivider.Size      = New-Object System.Drawing.Size(1, 30)
    [void]$buscaPanel.Controls.Add($buscaDivider)

    $btnBuscaProd = New-Object System.Windows.Forms.Button
    $btnBuscaProd.Text      = 'Buscar'
    $btnBuscaProd.Font      = New-Object System.Drawing.Font('Segoe UI Semibold', 9, [System.Drawing.FontStyle]::Bold)
    $btnBuscaProd.ForeColor = [System.Drawing.Color]::FromArgb(239, 233, 255)
    $btnBuscaProd.BackColor = [System.Drawing.Color]::FromArgb(109, 40, 217)
    $btnBuscaProd.FlatStyle = 'Flat'
    $btnBuscaProd.FlatAppearance.BorderSize            = 0
    $btnBuscaProd.FlatAppearance.MouseOverBackColor    = [System.Drawing.Color]::FromArgb(139, 92, 246)
    $btnBuscaProd.FlatAppearance.MouseDownBackColor    = [System.Drawing.Color]::FromArgb(82, 33, 150)
    $btnBuscaProd.Location  = New-Object System.Drawing.Point(443, 1)
    $btnBuscaProd.Size      = New-Object System.Drawing.Size(134, 42)
    [void]$buscaPanel.Controls.Add($btnBuscaProd)
    Set-RoundedControl -Control $buscaPanel -Radius 6
    Set-RoundedControl -Control $btnBuscaProd -Radius 5

    # --- Painel de resultados ---
    $prodPanel = New-Object System.Windows.Forms.Panel
    $prodPanel.BackColor   = $osUiSurface
    $prodPanel.BorderStyle = 'None'
    $prodPanel.Location    = New-Object System.Drawing.Point(20, 152)
    $prodPanel.Size        = New-Object System.Drawing.Size(580, 136)
    [void]$dlg.Controls.Add($prodPanel)

    # Header da lista com gradiente simulado
    $prodHead = New-Object System.Windows.Forms.Panel
    $prodHead.BackColor = [System.Drawing.Color]::FromArgb(25, 20, 48)
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
        $h.ForeColor = [System.Drawing.Color]::FromArgb(178, 171, 197)
        $h.Location  = New-Object System.Drawing.Point([int]$col.X, 7)
        $h.Size      = New-Object System.Drawing.Size([int]$col.W, 13)
        [void]$prodHead.Controls.Add($h)
    }

    # Divisores verticais no header
    foreach ($xDiv in @(100, 460)) {
        $dv = New-Object System.Windows.Forms.Panel
        $dv.BackColor = $osUiBorder
        $dv.Location  = New-Object System.Drawing.Point($xDiv, 5)
        $dv.Size      = New-Object System.Drawing.Size(1, 16)
        [void]$prodHead.Controls.Add($dv)
    }

    $listProd = New-Object System.Windows.Forms.ListBox
    $listProd.DisplayMember = 'texto'
    $listProd.DrawMode      = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
    $listProd.ItemHeight    = 28
    $listProd.Font          = New-Object System.Drawing.Font('Segoe UI', 8.5)
    $listProd.BackColor     = $osUiSurface
    $listProd.ForeColor     = [System.Drawing.Color]::White
    $listProd.BorderStyle   = 'None'
    $listProd.Location      = New-Object System.Drawing.Point(1, 27)
    # Largura extra: empurra o scrollbar nativo para fora do painel (que corta o excesso)
    $listProd.Size          = New-Object System.Drawing.Size((576 + [System.Windows.Forms.SystemInformation]::VerticalScrollBarWidth + 2), 107)
    [void]$prodPanel.Controls.Add($listProd)

    # --- Scrollbar customizado (trilho fino + polegar arredondado) ---
    $scrollProd = New-Object System.Windows.Forms.Panel
    $scrollProd.BackColor = $osUiSurface
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
        $trackBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(19, 17, 40))
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
        $thumbColor = if ($script:scrollProdDrag) { [System.Drawing.Color]::FromArgb(139, 92, 246) } else { [System.Drawing.Color]::FromArgb(78, 62, 110) }
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
    $lblListaVazia.ForeColor = $osUiDim
    $lblListaVazia.BackColor = $osUiSurface
    $lblListaVazia.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $lblListaVazia.Location  = New-Object System.Drawing.Point(1, 27)
    $lblListaVazia.Size      = New-Object System.Drawing.Size(576, 107)
    [void]$prodPanel.Controls.Add($lblListaVazia)
    $lblListaVazia.BringToFront()

    $buscaStatus = New-Object System.Windows.Forms.Panel
    $buscaStatus.BackColor = [System.Drawing.Color]::FromArgb(13, 18, 37)
    $buscaStatus.Location = New-Object System.Drawing.Point(20, 296)
    $buscaStatus.Size = New-Object System.Drawing.Size(580, 30)
    [void]$dlg.Controls.Add($buscaStatus)
    Set-RoundedControl -Control $buscaStatus -Radius 5

    $buscaStatusDot = New-Object System.Windows.Forms.Panel
    $buscaStatusDot.BackColor = [System.Drawing.Color]::FromArgb(139, 92, 246)
    $buscaStatusDot.Location = New-Object System.Drawing.Point(12, 11)
    $buscaStatusDot.Size = New-Object System.Drawing.Size(7, 7)
    [void]$buscaStatus.Controls.Add($buscaStatusDot)
    Set-RoundedControl -Control $buscaStatusDot -Radius 4

    $txtResumo = New-Object System.Windows.Forms.Label
    $txtResumo.Text = 'Digite um modelo, processador ou codigo para iniciar a busca.'
    $txtResumo.Font = New-Object System.Drawing.Font('Segoe UI', 7.5)
    $txtResumo.ForeColor = $osUiMuted
    $txtResumo.Location = New-Object System.Drawing.Point(28, 7)
    $txtResumo.Size = New-Object System.Drawing.Size(538, 17)
    $txtResumo.AutoEllipsis = $true
    [void]$buscaStatus.Controls.Add($txtResumo)

    # --- Leitura auxiliar e observacao ---
    $servHeader = New-Object System.Windows.Forms.Panel
    $servHeader.BackColor = $osUiSurface
    $servHeader.Location  = New-Object System.Drawing.Point(20, 344)
    $servHeader.Size      = New-Object System.Drawing.Size(800, 26)
    [void]$dlg.Controls.Add($servHeader)

    $servHeaderAccent = New-Object System.Windows.Forms.Panel
    $servHeaderAccent.BackColor = $cAccent
    $servHeaderAccent.Location  = New-Object System.Drawing.Point(0, 0)
    $servHeaderAccent.Size      = New-Object System.Drawing.Size(3, 26)
    [void]$servHeader.Controls.Add($servHeaderAccent)

    $lblServ = New-Object System.Windows.Forms.Label
    $lblServ.Text = 'OBSERVACAO DA OS'
    $lblServ.Font = New-Object System.Drawing.Font('Segoe UI', 7, [System.Drawing.FontStyle]::Bold)
    $lblServ.ForeColor = $cAccent
    $lblServ.Location = New-Object System.Drawing.Point(12, 6)
    $lblServ.Size = New-Object System.Drawing.Size(160, 14)
    [void]$servHeader.Controls.Add($lblServ)

    $lblServHint = New-Object System.Windows.Forms.Label
    $lblServHint.Text      = 'O Altertag recebera data, horario, tecnico e o texto abaixo automaticamente'
    $lblServHint.Font      = New-Object System.Drawing.Font('Segoe UI', 7)
    $lblServHint.ForeColor = $osUiMuted
    $lblServHint.Location  = New-Object System.Drawing.Point(172, 6)
    $lblServHint.Size      = New-Object System.Drawing.Size(455, 14)
    [void]$servHeader.Controls.Add($lblServHint)

    $btnLer3uCadastro = New-Object System.Windows.Forms.Button
    $btnLer3uCadastro.Text = 'Ler informacoes 3uTools'
    $btnLer3uCadastro.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 7, [System.Drawing.FontStyle]::Bold)
    $btnLer3uCadastro.ForeColor = [System.Drawing.Color]::White
    $btnLer3uCadastro.BackColor = [System.Drawing.Color]::FromArgb(91, 33, 182)
    $btnLer3uCadastro.FlatStyle = 'Flat'
    $btnLer3uCadastro.FlatAppearance.BorderSize = 0
    $btnLer3uCadastro.Location = New-Object System.Drawing.Point(616, 2)
    $btnLer3uCadastro.Size = New-Object System.Drawing.Size(176, 22)
    $btnLer3uCadastro.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnLer3uCadastro.Visible = $true
    [void]$servHeader.Controls.Add($btnLer3uCadastro)
    Set-RoundedControl -Control $btnLer3uCadastro -Radius 5

    $tipoPanel = New-Object System.Windows.Forms.Panel
    $tipoPanel.BackColor = $osUiBg
    $tipoPanel.Location = New-Object System.Drawing.Point(20, 372)
    $tipoPanel.Size = New-Object System.Drawing.Size(800, 34)
    $tipoPanel.Visible = $false
    [void]$dlg.Controls.Add($tipoPanel)

    $tipoButtons = @{}
    foreach ($tipoDef in @(
        @{ Nome='Notebook'; X=0 },
        @{ Nome='Monitor'; X=270 },
        @{ Nome='Celular'; X=540 }
    )) {
        $tipoBtn = New-Object System.Windows.Forms.Button
        $tipoBtn.Text = [string]$tipoDef.Nome
        $tipoBtn.Tag = [string]$tipoDef.Nome
        $tipoBtn.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5, [System.Drawing.FontStyle]::Bold)
        $tipoBtn.ForeColor = $osUiMuted
        $tipoBtn.BackColor = $osUiSurface
        $tipoBtn.FlatStyle = 'Flat'
        $tipoBtn.FlatAppearance.BorderSize = 1
        $tipoBtn.FlatAppearance.BorderColor = $osUiBorder
        $tipoBtn.Location = New-Object System.Drawing.Point([int]$tipoDef.X, 1)
        $tipoBtn.Size = New-Object System.Drawing.Size(260, 30)
        $tipoBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
        [void]$tipoPanel.Controls.Add($tipoBtn)
        Set-RoundedControl -Control $tipoBtn -Radius 6
        $tipoButtons[[string]$tipoDef.Nome] = $tipoBtn
    }

    $servicosCadastroEstado = [pscustomobject]@{
        Selecoes = @{ Notebook=@(); Monitor=@(); Celular=@() }
        DadosCelular = $null
        TipoAtual = switch ([string]$script:tipoEtiqueta) {
            'Monitor' { 'Monitor' }
            'Celular' { 'Celular' }
            default { 'Notebook' }
        }
    }
    $servPanel = New-Object System.Windows.Forms.Panel
    $servPanel.BackColor = $osUiSurfaceRaised
    $servPanel.BorderStyle = 'None'
    $servPanel.Location = New-Object System.Drawing.Point(20, 410)
    $servPanel.Size = New-Object System.Drawing.Size(800, 52)
    $servPanel.Visible = $false
    [void]$dlg.Controls.Add($servPanel)
    Set-RoundedControl -Control $servPanel -Radius 6

    $servicosPorTipo = @{
        Notebook = @(
            @{ Titulo='Pecas e manutencao'; Cor=[System.Drawing.Color]::FromArgb(139,92,246); Itens=@('Troca de bateria','Troca SSD','Troca de tela','Troca de memoria RAM') },
            @{ Titulo='Estrutura'; Cor=[System.Drawing.Color]::FromArgb(196,181,253); Itens=@('Troca de moldura','Troca de teclado','Troca de touchpad','Troca de dobradica') },
            @{ Titulo='Estrutura II'; Cor=[System.Drawing.Color]::FromArgb(0,206,190); Itens=@('Troca de carcaca','Troca de tampa','Troca de base','Troca de cooler') },
            @{ Titulo='Acabamento'; Cor=[System.Drawing.Color]::FromArgb(249,115,22); Itens=@('Pintura 1','Pintura 2','Pintura 3','Pintura geral') }
        )
        Monitor = @(
            @{ Titulo='Imagem'; Cor=[System.Drawing.Color]::FromArgb(139,92,246); Itens=@('Troca de tela/painel','Reparo de imagem','Troca de backlight','Teste de imagem') },
            @{ Titulo='Energia'; Cor=[System.Drawing.Color]::FromArgb(196,181,253); Itens=@('Troca de fonte','Reparo de placa','Troca de cabo','Teste de energia') },
            @{ Titulo='Conectividade'; Cor=[System.Drawing.Color]::FromArgb(0,206,190); Itens=@('Reparo HDMI','Reparo DisplayPort','Reparo VGA','Teste de entradas') },
            @{ Titulo='Estrutura'; Cor=[System.Drawing.Color]::FromArgb(249,115,22); Itens=@('Troca de botoes','Troca de base','Limpeza interna','Pintura') }
        )
        Celular = @()
    }

    $showServicosCadastro = {
        param($Contexto)
        $Tipo = [string]$Contexto.Tipo
        $grupos = @($Contexto.Grupos)
        if ($grupos.Count -eq 0) { return }

        $picker = New-Object System.Windows.Forms.Form
        $picker.Text = "Selecao desativada - $Tipo"
        $picker.Size = New-Object System.Drawing.Size(820, 330)
        $picker.StartPosition = 'CenterParent'
        $picker.BackColor = $osUiBg
        $picker.ForeColor = $osUiText
        $picker.FormBorderStyle = 'FixedDialog'
        $picker.MaximizeBox = $false
        $picker.MinimizeBox = $false

        $pickerHeader = New-Object System.Windows.Forms.Panel
        $pickerHeader.BackColor = $osUiSurface
        $pickerHeader.Location = New-Object System.Drawing.Point(0, 0)
        $pickerHeader.Size = New-Object System.Drawing.Size(804, 52)
        [void]$picker.Controls.Add($pickerHeader)

        $pickerTitle = New-Object System.Windows.Forms.Label
        $pickerTitle.Text = 'Selecao desativada'
        $pickerTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 12, [System.Drawing.FontStyle]::Bold)
        $pickerTitle.ForeColor = $osUiText
        $pickerTitle.Location = New-Object System.Drawing.Point(20, 8)
        $pickerTitle.Size = New-Object System.Drawing.Size(420, 24)
        [void]$pickerHeader.Controls.Add($pickerTitle)

        $pickerHint = New-Object System.Windows.Forms.Label
        $pickerHint.Text = $Tipo
        $pickerHint.Font = New-Object System.Drawing.Font('Segoe UI', 7.5)
        $pickerHint.ForeColor = $osUiMuted
        $pickerHint.Location = New-Object System.Drawing.Point(21, 31)
        $pickerHint.Size = New-Object System.Drawing.Size(300, 15)
        [void]$pickerHeader.Controls.Add($pickerHint)

        $pickerChecks = @()
        for ($grupoIndex = 0; $grupoIndex -lt $grupos.Count; $grupoIndex++) {
            $grupo = $grupos[$grupoIndex]
            $cardX = 20 + ($grupoIndex * 194)
            $gCard = New-Object System.Windows.Forms.Panel
            $gCard.BackColor = $osUiSurfaceRaised
            $gCard.Location = New-Object System.Drawing.Point($cardX, 66)
            $gCard.Size = New-Object System.Drawing.Size(182, 142)
            [void]$picker.Controls.Add($gCard)
            Set-RoundedControl -Control $gCard -Radius 6

            $gBar = New-Object System.Windows.Forms.Panel
            $gBar.BackColor = $cAccent
            $gBar.Location = New-Object System.Drawing.Point(0, 0)
            $gBar.Size = New-Object System.Drawing.Size(182, 3)
            [void]$gCard.Controls.Add($gBar)

            $gTit = New-Object System.Windows.Forms.Label
            $gTit.Text = [string]$grupo.Titulo
            $gTit.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 7.5, [System.Drawing.FontStyle]::Bold)
            $gTit.ForeColor = [System.Drawing.Color]::FromArgb(196,181,253)
            $gTit.Location = New-Object System.Drawing.Point(10, 9)
            $gTit.Size = New-Object System.Drawing.Size(162, 16)
            [void]$gCard.Controls.Add($gTit)

            $yChk = 32
            foreach ($itemTxt in @($grupo.Itens)) {
                $chk = New-Object System.Windows.Forms.CheckBox
                $chk.Text = [string]$itemTxt
                $chk.Font = New-Object System.Drawing.Font('Segoe UI', 8)
                $chk.ForeColor = $osUiText
                $chk.BackColor = $osUiSurfaceRaised
                $chk.Location = New-Object System.Drawing.Point(10, $yChk)
                $chk.Size = New-Object System.Drawing.Size(166, 22)
                $chk.FlatStyle = 'Flat'
                $chk.Checked = @($Contexto.Selecionados) -contains [string]$itemTxt
                [void]$gCard.Controls.Add($chk)
                $pickerChecks += $chk
                $yChk += 24
            }
        }

        $btnPickerCancelar = New-Object System.Windows.Forms.Button
        $btnPickerCancelar.Text = 'Cancelar'
        $btnPickerCancelar.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $btnPickerCancelar.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5)
        $btnPickerCancelar.ForeColor = $osUiMuted
        $btnPickerCancelar.BackColor = $osUiSurface
        $btnPickerCancelar.FlatStyle = 'Flat'
        $btnPickerCancelar.FlatAppearance.BorderColor = $osUiBorder
        $btnPickerCancelar.Location = New-Object System.Drawing.Point(20, 230)
        $btnPickerCancelar.Size = New-Object System.Drawing.Size(150, 38)
        [void]$picker.Controls.Add($btnPickerCancelar)
        Set-RoundedControl -Control $btnPickerCancelar -Radius 6

        $btnPickerSalvar = New-Object System.Windows.Forms.Button
        $btnPickerSalvar.Text = 'Aplicar selecao'
        $btnPickerSalvar.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $btnPickerSalvar.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5, [System.Drawing.FontStyle]::Bold)
        $btnPickerSalvar.ForeColor = [System.Drawing.Color]::White
        $btnPickerSalvar.BackColor = [System.Drawing.Color]::FromArgb(91,33,182)
        $btnPickerSalvar.FlatStyle = 'Flat'
        $btnPickerSalvar.FlatAppearance.BorderSize = 0
        $btnPickerSalvar.Location = New-Object System.Drawing.Point(624, 230)
        $btnPickerSalvar.Size = New-Object System.Drawing.Size(160, 38)
        [void]$picker.Controls.Add($btnPickerSalvar)
        Set-RoundedControl -Control $btnPickerSalvar -Radius 6

        $picker.AcceptButton = $btnPickerSalvar
        $picker.CancelButton = $btnPickerCancelar
        Set-CaijWindowsTypography -Root $picker
        if ($picker.ShowDialog($dlg) -eq [System.Windows.Forms.DialogResult]::OK) {
            $Contexto.Selecionados = @(
                $pickerChecks | Where-Object { $_.Checked } | ForEach-Object { [string]$_.Text }
            )
            $Contexto.Aplicado = $true
        }
        $picker.Dispose()
    }.GetNewClosure()

    $renderServicosCadastro = {
        param([string]$Tipo)
        $servicosCadastroEstado.TipoAtual = $Tipo
        $tipoGradeCelular = ($Tipo -eq 'Celular')
        foreach ($item in @($gradeMenuOs.Items)) {
            $tagGradeItem = [string]$item.Tag
            $item.Visible = if ($tipoGradeCelular) {
                $tagGradeItem -notmatch '^C\s*-\s*PINTURA'
            } else {
                $tagGradeItem -ne 'C'
            }
        }
        if ($tipoGradeCelular -and ([string]$script:gradeCadastroOs) -match '^C\s*-\s*PINTURA') {
            $script:gradeCadastroOs = 'C'
            $script:gradeAtual = 'C'
            $btnGradeOs.Text = (Format-CaijGradeReference 'C')
        } elseif (-not $tipoGradeCelular -and ([string]$script:gradeCadastroOs) -eq 'C') {
            $script:gradeCadastroOs = 'A'
            $script:gradeAtual = 'A'
            $btnGradeOs.Text = (Format-CaijGradeReference 'A')
        }
        $servPanel.Controls.Clear()
        foreach ($tipoNome in @('Notebook','Monitor','Celular')) {
            $ativo = ($tipoNome -eq $Tipo)
            $tipoButtons[$tipoNome].BackColor = if ($ativo) { [System.Drawing.Color]::FromArgb(91,33,182) } else { $osUiSurface }
            $tipoButtons[$tipoNome].ForeColor = if ($ativo) { [System.Drawing.Color]::White } else { $osUiMuted }
            $tipoButtons[$tipoNome].FlatAppearance.BorderColor = if ($ativo) { [System.Drawing.Color]::FromArgb(167,139,250) } else { $osUiBorder }
        }
        $btnLer3uCadastro.Visible = $true
        $gruposAtivos = @($servicosPorTipo[$Tipo])
        $compactRail = New-Object System.Windows.Forms.Panel
        $compactRail.BackColor = $cAccent
        $compactRail.Location = New-Object System.Drawing.Point(0, 0)
        $compactRail.Size = New-Object System.Drawing.Size(3, 52)
        [void]$servPanel.Controls.Add($compactRail)

        $compactTitle = New-Object System.Windows.Forms.Label
        $compactTitle.Text = if ($gruposAtivos.Count -eq 0) { 'SEM DETALHES PREDEFINIDOS' } else { 'DETALHES DA OBSERVACAO' }
        $compactTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 7.5, [System.Drawing.FontStyle]::Bold)
        $compactTitle.ForeColor = [System.Drawing.Color]::FromArgb(196,181,253)
        $compactTitle.Location = New-Object System.Drawing.Point(16, 7)
        $compactTitle.Size = New-Object System.Drawing.Size(260, 15)
        [void]$servPanel.Controls.Add($compactTitle)

        $selecionados = @($servicosCadastroEstado.Selecoes[$Tipo])
        $compactResumo = New-Object System.Windows.Forms.Label
        $compactResumo.Text = if ($gruposAtivos.Count -eq 0) {
            'Use o campo Observacao para registrar os detalhes.'
        } elseif ($selecionados.Count -eq 0) {
            'Nenhum detalhe selecionado'
        } else {
            "$($selecionados.Count) selecionado(s)  |  $($selecionados -join ', ')"
        }
        $compactResumo.Font = New-Object System.Drawing.Font('Segoe UI', 8)
        $compactResumo.ForeColor = $osUiMuted
        $compactResumo.Location = New-Object System.Drawing.Point(16, 26)
        $compactResumo.Size = New-Object System.Drawing.Size(580, 18)
        $compactResumo.AutoEllipsis = $true
        [void]$servPanel.Controls.Add($compactResumo)

        if ($gruposAtivos.Count -eq 0) {
            return
        }

        $btnSelecionarServicos = New-Object System.Windows.Forms.Button
        $btnSelecionarServicos.Text = 'Selecao desativada'
        $btnSelecionarServicos.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8, [System.Drawing.FontStyle]::Bold)
        $btnSelecionarServicos.ForeColor = [System.Drawing.Color]::FromArgb(225,216,255)
        $btnSelecionarServicos.BackColor = [System.Drawing.Color]::FromArgb(38,30,65)
        $btnSelecionarServicos.FlatStyle = 'Flat'
        $btnSelecionarServicos.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(107,82,160)
        $btnSelecionarServicos.Location = New-Object System.Drawing.Point(620, 9)
        $btnSelecionarServicos.Size = New-Object System.Drawing.Size(164, 34)
        $btnSelecionarServicos.Cursor = [System.Windows.Forms.Cursors]::Hand
        $btnSelecionarServicos.Tag = [pscustomobject]@{
            Tipo = $Tipo
            AbrirSeletor = $showServicosCadastro
            Resumo = $compactResumo
            Grupos = @($gruposAtivos)
            Estado = $servicosCadastroEstado
        }
        [void]$servPanel.Controls.Add($btnSelecionarServicos)
        Set-RoundedControl -Control $btnSelecionarServicos -Radius 6
        $btnSelecionarServicos.Add_Click({
            try {
                $contexto = $this.Tag
                $tipoSelecionado = [string]$contexto.Tipo
                $contextoSeletor = [pscustomobject]@{
                    Tipo = $tipoSelecionado
                    Grupos = @($contexto.Grupos)
                    Selecionados = @($contexto.Estado.Selecoes[$tipoSelecionado])
                    Aplicado = $false
                }
                & $contexto.AbrirSeletor $contextoSeletor
                if ($contextoSeletor.Aplicado) {
                    $contexto.Estado.Selecoes[$tipoSelecionado] = @($contextoSeletor.Selecionados)
                }
                $selecionadosAtualizados = @($contexto.Estado.Selecoes[$tipoSelecionado])
                $contexto.Resumo.Text = if ($selecionadosAtualizados.Count -eq 0) {
                    'Nenhum detalhe selecionado'
                } else {
                    "$($selecionadosAtualizados.Count) selecionado(s)  |  $($selecionadosAtualizados -join ', ')"
                }
            } catch {
                [System.Windows.Forms.MessageBox]::Show(
                    "Nao foi possivel abrir a selecao de detalhes.`r`n`r`n$($_.Exception.Message)",
                    'Selecao desativada', 'OK', 'Error'
                ) | Out-Null
            }
        })
    }.GetNewClosure()

    foreach ($tipoNome in @('Notebook','Monitor','Celular')) {
        $tipoButtons[$tipoNome].Add_Click({ & $renderServicosCadastro ([string]$this.Tag) }.GetNewClosure())
    }
    & $renderServicosCadastro $servicosCadastroEstado.TipoAtual

    $obsPanelCadastro = New-Object System.Windows.Forms.Panel
    $obsPanelCadastro.BackColor = $osUiSurface
    $obsPanelCadastro.Location = New-Object System.Drawing.Point(20, 382)
    $obsPanelCadastro.Size = New-Object System.Drawing.Size(800, 148)
    [void]$dlg.Controls.Add($obsPanelCadastro)
    Set-RoundedControl -Control $obsPanelCadastro -Radius 6
    $obsRailCadastro = New-Object System.Windows.Forms.Panel
    $obsRailCadastro.BackColor = [System.Drawing.Color]::FromArgb(34,211,238)
    $obsRailCadastro.Location = New-Object System.Drawing.Point(0,0)
    $obsRailCadastro.Size = New-Object System.Drawing.Size(3,148)
    [void]$obsPanelCadastro.Controls.Add($obsRailCadastro)
    $lblObsCadastro = New-Object System.Windows.Forms.Label
    $lblObsCadastro.Text = 'OBSERVACAO'
    $lblObsCadastro.Font = New-Object System.Drawing.Font('Segoe UI',6.5,[System.Drawing.FontStyle]::Bold)
    $lblObsCadastro.ForeColor = [System.Drawing.Color]::FromArgb(34,211,238)
    $lblObsCadastro.Location = New-Object System.Drawing.Point(12,6)
    $lblObsCadastro.Size = New-Object System.Drawing.Size(110,13)
    [void]$obsPanelCadastro.Controls.Add($lblObsCadastro)
    $txtObsCadastro = New-Object System.Windows.Forms.TextBox
    $txtObsCadastro.Multiline = $true
    $txtObsCadastro.MaxLength = 500
    $txtObsCadastro.BorderStyle = 'None'
    $txtObsCadastro.BackColor = $osUiSurface
    $txtObsCadastro.ForeColor = $osUiText
    $txtObsCadastro.Font = New-Object System.Drawing.Font('Segoe UI',8.5)
    $txtObsCadastro.Location = New-Object System.Drawing.Point(12,22)
    $txtObsCadastro.Size = New-Object System.Drawing.Size(774,112)
    [void]$obsPanelCadastro.Controls.Add($txtObsCadastro)

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
        @{c='T031';n='Notebook Lenovo T14 i5 10th';e='1';i=83590341}
        @{c='T031-';n='Notebook Lenovo T14 i7 10th';e='1';i=83591236}
        @{c='T032';n='Notebook Lenovo T14 i5 11th';e='0';i=83064775}
        @{c='T032-';n='Notebook Lenovo T14 i7 11th';e='1';i=83717625}
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
        @{c='A031-C2F';n='Notebook Lenovo T14 I5 10th 8GB 256GB W11P';e='0'}
        @{c='A031-C3F';n='Notebook Lenovo T14 I5 10th 16GB SSD 256 W11P';e='0'}
        @{c='A031-C3H';n='Notebook Lenovo T14 I5 10th 16GB SSD 512 W11P';e='0'}
        @{c='A031-D3F';n='Notebook Lenovo T14 I7 10th 16GB SSD 256 W11P';e='0'}
        @{c='A032-C2F';n='Notebook Lenovo T14 I5 11th 8GB 256GB W11P';e='0'}
        @{c='A032-C3F';n='Notebook Lenovo T14 I5 11th 16GB SSD 256GB W11P';e='0'}
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
        $termoUpper = ([string]$Termo).Trim().ToUpper()
        $buscaCodigo = $termoUpper -match '^[A-Z]+\d+-*$'
        if ($buscaCodigo) {
            $resultadosCodigo = @(
                $script:catalogoProdutosLocal | Where-Object {
                    $codigoAtual = ([string]$_.c).Trim().ToUpper()
                    if ($codigoAtual -match '^P') { return $false }
                    if ($termoUpper.EndsWith('-')) {
                        return ($codigoAtual -eq $termoUpper)
                    }
                    return ($codigoAtual -eq $termoUpper -or $codigoAtual.StartsWith($termoUpper + '-'))
                }
            )
            return @(
                $resultadosCodigo |
                    ForEach-Object {
                        [pscustomobject]@{
                            texto = "$($_.c) - $($_.n)"
                            codigo = $_.c
                            idProduto = if ($_.ContainsKey('i')) { [int]$_.i } else { 0 }
                            descricao = $_.n
                            valor = '0.00'
                            estoque = $_.e
                            estoqueDisplay = if ($_.e -and $_.e -ne '0') { $_.e } else { '' }
                        }
                    } |
                    Sort-Object -Property @{ Expression = { Get-ProdutoSortKeyLocal $_ } }
            )
        }

        $palavras = ($termoUpper -replace '[^A-Z0-9]', ' ' -split '\s+') | Where-Object { $_.Length -ge 2 }
        if ($palavras.Count -eq 0) { return @() }
        $resultados = $script:catalogoProdutosLocal | Where-Object {
            if (([string]$_.c).Trim().ToUpper() -match '^P') { return $false }
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
        $codigoProduto = Get-ProdutoCodigoLocal $Produto
        if ($codigoProduto -match '^P') { return $false }
        if ([int]$Produto.idProduto -gt 0) { return $true }
        return ($codigoProduto -match '^[A-Z]')
    }

    function Format-TecnicoCadastroObservacaoLocal {
        param([string]$Tecnico)
        $t = ([string]$Tecnico).Trim()
        if (-not $t) { return '' }
        return (Get-Culture).TextInfo.ToTitleCase($t.ToLower())
    }

    function Get-CadastroOsDiaPrefixoLocal {
        $agora = Get-Date
        return ('{0} - {1}' -f $agora.ToString('dd/MM/yy'), $agora.ToString('HH:mm'))
    }

    function Format-CadastroOsCpuConfigLocal {
        param([string]$Cpu)

        $cpuTexto = (([string]$Cpu -replace '\s+', ' ').Trim())
        if (-not $cpuTexto) { return '' }
        $cpuTexto = $cpuTexto -replace '(?i)\b(I[3579])\s+([7-9]|1[0-4])\b(?!\s*th)', '$1 $2th'
        $cpuTexto = $cpuTexto -replace '(?i)\bi([3579])\b', 'I$1'
        return $cpuTexto
    }

    function Get-CadastroOsConfiguracaoAtualLocal {
        param([string]$TipoEquipamento = 'Notebook')

        $tipoAtualCadastro = ([string]$TipoEquipamento).Trim()
        if ($tipoAtualCadastro -eq 'Celular') {
            # Nao reutiliza a configuracao detectada do notebook ao cadastrar celular/tablet.
            # Dados lidos pelo 3uTools ja entram na observacao; dados manuais so podem vir
            # do estado que foi efetivamente salvo como Celular.
            if ([string]$script:tipoEtiqueta -ne 'Celular') { return '' }

            $dadosCelular = @()
            foreach ($itemCelular in @(
                @('Armazenamento', [string]$script:memEtiqueta),
                @('Bateria', [string]$script:bateriaEtiqueta),
                @('IMEI', [string]$script:celularImeiEtiqueta)
            )) {
                $valorCelular = (([string]$itemCelular[1] -replace '\s+', ' ').Trim())
                if ($valorCelular -and $valorCelular -notmatch '^(N/A|NA|-)$') {
                    $dadosCelular += ('{0}: {1}' -f [string]$itemCelular[0], $valorCelular)
                }
            }
            if ($dadosCelular.Count -eq 0) { return '' }
            return ('Dados do celular: ' + ($dadosCelular -join ' - '))
        }

        if ($tipoAtualCadastro -eq 'Monitor') { return '' }
        if ($tipoAtualCadastro -eq 'Desktop' -and [string]$script:tipoEtiqueta -ne 'Desktop') { return '' }
        if ($tipoAtualCadastro -eq 'Notebook' -and [string]$script:tipoEtiqueta -ne 'Notebook') { return '' }

        $itensConfig = @()
        foreach ($valor in @(
            (Format-CadastroOsCpuConfigLocal -Cpu $script:cpuEtiqueta),
            [string]$script:memEtiqueta,
            [string]$script:ramEtiqueta
        )) {
            $v = (($valor -replace '\s+', ' ').Trim())
            if ($v -and $v -notmatch '^(N/A|NA|-)$') { $itensConfig += $v }
        }
        if ($itensConfig.Count -eq 0) { return '' }
        return ('Configuracao atual: ' + ($itensConfig -join ' - '))
    }

    function New-CadastroOsObservacaoLocal {
        param(
            [string]$Observacao,
            [string]$Tecnico,
            [string]$TipoEquipamento = 'Notebook'
        )

        $linhas = @()
        $texto = ([string]$Observacao).Trim()
        if ($texto) {
            $linhas += @($texto -split "\r?\n" | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
        }

        $configAtual = Get-CadastroOsConfiguracaoAtualLocal -TipoEquipamento $TipoEquipamento
        if ($configAtual -and -not (($linhas -join "`n") -match '(?i)Configuracao atual\s*:')) {
            $linhas += $configAtual
        }

        $conteudo = ($linhas -join "`r`n").Trim()
        if (-not $conteudo) { return '' }
        if ($conteudo -match '^[A-Z]{3}\s+\(\d{2}/\d{2}/\d{2}\)\s+\d{2}:\d{2}\s+/') { return $conteudo }
        if ($conteudo -match '^\d{2}/\d{2}/\d{4}\s+-\s+\d{2}:\d{2}\s+-') { return $conteudo }

        $tecnicoDisplay = Format-TecnicoCadastroObservacaoLocal -Tecnico $Tecnico
        $prefixo = Get-CadastroOsDiaPrefixoLocal
        if ($tecnicoDisplay) { $prefixo = "$prefixo - ${tecnicoDisplay}" }
        return "${prefixo}: $conteudo"
    }

    function Update-ResumoOs {
        param($Produto)
        if ($Produto) {
            $codigoResumo = Get-ProdutoCodigoLocal $Produto
            if ([int]$Produto.idProduto -gt 0) {
                $txtResumo.Text = "Produto pronto para criar OS. Codigo: $codigoResumo | ID: $([int]$Produto.idProduto)"
            } elseif ($codigoResumo -match '^[A-Z]') {
                $txtResumo.Text = "Produto sem ID na lista; o servidor vai resolver pelo codigo $codigoResumo ao criar."
            } else {
                $txtResumo.Text = 'Selecione um produto com codigo Altertag atual (A/T) ou com ID valido.'
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
        $itemsAtuais = @(
            $Items | Where-Object {
                (Get-ProdutoCodigoLocal $_) -notmatch '^P'
            }
        )
        foreach ($itemProd in $itemsAtuais) { [void]$listProd.Items.Add($itemProd) }
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
            [System.Drawing.Color]::FromArgb(82, 33, 150)
        } elseif (($e.Index % 2) -eq 0) {
            [System.Drawing.Color]::FromArgb(18, 16, 38)
        } else {
            [System.Drawing.Color]::FromArgb(17, 34, 51)
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
            [System.Drawing.Color]::FromArgb(196, 181, 253)
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
            [System.Drawing.Color]::FromArgb(239, 233, 255)
        } elseif ($temEstoque) {
            [System.Drawing.Color]::FromArgb(90, 220, 150)
        } else {
            [System.Drawing.Color]::FromArgb(159, 150, 180)
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
        $linePen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(62, 52, 88))
        $e.Graphics.DrawLine($linePen, ($e.Bounds.Left + 4), ($e.Bounds.Bottom - 1), $e.Bounds.Right, ($e.Bounds.Bottom - 1))
        $linePen.Dispose()
    })

    $cadastroFooterLine = New-Object System.Windows.Forms.Panel
    $cadastroFooterLine.BackColor = [System.Drawing.Color]::FromArgb(35, 67, 91)
    $cadastroFooterLine.Location = New-Object System.Drawing.Point(20, 542)
    $cadastroFooterLine.Size = New-Object System.Drawing.Size(800, 1)
    [void]$dlg.Controls.Add($cadastroFooterLine)

    $cadastroFooterHint = New-Object System.Windows.Forms.Label
    $cadastroFooterHint.Text = 'A confirmacao completa sera exibida antes do envio.'
    $cadastroFooterHint.Font = New-Object System.Drawing.Font('Segoe UI', 7.5)
    $cadastroFooterHint.ForeColor = $osUiDim
    $cadastroFooterHint.Location = New-Object System.Drawing.Point(198, 567)
    $cadastroFooterHint.Size = New-Object System.Drawing.Size(360, 18)
    $cadastroFooterHint.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    [void]$dlg.Controls.Add($cadastroFooterHint)

    $btnCriar = New-Object System.Windows.Forms.Button
    $btnCriar.Text = 'Criar OS'
    $btnCriar.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5, [System.Drawing.FontStyle]::Bold)
    $btnCriar.ForeColor = [System.Drawing.Color]::White
    $btnCriar.BackColor = [System.Drawing.Color]::FromArgb(16, 130, 78)
    $btnCriar.FlatStyle = 'Flat'
    $btnCriar.FlatAppearance.BorderSize = 0
    $btnCriar.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(22, 160, 96)
    $btnCriar.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(10, 100, 60)
    $btnCriar.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnCriar.Enabled = $false
    $btnCriar.Tag = $servicosCadastroEstado
    $btnCriar.Location = New-Object System.Drawing.Point(600, 554)
    $btnCriar.Size = New-Object System.Drawing.Size(220, 42)
    $dlg.Controls.Add($btnCriar)
    Set-RoundedControl -Control $btnCriar -Radius 6
    $btnCriar.Add_EnabledChanged({
        if ($this.Enabled) {
            $this.BackColor = $osUiPrimary
            $this.ForeColor = [System.Drawing.Color]::White
        } else {
            $this.BackColor = $osUiSurfaceRaised
            $this.ForeColor = $osUiDim
        }
    })
    $btnCriar.BackColor = $osUiSurfaceRaised
    $btnCriar.ForeColor = $osUiDim

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
                $txtResumo.Text = 'Falha na busca - o catalogo demorou demais para responder.'
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
                    $txtResumo.Text = "Falha na busca - $(if ($errosBusca.Count -gt 0) { $errosBusca -join ' | ' } else { 'Nenhum produto encontrado.' })"
                }
            } elseif ($script:cadastroOsProdutoBuscaTask.IsFaulted) {
                $erroBusca = $script:cadastroOsProdutoBuscaTask.Exception.GetBaseException().Message
                $lblListaVazia.Text = 'Falha na busca. Tente novamente.'
                $lblListaVazia.Visible = $true
                $lblListaVazia.BringToFront()
                $txtResumo.Text = "Falha na busca - $erroBusca"
            } elseif ($script:cadastroOsProdutoBuscaTask.IsCanceled) {
                $lblListaVazia.Text = 'Busca cancelada por demora'
                $lblListaVazia.Visible = $true
                $lblListaVazia.BringToFront()
                $txtResumo.Text = 'Falha na busca - busca cancelada por demora no catalogo.'
            } else {
                $resp = $script:cadastroOsProdutoBuscaTask.Result | ConvertFrom-Json
                if ($resp.status -and [string]$resp.status -ne 'ok') {
                    $lblListaVazia.Text = 'Nenhum produto encontrado'
                    $lblListaVazia.Visible = $true
                    $lblListaVazia.BringToFront()
                    $txtResumo.Text = "Falha na busca - $([string]$resp.mensagem)"
                } else {
                    $items = @(Convert-ProdutoResponseToItems -Resp $resp)
                    Set-ProdutoItems -Items $items -Fonte ([string]$resp.fonte) -Mensagem ([string]$resp.mensagem)
                }
            }
        } catch {
            $lblListaVazia.Text = 'Falha na busca. Tente novamente.'
            $lblListaVazia.Visible = $true
            $lblListaVazia.BringToFront()
            $txtResumo.Text = "Falha na busca - $($_.Exception.Message)"
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
            $txtResumo.Text = "Busca em andamento - $termo"
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
            $txtResumo.Text = "Buscando produtos no catalogo - $termo$(if ($termosServidor.Count -gt 1) { " -> $($termosServidor -join ', ')" } elseif ($termosServidor[0] -ne $termo) { " -> $($termosServidor[0])" } else { '' })"
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
            $txtResumo.Text = "Falha na busca - $($_.Exception.Message)"
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

    $btnLer3uCadastro.Add_Click({
        $btnLer3uCadastro.Enabled = $false
        $btnLer3uCadastro.Text = 'Lendo...'
        [System.Windows.Forms.Application]::DoEvents()
        try {
            $device3u = Get-3uToolsDeviceInfo
            $servicosCadastroEstado.DadosCelular = $device3u
            $txtSerialOs.Text = [string]$device3u.Serial
            $txtBuscaProd.Text = [string]$device3u.Modelo
            $detalhes3u = @("IMEI: $([string]$device3u.Imei)")
            if ($device3u.Armazenamento) { $detalhes3u += "Armazenamento: $([string]$device3u.Armazenamento)" }
            if ($device3u.Bateria) { $detalhes3u += "Bateria: $([string]$device3u.Bateria)" }
            if ([int]$device3u.Ciclos -gt 0) { $detalhes3u += "Ciclos: $([int]$device3u.Ciclos)" }
            $linha3u = $detalhes3u -join ' | '
            $obsAtual = $txtObsCadastro.Text.Trim()
            if ($obsAtual -notmatch '(?i)\bIMEI\s*:') {
                $txtObsCadastro.Text = if ($obsAtual) { "$obsAtual`r`n$linha3u" } else { $linha3u }
            }
            $txtResumo.Text = "3uTools: $([string]$device3u.Modelo) | $linha3u"
            $btnBuscaProd.PerformClick()
        } catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Nao foi possivel ler o iPhone.`r`n`r`n$($_.Exception.Message)",
                'Leitura do 3uTools', 'OK', 'Warning'
            ) | Out-Null
        } finally {
            $btnLer3uCadastro.Enabled = $true
            $btnLer3uCadastro.Text = 'Ler informacoes 3uTools'
        }
    })

    # $cmbTec e PSCustomObject — atualizacao do resumo feita no Add_Click de cada botao toggle
    $txtSerialOs.Add_TextChanged({ Update-ResumoOs -Produto $listProd.SelectedItem })

    $btnFecharDlg = New-Object System.Windows.Forms.Button
    $btnFecharDlg.Text = 'Cancelar'
    $btnFecharDlg.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $btnFecharDlg.ForeColor = [System.Drawing.Color]::FromArgb(218, 176, 184)
    $btnFecharDlg.BackColor = [System.Drawing.Color]::FromArgb(31, 22, 31)
    $btnFecharDlg.FlatStyle = 'Flat'
    $btnFecharDlg.FlatAppearance.BorderSize = 1
    $btnFecharDlg.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(112, 55, 69)
    $btnFecharDlg.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(59, 28, 39)
    $btnFecharDlg.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(70, 22, 32)
    $btnFecharDlg.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnFecharDlg.Location = New-Object System.Drawing.Point(20, 554)
    $btnFecharDlg.Size = New-Object System.Drawing.Size(160, 42)
    $btnFecharDlg.Add_Click({ $dlg.Close() })
    $dlg.Controls.Add($btnFecharDlg)
    Set-RoundedControl -Control $btnFecharDlg -Radius 6

    $btnCriar.Add_Click({
        if (-not $listProd.SelectedItem) { return }
        $prodSel = $listProd.SelectedItem
        $codigoProdutoSel = Get-ProdutoCodigoLocal $prodSel
        if (-not (Test-ProdutoSelecionavel $prodSel)) {
            [System.Windows.Forms.MessageBox]::Show('Selecione um produto com codigo Altertag atual (A/T) ou retornado com ID pela API antes de criar a OS.', 'Cadastrar OS', 'OK', 'Warning') | Out-Null
            return
        }
        if (-not $txtSerialOs.Text.Trim()) {
            [System.Windows.Forms.MessageBox]::Show('Informe o serial antes de criar a OS.', 'Cadastrar OS', 'OK', 'Warning') | Out-Null
            return
        }
        $estadoServicosAtual = $this.Tag
        $servicosMarcados = @()
        $produtoDescricaoSel = [string]$prodSel.descricao
        $tipoCadastroInferido = if ($estadoServicosAtual.DadosCelular -or (Test-CelularProduto -Descricao $produtoDescricaoSel)) {
            'Celular'
        } elseif ($produtoDescricaoSel -match '(?i)\b(Monitor|Display|Tela)\b') {
            'Monitor'
        } elseif (Test-DesktopProduto -Descricao $produtoDescricaoSel) {
            'Desktop'
        } else {
            'Notebook'
        }
        $qtdSel = Get-ProdutoQuantidadeOsDisplayLocal $prodSel
        $observacaoCadastroFinal = New-CadastroOsObservacaoLocal -Observacao ($txtObsCadastro.Text.Trim()) -Tecnico ([string]$cmbTec.SelectedItem) -TipoEquipamento $tipoCadastroInferido
        $confirm = Show-CadastroOsConfirm `
            -Owner $dlg `
            -OsCodigo (Format-OsCodigo -Numero $script:osNumero) `
            -Produto ([string]$prodSel.texto) `
            -Quantidade $(if ($qtdSel) { $qtdSel } else { '1,00' }) `
            -Serial ($txtSerialOs.Text.Trim()) `
            -Referencia ($btnGradeOs.Text.Trim()) `
            -Servicos 'nao utilizado' `
            -Localizacao 'Bancada tecnica' `
            -Observacao $observacaoCadastroFinal
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
                produtoDescricao = $produtoDescricaoSel
                produtoValor = [string]$prodSel.valor
                servicos = @($servicosMarcados)
                tipoEquipamento = $tipoCadastroInferido
                observacao = $observacaoCadastroFinal
            }
            $payload = $payloadObj | ConvertTo-Json -Depth 5 -Compress
            $resp = Invoke-RestMethod -Uri ('{0}/criar-os-altertag' -f (Get-ServidorBaseUrl)) -Method Post -Body $payload -ContentType 'application/json; charset=utf-8' -TimeoutSec 45 -ErrorAction Stop
            if ([string]$resp.status -ne 'ok') { throw [Exception]::new([string]$resp.mensagem) }
            $osCriadaNumero = [int]$resp.osNumero
            $proximaOsNumero = if ($resp.proximoDisponivel) { [int]$resp.proximoDisponivel } else { $osCriadaNumero + 1 }
            $script:altertagOsAtual = [pscustomobject]@{
                idOrdem = [int]$resp.idOrdem
                numero = [int]$resp.osNumero
                osCodigo = [string]$resp.osCodigo
                cliente = [string]$resp.cliente
                tecnico = [string]$resp.tecnico
                statusOs = 'Em Aberto'
                equipamento = Get-ModeloEtiquetaProduto -Descricao $produtoDescricaoSel -CodigoProduto $codigoProdutoSel
                garantia = [string]$resp.garantia
                referencia = [string]$resp.referencia
            }
            $script:incluirOSAtual = $true
            $script:maiorOsVistaAltertag = [Math]::Max([int]$script:maiorOsVistaAltertag, $osCriadaNumero)
            $script:ultimoAlertaOsNumero = [Math]::Max([int]$script:ultimoAlertaOsNumero, $osCriadaNumero)
            $script:ultimoConfirmadoServidor = [Math]::Max([int]$script:ultimoConfirmadoServidor, $osCriadaNumero)
            Set-OsNumeroAtual -Numero $proximaOsNumero -Fonte 'concorrencia'
            Set-AppStatus -Texto "OS $($resp.osCodigo) criada | proxima disponivel: $(Format-OsCodigo -Numero $proximaOsNumero)" -Cor $cGreen
            $acaoResultado = Show-CadastroOsResult `
                -Owner $dlg `
                -OsCodigo ([string]$resp.osCodigo) `
                -ProdutoErro ([string]$resp.produtoErro) `
                -ServicosErro ([string]$resp.servicosErro)
            if ($acaoResultado -eq 'imprimir') {
                $etiquetaCadastro = $null
                if ($tipoCadastroInferido -eq 'Celular') {
                    $dadosCelularCadastro = $estadoServicosAtual.DadosCelular
                    $modeloCelularCadastro = if ($dadosCelularCadastro -and ([string]$dadosCelularCadastro.Modelo).Trim()) {
                        ([string]$dadosCelularCadastro.Modelo).Trim()
                    } else {
                        Get-ModeloEtiquetaProduto -Descricao $produtoDescricaoSel -CodigoProduto $codigoProdutoSel
                    }
                    $etiquetaCadastro = [pscustomobject]@{
                        tipoEquipamento = 'Celular'
                        produtoCodigo = $codigoProdutoSel
                        modelo = $modeloCelularCadastro
                        serial = $txtSerialOs.Text.Trim()
                        imei = if ($dadosCelularCadastro) { [string]$dadosCelularCadastro.Imei } else { '' }
                        bateria = if ($dadosCelularCadastro) { [string]$dadosCelularCadastro.Bateria } else { '' }
                        armazenamento = if ($dadosCelularCadastro) { [string]$dadosCelularCadastro.Armazenamento } else { '' }
                    }
                } elseif ($tipoCadastroInferido -eq 'Desktop') {
                    $etiquetaCadastro = [pscustomobject]@{
                        tipoEquipamento = 'Desktop'
                        produtoCodigo = $codigoProdutoSel
                        modelo = Get-ModeloEtiquetaProduto -Descricao $produtoDescricaoSel -CodigoProduto $codigoProdutoSel
                        serial = $txtSerialOs.Text.Trim()
                        cpu = ''
                        ram = ''
                        armazenamento = ''
                        gpu = ''
                        bateria = ''
                    }
                }
                $script:osImpressaoPendente = [pscustomobject]@{
                    osNumero = $osCriadaNumero
                    ordem = $script:altertagOsAtual
                    etiqueta = $etiquetaCadastro
                    observacao = $observacaoCadastroFinal
                }
            }
            $dlg.Close()
            if ($acaoResultado -eq 'imprimir') {
                [void]$form.BeginInvoke([System.Action]{
                    if ($btnImprimir.Enabled) { $btnImprimir.PerformClick() }
                })
            }
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Falha ao criar OS:`n$($_.Exception.Message)", 'Cadastrar OS', 'OK', 'Error') | Out-Null
        } finally {
            $btnCriar.Enabled = ($listProd.SelectedItem -and (Test-ProdutoSelecionavel $listProd.SelectedItem))
            $btnCriar.Text = 'Criar OS'
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

    # Composicao final: hierarquia compacta, superfícies consistentes e uma unica cor de acao.
    $infoOsPanel.Location = New-Object System.Drawing.Point(664, 106)
    $infoOsPanel.Size = New-Object System.Drawing.Size(232, 304)
    $infoOsPanel.BackColor = $osUiSurface
    $infoOsAccent.Visible = $false

    $cardTec.Location = New-Object System.Drawing.Point(12, 12)
    $cardTec.Size = New-Object System.Drawing.Size(208, 88)
    $cardSerial.Location = New-Object System.Drawing.Point(12, 106)
    $cardSerial.Size = New-Object System.Drawing.Size(208, 50)
    $cardGrade.Location = New-Object System.Drawing.Point(12, 162)
    $cardGrade.Size = New-Object System.Drawing.Size(208, 50)
    $cardOs.Location = New-Object System.Drawing.Point(12, 218)
    $cardOs.Size = New-Object System.Drawing.Size(208, 74)
    foreach ($card in @($cardTec, $cardSerial, $cardGrade)) { $card.BackColor = $osUiSurfaceRaised }
    foreach ($rail in @($cardTecBar, $cardSerialBar, $cardGradeBar)) { $rail.Visible = $false }
    $cardOs.BackColor = [System.Drawing.Color]::FromArgb(10, 41, 34)
    $cardOsBar.Size = New-Object System.Drawing.Size(3, 74)

    $lblTecCaption.Location = New-Object System.Drawing.Point(12, 9)
    $lblTecCaption.Size = New-Object System.Drawing.Size(184, 13)
    $lblTecCaption.ForeColor = $osUiMuted
    $lblTecnicoEscolhido.Location = New-Object System.Drawing.Point(12, 30)
    $lblTecnicoEscolhido.Size = New-Object System.Drawing.Size(116, 30)
    $btnTrocarTecnico.Location = New-Object System.Drawing.Point(134, 29)
    $btnTrocarTecnico.Size = New-Object System.Drawing.Size(62, 30)
    $btnTrocarTecnico.BackColor = $osUiSurface
    $btnTrocarTecnico.ForeColor = $osUiText
    $btnTrocarTecnico.FlatAppearance.BorderColor = $osUiBorder

    $lblSerialCaption.Location = New-Object System.Drawing.Point(12, 7)
    $lblSerialCaption.Size = New-Object System.Drawing.Size(184, 13)
    $lblSerialCaption.ForeColor = $osUiMuted
    $txtSerialOs.Location = New-Object System.Drawing.Point(12, 25)
    $txtSerialOs.Size = New-Object System.Drawing.Size(184, 20)
    $txtSerialOs.BackColor = $osUiSurfaceRaised

    $lblGradeCaption.Location = New-Object System.Drawing.Point(12, 7)
    $lblGradeCaption.Size = New-Object System.Drawing.Size(184, 13)
    $lblGradeCaption.ForeColor = $osUiMuted
    $btnGradeOs.Location = New-Object System.Drawing.Point(7, 21)
    $btnGradeOs.Size = New-Object System.Drawing.Size(194, 27)

    $lblOsCaption.Location = New-Object System.Drawing.Point(12, 10)
    $lblOsCaption.Size = New-Object System.Drawing.Size(184, 13)
    $lblOsTopoValor.Location = New-Object System.Drawing.Point(12, 31)
    $lblOsTopoValor.Size = New-Object System.Drawing.Size(184, 30)

    $buscaHeader.Location = New-Object System.Drawing.Point(24, 106)
    $buscaHeader.Size = New-Object System.Drawing.Size(620, 30)
    $buscaHeader.BackColor = $osUiBg
    $buscaHeaderAccent.Visible = $false
    $lblBusca.Location = New-Object System.Drawing.Point(0, 8)
    $lblBusca.ForeColor = $osUiPrimaryHover
    $lblBuscaHint.Location = New-Object System.Drawing.Point(86, 8)
    $lblBuscaHint.Size = New-Object System.Drawing.Size(520, 14)

    $buscaPanel.Location = New-Object System.Drawing.Point(24, 138)
    $buscaPanel.Size = New-Object System.Drawing.Size(620, 48)
    $buscaPanel.BackColor = $osUiSurfaceRaised
    $lblLupa.Location = New-Object System.Drawing.Point(12, 11)
    $lblLupa.ForeColor = $osUiPrimaryHover
    $txtBuscaProd.Location = New-Object System.Drawing.Point(44, 14)
    $txtBuscaProd.Size = New-Object System.Drawing.Size(422, 22)
    $txtBuscaProd.BackColor = $osUiSurfaceRaised
    $buscaDivider.Location = New-Object System.Drawing.Point(474, 9)
    $btnBuscaProd.Location = New-Object System.Drawing.Point(480, 4)
    $btnBuscaProd.Size = New-Object System.Drawing.Size(136, 40)
    $btnBuscaProd.BackColor = $osUiPrimary
    $btnBuscaProd.FlatAppearance.MouseOverBackColor = $osUiPrimaryHover
    $btnBuscaProd.FlatAppearance.MouseDownBackColor = $osUiBorderStrong

    $prodPanel.Location = New-Object System.Drawing.Point(24, 194)
    $prodPanel.Size = New-Object System.Drawing.Size(620, 174)
    $prodPanel.BackColor = $osUiSurface
    $prodHead.Size = New-Object System.Drawing.Size(618, 30)
    $prodHead.BackColor = $osUiSurfaceRaised
    $prodHeadAccent.Visible = $false
    foreach ($cabecalho in @($prodHead.Controls | Where-Object { $_ -is [System.Windows.Forms.Label] })) {
        switch ([string]$cabecalho.Text) {
            'CODIGO'  { $cabecalho.Location = New-Object System.Drawing.Point(12, 9);  $cabecalho.Size = New-Object System.Drawing.Size(88, 13) }
            'PRODUTO' { $cabecalho.Location = New-Object System.Drawing.Point(116, 9); $cabecalho.Size = New-Object System.Drawing.Size(388, 13) }
            'ESTOQUE' { $cabecalho.Location = New-Object System.Drawing.Point(538, 9); $cabecalho.Size = New-Object System.Drawing.Size(68, 13) }
        }
    }
    $divisoresProduto = @($prodHead.Controls | Where-Object { $_ -is [System.Windows.Forms.Panel] -and $_ -ne $prodHeadAccent })
    if ($divisoresProduto.Count -ge 2) {
        $divisoresProduto[0].Location = New-Object System.Drawing.Point(104, 7)
        $divisoresProduto[1].Location = New-Object System.Drawing.Point(522, 7)
    }
    $listProd.Location = New-Object System.Drawing.Point(1, 31)
    $listProd.Size = New-Object System.Drawing.Size((616 + [System.Windows.Forms.SystemInformation]::VerticalScrollBarWidth + 2), 141)
    $scrollProd.Location = New-Object System.Drawing.Point(608, 33)
    $scrollProd.Size = New-Object System.Drawing.Size(8, 137)
    $lblListaVazia.Location = New-Object System.Drawing.Point(1, 31)
    $lblListaVazia.Size = New-Object System.Drawing.Size(616, 141)

    $buscaStatus.Location = New-Object System.Drawing.Point(24, 376)
    $buscaStatus.Size = New-Object System.Drawing.Size(620, 34)
    $buscaStatus.BackColor = $osUiSurface
    $buscaStatusDot.Location = New-Object System.Drawing.Point(14, 13)
    $buscaStatusDot.BackColor = $osUiPrimary
    $txtResumo.Location = New-Object System.Drawing.Point(32, 9)
    $txtResumo.Size = New-Object System.Drawing.Size(574, 17)

    $servHeader.Location = New-Object System.Drawing.Point(24, 428)
    $servHeader.Size = New-Object System.Drawing.Size(872, 38)
    $servHeader.BackColor = $osUiBg
    $servHeaderAccent.Visible = $false
    $lblServ.Location = New-Object System.Drawing.Point(0, 12)
    $lblServ.Size = New-Object System.Drawing.Size(154, 14)
    $lblServ.ForeColor = $osUiPrimaryHover
    $lblServHint.Location = New-Object System.Drawing.Point(164, 12)
    $lblServHint.Size = New-Object System.Drawing.Size(490, 14)
    $btnLer3uCadastro.Location = New-Object System.Drawing.Point(674, 4)
    $btnLer3uCadastro.Size = New-Object System.Drawing.Size(198, 30)
    $btnLer3uCadastro.BackColor = $osUiSurfaceRaised
    $btnLer3uCadastro.ForeColor = $osUiText
    $btnLer3uCadastro.FlatAppearance.BorderSize = 1
    $btnLer3uCadastro.FlatAppearance.BorderColor = $osUiBorder

    $tipoPanel.Location = New-Object System.Drawing.Point(24, 468)
    $tipoPanel.Size = New-Object System.Drawing.Size(872, 34)
    $servPanel.Location = New-Object System.Drawing.Point(24, 506)
    $servPanel.Size = New-Object System.Drawing.Size(872, 52)

    $obsPanelCadastro.Location = New-Object System.Drawing.Point(24, 474)
    $obsPanelCadastro.Size = New-Object System.Drawing.Size(872, 132)
    $obsPanelCadastro.BackColor = $osUiSurface
    $obsRailCadastro.Visible = $false
    $lblObsCadastro.Location = New-Object System.Drawing.Point(14, 10)
    $lblObsCadastro.ForeColor = $osUiMuted
    $txtObsCadastro.Location = New-Object System.Drawing.Point(14, 30)
    $txtObsCadastro.Size = New-Object System.Drawing.Size(844, 90)
    $txtObsCadastro.BackColor = $osUiSurface

    $cadastroFooterLine.Location = New-Object System.Drawing.Point(24, 622)
    $cadastroFooterLine.Size = New-Object System.Drawing.Size(872, 1)
    $cadastroFooterLine.BackColor = $osUiBorder
    $cadastroFooterHint.Location = New-Object System.Drawing.Point(250, 646)
    $cadastroFooterHint.Size = New-Object System.Drawing.Size(420, 18)
    $btnFecharDlg.Location = New-Object System.Drawing.Point(24, 636)
    $btnFecharDlg.Size = New-Object System.Drawing.Size(144, 42)
    $btnFecharDlg.BackColor = $osUiSurface
    $btnFecharDlg.ForeColor = $osUiText
    $btnFecharDlg.FlatAppearance.BorderColor = $osUiBorder
    $btnFecharDlg.FlatAppearance.MouseOverBackColor = $osUiSurfaceRaised
    $btnFecharDlg.FlatAppearance.MouseDownBackColor = $osUiBorder
    $btnCriar.Location = New-Object System.Drawing.Point(704, 636)
    $btnCriar.Size = New-Object System.Drawing.Size(192, 42)
    $btnCriar.FlatAppearance.MouseOverBackColor = $osUiPrimaryHover
    $btnCriar.FlatAppearance.MouseDownBackColor = $osUiBorderStrong

    $dlg.AcceptButton = $btnCriar
    $dlg.CancelButton = $btnFecharDlg
    $dlg.Add_KeyDown({ if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { $dlg.Close() } })
    $btnFecharCadastroTopo.BringToFront()

    Set-CaijWindowsTypography -Root $dlg
    [void]$dlg.ShowDialog($form)
}

$btnCadastrarOs.Add_Click({
    $tecnicoCadastro = Show-TecnicoCadastroOs -Owner $form
    if (-not [string]::IsNullOrWhiteSpace($tecnicoCadastro)) {
        Show-CadastroOsAltertagDraft -TecnicoInicial $tecnicoCadastro
    }
})

$btnTestes.Add_Click({
    try {
        $workspaceDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
        $launcherTeste = Join-Path $workspaceDir 'TestarNotebook.vbs'
        if (Test-Path $launcherTeste) {
            Start-Process wscript.exe -ArgumentList ('//B //Nologo "' + $launcherTeste + '"') -WindowStyle Hidden
        } else {
            [System.Windows.Forms.MessageBox]::Show("Inicializador de testes nao encontrado:`n$launcherTeste", 'Central de Testes', 'OK', 'Warning') | Out-Null
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
    $printContext = [pscustomobject]@{
        OsNumero = [int]$script:osNumero
        Ordem = $script:altertagOsAtual
        CriadaAgora = $false
        Etiqueta = $null
        Observacao = ''
    }
    if ($script:osImpressaoPendente -and [int]$script:osImpressaoPendente.osNumero -gt 0) {
        $printContext.OsNumero = [int]$script:osImpressaoPendente.osNumero
        $printContext.Ordem = $script:osImpressaoPendente.ordem
        $printContext.CriadaAgora = $true
        $printContext.Etiqueta = $script:osImpressaoPendente.etiqueta
        $printContext.Observacao = [string]$script:osImpressaoPendente.observacao
        $script:osImpressaoPendente = $null
    }
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
    if ($gpuCurta -match '(?i)MX\s*450') { $gpuCurta = "MX450$gpuVramSuf Dedicada" }
    elseif ($gpuCurta -match '(?i)MX\s*350') { $gpuCurta = "MX350$gpuVramSuf Dedicada" }
    elseif ($gpuCurta -match '(?i)QUADRO\s+RTX\s*([0-9]{4})') { $gpuCurta = "Quadro RTX $($Matches[1])$gpuVramSuf Dedicada" }
    elseif ($gpuCurta -match '(?i)RTX\s*([0-9]{4})') { $gpuCurta = "RTX $($Matches[1])$gpuVramSuf Dedicada" }
    elseif ($gpuCurta -match '(?i)GTX\s*([0-9]{3,4})') { $gpuCurta = "GTX $($Matches[1])$gpuVramSuf Dedicada" }
    elseif ($gpuCurta -match '(?i)Iris\s*Xe') { $gpuCurta = 'Intel Iris Xe' }
    elseif ($gpuCurta -match '(?i)UHD') { $gpuCurta = 'Intel UHD' }
    elseif ($gpuCurta.Length -gt 28) { $gpuCurta = $gpuCurta.Substring(0, 28) }
    if ($gpuVramSuf -and $gpuCurta -notmatch '(?i)\bGB\b') { $gpuCurta += $gpuVramSuf }
    function Format-GpuEtiquetaLocal {
        param([string]$Gpu)
        $gpuTexto = (([string]$Gpu -replace '\s+', ' ').Trim())
        $gpuTexto = $gpuTexto -replace '(?i)^NVIDIA\s+', ''
        $gpuTexto = $gpuTexto -replace '(?i)\s*\(\s*DEDICADA\s*\)\s*$', ' DED.'
        $gpuTexto = $gpuTexto -replace '(?i)\s+DEDICADA\s*$', ' DED.'
        return $gpuTexto.Trim()
    }
    $script:IsGpuEtiquetaVisivel = {
        param([string]$Gpu)
        $g = if ($Gpu) { $Gpu.Trim() } else { '' }
        return ($g -ne '' -and $g -notmatch '^(?i:N/?A|Nao identificada|Não identificada)$')
    }
    $script:IsBateriaEtiquetaVisivel = {
        param([string]$Bateria)
        return (
            [bool]$info.MostrarBateria -and
            [string]$script:tipoEtiqueta -ne 'Desktop' -and
            -not [string]::IsNullOrWhiteSpace($Bateria)
        )
    }

    # ================================================
    # POPUP PREVIA DE IMPRESSAO
    # ================================================
    $popup = New-Object System.Windows.Forms.Form
    $popup.Text            = 'Previa de Impressao'
    $previewUiBg = [System.Drawing.Color]::FromArgb(7, 9, 17)
    $previewUiSurface = [System.Drawing.Color]::FromArgb(15, 18, 29)
    $previewUiRaised = [System.Drawing.Color]::FromArgb(21, 24, 38)
    $previewUiBorder = [System.Drawing.Color]::FromArgb(42, 46, 63)
    $previewUiPrimary = [System.Drawing.Color]::FromArgb(94, 106, 210)
    $previewUiPrimaryHover = [System.Drawing.Color]::FromArgb(112, 124, 228)
    $previewUiText = [System.Drawing.Color]::FromArgb(240, 242, 248)
    $previewUiMuted = [System.Drawing.Color]::FromArgb(166, 170, 184)

    $popup.AutoScaleMode   = [System.Windows.Forms.AutoScaleMode]::None
    $popup.ClientSize      = New-Object System.Drawing.Size(920, 628)
    $popup.StartPosition   = 'CenterScreen'
    $popup.BackColor       = $previewUiBg
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
        $border = New-Object System.Drawing.Pen($previewUiBorder, 1)
        $e.Graphics.DrawRectangle($border, 0, 0, ($s.ClientSize.Width - 1), ($s.ClientSize.Height - 1))
        $border.Dispose()
    })

    $headerAccent = New-Object System.Windows.Forms.Panel
    $headerAccent.Location = New-Object System.Drawing.Point(0, 0)
    $headerAccent.Size = New-Object System.Drawing.Size(5, 72)
    $headerAccent.BackColor = $cAccent
    $headerAccent.Visible = $false
    $popup.Controls.Add($headerAccent)

    $headerSurface = New-Object System.Windows.Forms.Panel
    $headerSurface.Location = New-Object System.Drawing.Point(0, 0)
    $headerSurface.Size = New-Object System.Drawing.Size(920, 72)
    $headerSurface.BackColor = $previewUiSurface
    $popup.Controls.Add($headerSurface)
    $headerSurface.Add_Paint({
        param($s, $e)
        $line = New-Object System.Drawing.Pen($previewUiBorder, 1)
        $e.Graphics.DrawLine($line, 0, ($s.Height - 1), $s.Width, ($s.Height - 1))
        $line.Dispose()
    })

    $popEyebrow = New-Object System.Windows.Forms.Label
    $popEyebrow.Text = 'IMPRESSAO / ETIQUETA TERMICA'
    $popEyebrow.Font = New-Object System.Drawing.Font('Segoe UI', 6.8, [System.Drawing.FontStyle]::Bold)
    $popEyebrow.ForeColor = $previewUiPrimaryHover
    $popEyebrow.Location = New-Object System.Drawing.Point(19, 9)
    $popEyebrow.Size = New-Object System.Drawing.Size(260, 14)
    $headerSurface.Controls.Add($popEyebrow)

    $popTitle = New-Object System.Windows.Forms.Label
    $popTitle.Text = 'Previa de impressao'
    $popTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 15, [System.Drawing.FontStyle]::Bold)
    $popTitle.ForeColor = $previewUiText
    $popTitle.Location = New-Object System.Drawing.Point(17, 25)
    $popTitle.Size = New-Object System.Drawing.Size(310, 28)
    $headerSurface.Controls.Add($popTitle)

    $popSub = New-Object System.Windows.Forms.Label
    $popSub.Text = 'A imagem abaixo acompanha o layout enviado para a impressora'
    $popSub.Font = New-Object System.Drawing.Font('Segoe UI', 7.5)
    $popSub.ForeColor = $previewUiMuted
    $popSub.Location = New-Object System.Drawing.Point(20, 52)
    $popSub.Size = New-Object System.Drawing.Size(410, 15)
    $headerSurface.Controls.Add($popSub)

    $popChip = New-Object System.Windows.Forms.Panel
    $popChip.Location = New-Object System.Drawing.Point(718, 21)
    $popChip.Size = New-Object System.Drawing.Size(142, 32)
    $popChip.BackColor = $previewUiRaised
    $popChip.BorderStyle = 'None'
    $headerSurface.Controls.Add($popChip)
    Set-RoundedControl -Control $popChip -Radius 8

    $popChipText = New-Object System.Windows.Forms.Label
    $popChipText.Text = '80 x 50 mm'
    $popChipText.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5, [System.Drawing.FontStyle]::Bold)
    $popChipText.ForeColor = $previewUiText
    $popChipText.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $popChipText.Location = New-Object System.Drawing.Point(0, 7)
    $popChipText.Size = New-Object System.Drawing.Size(142, 18)
    $popChip.Controls.Add($popChipText)

    $popClose = New-Object System.Windows.Forms.Button
    $popClose.Text = 'X'
    $popClose.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
    $popClose.ForeColor = $previewUiMuted
    $popClose.BackColor = $headerSurface.BackColor
    $popClose.FlatStyle = 'Flat'
    $popClose.FlatAppearance.BorderSize = 0
    $popClose.FlatAppearance.MouseOverBackColor = $previewUiRaised
    $popClose.Location = New-Object System.Drawing.Point(878, 8)
    $popClose.Size = New-Object System.Drawing.Size(28, 28)
    $popClose.Cursor = [System.Windows.Forms.Cursors]::Hand
    $popClose.Add_Click({ $popup.DialogResult = 'Cancel'; $popup.Close() })
    $headerSurface.Controls.Add($popClose)

    $previewDrag = [pscustomobject]@{ Ativo=$false; Origem=[System.Drawing.Point]::Empty }
    $headerSurface.Add_MouseDown({
        if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) { $previewDrag.Ativo=$true; $previewDrag.Origem=$_.Location }
    })
    $headerSurface.Add_MouseMove({
        if ($previewDrag.Ativo) { $popup.Location = New-Object System.Drawing.Point(($popup.Left + $_.X - $previewDrag.Origem.X), ($popup.Top + $_.Y - $previewDrag.Origem.Y)) }
    })
    $headerSurface.Add_MouseUp({ $previewDrag.Ativo=$false })

    $previewBack = New-Object System.Windows.Forms.Panel
    $previewBack.Location = New-Object System.Drawing.Point(20, 88)
    $previewBack.Size = New-Object System.Drawing.Size(592, 376)
    $previewBack.BackColor = $previewUiSurface
    $previewBack.BorderStyle = 'None'
    $popup.Controls.Add($previewBack)
    Set-RoundedControl -Control $previewBack -Radius 8
    $previewBack.Add_Paint({
        $pen = New-Object System.Drawing.Pen($previewUiBorder, 1)
        $_.Graphics.DrawRectangle($pen, 0, 0, ($this.Width - 1), ($this.Height - 1))
        $pen.Dispose()
    })

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
    $controlDeck.Size = New-Object System.Drawing.Size(272, 340)
    $controlDeck.BackColor = $previewUiSurface
    $popup.Controls.Add($controlDeck)
    Set-RoundedControl -Control $controlDeck -Radius 8
    $controlDeck.Add_Paint({
        $pen = New-Object System.Drawing.Pen($previewUiBorder, 1)
        $_.Graphics.DrawRectangle($pen, 0, 0, ($this.Width - 1), ($this.Height - 1))
        $pen.Dispose()
    })
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
        $script:tipoEtiqueta = [string]$info.TipoEquipamento
        $script:monitorTamanhoEtiqueta = ''
        $script:monitorEntradasEtiqueta = ''
        $script:celularImeiEtiqueta = ''
        $script:modoManualEtiqueta = $false
        $script:rnaAtivo = $false
        $script:rnaItensOk = @()
        $script:gradeAnteriorRma = 'A'
        $script:pinturaOpcaoAtual = ''
    }
    if ($printContext.CriadaAgora) {
        $script:incluirOSAtual = $true
        if (-not [string]::IsNullOrWhiteSpace($printContext.Observacao)) {
            $script:obsAtual = $printContext.Observacao.Trim()
        }
        Apply-OsAltertagNaEtiqueta -Ordem $printContext.Ordem
        Apply-CadastroOsEtiquetaNaImpressao -Etiqueta $printContext.Etiqueta
        $referenciaCriada = if ($printContext.Ordem) { ([string]$printContext.Ordem.referencia).Trim().ToUpperInvariant() } else { '' }
        foreach ($gradeOpcaoCriada in @(Get-CaijGradeOptions)) {
            if ((Format-CaijGradeReference $gradeOpcaoCriada).ToUpperInvariant() -eq $referenciaCriada) {
                $script:gradeAtual = $gradeOpcaoCriada
                break
            }
        }
    } elseif ($script:osDefinidaPorAltertag -and $script:altertagOsAtual) {
        $script:incluirOSAtual = $true
        Apply-OsAltertagNaEtiqueta -Ordem $script:altertagOsAtual
    }

    $altertagResumoPreview = Get-OsAltertagResumoPreview `
        -OsNumero $printContext.OsNumero `
        -OrdemFallback $printContext.Ordem

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
        $f1 = New-Object System.Drawing.Font('Segoe UI', 5.8, [System.Drawing.FontStyle]::Bold)
        $f2 = New-Object System.Drawing.Font('Segoe UI Semibold', 7.2, [System.Drawing.FontStyle]::Bold)
        $f3 = New-Object System.Drawing.Font('Segoe UI Semibold', 9.4, [System.Drawing.FontStyle]::Bold)
        $f4 = New-Object System.Drawing.Font('Segoe UI Semibold', 13.2, [System.Drawing.FontStyle]::Bold)
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

        function QrPreview($payload, $x, $y, $size) {
            $qrPanel = New-Object System.Windows.Forms.Panel
            $qrPanel.BackColor = [System.Drawing.Color]::White
            $qrPanel.Location = New-Object System.Drawing.Point(
                [int][math]::Round($x * $scaleX),
                [int][math]::Round($y * $scaleY)
            )
            $qrPanel.Size = New-Object System.Drawing.Size(
                [int][math]::Max(1, [math]::Round($size * $scaleX)),
                [int][math]::Max(1, [math]::Round($size * $scaleY))
            )
            $qrPayloadLocal = [string]$payload
            $qrPanel.Add_Paint({
                param($sender, $e)
                $modules = 41
                $cell = [Math]::Max(1, [Math]::Floor([Math]::Min($sender.ClientSize.Width, $sender.ClientSize.Height) / $modules))
                $drawSize = $cell * $modules
                $offsetX = [Math]::Floor(($sender.ClientSize.Width - $drawSize) / 2)
                $offsetY = [Math]::Floor(($sender.ClientSize.Height - $drawSize) / 2)
                $seed = 0
                foreach ($ch in $qrPayloadLocal.ToCharArray()) { $seed = (($seed * 31) + [int]$ch) -band 0x7fffffff }
                $brush = [System.Drawing.Brushes]::Black
                for ($row = 0; $row -lt $modules; $row++) {
                    for ($col = 0; $col -lt $modules; $col++) {
                        $finderRow = -1
                        $finderCol = -1
                        if ($row -lt 7 -and $col -lt 7) { $finderRow = $row; $finderCol = $col }
                        elseif ($row -lt 7 -and $col -ge ($modules - 7)) { $finderRow = $row; $finderCol = $col - ($modules - 7) }
                        elseif ($row -ge ($modules - 7) -and $col -lt 7) { $finderRow = $row - ($modules - 7); $finderCol = $col }

                        $paintCell = if ($finderRow -ge 0) {
                            ($finderRow -eq 0 -or $finderRow -eq 6 -or $finderCol -eq 0 -or $finderCol -eq 6 -or
                             ($finderRow -ge 2 -and $finderRow -le 4 -and $finderCol -ge 2 -and $finderCol -le 4))
                        } else {
                            ((($row * 17) + ($col * 31) + $seed) % 7) -lt 3
                        }
                        if ($paintCell) {
                            $e.Graphics.FillRectangle($brush, $offsetX + ($col * $cell), $offsetY + ($row * $cell), $cell, $cell)
                        }
                    }
                }
            }.GetNewClosure())
            [void]$prevPanel.Controls.Add($qrPanel)
        }

        function BarcodePreview($payload, $x, $y, $width, $height) {
            if ([string]::IsNullOrWhiteSpace([string]$payload)) { return }
            $barcodePanel = New-Object System.Windows.Forms.Panel
            $barcodePanel.BackColor = [System.Drawing.Color]::White
            $barcodePanel.Location = New-Object System.Drawing.Point(
                [int][math]::Round($x * $scaleX),
                [int][math]::Round($y * $scaleY)
            )
            $barcodePanel.Size = New-Object System.Drawing.Size(
                [int][math]::Max(1, [math]::Round($width * $scaleX)),
                [int][math]::Max(1, [math]::Round($height * $scaleY))
            )
            $barcodePayloadLocal = ([string]$payload).ToUpperInvariant()
            $barcodePanel.Add_Paint({
                param($sender, $e)
                $cursor = 1
                $maxX = [Math]::Max(1, $sender.ClientSize.Width - 1)
                foreach ($ch in $barcodePayloadLocal.ToCharArray()) {
                    $value = [int]$ch
                    for ($bit = 0; $bit -lt 7; $bit++) {
                        $barWidth = 1 + (($value + ($bit * 3)) % 3)
                        if (($bit % 2) -eq 0) {
                            $e.Graphics.FillRectangle([System.Drawing.Brushes]::Black, $cursor, 0, $barWidth, $sender.ClientSize.Height)
                        }
                        $cursor += $barWidth + 1
                        if ($cursor -ge $maxX) { break }
                    }
                    if ($cursor -ge $maxX) { break }
                }
            }.GetNewClosure())
            [void]$prevPanel.Controls.Add($barcodePanel)
        }

        function Wrap-TextLines {
            param(
                [string]$Text,
                [int]$MaxLen = 46,
                [int]$MaxLines = 3
            )
            $clean = ([string]$Text -replace '\s+', ' ').Trim()
            if (-not $clean) { return @() }
            $lines = New-Object System.Collections.Generic.List[string]
            $remaining = $clean
            while ($remaining -and $lines.Count -lt $MaxLines) {
                if ($remaining.Length -le $MaxLen) {
                    $lines.Add($remaining)
                    $remaining = ''
                    break
                }
                $breakAt = $remaining.LastIndexOf(' ', [Math]::Min($MaxLen, ($remaining.Length - 1)))
                if ($breakAt -lt [Math]::Floor($MaxLen * 0.55)) { $breakAt = $MaxLen }
                $lines.Add($remaining.Substring(0, $breakAt).Trim())
                $remaining = $remaining.Substring($breakAt).Trim()
            }
            if ($remaining -and $lines.Count -gt 0) {
                $last = $lines[$MaxLines - 1]
                $cutLen = [math]::Min($last.Length, [math]::Max(0, $MaxLen - 3))
                $lines[$MaxLines - 1] = $last.Substring(0, $cutLen).TrimEnd() + '...'
            }
            return @($lines)
        }

        function Format-ObservacaoPreview($text) {
            $clean = ([string]$text).Trim()
            if (-not $clean) { return '' }
            $clean = $clean -replace '^\s*\d{2}/\d{2}/\d{2,4}\s*-\s*\d{1,2}:\d{2}(?:\s*-\s*[^:\r\n]{1,60})?\s*:\s*', ''
            return $clean.Trim()
        }

        # Canvas TSPL exato de 640x400 para etiqueta 80x50mm a 203 dpi.
        # Uma unica moldura com margem segura evita o efeito de borda duplicada.
        BoxPreview 10 10 630 390 2

        $modeloTxt = ([string]$script:modeloEtiqueta -replace '\s+', ' ').Trim()
        $modeloTxt = $modeloTxt -replace '(?i)^\s*T\d{3}(?:-+)?\s*(?:[-:|]\s*)?(?=(?:CPU|DESKTOP|MINI\s+DESKTOP|COMPUTADOR\s+DESKTOP)\b)', ''
        $modeloTxt = $modeloTxt -replace '(?i)^\s*(NOTEBOOK|LAPTOP|COMPUTADOR|CPU)\s+', ''
        $modeloTxt = $modeloTxt -replace '(?i)\bGEN(?:ERACAO)?\s*(\d+)\b', 'G$1'
        if ($modeloTxt.Length -le 24) {
            $modeloTop = $modeloTxt
            $modeloFont = $f3
            $modeloY = 36
        } else {
            $modeloTop = if ($modeloTxt.Length -gt 32) { $modeloTxt.Substring(0, 32) } else { $modeloTxt }
            $modeloFont = $f2
            $modeloY = 36
        }
        L 'EQUIPAMENTO' 22 16 150 20 $f2 $preto
        L $modeloTop 22 $modeloY 410 34 $modeloFont $preto

        $gradeTxt = ''
        if ($gradeEfetiva) {
            $gradeTxt = if ($gradeEfetiva -eq 'RMA') {
                'GRADE RMA'
            } elseif ($gradeEfetiva -match '^C\s*-\s*PINTURA\s*([123])$') {
                "C - PINTURA $($matches[1])"
            } elseif ($gradeEfetiva -match '^T\s*-\s*TRIAGEM$') {
                'T - TRIAGEM'
            } else {
                "GRADE $([string]$gradeEfetiva)"
            }
            if ($gradeTxt.Length -gt 13) { $gradeTxt = $gradeTxt.Substring(0, 13) }
        }
        if ($gradeTxt) {
            $gradePreviewFont = if ($gradeTxt.Length -le 9) { $f2 } else { $f1 }
            BoxPreview 452 20 618 70 2
            L $gradeTxt 464 34 142 24 $gradePreviewFont $preto
        }

        B 10 82 620 2

        $serialTop = ([string]$script:serialEtiqueta -replace '\s+', '').Trim()
        $serialBar = ($serialTop -replace '[^A-Za-z0-9]', '').ToUpper()
        $serialPreviewFont = if ($serialTop.Length -le 22) { $f3 } else { $f2 }
        if ($incluirOS) {
            if ($serialTop.Length -gt 22) { $serialTop = $serialTop.Substring(0, 22) }
            L 'SERIAL' 22 86 80 20 $f2 $preto
            L $serialTop 22 108 392 24 $serialPreviewFont $preto
            if ($serialBar.Length -ge 4) { BarcodePreview $serialBar 22 136 300 16 }
            B 430 82 2 76
            L 'ORDEM DE SERV.' 446 86 170 20 $f2 $preto
            L (Format-OsCodigo -Numero $printContext.OsNumero) 446 112 166 34 $f4 $preto
        } else {
            if ($serialTop.Length -gt 28) { $serialTop = $serialTop.Substring(0, 28) }
            L 'SERIAL' 22 86 80 20 $f2 $preto
            L $serialTop 22 108 590 24 $serialPreviewFont $preto
            if ($serialBar.Length -ge 4) { BarcodePreview $serialBar 22 136 420 16 }
        }
        B 10 158 620 2

        $isMonitorEtiqueta = ([string]$script:tipoEtiqueta -eq 'Monitor')
        $isCelularEtiqueta = ([string]$script:tipoEtiqueta -eq 'Celular')
        $isDesktopEtiqueta = ([string]$script:tipoEtiqueta -eq 'Desktop')
        $obsLines = @()
        if (-not [string]::IsNullOrWhiteSpace([string]$obs)) {
            $obsPreview = Format-ObservacaoPreview $obs
            $obsLines = Wrap-TextLines -Text $obsPreview -MaxLen 69 -MaxLines 3
        }
        $temObservacaoEtiqueta = ($obsLines.Count -gt 0)
        $alturaDivisoriaInferior = if ($temObservacaoEtiqueta) { 172 } else { 232 }
        B 318 158 2 $alturaDivisoriaInferior
        B 10 194 308 1
        $tituloEspecificacoes = if ($isMonitorEtiqueta) {
            'MONITOR'
        } elseif ($isCelularEtiqueta) {
            'CELULAR'
        } elseif ($isDesktopEtiqueta) {
            'DESKTOP'
        } else {
            'CONFIGURACAO'
        }
        L $tituloEspecificacoes 22 173 270 20 $f2 $preto

        $bateriaCelularPreview = 'N/A'
        if ($isCelularEtiqueta -and [string]$script:bateriaEtiqueta -match '(\d{1,3})') {
            $bateriaCelularPreview = "$([math]::Min(100, [math]::Max(0, [int]$matches[1])))%"
        }
        $desktopSpecRows = @()
        if ($isDesktopEtiqueta) {
            foreach ($desktopSpec in @(
                @('CPU', [string]$script:cpuEtiqueta),
                @('RAM', [string]$script:ramEtiqueta),
                @('DISCO', [string]$script:memEtiqueta),
                @('GPU', [string]$script:gpuEtiqueta)
            )) {
                $desktopValue = ([string]$desktopSpec[1]).Trim()
                if ($desktopValue -and $desktopValue -notmatch '^(?i:N/?A)$') {
                    $desktopSpecRows += ,$desktopSpec
                }
            }
        }
        $specRows = if ($isMonitorEtiqueta) {
            @(
                @('TAMANHO', [string]$script:monitorTamanhoEtiqueta),
                @('ENTRADAS', [string]$script:monitorEntradasEtiqueta)
            )
        } elseif ($isCelularEtiqueta) {
            @(
                @('IMEI', [string]$script:celularImeiEtiqueta),
                @('ARMAZ.', [string]$script:memEtiqueta),
                @('BATERIA', $bateriaCelularPreview)
            )
        } elseif ($isDesktopEtiqueta) {
            @($desktopSpecRows)
        } else {
            @(
                @('CPU', [string]$script:cpuEtiqueta),
                @('RAM', [string]$script:ramEtiqueta),
                @('DISCO', [string]$script:memEtiqueta),
                @('GPU', $(if (& $script:IsGpuEtiquetaVisivel $script:gpuEtiqueta) { [string]$script:gpuEtiqueta } else { 'N/A' })),
                @('BAT', $(if (& $script:IsBateriaEtiquetaVisivel $script:bateriaEtiqueta) { [string]$script:bateriaEtiqueta } else { 'N/A' }))
            )
        }
        $isEtiquetaCompacta = ($isMonitorEtiqueta -or $isCelularEtiqueta)
        $specY = if ($isEtiquetaCompacta) { 206 } else { 200 }
        $specStep = if ($isEtiquetaCompacta) { 44 } else { 28 }
        foreach ($row in $specRows) {
            $specLabel = [string]$row[0]
            $specValue = ([string]$row[1] -replace '\s+', ' ').Trim()
            if ($specLabel -eq 'GPU' -and $specValue -match '(?i)AMD\s+Radeon\s+Graphics.*Integr') {
                $specValue = 'AMD Radeon Int.'
            } elseif ($specLabel -eq 'GPU') {
                $specValue = Format-GpuEtiquetaLocal $specValue
            }
            $specMaxLen = if ($specLabel -eq 'GPU') { 27 } elseif ($isMonitorEtiqueta -and $specLabel -eq 'ENTRADAS') { 25 } else { 18 }
            if ($specValue.Length -gt $specMaxLen) { $specValue = $specValue.Substring(0, $specMaxLen) }
            $labelX = 22
            $labelWidth = if ($isEtiquetaCompacta) { 50 } else { 48 }
            $valueX = if ($isCelularEtiqueta -and $specLabel -eq 'BATERIA') { 94 } else { 76 }
            $specFont = if (($isMonitorEtiqueta -and $specLabel -eq 'ENTRADAS') -or ($specLabel -eq 'GPU' -and $specValue.Length -gt 18)) {
                $f1
            } else {
                $f2
            }
            $specValueY = if ($specFont -eq $f1) { $specY } else { $specY - 4 }
            L $specLabel $labelX $specY $labelWidth 16 $f1 $preto
            $valueRight = 298
            L $specValue $valueX $specValueY ($valueRight - $valueX) 24 $specFont $preto
            if (-not $isMonitorEtiqueta -or $specLabel -ne 'ENTRADAS') {
                B 20 ($specY + 25) 282 1
            }
            $specY += $specStep
        }

        $qrPreviewPayload = 'http://192.168.15.127:9100/f/0000000000'
        if ($temObservacaoEtiqueta) {
            QrPreview $qrPreviewPayload 398 172 150
        } else {
            QrPreview $qrPreviewPayload 374 174 198
        }

        if ($obsLines.Count -gt 0) {
            B 20 330 590 1
            L 'OBS' 22 334 40 20 $f2 $preto
            $obsY = 334
            foreach ($line in $obsLines) {
                L $line 66 $obsY 540 16 $f1 $preto
                $obsY += 16
            }
        }

        if ($obsLines.Count -eq 0) {
            $dataCurta = Get-Date -Format 'dd/MM/yy'
            L $dataCurta 244 368 62 14 $f1 $cinza
        }

        $prevPanel.Refresh()
    }
    & $script:DesenharPrevia 'A' (& $script:GetObsImpressao) $script:incluirOSAtual

    # Grade — header com barra de destaque
    $gradeAccentBar = New-Object System.Windows.Forms.Panel
    $gradeAccentBar.BackColor = $cAccent
    $gradeAccentBar.Location  = New-Object System.Drawing.Point(644, 102)
    $gradeAccentBar.Size      = New-Object System.Drawing.Size(3, 18)
    $gradeAccentBar.Visible   = $false
    $popup.Controls.Add($gradeAccentBar)

    $gradeLabel = New-Object System.Windows.Forms.Label
    $gradeLabel.Text = 'CLASSIFICACAO'
    $gradeLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5, [System.Drawing.FontStyle]::Bold)
    $gradeLabel.ForeColor = $previewUiMuted
    $gradeLabel.Location = New-Object System.Drawing.Point(656, 101)
    $gradeLabel.Size = New-Object System.Drawing.Size(126, 20)
    $popup.Controls.Add($gradeLabel)
    $gradeHairline = New-SectionHairline -Parent $popup -X 788 -Y 111 -W 96 -Cor $previewUiBorder

    $gradeIdleColor = [System.Drawing.Color]::FromArgb(29, 49, 64)
    $gradeHoverColor = [System.Drawing.Color]::FromArgb(39, 65, 82)
    $gradeDownColor = [System.Drawing.Color]::FromArgb(24, 44, 58)
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
        $coresGradeIdle[$kG]  = [System.Drawing.Color]::FromArgb(([int]($cG.R * 0.18) + 22), ([int]($cG.G * 0.18) + 30), ([int]($cG.B * 0.18) + 38))
        $coresGradeTexto[$kG] = [System.Drawing.Color]::FromArgb([Math]::Min($cG.R + 135, 255), [Math]::Min($cG.G + 125, 255), [Math]::Min($cG.B + 125, 255))
        $coresGradeBorda[$kG] = [System.Drawing.Color]::FromArgb([Math]::Min([int]($cG.R * 0.7) + 24, 255), [Math]::Min([int]($cG.G * 0.7) + 24, 255), [Math]::Min([int]($cG.B * 0.7) + 24, 255))
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
        $pForm.ClientSize = New-Object System.Drawing.Size(400, 348)
        $pForm.StartPosition = 'CenterParent'
        $pForm.BackColor = [System.Drawing.Color]::FromArgb(7, 9, 17)
        $pForm.ForeColor = [System.Drawing.Color]::FromArgb(240, 242, 248)
        $pForm.FormBorderStyle = 'None'
        $pForm.MaximizeBox = $false
        $pForm.MinimizeBox = $false
        $pForm.ShowInTaskbar = $false
        Set-DoubleBuffered $pForm
        Set-RoundedControl -Control $pForm -Radius 12
        $pForm.Add_SizeChanged({ Set-RoundedControl -Control $this -Radius 12 })
        $pForm.Add_Paint({
            param($s, $e)
            $bordaPintura = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(42, 46, 63), 1)
            $e.Graphics.DrawRectangle($bordaPintura, 0, 0, ($s.ClientSize.Width - 1), ($s.ClientSize.Height - 1))
            $bordaPintura.Dispose()
        })

        $pHeader = New-Object System.Windows.Forms.Panel
        $pHeader.Location = New-Object System.Drawing.Point(0, 0)
        $pHeader.Size = New-Object System.Drawing.Size(400, 64)
        $pHeader.BackColor = [System.Drawing.Color]::FromArgb(15, 18, 29)
        $pHeader.Add_Paint({
            param($s, $e)
            $linhaHeader = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(42, 46, 63), 1)
            $e.Graphics.DrawLine($linhaHeader, 0, ($s.Height - 1), $s.Width, ($s.Height - 1))
            $linhaHeader.Dispose()
        })
        [void]$pForm.Controls.Add($pHeader)

        $pEyebrow = New-Object System.Windows.Forms.Label
        $pEyebrow.Text = 'ETIQUETA / CLASSIFICACAO'
        $pEyebrow.Font = New-Object System.Drawing.Font('Segoe UI', 6.8, [System.Drawing.FontStyle]::Bold)
        $pEyebrow.ForeColor = [System.Drawing.Color]::FromArgb(112, 124, 228)
        $pEyebrow.Location = New-Object System.Drawing.Point(20, 9)
        $pEyebrow.Size = New-Object System.Drawing.Size(260, 14)
        [void]$pHeader.Controls.Add($pEyebrow)

        $pHeaderTitle = New-Object System.Windows.Forms.Label
        $pHeaderTitle.Text = 'Grade C - Pintura'
        $pHeaderTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 14, [System.Drawing.FontStyle]::Bold)
        $pHeaderTitle.ForeColor = [System.Drawing.Color]::FromArgb(240, 242, 248)
        $pHeaderTitle.Location = New-Object System.Drawing.Point(18, 27)
        $pHeaderTitle.Size = New-Object System.Drawing.Size(280, 28)
        [void]$pHeader.Controls.Add($pHeaderTitle)

        $pClose = New-Object System.Windows.Forms.Button
        $pClose.Text = 'X'
        $pClose.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
        $pClose.ForeColor = [System.Drawing.Color]::FromArgb(166, 170, 184)
        $pClose.BackColor = $pHeader.BackColor
        $pClose.FlatStyle = 'Flat'
        $pClose.FlatAppearance.BorderSize = 0
        $pClose.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(21, 24, 38)
        $pClose.Location = New-Object System.Drawing.Point(364, 8)
        $pClose.Size = New-Object System.Drawing.Size(28, 28)
        $pClose.Cursor = [System.Windows.Forms.Cursors]::Hand
        $pClose.Add_Click({
            $script:pinturaSelecionadaTemp = $null
            $pForm.Tag = 'Cancel'
            $pForm.Close()
        })
        [void]$pHeader.Controls.Add($pClose)

        $pDrag = @{ Active = $false; Mouse = [System.Drawing.Point]::Empty; Form = [System.Drawing.Point]::Empty }
        $pHeader.Add_MouseDown({
            if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
                $pDrag.Active = $true
                $pDrag.Mouse = [System.Windows.Forms.Cursor]::Position
                $pDrag.Form = $pForm.Location
            }
        })
        $pHeader.Add_MouseMove({
            if ($pDrag.Active) {
                $agora = [System.Windows.Forms.Cursor]::Position
                $pForm.Location = New-Object System.Drawing.Point(
                    ($pDrag.Form.X + $agora.X - $pDrag.Mouse.X),
                    ($pDrag.Form.Y + $agora.Y - $pDrag.Mouse.Y)
                )
            }
        })
        $pHeader.Add_MouseUp({ $pDrag.Active = $false })

        # Header: barra de destaque + titulo + hairline
        $pAccent = New-Object System.Windows.Forms.Panel
        $pAccent.BackColor = $corPintura
        $pAccent.Location  = New-Object System.Drawing.Point(20, 80)
        $pAccent.Size      = New-Object System.Drawing.Size(2, 16)
        $pForm.Controls.Add($pAccent)

        $pTitle = New-Object System.Windows.Forms.Label
        $pTitle.Text = 'NIVEL DE PINTURA'
        $pTitle.Font = New-Object System.Drawing.Font('Segoe UI', 6.8, [System.Drawing.FontStyle]::Bold)
        $pTitle.ForeColor = [System.Drawing.Color]::FromArgb(255, 180, 120)
        $pTitle.Location = New-Object System.Drawing.Point(30, 79)
        $pTitle.Size = New-Object System.Drawing.Size(190, 18)
        $pForm.Controls.Add($pTitle)

        $pSub = New-Object System.Windows.Forms.Label
        $pSub.Text = 'Escolha o nivel de pintura que vai aparecer na etiqueta.'
        $pSub.Font = New-Object System.Drawing.Font('Segoe UI', 8)
        $pSub.ForeColor = [System.Drawing.Color]::FromArgb(166, 170, 184)
        $pSub.Location = New-Object System.Drawing.Point(20, 101)
        $pSub.Size = New-Object System.Drawing.Size(360, 16)
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
                    $card.BackColor = [System.Drawing.Color]::FromArgb(50, 31, 22)
                    $card.ForeColor = [System.Drawing.Color]::White
                    $card.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(232, 102, 34)
                    $card.FlatAppearance.BorderSize = 2
                    $card.Text = ([string][char]0x25CF + '   ' + $opcaoCard + '   -   ' + $script:pinturaDescsUi[$opcaoCard])
                } else {
                    $card.BackColor = [System.Drawing.Color]::FromArgb(21, 24, 38)
                    $card.ForeColor = [System.Drawing.Color]::FromArgb(240, 242, 248)
                    $card.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(42, 46, 63)
                    $card.FlatAppearance.BorderSize = 1
                    $card.Text = ([string][char]0x25CB + '   ' + $opcaoCard + '   -   ' + $script:pinturaDescsUi[$opcaoCard])
                }
            }
            if ($script:pinturaConfirmBtn) {
                $temSel = [bool]$script:pinturaSelecionadaTemp
                $script:pinturaConfirmBtn.Enabled = $temSel
                $script:pinturaConfirmBtn.BackColor = if ($temSel) { [System.Drawing.Color]::FromArgb(94, 106, 210) } else { [System.Drawing.Color]::FromArgb(26, 29, 43) }
                $script:pinturaConfirmBtn.ForeColor = if ($temSel) { [System.Drawing.Color]::White } else { [System.Drawing.Color]::FromArgb(98, 102, 118) }
            }
        }

        $yCard = 126
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
            $card.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(31, 35, 51)
            $card.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(50, 31, 22)
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
        $pFooterLine.BackColor = [System.Drawing.Color]::FromArgb(42, 46, 63)
        $pFooterLine.Location  = New-Object System.Drawing.Point(20, 282)
        $pFooterLine.Size      = New-Object System.Drawing.Size(344, 1)
        $pForm.Controls.Add($pFooterLine)

        $cancel = New-Object System.Windows.Forms.Button
        $cancel.Text = 'Cancelar'
        $cancel.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
        $cancel.ForeColor = [System.Drawing.Color]::FromArgb(240, 242, 248)
        $cancel.BackColor = [System.Drawing.Color]::FromArgb(21, 24, 38)
        $cancel.FlatStyle = 'Flat'
        $cancel.FlatAppearance.BorderSize = 1
        $cancel.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(42, 46, 63)
        $cancel.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(31, 35, 51)
        $cancel.Cursor = [System.Windows.Forms.Cursors]::Hand
        $cancel.Location = New-Object System.Drawing.Point(20, 296)
        $cancel.Size = New-Object System.Drawing.Size(112, 36)
        $cancel.Add_Click({
            $script:pinturaSelecionadaTemp = $null
            $pForm.Tag = 'Cancel'
            $pForm.Close()
        })
        $pForm.Controls.Add($cancel)
        Set-RoundedControl -Control $cancel -Radius 8

        $confirm = New-Object System.Windows.Forms.Button
        $confirm.Text = 'Confirmar'
        $confirm.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9, [System.Drawing.FontStyle]::Bold)
        $confirm.ForeColor = [System.Drawing.Color]::White
        $confirm.BackColor = [System.Drawing.Color]::FromArgb(94, 106, 210)
        $confirm.FlatStyle = 'Flat'
        $confirm.FlatAppearance.BorderSize = 0
        $confirm.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(112, 124, 228)
        $confirm.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(78, 89, 187)
        $confirm.Cursor = [System.Windows.Forms.Cursors]::Hand
        $confirm.Location = New-Object System.Drawing.Point(232, 296)
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
        Set-CaijWindowsTypography -Root $pForm
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
                if ($script:tipoEtiqueta -eq 'Celular') {
                    $script:pinturaOpcaoAtual = ''
                    $script:gradeAtual = 'C'
                    Set-AppStatus -Texto 'Grade C selecionada' -Cor $cYellow
                } else {
                    $pintura = & $script:SelecionarPintura
                    if (-not $pintura) { return }
                    $script:pinturaOpcaoAtual = $pintura
                    $script:gradeAtual = "C - $pintura"
                    Set-AppStatus -Texto "Grade C selecionada: $pintura" -Cor $cYellow
                }
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
                $this.FlatAppearance.BorderSize = 2
            }
        }.GetNewClosure())
        $btnG.Add_MouseLeave({
            $isSelected = (($this.Tag -eq $script:gradeAtual) -or ($this.Tag -eq 'C' -and ([string]$script:gradeAtual) -match '^C\s*-\s*PINTURA') -or ($this.Tag -eq 'T' -and ([string]$script:gradeAtual) -match '^T\s*-\s*TRIAGEM') -or ($this.Tag -eq 'RMA' -and $script:rnaAtivo))
            if (-not $isSelected) {
                $this.FlatAppearance.BorderSize = 1
            }
        }.GetNewClosure())
        $script:btnGrades[$g.L] = $btnG
        $popup.Controls.Add($btnG)
        Set-RoundedControl -Control $btnG -Radius 6
        $gradeIndex++
    }

    $script:AtualizarGradeState = {
        $gradeLabel.Text = if ($script:rnaAtivo) { 'RMA ATIVO' } else { 'CLASSIFICACAO' }
        foreach ($key in $script:btnGrades.Keys) {
            $btn = $script:btnGrades[$key]
            if ($key -eq 'C') {
                $btn.Text = if ($script:tipoEtiqueta -eq 'Celular') { "C`r`nGrade C" } elseif ($script:pinturaOpcaoAtual) { "C`r`n$($script:pinturaOpcaoAtual)" } else { "C`r`nPintura" }
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
    $obsPanel.BackColor = $previewUiRaised
    $obsPanel.BorderStyle = 'None'
    $popup.Controls.Add($obsPanel)
    Set-RoundedControl -Control $obsPanel -Radius 8

    $obsAccent = New-Object System.Windows.Forms.Panel
    $obsAccent.Location = New-Object System.Drawing.Point(0, 0)
    $obsAccent.Size = New-Object System.Drawing.Size(4, 110)
    $obsAccent.BackColor = $cAccent
    $obsAccent.Visible = $false
    $obsPanel.Controls.Add($obsAccent)

    $obsLabel = New-Object System.Windows.Forms.Label
    $obsLabel.Text = 'OBSERVAÇÕES'
    $obsLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5, [System.Drawing.FontStyle]::Bold)
    $obsLabel.ForeColor = $previewUiMuted
    $obsLabel.Location = New-Object System.Drawing.Point(14, 5)
    $obsLabel.Size = New-Object System.Drawing.Size(110, 16)
    $obsPanel.Controls.Add($obsLabel)
    [void](New-SectionHairline -Parent $obsPanel -X 120 -Y 13 -W 48 -Cor $previewUiBorder)

    $obsCount = New-Object System.Windows.Forms.Label
    $obsCount.Text = '0/220'
    $obsCount.Font = New-Object System.Drawing.Font('Segoe UI', 7.5)
    $obsCount.ForeColor = $previewUiMuted
    $obsCount.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
    $obsCount.Location = New-Object System.Drawing.Point(174, 5)
    $obsCount.Size = New-Object System.Drawing.Size(52, 15)
    $obsPanel.Controls.Add($obsCount)

    $obsBox = New-Object System.Windows.Forms.TextBox
    $obsBox.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $obsBox.BackColor = $previewUiSurface
    $obsBox.ForeColor = $previewUiText
    $obsBox.BorderStyle = 'None'
    $obsBox.Location = New-Object System.Drawing.Point(14, 27)
    $obsBox.Size = New-Object System.Drawing.Size(212, 72)
    $obsBox.Multiline = $true
    $obsBox.ScrollBars = 'None'
    $obsBox.MaxLength = 220
    $obsBox.Cursor = [System.Windows.Forms.Cursors]::IBeam
    $obsBox.Text = if ($script:obsAtual) { [string]$script:obsAtual } else { '' }
    $obsCount.Text = "$($obsBox.Text.Length)/220"
    $obsBox.Add_Enter({ $obsLabel.ForeColor = $previewUiPrimaryHover })
    $obsBox.Add_Leave({ $obsLabel.ForeColor = $previewUiMuted })
    $obsBox.Add_TextChanged({
        $script:obsAtual = $obsBox.Text
        $obsCount.Text = "$($obsBox.Text.Length)/220"
        $obsCount.ForeColor = if ($obsBox.Text.Length -ge 200) { $cYellow } else { $previewUiMuted }
        & $script:DesenharPrevia $script:gradeAtual (& $script:GetObsImpressao) $script:incluirOSAtual
        & $script:UpdateConfirmState
    })
    $obsPanel.Controls.Add($obsBox)

    $altertagCard = New-Object System.Windows.Forms.Panel
    $altertagCard.Location = New-Object System.Drawing.Point(628, 438)
    $altertagCard.Size = New-Object System.Drawing.Size(272, 110)
    $altertagCard.BackColor = $previewUiSurface
    $altertagCard.BorderStyle = 'None'
    $popup.Controls.Add($altertagCard)
    Set-RoundedControl -Control $altertagCard -Radius 8
    $altertagCard.Add_Paint({
        $pen = New-Object System.Drawing.Pen($previewUiBorder, 1)
        $_.Graphics.DrawRectangle($pen, 0, 0, ($this.Width - 1), ($this.Height - 1))
        $pen.Dispose()
    })

    $altertagBar = New-Object System.Windows.Forms.Panel
    $altertagBar.Location = New-Object System.Drawing.Point(0, 0)
    $altertagBar.Size = New-Object System.Drawing.Size(4, 110)
    $altertagBar.BackColor = [System.Drawing.Color]::FromArgb(139, 92, 246)
    $altertagCard.Controls.Add($altertagBar)

    $altertagTitle = New-Object System.Windows.Forms.Label
    $altertagTitle.Text = 'CONFERENCIA ALTERTAG'
    $altertagTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 7, [System.Drawing.FontStyle]::Bold)
    $altertagTitle.ForeColor = $previewUiMuted
    $altertagTitle.Location = New-Object System.Drawing.Point(14, 7)
    $altertagTitle.Size = New-Object System.Drawing.Size(145, 15)
    $altertagCard.Controls.Add($altertagTitle)

    $altertagStatus = New-Object System.Windows.Forms.Label
    $altertagStatus.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 6.5, [System.Drawing.FontStyle]::Bold)
    $altertagStatus.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
    $altertagStatus.Location = New-Object System.Drawing.Point(158, 6)
    $altertagStatus.Size = New-Object System.Drawing.Size(100, 16)
    $altertagCard.Controls.Add($altertagStatus)

    $altertagOs = New-Object System.Windows.Forms.Label
    $altertagOs.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8, [System.Drawing.FontStyle]::Bold)
    $altertagOs.ForeColor = $previewUiText
    $altertagOs.Location = New-Object System.Drawing.Point(14, 27)
    $altertagOs.Size = New-Object System.Drawing.Size(244, 17)
    $altertagCard.Controls.Add($altertagOs)

    $altertagProduto = New-Object System.Windows.Forms.Label
    $altertagProduto.Font = New-Object System.Drawing.Font('Segoe UI', 7.5)
    $altertagProduto.ForeColor = $previewUiMuted
    $altertagProduto.Location = New-Object System.Drawing.Point(14, 47)
    $altertagProduto.Size = New-Object System.Drawing.Size(244, 17)
    $altertagProduto.AutoEllipsis = $true
    $altertagCard.Controls.Add($altertagProduto)

    $altertagTecnico = New-Object System.Windows.Forms.Label
    $altertagTecnico.Font = New-Object System.Drawing.Font('Segoe UI', 7.5)
    $altertagTecnico.ForeColor = $previewUiMuted
    $altertagTecnico.Location = New-Object System.Drawing.Point(14, 67)
    $altertagTecnico.Size = New-Object System.Drawing.Size(244, 17)
    $altertagTecnico.AutoEllipsis = $true
    $altertagCard.Controls.Add($altertagTecnico)

    $altertagSerial = New-Object System.Windows.Forms.Label
    $altertagSerial.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 7.5, [System.Drawing.FontStyle]::Bold)
    $altertagSerial.Location = New-Object System.Drawing.Point(14, 87)
    $altertagSerial.Size = New-Object System.Drawing.Size(244, 17)
    $altertagSerial.AutoEllipsis = $true
    $altertagCard.Controls.Add($altertagSerial)

    $script:AtualizarResumoAltertagPreview = {
        param([switch]$Reconsultar)
        if ($Reconsultar) {
            $altertagResumoPreview = Get-OsAltertagResumoPreview `
                -OsNumero $printContext.OsNumero `
                -OrdemFallback $printContext.Ordem `
                -ConsultarOnline
            $printContext.Ordem = $altertagResumoPreview.ordem
        }
        $serialOs = ([string]$altertagResumoPreview.serial).Trim()
        $serialEtiquetaAtual = ([string]$script:serialEtiqueta).Trim()
        $serialDivergente = (
            $serialOs -and
            $serialOs -ne '-' -and
            $serialEtiquetaAtual -and
            (($serialOs -replace '\s+', '').ToUpperInvariant() -ne ($serialEtiquetaAtual -replace '\s+', '').ToUpperInvariant())
        )
        $altertagOs.Text = "OS  $($altertagResumoPreview.osCodigo)"
        $altertagProduto.Text = "PRODUTO  $($altertagResumoPreview.produto)"
        $altertagTecnico.Text = "TECNICO  $($altertagResumoPreview.tecnico)"
        $altertagSerial.Text = "SERIAL  $($altertagResumoPreview.serial)"
        if ($serialDivergente) {
            $altertagStatus.Text = 'SERIAL DIVERGENTE'
            $altertagStatus.ForeColor = [System.Drawing.Color]::FromArgb(251, 113, 133)
            $altertagSerial.ForeColor = [System.Drawing.Color]::FromArgb(251, 113, 133)
            $altertagBar.BackColor = [System.Drawing.Color]::FromArgb(244, 63, 94)
        } elseif ($altertagResumoPreview.online) {
            $altertagStatus.Text = 'SINCRONIZADO'
            $altertagStatus.ForeColor = [System.Drawing.Color]::FromArgb(74, 222, 128)
            $altertagSerial.ForeColor = [System.Drawing.Color]::FromArgb(216, 205, 244)
            $altertagBar.BackColor = [System.Drawing.Color]::FromArgb(34, 197, 94)
        } elseif ($altertagResumoPreview.ordem) {
            $altertagStatus.Text = 'DADOS LOCAIS'
            $altertagStatus.ForeColor = [System.Drawing.Color]::FromArgb(251, 191, 36)
            $altertagSerial.ForeColor = [System.Drawing.Color]::FromArgb(216, 205, 244)
            $altertagBar.BackColor = [System.Drawing.Color]::FromArgb(245, 158, 11)
        } else {
            $altertagStatus.Text = 'INDISPONIVEL'
            $altertagStatus.ForeColor = [System.Drawing.Color]::FromArgb(148, 163, 184)
            $altertagSerial.ForeColor = [System.Drawing.Color]::FromArgb(180, 172, 198)
            $altertagBar.BackColor = [System.Drawing.Color]::FromArgb(100, 116, 139)
        }
    }.GetNewClosure()
    & $script:AtualizarResumoAltertagPreview

    $altertagPreviewTimer = New-Object System.Windows.Forms.Timer
    $altertagPreviewTimer.Interval = 150
    $altertagPreviewTimer.Add_Tick({
        $this.Stop()
        try {
            if ($popup -and -not $popup.IsDisposed) {
                & $script:AtualizarResumoAltertagPreview -Reconsultar
            }
        } catch {}
        try { $this.Dispose() } catch {}
    })
    $altertagPreviewTimer.Start()

    $osCard = New-Object System.Windows.Forms.Panel
    $osCard.Location = New-Object System.Drawing.Point(20, 480)
    $osCard.Size = New-Object System.Drawing.Size(280, 58)
    $osCard.BackColor = $previewUiRaised
    $osCard.BorderStyle = 'None'
    $osCard.Cursor = [System.Windows.Forms.Cursors]::Hand
    $popup.Controls.Add($osCard)
    Set-RoundedControl -Control $osCard -Radius 8

    $osCardBar = New-Object System.Windows.Forms.Panel
    $osCardBar.Location = New-Object System.Drawing.Point(0, 0)
    $osCardBar.Size = New-Object System.Drawing.Size(4, 58)
    $osCardBar.BackColor = $cAccent
    $osCardBar.Visible = $false
    $osCard.Controls.Add($osCardBar)

    $osCardTitle = New-Object System.Windows.Forms.Label
    $osCardTitle.Text = 'OS NA ETIQUETA'
    $osCardTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 7.5, [System.Drawing.FontStyle]::Bold)
    $osCardTitle.ForeColor = $previewUiMuted
    $osCardTitle.Location = New-Object System.Drawing.Point(14, 8)
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
    $btnAlterarOsPreview.Text = (Format-OsCodigo -Numero $printContext.OsNumero)
    $btnAlterarOsPreview.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 7.5, [System.Drawing.FontStyle]::Bold)
    $btnAlterarOsPreview.ForeColor = $previewUiText
    $btnAlterarOsPreview.BackColor = $previewUiSurface
    $btnAlterarOsPreview.FlatStyle = 'Flat'
    $btnAlterarOsPreview.FlatAppearance.BorderColor = $previewUiBorder
    $btnAlterarOsPreview.FlatAppearance.MouseOverBackColor = $previewUiRaised
    $btnAlterarOsPreview.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnAlterarOsPreview.Location = New-Object System.Drawing.Point(14, 29)
    $btnAlterarOsPreview.Size = New-Object System.Drawing.Size(100, 22)
    $btnAlterarOsPreview.Add_Click({
        $popup.TopMost = $false
        Prompt-OsManual -Owner $popup | Out-Null
        $popup.TopMost = $true
        $popup.Activate() | Out-Null
        $printContext.OsNumero = [int]$script:osNumero
        $printContext.Ordem = $script:altertagOsAtual
        $printContext.CriadaAgora = $false
        $btnAlterarOsPreview.Text = (Format-OsCodigo -Numero $printContext.OsNumero)
        $chkOS.Checked = $true
        & $script:UpdateOsToggle
        & $script:AtualizarResumoAltertagPreview -Reconsultar
        & $script:DesenharPrevia $script:gradeAtual (& $script:GetObsImpressao) $script:incluirOSAtual
    })
    $osCard.Controls.Add($btnAlterarOsPreview)
    Set-RoundedControl -Control $btnAlterarOsPreview -Radius 5
    if (-not $printContext.CriadaAgora) {
        Register-OsNumeroControl -Control $btnAlterarOsPreview
    }
    $osPreviewTip = New-Object System.Windows.Forms.ToolTip
    $osPreviewTip.SetToolTip($btnAlterarOsPreview, 'Alterar o numero da OS')

    $chkOS = New-Object System.Windows.Forms.CheckBox
    $chkOS.Text = 'Ativo'
    $chkOS.Checked = [bool]$script:incluirOSAtual
    $chkOS.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $chkOS.ForeColor = [System.Drawing.Color]::FromArgb(0, 220, 120)
    $chkOS.BackColor = [System.Drawing.Color]::FromArgb(13, 18, 37)
    $chkOS.FlatStyle = 'Flat'
    $chkOS.Location = New-Object System.Drawing.Point(380, 15)
    $chkOS.Size = New-Object System.Drawing.Size(82, 24)
    $chkOS.Visible = $false
    $chkOS.Add_CheckedChanged({
        $script:incluirOSAtual = [bool]$chkOS.Checked
        $osCardBar.BackColor = if ($chkOS.Checked) { [System.Drawing.Color]::FromArgb(139, 92, 246) } else { [System.Drawing.Color]::FromArgb(90, 110, 130) }
        & $script:DesenharPrevia $script:gradeAtual $script:obsAtual $script:incluirOSAtual
    })
    $osCard.Controls.Add($chkOS)

    $osStatusPill = New-Object System.Windows.Forms.Panel
    $osStatusPill.Location = New-Object System.Drawing.Point(122, 29)
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
    $osToggleWrap.Location = New-Object System.Drawing.Point(214, 28)
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
                $it.Card.BackColor = [System.Drawing.Color]::FromArgb(13, 20, 38)
                $it.Label.ForeColor = [System.Drawing.Color]::FromArgb(200, 224, 245)
            }
        }
        foreach ($o in $opcoesRNA) {
            $rowCard = New-Object System.Windows.Forms.Panel
            $rowCard.Location = New-Object System.Drawing.Point($xOpt, $yOpt)
            $rowCard.Size = New-Object System.Drawing.Size(228, 30)
            $rowCard.BackColor = [System.Drawing.Color]::FromArgb(13, 20, 38)
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

        Set-CaijWindowsTypography -Root $rnaForm
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
    $triCard.BackColor = [System.Drawing.Color]::FromArgb(13, 18, 37)
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
    $cmbTecnico.BackColor = [System.Drawing.Color]::FromArgb(13, 20, 38)
    $cmbTecnico.ForeColor = [System.Drawing.Color]::White
    $cmbTecnico.Location = New-Object System.Drawing.Point(14, 30)
    $cmbTecnico.Size = New-Object System.Drawing.Size(120, 24)
    [void]$cmbTecnico.Items.Add('Hyrides')
    [void]$cmbTecnico.Items.Add('Vitor')
    [void]$cmbTecnico.Items.Add('Lucas')
    [void]$cmbTecnico.Items.Add('Erick')
    [void]$cmbTecnico.Items.Add('Felipe')
    $cmbTecnico.SelectedIndex = 1
    $triCard.Controls.Add($cmbTecnico)

    $produtoBox = New-Object System.Windows.Forms.TextBox
    $produtoBox.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $produtoBox.BackColor = [System.Drawing.Color]::FromArgb(13, 20, 38)
    $produtoBox.ForeColor = [System.Drawing.Color]::FromArgb(218, 211, 232)
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
    $btnBuscarProduto.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(139, 92, 246)
    $btnBuscarProduto.Location = New-Object System.Drawing.Point(384, 30)
    $btnBuscarProduto.Size = New-Object System.Drawing.Size(80, 25)
    $triCard.Controls.Add($btnBuscarProduto)

    $servicoBox = New-Object System.Windows.Forms.TextBox
    $servicoBox.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $servicoBox.BackColor = [System.Drawing.Color]::FromArgb(13, 20, 38)
    $servicoBox.ForeColor = [System.Drawing.Color]::FromArgb(218, 211, 232)
    $servicoBox.BorderStyle = 'FixedSingle'
    $servicoBox.Location = New-Object System.Drawing.Point(146, 62)
    $servicoBox.Size = New-Object System.Drawing.Size(230, 23)
    $servicoBox.Text = ''
    $triCard.Controls.Add($servicoBox)

    $servicoLbl = New-Object System.Windows.Forms.Label
    $servicoLbl.Text = 'Servico extra'
    $servicoLbl.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
    $servicoLbl.ForeColor = [System.Drawing.Color]::FromArgb(178, 171, 197)
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
        $chkSvc.BackColor = [System.Drawing.Color]::FromArgb(13, 18, 37)
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
                    $list2.BackColor = [System.Drawing.Color]::FromArgb(13, 20, 38)
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
                    Set-CaijWindowsTypography -Root $pick
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
            $list.BackColor = [System.Drawing.Color]::FromArgb(13, 20, 38)
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

            Set-CaijWindowsTypography -Root $pick
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
    $btnCancelar.ForeColor = $previewUiText
    $btnCancelar.BackColor = $previewUiSurface
    $btnCancelar.FlatStyle = 'Flat'
    $btnCancelar.FlatAppearance.BorderColor = $previewUiBorder
    $btnCancelar.FlatAppearance.MouseOverBackColor = $previewUiRaised
    $btnCancelar.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnCancelar.Location = New-Object System.Drawing.Point(20, 576)
    $btnCancelar.Size = New-Object System.Drawing.Size(132, 36)
    $btnCancelar.Add_Click({ $popup.DialogResult = 'Cancel'; $popup.Close() })
    $popup.Controls.Add($btnCancelar)
    Set-RoundedControl -Control $btnCancelar -Radius 8

    $btnReimprimir = New-Object System.Windows.Forms.Button
    $btnReimprimir.Text = 'Reimprimir ultima'
    $btnReimprimir.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8, [System.Drawing.FontStyle]::Bold)
    $btnReimprimir.ForeColor = $previewUiText
    $btnReimprimir.BackColor = $previewUiSurface
    $btnReimprimir.FlatStyle = 'Flat'
    $btnReimprimir.FlatAppearance.BorderColor = $previewUiBorder
    $btnReimprimir.FlatAppearance.MouseOverBackColor = $previewUiRaised
    $btnReimprimir.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnReimprimir.Location = New-Object System.Drawing.Point(164, 576)
    $btnReimprimir.Size = New-Object System.Drawing.Size(150, 36)
    $btnReimprimir.Enabled = -not [string]::IsNullOrWhiteSpace([string]$script:ultimaEtiquetaPayload)
    $btnReimprimir.Add_Click({
        if ([string]::IsNullOrWhiteSpace([string]$script:ultimaEtiquetaPayload)) { return }
        $btnReimprimir.Enabled = $false
        $textoOriginalReimpressao = $btnReimprimir.Text
        $btnReimprimir.Text = 'Reenviando...'
        [System.Windows.Forms.Application]::DoEvents()
        try {
            Invoke-CaijServer -Path '/imprimir' -Method POST -Body ([string]$script:ultimaEtiquetaPayload) -TimeoutSec 20 -Retries 2 | Out-Null
            $resumoAnterior = $script:ultimaEtiquetaResumo
            if ($resumoAnterior) {
                Add-HistoricoNotebook `
                    -Acao 'reimpressao' `
                    -Status 'ok' `
                    -Mensagem 'Ultima etiqueta reenviada sem alterar a OS' `
                    -Grade ([string]$resumoAnterior.grade) `
                    -Obs ([string]$resumoAnterior.obs) `
                    -OsNumero ([int]$resumoAnterior.osNumero) `
                    -Serial ([string]$resumoAnterior.serial) `
                    -Modelo ([string]$resumoAnterior.modelo) `
                    -Cpu ([string]$resumoAnterior.cpu) `
                    -Ram ([string]$resumoAnterior.ram) `
                    -Disco ([string]$resumoAnterior.disco) `
                    -Gpu ([string]$resumoAnterior.gpu) `
                    -Bateria ([string]$resumoAnterior.bateria)
            }
            $btnReimprimir.Text = 'Etiqueta reenviada'
            Set-AppStatus -Texto 'Ultima etiqueta reenviada sem alterar a OS' -Cor $cGreen
        } catch {
            $btnReimprimir.Text = 'Falha ao reenviar'
            Set-AppStatus -Texto 'Falha ao reimprimir a ultima etiqueta' -Cor $cRed
            [System.Windows.Forms.MessageBox]::Show(
                "Nao foi possivel reimprimir a ultima etiqueta:`n$($_.Exception.Message)",
                'Falha na reimpressao',
                'OK',
                'Error'
            ) | Out-Null
        } finally {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 500
            $btnReimprimir.Text = $textoOriginalReimpressao
            $btnReimprimir.Enabled = $true
        }
    })
    $popup.Controls.Add($btnReimprimir)
    Set-RoundedControl -Control $btnReimprimir -Radius 8

    $btnManual = New-Object System.Windows.Forms.Button
    $btnManual.Text = ([string][char]0x270E + '  Manual')
    $btnManual.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8, [System.Drawing.FontStyle]::Bold)
    $btnManual.ForeColor = $previewUiText
    $btnManual.BackColor = $previewUiRaised
    $btnManual.FlatStyle = 'Flat'
    $btnManual.FlatAppearance.BorderColor = $previewUiBorder
    $btnManual.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(31, 35, 52)
    $btnManual.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnManual.Location = New-Object System.Drawing.Point(502, 508)
    $btnManual.Size = New-Object System.Drawing.Size(110, 30)
    $btnManual.Add_Click({
        $manualForm = New-Object System.Windows.Forms.Form
        $manualForm.Text = 'Preencher dados manualmente'
        $manualForm.ClientSize = New-Object System.Drawing.Size(440, 570)
        $manualForm.StartPosition = 'CenterParent'
        $manualForm.BackColor = $previewUiBg
        $manualForm.FormBorderStyle = 'None'
        $manualForm.MaximizeBox = $false
        $manualForm.MinimizeBox = $false
        $manualForm.TopMost = $true
        $manualForm.KeyPreview = $true
        Set-RoundedControl -Control $manualForm -Radius 12
        $manualForm.Add_SizeChanged({ Set-RoundedControl -Control $this -Radius 12 })
        $manualForm.Add_Paint({
            $manualBorderPen = New-Object System.Drawing.Pen($previewUiBorder, 1)
            $_.Graphics.DrawRectangle($manualBorderPen, 0, 0, ($this.ClientSize.Width - 1), ($this.ClientSize.Height - 1))
            $manualBorderPen.Dispose()
        })

        function New-ManualField {
            param([string]$titulo, [int]$y, [string]$valor)
            $lbl = New-Object System.Windows.Forms.Label
            $lbl.Text = $titulo
            $lbl.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
            $lbl.ForeColor = $previewUiMuted
            $lbl.Location = New-Object System.Drawing.Point(16, $y)
            $lbl.Size = New-Object System.Drawing.Size(160, 18)
            $manualForm.Controls.Add($lbl)

            $txt = New-Object System.Windows.Forms.TextBox
            $txt.Font = New-Object System.Drawing.Font('Segoe UI', 9)
            $txt.BackColor = $previewUiRaised
            $txt.ForeColor = $previewUiText
            $txt.BorderStyle = 'FixedSingle'
            $txt.Location = New-Object System.Drawing.Point(16, ($y + 18))
            $txt.Size = New-Object System.Drawing.Size(282, 24)
            $txt.Text = $valor
            $txt.Tag = $lbl
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
            $btn.ForeColor = $previewUiText
            $btn.BackColor = $previewUiRaised
            $btn.FlatStyle = 'Flat'
            $btn.FlatAppearance.BorderColor = $previewUiBorder
            $btn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(31, 35, 52)
            $btn.Location = New-Object System.Drawing.Point(306, ($y + 18))
            $btn.Size = New-Object System.Drawing.Size(102, 24)
            $btn.Tag = [pscustomobject]@{ Target = $target; Valor = $valor }
            $btn.Add_Click({ $this.Tag.Target.Text = $this.Tag.Valor })
            $btn.TabStop = $false
            $manualForm.Controls.Add($btn)
            return $btn
        }

        $tipoManualLabel = New-Object System.Windows.Forms.Label
        $tipoManualLabel.Text = 'TIPO DE EQUIPAMENTO'
        $tipoManualLabel.Font = New-Object System.Drawing.Font('Segoe UI', 7, [System.Drawing.FontStyle]::Bold)
        $tipoManualLabel.ForeColor = $previewUiPrimaryHover
        $tipoManualLabel.Location = New-Object System.Drawing.Point(16, 8)
        $tipoManualLabel.Size = New-Object System.Drawing.Size(180, 16)
        [void]$manualForm.Controls.Add($tipoManualLabel)

        $btnTipoNotebook = New-Object System.Windows.Forms.Button
        $btnTipoNotebook.Text = 'Notebook'
        $btnTipoNotebook.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5, [System.Drawing.FontStyle]::Bold)
        $btnTipoNotebook.FlatStyle = 'Flat'
        $btnTipoNotebook.Cursor = [System.Windows.Forms.Cursors]::Hand
        $btnTipoNotebook.Location = New-Object System.Drawing.Point(16, 25)
        $btnTipoNotebook.Size = New-Object System.Drawing.Size(92, 29)
        [void]$manualForm.Controls.Add($btnTipoNotebook)
        Set-RoundedControl -Control $btnTipoNotebook -Radius 6

        $btnTipoDesktop = New-Object System.Windows.Forms.Button
        $btnTipoDesktop.Text = 'Desktop'
        $btnTipoDesktop.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5, [System.Drawing.FontStyle]::Bold)
        $btnTipoDesktop.FlatStyle = 'Flat'
        $btnTipoDesktop.Cursor = [System.Windows.Forms.Cursors]::Hand
        $btnTipoDesktop.Location = New-Object System.Drawing.Point(114, 25)
        $btnTipoDesktop.Size = New-Object System.Drawing.Size(92, 29)
        [void]$manualForm.Controls.Add($btnTipoDesktop)
        Set-RoundedControl -Control $btnTipoDesktop -Radius 6

        $btnTipoMonitor = New-Object System.Windows.Forms.Button
        $btnTipoMonitor.Text = 'Monitor'
        $btnTipoMonitor.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5, [System.Drawing.FontStyle]::Bold)
        $btnTipoMonitor.FlatStyle = 'Flat'
        $btnTipoMonitor.Cursor = [System.Windows.Forms.Cursors]::Hand
        $btnTipoMonitor.Location = New-Object System.Drawing.Point(212, 25)
        $btnTipoMonitor.Size = New-Object System.Drawing.Size(92, 29)
        [void]$manualForm.Controls.Add($btnTipoMonitor)
        Set-RoundedControl -Control $btnTipoMonitor -Radius 6

        $btnTipoCelular = New-Object System.Windows.Forms.Button
        $btnTipoCelular.Text = 'Celular'
        $btnTipoCelular.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5, [System.Drawing.FontStyle]::Bold)
        $btnTipoCelular.FlatStyle = 'Flat'
        $btnTipoCelular.Cursor = [System.Windows.Forms.Cursors]::Hand
        $btnTipoCelular.Location = New-Object System.Drawing.Point(310, 25)
        $btnTipoCelular.Size = New-Object System.Drawing.Size(98, 29)
        [void]$manualForm.Controls.Add($btnTipoCelular)
        Set-RoundedControl -Control $btnTipoCelular -Radius 6

        $manualForm.Tag = switch ([string]$script:tipoEtiqueta) {
            'Desktop' { 'Desktop' }
            'Monitor' { 'Monitor' }
            'Celular' { 'Celular' }
            default { 'Notebook' }
        }

        $modeloManualSalvo = Get-ModeloManualUltimo -Tipo ([string]$manualForm.Tag)
        $modeloManualInicial = if ($script:modoManualEtiqueta -and -not [string]::IsNullOrWhiteSpace([string]$script:modeloEtiqueta)) {
            [string]$script:modeloEtiqueta
        } elseif (-not [string]::IsNullOrWhiteSpace($modeloManualSalvo)) {
            $modeloManualSalvo
        } else {
            [string]$script:modeloEtiqueta
        }
        $txtModelo = New-ManualField 'Nome do modelo' 62 $modeloManualInicial

        $modeloSugPanel = New-Object System.Windows.Forms.Panel
        $modeloSugPanel.Location = New-Object System.Drawing.Point(16, 107)
        $modeloSugPanel.Size = New-Object System.Drawing.Size(282, 124)
        $modeloSugPanel.BackColor = $previewUiBorder
        $modeloSugPanel.Visible = $false
        [void]$manualForm.Controls.Add($modeloSugPanel)
        Set-RoundedControl -Control $modeloSugPanel -Radius 7
        $modeloSugPanel.Add_SizeChanged({ Set-RoundedControl -Control $this -Radius 7 })

        $modeloSugHeader = New-Object System.Windows.Forms.Panel
        $modeloSugHeader.Location = New-Object System.Drawing.Point(1, 1)
        $modeloSugHeader.Size = New-Object System.Drawing.Size(280, 25)
        $modeloSugHeader.BackColor = $previewUiSurface
        [void]$modeloSugPanel.Controls.Add($modeloSugHeader)

        $modeloSugDot = New-Object System.Windows.Forms.Panel
        $modeloSugDot.Location = New-Object System.Drawing.Point(10, 9)
        $modeloSugDot.Size = New-Object System.Drawing.Size(6, 6)
        $modeloSugDot.BackColor = $previewUiPrimary
        [void]$modeloSugHeader.Controls.Add($modeloSugDot)
        Set-RoundedControl -Control $modeloSugDot -Radius 3

        $modeloSugTitle = New-Object System.Windows.Forms.Label
        $modeloSugTitle.Text = 'MODELOS RECENTES'
        $modeloSugTitle.Font = New-Object System.Drawing.Font('Segoe UI', 6.5, [System.Drawing.FontStyle]::Bold)
        $modeloSugTitle.ForeColor = $previewUiPrimaryHover
        $modeloSugTitle.Location = New-Object System.Drawing.Point(23, 5)
        $modeloSugTitle.Size = New-Object System.Drawing.Size(150, 15)
        [void]$modeloSugHeader.Controls.Add($modeloSugTitle)

        $modeloSugCount = New-Object System.Windows.Forms.Label
        $modeloSugCount.Text = ''
        $modeloSugCount.Font = New-Object System.Drawing.Font('Segoe UI', 6.5, [System.Drawing.FontStyle]::Bold)
        $modeloSugCount.ForeColor = $previewUiMuted
        $modeloSugCount.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
        $modeloSugCount.Location = New-Object System.Drawing.Point(205, 5)
        $modeloSugCount.Size = New-Object System.Drawing.Size(62, 15)
        [void]$modeloSugHeader.Controls.Add($modeloSugCount)

        $modeloSugList = New-Object System.Windows.Forms.ListBox
        $modeloSugList.Location = New-Object System.Drawing.Point(1, 26)
        $modeloSugList.Size = New-Object System.Drawing.Size(280, 96)
        $modeloSugList.BackColor = $previewUiSurface
        $modeloSugList.ForeColor = $previewUiText
        $modeloSugList.BorderStyle = 'None'
        $modeloSugList.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5)
        $modeloSugList.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
        $modeloSugList.ItemHeight = 34
        $modeloSugList.IntegralHeight = $false
        $modeloSugList.Cursor = [System.Windows.Forms.Cursors]::Hand
        [void]$modeloSugPanel.Controls.Add($modeloSugList)
        $modeloSugList.Add_DrawItem({
            param($sender, $e)
            if ($e.Index -lt 0) { return }
            $selecionado = (($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -eq [System.Windows.Forms.DrawItemState]::Selected)
            $fundo = if ($selecionado) {
                [System.Drawing.Color]::FromArgb(31, 35, 52)
            } else {
                $previewUiSurface
            }
            $texto = if ($selecionado) {
                $previewUiText
            } else {
                $previewUiMuted
            }
            $bgBrush = New-Object System.Drawing.SolidBrush($fundo)
            $e.Graphics.FillRectangle($bgBrush, $e.Bounds)
            $bgBrush.Dispose()
            if ($selecionado) {
                $railBrush = New-Object System.Drawing.SolidBrush($previewUiPrimary)
                $e.Graphics.FillRectangle($railBrush, $e.Bounds.X, $e.Bounds.Y, 3, $e.Bounds.Height)
                $railBrush.Dispose()
            }
            $textBrush = New-Object System.Drawing.SolidBrush($texto)
            $textRect = New-Object System.Drawing.RectangleF(
                ($e.Bounds.X + 12),
                ($e.Bounds.Y + 6),
                ($e.Bounds.Width - 20),
                ($e.Bounds.Height - 8)
            )
            $textFormat = New-Object System.Drawing.StringFormat
            $textFormat.FormatFlags = [System.Drawing.StringFormatFlags]::NoWrap
            $textFormat.Trimming = [System.Drawing.StringTrimming]::EllipsisCharacter
            $textFormat.LineAlignment = [System.Drawing.StringAlignment]::Center
            $e.Graphics.DrawString([string]$sender.Items[$e.Index], $sender.Font, $textBrush, $textRect, $textFormat)
            $textFormat.Dispose()
            $textBrush.Dispose()
        })
        $modeloSugTip = New-Object System.Windows.Forms.ToolTip
        $modeloSugTip.AutoPopDelay = 6000
        $modeloSugTip.InitialDelay = 350
        $modeloSugTip.ReshowDelay = 100
        $modeloSugList.Add_MouseMove({
            $indiceHover = $modeloSugList.IndexFromPoint($_.Location)
            $textoHover = if ($indiceHover -ge 0) { [string]$modeloSugList.Items[$indiceHover] } else { '' }
            if ([string]$modeloSugList.Tag -ne $textoHover) {
                $modeloSugList.Tag = $textoHover
                $modeloSugTip.SetToolTip($modeloSugList, $textoHover)
            }
        })

        $atualizarModeloSugestoes = {
            $buscaModelo = $txtModelo.Text.Trim()
            $resultadosModelo = New-Object System.Collections.Generic.List[string]
            foreach ($modeloSalvo in @($script:modelosManuaisHistorico)) {
                $modeloTexto = ([string]$modeloSalvo).Trim()
                if (-not $modeloTexto) { continue }
                if ($buscaModelo -and $modeloTexto.IndexOf($buscaModelo, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
                    continue
                }
                if (-not $resultadosModelo.Contains($modeloTexto)) {
                    [void]$resultadosModelo.Add($modeloTexto)
                }
                if ($resultadosModelo.Count -ge 5) { break }
            }

            $modeloSugList.Items.Clear()
            foreach ($modeloResultado in $resultadosModelo) {
                [void]$modeloSugList.Items.Add($modeloResultado)
            }
            $quantidadeModelo = $modeloSugList.Items.Count
            if ($quantidadeModelo -gt 0 -and $txtModelo.Focused) {
                $alturaLista = [Math]::Min(170, [Math]::Max(68, ($quantidadeModelo * 34)))
                $modeloSugList.Height = $alturaLista
                $modeloSugPanel.Height = 31 + $alturaLista
                $modeloSugCount.Text = "$quantidadeModelo encontrado$(if ($quantidadeModelo -eq 1) { '' } else { 's' })"
                $modeloSugPanel.Visible = $true
                $modeloSugPanel.BringToFront()
                $modeloSugList.BringToFront()
            } else {
                $modeloSugPanel.Visible = $false
            }
        }

        $aplicarModeloSugestao = {
            if ($modeloSugList.SelectedIndex -lt 0) { return }
            $txtModelo.Text = [string]$modeloSugList.SelectedItem
            $txtModelo.SelectionStart = $txtModelo.Text.Length
            $modeloSugPanel.Visible = $false
            $txtModelo.Focus() | Out-Null
        }

        $txtModelo.Add_Enter({ & $atualizarModeloSugestoes })
        $txtModelo.Add_TextChanged({ & $atualizarModeloSugestoes })
        $txtModelo.Add_KeyDown({
            if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Down -and $modeloSugPanel.Visible -and $modeloSugList.Items.Count -gt 0) {
                $modeloSugList.SelectedIndex = 0
                $modeloSugList.Focus() | Out-Null
                $_.SuppressKeyPress = $true
            } elseif ($_.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
                $modeloSugPanel.Visible = $false
                $_.SuppressKeyPress = $true
            }
        })
        $modeloSugList.Add_MouseClick({ & $aplicarModeloSugestao })
        $modeloSugList.Add_KeyDown({
            if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
                & $aplicarModeloSugestao
                $_.SuppressKeyPress = $true
            } elseif ($_.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
                $modeloSugPanel.Visible = $false
                $txtModelo.Focus() | Out-Null
                $_.SuppressKeyPress = $true
            }
        })

        $txtSerial = New-ManualField 'Serial'         112 $script:serialEtiqueta
        $txtCpu    = New-ManualField 'Processador'    162 $script:cpuEtiqueta
        $txtMem    = New-ManualField 'Memoria'        212 $script:memEtiqueta
        $txtRam    = New-ManualField 'RAM'            262 $script:ramEtiqueta
        $txtGpu    = New-ManualField 'GPU'            312 $script:gpuEtiqueta
        $txtBat    = $null
        if ($info.MostrarBateria) {
            $txtBat = New-ManualField 'Bateria'        362 $script:bateriaEtiqueta
        }

        $txtCelularImei = New-ManualField 'IMEI' 162 $script:celularImeiEtiqueta
        $txtCelularImei.MaxLength = 15
        $bateriaCelularInicial = if ([string]$script:tipoEtiqueta -eq 'Celular') { [string]$script:bateriaEtiqueta } else { '' }
        $txtCelularBateria = New-ManualField 'Bateria' 212 $bateriaCelularInicial
        $armazenamentoCelularInicial = if ([string]$script:tipoEtiqueta -eq 'Celular') { [string]$script:memEtiqueta } else { '' }
        $txtCelularArmazenamento = New-ManualField 'Armazenamento' 262 $armazenamentoCelularInicial

        $btnLer3uTools = New-Object System.Windows.Forms.Button
        $btnLer3uTools.Text = 'Ler do 3uTools'
        $btnLer3uTools.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5, [System.Drawing.FontStyle]::Bold)
        $btnLer3uTools.ForeColor = [System.Drawing.Color]::FromArgb(245, 240, 255)
        $btnLer3uTools.BackColor = [System.Drawing.Color]::FromArgb(88, 33, 182)
        $btnLer3uTools.FlatStyle = 'Flat'
        $btnLer3uTools.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(167, 139, 250)
        $btnLer3uTools.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(109, 40, 217)
        $btnLer3uTools.Cursor = [System.Windows.Forms.Cursors]::Hand
        $btnLer3uTools.Location = New-Object System.Drawing.Point(16, 325)
        $btnLer3uTools.Size = New-Object System.Drawing.Size(392, 34)
        [void]$manualForm.Controls.Add($btnLer3uTools)
        Set-RoundedControl -Control $btnLer3uTools -Radius 6

        $lbl3uToolsStatus = New-Object System.Windows.Forms.Label
        $lbl3uToolsStatus.Text = 'Conecte o iPhone e abra a tela Informacoes no 3uTools.'
        $lbl3uToolsStatus.Font = New-Object System.Drawing.Font('Segoe UI', 7.5)
        $lbl3uToolsStatus.ForeColor = [System.Drawing.Color]::FromArgb(174, 165, 194)
        $lbl3uToolsStatus.Location = New-Object System.Drawing.Point(16, 365)
        $lbl3uToolsStatus.Size = New-Object System.Drawing.Size(392, 38)
        [void]$manualForm.Controls.Add($lbl3uToolsStatus)

        $btnLer3uTools.Add_Click({
            $btnLer3uTools.Enabled = $false
            $btnLer3uTools.Text = 'Lendo...'
            $lbl3uToolsStatus.ForeColor = [System.Drawing.Color]::FromArgb(196, 181, 253)
            $lbl3uToolsStatus.Text = 'Consultando o aparelho mais recente...'
            [System.Windows.Forms.Application]::DoEvents()
            try {
                $device3u = Get-3uToolsDeviceInfo
                $txtModelo.Text = [string]$device3u.Modelo
                $txtSerial.Text = [string]$device3u.Serial
                $txtCelularImei.Text = [string]$device3u.Imei
                $txtCelularArmazenamento.Text = [string]$device3u.Armazenamento
                $armazenamentoTexto = if ($device3u.Armazenamento) { " | $($device3u.Armazenamento)" } else { '' }
                if ($device3u.Bateria) {
                    $txtCelularBateria.Text = [string]$device3u.Bateria
                    $ciclosTexto = if ([int]$device3u.Ciclos -gt 0) { " | $($device3u.Ciclos) ciclos" } else { '' }
                    $lbl3uToolsStatus.ForeColor = [System.Drawing.Color]::FromArgb(74, 222, 128)
                    $lbl3uToolsStatus.Text = "Dados lidos: $($device3u.Bateria)$ciclosTexto$armazenamentoTexto."
                } else {
                    $txtCelularBateria.Text = ''
                    $lbl3uToolsStatus.ForeColor = [System.Drawing.Color]::FromArgb(251, 191, 36)
                    $lbl3uToolsStatus.Text = "Dados lidos. Bateria indisponivel: $($device3u.BateriaErro)"
                }
            } catch {
                $lbl3uToolsStatus.ForeColor = [System.Drawing.Color]::FromArgb(251, 113, 133)
                $lbl3uToolsStatus.Text = $_.Exception.Message
            } finally {
                $btnLer3uTools.Enabled = $true
                $btnLer3uTools.Text = 'Ler do 3uTools'
            }
        })

        $txtMonitorTamanho = New-ManualField 'Tamanho da tela' 162 (Get-MonitorTamanhoNumero -Valor ([string]$script:monitorTamanhoEtiqueta))
        $txtMonitorTamanho.Size = New-Object System.Drawing.Size(198, 24)
        $txtMonitorTamanho.MaxLength = 5
        $txtMonitorTamanho.Add_KeyPress({
            if (
                -not [char]::IsControl($_.KeyChar) -and
                -not [char]::IsDigit($_.KeyChar) -and
                $_.KeyChar -notin @(',', '.')
            ) {
                $_.Handled = $true
            }
        })

        $monitorPolegadas = New-Object System.Windows.Forms.Label
        $monitorPolegadas.Text = 'polegadas'
        $monitorPolegadas.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8)
        $monitorPolegadas.ForeColor = [System.Drawing.Color]::FromArgb(196, 181, 253)
        $monitorPolegadas.BackColor = [System.Drawing.Color]::FromArgb(20, 17, 42)
        $monitorPolegadas.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $monitorPolegadas.Location = New-Object System.Drawing.Point(216, 180)
        $monitorPolegadas.Size = New-Object System.Drawing.Size(82, 24)
        [void]$manualForm.Controls.Add($monitorPolegadas)
        Set-RoundedControl -Control $monitorPolegadas -Radius 4

        $entradasLabel = New-Object System.Windows.Forms.Label
        $entradasLabel.Text = 'Entradas'
        $entradasLabel.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
        $entradasLabel.ForeColor = $cAccent
        $entradasLabel.Location = New-Object System.Drawing.Point(16, 212)
        $entradasLabel.Size = New-Object System.Drawing.Size(160, 18)
        [void]$manualForm.Controls.Add($entradasLabel)

        $entradasPanel = New-Object System.Windows.Forms.Panel
        $entradasPanel.Location = New-Object System.Drawing.Point(16, 230)
        $entradasPanel.Size = New-Object System.Drawing.Size(392, 42)
        $entradasPanel.BackColor = [System.Drawing.Color]::FromArgb(10, 22, 34)
        [void]$manualForm.Controls.Add($entradasPanel)
        Set-RoundedControl -Control $entradasPanel -Radius 6

        $monitorEntradasSalvas = ([string]$script:monitorEntradasEtiqueta).ToUpper()
        $entradaChecks = @()
        $entradaX = 10
        foreach ($entradaNome in @('VGA', 'HDMI', 'DISPLAYPORT')) {
            $entradaCheck = New-Object System.Windows.Forms.CheckBox
            $entradaCheck.Text = $entradaNome
            $entradaCheck.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8, [System.Drawing.FontStyle]::Bold)
            $entradaCheck.ForeColor = [System.Drawing.Color]::FromArgb(218, 211, 232)
            $entradaCheck.BackColor = $entradasPanel.BackColor
            $entradaCheck.FlatStyle = 'Flat'
            $entradaCheck.Cursor = [System.Windows.Forms.Cursors]::Hand
            $entradaCheck.Location = New-Object System.Drawing.Point($entradaX, 9)
            $entradaCheck.Size = if ($entradaNome -eq 'DISPLAYPORT') {
                New-Object System.Drawing.Size(132, 24)
            } else {
                New-Object System.Drawing.Size(82, 24)
            }
            $entradaCheck.Checked = ($monitorEntradasSalvas -match "(^|[/,\s])$entradaNome($|[/,\s])")
            [void]$entradasPanel.Controls.Add($entradaCheck)
            $entradaChecks += $entradaCheck
            $entradaX += if ($entradaNome -eq 'DISPLAYPORT') { 132 } else { 86 }
        }

        foreach ($campoManual in @($txtSerial, $txtCpu, $txtMem, $txtRam, $txtGpu, $txtBat, $txtMonitorTamanho, $txtCelularImei, $txtCelularBateria)) {
            if ($campoManual) {
                $campoManual.Add_Enter({ $modeloSugPanel.Visible = $false })
            }
        }

        $tabIndexManual = 10
        foreach ($campoManual in @($txtModelo, $txtSerial, $txtCpu, $txtMem, $txtRam, $txtGpu, $txtBat, $txtMonitorTamanho, $txtCelularImei, $txtCelularBateria)) {
            if (-not $campoManual) { continue }
            $campoManual.TabIndex = $tabIndexManual
            $tabIndexManual += 10
            $campoManual.Add_KeyDown({
                if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter -and -not $modeloSugList.Focused) {
                    $modeloSugPanel.Visible = $false
                    [void]$manualForm.SelectNextControl($this, $true, $true, $true, $true)
                    $_.SuppressKeyPress = $true
                }
            })
        }

        $btnSemModelo = New-ManualQuickButton 'Sem modelo' 62  $txtModelo 'N/A'
        $btnSemSerial = New-ManualQuickButton 'Sem serial' 112 $txtSerial 'XXXXXX'
        $btnSemCpu = New-ManualQuickButton 'Sem CPU'    162 $txtCpu    'N/A'
        $btnSemDisco = New-ManualQuickButton 'Sem disco'  212 $txtMem    'N/A'
        $btnSemRam = New-ManualQuickButton 'Sem RAM'    262 $txtRam    'N/A'
        $btnSemGpu = New-ManualQuickButton 'Sem GPU'    312 $txtGpu    ''
        $btnSemBat = $null
        if ($info.MostrarBateria) {
            $btnSemBat = New-ManualQuickButton 'Sem bateria' 362 $txtBat 'NA'
        }

        $atualizarTipoManual = {
            $isMonitorManual = ([string]$manualForm.Tag -eq 'Monitor')
            $isCelularManual = ([string]$manualForm.Tag -eq 'Celular')
            $isDesktopManual = ([string]$manualForm.Tag -eq 'Desktop')
            $isNotebookManual = ([string]$manualForm.Tag -eq 'Notebook')
            $isComputadorManual = ($isNotebookManual -or $isDesktopManual)
            foreach ($tipoVisual in @(
                @{ Botao=$btnTipoNotebook; Ativo=$isNotebookManual },
                @{ Botao=$btnTipoDesktop; Ativo=$isDesktopManual },
                @{ Botao=$btnTipoMonitor; Ativo=$isMonitorManual },
                @{ Botao=$btnTipoCelular; Ativo=$isCelularManual }
            )) {
                $tipoVisual.Botao.BackColor = if ($tipoVisual.Ativo) { $previewUiPrimary } else { $previewUiRaised }
                $tipoVisual.Botao.ForeColor = if ($tipoVisual.Ativo) { [System.Drawing.Color]::White } else { $previewUiMuted }
                $tipoVisual.Botao.FlatAppearance.BorderColor = if ($tipoVisual.Ativo) { $previewUiPrimary } else { $previewUiBorder }
                $tipoVisual.Botao.FlatAppearance.MouseOverBackColor = if ($tipoVisual.Ativo) { $previewUiPrimaryHover } else { [System.Drawing.Color]::FromArgb(31, 35, 52) }
            }

            $txtModelo.Tag.Text = if ($isCelularManual) { 'Nome' } else { 'Nome do modelo' }
            $txtSerial.Tag.Text = if ($isCelularManual) { 'Serial Number' } else { 'Serial' }

            foreach ($campoComputador in @($txtCpu, $txtMem, $txtRam, $txtGpu)) {
                if ($campoComputador) {
                    $campoComputador.Visible = $isComputadorManual
                    if ($campoComputador.Tag) { $campoComputador.Tag.Visible = $isComputadorManual }
                }
            }
            if ($txtBat) {
                $txtBat.Visible = $isNotebookManual
                if ($txtBat.Tag) { $txtBat.Tag.Visible = $isNotebookManual }
            }
            foreach ($botaoComputador in @($btnSemCpu, $btnSemDisco, $btnSemRam, $btnSemGpu)) {
                if ($botaoComputador) { $botaoComputador.Visible = $isComputadorManual }
            }
            if ($btnSemBat) { $btnSemBat.Visible = $isNotebookManual }
            foreach ($campoMonitor in @($txtMonitorTamanho)) {
                $campoMonitor.Visible = $isMonitorManual
                if ($campoMonitor.Tag) { $campoMonitor.Tag.Visible = $isMonitorManual }
            }
            $monitorPolegadas.Visible = $isMonitorManual
            $entradasLabel.Visible = $isMonitorManual
            $entradasPanel.Visible = $isMonitorManual
            foreach ($campoCelular in @($txtCelularImei, $txtCelularBateria, $txtCelularArmazenamento)) {
                $campoCelular.Visible = $isCelularManual
                if ($campoCelular.Tag) { $campoCelular.Tag.Visible = $isCelularManual }
            }
            $btnLer3uTools.Visible = $isCelularManual
            $lbl3uToolsStatus.Visible = $isCelularManual
            $modeloSugPanel.Visible = $false
        }
        $selecionarTipoManual = {
            param([string]$Tipo)
            $manualForm.Tag = $Tipo
            $modeloSalvoTipo = Get-ModeloManualUltimo -Tipo $Tipo
            if (-not [string]::IsNullOrWhiteSpace($modeloSalvoTipo)) {
                $txtModelo.Text = $modeloSalvoTipo
                $txtModelo.SelectionStart = $txtModelo.Text.Length
            }
            & $atualizarTipoManual
        }.GetNewClosure()
        $btnTipoNotebook.Add_Click({ & $selecionarTipoManual 'Notebook' })
        $btnTipoDesktop.Add_Click({ & $selecionarTipoManual 'Desktop' })
        $btnTipoMonitor.Add_Click({ & $selecionarTipoManual 'Monitor' })
        $btnTipoCelular.Add_Click({ & $selecionarTipoManual 'Celular' })
        & $atualizarTipoManual

        $btnManualCancelar = New-Object System.Windows.Forms.Button
        $btnManualCancelar.Text = 'Cancelar'
        $btnManualCancelar.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
        $btnManualCancelar.ForeColor = $previewUiText
        $btnManualCancelar.BackColor = $previewUiSurface
        $btnManualCancelar.FlatStyle = 'Flat'
        $btnManualCancelar.FlatAppearance.BorderColor = $previewUiBorder
        $btnManualCancelar.FlatAppearance.MouseOverBackColor = $previewUiRaised
        $btnManualCancelar.Location = New-Object System.Drawing.Point(16, 456)
        $btnManualCancelar.Size = New-Object System.Drawing.Size(120, 34)
        $btnManualCancelar.Add_Click({ $manualForm.DialogResult = 'Cancel'; $manualForm.Close() })
        $manualForm.Controls.Add($btnManualCancelar)
        Set-RoundedControl -Control $btnManualCancelar -Radius 8

        $btnManualSalvar = New-Object System.Windows.Forms.Button
        $btnManualSalvar.Text = 'Salvar dados'
        $btnManualSalvar.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9, [System.Drawing.FontStyle]::Bold)
        $btnManualSalvar.ForeColor = [System.Drawing.Color]::White
        $btnManualSalvar.BackColor = $previewUiPrimary
        $btnManualSalvar.FlatStyle = 'Flat'
        $btnManualSalvar.FlatAppearance.BorderColor = $previewUiPrimary
        $btnManualSalvar.FlatAppearance.MouseOverBackColor = $previewUiPrimaryHover
        $btnManualSalvar.Location = New-Object System.Drawing.Point(286, 456)
        $btnManualSalvar.Size = New-Object System.Drawing.Size(122, 34)
        $btnManualSalvar.Add_Click({
            $modelo = $txtModelo.Text.Trim()
            $serial = $txtSerial.Text.Trim()
            $cpu    = $txtCpu.Text.Trim()
            $mem    = $txtMem.Text.Trim()
            $ram    = $txtRam.Text.Trim()
            $gpu    = $txtGpu.Text.Trim()
            $bat    = if ($info.MostrarBateria) { $txtBat.Text.Trim() } else { $null }
            $monitorTamanho = Get-MonitorTamanhoNumero -Valor $txtMonitorTamanho.Text
            $monitorEntradas = @($entradaChecks | Where-Object { $_.Checked } | ForEach-Object { [string]$_.Text })
            $isMonitorManual = ([string]$manualForm.Tag -eq 'Monitor')
            $isCelularManual = ([string]$manualForm.Tag -eq 'Celular')
            $isDesktopManual = ([string]$manualForm.Tag -eq 'Desktop')
            $isNotebookManual = ([string]$manualForm.Tag -eq 'Notebook')
            $celularImei = ($txtCelularImei.Text -replace '[^0-9]', '')
            $celularBateria = $txtCelularBateria.Text.Trim()
            $celularArmazenamento = $txtCelularArmazenamento.Text.Trim()
            $faltamDadosBase = (
                [string]::IsNullOrWhiteSpace($modelo) -or
                [string]::IsNullOrWhiteSpace($serial)
            )
            $faltamDadosMonitor = (
                $isMonitorManual -and (
                    [string]::IsNullOrWhiteSpace($monitorTamanho) -or
                    $monitorEntradas.Count -eq 0
                )
            )
            $faltamDadosCelular = $false
            $faltamDadosNotebook = (
                $isNotebookManual -and (
                    [string]::IsNullOrWhiteSpace($cpu) -or
                    [string]::IsNullOrWhiteSpace($mem) -or
                    [string]::IsNullOrWhiteSpace($ram) -or
                    ($info.MostrarBateria -and [string]::IsNullOrWhiteSpace($bat))
                )
            )
            if ($faltamDadosBase -or $faltamDadosMonitor -or $faltamDadosCelular -or $faltamDadosNotebook) {
                $mensagemObrigatoria = if ($isMonitorManual) {
                    'Informe modelo, serial, tamanho e ao menos uma entrada do monitor.'
                } elseif ($isCelularManual) {
                    'Informe nome e Serial Number do celular. IMEI e bateria sao opcionais.'
                } else {
                    'Preencha todos os campos para salvar os dados manuais.'
                }
                [System.Windows.Forms.MessageBox]::Show(
                    $mensagemObrigatoria,
                    'Campos obrigatorios',
                    'OK',
                    'Warning'
                ) | Out-Null
                return
            }
            if ($isCelularManual -and $celularImei -and $celularImei.Length -ne 15) {
                [System.Windows.Forms.MessageBox]::Show(
                    'O IMEI deve conter exatamente 15 numeros.',
                    'IMEI invalido',
                    'OK',
                    'Warning'
                ) | Out-Null
                $txtCelularImei.Focus() | Out-Null
                $txtCelularImei.SelectAll()
                return
            }
            $serialAnterior = Find-SerialManualNoHistorico -Serial $serial
            if ($serialAnterior) {
                $osAnterior = if ($serialAnterior.os) { [string]$serialAnterior.os } else { 'OS nao informada' }
                $dataAnterior = if ($serialAnterior.dataHora) { [string]$serialAnterior.dataHora } else { 'data nao informada' }
                $continuarSerial = [System.Windows.Forms.MessageBox]::Show(
                    "A serial $serial ja aparece no historico.`n`nRegistro: $osAnterior em $dataAnterior.`n`nDeseja continuar mesmo assim?",
                    'Serial ja utilizada',
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                )
                if ($continuarSerial -ne [System.Windows.Forms.DialogResult]::Yes) {
                    $txtSerial.Focus() | Out-Null
                    $txtSerial.SelectAll()
                    return
                }
            }
            $script:modeloEtiqueta = $modelo
            $script:serialEtiqueta = $serial
            $script:tipoEtiqueta = if ($isMonitorManual) { 'Monitor' } elseif ($isCelularManual) { 'Celular' } elseif ($isDesktopManual) { 'Desktop' } else { 'Notebook' }
            if ($isCelularManual -and ([string]$script:gradeAtual) -match '^C\s*-\s*PINTURA') {
                $script:gradeAtual = 'C'
                $script:pinturaOpcaoAtual = ''
            }
            if ($isMonitorManual) {
                $script:monitorTamanhoEtiqueta = Format-MonitorTamanhoEtiqueta -Valor $monitorTamanho
                $script:monitorEntradasEtiqueta = ($monitorEntradas -join ' / ')
                $script:celularImeiEtiqueta = ''
                $script:cpuEtiqueta = ''
                $script:memEtiqueta = ''
                $script:ramEtiqueta = ''
                $script:gpuEtiqueta = ''
                $script:bateriaEtiqueta = $null
            } elseif ($isCelularManual) {
                $script:monitorTamanhoEtiqueta = ''
                $script:monitorEntradasEtiqueta = ''
                $script:celularImeiEtiqueta = $celularImei
                $script:cpuEtiqueta = ''
                $script:memEtiqueta = $celularArmazenamento
                $script:ramEtiqueta = ''
                $script:gpuEtiqueta = ''
                $script:bateriaEtiqueta = $celularBateria
            } else {
                $script:monitorTamanhoEtiqueta = ''
                $script:monitorEntradasEtiqueta = ''
                $script:celularImeiEtiqueta = ''
                $script:cpuEtiqueta    = $cpu
                $script:memEtiqueta    = $mem
                $script:ramEtiqueta    = $ram
                $script:gpuEtiqueta    = $gpu
                $script:bateriaEtiqueta = if ($isDesktopManual) { $null } else { $bat }
            }
            $script:modoManualEtiqueta = $true
            Add-ModeloManualHistorico -Modelo $modelo
            $modeloPersistido = Save-ModeloManualUltimo -Tipo ([string]$script:tipoEtiqueta) -Modelo $modelo
            if (-not $modeloPersistido) {
                [System.Windows.Forms.MessageBox]::Show(
                    'Os dados foram aplicados, mas nao foi possivel salvar o modelo para a proxima abertura.',
                    'Modelo nao persistido',
                    'OK',
                    'Warning'
                ) | Out-Null
            }
            $manualForm.DialogResult = 'OK'
            $manualForm.Close()
        })
        $manualForm.Controls.Add($btnManualSalvar)
        Set-RoundedControl -Control $btnManualSalvar -Radius 8
        $manualForm.AcceptButton = $btnManualSalvar
        $manualForm.CancelButton = $btnManualCancelar

        foreach ($controleManualExistente in @($manualForm.Controls)) {
            $controleManualExistente.Top += 64
        }

        $manualHeader = New-Object System.Windows.Forms.Panel
        $manualHeader.Location = New-Object System.Drawing.Point(0, 0)
        $manualHeader.Size = New-Object System.Drawing.Size(440, 64)
        $manualHeader.BackColor = $previewUiSurface
        [void]$manualForm.Controls.Add($manualHeader)

        $manualHeaderLine = New-Object System.Windows.Forms.Panel
        $manualHeaderLine.Location = New-Object System.Drawing.Point(0, 63)
        $manualHeaderLine.Size = New-Object System.Drawing.Size(440, 1)
        $manualHeaderLine.BackColor = $previewUiBorder
        [void]$manualHeader.Controls.Add($manualHeaderLine)

        $manualEyebrow = New-Object System.Windows.Forms.Label
        $manualEyebrow.Text = 'ETIQUETA  /  DADOS MANUAIS'
        $manualEyebrow.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 6.8, [System.Drawing.FontStyle]::Bold)
        $manualEyebrow.ForeColor = $previewUiPrimaryHover
        $manualEyebrow.Location = New-Object System.Drawing.Point(20, 10)
        $manualEyebrow.Size = New-Object System.Drawing.Size(280, 14)
        [void]$manualHeader.Controls.Add($manualEyebrow)

        $manualTitle = New-Object System.Windows.Forms.Label
        $manualTitle.Text = 'Preencher dados manualmente'
        $manualTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 13, [System.Drawing.FontStyle]::Bold)
        $manualTitle.ForeColor = $previewUiText
        $manualTitle.Location = New-Object System.Drawing.Point(18, 27)
        $manualTitle.Size = New-Object System.Drawing.Size(340, 25)
        [void]$manualHeader.Controls.Add($manualTitle)

        $manualClose = New-Object System.Windows.Forms.Button
        $manualClose.Text = [string][char]0x00D7
        $manualClose.Font = New-Object System.Drawing.Font('Segoe UI', 15)
        $manualClose.ForeColor = $previewUiMuted
        $manualClose.BackColor = $previewUiSurface
        $manualClose.FlatStyle = 'Flat'
        $manualClose.FlatAppearance.BorderSize = 0
        $manualClose.FlatAppearance.MouseOverBackColor = $previewUiRaised
        $manualClose.Location = New-Object System.Drawing.Point(396, 10)
        $manualClose.Size = New-Object System.Drawing.Size(32, 32)
        $manualClose.Cursor = [System.Windows.Forms.Cursors]::Hand
        $manualClose.Add_Click({ $manualForm.DialogResult = 'Cancel'; $manualForm.Close() })
        [void]$manualHeader.Controls.Add($manualClose)

        $manualDrag = [pscustomobject]@{ Ativo=$false; Origem=[System.Drawing.Point]::Empty }
        $manualHeader.Add_MouseDown({
            if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) { $manualDrag.Ativo=$true; $manualDrag.Origem=$_.Location }
        })
        $manualHeader.Add_MouseMove({
            if ($manualDrag.Ativo) { $manualForm.Location = New-Object System.Drawing.Point(($manualForm.Left + $_.X - $manualDrag.Origem.X), ($manualForm.Top + $_.Y - $manualDrag.Origem.Y)) }
        })
        $manualHeader.Add_MouseUp({ $manualDrag.Ativo=$false })

        $manualFooterLine = New-Object System.Windows.Forms.Panel
        $manualFooterLine.Location = New-Object System.Drawing.Point(16, 510)
        $manualFooterLine.Size = New-Object System.Drawing.Size(392, 1)
        $manualFooterLine.BackColor = $previewUiBorder
        [void]$manualForm.Controls.Add($manualFooterLine)
        $manualHeader.BringToFront()
        $manualForm.Add_Shown({
            $txtModelo.Focus() | Out-Null
            $txtModelo.SelectAll()
        })

        Set-CaijWindowsTypography -Root $manualForm
        $resManual = $manualForm.ShowDialog($popup)
        if ($resManual -eq 'OK') {
            & $script:AtualizarGradeState
            & $script:AtualizarResumoAltertagPreview
            & $script:DesenharPrevia $script:gradeAtual $script:obsAtual $script:incluirOSAtual
        }
    })
    $popup.Controls.Add($btnManual)
    Set-RoundedControl -Control $btnManual -Radius 8

    $btnAuto = New-Object System.Windows.Forms.Button
    $btnAuto.Text = ([string][char]0x21BB + '  Leitura automatica')
    $btnAuto.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8, [System.Drawing.FontStyle]::Bold)
    $btnAuto.ForeColor = $previewUiText
    $btnAuto.BackColor = $previewUiRaised
    $btnAuto.FlatStyle = 'Flat'
    $btnAuto.FlatAppearance.BorderColor = $previewUiBorder
    $btnAuto.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(31, 35, 52)
    $btnAuto.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnAuto.Location = New-Object System.Drawing.Point(320, 508)
    $btnAuto.Size = New-Object System.Drawing.Size(174, 30)
    $btnAuto.Add_Click({
        $script:modeloEtiqueta = $info.Modelo
        $script:serialEtiqueta = $info.Serial
        $script:cpuEtiqueta    = $cpuCurto
        $script:memEtiqueta    = $discoCurto
        $script:ramEtiqueta    = $ramCurto
        $script:gpuEtiqueta    = $gpuCurta
        $script:bateriaEtiqueta = if ($info.MostrarBateria) { $info.BatSaude } else { $null }
        $script:tipoEtiqueta = [string]$info.TipoEquipamento
        $script:monitorTamanhoEtiqueta = ''
        $script:monitorEntradasEtiqueta = ''
        $script:celularImeiEtiqueta = ''
        $script:modoManualEtiqueta = $false
        & $script:DesenharPrevia $script:gradeAtual (& $script:GetObsImpressao) $script:incluirOSAtual
    })
    $popup.Controls.Add($btnAuto)
    Set-RoundedControl -Control $btnAuto -Radius 8

    # Caption da linha de fonte de dados
    $lblFonteDados = New-Object System.Windows.Forms.Label
    $lblFonteDados.Text      = 'FONTE DOS DADOS'
    $lblFonteDados.Font      = New-Object System.Drawing.Font('Segoe UI', 6.5, [System.Drawing.FontStyle]::Bold)
    $lblFonteDados.ForeColor = $previewUiMuted
    $lblFonteDados.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $lblFonteDados.Location  = New-Object System.Drawing.Point(320, 480)
    $lblFonteDados.Size      = New-Object System.Drawing.Size(292, 22)
    $popup.Controls.Add($lblFonteDados)

    # Divisor acima do rodape
    $footerDivider = New-Object System.Windows.Forms.Panel
    $footerDivider.BackColor = $previewUiBorder
    $footerDivider.Location  = New-Object System.Drawing.Point(20, 558)
    $footerDivider.Size      = New-Object System.Drawing.Size(880, 1)
    $popup.Controls.Add($footerDivider)

    # Estado visual do seletor de fonte (chip ativo acende)
    $script:UpdateFonteDados = {
        if ($script:modoManualEtiqueta) {
            $btnManual.ForeColor = [System.Drawing.Color]::White
            $btnManual.BackColor = $previewUiPrimary
            $btnManual.FlatAppearance.BorderColor = $previewUiPrimary
            $btnAuto.ForeColor = $previewUiMuted
            $btnAuto.BackColor = $previewUiRaised
            $btnAuto.FlatAppearance.BorderColor = $previewUiBorder
        } else {
            $btnAuto.ForeColor = [System.Drawing.Color]::White
            $btnAuto.BackColor = $previewUiPrimary
            $btnAuto.FlatAppearance.BorderColor = $previewUiPrimary
            $btnManual.ForeColor = $previewUiMuted
            $btnManual.BackColor = $previewUiRaised
            $btnManual.FlatAppearance.BorderColor = $previewUiBorder
        }
    }
    $btnAuto.Add_Click({ & $script:UpdateFonteDados })
    $btnManual.Add_Click({ & $script:UpdateFonteDados })
    & $script:UpdateFonteDados

    $btnConfirmar = New-Object System.Windows.Forms.Button
    $btnConfirmar.Text = 'Confirmar e Imprimir'
    $btnConfirmar.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5, [System.Drawing.FontStyle]::Bold)
    $btnConfirmar.ForeColor = [System.Drawing.Color]::White
    $btnConfirmar.BackColor = $previewUiPrimary
    $btnConfirmar.FlatStyle = 'Flat'
    $btnConfirmar.FlatAppearance.BorderColor = $previewUiPrimary
    $btnConfirmar.FlatAppearance.MouseOverBackColor = $previewUiPrimaryHover
    $btnConfirmar.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(78, 89, 184)
    $btnConfirmar.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnConfirmar.Location = New-Object System.Drawing.Point(738, 576)
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
            $btnConfirmar.BackColor = $previewUiPrimary
            $btnConfirmar.FlatAppearance.BorderColor = $previewUiPrimary
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
        $altertagCard,
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

    $script:osPreviewRefreshAction = {
        if ($popup -and -not $popup.IsDisposed) {
            if (-not $printContext.CriadaAgora) {
                $printContext.OsNumero = [int]$script:osNumero
            }
            $btnAlterarOsPreview.Text = (Format-OsCodigo -Numero $printContext.OsNumero)
            & $script:DesenharPrevia $script:gradeAtual (& $script:GetObsImpressao) $script:incluirOSAtual
        }
    }.GetNewClosure()
    $abrirManualAutomaticamente = (
        ($reusarPreviaManual -and $script:abrirManualNaProximaPrevia) -or
        $script:abrirManualPorOsSelecionada
    )
    if ($abrirManualAutomaticamente) {
        $script:abrirManualNaProximaPrevia = $false
        $script:abrirManualPorOsSelecionada = $false
        $popup.Add_Shown({
            [void]$popup.BeginInvoke([System.Action]{
                if ($btnManual.Enabled) { $btnManual.PerformClick() }
            })
        })
    }
    Set-CaijWindowsTypography -Root $popup
    $resultado = $popup.ShowDialog()
    $script:osPreviewRefreshAction = $null
    $script:AtualizarResumoAltertagPreview = $null

    if ($resultado -ne 'OK') {
        $btnImprimir.Enabled = $true
        $btnImprimir.Text    = ([string][char]0x2399 + '  Imprimir etiqueta')
        return
    }

    $btnImprimir.Text = 'Enviando...'
    Set-AppStatus -Texto 'Enviando etiqueta para o servidor...' -Cor $cAccent
    [System.Windows.Forms.Application]::DoEvents()

    # Monta JSON com dados + grade + obs
    if ($script:incluirOSAtual -and -not $printContext.CriadaAgora -and -not $script:osDefinidaPorTriagem -and -not $script:osDefinidaPorAltertag -and -not $script:osDefinidaManual) {
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
        Set-AppStatus -Texto "OS da triagem aplicada: $(Format-OsCodigo -Numero $printContext.OsNumero)" -Cor $cGreen
    } elseif ($script:incluirOSAtual -and ($script:osDefinidaPorAltertag -or $printContext.CriadaAgora)) {
        Set-AppStatus -Texto "OS Altertag confirmada para impressao: $(Format-OsCodigo -Numero $printContext.OsNumero)" -Cor $cGreen
    }

    $gpuPayload = if ($script:modoManualEtiqueta) {
        [string]$script:gpuEtiqueta
    } else {
        [string]$info.GPU
    }
    $dadosJson = @{
        os      = if ($script:incluirOSAtual) { $printContext.OsNumero } else { $null }
        modelo  = $script:modeloEtiqueta
        serial  = $script:serialEtiqueta
        tipoEquipamento = if ($script:tipoEtiqueta) { [string]$script:tipoEtiqueta } else { 'Notebook' }
        monitorTamanho = [string]$script:monitorTamanhoEtiqueta
        monitorEntradas = [string]$script:monitorEntradasEtiqueta
        celularImei = [string]$script:celularImeiEtiqueta
        cpu     = $script:cpuEtiqueta
        gpu     = if (& $script:IsGpuEtiquetaVisivel $gpuPayload) { $gpuPayload } else { $null }
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
        $gradeImpressa = if ($script:rnaAtivo) { 'RMA' } elseif ($script:gradeAtual) { [string]$script:gradeAtual } else { 'A' }
        $script:ultimaEtiquetaPayload = [string]$dadosJson
        $script:ultimaEtiquetaResumo = [pscustomobject]@{
            osNumero = [int]$printContext.OsNumero
            serial = [string]$script:serialEtiqueta
            modelo = [string]$script:modeloEtiqueta
            cpu = [string]$script:cpuEtiqueta
            ram = [string]$script:ramEtiqueta
            disco = [string]$script:memEtiqueta
            gpu = [string]$script:gpuEtiqueta
            bateria = [string]$script:bateriaEtiqueta
            grade = $gradeImpressa
            obs = [string]$script:obsAtual
        }
        Add-HistoricoNotebook `
            -Acao 'impressao' `
            -Status 'ok' `
            -Mensagem 'Etiqueta enviada com sucesso' `
            -Grade $gradeImpressa `
            -Obs $script:obsAtual `
            -OsNumero $printContext.OsNumero `
            -Serial $script:serialEtiqueta `
            -Modelo $script:modeloEtiqueta `
            -Cpu $script:cpuEtiqueta `
            -Ram $script:ramEtiqueta `
            -Disco $script:memEtiqueta `
            -Gpu $script:gpuEtiqueta `
            -Bateria ([string]$script:bateriaEtiqueta)
        $statusOsRegistrado = Register-OsAltertagStatusImpressao `
            -Grade $script:gradeAtual `
            -Obs $script:obsAtual `
            -OsNumero $printContext.OsNumero `
            -Ordem $printContext.Ordem `
            -ForcarAltertag:$printContext.CriadaAgora
        if ($script:incluirOSAtual) { Sync-OsFromAltertag -Silent }
        if ($statusOsRegistrado) {
            Set-AppStatus -Texto "Impresso | status registrado na OS $(Format-OsCodigo -Numero $printContext.OsNumero)" -Cor $cGreen
        } else {
            Set-AppStatus -Texto "Impresso | historico salvo | OS $(Format-OsCodigo -Numero $printContext.OsNumero)" -Cor $cGreen
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
        Add-HistoricoNotebook `
            -Acao 'impressao' `
            -Status 'erro' `
            -Mensagem $erro `
            -Grade $script:gradeAtual `
            -Obs $script:obsAtual `
            -OsNumero $printContext.OsNumero `
            -Serial $script:serialEtiqueta `
            -Modelo $script:modeloEtiqueta `
            -Cpu $script:cpuEtiqueta `
            -Ram $script:ramEtiqueta `
            -Disco $script:memEtiqueta `
            -Gpu $script:gpuEtiqueta `
            -Bateria ([string]$script:bateriaEtiqueta)
        Set-AppStatus -Texto 'Falha ao imprimir | historico salvo' -Cor $cRed
        $btnImprimir.Text      = 'Erro ao enviar!'
        $btnImprimir.BackColor = [System.Drawing.Color]::FromArgb(130, 30, 30)
    }

    $btnImprimir.Enabled = $true
    $resetImpTimer = New-Object System.Windows.Forms.Timer
    $resetImpTimer.Interval = 1500
    $resetImpTimer.Add_Tick({
        $btnImprimir.Text      = ([string][char]0x2399 + '  Imprimir etiqueta')
        $btnImprimir.BackColor = [System.Drawing.Color]::FromArgb(94, 106, 210)
        $this.Stop()
        $this.Dispose()
    })
    $resetImpTimer.Start()

    if ($impressaoConcluida -and $script:modoManualEtiqueta) {
        $script:modeloEtiqueta = ''
        $script:serialEtiqueta = ''
        $script:cpuEtiqueta = ''
        $script:memEtiqueta = ''
        $script:ramEtiqueta = ''
        $script:gpuEtiqueta = ''
        $script:bateriaEtiqueta = $null
        $script:monitorTamanhoEtiqueta = ''
        $script:monitorEntradasEtiqueta = ''
        $script:celularImeiEtiqueta = ''
        $script:obsAtual = ''
        $script:rnaAtivo = $false
        $script:rnaItensOk = @()
        $script:modoManualEtiqueta = $false
        $script:abrirManualNaProximaPrevia = $false
        $script:reabrindoPreviaManual = $false
        if ($script:reabrirPreviaTimer) {
            try { $script:reabrirPreviaTimer.Stop(); $script:reabrirPreviaTimer.Dispose() } catch {}
            $script:reabrirPreviaTimer = $null
        }
    }
})
# ================================================
# BARRA INFERIOR
# ================================================
$botY = $actY + $actBarH

$botBar = New-Object System.Windows.Forms.Panel
$botBar.BackColor = $cSurface
$botBar.Location  = New-Object System.Drawing.Point(0, $botY)
$botBar.Size      = New-Object System.Drawing.Size($W, 32)
$form.Controls.Add($botBar)

$botBar.Add_Paint({
    param($s, $e)
    $footerPen = New-Object System.Drawing.Pen($cBorder, 1)
    $e.Graphics.DrawLine($footerPen, 0, 0, $s.Width, 0)
    $footerPen.Dispose()
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
$script:botTxt.ForeColor = $cMuted
$script:botTxt.Location  = New-Object System.Drawing.Point(28, 9)
$script:botTxt.Size      = New-Object System.Drawing.Size(546, 14)
$botBar.Controls.Add($script:botTxt)

# Badge versao (direita)
$botVerBadge = New-Object System.Windows.Forms.Panel
$botVerBadge.BackColor   = $cCard
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
    $pen = New-Object System.Drawing.Pen($cBorder, 1)
    $e.Graphics.DrawPath($pen, $path)
    $pen.Dispose(); $path.Dispose()
})

$botVer = New-Object System.Windows.Forms.Label
$botVer.Text      = 'v4.1'
$botVer.Font      = New-Object System.Drawing.Font('Segoe UI', 7.5, [System.Drawing.FontStyle]::Bold)
$botVer.ForeColor = $cMuted
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

function Show-OsConcorrenciaPopup {
    param(
        $Os,
        [int]$ProximaOs,
        [int]$NovasCount = 1
    )
    if ($script:osGlobalAlertOpen -or -not $Os) { return }
    $numeroCriado = [int]$Os.numero
    if ($numeroCriado -lt 1 -or $ProximaOs -lt 1) { return }

    $script:osGlobalAlertOpen = $true
    $owner = [System.Windows.Forms.Form]::ActiveForm
    if (-not $owner -or $owner.IsDisposed) { $owner = $form }

    $alertForm = New-Object System.Windows.Forms.Form
    $alertForm.Text = 'Atualizacao de ordem de servico'
    $alertForm.ClientSize = New-Object System.Drawing.Size(540, 326)
    $alertForm.StartPosition = 'CenterParent'
    $alertForm.FormBorderStyle = 'None'
    $alertForm.BackColor = [System.Drawing.Color]::FromArgb(7, 9, 17)
    $alertForm.ForeColor = [System.Drawing.Color]::FromArgb(240, 242, 248)
    $alertForm.ShowInTaskbar = $false
    $alertForm.TopMost = $true
    $alertForm.KeyPreview = $true
    Set-RoundedControl -Control $alertForm -Radius 10
    $alertForm.Add_Paint({
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(42, 46, 63), 1)
        $_.Graphics.DrawRectangle($pen, 0, 0, ($this.Width - 1), ($this.Height - 1))
        $pen.Dispose()
    })

    $header = New-Object System.Windows.Forms.Panel
    $header.BackColor = [System.Drawing.Color]::FromArgb(15, 18, 29)
    $header.Location = New-Object System.Drawing.Point(0, 0)
    $header.Size = New-Object System.Drawing.Size(540, 78)
    [void]$alertForm.Controls.Add($header)
    $header.Add_Paint({
        param($s, $e)
        $headerLine = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(42, 46, 63), 1)
        $e.Graphics.DrawLine($headerLine, 0, ($s.Height - 1), $s.Width, ($s.Height - 1))
        $headerLine.Dispose()
    })

    $headerRail = New-Object System.Windows.Forms.Panel
    $headerRail.BackColor = [System.Drawing.Color]::FromArgb(94, 106, 210)
    $headerRail.Location = New-Object System.Drawing.Point(0, 0)
    $headerRail.Size = New-Object System.Drawing.Size(0, 78)
    [void]$header.Controls.Add($headerRail)

    $eyebrow = New-Object System.Windows.Forms.Label
    $eyebrow.Text = 'SINCRONIZACAO DA BANCADA'
    $eyebrow.Font = New-Object System.Drawing.Font('Segoe UI', 7, [System.Drawing.FontStyle]::Bold)
    $eyebrow.ForeColor = [System.Drawing.Color]::FromArgb(112, 124, 228)
    $eyebrow.Location = New-Object System.Drawing.Point(22, 11)
    $eyebrow.Size = New-Object System.Drawing.Size(300, 16)
    [void]$header.Controls.Add($eyebrow)

    $alertTitle = New-Object System.Windows.Forms.Label
    $alertTitle.Text = 'Nova OS detectada'
    $alertTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 16, [System.Drawing.FontStyle]::Bold)
    $alertTitle.ForeColor = [System.Drawing.Color]::FromArgb(240, 242, 248)
    $alertTitle.Location = New-Object System.Drawing.Point(20, 30)
    $alertTitle.Size = New-Object System.Drawing.Size(360, 34)
    [void]$header.Controls.Add($alertTitle)

    $livePill = New-Object System.Windows.Forms.Panel
    $livePill.BackColor = [System.Drawing.Color]::FromArgb(21, 24, 38)
    $livePill.Location = New-Object System.Drawing.Point(386, 23)
    $livePill.Size = New-Object System.Drawing.Size(112, 30)
    [void]$header.Controls.Add($livePill)
    Set-RoundedControl -Control $livePill -Radius 8
    $livePill.Add_Paint({
        param($s, $e)
        $pillBorder = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(42, 46, 63), 1)
        $e.Graphics.DrawRectangle($pillBorder, 0, 0, ($s.Width - 1), ($s.Height - 1))
        $pillBorder.Dispose()
    })

    $liveText = New-Object System.Windows.Forms.Label
    $liveText.Text = 'ATUALIZADO'
    $liveText.Font = New-Object System.Drawing.Font('Segoe UI', 7, [System.Drawing.FontStyle]::Bold)
    $liveText.ForeColor = [System.Drawing.Color]::FromArgb(46, 204, 113)
    $liveText.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $liveText.Dock = 'Fill'
    [void]$livePill.Controls.Add($liveText)

    $alertClose = New-Object System.Windows.Forms.Button
    $alertClose.Text = 'X'
    $alertClose.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
    $alertClose.ForeColor = [System.Drawing.Color]::FromArgb(166, 170, 184)
    $alertClose.BackColor = $header.BackColor
    $alertClose.FlatStyle = 'Flat'
    $alertClose.FlatAppearance.BorderSize = 0
    $alertClose.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(21, 24, 38)
    $alertClose.Location = New-Object System.Drawing.Point(505, 6)
    $alertClose.Size = New-Object System.Drawing.Size(28, 28)
    $alertClose.Cursor = [System.Windows.Forms.Cursors]::Hand
    $alertClose.Add_Click({ $alertForm.Close() })
    [void]$header.Controls.Add($alertClose)

    $alertDrag = @{ Active = $false; Mouse = [System.Drawing.Point]::Empty; Form = [System.Drawing.Point]::Empty }
    $header.Add_MouseDown({
        if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            $alertDrag.Active = $true
            $alertDrag.Mouse = [System.Windows.Forms.Cursor]::Position
            $alertDrag.Form = $alertForm.Location
        }
    })
    $header.Add_MouseMove({
        if ($alertDrag.Active) {
            $mouseNow = [System.Windows.Forms.Cursor]::Position
            $alertForm.Location = New-Object System.Drawing.Point(
                ($alertDrag.Form.X + $mouseNow.X - $alertDrag.Mouse.X),
                ($alertDrag.Form.Y + $mouseNow.Y - $alertDrag.Mouse.Y)
            )
        }
    })
    $header.Add_MouseUp({ $alertDrag.Active = $false })

    $tecnico = ([string]$Os.tecnico).Trim()
    if (-not $tecnico) { $tecnico = 'outra estacao' }
    $hora = (Get-Date).ToString('HH:mm:ss')
    try {
        if ($Os.dataCadastro) { $hora = ([datetime]::Parse([string]$Os.dataCadastro)).ToString('HH:mm:ss') }
    } catch {}
    $extra = if ($NovasCount -gt 1) { " e mais $($NovasCount - 1)" } else { '' }

    $detail = New-Object System.Windows.Forms.Label
    $detail.Text = "$(Format-OsCodigo -Numero $numeroCriado) foi criada por $tecnico as $hora$extra."
    $detail.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $detail.ForeColor = [System.Drawing.Color]::FromArgb(166, 170, 184)
    $detail.Location = New-Object System.Drawing.Point(22, 92)
    $detail.Size = New-Object System.Drawing.Size(496, 22)
    [void]$alertForm.Controls.Add($detail)

    $createdCard = New-Object System.Windows.Forms.Panel
    $createdCard.BackColor = [System.Drawing.Color]::FromArgb(21, 24, 38)
    $createdCard.Location = New-Object System.Drawing.Point(22, 126)
    $createdCard.Size = New-Object System.Drawing.Size(210, 76)
    [void]$alertForm.Controls.Add($createdCard)
    Set-RoundedControl -Control $createdCard -Radius 8
    $createdCard.Add_Paint({
        param($s, $e)
        $cardBorder = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(42, 46, 63), 1)
        $e.Graphics.DrawRectangle($cardBorder, 0, 0, ($s.Width - 1), ($s.Height - 1))
        $cardBorder.Dispose()
    })

    $createdCaption = New-Object System.Windows.Forms.Label
    $createdCaption.Text = 'OS CRIADA EM OUTRA ESTACAO'
    $createdCaption.Font = New-Object System.Drawing.Font('Segoe UI', 7, [System.Drawing.FontStyle]::Bold)
    $createdCaption.ForeColor = [System.Drawing.Color]::FromArgb(166, 170, 184)
    $createdCaption.Location = New-Object System.Drawing.Point(14, 11)
    $createdCaption.Size = New-Object System.Drawing.Size(170, 16)
    [void]$createdCard.Controls.Add($createdCaption)

    $createdValue = New-Object System.Windows.Forms.Label
    $createdValue.Text = (Format-OsCodigo -Numero $numeroCriado)
    $createdValue.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 15, [System.Drawing.FontStyle]::Bold)
    $createdValue.ForeColor = [System.Drawing.Color]::FromArgb(240, 242, 248)
    $createdValue.Location = New-Object System.Drawing.Point(13, 32)
    $createdValue.Size = New-Object System.Drawing.Size(180, 30)
    [void]$createdCard.Controls.Add($createdValue)

    $arrow = New-Object System.Windows.Forms.Label
    $arrow.Text = [char]0x2192
    $arrow.Font = New-Object System.Drawing.Font('Segoe UI Symbol', 18, [System.Drawing.FontStyle]::Bold)
    $arrow.ForeColor = [System.Drawing.Color]::FromArgb(112, 124, 228)
    $arrow.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $arrow.Location = New-Object System.Drawing.Point(238, 146)
    $arrow.Size = New-Object System.Drawing.Size(62, 34)
    [void]$alertForm.Controls.Add($arrow)

    $nextCard = New-Object System.Windows.Forms.Panel
    $nextCard.BackColor = [System.Drawing.Color]::FromArgb(21, 24, 38)
    $nextCard.Location = New-Object System.Drawing.Point(306, 126)
    $nextCard.Size = New-Object System.Drawing.Size(212, 76)
    [void]$alertForm.Controls.Add($nextCard)
    Set-RoundedControl -Control $nextCard -Radius 8
    $nextCard.Add_Paint({
        param($s, $e)
        $nextBorder = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(94, 106, 210), 1)
        $e.Graphics.DrawRectangle($nextBorder, 0, 0, ($s.Width - 1), ($s.Height - 1))
        $nextBorder.Dispose()
    })

    $nextCaption = New-Object System.Windows.Forms.Label
    $nextCaption.Text = 'SUA PROXIMA OS'
    $nextCaption.Font = New-Object System.Drawing.Font('Segoe UI', 7, [System.Drawing.FontStyle]::Bold)
    $nextCaption.ForeColor = [System.Drawing.Color]::FromArgb(112, 124, 228)
    $nextCaption.Location = New-Object System.Drawing.Point(14, 11)
    $nextCaption.Size = New-Object System.Drawing.Size(180, 16)
    [void]$nextCard.Controls.Add($nextCaption)

    $nextValue = New-Object System.Windows.Forms.Label
    $nextValue.Text = (Format-OsCodigo -Numero $ProximaOs)
    $nextValue.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 15, [System.Drawing.FontStyle]::Bold)
    $nextValue.ForeColor = [System.Drawing.Color]::FromArgb(240, 242, 248)
    $nextValue.Location = New-Object System.Drawing.Point(13, 32)
    $nextValue.Size = New-Object System.Drawing.Size(184, 30)
    [void]$nextCard.Controls.Add($nextValue)

    $message = New-Object System.Windows.Forms.Label
    $message.Text = 'Toda a interface foi atualizada automaticamente para evitar OS duplicada.'
    $message.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
    $message.ForeColor = [System.Drawing.Color]::FromArgb(166, 170, 184)
    $message.Location = New-Object System.Drawing.Point(22, 218)
    $message.Size = New-Object System.Drawing.Size(496, 20)
    [void]$alertForm.Controls.Add($message)

    $continue = New-Object System.Windows.Forms.Button
    $continue.Text = "Continuar com $(Format-OsCodigo -Numero $ProximaOs)"
    $continue.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9, [System.Drawing.FontStyle]::Bold)
    $continue.ForeColor = [System.Drawing.Color]::White
    $continue.BackColor = [System.Drawing.Color]::FromArgb(94, 106, 210)
    $continue.FlatStyle = 'Flat'
    $continue.FlatAppearance.BorderSize = 0
    $continue.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(112, 124, 228)
    $continue.Cursor = [System.Windows.Forms.Cursors]::Hand
    $continue.Location = New-Object System.Drawing.Point(306, 260)
    $continue.Size = New-Object System.Drawing.Size(212, 42)
    $continue.Add_Click({ $alertForm.Close() })
    [void]$alertForm.Controls.Add($continue)
    Set-RoundedControl -Control $continue -Radius 7
    $alertForm.AcceptButton = $continue
    $alertForm.Add_KeyDown({
        if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { $alertForm.Close() }
    })

    try {
        Set-CaijWindowsTypography -Root $alertForm
        [void]$alertForm.ShowDialog($owner)
    } finally {
        try { $alertForm.Dispose() } catch {}
        $script:osGlobalAlertOpen = $false
    }
}

function Show-NewOsAlert {
    param($Os, [int]$NovasCount = 1, [int]$ProximaOs = 0)
    if (-not $Os) { return }
    $numero = [int]$Os.numero
    if ($numero -lt 1) { return }
    if ($ProximaOs -lt 1) { $ProximaOs = $numero + 1 }
    $script:alertaOsAtual = $Os
    $tec = ([string]$Os.tecnico).Trim()
    if (-not $tec) { $tec = 'tecnico nao informado' }
    $hora = ''
    try {
        if ($Os.dataCadastro) { $hora = ([datetime]::Parse([string]$Os.dataCadastro)).ToString('HH:mm:ss') }
    } catch {}
    if (-not $hora) { $hora = (Get-Date).ToString('HH:mm:ss') }
    $extra = if ($NovasCount -gt 1) { " (+$($NovasCount - 1) novas)" } else { '' }
    if ($script:osAlertText) {
        $script:osAlertText.Text = "OS $(Format-OsCodigo -Numero $numero) adicionada por $tec as $hora$extra"
    }
    Hide-NewOsAlert
    Set-OsNumeroAtual -Numero $ProximaOs -Fonte 'concorrencia'
    Set-AppStatus -Texto "OS $(Format-OsCodigo -Numero $numero) criada em outra estacao | usando $(Format-OsCodigo -Numero $ProximaOs)" -Cor $cGreen
    Show-OsConcorrenciaPopup -Os $Os -ProximaOs $ProximaOs -NovasCount $NovasCount
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
        try {
            $resp = Invoke-CaijServer -Path '/status-os-local' -Method GET -TimeoutSec 4 -Retries 1
        } catch {
            $resp = Invoke-CaijServer -Path '/status-os' -Method GET -TimeoutSec 5 -Retries 1
        }
        $proximaDetectada = 0
        if ($resp -and [string]$resp.status -eq 'ok' -and $resp.ultimoConfirmado) {
            $maiorStatus = [int]$resp.ultimoConfirmado
            $anteriorConfirmado = [int]$script:ultimoConfirmadoServidor
            $script:ultimoConfirmadoServidor = $maiorStatus
            if ($resp.proximoDisponivel) { $proximaDetectada = [int]$resp.proximoDisponivel }
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
        if (-not $resp -or [string]$resp.status -ne 'ok' -or -not $resp.ordens) {
            if ($maiorStatus -gt [int]$script:maiorOsVistaAltertag -and $maiorStatus -gt [int]$script:ultimoAlertaOsNumero) {
                $script:maiorOsVistaAltertag = $maiorStatus
                Show-NewOsAlert -Os ([pscustomobject]@{ numero = $maiorStatus; tecnico = 'outra estacao' }) -ProximaOs $proximaDetectada
            }
            return
        }
        $ordens = @($resp.ordens | Where-Object { $_ -and $_.numero } | Sort-Object -Property numero -Descending)
        if (-not $ordens -or $ordens.Count -eq 0) { return }
        $maior = [int]$ordens[0].numero
        if ($maiorStatus -gt $maior -and $maiorStatus -gt [int]$script:maiorOsVistaAltertag -and $maiorStatus -gt [int]$script:ultimoAlertaOsNumero) {
            $script:maiorOsVistaAltertag = $maiorStatus
            Show-NewOsAlert -Os ([pscustomobject]@{ numero = $maiorStatus; tecnico = 'outra estacao' }) -ProximaOs $proximaDetectada
            return
        }
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
            Show-NewOsAlert -Os $ordens[0] -NovasCount $novas.Count -ProximaOs $proximaDetectada
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
$mainClientHeight = $botY + 34
$form.ClientSize = New-Object System.Drawing.Size($W, $mainClientHeight)
$form.MinimumSize = $form.Size
$script:mainLayoutWidth = $W
$script:mainLayoutHeight = $mainClientHeight
$script:mainLayoutSuspended = $false
$script:mainDpiScaleApplied = 1.0
$script:mainResponsiveScaleX = 1.0
$script:mainResponsiveScaleY = 1.0

# Guarda os controles principais para dimensionamento responsivo.
$script:mainLayoutControls = @(
    foreach ($control in @($form.Controls)) {
        [pscustomobject]@{
            Control = $control
            X = $control.Left
            Y = $control.Top
        }
    }
)
$form.Add_ClientSizeChanged({
    if ($script:mainLayoutSuspended) { return }

    $targetScaleX = [Math]::Max(1.0, ([double]$this.ClientSize.Width / [Math]::Max(1, $script:mainLayoutWidth)))
    $targetScaleY = [Math]::Max(1.0, ([double]$this.ClientSize.Height / [Math]::Max(1, $script:mainLayoutHeight)))
    $ratioX = $targetScaleX / [Math]::Max(0.01, $script:mainResponsiveScaleX)
    $ratioY = $targetScaleY / [Math]::Max(0.01, $script:mainResponsiveScaleY)
    if ([Math]::Abs($ratioX - 1.0) -lt 0.002 -and [Math]::Abs($ratioY - 1.0) -lt 0.002) { return }

    $script:mainLayoutSuspended = $true
    try {
        $this.SuspendLayout()
        $scaleFactor = New-Object System.Drawing.SizeF([float]$ratioX, [float]$ratioY)
        foreach ($item in $script:mainLayoutControls) {
            if (-not $item.Control.IsDisposed) { $item.Control.Scale($scaleFactor) }
        }
        $script:mainResponsiveScaleX = $targetScaleX
        $script:mainResponsiveScaleY = $targetScaleY

        $radiusScale = $script:mainDpiScaleApplied * [Math]::Min($targetScaleX, $targetScaleY)
        $regionQueue = New-Object System.Collections.Queue
        foreach ($item in $script:mainLayoutControls) { $regionQueue.Enqueue($item.Control) }
        while ($regionQueue.Count -gt 0) {
            $regionControl = [System.Windows.Forms.Control]$regionQueue.Dequeue()
            foreach ($child in $regionControl.Controls) { $regionQueue.Enqueue($child) }
            $radiusProperty = $regionControl.PSObject.Properties['CaijBaseCornerRadius']
            if ($radiusProperty) {
                $radius = [Math]::Max(1, [int][Math]::Round(([int]$radiusProperty.Value * $radiusScale)))
                Set-RoundedControl -Control $regionControl -Radius $radius
            }
        }
    } finally {
        $this.ResumeLayout($true)
        $script:mainLayoutSuspended = $false
    }
})

# F11 alterna tela cheia; Esc retorna ao modo de janela.
$script:mainFullscreen = $false
$script:mainRestoreBounds = $null
$script:mainRestoreWindowState = [System.Windows.Forms.FormWindowState]::Normal
$form.Add_KeyDown({
    param($sender, $eventArgs)

    $toggleFullscreen = ($eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::F11)
    $leaveFullscreen = ($eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::Escape -and $script:mainFullscreen)
    if (-not $toggleFullscreen -and -not $leaveFullscreen) { return }

    $eventArgs.SuppressKeyPress = $true
    if (-not $script:mainFullscreen) {
        $script:mainRestoreBounds = $sender.Bounds
        $script:mainRestoreWindowState = $sender.WindowState
        $sender.WindowState = [System.Windows.Forms.FormWindowState]::Normal
        $sender.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
        $sender.Bounds = [System.Windows.Forms.Screen]::FromControl($sender).Bounds
        $script:mainFullscreen = $true
    } else {
        $sender.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
        $sender.WindowState = [System.Windows.Forms.FormWindowState]::Normal
        if ($script:mainRestoreBounds) { $sender.Bounds = $script:mainRestoreBounds }
        $sender.WindowState = $script:mainRestoreWindowState
        $script:mainFullscreen = $false
    }
})

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
                $script:osRecentesTimer.Interval = 4000
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

Set-CaijWindowsTypography -Root $form
try { [CaijWindowTheme]::UseDarkTitleBar($form) } catch {}
$form.ShowDialog() | Out-Null
