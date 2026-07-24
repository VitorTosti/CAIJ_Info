# Localizacao obrigatoria no cadastro de OS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Impedir que o InfoNotebook conclua uma OS cujo produto nao tenha sido persistido no VHSYS com a localizacao `TECNICA_BT` e o almoxarifado `31196`.

**Architecture:** O payload continuara incluindo `json_localizacoes`, mas o fallback sem localizacao sera removido. Depois do POST, o servidor consultara os produtos da OS e validara tanto o produto quanto o almoxarifado antes de adicionar servicos e concluir o job.

**Tech Stack:** Windows PowerShell 5.1, API REST VHSYS v2, testes PowerShell existentes.

## Global Constraints

- Toda OS automatica deve usar `TECNICA_BT`.
- O identificador obrigatorio do almoxarifado e `31196`.
- Uma OS sem a localizacao confirmada nunca pode ser apresentada como concluida.
- Credenciais do VHSYS nao podem aparecer em logs ou mensagens.
- O servidor nao deve excluir automaticamente uma OS parcialmente criada.

---

### Task 1: Validar a localizacao retornada pelo VHSYS

**Files:**
- Modify: `CoreCAIJ/TestarAltertag.Tests.ps1:225`
- Modify: `CoreCAIJ/TestarAltertag.ps1:410`
- Modify: `CoreCAIJ/ServidorImpressao.ps1:1260`
- Modify: `CoreCAIJ/InfoNotebookPreview.Tests.ps1:23`

**Interfaces:**
- Consumes: resposta bruta de `GET /ordens-servico/{id_os}/produtos`, `IdProduto` e `IdAlmoxarifado`.
- Produces: `Test-VhsysProdutoLocalizacao -Response <object> -IdProduto <int> -IdAlmoxarifado <int>` retornando `bool`.

- [ ] **Step 1: Escrever os testes que reproduzem a falha**

Adicionar a `CoreCAIJ/TestarAltertag.Tests.ps1`:

```powershell
$produtoComLocalizacao = @{
    data = @(
        @{
            id_produto = 82530104
            json_localizacoes = '[{"desc_almoxarifado":"TÉCNICA_BT","id_almoxarifado":"31196","qtde_saida":"1,00"}]'
        }
    )
} | ConvertTo-Json -Depth 5 | ConvertFrom-Json
$produtoSemLocalizacao = @{
    data = @(
        @{ id_produto = 82530104; json_localizacoes = $null }
    )
} | ConvertTo-Json -Depth 5 | ConvertFrom-Json
$produtoEmOutroAlmoxarifado = @{
    data = @(
        @{
            id_produto = 82530104
            json_localizacoes = '[{"desc_almoxarifado":"OUTRO","id_almoxarifado":"999","qtde_saida":"1,00"}]'
        }
    )
} | ConvertTo-Json -Depth 5 | ConvertFrom-Json

Assert-True (Test-VhsysProdutoLocalizacao -Response $produtoComLocalizacao -IdProduto 82530104 -IdAlmoxarifado 31196) 'confirma localizacao TECNICA_BT'
Assert-True (-not (Test-VhsysProdutoLocalizacao -Response $produtoSemLocalizacao -IdProduto 82530104 -IdAlmoxarifado 31196)) 'rejeita produto sem localizacao'
Assert-True (-not (Test-VhsysProdutoLocalizacao -Response $produtoEmOutroAlmoxarifado -IdProduto 82530104 -IdAlmoxarifado 31196)) 'rejeita outro almoxarifado'
```

Substituir o teste do fallback por verificacoes estaticas em `CoreCAIJ/InfoNotebookPreview.Tests.ps1`:

```powershell
Assert-True ($serverText -match 'Test-VhsysProdutoLocalizacao') 'servidor confirma localizacao depois do cadastro'
Assert-True ($serverText -notmatch '-SemLocalizacao') 'servidor nao permite fallback sem localizacao'
Assert-True ($serverText -notmatch 'tentando sem localizacao') 'servidor nao mascara falha da localizacao'
```

