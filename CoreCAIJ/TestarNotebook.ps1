[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Speech

if (-not ('CaijTestsDpiAwareness' -as [type])) {
    $testsDpiSource = @'
using System;
using System.Runtime.InteropServices;

public static class CaijTestsDpiAwareness
{
    [DllImport("user32.dll")]
    private static extern bool SetProcessDpiAwarenessContext(IntPtr value);

    [DllImport("shcore.dll")]
    private static extern int SetProcessDpiAwareness(int value);

    [DllImport("user32.dll")]
    private static extern bool SetProcessDPIAware();

    public static void Enable()
    {
        try { if (SetProcessDpiAwarenessContext(new IntPtr(-4))) return; } catch { }
        try { if (SetProcessDpiAwareness(2) == 0) return; } catch { }
        try { SetProcessDPIAware(); } catch { }
    }
}
'@
    Add-Type -TypeDefinition $testsDpiSource -WarningAction SilentlyContinue
}

try { [CaijTestsDpiAwareness]::Enable() } catch {}

$NL = [Environment]::NewLine

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

function New-TestsFont {
    param(
        [ValidateSet('UI','Display')][string]$Kind = 'UI',
        [float]$Size = 9,
        [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular
    )

    $fontName = if ($Kind -eq 'Display') {
        'Segoe UI Variable Display'
    } elseif ($Size -le 8) {
        'Segoe UI Variable Small'
    } else {
        'Segoe UI Variable Text'
    }
    try {
        $font = New-Object System.Drawing.Font($fontName, $Size, $Style, [System.Drawing.GraphicsUnit]::Point)
        if ($font.Name -eq $fontName) { return $font }
        $font.Dispose()
    } catch {}

    $fallback = if ($Kind -eq 'Display') { 'Segoe UI Semibold' } else { 'Segoe UI' }
    return New-Object System.Drawing.Font($fallback, $Size, $Style, [System.Drawing.GraphicsUnit]::Point)
}

function Set-TestsTypography {
    param([System.Windows.Forms.Control]$Root)
    if (-not $Root) { return }

    $queue = New-Object System.Collections.Queue
    $queue.Enqueue($Root)
    while ($queue.Count -gt 0) {
        $control = [System.Windows.Forms.Control]$queue.Dequeue()
        foreach ($child in $control.Controls) { $queue.Enqueue($child) }
        if (-not $control.Font -or $control.Font.Name -match 'Symbol') { continue }

        $kind = if ($control.Font.Bold -and $control.Font.Size -ge 11) { 'Display' } else { 'UI' }
        try {
            $control.Font = New-TestsFont -Kind $kind -Size ([float]$control.Font.Size) -Style $control.Font.Style
            if ($control -is [System.Windows.Forms.Label] -or $control -is [System.Windows.Forms.Button]) {
                $control.UseCompatibleTextRendering = $false
            }
        } catch {}
    }
}

$cBg       = [System.Drawing.Color]::FromArgb(7, 9, 17)
$cSurface  = [System.Drawing.Color]::FromArgb(15, 18, 29)
$cCard     = [System.Drawing.Color]::FromArgb(21, 24, 38)
$cCard2    = [System.Drawing.Color]::FromArgb(15, 18, 29)
$cBorder   = [System.Drawing.Color]::FromArgb(42, 46, 63)
$cAccent   = [System.Drawing.Color]::FromArgb(94, 106, 210)
$cAccentHi = [System.Drawing.Color]::FromArgb(112, 124, 228)
$cMain     = [System.Drawing.Color]::FromArgb(240, 242, 248)
$cMuted    = [System.Drawing.Color]::FromArgb(166, 170, 184)
$cSubtle   = [System.Drawing.Color]::FromArgb(112, 117, 133)
$cOk       = [System.Drawing.Color]::FromArgb(46, 204, 113)
$cErr      = [System.Drawing.Color]::FromArgb(244, 63, 94)
$cWarn     = [System.Drawing.Color]::FromArgb(245, 158, 11)

$form = New-Object System.Windows.Forms.Form
$form.Text = 'CAIJ | Central de Testes'
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'None'
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.ShowInTaskbar = $true
$form.BackColor = $cBg
$form.ForeColor = $cMain
$form.ClientSize = New-Object System.Drawing.Size(980, 550)
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
Set-RoundedControl -Control $form -Radius 12
$form.Add_SizeChanged({ Set-RoundedControl -Control $this -Radius 12 })
$form.Add_Paint({
    param($s, $e)
    $windowBorder = New-Object System.Drawing.Pen($cBorder, 1)
    $e.Graphics.DrawRectangle($windowBorder, 0, 0, ($s.ClientSize.Width - 1), ($s.ClientSize.Height - 1))
    $windowBorder.Dispose()
})

$head = New-Object System.Windows.Forms.Panel
$head.Location = New-Object System.Drawing.Point(0, 0)
$head.Size = New-Object System.Drawing.Size(980, 88)
$head.BackColor = $cSurface
$form.Controls.Add($head)
$head.Add_Paint({
    param($s, $e)
    $headerLine = New-Object System.Drawing.Pen($cBorder, 1)
    $e.Graphics.DrawLine($headerLine, 0, ($s.Height - 1), $s.Width, ($s.Height - 1))
    $headerLine.Dispose()
})

$eyebrow = New-Object System.Windows.Forms.Label
$eyebrow.Text = 'DIAGNOSTICO  /  VALIDACAO TECNICA'
$eyebrow.Font = New-Object System.Drawing.Font('Segoe UI', 7, [System.Drawing.FontStyle]::Bold)
$eyebrow.ForeColor = $cAccentHi
$eyebrow.Location = New-Object System.Drawing.Point(24, 10)
$eyebrow.Size = New-Object System.Drawing.Size(340, 16)
$head.Controls.Add($eyebrow)

$title = New-Object System.Windows.Forms.Label
$title.Text = 'Central de testes'
$title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 17, [System.Drawing.FontStyle]::Bold)
$title.ForeColor = $cMain
$title.Location = New-Object System.Drawing.Point(22, 28)
$title.Size = New-Object System.Drawing.Size(420, 32)
$head.Controls.Add($title)

$sub = New-Object System.Windows.Forms.Label
$sub.Text = 'Fluxo completo de validacao tecnica para notebooks'
$sub.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$sub.ForeColor = $cMuted
$sub.Location = New-Object System.Drawing.Point(24, 61)
$sub.Size = New-Object System.Drawing.Size(440, 22)
$head.Controls.Add($sub)

$chip = New-Object System.Windows.Forms.Panel
$chip.Location = New-Object System.Drawing.Point(748, 18)
$chip.Size = New-Object System.Drawing.Size(184, 52)
$chip.BackColor = $cCard
$head.Controls.Add($chip)
Set-RoundedControl -Control $chip -Radius 8
$chip.Add_Paint({
    param($s, $e)
    $chipBorder = New-Object System.Drawing.Pen($cBorder, 1)
    $e.Graphics.DrawRectangle($chipBorder, 0, 0, ($s.Width - 1), ($s.Height - 1))
    $chipBorder.Dispose()
})

$chipLbl = New-Object System.Windows.Forms.Label
$chipLbl.Text = 'STATUS GERAL'
$chipLbl.Font = New-Object System.Drawing.Font('Segoe UI', 7, [System.Drawing.FontStyle]::Bold)
$chipLbl.ForeColor = $cSubtle
$chipLbl.Location = New-Object System.Drawing.Point(12, 7)
$chipLbl.Size = New-Object System.Drawing.Size(120, 14)
$chip.Controls.Add($chipLbl)

$chipVal = New-Object System.Windows.Forms.Label
$chipVal.Text = 'PENDENTE'
$chipVal.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 13, [System.Drawing.FontStyle]::Bold)
$chipVal.ForeColor = $cWarn
$chipVal.Location = New-Object System.Drawing.Point(12, 23)
$chipVal.Size = New-Object System.Drawing.Size(170, 22)
$chip.Controls.Add($chipVal)

