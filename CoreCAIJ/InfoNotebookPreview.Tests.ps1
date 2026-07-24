param(
    [string]$ScriptPath = (Join-Path $PSScriptRoot 'InfoNotebook.ps1')
)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Name
    )
    if (-not $Condition) {
        throw "FAIL: $Name"
    }
}

$scriptText = Get-Content -Path $ScriptPath -Raw
$gradeRulesText = Get-Content -Path (Join-Path $PSScriptRoot 'GradeRules.ps1') -Raw

Assert-True ($scriptText -notmatch '(?m)^\s*B\s+14\s+238\s+458\s+1\s*$') 'previa com observacao nao deve desenhar separador solto'
Assert-True ($gradeRulesText -match 'GRADE T - TRIAGEM') 'referencia da OS mantem Grade T - Triagem'
Assert-True ($scriptText -match "\@\{L='T'; D='Triagem'\}") 'popup mostra botao Grade T'
Assert-True ($scriptText -match "\`$tecNomes\s*=\s*@\('Lucas',\s*'Hyrides',\s*'Vitor',\s*'Erick'\)") 'cadastro mostra tecnico Erick'
Assert-True ($scriptText -match 'Get-CaijGradeOptions') 'cadastro usa todas as grades'
Assert-True ($scriptText -match 'ContextMenuStrip') 'cadastro abre menu de grades'
Assert-True ($scriptText -match '\$btnGradeOs') 'referencia usa botao de grade'
Assert-True ($scriptText -notmatch '\$txtGradeOs\s*=\s*New-Object System\.Windows\.Forms\.TextBox') 'referencia nao usa texto livre'
Assert-True ($scriptText -match 'class\s+CaijGradeMenuRenderer') 'renderer exclusivo do menu de grades'
Assert-True ($scriptText -match "StartsWith\(`"C - PINTURA`"") 'renderer agrupa grades C'
Assert-True ($scriptText -match 'Color\.FromArgb\(66,\s*232,\s*176\)') 'renderer usa verde na grade A'
Assert-True ($scriptText -match 'Color\.FromArgb\(255,\s*208,\s*96\)') 'renderer usa amarelo na grade B'
Assert-True ($scriptText -match 'Color\.FromArgb\(255,\s*156,\s*98\)') 'renderer usa laranja nas grades C'
Assert-True ($scriptText -match 'Color\.FromArgb\(24,\s*185,\s*255\)') 'renderer usa ciano na grade T'
Assert-True ($scriptText -match 'Color\.FromArgb\(241,\s*95,\s*122\)') 'renderer usa vermelho no RMA'
Assert-True ($scriptText -match 'FillEllipse\(marker,\s*bounds\.Width\s*-\s*12') 'marcador selecionado fica no canto direito'
$rendererSourceMatch = [regex]::Match($scriptText, "(?s)\`$gradeMenuRendererSource\s*=\s*@'\r?\n(?<source>.*?)\r?\n'@")
Assert-True $rendererSourceMatch.Success 'fonte C# do renderer pode ser extraida'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition $rendererSourceMatch.Groups['source'].Value -ReferencedAssemblies @('System.Windows.Forms', 'System.Drawing') -WarningAction SilentlyContinue
$rendererInstance = New-Object CaijGradeMenuRenderer
Assert-True ($rendererInstance -is [System.Windows.Forms.ToolStripProfessionalRenderer]) 'renderer C# compila e instancia'
Assert-True ($scriptText -match '\$gradeMenuOs\.ShowImageMargin\s*=\s*\$false') 'menu remove faixa branca de imagens'
Assert-True ($scriptText -match '\$gradeMenuOs\.ShowCheckMargin\s*=\s*\$false') 'menu remove margem nativa de marcacao'
Assert-True ($scriptText -match '\$gradeMenuOs\.Renderer\s*=\s*New-Object CaijGradeMenuRenderer') 'menu usa renderer hibrido'
Assert-True ($scriptText -match '\$gradeMenuOs\.MinimumSize\s*=\s*New-Object System\.Drawing\.Size\(178,\s*0\)') 'menu acompanha largura do card'
Assert-True ($scriptText -match '\$gradeItem\.Size\s*=\s*New-Object System\.Drawing\.Size\(176,\s*30\)') 'itens possuem dimensoes estaveis'
Assert-True ($scriptText -match '\$gradeMenuOs\.Add_Opening') 'menu sincroniza grade selecionada ao abrir'
Assert-True ($scriptText -match '\$item\.Checked\s*=\s*\(\[string\]\$item\.Tag -eq \[string\]\$script:gradeCadastroOs\)') 'marcador representa grade atual'
Assert-True ($scriptText -match 'function\s+Show-CadastroOsConfirm') 'cadastro usa modal moderno de confirmacao'
Assert-True ($scriptText -match 'function\s+Show-CadastroOsResult') 'cadastro usa modal moderno de resultado'
Assert-True ($scriptText -match 'Show-CadastroOsResult\s+`\s*\r?\n\s*-Owner\s+\$dlg') 'resultado substitui caixa padrao do Windows'
Assert-True ($scriptText -notmatch 'MessageBox\]\:\:Show\(\$msgOk') 'resultado nao usa mensagem padrao de sucesso'
Assert-True ($scriptText -match 'ALTERTAG / NOVA OS') 'modal identifica fluxo Altertag'
foreach ($confirmLabel in @('PRODUTO', 'SERIAL', 'REFERENCIA', 'QUANTIDADE', 'LOCALIZACAO', 'SERVICOS')) {
    Assert-True ($scriptText -match [regex]::Escape("'$confirmLabel'")) "modal mostra campo $confirmLabel"
}
Assert-True ($scriptText -match 'Show-CadastroOsConfirm\s+`\s*\r?\n\s*-Owner\s+\$dlg') 'cadastro abre modal moderno'
Assert-True ($scriptText -notmatch "'Confirmar cadastro',\s*\r?\n\s*\[System\.Windows\.Forms\.MessageBoxButtons\]::YesNo") 'cadastro nao usa MessageBox antigo'
Assert-True ($scriptText -match 'Test-CaijGradeRequiresObs') 'validacao de OBS usa regra central'
Assert-True ($scriptText -match "(?s)\`$gradeTxt\s*=.*?'T - TRIAGEM'") 'previa encurta selo da triagem'
Assert-True ($scriptText -match '\$popup\.ClientSize\s*=\s*New-Object System\.Drawing\.Size\(920,\s*660\)') 'popup usa layout horizontal moderno'
Assert-True ($scriptText -match '\$prevPanel\.Size\s*=\s*New-Object System\.Drawing\.Size\(576,\s*360\)') 'previa preserva proporcao 80x50'
Assert-True ($scriptText -match 'BoxPreview\s+10\s+14\s+430\s+74\s+2') 'previa replica caixa superior do modelo'
Assert-True ($scriptText -match 'BoxPreview\s+10\s+84\s+410\s+154\s+3') 'previa replica caixa separada do serial'
Assert-True ($scriptText -match 'BoxPreview\s+430\s+84\s+630\s+154\s+3') 'previa replica caixa separada da OS'
Assert-True ($scriptText -match 'BoxPreview\s+10\s+166\s+630\s+384\s+2') 'previa replica area inferior'
Assert-True ($scriptText -match 'B\s+318\s+166\s+2\s+218') 'previa divide configuracao e observacoes'
Assert-True ($scriptText -match "L\s+'CONFIGURACAO'\s+22\s+173") 'previa identifica configuracao'
Assert-True ($scriptText -match "L\s+'OBSERVACOES'\s+334\s+173") 'previa identifica observacoes'
Assert-True ($scriptText -match '\$controlDeck\.SendToBack\(\)\s*\r?\n\s*foreach\s*\(\$previewControl') 'painel direito fica atras dos controles'
Assert-True ($scriptText -match '\$previewControl\.BringToFront\(\)') 'controles da previa voltam para frente'
Assert-True ($scriptText -match '\$resp\.produtoErro') 'interface informa pendencia ao adicionar produto'

$serverPath = Join-Path $PSScriptRoot 'ServidorImpressao.ps1'
$serverText = Get-Content -Path $serverPath -Raw
Assert-True ($serverText -match "'ERICK'") 'servidor permite tecnico Erick'
Assert-True ($serverText -match 'T - TRIAGEM') 'servidor reconhece Grade T - Triagem'
Assert-True ($serverText -match "\`$gradeBadge\s*=\s*'T - TRIAGEM'") 'impressao encurta selo da triagem'
Assert-True ($serverText -notmatch 'Test-VhsysProdutoLocalizacao -Response \$prodResp') 'servidor aceita resposta oficial do produto sem localizacao'
Assert-True ($serverText -notmatch '-SemLocalizacao') 'servidor nao permite fallback sem localizacao'
Assert-True ($serverText -notmatch 'tentando sem localizacao') 'servidor nao mascara falha da localizacao'
Assert-True ($serverText -notmatch 'Produto da OS .* nao confirmou a localizacao T.+CNICA_BT') 'servidor nao transforma produto criado em erro de localizacao'
Assert-True ($serverText -match 'OS \$idPedido criada, mas o produto falhou') 'servidor registra pendencia sem negar criacao da OS'
Assert-True ($serverText -match 'produtoErro=\$out\.produtoErro') 'rota informa pendencia do produto'

'OK: InfoNotebookPreview tests'
