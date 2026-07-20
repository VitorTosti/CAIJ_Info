param(
    [switch]$Library,
    [switch]$ShowConfig,
    [switch]$Discover,
    [switch]$ListOs,
    [string]$EnvPath = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'CAIJ\altertag.env'),
    [string]$ParseDadosFile,
    [string]$ParseProdutosFile,
    [int]$TimeoutSec = 8
)

$ErrorActionPreference = 'Stop'

function ConvertFrom-AltertagEnvText {
    param([Parameter(Mandatory=$true)][string]$Text)

    $values = @{}
    foreach ($line in ($Text -split "`r?`n")) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }
        $parts = $trimmed -split '=', 2
        if ($parts.Count -ne 2) { continue }
        $key = $parts[0].Trim()
        $value = $parts[1].Trim().Trim('"').Trim("'")
        $values[$key] = $value
    }

    $baseUrl = [string]$values['ALTERTAG_BASE_URL']
    if ($baseUrl) { $baseUrl = $baseUrl.TrimEnd('/') }
    $apiKey = [string]$values['ALTERTAG_API_KEY']
    $apiSecret = [string]$values['ALTERTAG_API_SECRET']

    [pscustomobject]@{
        BaseUrl = $baseUrl
        ApiBaseUrl = if ($values['ALTERTAG_API_BASE_URL']) { ([string]$values['ALTERTAG_API_BASE_URL']).TrimEnd('/') } else { 'https://api.vhsys.com/v2' }
        AccessToken = $apiKey
        SecretAccessToken = $apiSecret
        ApiKeySet = -not [string]::IsNullOrWhiteSpace($apiKey)
        ApiSecretSet = -not [string]::IsNullOrWhiteSpace($apiSecret)
        ApiKeyLength = if ($apiKey) { $apiKey.Length } else { 0 }
        ApiSecretLength = if ($apiSecret) { $apiSecret.Length } else { 0 }
    }
}

function Read-AltertagConfig {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Arquivo de configuracao nao encontrado: $Path"
    }
    ConvertFrom-AltertagEnvText -Text (Get-Content -LiteralPath $Path -Raw)
}

function Get-AltertagEndpointCandidates {
    param([Parameter(Mandatory=$true)][string]$BaseUrl)

    $root = $BaseUrl.TrimEnd('/')
    @(
        $root,
        "$root/api",
        "$root/api/v1",
        "$root/webservice",
        "$root/index.php?Secao=Servicos.Ordem&Modulo=Servicos"
    )
}

function ConvertFrom-AltertagXajax {
    param([Parameter(Mandatory=$true)][string]$XmlText)

    $text = $XmlText.Trim()
    if ($text -notmatch '<xjx[\s>]') {
        $text = "<xjx>$text</xjx>"
    }

    $result = [ordered]@{}
    try {
        [xml]$xml = $text
        foreach ($cmd in $xml.SelectNodes('//cmd[@n="as"]')) {
            $target = [string]$cmd.t
            $prop = [string]$cmd.p
            if (-not $target -or $prop -ne 'value') { continue }
            $result[$target] = [System.Net.WebUtility]::HtmlDecode($cmd.InnerText)
        }
    } catch {
        $pattern = '<cmd\s+[^>]*n="as"[^>]*t="([^"]+)"[^>]*p="value"[^>]*>(.*?)</cmd>'
        foreach ($m in [regex]::Matches($text, $pattern, 'Singleline')) {
            $result[$m.Groups[1].Value] = [System.Net.WebUtility]::HtmlDecode($m.Groups[2].Value)
        }
    }

    [pscustomobject]$result
}

