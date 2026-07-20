param(
    [string]$ScriptPath = (Join-Path $PSScriptRoot 'TestarAltertag.ps1')
)

$ErrorActionPreference = 'Stop'

function Assert-Equal {
    param(
        [object]$Actual,
        [object]$Expected,
        [string]$Name
    )
    if ($Actual -ne $Expected) {
        throw "FAIL: $Name | esperado=[$Expected] atual=[$Actual]"
    }
}

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Name
    )
    if (-not $Condition) {
        throw "FAIL: $Name"
    }
}

function Assert-Throws {
    param(
        [scriptblock]$ScriptBlock,
        [string]$Name
    )
    $threw = $false
    try {
        & $ScriptBlock
    } catch {
        $threw = $true
    }
    if (-not $threw) {
        throw "FAIL: $Name"
    }
}

. $ScriptPath -Library

$envText = @'
ALTERTAG_BASE_URL=https://app.altertag.com.br
ALTERTAG_API_KEY=abc123
ALTERTAG_API_SECRET=def456
'@

$cfg = ConvertFrom-AltertagEnvText -Text $envText
Assert-Equal $cfg.BaseUrl 'https://app.altertag.com.br' 'base url'
Assert-Equal $cfg.ApiKeySet $true 'api key set'
Assert-Equal $cfg.ApiSecretSet $true 'api secret set'
Assert-Equal $cfg.ApiKeyLength 6 'api key length'
Assert-Equal $cfg.ApiSecretLength 6 'api secret length'

$dadosXml = @'
<xjx>
<cmd n="as" t="nome_cliente" p="value">CAIJ SERVICOS E COMERCIO LTDA</cmd>
<cmd n="as" t="id_cliente" p="value">39509812</cmd>
<cmd n="as" t="vendedor_pedido" p="value">HYRIDES</cmd>
<cmd n="as" t="tipo_atendimento" p="value">1</cmd>
<cmd n="as" t="id_pedido" p="value">273</cmd>
<cmd n="as" t="valor_total_pecas" p="value">5.000,00</cmd>
<cmd n="as" t="valor_total_os" p="value">5.000,00</cmd>
<cmd n="as" t="data_pedido" p="value">26/05/2026</cmd>
<cmd n="as" t="data_entrega" p="value">26/05/2026</cmd>
<cmd n="as" t="id_ordem" p="value">14820098</cmd>
</xjx>
'@

$dados = ConvertFrom-AltertagXajax -XmlText $dadosXml
Assert-Equal $dados.nome_cliente 'CAIJ SERVICOS E COMERCIO LTDA' 'cliente'
Assert-Equal $dados.id_cliente '39509812' 'id cliente'
Assert-Equal $dados.vendedor_pedido 'HYRIDES' 'vendedor'
Assert-Equal $dados.tipo_atendimento '1' 'tipo atendimento'
Assert-Equal $dados.id_pedido '273' 'numero os'
Assert-Equal $dados.id_ordem '14820098' 'id interno'
Assert-Equal $dados.valor_total_os '5.000,00' 'total os'
Assert-Equal $dados.data_pedido '26/05/2026' 'data pedido'

$produtosXml = @'
<xjx>
<cmd n="as" t="produto_salvo_1" p="value">1</cmd>
<cmd n="as" t="id_ped_produto_1" p="value">68740363</cmd>
<cmd n="as" t="desc_produto_1" p="value">Apple Macbook Pro 13&quot; I7 16Gb 256GB</cmd>
<cmd n="as" t="id_produto_1" p="value">82474640</cmd>
<cmd n="as" t="qtde_produto_1" p="value">1,00</cmd>
<cmd n="as" t="valor_unit_produto_1" p="value">5.000,00</cmd>
<cmd n="as" t="valor_total_produto_1" p="value">5.000,00</cmd>
<cmd n="as" t="valor_custo_produto_1" p="value">1.500,00</cmd>
<cmd n="as" t="produtos_carregados" p="value">1</cmd>
</xjx>
'@