$close = New-Object System.Windows.Forms.Button
$close.Text = 'X'
$close.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
$close.ForeColor = $cMuted
$close.BackColor = $head.BackColor
$close.FlatStyle = 'Flat'
$close.FlatAppearance.BorderSize = 0
$close.FlatAppearance.MouseOverBackColor = $cCard
$close.Location = New-Object System.Drawing.Point(940, 8)
$close.Size = New-Object System.Drawing.Size(30, 30)
$close.Cursor = [System.Windows.Forms.Cursors]::Hand
$close.Add_Click({ $form.Close() })
$head.Controls.Add($close)

$dragState = @{ Active = $false; Mouse = [System.Drawing.Point]::Empty; Form = [System.Drawing.Point]::Empty }
$head.Add_MouseDown({
    if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $dragState.Active = $true
        $dragState.Mouse = [System.Windows.Forms.Cursor]::Position
        $dragState.Form = $form.Location
    }
})
$head.Add_MouseMove({
    if ($dragState.Active) {
        $mouseNow = [System.Windows.Forms.Cursor]::Position
        $form.Location = New-Object System.Drawing.Point(
            ($dragState.Form.X + $mouseNow.X - $dragState.Mouse.X),
            ($dragState.Form.Y + $mouseNow.Y - $dragState.Mouse.Y)
        )
    }
})
$head.Add_MouseUp({ $dragState.Active = $false })

