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

$aliasesInicio = $scriptText.IndexOf('function Get-CaijProdutoBuscaAliases')
$aliasesFim = $scriptText.IndexOf('function Normalize-AltertagQuantidade', $aliasesInicio)
$aliasesText = $scriptText.Substring($aliasesInicio, $aliasesFim - $aliasesInicio)
Assert-True ($aliasesText.Contains("`$aliases += @('T023', 'T023-', 'T023--')")) 'busca pelo modelo 3420 inclui toda a familia operacional T023'

$buscaCatalogoInicio = $scriptText.IndexOf('function Search-VhsysProdutosCatalogo')
$buscaCatalogoFim = $scriptText.IndexOf('function Resolve-VhsysProdutoCatalogo', $buscaCatalogoInicio)
$buscaCatalogoText = $scriptText.Substring($buscaCatalogoInicio, $buscaCatalogoFim - $buscaCatalogoInicio)
Assert-True ($buscaCatalogoText.Contains("`$termoClean + '--'")) 'busca por codigo T inclui a segunda variacao com traco'
Assert-True ($buscaCatalogoText.Contains('Get-ProdutoSortKey')) 'busca da API prioriza codigos operacionais T'
Assert-True ($buscaCatalogoText.Contains('T\d{3,}')) 'modelo E14 nao e confundido com codigo operacional T019'
Assert-True ($buscaCatalogoText.Contains('if ($result.Count -gt 0)')) 'resultado vazio da API nao fica preso no cache'
Assert-True ($buscaCatalogoText.Contains('return $result')) 'busca da API retorna a colecao sem array aninhado'
Assert-True ($scriptText.Contains('Search-VhsysProdutosCatalogo -Termo $termoBusca -Limit 50')) 'busca por modelo considera ate 50 produtos'

