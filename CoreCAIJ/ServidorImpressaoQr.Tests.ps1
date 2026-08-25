param(
    [string]$ScriptPath = (Join-Path $PSScriptRoot 'ServidorImpressao.ps1')
)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Name)
    if (-not $Condition) { throw "FAIL: $Name" }
}

function Assert-Equal {
    param($Actual, $Expected, [string]$Name)
    if ($Actual -ne $Expected) { throw "FAIL: $Name. Esperado=[$Expected] Atual=[$Actual]" }
}

$scriptText = Get-Content -LiteralPath $ScriptPath -Raw

Assert-True ($scriptText -match "function\s+Publish-QrFicha") 'publicacao da ficha possui funcao dedicada'
Assert-True ($scriptText -match "Invoke-WebRequest[\s\S]*?-Uri\s+\`$publishedUrl") 'URL publica e consultada antes da impressao'
Assert-True ($scriptText -match "StatusCode\s+-eq\s+200") 'validacao exige resposta HTTP 200'
Assert-True ($scriptText -match "FICHA TECNICA") 'validacao confirma o conteudo da ficha'
Assert-True ($scriptText -match "foreach\s*\(\`$attempt\s+in\s+1\.\.4\)") 'validacao tolera propagacao curta do tunnel'
Assert-True ($scriptText -match "\`$qrPayload\s*=\s*\`$publicQrUrl") 'QR usa somente a URL publica validada'
Assert-True ($scriptText -notmatch "\`$qrPayload\s*=\s*if\s*\(\`$publicQrUrl\)") 'impressao nao usa fallback local silencioso'
Assert-True ($scriptText -match "Nao foi possivel publicar e validar a ficha do QR") 'falha publica interrompe a impressao com diagnostico'
Assert-True ($scriptText -notmatch "qrEncodedPayload|'B\{0:D4\}\{1\}'") 'QR nao inclui prefixo B00 incompativel com o firmware'
Assert-True ($scriptText -match 'QRCODE 382,188,M,5,A,0,M2,S7') 'QR compacto fica centralizado verticalmente no quadro direito'
Assert-True ($scriptText -match 'QRCODE 382,188,M,5,A,0,M2,S7,`"\$qrPayload`"') 'QR codifica somente a URL publica'
Assert-True ($scriptText -match 'QRCODE 402,174,M,4,A,0,M2,S7,`"\$qrPayload`"') 'QR fica menor quando a observacao precisa da faixa inferior'
Assert-True ($scriptText -match 'SIZE 80 mm,50 mm') 'canvas fisico usa exatamente 80x50mm'
Assert-True ($scriptText -match 'BOX 10,10,630,390,2') 'etiqueta possui uma unica moldura com margem segura'
Assert-True ($scriptText -notmatch 'BOX 2,4,638,398|BARCODE 28,132') 'layout remove segunda borda visual e codigo de barras redundante'
Assert-True ($scriptText -match 'BAR 10,82,620,2[\s\S]*?BAR 10,158,620,2') 'cabecalho usa divisorias simples sem caixas sobrepostas'
Assert-True ($scriptText -match 'Wrap-TsplLines\s+-Text\s+\(\[string\]\$obs\)\.Trim\(\)\s+-MaxLen\s+69\s+-MaxLines\s+3') 'etiqueta usa tres linhas largas para a observacao da OS'
Assert-True ($scriptText -match 'BAR 20,330,590,1') 'observacao ocupa toda a largura segura da etiqueta'
Assert-True ($scriptText -match '\.TrimEnd\(\)\s*\+\s*''\.\.\.''') 'texto excedente recebe reticencias sem ultrapassar a moldura'
Assert-True ($scriptText -match 'if\s*\(-not\s+\$temObservacaoEtiqueta\)[\s\S]*?TEXT 244,370') 'data avulsa nao sobrepoe uma observacao presente'
Assert-True ($scriptText -match 'BARCODE 22,136,`"128`",16,0,0,1,2') 'codigo de barras Code 128 acompanha a serial'
Assert-True ($scriptText -match '\$temObservacaoEtiqueta\s*=\s*\(\$obsLines\.Count\s+-gt\s+0\)') 'OBS so existe quando o texto gera linhas imprimiveis'
Assert-True ($scriptText -match 'TEXT 22,16,`"2`",0,1,1,`"EQUIPAMENTO') 'titulo equipamento usa fonte termica 2'
Assert-True ($scriptText -match 'TEXT 22,86,`"2`",0,1,1,`"SERIAL') 'titulo serial usa fonte termica 2'
Assert-True ($scriptText -match 'TEXT 446,86,`"2`",0,1,1,`"ORDEM DE SERV\.') 'titulo da OS usa fonte termica 2'
Assert-True ($scriptText -match "Limpar\s+\`$obsVisual\s+'!,;:/%'") 'observacao preserva barra e percentual'
Assert-True ($scriptText -match "fichaUrl=\`$qrPayload") 'resposta informa a URL realmente enviada para a impressora'
Assert-True ($scriptText -match "v6\.15-mac-ciclos-bateria") 'status identifica a versao com ciclos da bateria do Mac'
Assert-True ($scriptText -match '\$modelo\s*=\s*Limpar\s+\$dados\.modelo\s+'',''') 'modelo preserva a virgula do identificador tecnico do Mac'
Assert-True ($scriptText -match 'if\s*\(\$pct\s+-le\s+0\)\s*\{\s*return\s+''N/A''') 'servidor nunca classifica bateria zerada como boa'
Assert-True ($scriptText -match '\$cycleText\s*=\s*" C:') 'etiqueta mostra ciclos da bateria de forma compacta'
Assert-True ($scriptText -match '\$bateriaFicha\s*\+=\s*" \| .* CICLOS"') 'ficha QR mostra ciclos da bateria por extenso'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $ScriptPath), [ref]$tokens, [ref]$parseErrors)
Assert-True ($parseErrors.Count -eq 0) 'servidor de impressao possui sintaxe valida'
$wrapObsAst = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Wrap-TsplLines' }, $true)
Assert-True ($null -ne $wrapObsAst) 'funcao de quebra da observacao encontrada'
Invoke-Expression $wrapObsAst.Extent.Text
$linhasObservacaoLonga = @(Wrap-TsplLines -Text (('observacao extensa para validar o limite seguro ' * 8).Trim()) -MaxLen 69 -MaxLines 3)
Assert-Equal $linhasObservacaoLonga.Count 3 'observacao longa permanece em tres linhas'
Assert-True (($linhasObservacaoLonga | Where-Object { $_.Length -gt 69 }).Count -eq 0) 'nenhuma linha ultrapassa a largura imprimivel'
Assert-True ($linhasObservacaoLonga[-1].EndsWith('...')) 'observacao excedente termina com reticencias'
$formatObsAst = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Format-ObservacaoEtiqueta' }, $true)
Assert-True ($null -ne $formatObsAst) 'funcao de limpeza visual da observacao encontrada'
Invoke-Expression $formatObsAst.Extent.Text
Assert-Equal (Format-ObservacaoEtiqueta '24/08/26 - 15:20 - Vitor: Bateria 90% / aprovada') 'Bateria 90% / aprovada' 'etiqueta remove auditoria e preserva o relato'
Assert-Equal (Format-ObservacaoEtiqueta 'Trocar cabo / testar em 100%') 'Trocar cabo / testar em 100%' 'observacao manual sem prefixo permanece intacta'
$formatBatteryAst = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Format-BateriaQualidade' }, $true)
Assert-True ($null -ne $formatBatteryAst) 'funcao de formatacao da bateria encontrada'
Invoke-Expression $formatBatteryAst.Extent.Text
Assert-Equal (Format-BateriaQualidade '91% (Normal) | 540 ciclos') 'GOOD (91%) C:540' 'bateria com ciclos fica compacta na etiqueta'
Assert-True ($scriptText -match '\$isDesktop\s*=\s*\(\$tipoEquipamento\s+-match') 'servidor reconhece etiquetas desktop'
Assert-True ($scriptText -match "\`$gradeRaw\s+-in\s+@\('A','B','C','RMA'\)") 'servidor aceita grade C simples'
Assert-True ($scriptText -match '\$mostrarBateria\s*=\s*\(-not\s+\$isDesktop') 'desktop nao imprime bateria'
Assert-True ($scriptText -match 'elseif\s*\(\$isDesktop\)\s*\{[\s\S]*?TEXT 22,173,.*DESKTOP') 'desktop usa bloco de configuracao proprio'
Assert-True ($scriptText -match "AMD Radeon Int\.") 'etiqueta abrevia Radeon integrada sem cortar palavras'
Assert-True ($scriptText -match 'function\s+Expand-GpuCompleta') 'servidor restaura nomes conhecidos antes de publicar a ficha'
Assert-True ($scriptText -match "AMD Radeon Graphics \(Integrada\)") 'ficha normaliza Radeon integrada para o nome completo'
Assert-True ($scriptText -match '\$qrGpu\s*=\s*if[\s\S]*?else\s*\{\s*\$gpuCompleta\s*\}') 'ficha QR preserva GPU completa como fallback'
Assert-True ($scriptText -match '\$qrCpu\s*=\s*if\s*\(\$dados\.fichaCpu\)') 'ficha QR aceita CPU integral enviada pelo cliente'
Assert-True ($scriptText -match '\$qrGpu\s*=\s*if\s*\(\$dados\.fichaGpu\)') 'ficha QR aceita GPU integral enviada pelo cliente'
Assert-True ($scriptText -match '\$qrRam\s*=\s*if\s*\(\$dados\.fichaRam\)') 'ficha QR aceita RAM integral enviada pelo cliente'
Assert-True ($scriptText -match '\$qrDisco\s*=\s*if\s*\(\$dados\.fichaDisco\)') 'ficha QR aceita disco integral enviado pelo cliente'

Write-Host 'PASS: QR usa somente a URL publica e respeita os limites da etiqueta.'