$summary = New-Object System.Windows.Forms.Panel
$summary.Location = New-Object System.Drawing.Point(20, 104)
$summary.Size = New-Object System.Drawing.Size(940, 80)
$summary.BackColor = $cCard2
$form.Controls.Add($summary)
Set-RoundedControl -Control $summary -Radius 8
$summary.Add_Paint({
    param($s, $e)
    $summaryBorder = New-Object System.Drawing.Pen($cBorder, 1)
    $e.Graphics.DrawRectangle($summaryBorder, 0, 0, ($s.Width - 1), ($s.Height - 1))
    $summaryBorder.Dispose()
})

$sumPass = New-Object System.Windows.Forms.Label
$sumPass.Text = 'Passou: 0'
$sumPass.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 11, [System.Drawing.FontStyle]::Bold)
$sumPass.ForeColor = $cOk
$sumPass.Location = New-Object System.Drawing.Point(20, 12)
$sumPass.Size = New-Object System.Drawing.Size(170, 24)
$summary.Controls.Add($sumPass)

$sumFail = New-Object System.Windows.Forms.Label
$sumFail.Text = 'Falhou: 0'
$sumFail.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 11, [System.Drawing.FontStyle]::Bold)
$sumFail.ForeColor = $cErr
$sumFail.Location = New-Object System.Drawing.Point(200, 12)
$sumFail.Size = New-Object System.Drawing.Size(170, 24)
$summary.Controls.Add($sumFail)

$sumPend = New-Object System.Windows.Forms.Label
$sumPend.Text = 'Pendente: 0'
$sumPend.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 11, [System.Drawing.FontStyle]::Bold)
$sumPend.ForeColor = $cWarn
$sumPend.Location = New-Object System.Drawing.Point(380, 12)
$sumPend.Size = New-Object System.Drawing.Size(170, 24)
$summary.Controls.Add($sumPend)

$sumText = New-Object System.Windows.Forms.Label
$sumText.Text = 'Marque cada etapa apos validar fisicamente o item.'
$sumText.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$sumText.ForeColor = $cMuted
$sumText.Location = New-Object System.Drawing.Point(560, 14)
$sumText.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$sumText.Size = New-Object System.Drawing.Size(360, 18)
$summary.Controls.Add($sumText)