function ConvertFrom-AltertagProdutosXajax {
    param([Parameter(Mandatory=$true)][string]$XmlText)

    $fields = ConvertFrom-AltertagXajax -XmlText $XmlText
    $groups = @{}
    $produtos = @()
    foreach ($prop in $fields.PSObject.Properties) {
        if ($prop.Name -match '^(produto_salvo|id_ped_produto|desc_produto|id_produto|qtde_produto|valor_unit_produto|valor_total_produto|valor_custo_produto)_(\d+)$') {
            $field = $matches[1]
            $idx = [int]$matches[2]
            if (-not $groups.ContainsKey($idx)) { $groups[$idx] = @{} }
            $groups[$idx][$field] = $prop.Value
        }
    }

    foreach ($idx in ($groups.Keys | Sort-Object)) {
        $item = $groups[$idx]
        $produtos += [pscustomobject]@{
            Indice = $idx
            Salvo = $item['produto_salvo']
            IdItemOs = $item['id_ped_produto']
            IdProduto = $item['id_produto']
            Descricao = $item['desc_produto']
            Quantidade = $item['qtde_produto']
            ValorUnitario = $item['valor_unit_produto']
            ValorTotal = $item['valor_total_produto']
            ValorCusto = $item['valor_custo_produto']
        }
    }
    return ,$produtos
}

function Test-AltertagEndpoint {
    param(
        [Parameter(Mandatory=$true)][string]$Url,
        [int]$TimeoutSec = 8
    )

    try {
        $resp = Invoke-WebRequest -Uri $Url -Method GET -UseBasicParsing -TimeoutSec $TimeoutSec -MaximumRedirection 0 -ErrorAction Stop
        [pscustomobject]@{ Url = $Url; Status = [int]$resp.StatusCode; Result = 'OK' }
    } catch {
        $status = $null
        if ($_.Exception.Response) {
            try { $status = [int]$_.Exception.Response.StatusCode } catch {}
        }
        [pscustomobject]@{ Url = $Url; Status = $status; Result = $_.Exception.Message }
    }
}

function New-AltertagApiHeaders {
    param(
        [Parameter(Mandatory=$true)][string]$AccessToken,
        [Parameter(Mandatory=$true)][string]$SecretAccessToken
    )

    @{
        'access-token' = $AccessToken
        'secret-access-token' = $SecretAccessToken
        'Cache-Control' = 'no-cache'
        'User-Agent' = 'CAIJ-TesteAltertag/0.2'
        'Content-Type' = 'application/json'
    }
}

function Assert-VhsysSuccess {
    param(
        [Parameter(Mandatory=$true)]$Response,
        [string]$Contexto = 'API vhsys'
    )

    if ($Response.PSObject.Properties['status'] -and [string]$Response.status -and [string]$Response.status -ne 'success') {
        $msg = if ($Response.PSObject.Properties['message'] -and $Response.message) { [string]$Response.message } elseif ($Response.PSObject.Properties['data'] -and $Response.data) { [string]$Response.data } else { 'resposta sem sucesso' }
        throw "$Contexto retornou erro: $msg"
    }
    if ($Response.PSObject.Properties['code'] -and [string]$Response.code -match '^\d+$' -and [int]$Response.code -ge 400) {
        $msg = if ($Response.PSObject.Properties['message'] -and $Response.message) { [string]$Response.message } elseif ($Response.PSObject.Properties['data'] -and $Response.data) { [string]$Response.data } else { 'resposta sem sucesso' }
        throw "$Contexto retornou erro $($Response.code): $msg"
    }
    return $Response
}

function ConvertFrom-VhsysOrdensServico {
    param([Parameter(Mandatory=$true)]$Response)

    function Get-FirstValue {
        param($Value)
        if ($null -eq $Value) { return $null }
        while ($Value -is [array]) {
            $arr = @($Value)
            if ($arr.Count -lt 1) { return $null }
            $Value = $arr[0]
        }
        return $Value
    }

    $ordens = @()
    foreach ($item in @($Response.data)) {
        if (-not $item) { continue }
        $tecnico = ''
        if ($item.nome_tecnico) { $tecnico = [string]$item.nome_tecnico }
        elseif ($item.vendedor_pedido) { $tecnico = [string]$item.vendedor_pedido }

        $idOrdem = Get-FirstValue $item.id_ordem
        $numero = Get-FirstValue $item.id_pedido
        $ordens += [pscustomobject]@{
            IdOrdem = [int]$idOrdem
            Numero = [int]$numero
            Cliente = [string]$item.nome_cliente
            Tecnico = $tecnico
            Status = [string]$item.status_pedido
            DataCadastro = [string]$item.data_cad_pedido
            Equipamento = [string]$item.equipamento_ordem
            Problema = [string]$item.problema_ordem
        }
    }
    return ,$ordens
}

