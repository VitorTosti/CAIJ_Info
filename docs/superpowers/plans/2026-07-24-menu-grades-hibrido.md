# Menu de grades hibrido Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tornar o seletor de grades compacto e coerente com a interface escura, usando barras coloridas por grade e destaque da opcao atual.

**Architecture:** Um renderer WinForms isolado desenhara fundo, hover, borda, barra de cor e marcador de selecao sem alterar outros menus. O `ContextMenuStrip` existente continuara responsavel pelas mesmas opcoes e eventos, recebendo apenas dimensoes estaveis e sincronizacao visual da grade atual.

**Tech Stack:** Windows PowerShell 5.1, Windows Forms, C# embutido via `Add-Type`, testes PowerShell estaticos existentes.

## Global Constraints

- O menu deve permanecer escuro e alinhado ao estilo atual.
- A faixa branca lateral deve desaparecer.
- As sete opcoes e os valores enviados ao servidor nao podem mudar.
- As cores sao: A verde, B amarelo, C laranja, T azul/ciano e RMA vermelho.
- Hover e selecao nao podem alterar tamanho ou posicao dos itens.
- Nenhuma regra de OBS, impressao ou cadastro da OS pode ser alterada.

---

### Task 1: Criar o renderer visual isolado

**Files:**
- Modify: `CoreCAIJ/InfoNotebook.ps1:8-35`
- Modify: `CoreCAIJ/InfoNotebookPreview.Tests.ps1:18-30`

**Interfaces:**
- Consumes: `ToolStripItem.Tag` contendo `A`, `B`, `C - PINTURA N`, `T - TRIAGEM` ou `RMA`; `ToolStripMenuItem.Checked`.
- Produces: tipo .NET `CaijGradeMenuRenderer`, instanciavel com `New-Object CaijGradeMenuRenderer`.

- [ ] **Step 1: Escrever os testes estaticos do renderer**

Adicionar depois das assercoes atuais do seletor em `CoreCAIJ/InfoNotebookPreview.Tests.ps1`:

```powershell
Assert-True ($scriptText -match 'class\s+CaijGradeMenuRenderer') 'renderer exclusivo do menu de grades'
Assert-True ($scriptText -match "StartsWith\(`"C - PINTURA`"") 'renderer agrupa grades C'
Assert-True ($scriptText -match 'Color\.FromArgb\(66,\s*232,\s*176\)') 'renderer usa verde na grade A'
Assert-True ($scriptText -match 'Color\.FromArgb\(255,\s*208,\s*96\)') 'renderer usa amarelo na grade B'
Assert-True ($scriptText -match 'Color\.FromArgb\(255,\s*156,\s*98\)') 'renderer usa laranja nas grades C'
Assert-True ($scriptText -match 'Color\.FromArgb\(24,\s*185,\s*255\)') 'renderer usa ciano na grade T'
Assert-True ($scriptText -match 'Color\.FromArgb\(241,\s*95,\s*122\)') 'renderer usa vermelho no RMA'
```

- [ ] **Step 2: Executar o teste e confirmar a falha esperada**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File CoreCAIJ\InfoNotebookPreview.Tests.ps1
```

Expected: `FAIL: renderer exclusivo do menu de grades`.

- [ ] **Step 3: Implementar o renderer minimo**

Depois dos `Add-Type -AssemblyName` no inicio de `CoreCAIJ/InfoNotebook.ps1`, adicionar:

```powershell
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
                e.Graphics.FillEllipse(marker, 12, Math.Max(2, (bounds.Height - 5) / 2), 5, 5);
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
    Add-Type -TypeDefinition $gradeMenuRendererSource -ReferencedAssemblies @('System.Windows.Forms', 'System.Drawing')
}
```