$progressTrack = New-Object System.Windows.Forms.Panel
$progressTrack.Location = New-Object System.Drawing.Point(20, 54)
$progressTrack.Size = New-Object System.Drawing.Size(900, 12)
$progressTrack.BackColor = $cCard
$summary.Controls.Add($progressTrack)
Set-RoundedControl -Control $progressTrack -Radius 6

$progressFill = New-Object System.Windows.Forms.Panel
$progressFill.Location = New-Object System.Drawing.Point(0, 0)
$progressFill.Size = New-Object System.Drawing.Size(0, 12)
$progressFill.BackColor = $cAccent
$progressTrack.Controls.Add($progressFill)
Set-RoundedControl -Control $progressFill -Radius 6

$listPanel = New-Object System.Windows.Forms.Panel
$listPanel.Location = New-Object System.Drawing.Point(20, 196)
$listPanel.Size = New-Object System.Drawing.Size(940, 268)
$listPanel.BackColor = $cBg
$form.Controls.Add($listPanel)

$script:linhas = @()

function New-ActionButton {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$W,
        [int]$H,
        [System.Drawing.Color]$Bg,
        [System.Drawing.Color]$Fg,
        [scriptblock]$OnClick
    )
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.Location = New-Object System.Drawing.Point($X, $Y)
    $b.Size = New-Object System.Drawing.Size($W, $H)
    $b.BackColor = $Bg
    $b.ForeColor = $Fg
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 1
    $b.FlatAppearance.BorderColor = $cBorder
    $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(
        [int][math]::Min($Bg.R + 16, 255),
        [int][math]::Min($Bg.G + 16, 255),
        [int][math]::Min($Bg.B + 16, 255)
    )
    $b.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(
        [int][math]::Max($Bg.R - 8, 0),
        [int][math]::Max($Bg.G - 8, 0),
        [int][math]::Max($Bg.B - 8, 0)
    )
    $b.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5)
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    Set-RoundedControl -Control $b -Radius 8
    if ($OnClick) { $b.Add_Click($OnClick) }
    return $b
}