function ConvertFrom-VhsysOrdemServicoDetalhe {
    param([Parameter(Mandatory=$true)]$Response)

    $item = $Response.data
    if ($item -is [array]) { $item = @($item)[0] }
    if (-not $item) { throw 'API vhsys nao retornou detalhe da ordem de servico.' }

    $tecnico = ''
    if ($item.nome_tecnico) { $tecnico = [string]$item.nome_tecnico }
    elseif ($item.vendedor_pedido) { $tecnico = [string]$item.vendedor_pedido }

    [pscustomobject]@{
        IdOrdem = [int]$item.id_ordem
        Numero = [int]$item.id_pedido
        Cliente = [string]$item.nome_cliente
        Tecnico = $tecnico
        Status = [string]$item.status_pedido
        DataCadastro = [string]$item.data_cad_pedido
        DataPedido = [string]$item.data_pedido
        Equipamento = [string]$item.equipamento_ordem
        Problema = [string]$item.problema_ordem
        Garantia = [string]$item.garantia_ordem
        Referencia = [string]$item.referencia_ordem
        ValorTotal = [string]$item.valor_total_os
    }
}

function Get-VhsysNextOsNumber {
    param([object[]]$Ordens)

    $max = 0
    foreach ($os in @($Ordens)) {
        if ($os.Numero -and [int]$os.Numero -gt $max) { $max = [int]$os.Numero }
    }
    if ($max -lt 1) { return $null }
    return ($max + 1)
}

function Get-VhsysOrdensServicoRecentes {
    param(
        [Parameter(Mandatory=$true)]$Config,
        [int]$Limit = 10,
        [int]$TimeoutSec = 12
    )

    if (-not $Config.AccessToken -or -not $Config.SecretAccessToken) {
        throw 'ALTERTAG_API_KEY e ALTERTAG_API_SECRET precisam estar preenchidos.'
    }
    $base = if ($Config.ApiBaseUrl) { [string]$Config.ApiBaseUrl } else { 'https://api.vhsys.com/v2' }
    $uri = '{0}/ordens-servico?limit={1}&offset=0&lixeira=Nao&order=id_pedido&sort=desc' -f $base.TrimEnd('/'), $Limit
    $headers = New-AltertagApiHeaders -AccessToken $Config.AccessToken -SecretAccessToken $Config.SecretAccessToken
    $resp = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers -TimeoutSec $TimeoutSec -ErrorAction Stop
    ConvertFrom-VhsysOrdensServico -Response $resp | ForEach-Object { $_ }
}

function ConvertFrom-VhsysProdutosOrdemServico {
    param([Parameter(Mandatory=$true)]$Response)

    $produtos = @()
    foreach ($item in @($Response.data)) {
        if (-not $item) { continue }
        $produtos += [pscustomobject]@{
            IdItemOs = [string]$item.id_ped_produto
            IdOrdem = [string]$item.id_ordem
            IdProduto = [string]$item.id_produto
            Descricao = [string]$item.desc_produto
            Quantidade = [string]$item.qtde_produto
            ValorTotal = [string]$item.valor_total_produto
        }
    }
    return ,$produtos
}

function ConvertFrom-VhsysProdutosCatalogo {
    param([Parameter(Mandatory=$true)]$Response)

    function Get-IndexedValue {
        param($Value, [int]$Index)
        if ($null -eq $Value) { return '' }
        $arr = @($Value)
        if ($arr.Count -gt 1) {
            if ($Index -lt $arr.Count) { return [string]$arr[$Index] }
            return ''
        }
        return [string]$Value
    }

    $produtos = @()
    foreach ($item in @($Response.data)) {
        if (-not $item) { continue }

        $campos = @('id_produto','cod_produto','desc_produto','valor_produto','estoque_produto','estoque','saldo_produto','saldo_estoque','qtd_estoque','quantidade','qtde')
        $maxCount = 1
        foreach ($campo in $campos) {
            if ($item.PSObject.Properties[$campo]) {
                $count = @($item.$campo).Count
                if ($count -gt $maxCount) { $maxCount = $count }
            }
        }

        for ($idx = 0; $idx -lt $maxCount; $idx++) {
            $cod = (Get-IndexedValue $item.cod_produto $idx).Trim()
            $desc = (Get-IndexedValue $item.desc_produto $idx).Trim()
            if (-not $cod -and -not $desc) { continue }

            $estoque = ''
            foreach ($campoEstoque in @('estoque_produto','estoque','saldo_produto','saldo_estoque','qtd_estoque','quantidade','qtde')) {
                if ($item.PSObject.Properties[$campoEstoque]) {
                    $valorEstoque = (Get-IndexedValue $item.$campoEstoque $idx).Trim()
                    if ($valorEstoque) {
                        $estoque = $valorEstoque
                        break
                    }
                }
            }

            $produtos += [pscustomobject]@{
                IdProduto = (Get-IndexedValue $item.id_produto $idx).Trim()
                Codigo = $cod
                Descricao = $desc
                Valor = (Get-IndexedValue $item.valor_produto $idx).Trim()
                Estoque = $estoque
                Texto = if ($cod) { ('{0} - {1}' -f $cod, $desc) } else { $desc }
            }
        }
    }
    return ,$produtos
}

