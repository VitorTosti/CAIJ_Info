# Seletor de grades e ajustes da triagem Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adicionar um menu completo de grades ao cadastro da OS, incluir Erick no card de tecnicos, liberar Grade T sem observacoes e imprimir `T - TRIAGEM` sem corte.

**Architecture:** As regras de grade ficarao em uma biblioteca PowerShell pequena e testavel, carregada pelo `InfoNotebook.ps1`. A janela de cadastro usara essas regras para montar um menu de selecao direta; a previa e o servidor de impressao compartilharao a mesma decisao funcional, mantendo a geometria atual.

**Tech Stack:** Windows PowerShell 5.1, Windows Forms, TSPL, testes PowerShell existentes.

## Global Constraints

- O menu deve oferecer A, B, C - Pintura 1/2/3, T - Triagem e RMA.
- O cadastro da OS deve continuar enviando `GRADE T - TRIAGEM` como referencia.
- Grade T nao exige observacoes.
- Grade B e todas as variacoes de Grade C continuam exigindo observacoes.
- O selo da previa e da etiqueta deve mostrar `T - TRIAGEM`.
- As demais grades e a geometria aprovada da etiqueta nao devem mudar.

---

### Task 1: Centralizar e testar as regras de grade

**Files:**
- Create: `CoreCAIJ/GradeRules.ps1`
- Create: `CoreCAIJ/GradeRules.Tests.ps1`
- Modify: `CoreCAIJ/InfoNotebook.ps1:1`

**Interfaces:**
- Consumes: grade interna como `A`, `C - PINTURA 2`, `T - TRIAGEM` ou `RMA`.
- Produces: `Get-CaijGradeOptions`, `Format-CaijGradeReference` e `Test-CaijGradeRequiresObs`.

- [ ] **Step 1: Escrever o teste que define opcoes, referencia e obrigatoriedade**

Criar `CoreCAIJ/GradeRules.Tests.ps1`:

```powershell
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'GradeRules.ps1')

function Assert-Equal {
    param($Actual, $Expected, [string]$Name)
    if ($Actual -ne $Expected) {
        throw "FAIL: $Name | esperado=[$Expected] atual=[$Actual]"
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Name)
    if (-not $Condition) { throw "FAIL: $Name" }
}

$options = @(Get-CaijGradeOptions)
Assert-Equal ($options -join '|') 'A|B|C - PINTURA 1|C - PINTURA 2|C - PINTURA 3|T - TRIAGEM|RMA' 'opcoes de grade'
Assert-Equal (Format-CaijGradeReference 'A') 'GRADE A' 'referencia A'
Assert-Equal (Format-CaijGradeReference 'C - PINTURA 2') 'GRADE C - PINTURA 2' 'referencia pintura'
Assert-Equal (Format-CaijGradeReference 'T - TRIAGEM') 'GRADE T - TRIAGEM' 'referencia triagem'
Assert-Equal (Format-CaijGradeReference 'RMA') 'RMA' 'referencia RMA'
Assert-True (Test-CaijGradeRequiresObs 'B') 'B exige observacao'
Assert-True (Test-CaijGradeRequiresObs 'C - PINTURA 1') 'C exige observacao'
Assert-True (-not (Test-CaijGradeRequiresObs 'T - TRIAGEM')) 'T nao exige observacao'
Assert-True (-not (Test-CaijGradeRequiresObs 'A')) 'A nao exige observacao'

'OK: GradeRules tests'
```

- [ ] **Step 2: Executar o teste e confirmar a falha esperada**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File CoreCAIJ\GradeRules.Tests.ps1
```

Expected: falha porque `CoreCAIJ/GradeRules.ps1` ainda nao existe.

- [ ] **Step 3: Implementar a biblioteca minima**

Criar `CoreCAIJ/GradeRules.ps1`:

```powershell
function Get-CaijGradeOptions {
    @(
        'A'
        'B'
        'C - PINTURA 1'
        'C - PINTURA 2'
        'C - PINTURA 3'
        'T - TRIAGEM'
        'RMA'
    )
}