function New-TestRow {
    param(
        [int]$Y,
        [string]$Numero,
        [string]$Titulo,
        [string]$Instrucao,
        [scriptblock]$AbrirAcao
    )
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = New-Object System.Drawing.Point(0, $Y)
    $panel.Size = New-Object System.Drawing.Size(940, 64)
    $panel.BackColor = $cCard
    $listPanel.Controls.Add($panel)
    Set-RoundedControl -Control $panel -Radius 8
    $panel.Add_Paint({
        param($s, $e)
        $rowBorder = New-Object System.Drawing.Pen($cBorder, 1)
        $e.Graphics.DrawRectangle($rowBorder, 0, 0, ($s.Width - 1), ($s.Height - 1))
        $rowBorder.Dispose()
    })

    $num = New-Object System.Windows.Forms.Label
    $num.Text = $Numero
    $num.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 13, [System.Drawing.FontStyle]::Bold)
    $num.ForeColor = $cAccentHi
    $num.Location = New-Object System.Drawing.Point(16, 17)
    $num.Size = New-Object System.Drawing.Size(34, 28)
    $panel.Controls.Add($num)

    $ttl = New-Object System.Windows.Forms.Label
    $ttl.Text = $Titulo
    $ttl.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 11, [System.Drawing.FontStyle]::Bold)
    $ttl.ForeColor = $cMain
    $ttl.Location = New-Object System.Drawing.Point(58, 9)
    $ttl.Size = New-Object System.Drawing.Size(250, 24)
    $panel.Controls.Add($ttl)

    $ins = New-Object System.Windows.Forms.Label
    $ins.Text = $Instrucao
    $ins.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
    $ins.ForeColor = $cMuted
    $ins.Location = New-Object System.Drawing.Point(58, 33)
    $ins.Size = New-Object System.Drawing.Size(360, 22)
    $panel.Controls.Add($ins)

    $status = New-Object System.Windows.Forms.Label
    $status.Text = 'PENDENTE'
    $status.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9, [System.Drawing.FontStyle]::Bold)
    $status.ForeColor = $cWarn
    $status.Location = New-Object System.Drawing.Point(422, 22)
    $status.Size = New-Object System.Drawing.Size(95, 20)
    $panel.Controls.Add($status)

    $btnAbrir = New-ActionButton -Text 'Abrir teste' -X 532 -Y 14 -W 116 -H 36 `
        -Bg $cAccent -Fg ([System.Drawing.Color]::White) -OnClick $AbrirAcao
    $panel.Controls.Add($btnAbrir)

    $btnOK = New-ActionButton -Text 'Passou' -X 656 -Y 14 -W 82 -H 36 `
        -Bg ([System.Drawing.Color]::FromArgb(18, 55, 39)) -Fg ([System.Drawing.Color]::FromArgb(174, 239, 204)) -OnClick $null
    $panel.Controls.Add($btnOK)

    $btnFail = New-ActionButton -Text 'Falhou' -X 746 -Y 14 -W 82 -H 36 `
        -Bg ([System.Drawing.Color]::FromArgb(57, 24, 34)) -Fg ([System.Drawing.Color]::FromArgb(255, 196, 207)) -OnClick $null
    $panel.Controls.Add($btnFail)

    $btnReset = New-ActionButton -Text 'Limpar' -X 836 -Y 14 -W 84 -H 36 `
        -Bg $cCard2 -Fg $cMuted -OnClick $null
    $panel.Controls.Add($btnReset)

    $row = [ordered]@{
        Panel = $panel; Titulo = $Titulo; Status = 'pendente'; Label = $status
        BtnOK = $btnOK; BtnFail = $btnFail; BtnReset = $btnReset; BtnAbrir = $btnAbrir; TitleLabel = $ttl
    }

    $btnOK.Add_Click({
        $row.Status = 'ok'
        $row.Panel.BackColor = [System.Drawing.Color]::FromArgb(15, 37, 29)
        $row.TitleLabel.ForeColor = $cOk
        $row.Label.Text = 'APROVADO'
        $row.Label.ForeColor = $cOk
        Update-Resumo
    }.GetNewClosure())

    $btnFail.Add_Click({
        $row.Status = 'fail'
        $row.Panel.BackColor = [System.Drawing.Color]::FromArgb(39, 20, 29)
        $row.TitleLabel.ForeColor = $cErr
        $row.Label.Text = 'REPROVADO'
        $row.Label.ForeColor = $cErr
        Update-Resumo
    }.GetNewClosure())

    $btnReset.Add_Click({
        $row.Status = 'pendente'
        $row.Panel.BackColor = $cCard
        $row.TitleLabel.ForeColor = $cMain
        $row.Label.Text = 'PENDENTE'
        $row.Label.ForeColor = $cWarn
        Update-Resumo
    }.GetNewClosure())

    return $row
}

$script:linhas += New-TestRow -Y 0   -Numero '01' -Titulo 'Camera' -Instrucao 'Validar imagem, foco e captura' -AbrirAcao { Start-Process 'microsoft.windows.camera:' }
$script:linhas += New-TestRow -Y 68  -Numero '02' -Titulo 'Teclado' -Instrucao 'Pressionar todas as teclas' -AbrirAcao { Start-Process 'msedge.exe' -ArgumentList '-inprivate https://keyboard-test.space/pt/' }
$script:linhas += New-TestRow -Y 136 -Numero '03' -Titulo 'Som e Microfone' -Instrucao 'Ouvir teste e validar entrada de voz' -AbrirAcao {
    Start-Process 'ms-settings:sound'
    $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
    $synth.Volume = 100
    $synth.SpeakAsync('teste') | Out-Null
}
$script:linhas += New-TestRow -Y 204 -Numero '04' -Titulo 'Tela / Dead Pixel' -Instrucao 'Inspecionar cores, brilho e pixel' -AbrirAcao { Start-Process 'msedge.exe' -ArgumentList '-inprivate https://lcdtech.info/en/tests/dead.pixel.htm' }