function Add-VhsysProdutoResumoToOrdens {
    param(
        [Parameter(Mandatory=$true)][object[]]$Ordens,
        [hashtable]$ProdutosPorIdOrdem = @{}
    )

    foreach ($os in @($Ordens)) {
        $produtos = @()
        if ($ProdutosPorIdOrdem.ContainsKey([string]$os.IdOrdem)) {
            $produtos = @($ProdutosPorIdOrdem[[string]$os.IdOrdem])
        }
        $nomes = @($produtos | ForEach-Object { [string]$_.Descricao } | Where-Object { $_.Trim() -ne '' })
        $resumo = if ($nomes.Count -gt 0) { $nomes -join ' | ' } else { [string]$os.Equipamento }
        $os | Add-Member -NotePropertyName ProdutoResumo -NotePropertyValue $resumo -Force
        if ($nomes.Count -gt 0 -and $resumo) {
            $os.Equipamento = $resumo
        }
    }
    return ,$Ordens
}

function Format-CaijServicoNome {
    param([string]$Nome)

    $n = ([string]$Nome).Trim()
    if (-not $n) { return '' }
    switch -Regex ($n) {
        '^(?i)troca\s+ssd$' { return 'Troca SSD' }
        '^(?i)troca\s+ram$' { return 'Troca de memoria RAM' }
        default {
            $ti = (Get-Culture).TextInfo
            return $ti.ToTitleCase($n.ToLower())
        }
    }
}

function Normalize-VhsysValorUnitario {
    param([string]$Valor)

    $v = ([string]$Valor).Trim()
    if (-not $v) { return '0.00' }
    if ($v -match '\s') { return '0.00' }
    if ($v -notmatch '^\d+(?:[,.]\d+)?$') { return '0.00' }
    return $v.Replace(',', '.')
}

function New-VhsysOrdemServicoPayload {
    param(
        [string]$Tecnico,
        [string]$Serial,
        [string]$Referencia,
        [string]$Equipamento,
        [string]$Problema = ''
    )

    [ordered]@{
        id_cliente = 39509812
        nome_cliente = 'CAIJ SERVICOS E COMERCIO LTDA'
        vendedor_pedido = ([string]$Tecnico).Trim().ToUpper()
        data_pedido = (Get-Date).ToString('yyyy-MM-dd')
        garantia_ordem = ([string]$Serial).Trim()
        equipamento_ordem = ([string]$Equipamento).Trim()
        problema_ordem = ([string]$Problema).Trim()
        referencia_ordem = ([string]$Referencia).Trim()
        status_pedido = 'Em Aberto'
    }
}

function New-VhsysOrdemProdutoPayload {
    param(
        [Parameter(Mandatory=$true)][int]$IdProduto,
        [Parameter(Mandatory=$true)][string]$Descricao,
        [string]$ValorUnitario = '0.00',
        [int]$IdAlmoxarifado = 31196,
        [switch]$SemLocalizacao
    )

    $payload = [ordered]@{
        qtde_produto = '1'
        id_produto = $IdProduto
        valor_unit_produto = Normalize-VhsysValorUnitario $ValorUnitario
        desc_produto = ([string]$Descricao).Trim()
        id_almoxarifado = $IdAlmoxarifado
    }

    if (-not $SemLocalizacao) {
        $payload.json_localizacoes = @(
            [ordered]@{
                desc_almoxarifado = 'TÉCNICA_BT'
                id_almoxarifado = ([string]$IdAlmoxarifado)
                controla_lote = '0'
                qtde_atual = '1,00'
                qtde_saida = '1,00'
                id_lote = '0'
            }
        ) | ConvertTo-Json -Compress
    }

    @([pscustomobject]$payload)
}