$produtos = ConvertFrom-AltertagProdutosXajax -XmlText $produtosXml
Assert-Equal $produtos.Count 1 'quantidade produtos'
Assert-Equal $produtos[0].Indice 1 'indice produto'
Assert-Equal $produtos[0].Descricao 'Apple Macbook Pro 13" I7 16Gb 256GB' 'descricao produto'
Assert-Equal $produtos[0].IdProduto '82474640' 'id produto'
Assert-Equal $produtos[0].Quantidade '1,00' 'quantidade produto'
Assert-Equal $produtos[0].ValorTotal '5.000,00' 'valor total produto'

Assert-True ((Get-AltertagEndpointCandidates -BaseUrl 'https://app.altertag.com.br') -contains 'https://app.altertag.com.br/index.php?Secao=Servicos.Ordem&Modulo=Servicos') 'endpoint ordem'

$headers = New-AltertagApiHeaders -AccessToken 'abc123' -SecretAccessToken 'def456'
Assert-Equal $headers['access-token'] 'abc123' 'header access token'
Assert-Equal $headers['secret-access-token'] 'def456' 'header secret token'
Assert-Throws { Assert-VhsysSuccess -Response ([pscustomobject]@{ code = 404; status = 'error'; data = 'No query results' }) -Contexto 'teste' | Out-Null } 'vhsys json error throws'

$apiResp = @{
    code = 200
    status = 'success'
    paging = @{ total = 2 }
    data = @(
        @{ id_ordem = 14831529; id_pedido = 275; nome_cliente = 'Cliente A'; nome_tecnico = ''; vendedor_pedido = 'VITOR'; status_pedido = 'Em Aberto'; data_cad_pedido = '2026-05-27 15:33:28'; equipamento_ordem = 'ThinkPad E14'; problema_ordem = 'Tela' },
        @{ id_ordem = 14820098; id_pedido = 273; nome_cliente = 'Cliente B'; nome_tecnico = 'HYURI'; vendedor_pedido = ''; status_pedido = 'Em Aberto'; data_cad_pedido = '2026-05-26 15:24:53'; equipamento_ordem = 'MacBook'; problema_ordem = '' }
    )
} | ConvertTo-Json -Depth 6 | ConvertFrom-Json

$recentes = ConvertFrom-VhsysOrdensServico -Response $apiResp
Assert-Equal $recentes.Count 2 'quantidade os recentes'
Assert-Equal $recentes[0].IdOrdem 14831529 'id ordem recente'
Assert-Equal $recentes[0].Numero 275 'numero os recente'
Assert-Equal $recentes[0].Tecnico 'VITOR' 'tecnico fallback vendedor'
Assert-Equal $recentes[1].Tecnico 'HYURI' 'tecnico nome tecnico'
Assert-Equal (Get-VhsysNextOsNumber -Ordens $recentes) 276 'proxima os por lista'

$apiRespComArray = @{
    code = 200
    status = 'success'
    data = @(
        @{ id_ordem = @(14831529); id_pedido = @(275); nome_cliente = 'Cliente A'; vendedor_pedido = 'VITOR'; status_pedido = 'Em Aberto'; data_cad_pedido = '2026-05-27 15:33:28' }
    )
} | ConvertTo-Json -Depth 6 | ConvertFrom-Json
$recentesArray = ConvertFrom-VhsysOrdensServico -Response $apiRespComArray
Assert-Equal $recentesArray[0].IdOrdem 14831529 'id ordem scalar from array'
Assert-Equal $recentesArray[0].Numero 275 'numero scalar from array'
$statusArray = Get-VhsysOsStatusFromOrdens -Ordens $recentesArray
Assert-Equal $statusArray.ultimoSite 275 'status ultimo scalar'
Assert-Equal $statusArray.proximoDisponivel 276 'status proximo scalar'