function Update-Resumo {
    $ok = ($script:linhas | Where-Object { $_.Status -eq 'ok' }).Count
    $fail = ($script:linhas | Where-Object { $_.Status -eq 'fail' }).Count
    $total = $script:linhas.Count
    $pend = $total - $ok - $fail

    $sumPass.Text = "Passou: $ok"
    $sumFail.Text = "Falhou: $fail"
    $sumPend.Text = "Pendente: $pend"

    $done = $ok + $fail
    $pct = if ($total -gt 0) { [int](($done * 100) / $total) } else { 0 }
    $fillW = [int](($progressTrack.Width * $pct) / 100)
    $progressFill.Width = $fillW
    $progressFill.BackColor = if ($fail -gt 0) { $cWarn } elseif ($ok -eq $total) { $cOk } else { $cAccent }

    if ($fail -gt 0) {
        $chipVal.Text = 'ATENCAO'
        $chipVal.ForeColor = $cWarn
    } elseif ($ok -eq $total) {
        $chipVal.Text = 'APROVADO'
        $chipVal.ForeColor = $cOk
    } else {
        $chipVal.Text = 'PENDENTE'
        $chipVal.ForeColor = $cWarn
    }
}

$footerLine = New-Object System.Windows.Forms.Panel
$footerLine.Location = New-Object System.Drawing.Point(20, 484)
$footerLine.Size = New-Object System.Drawing.Size(940, 1)
$footerLine.BackColor = $cBorder
$form.Controls.Add($footerLine)

$btnOpenAll = New-ActionButton -Text 'Abrir todos os testes' -X 20 -Y 500 -W 154 -H 38 `
    -Bg $cAccent -Fg ([System.Drawing.Color]::White) -OnClick {
        Start-Process 'microsoft.windows.camera:'
        Start-Sleep -Milliseconds 250
        Start-Process 'msedge.exe' -ArgumentList '-inprivate https://keyboard-test.space/pt/'
        Start-Sleep -Milliseconds 250
        Start-Process 'ms-settings:sound'
        $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
        $synth.Volume = 100
        $synth.SpeakAsync('teste') | Out-Null
        Start-Sleep -Milliseconds 250
        Start-Process 'msedge.exe' -ArgumentList '-inprivate https://lcdtech.info/en/tests/dead.pixel.htm'
    }
$form.Controls.Add($btnOpenAll)

$btnCopy = New-ActionButton -Text 'Copiar relatorio' -X 182 -Y 500 -W 144 -H 38 `
    -Bg $cCard -Fg $cMain -OnClick {
        $txt = "CAIJ | CENTRAL DE TESTES$NL"
        $txt += "==========================$NL"
        foreach ($l in $script:linhas) {
            $st = switch ($l.Status) { 'ok' { 'PASSOU' } 'fail' { 'FALHOU' } default { 'PENDENTE' } }
            $txt += "- $($l.Titulo): $st$NL"
        }
        $txt += "==========================$NL"
        $txt += "$($sumPass.Text) | $($sumFail.Text) | $($sumPend.Text)"
        [System.Windows.Forms.Clipboard]::SetText($txt)
        $btnCopy.Text = 'Copiado!'
        Start-Sleep -Milliseconds 900
        $btnCopy.Text = 'Copiar relatorio'
    }
$form.Controls.Add($btnCopy)