- [ ] **Step 4: Executar o teste e validar o parser**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File CoreCAIJ\InfoNotebookPreview.Tests.ps1
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path 'CoreCAIJ\InfoNotebook.ps1'),
    [ref]$null,
    [ref]$parseErrors
) | Out-Null
if ($parseErrors) {
    $parseErrors | ForEach-Object { $_.Message }
    exit 1
}
'OK: parser'
```

Expected: `OK: InfoNotebookPreview tests` e `OK: parser`.

- [ ] **Step 5: Commitar o renderer**

```powershell
git add CoreCAIJ/InfoNotebook.ps1 CoreCAIJ/InfoNotebookPreview.Tests.ps1
git commit -m "feat: adiciona renderer do menu de grades"
```

---

### Task 2: Aplicar layout, selecao e validacao visual

**Files:**
- Modify: `CoreCAIJ/InfoNotebook.ps1:2425-2442`
- Modify: `CoreCAIJ/InfoNotebookPreview.Tests.ps1:18-36`

**Interfaces:**
- Consumes: `CaijGradeMenuRenderer`, `Get-CaijGradeOptions`, `Format-CaijGradeReference` e `$script:gradeCadastroOs`.
- Produces: `$gradeMenuOs` com largura minima de 178 px, itens de 176 x 30 px e `Checked` sincronizado ao abrir.

- [ ] **Step 1: Escrever os testes estaticos do menu**

Adicionar a `CoreCAIJ/InfoNotebookPreview.Tests.ps1`:

```powershell
Assert-True ($scriptText -match '\$gradeMenuOs\.ShowImageMargin\s*=\s*\$false') 'menu remove faixa branca de imagens'
Assert-True ($scriptText -match '\$gradeMenuOs\.ShowCheckMargin\s*=\s*\$false') 'menu remove margem nativa de marcacao'
Assert-True ($scriptText -match '\$gradeMenuOs\.Renderer\s*=\s*New-Object CaijGradeMenuRenderer') 'menu usa renderer hibrido'
Assert-True ($scriptText -match '\$gradeMenuOs\.MinimumSize\s*=\s*New-Object System\.Drawing\.Size\(178,\s*0\)') 'menu acompanha largura do card'
Assert-True ($scriptText -match '\$gradeItem\.Size\s*=\s*New-Object System\.Drawing\.Size\(176,\s*30\)') 'itens possuem dimensoes estaveis'
Assert-True ($scriptText -match '\$gradeMenuOs\.Add_Opening') 'menu sincroniza grade selecionada ao abrir'
Assert-True ($scriptText -match '\$item\.Checked\s*=\s*\(\[string\]\$item\.Tag -eq \[string\]\$script:gradeCadastroOs\)') 'marcador representa grade atual'
```

- [ ] **Step 2: Executar o teste e confirmar a falha esperada**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File CoreCAIJ\InfoNotebookPreview.Tests.ps1
```

Expected: `FAIL: menu remove faixa branca de imagens`.

- [ ] **Step 3: Configurar o menu e os itens**

Substituir a configuracao inicial de `$gradeMenuOs` por:

```powershell
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
```

Dentro do `foreach ($gradeOpcao in @(Get-CaijGradeOptions))`, depois de definir `Text` e `Tag`, adicionar:

```powershell
$gradeItem.AutoSize = $false
$gradeItem.Size = New-Object System.Drawing.Size(176, 30)
$gradeItem.Padding = New-Object System.Windows.Forms.Padding(18, 0, 6, 0)
$gradeItem.Margin = [System.Windows.Forms.Padding]::Empty
$gradeItem.CheckOnClick = $false
```

- [ ] **Step 4: Sincronizar a selecao ao abrir**

Depois do `foreach`, antes do evento de clique do botao, adicionar:

```powershell
$gradeMenuOs.Add_Opening({
    foreach ($item in @($gradeMenuOs.Items)) {
        $item.Checked = ([string]$item.Tag -eq [string]$script:gradeCadastroOs)
    }
})
```

Manter o evento atual de `$btnGradeOs.Add_Click` sem mudar o comportamento:

```powershell
$btnGradeOs.Add_Click({
    $gradeMenuOs.Show($btnGradeOs, (New-Object System.Drawing.Point(0, $btnGradeOs.Height)))
})
```

- [ ] **Step 5: Executar os testes focados**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File CoreCAIJ\InfoNotebookPreview.Tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File CoreCAIJ\GradeRules.Tests.ps1
```

Expected: ambos imprimem `OK`.

- [ ] **Step 6: Validar visualmente no Windows**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File CoreCAIJ\InfoNotebook.ps1
```

Na janela `Cadastrar OS Altertag`, abrir `REFERENCIA` e confirmar:

1. Nao existe faixa branca lateral.
2. O menu tem largura visual alinhada ao card.
3. As sete opcoes cabem sem corte.
4. A, B, C, T e RMA usam as cores especificadas.
5. Hover nao desloca nem redimensiona itens.
6. A grade atual aparece marcada ao reabrir o menu.
7. Selecionar cada grade continua atualizando o resumo.

Fechar o aplicativo depois da verificacao.

- [ ] **Step 7: Executar a regressao completa**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File CoreCAIJ\TestarAltertag.Tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File CoreCAIJ\GradeRules.Tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File CoreCAIJ\InfoNotebookPreview.Tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File CoreCAIJ\InfoNotebookMac.Tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File CoreCAIJ\MacUi.Tests.ps1
git diff --check
```

Expected: todos os testes imprimem `OK` e `git diff --check` nao apresenta erros.

- [ ] **Step 8: Commitar o menu final**

```powershell
git add CoreCAIJ/InfoNotebook.ps1 CoreCAIJ/InfoNotebookPreview.Tests.ps1
git commit -m "feat: melhora visual do seletor de grades"
```