Assert-True ($scriptText -match 'class CaijRawPrinter') 'servidor possui envio RAW direto ao spooler'
Assert-True ($scriptText -match 'WritePrinter\(printer, data, data\.Length, out written\)') 'servidor confirma todos os bytes enviados'
Assert-True ($scriptText -match 'CaijRawPrinter\]::Print\(\$impressora, \$bytes\)') 'etiqueta usa a impressora configurada sem compartilhamento UNC'
Assert-True ($scriptText -notmatch 'copy /b .*\\\\localhost') 'impressao nao depende do compartilhamento localhost'
Assert-True ($scriptText -match "function\s+Publish-QrFicha") 'publicacao da ficha possui funcao dedicada'
Assert-True ($scriptText -match "function\s+Sync-InfoNotebookServiceOrderTracker") 'impressao possui sincronizacao dedicada com o rastreador'
Assert-True ($scriptText -match '/api/infonotebook/service-order-sync') 'rastreador usa a integracao protegida do site'
Assert-True ($scriptText -match 'x-caij-infonotebook-key') 'sincronizacao do rastreador exige chave privada'
Assert-True ($scriptText -match 'if \(\$printRes\.ok\)[\s\S]*?Sync-InfoNotebookServiceOrderTracker') 'rastreador so e alterado depois da confirmacao do spooler'
Assert-True ($scriptText -match "rastreador nao atualizado apos a impressao") 'falha do rastreador nao transforma etiqueta impressa em falha de impressao'
$publishStart = $scriptText.IndexOf('function Publish-QrFicha')
$publishEnd = $scriptText.IndexOf('function Sync-InfoNotebookServiceOrderTracker', $publishStart)
$publishText = $scriptText.Substring($publishStart, $publishEnd - $publishStart)
Assert-True ($publishText -match 'Invoke-RestMethod[\s\S]*?/api/label-sheets') 'ficha QR e persistida pela API publica antes da impressao'
Assert-True ($publishText -match '\$publishedUrl\s+-notmatch') 'API deve devolver uma URL publica no formato esperado'
Assert-True ($publishText -notmatch 'Invoke-WebRequest|foreach\s*\(\$attempt\s+in\s+1\.\.4\)') 'impressao nao aguarda consultas externas repetidas depois da publicacao'
Assert-True ($scriptText -match "\`$qrPayload\s*=\s*\`$publicQrUrl") 'QR usa somente a URL publica validada'
Assert-True ($scriptText -notmatch "\`$qrPayload\s*=\s*if\s*\(\`$publicQrUrl\)") 'impressao nao usa fallback local silencioso'
Assert-True ($scriptText -match "Nao foi possivel publicar a ficha do QR") 'falha de publicacao interrompe a impressao com diagnostico'
Assert-True ($scriptText -notmatch "qrEncodedPayload|'B\{0:D4\}\{1\}'") 'QR nao inclui prefixo B00 incompativel com o firmware'
Assert-True ($scriptText -match 'QRCODE 382,188,M,5,A,0,M2,S7') 'QR compacto fica centralizado verticalmente no quadro direito'
Assert-True ($scriptText -match 'QRCODE 382,188,M,5,A,0,M2,S7,`"\$qrPayload`"') 'QR codifica somente a URL publica'
Assert-True ($scriptText -match 'QRCODE 402,174,M,4,A,0,M2,S7,`"\$qrPayload`"') 'QR fica menor quando a observacao precisa da faixa inferior'
Assert-True ($scriptText -match 'SIZE 80 mm,50 mm') 'canvas fisico usa exatamente 80x50mm'
Assert-True ($scriptText -notmatch 'BOX 10,10,630,390,2|BOX 2,4,638,398') 'layout remove moldura perimetral sensivel a inclinacao do rolo'
Assert-True ($scriptText -notmatch 'BARCODE 28,132') 'layout nao reintroduz codigo de barras redundante'
Assert-True ($scriptText -match 'BITMAP 22,20,10,42,0') 'logo CAIJ ancora o inicio do cabecalho'
Assert-True ($scriptText -match 'function Get-CaijLabelLogoTsplData') 'bitmap do logo fica disponivel sem arquivo externo'
Assert-True ($scriptText -match 'ToByte\(\$hex\.Substring[\s\S]*?-bxor 0xFF') 'bitmap inverte a polaridade exigida pelo firmware termico'
Assert-True ($scriptText -match 'BAR 18,82,604,2[\s\S]*?BAR 18,158,604,2') 'cabecalho usa divisorias internas com folga lateral'
Assert-True ($scriptText -match 'Wrap-TsplLines\s+-Text\s+\(\[string\]\$obs\)\.Trim\(\)\s+-MaxLen\s+69\s+-MaxLines\s+3') 'etiqueta usa tres linhas largas para a observacao da OS'
Assert-True ($scriptText -match 'BAR 20,334,590,1') 'observacao ocupa toda a largura com folga apos configuracao'
Assert-True ($scriptText -match 'TEXT 22,346,`"2`",0,1,1,`"OBS') 'titulo da observacao ganha respiro abaixo da divisoria'
Assert-True ($scriptText -match '\.TrimEnd\(\)\s*\+\s*''\.\.\.''') 'texto excedente recebe reticencias sem ultrapassar a moldura'
Assert-True ($scriptText -match 'if\s*\(-not\s+\$temObservacaoEtiqueta\)[\s\S]*?TEXT 244,370') 'data avulsa nao sobrepoe uma observacao presente'
Assert-True ($scriptText -match 'BARCODE 22,136,`"128`",16,0,0,1,2') 'codigo de barras Code 128 acompanha a serial'
Assert-True ($scriptText -match '\$temObservacaoEtiqueta\s*=\s*\(\$obsLines\.Count\s+-gt\s+0\)') 'OBS so existe quando o texto gera linhas imprimiveis'
Assert-True ($scriptText -match 'TEXT 120,16,`"2`",0,1,1,`"EQUIPAMENTO') 'titulo equipamento fica alinhado ao lado do logo'
Assert-True ($scriptText -match 'TEXT 120,\$modeloY') 'modelo integra o mesmo bloco visual do logo e titulo'
Assert-True ($scriptText -match 'TEXT 22,86,`"2`",0,1,1,`"SERIAL') 'titulo serial usa fonte termica 2'
Assert-True ($scriptText -match 'TEXT 446,86,`"2`",0,1,1,`"ORDEM DE SERV\.') 'titulo da OS usa fonte termica 2'
Assert-True ($scriptText -match "Limpar\s+\`$obsVisual\s+'!,;:/%'") 'observacao preserva barra e percentual'
Assert-True ($scriptText -match "fichaUrl=\`$qrPayload") 'resposta informa a URL realmente enviada para a impressora'
Assert-True ($scriptText -match '\$requestedFichaUrl\s*=\s*if\s*\(\$dados\.fichaUrl\)') 'reimpressao aceita a URL da ficha existente'
Assert-True ($scriptText -match '\$requestedFichaUrl\s+-notmatch\s+''\^https://\[\^/\]\+/f/\[a-fA-F0-9\]\{32\}\$''') 'reimpressao valida a URL publica existente'
Assert-True ($scriptText -match '\$qrPayload\s*=\s*\$requestedFichaUrl[\s\S]*?else\s*\{[\s\S]*?Publish-QrFicha') 'reimpressao preserva o QR e publicacao nova continua isolada'
Assert-True ($scriptText -match "v6\.18-layout-termico") 'status identifica a revisao visual da etiqueta termica'
Assert-True ($scriptText -match 'Get-VhsysOrdensServicoRecentes\s+-Limit\s+250') 'consulta por numero cobre OS anteriores alem da lista curta'
Assert-True ($scriptText -match '\[Math\]::Min\(250,\s*\$Limit\)') 'API permite janela maxima de 250 ordens'
Assert-True ($scriptText -match '\$modelo\s*=\s*Limpar\s+\$dados\.modelo\s+'',''') 'modelo preserva a virgula do identificador tecnico do Mac'
Assert-True ($scriptText -match 'if\s*\(\$pct\s+-le\s+0\)\s*\{\s*return\s+''N/A''') 'servidor nunca classifica bateria zerada como boa'
Assert-True ($scriptText -match '\$cycleText\s*=\s*" C:') 'etiqueta mostra ciclos da bateria de forma compacta'
Assert-True ($scriptText -match '\$bateriaFicha\s*\+=\s*" \| .* CICLOS"') 'ficha QR mostra ciclos da bateria por extenso'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $ScriptPath), [ref]$tokens, [ref]$parseErrors)
Assert-True ($parseErrors.Count -eq 0) 'servidor de impressao possui sintaxe valida'
$aliasesAst = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-CaijProdutoBuscaAliases' }, $true)
$limparAst = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Limpar' }, $true)
$fitTextAst = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Fit-TsplText' }, $true)
$formatGpuAst = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Format-GpuEtiqueta' }, $true)
Assert-True ($null -ne $limparAst -and $null -ne $fitTextAst -and $null -ne $formatGpuAst) 'formatadores visuais da GPU encontrados'
Assert-True ($null -ne $aliasesAst) 'aliases da busca de produtos encontrados'
Invoke-Expression $aliasesAst.Extent.Text
$aliases3420 = @(Get-CaijProdutoBuscaAliases -Termo '3420')
Assert-True ($aliases3420 -contains 'T023') '3420 encontra o codigo T023'
Assert-True ($aliases3420 -contains 'T023-') '3420 encontra a variacao T023-'
Assert-True ($aliases3420 -contains 'T023--') '3420 consulta tambem a segunda variacao T023--'
Assert-True (@(Get-CaijProdutoBuscaAliases -Termo 'Latitude 3420 i5 11th') -contains 'A023-C2F') 'busca detalhada do 3420 preserva variacoes de configuracao'
Invoke-Expression $limparAst.Extent.Text
Invoke-Expression $fitTextAst.Extent.Text
Invoke-Expression $formatGpuAst.Extent.Text
Assert-Equal (Format-GpuEtiqueta 'Intel Iris Plus Graphics 655 (Integrada)') 'IRIS PLUS 655' 'GPU Intel permanece legivel em fonte normal'
Assert-Equal (Format-GpuEtiqueta 'Apple M1 Pro (Integrada)') 'APPLE M1 PRO' 'GPU Apple permanece legivel em fonte normal'
Assert-Equal (Format-GpuEtiqueta 'NVIDIA Quadro RTX 4000 8GB Dedicada') 'Q. RTX 4000 8GB D' 'GPU dedicada preserva modelo e VRAM sem reduzir a fonte'
Assert-True ($scriptText -match '\$gpuFont\s*=\s*''2''') 'GPU do notebook usa a mesma fonte das demais configuracoes'
Assert-True ($scriptText -match '\$desktopFont\s*=\s*''2''') 'GPU do desktop usa a mesma fonte das demais configuracoes'
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
Assert-True ($scriptText -match "\`$gradeBadge\s*=\s*'GRADE C'") 'etiqueta imprime apenas GRADE C'
Assert-True ($scriptText -match "\^\(\?:GRADE\\s\+\)\?C\(\?:\\s\*-\\s\*PINTURA\\s\*\[123\]\)\?\$") 'servidor converte referencias antigas de pintura para Grade C'
Assert-True ($scriptText -match '\$mostrarBateria\s*=\s*\(-not\s+\$isDesktop') 'desktop nao imprime bateria'
Assert-True ($scriptText -match "@\('IMEI',[\s\S]*?@\('ARMAZ\.',[\s\S]*?@\('RAM',[\s\S]*?@\('BATERIA',[\s\S]*?@\('CICLOS'") 'celular imprime IMEI, armazenamento, RAM, bateria e ciclos'
Assert-True ($scriptText -match '\$isMonitor[\s\S]*?TAMANHO[\s\S]*?ENTRADAS') 'monitor imprime tamanho e entradas'
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