$btnResetAll = New-ActionButton -Text 'Limpar marcacoes' -X 334 -Y 500 -W 150 -H 38 `
    -Bg $cCard -Fg $cMuted -OnClick {
        foreach ($l in $script:linhas) {
            $l.Status = 'pendente'
            $l.Panel.BackColor = $cCard
            $l.TitleLabel.ForeColor = $cMain
            $l.Label.Text = 'PENDENTE'
            $l.Label.ForeColor = $cWarn
        }
        Update-Resumo
    }
$form.Controls.Add($btnResetAll)

$btnClose = New-ActionButton -Text 'Fechar' -X 844 -Y 500 -W 116 -H 38 `
    -Bg $cCard -Fg $cMuted -OnClick { $form.Close() }
$form.Controls.Add($btnClose)

function Set-TestsResponsiveLayout {
    param([System.Windows.Forms.Form]$Form)

    # O layout foi desenhado em 980 x 550. Amplia tudo de forma uniforme para
    # ocupar a maior parte do monitor atual, sem distorcer nem sair da area util.
    $baseWidth = 980.0
    $baseHeight = 550.0
    $workingArea = [System.Windows.Forms.Screen]::FromPoint(
        [System.Windows.Forms.Cursor]::Position
    ).WorkingArea
    $targetWidth = [Math]::Max(1.0, $workingArea.Width * 0.84)
    $targetHeight = [Math]::Max(1.0, $workingArea.Height * 0.84)
    $layoutScale = [Math]::Min($targetWidth / $baseWidth, $targetHeight / $baseHeight)
    $layoutScale = [Math]::Max(0.75, $layoutScale)

    if ([Math]::Abs($layoutScale - 1.0) -gt 0.01) {
        $Form.SuspendLayout()
        try {
            # Control.Scale ja amplia limites e fontes. Alterar Font manualmente
            # aqui aplicaria a escala duas vezes e cortaria textos e numeros.
            $Form.Scale((New-Object System.Drawing.SizeF([float]$layoutScale, [float]$layoutScale)))
            $Form.ClientSize = New-Object System.Drawing.Size(
                [int][Math]::Round($baseWidth * $layoutScale),
                [int][Math]::Round($baseHeight * $layoutScale)
            )
        } finally {
            $Form.ResumeLayout($true)
        }
    }

    # Reconstroi os recortes arredondados depois da escala.
    Set-RoundedControl -Control $Form -Radius ([Math]::Max(8, [int][Math]::Round(12 * $layoutScale)))
    Set-RoundedControl -Control $chip -Radius ([Math]::Max(6, [int][Math]::Round(8 * $layoutScale)))
    Set-RoundedControl -Control $summary -Radius ([Math]::Max(6, [int][Math]::Round(8 * $layoutScale)))
    Set-RoundedControl -Control $progressTrack -Radius ([Math]::Max(4, [int][Math]::Round(6 * $layoutScale)))
    foreach ($row in $script:linhas) {
        Set-RoundedControl -Control $row.Panel -Radius ([Math]::Max(6, [int][Math]::Round(8 * $layoutScale)))
        foreach ($button in @($row.BtnAbrir, $row.BtnOK, $row.BtnFail, $row.BtnReset)) {
            Set-RoundedControl -Control $button -Radius ([Math]::Max(6, [int][Math]::Round(8 * $layoutScale)))
        }
    }
    foreach ($button in @($btnOpenAll, $btnCopy, $btnResetAll, $btnClose)) {
        Set-RoundedControl -Control $button -Radius ([Math]::Max(6, [int][Math]::Round(8 * $layoutScale)))
    }

    $Form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $Form.Location = New-Object System.Drawing.Point(
        ($workingArea.Left + [int](($workingArea.Width - $Form.Width) / 2)),
        ($workingArea.Top + [int](($workingArea.Height - $Form.Height) / 2))
    )
}

Update-Resumo
Set-TestsTypography -Root $form
Set-TestsResponsiveLayout -Form $form
$form.ShowDialog() | Out-Null