$detalheResp = @{
    code = 200
    status = 'success'
    data = @{
        id_ordem = 14831529
        id_pedido = 275
        nome_cliente = 'Cliente A'
        nome_tecnico = ''
        vendedor_pedido = 'VITOR'
        status_pedido = 'Em Aberto'
        data_cad_pedido = '2026-05-27 15:33:28'
        equipamento_ordem = 'ThinkPad E14'
        problema_ordem = 'Tela quebrada'
        garantia_ordem = 'PF3ABC12'
        referencia_ordem = 'GRADE B'
        valor_total_os = '0.00'
    }
} | ConvertTo-Json -Depth 6 | ConvertFrom-Json
$detalhe = ConvertFrom-VhsysOrdemServicoDetalhe -Response $detalheResp
Assert-Equal $detalhe.IdOrdem 14831529 'detalhe id ordem'
Assert-Equal $detalhe.Numero 275 'detalhe numero'
Assert-Equal $detalhe.Tecnico 'VITOR' 'detalhe tecnico fallback'
Assert-Equal $detalhe.Problema 'Tela quebrada' 'detalhe problema'
Assert-Equal $detalhe.Garantia 'PF3ABC12' 'detalhe serial garantia'
Assert-Equal $detalhe.Referencia 'GRADE B' 'detalhe referencia'

$statusPayload = New-VhsysOrdemStatusPayload -Status 'Etiqueta CAIJ impressa' -Observacao 'Serial PF3ABC12 | Grade B'
Assert-Equal $statusPayload.tipo_status 'Etiqueta CAIJ impressa' 'payload status texto'
Assert-Equal $statusPayload.obs_status 'Serial PF3ABC12 | Grade B' 'payload status obs'
Assert-True ($statusPayload.data_status -match '^\d{4}-\d{2}-\d{2}$') 'payload status data'

$prodResp = @{
    code = 200
    status = 'success'
    data = @(
        @{ id_ped_produto = 68740363; id_ordem = 14820098; id_produto = 82474640; desc_produto = 'Apple Macbook Pro 13" I7 16Gb 256GB'; qtde_produto = '1.0000'; valor_total_produto = 5000 }
    )
} | ConvertTo-Json -Depth 5 | ConvertFrom-Json
$prodApi = ConvertFrom-VhsysProdutosOrdemServico -Response $prodResp
Assert-Equal $prodApi.Count 1 'produto api count'
Assert-Equal $prodApi[0].Descricao 'Apple Macbook Pro 13" I7 16Gb 256GB' 'produto api descricao'

$catalogoRespColunar = @{
    code = 200
    status = 'success'
    data = @(
        @{
            id_produto = @(82530104, 82530105)
            cod_produto = @('P035-C2F', 'P035-C3F')
            desc_produto = @('Notebook Dell Latitude 5420 i5 11th 8GB 256GB W11P', 'Notebook Dell Latitude 5420 i5 11th 16GB SSD 256 W11P')
            valor_produto = @('3000.000000', '2950.000000')
            estoque_produto = @('2.0000', '4.0000')
        }
    )
} | ConvertTo-Json -Depth 6 | ConvertFrom-Json
$catalogoColunar = ConvertFrom-VhsysProdutosCatalogo -Response $catalogoRespColunar
Assert-Equal $catalogoColunar.Count 2 'catalogo colunar count'
Assert-Equal $catalogoColunar[0].Codigo 'P035-C2F' 'catalogo colunar codigo 1'
Assert-Equal $catalogoColunar[0].IdProduto '82530104' 'catalogo colunar id 1'
Assert-Equal $catalogoColunar[0].Estoque '2.0000' 'catalogo colunar estoque 1'
Assert-Equal $catalogoColunar[1].Codigo 'P035-C3F' 'catalogo colunar codigo 2'
Assert-Equal $catalogoColunar[1].IdProduto '82530105' 'catalogo colunar id 2'
Assert-Equal $catalogoColunar[1].Estoque '4.0000' 'catalogo colunar estoque 2'

$porOs = @{ '14820098' = $prodApi }
$recentesComProduto = Add-VhsysProdutoResumoToOrdens -Ordens $recentes -ProdutosPorIdOrdem $porOs
Assert-Equal $recentesComProduto[1].Equipamento 'Apple Macbook Pro 13" I7 16Gb 256GB' 'equipamento por produto'
Assert-Equal $recentesComProduto[1].ProdutoResumo 'Apple Macbook Pro 13" I7 16Gb 256GB' 'produto resumo'