function Format-CaijGradeReference {
    param([string]$Grade)

    $normalized = ([string]$Grade).Trim().ToUpper()
    if ($normalized -eq 'RMA') { return 'RMA' }
    if ($normalized -match '^C\s*-\s*PINTURA\s*([123])$') {
        return "GRADE C - PINTURA $($matches[1])"
    }
    if ($normalized -match '^T\s*-\s*TRIAGEM$') {
        return 'GRADE T - TRIAGEM'
    }
    if ($normalized -in @('A', 'B')) {
        return "GRADE $normalized"
    }
    return 'GRADE A'
}

function Test-CaijGradeRequiresObs {
    param([string]$Grade)

    $normalized = ([string]$Grade).Trim().ToUpper()
    return ($normalized -eq 'B' -or $normalized -match '^C\s*-\s*PINTURA\s*[123]$')
}
```

No inicio de `CoreCAIJ/InfoNotebook.ps1`, depois dos parametros, carregar:

```powershell
. (Join-Path $PSScriptRoot 'GradeRules.ps1')
```

- [ ] **Step 4: Executar o teste e o parser**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File CoreCAIJ\GradeRules.Tests.ps1
powershell -NoProfile -Command "$errors=$null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'CoreCAIJ\InfoNotebook.ps1'),[ref]$null,[ref]$errors) | Out-Null; if($errors){$errors | ForEach-Object {$_.Message}; exit 1}; 'OK: parser'"
```

Expected: `OK: GradeRules tests` e `OK: parser`.

- [ ] **Step 5: Commitar as regras**

```powershell
git add CoreCAIJ/GradeRules.ps1 CoreCAIJ/GradeRules.Tests.ps1 CoreCAIJ/InfoNotebook.ps1
git commit -m "refactor: centraliza regras de grade"
```

### Task 2: Adicionar Erick e o menu completo ao cadastro da OS

**Files:**
- Modify: `CoreCAIJ/InfoNotebook.ps1:2296`
- Modify: `CoreCAIJ/InfoNotebook.ps1:2391`
- Modify: `CoreCAIJ/InfoNotebook.ps1:3418`
- Modify: `CoreCAIJ/InfoNotebookPreview.Tests.ps1:17`

**Interfaces:**
- Consumes: `Get-CaijGradeOptions` e `Format-CaijGradeReference` da Task 1.
- Produces: `$btnGradeOs` com menu de selecao direta e `$cmbTec.SelectedItem` aceitando `Erick`.

- [ ] **Step 1: Escrever testes estaticos da interface**

Adicionar a `CoreCAIJ/InfoNotebookPreview.Tests.ps1`:

```powershell
Assert-True ($scriptText -match "\$tecNomes\s*=\s*@\('Lucas',\s*'Hyrides',\s*'Vitor',\s*'Erick'\)") 'cadastro mostra tecnico Erick'
Assert-True ($scriptText -match 'Get-CaijGradeOptions') 'cadastro usa todas as grades'
Assert-True ($scriptText -match 'ContextMenuStrip') 'cadastro abre menu de grades'
Assert-True ($scriptText -match '\$btnGradeOs') 'referencia usa botao de grade'
Assert-True ($scriptText -notmatch '\$txtGradeOs\s*=\s*New-Object System\.Windows\.Forms\.TextBox') 'referencia nao usa texto livre'
```