function New-VhsysOrdemServicosPayload {
    param([object[]]$Servicos)

    $out = @()
    foreach ($svc in @($Servicos)) {
        $nome = Format-CaijServicoNome -Nome ([string]$svc)
        if (-not $nome) { continue }
        $out += [pscustomobject]([ordered]@{
            horas_servico = '1'
            id_servico = 0
            valor_unit_servico = '0.00'
            desc_servico = $nome
        })
    }
    return ,$out
}

function Get-VhsysOsStatusFromOrdens {
    param([object[]]$Ordens)

    if (-not $Ordens -or $Ordens.Count -eq 0) { throw 'API vhsys nao retornou ordens de servico.' }
    $ultima = @($Ordens | ForEach-Object { $_ } | Sort-Object -Property Numero -Descending | Select-Object -First 1)[0]
    $ultimoApi = [int](@($ultima.Numero)[0])
    [pscustomobject]@{
        ok = $true
        ultimoSite = $ultimoApi
        proximoDisponivel = $ultimoApi + 1
    }
}

function New-VhsysOrdemStatusPayload {
    param(
        [Parameter(Mandatory=$true)][string]$Status,
        [string]$Observacao = ''
    )

    [ordered]@{
        tipo_status = ([string]$Status).Trim()
        obs_status = ([string]$Observacao).Trim()
        data_status = (Get-Date).ToString('yyyy-MM-dd')
    }
}

if ($Library) { return }

$config = Read-AltertagConfig -Path $EnvPath

if ($ShowConfig -or (-not $Discover -and -not $ListOs -and -not $ParseDadosFile -and -not $ParseProdutosFile)) {
    Write-Host 'Configuracao Altertag:'
    Write-Host ("  Arquivo: {0}" -f $EnvPath)
    Write-Host ("  Base URL: {0}" -f $config.BaseUrl)
    Write-Host ("  API Base URL: {0}" -f $config.ApiBaseUrl)
    Write-Host ("  API Key: {0} ({1} caracteres)" -f $(if ($config.ApiKeySet) { 'SET' } else { 'EMPTY' }), $config.ApiKeyLength)
    Write-Host ("  API Secret: {0} ({1} caracteres)" -f $(if ($config.ApiSecretSet) { 'SET' } else { 'EMPTY' }), $config.ApiSecretLength)
}

if ($Discover) {
    if (-not $config.BaseUrl) { throw 'ALTERTAG_BASE_URL esta vazio.' }
    Write-Host ''
    Write-Host 'Testando endpoints sem imprimir credenciais:'
    Get-AltertagEndpointCandidates -BaseUrl $config.BaseUrl |
        ForEach-Object { Test-AltertagEndpoint -Url $_ -TimeoutSec $TimeoutSec } |
        Format-Table -AutoSize
}

if ($ListOs) {
    Write-Host ''
    Write-Host 'Consultando OS recentes via API oficial vhsys:'
    $ordens = Get-VhsysOrdensServicoRecentes -Config $config -Limit 10 -TimeoutSec $TimeoutSec
    $ordens | Select-Object Numero,IdOrdem,Tecnico,Status,DataCadastro,Equipamento | Format-Table -AutoSize
    $proxima = Get-VhsysNextOsNumber -Ordens $ordens
    if ($proxima) { Write-Host ("Proxima sugerida pela API: C000{0}" -f $proxima) }
}

if ($ParseDadosFile) {
    $dados = ConvertFrom-AltertagXajax -XmlText (Get-Content -LiteralPath $ParseDadosFile -Raw)
    $dados | Format-List
}

if ($ParseProdutosFile) {
    $produtos = ConvertFrom-AltertagProdutosXajax -XmlText (Get-Content -LiteralPath $ParseProdutosFile -Raw)
    $produtos | Format-Table -AutoSize
}
