param(
    [string]$ScriptPath = (Join-Path $PSScriptRoot 'TestarNotebook.ps1')
)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Name)
    if (-not $Condition) { throw "FAIL: $Name" }
}

$scriptText = Get-Content -LiteralPath $ScriptPath -Raw
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path $ScriptPath),
    [ref]$tokens,
    [ref]$parseErrors
)

Assert-True ($parseErrors.Count -eq 0) 'Central de Testes possui sintaxe valida'
Assert-True ($scriptText -match 'class\s+CaijTestsDpiAwareness') 'processo separado possui DPI awareness dedicado'
Assert-True ($scriptText -match 'SetProcessDpiAwarenessContext\(new IntPtr\(-4\)\)') 'Central usa DPI real por monitor antes da janela'
$dpiSourceMatch = [regex]::Match($scriptText, "(?s)\`$testsDpiSource\s*=\s*@'\r?\n(?<source>.*?)\r?\n'@")
Assert-True $dpiSourceMatch.Success 'fonte C# do DPI pode ser extraida'
Add-Type -TypeDefinition $dpiSourceMatch.Groups['source'].Value -WarningAction SilentlyContinue
Assert-True ($null -ne ('CaijTestsDpiAwareness' -as [type])) 'integracao de DPI compila corretamente'
Assert-True ($scriptText -match 'function\s+New-TestsFont') 'Central possui selecao de fonte nativa nitida'
Assert-True ($scriptText -match "'Segoe UI Variable Display'") 'titulos usam Segoe UI Variable Display'
Assert-True ($scriptText -match "'Segoe UI Variable Text'") 'textos usam Segoe UI Variable Text'
Assert-True ($scriptText -match 'function\s+Set-TestsTypography') 'tipografia e aplicada recursivamente aos controles'
Assert-True ($scriptText -match '\$control\.UseCompatibleTextRendering\s*=\s*\$false') 'rotulos e botoes usam renderizacao GDI nitida'
Assert-True ($scriptText -match 'Set-TestsTypography\s+-Root\s+\$form') 'tipografia e aplicada antes de exibir a janela'
$fontFunctionAst = $ast.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'New-TestsFont'
}, $true)
Assert-True ($null -ne $fontFunctionAst) 'funcao de tipografia pode ser testada isoladamente'
Add-Type -AssemblyName System.Drawing
Invoke-Expression $fontFunctionAst.Extent.Text
$testFont = New-TestsFont -Kind 'UI' -Size 9
Assert-True ($null -ne $testFont -and -not [string]::IsNullOrWhiteSpace($testFont.Name)) 'fonte de interface e criada no Windows'
$testFont.Dispose()
Assert-True ($scriptText -match '\$form\.FormBorderStyle\s*=\s*''None''') 'janela usa cabecalho proprio'
Assert-True ($scriptText -match '\$form\.ClientSize\s*=\s*New-Object System\.Drawing\.Size\(980,\s*550\)') 'layout possui dimensoes estaveis'
Assert-True ($scriptText -match '\$form\.AutoScaleMode\s*=\s*\[System\.Windows\.Forms\.AutoScaleMode\]::None') 'layout evita dupla escala automatica do WinForms'
Assert-True ($scriptText -notmatch '\$form\.DoubleBuffered\s*=') 'Central nao tenta gravar propriedade interna do formulario'
Assert-True ($scriptText -match 'function\s+Set-TestsResponsiveLayout') 'Central possui dimensionamento adaptativo'
Assert-True ($scriptText -match '\$workingArea\.Width\s*\*\s*0\.84') 'janela ocupa uma area confortavel do monitor'
Assert-True ($scriptText -match '\$Form\.Scale\(\(New-Object System\.Drawing\.SizeF') 'controles acompanham a ampliacao da janela'
Assert-True ($scriptText -notmatch '\$fontControl\.Font\.Size\s*\*\s*\$layoutScale') 'fonte nao recebe escala duplicada'
Assert-True ($scriptText -match 'Set-TestsResponsiveLayout\s+-Form\s+\$form') 'escala responsiva e aplicada antes de exibir a Central'
Assert-True ($scriptText -match '\$cBg\s*=\s*\[System\.Drawing\.Color\]::FromArgb\(7,\s*9,\s*17\)') 'tela usa o mesmo canvas do InfoNotebook'
Assert-True ($scriptText -match '\$cAccent\s*=\s*\[System\.Drawing\.Color\]::FromArgb\(94,\s*106,\s*210\)') 'lavanda e a unica acao visual primaria'
Assert-True ($scriptText -match '\$eyebrow\.Text\s*=\s*''DIAGNOSTICO\s+/\s+VALIDACAO TECNICA''') 'cabecalho possui contexto operacional'
Assert-True ($scriptText -match '\$head\.Add_MouseDown') 'cabecalho personalizado permite mover a janela'
Assert-True ($scriptText -match '\$footerLine\.BackColor\s*=\s*\$cBorder') 'rodape possui divisoria discreta'
Assert-True ($scriptText -match "New-TestRow\s+-Y\s+0\s+-Numero\s+'01'\s+-Titulo\s+'Camera'") 'teste de camera permanece'
Assert-True ($scriptText -match "New-TestRow\s+-Y\s+68\s+-Numero\s+'02'\s+-Titulo\s+'Teclado'") 'teste de teclado permanece'
Assert-True ($scriptText -match "New-TestRow\s+-Y\s+136\s+-Numero\s+'03'\s+-Titulo\s+'Som e Microfone'") 'teste de som e microfone permanece'
Assert-True ($scriptText -match "New-TestRow\s+-Y\s+204\s+-Numero\s+'04'\s+-Titulo\s+'Tela / Dead Pixel'") 'teste de tela permanece'
Assert-True ($scriptText -match "Start-Process\s+'microsoft\.windows\.camera:'") 'acao da camera permanece conectada'
Assert-True ($scriptText -match 'https://keyboard-test\.space/pt/') 'acao do teclado permanece conectada'
Assert-True ($scriptText -match "Start-Process\s+'ms-settings:sound'") 'acao de som permanece conectada'
Assert-True ($scriptText -match 'https://lcdtech\.info/en/tests/dead\.pixel\.htm') 'acao de dead pixel permanece conectada'
Assert-True ($scriptText -match '\$txt\s*=\s*"CAIJ \| CENTRAL DE TESTES\$NL"') 'relatorio continua sendo gerado'
Assert-True ($scriptText -match "'ok'\s*\{\s*'PASSOU'\s*\}\s*'fail'\s*\{\s*'FALHOU'") 'relatorio preserva estados operacionais'

Write-Host 'OK: Central de Testes preserva comportamento e usa o novo design.'