- [ ] **Step 2: Executar o teste e confirmar a falha esperada**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File CoreCAIJ\InfoNotebookPreview.Tests.ps1
```

Expected: `FAIL: cadastro mostra tecnico Erick`.

- [ ] **Step 3: Redistribuir os quatro tecnicos**

Em `Show-CadastroOsAltertagDraft`, substituir a lista e dimensoes dos botoes:

```powershell
$tecNomes = @('Lucas', 'Hyrides', 'Vitor', 'Erick')
$tecX = 6
foreach ($tec in $tecNomes) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $tec
    $btn.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 6.5)
    $btn.FlatStyle = 'Flat'
    $btn.FlatAppearance.BorderSize = 1
    $btn.Location = New-Object System.Drawing.Point($tecX, 20)
    $btn.Size = New-Object System.Drawing.Size(40, 34)
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
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
```

Inicializar todos os demais botoes com:

```powershell
foreach ($t in @('Hyrides', 'Vitor', 'Erick')) {
    $script:tecBtns[$t].BackColor = [System.Drawing.Color]::FromArgb(10, 20, 33)
    $script:tecBtns[$t].ForeColor = [System.Drawing.Color]::FromArgb(100, 148, 185)
    $script:tecBtns[$t].FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(22, 44, 66)
}
```

- [ ] **Step 4: Trocar o texto livre pelo botao com menu**

Substituir `$txtGradeOs` por:

```powershell
$script:gradeCadastroOs = if ($script:rnaAtivo) { 'RMA' } elseif ($script:gradeAtual) { [string]$script:gradeAtual } else { 'A' }
$btnGradeOs = New-Object System.Windows.Forms.Button
$btnGradeOs.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 7.5)
$btnGradeOs.BackColor = [System.Drawing.Color]::FromArgb(12, 22, 35)
$btnGradeOs.ForeColor = [System.Drawing.Color]::White
$btnGradeOs.FlatStyle = 'Flat'
$btnGradeOs.FlatAppearance.BorderSize = 0
$btnGradeOs.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$btnGradeOs.Location = New-Object System.Drawing.Point(5, 19)
$btnGradeOs.Size = New-Object System.Drawing.Size(168, 22)
$btnGradeOs.Text = (Format-CaijGradeReference $script:gradeCadastroOs)
$btnGradeOs.Cursor = [System.Windows.Forms.Cursors]::Hand
[void]$cardGrade.Controls.Add($btnGradeOs)

$gradeMenuOs = New-Object System.Windows.Forms.ContextMenuStrip
$gradeMenuOs.BackColor = [System.Drawing.Color]::FromArgb(12, 22, 35)
$gradeMenuOs.ForeColor = [System.Drawing.Color]::White
foreach ($gradeOpcao in @(Get-CaijGradeOptions)) {
    $gradeItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $gradeItem.Text = (Format-CaijGradeReference $gradeOpcao)
    $gradeItem.Tag = $gradeOpcao
    $gradeItem.Add_Click({
        $script:gradeCadastroOs = [string]$this.Tag
        $script:gradeAtual = [string]$this.Tag
        $btnGradeOs.Text = (Format-CaijGradeReference $script:gradeCadastroOs)
        Update-ResumoOs -Produto $listProd.SelectedItem
    })
    [void]$gradeMenuOs.Items.Add($gradeItem)
}
$btnGradeOs.Add_Click({
    $gradeMenuOs.Show($btnGradeOs, (New-Object System.Drawing.Point(0, $btnGradeOs.Height)))
})
```

Trocar as leituras de `$txtGradeOs.Text` por `$btnGradeOs.Text` em
`Update-ResumoOs`, confirmacao e payload. Remover o evento
`$txtGradeOs.Add_TextChanged`.

- [ ] **Step 5: Executar testes e parser**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File CoreCAIJ\GradeRules.Tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File CoreCAIJ\InfoNotebookPreview.Tests.ps1
powershell -NoProfile -Command "$errors=$null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'CoreCAIJ\InfoNotebook.ps1'),[ref]$null,[ref]$errors) | Out-Null; if($errors){$errors | ForEach-Object {$_.Message}; exit 1}; 'OK: parser'"
```

Expected: ambos os testes terminam com `OK` e o parser imprime `OK: parser`.

- [ ] **Step 6: Commitar a interface**

```powershell
git add CoreCAIJ/InfoNotebook.ps1 CoreCAIJ/InfoNotebookPreview.Tests.ps1
git commit -m "feat: adiciona seletor completo de grades"
```

### Task 3: Liberar Grade T sem OBS e encurtar o selo