$draftOs = New-VhsysOrdemServicoPayload -Tecnico 'Vitor' -Serial 'PF3ABC12' -Referencia 'GRADE A' -Equipamento 'NOTEBOOK LENOVO T14' -Problema 'Cadastro automatico CAIJ'
Assert-Equal $draftOs.id_cliente 39509812 'payload os id cliente'
Assert-Equal $draftOs.nome_cliente 'CAIJ SERVICOS E COMERCIO LTDA' 'payload os cliente'
Assert-Equal $draftOs.vendedor_pedido 'VITOR' 'payload os vendedor'
Assert-Equal $draftOs.garantia_ordem 'PF3ABC12' 'payload os garantia'
Assert-Equal $draftOs.referencia_ordem 'GRADE A' 'payload os referencia'
Assert-Equal $draftOs.equipamento_ordem 'NOTEBOOK LENOVO T14' 'payload os equipamento'
Assert-Equal $draftOs.problema_ordem 'Cadastro automatico CAIJ' 'payload os problema'
Assert-True (-not $draftOs.Contains('obs_interno_pedido')) 'payload os sem obs interna'
Assert-Equal $draftOs.status_pedido 'Em Aberto' 'payload os status'

$draftProduto = New-VhsysOrdemProdutoPayload -IdProduto 82530104 -Descricao '5420 I5 16GB 256GB' -ValorUnitario '0.00' -IdAlmoxarifado 31196
Assert-Equal $draftProduto[0].id_produto 82530104 'payload produto id'
Assert-Equal $draftProduto[0].desc_produto '5420 I5 16GB 256GB' 'payload produto descricao'
Assert-Equal $draftProduto[0].qtde_produto '1' 'payload produto quantidade'
Assert-Equal $draftProduto[0].valor_unit_produto '0.00' 'payload produto valor'
Assert-Equal $draftProduto[0].id_almoxarifado 31196 'payload produto almoxarifado'
$draftProdutoLoc = $draftProduto[0].json_localizacoes | ConvertFrom-Json
Assert-Equal $draftProdutoLoc[0].id_almoxarifado '31196' 'payload produto localizacao almoxarifado'
Assert-Equal $draftProdutoLoc[0].desc_almoxarifado 'TÉCNICA_BT' 'payload produto localizacao nome'
Assert-Equal $draftProdutoLoc[0].qtde_saida '1,00' 'payload produto localizacao quantidade'
$draftProdutoValorRuim = New-VhsysOrdemProdutoPayload -IdProduto 82530104 -Descricao '5420 I5 16GB 256GB' -ValorUnitario '0.000000 2950.000000 3000.000000' -IdAlmoxarifado 31196
Assert-Equal $draftProdutoValorRuim[0].valor_unit_produto '0.00' 'payload produto valor invalido normalizado'
$draftProdutoSemLoc = New-VhsysOrdemProdutoPayload -IdProduto 82530104 -Descricao '5420 I5 16GB 256GB' -ValorUnitario '2950.00' -IdAlmoxarifado 31196 -SemLocalizacao
Assert-True (-not $draftProdutoSemLoc[0].PSObject.Properties['json_localizacoes']) 'payload produto fallback sem localizacao'

$draftServicos = New-VhsysOrdemServicosPayload -Servicos @('troca de bateria', 'Troca SSD', '', 'troca de tela')
Assert-Equal $draftServicos.Count 3 'payload servicos count'
Assert-Equal $draftServicos[0].desc_servico 'Troca de bateria' 'payload servico bateria'
Assert-Equal $draftServicos[0].horas_servico '1' 'payload servico bateria horas'
Assert-Equal $draftServicos[0].id_servico 0 'payload servico bateria id livre'
Assert-Equal $draftServicos[1].desc_servico 'Troca SSD' 'payload servico ssd'
Assert-Equal $draftServicos[1].horas_servico '1' 'payload servico ssd horas'
Assert-Equal $draftServicos[2].desc_servico 'Troca de tela' 'payload servico tela'

'OK: TestarAltertag tests'