- [ ] **Step 2: Executar os testes e confirmar a falha esperada**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File CoreCAIJ\TestarAltertag.Tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File CoreCAIJ\InfoNotebookPreview.Tests.ps1
```

Expected: o primeiro teste falha porque `Test-VhsysProdutoLocalizacao` ainda nao existe; o segundo falha porque o servidor ainda contem `-SemLocalizacao`.

- [ ] **Step 3: Implementar o validador minimo**

Adicionar a mesma funcao de biblioteca em `CoreCAIJ/TestarAltertag.ps1` e `CoreCAIJ/ServidorImpressao.ps1`, logo depois de `New-VhsysOrdemProdutoPayload`:

```powershell
function Test-VhsysProdutoLocalizacao {
    param(
        [Parameter(Mandatory=$true)]$Response,
        [Parameter(Mandatory=$true)][int]$IdProduto,
        [Parameter(Mandatory=$true)][int]$IdAlmoxarifado
    )

    foreach ($produto in @($Response.data)) {
        if ([int]$produto.id_produto -ne $IdProduto) { continue }
        $jsonLocalizacoes = ([string]$produto.json_localizacoes).Trim()
        if (-not $jsonLocalizacoes) { return $false }
        try {
            foreach ($localizacao in @($jsonLocalizacoes | ConvertFrom-Json)) {
                if ([int]$localizacao.id_almoxarifado -eq $IdAlmoxarifado) {
                    return $true
                }
            }
        } catch {
            return $false
        }
        return $false
    }
    return $false
}
```

Remover o parametro `[switch]$SemLocalizacao` e tornar `json_localizacoes` parte incondicional de `New-VhsysOrdemProdutoPayload`.

- [ ] **Step 4: Executar os testes da biblioteca**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File CoreCAIJ\TestarAltertag.Tests.ps1
```

Expected: `OK: TestarAltertag tests`.

- [ ] **Step 5: Commitar o validador e seus testes**

```powershell
git add CoreCAIJ/TestarAltertag.ps1 CoreCAIJ/TestarAltertag.Tests.ps1
git commit -m "test: valida localizacao dos produtos da OS"
```

### Task 2: Falhar o cadastro quando a localizacao nao for persistida

**Files:**
- Modify: `CoreCAIJ/ServidorImpressao.ps1:1364`
- Modify: `CoreCAIJ/InfoNotebookPreview.Tests.ps1:23`
- Deploy: `C:\Users\Usuário\Desktop\ServidorImpressao.ps1`

**Interfaces:**
- Consumes: `Test-VhsysProdutoLocalizacao` criado na Task 1 e resposta de `Invoke-VhsysJson`.
- Produces: `Add-VhsysProdutoNaOrdemServico` que so retorna quando produto e localizacao estao confirmados.

- [ ] **Step 1: Completar o teste estatico do comportamento obrigatorio**

Adicionar a `CoreCAIJ/InfoNotebookPreview.Tests.ps1`:

```powershell
Assert-True ($serverText -match 'Produto da OS .* nao confirmou a localizacao T.+CNICA_BT') 'servidor informa localizacao ausente'
```

- [ ] **Step 2: Executar o teste e confirmar a falha esperada**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File CoreCAIJ\InfoNotebookPreview.Tests.ps1
```

Expected: `FAIL: servidor informa localizacao ausente`.

- [ ] **Step 3: Remover o fallback e exigir confirmacao por leitura**

Substituir o bloco de POST e confirmacao em `Add-VhsysProdutoNaOrdemServico` por:

```powershell
$prodPath = "/ordens-servico/{0}/produtos" -f $IdOrdem
$prodPayload = New-VhsysOrdemProdutoPayload `
    -IdProduto $IdProduto `
    -Descricao $ProdutoDescricao `
    -ValorUnitario $ProdutoValor `
    -IdAlmoxarifado $almoxarifadoBancadaTecnicaId
$prodResp = Invoke-VhsysJson -Config $Config -Path $prodPath -Method 'Post' -Body $prodPayload -TimeoutSec 25