**Files:**
- Modify: `CoreCAIJ/InfoNotebook.ps1:5250`
- Modify: `CoreCAIJ/InfoNotebook.ps1:5789`
- Modify: `CoreCAIJ/ServidorImpressao.ps1:3132`
- Modify: `CoreCAIJ/InfoNotebookPreview.Tests.ps1:17`
- Deploy: `C:\Users\Usuário\Desktop\ServidorImpressao.ps1`

**Interfaces:**
- Consumes: `Test-CaijGradeRequiresObs` da Task 1.
- Produces: validacoes coerentes de OBS e selo TSPL `T - TRIAGEM`.

- [ ] **Step 1: Escrever os testes regressivos**

Adicionar a `CoreCAIJ/InfoNotebookPreview.Tests.ps1`:

```powershell
Assert-True ($scriptText -match 'Test-CaijGradeRequiresObs') 'janela usa regra central de observacao'
Assert-True ($scriptText -match "'T - TRIAGEM'") 'previa usa selo curto de triagem'
Assert-True ($serverText -match "\$gradeBadge\s*=\s*'T - TRIAGEM'") 'TSPL usa selo curto de triagem'
```

- [ ] **Step 2: Executar o teste e confirmar a falha esperada**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File CoreCAIJ\InfoNotebookPreview.Tests.ps1
```

Expected: falha em `janela usa regra central de observacao`.

- [ ] **Step 3: Aplicar a regra central nas tres validacoes**

Substituir as condicoes que combinam B, C e T por:

```powershell
if ((Test-CaijGradeRequiresObs $script:gradeAtual) -and [string]::IsNullOrWhiteSpace($obsTexto)) {
```

No bloco `UpdateConfirmState`, usar:

```powershell
$needsObs = Test-CaijGradeRequiresObs $script:gradeAtual
```

- [ ] **Step 4: Encurtar somente o selo de Grade T**

Na previa de `CoreCAIJ/InfoNotebook.ps1`, trocar a alternativa de Grade T para:

```powershell
elseif ($gradeEfetiva -match '^T\s*-\s*TRIAGEM$') { 'T - TRIAGEM' }
```

No TSPL de `CoreCAIJ/ServidorImpressao.ps1`, trocar:

```powershell
} elseif ($grade -match '^T\s*-\s*TRIAGEM$') {
    $gradeBadge = 'T - TRIAGEM'
}
```

- [ ] **Step 5: Executar a verificacao completa**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File CoreCAIJ\GradeRules.Tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File CoreCAIJ\InfoNotebookPreview.Tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File CoreCAIJ\TestarAltertag.Tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File CoreCAIJ\InfoNotebookMac.Tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File CoreCAIJ\MacUi.Tests.ps1
git diff --check
```

Expected: todos os testes terminam com `OK` e `git diff --check` nao aponta erros.

- [ ] **Step 6: Sincronizar e reiniciar o servidor operacional**

```powershell
$source = (Resolve-Path 'CoreCAIJ\ServidorImpressao.ps1').Path
$destination = 'C:\Users\Usuário\Desktop\ServidorImpressao.ps1'
Copy-Item -LiteralPath $source -Destination $destination -Force
$repoHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
$operationalHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
if ($repoHash -ne $operationalHash) { throw 'Servidor operacional diferente do arquivo versionado' }
'OK: servidor sincronizado'
```

Reiniciar o processo elevado do servidor e validar:

```powershell
$status = Invoke-RestMethod -Uri 'http://127.0.0.1:9100/status' -Method Get -TimeoutSec 8
if ($status.status -ne 'ok') { throw 'Servidor nao respondeu OK' }
'OK: servidor operacional'
```

- [ ] **Step 7: Commitar a correcao**

```powershell
git add CoreCAIJ/InfoNotebook.ps1 CoreCAIJ/ServidorImpressao.ps1 CoreCAIJ/InfoNotebookPreview.Tests.ps1
git commit -m "fix: ajusta triagem sem obs na etiqueta"
```