$prodCheck = Invoke-VhsysJson -Config $Config -Path $prodPath -Method 'Get' -TimeoutSec 15
$produtoConfirmado = @($prodCheck.data | Where-Object {
    [int]$_.id_produto -eq $IdProduto -or
    ([string]$_.desc_produto).Trim() -eq $ProdutoDescricao.Trim()
}).Count -gt 0

if (-not $produtoConfirmado) {
    throw "OS $IdPedido nao confirmou o produto pela API. Verifique a OS manualmente antes de continuar."
}
if (-not (Test-VhsysProdutoLocalizacao -Response $prodCheck -IdProduto $IdProduto -IdAlmoxarifado $almoxarifadoBancadaTecnicaId)) {
    throw "Produto da OS $IdPedido nao confirmou a localizacao TÉCNICA_BT. A OS nao foi concluida; corrija a localizacao manualmente."
}

return $prodResp
```

O erro original do POST deve continuar subindo pelo tratamento existente do job. Nao incluir token, secret ou cabecalhos na mensagem.

- [ ] **Step 4: Executar testes e parser**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File CoreCAIJ\TestarAltertag.Tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File CoreCAIJ\InfoNotebookPreview.Tests.ps1
powershell -NoProfile -Command "$errors=$null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'CoreCAIJ\ServidorImpressao.ps1'),[ref]$null,[ref]$errors) | Out-Null; if($errors){$errors | ForEach-Object {$_.Message}; exit 1}; 'OK: parser'"
git diff --check
```

Expected: os dois testes terminam com `OK`, o parser imprime `OK: parser` e `git diff --check` nao aponta erros.

- [ ] **Step 5: Sincronizar o servidor operacional**

Antes da copia, confirmar os caminhos:

```powershell
$source = (Resolve-Path 'CoreCAIJ\ServidorImpressao.ps1').Path
$destination = 'C:\Users\Usuário\Desktop\ServidorImpressao.ps1'
if ($source -notlike 'C:\Users\Usuário\Desktop\1 - CAIJ\*') { throw 'Origem inesperada' }
if ([System.IO.Path]::GetFullPath($destination) -ne 'C:\Users\Usuário\Desktop\ServidorImpressao.ps1') { throw 'Destino inesperado' }
Copy-Item -LiteralPath $source -Destination $destination -Force
```

Comparar os hashes:

```powershell
$repoHash = (Get-FileHash -LiteralPath 'CoreCAIJ\ServidorImpressao.ps1' -Algorithm SHA256).Hash
$operationalHash = (Get-FileHash -LiteralPath 'C:\Users\Usuário\Desktop\ServidorImpressao.ps1' -Algorithm SHA256).Hash
if ($repoHash -ne $operationalHash) { throw 'Servidor operacional diferente do arquivo versionado' }
'OK: servidor sincronizado'
```

Expected: `OK: servidor sincronizado`.

- [ ] **Step 6: Reiniciar e verificar sem criar uma OS**

Reiniciar o servidor pela rotina administrativa ja usada no PC principal. Em seguida:

```powershell
$status = Invoke-RestMethod -Uri 'http://127.0.0.1:9100/status' -Method Get -TimeoutSec 8
if ($status.status -ne 'ok') { throw 'Servidor nao respondeu OK' }
$recentes = Invoke-RestMethod -Uri 'http://127.0.0.1:9100/os-recentes?limit=1&produtos=true' -Method Get -TimeoutSec 20
if ($recentes.status -ne 'ok') { throw 'Consulta VHSYS nao respondeu OK' }
'OK: servidor e consulta VHSYS'
```

Expected: `OK: servidor e consulta VHSYS`. A validacao final de escrita sera feita na proxima OS real cadastrada pelo operador, evitando gerar registro artificial.

- [ ] **Step 7: Commitar a correcao**

```powershell
git add CoreCAIJ/ServidorImpressao.ps1 CoreCAIJ/InfoNotebookPreview.Tests.ps1
git commit -m "fix: exige localizacao nos produtos da OS"
```
