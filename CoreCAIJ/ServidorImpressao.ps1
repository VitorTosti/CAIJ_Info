# ================================================
#  CAIJ INFORMATICA - SERVIDOR DE IMPRESSAO v5
#  Roda no PC principal (.54) como Administrador
#  Recebe JSON, monta TSPL 80x50mm e imprime
# ================================================

$porta      = 9100
$impressora = 'LABEL'
$clientePadrao = 'CAIJ SERVICOS E COMERCIO LTDA'
$clientePadraoId = 39509812
$almoxarifadoBancadaTecnicaId = 31196
$tecnicosPermitidos = @('HYURI', 'HYRIDES', 'VITOR', 'LUCAS', 'ERICK')
$mapaProdutosArquivo = Join-Path (Split-Path -Parent $PSCommandPath) 'mapa_produtos.json'
$desktopUsuario = [Environment]::GetFolderPath('Desktop')
$produtosCsvPadrao = Join-Path $desktopUsuario 'produtos_1019993.csv'
$estadoOsArquivo = Join-Path (Split-Path -Parent $PSCommandPath) 'estado_os.json'
$altertagEnvArquivo = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'CAIJ\altertag.env'
$altertagApiBaseUrlPadrao = 'https://api.vhsys.com/v2'
$mutexOsName = 'Global\CAIJ_OS_MUTEX'
$autoSyncIntervalMin = 30
$braveDebugPort = 9222
$braveDebugPortFallback = 9333
$braveAutomationProfile = Join-Path $env:LOCALAPPDATA 'CAIJ\BraveAltertagProfile'
$script:produtosCsvCache = $null
$script:produtosCsvCachePath = $null
$script:produtosCsvCacheStamp = $null
$script:triagemQueue = New-Object System.Collections.ArrayList
$script:triagemJobs = @{}
$script:triagemLock = New-Object object
$script:triagemWorkerBusy = $false
$script:printLock = New-Object object

Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class CaijWin32 {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@

function Get-BravePath {
    $paths = @(
        'C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe',
        'C:\Program Files (x86)\BraveSoftware\Brave-Browser\Application\brave.exe'
    )
    foreach ($p in $paths) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Test-BraveDebug {
    param([int]$Port = $braveDebugPort)
    try {
        Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/version" -TimeoutSec 1 -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Start-BraveAutomation {
    param([string]$Url)

    $bravePath = Get-BravePath
    if (-not $bravePath) { throw 'Brave nao encontrado. Instale o Brave no PC principal.' }

    if (-not (Test-Path $braveAutomationProfile)) {
        New-Item -ItemType Directory -Path $braveAutomationProfile -Force | Out-Null
    }

    $portsTentativa = @($braveDebugPort, $braveDebugPortFallback)
    $started = $false
    foreach ($p in $portsTentativa) {
        if (Test-BraveDebug -Port $p) {
            $script:braveDebugPort = $p
            $started = $true
            break
        }

        $args = @(
            "--remote-debugging-port=$p"
            '--remote-debugging-address=127.0.0.1'
            "--user-data-dir=$braveAutomationProfile"
            '--no-first-run'
            '--disable-features=Translate'
            '--new-window'
            $Url
        )
        Start-Process -FilePath $bravePath -ArgumentList $args -WindowStyle Normal | Out-Null
        for ($i = 0; $i -lt 60; $i++) {
            Start-Sleep -Milliseconds 500
            if (Test-BraveDebug -Port $p) {
                $script:braveDebugPort = $p
                $started = $true
                break
            }
        }
        if ($started) { break }
    }

    if (-not $started -and -not (Test-BraveDebug -Port $script:braveDebugPort)) {
        throw "Nao foi possivel iniciar o Brave em modo de automacao (portas testadas: $($portsTentativa -join ', '))."
    }

    try {
        $encoded = [System.Uri]::EscapeDataString($Url)
        Invoke-RestMethod -Method Put -Uri "http://127.0.0.1:$script:braveDebugPort/json/new?$encoded" -TimeoutSec 5 -ErrorAction Stop | Out-Null
    } catch {
        Start-Process -FilePath $bravePath -ArgumentList @("--user-data-dir=$braveAutomationProfile", $Url) -WindowStyle Normal | Out-Null
    }

    Start-Sleep -Seconds 2
}

function Get-BravePageTarget {
    param([string]$UrlPart)
    $targets = Invoke-RestMethod -Uri "http://127.0.0.1:$script:braveDebugPort/json" -TimeoutSec 5 -ErrorAction Stop
    $target = @($targets | Where-Object { $_.type -eq 'page' -and $_.url -like "*$UrlPart*" } | Select-Object -First 1)
    if (-not $target) {
        $target = @($targets | Where-Object { $_.type -eq 'page' } | Select-Object -First 1)
    }
    if (-not $target -or -not $target.webSocketDebuggerUrl) { throw 'Nenhuma aba do Brave disponivel para automacao.' }
    return $target.webSocketDebuggerUrl
}

function Invoke-BraveRuntimeEvaluate {
    param(
        [string]$WebSocketUrl,
        [string]$Expression
    )

    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $ct = [System.Threading.CancellationToken]::None
    if (-not $ws.ConnectAsync([Uri]$WebSocketUrl, $ct).Wait(10000)) {
        throw 'Timeout ao conectar no Brave DevTools.'
    }

    $payload = @{
        id = 1
        method = 'Runtime.evaluate'
        params = @{
            expression = $Expression
            awaitPromise = $true
            returnByValue = $true
        }
    } | ConvertTo-Json -Depth 20 -Compress

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
    if (-not $ws.SendAsync([System.ArraySegment[byte]]::new($bytes), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait(10000)) {
        throw 'Timeout ao enviar automacao ao Brave.'
    }

    $buffer = New-Object byte[] 1048576
    $deadline = (Get-Date).AddSeconds(25)
    while ((Get-Date) -lt $deadline) {
        $text = ''
        while ($true) {
            $seg = [System.ArraySegment[byte]]::new($buffer)
            $task = $ws.ReceiveAsync($seg, $ct)
            if (-not $task.Wait(3000)) { throw 'Timeout aguardando resposta do Brave DevTools.' }
            $recv = $task.Result
            $text += [System.Text.Encoding]::UTF8.GetString($buffer, 0, $recv.Count)
            if ($recv.EndOfMessage) { break }
        }

        if (-not $text) { continue }
        try {
            $msg = $text | ConvertFrom-Json -ErrorAction Stop
            if ($msg.id -eq 1) {
                try { $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, 'done', $ct).Wait(1500) | Out-Null } catch {}
                return $msg
            }
        } catch {}
    }
    throw 'Timeout aguardando retorno da automacao do Brave.'
}

function Search-AltertagOptions {
    param(
        [string]$Tipo,
        [string]$Termo,
        [string]$Modo = ''
    )

    $url = 'https://app.altertag.com.br/index.php?Secao=Servicos.Ordem&Modulo=Servicos#!cadastrar'
    Start-BraveAutomation -Url $url

    $data = @{
        tipo = $Tipo
        termo = $Termo
        modo = $Modo
    } | ConvertTo-Json -Compress

    $js = @"
(async function(){
  const data = $data;
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const norm = s => (s || '').toString().normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().trim();
  const visible = el => {
    if(!el) return false;
    const r = el.getBoundingClientRect();
    const st = getComputedStyle(el);
    return r.width > 1 && r.height > 1 && st.display !== 'none' && st.visibility !== 'hidden';
  };
  function setVal(el, value){
    el.focus();
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')?.set;
    if(setter) setter.call(el, value); else el.value = value;
    el.dispatchEvent(new Event('input', {bubbles:true}));
    el.dispatchEvent(new Event('change', {bubbles:true}));
    el.dispatchEvent(new KeyboardEvent('keyup', {key:value.slice(-1) || 'a', bubbles:true}));
  }
  function queryVariants(term){
    const raw = (term || '').trim();
    const out = [];
    if(raw) out.push(raw);
    const up = raw.toUpperCase();
    if(/^E\d{2,3}$/.test(up)) out.push('Notebook Lenovo ' + up);
    if(/^T\d{2,3}$/.test(up)) out.push('Notebook Lenovo ' + up);
    if(/^VOSTRO\s*\d{3,4}$/i.test(raw)) out.push('Notebook Dell ' + raw.replace(/\s+/g,' ').trim());
    if(/^3\d{3}$/.test(raw)) out.push('Notebook Dell Vostro ' + raw);
    return [...new Set(out.filter(Boolean))];
  }
  function parseOptionText(rawText, el){
    const text = (rawText || '').replace(/\s+/g,' ').trim();
    if(!text || text.length <= 2 || text.length >= 260) return null;
    const attrs = {};
    for(const a of (el?.attributes || [])) attrs[a.name.toLowerCase()] = a.value;
    const idRaw = attrs['data-idproduto'] || attrs['data-id-produto'] || attrs['data-id'] || attrs['id_produto'] || attrs['value'] || '';
    const idMatch = (idRaw || '').toString().match(/\d{3,}/);
    const qtdMatch = text.match(/(?:\bun\b|estoque|qtd|qtde|quantidade|saldo|disp\.?)\D{0,12}(-?[\d.,]+)/i);
    const codigoMatch = text.match(/^\s*([A-Z0-9][A-Z0-9._\/-]{1,})\s*(?:-|–|—|\|)/i);
    const estoque = qtdMatch ? qtdMatch[1] : '';
    const codigo = codigoMatch ? codigoMatch[1].toUpperCase() : '';
    const texto = estoque && !/\bun\b|qtd|qtde|quantidade|estoque|saldo/i.test(text)
      ? text + ' | un ' + estoque
      : text;
    return {
      texto,
      codigo,
      descricao: text,
      estoque,
      quantidade: estoque,
      idProduto: idMatch ? parseInt(idMatch[0], 10) : 0,
      fonte: 'site'
    };
  }
  function cleanQty(raw){
    const q = (raw || '').toString().trim();
    if(!q) return '';
    if(/\s/.test(q)) return '';
    if(!/^-?\d+(?:[,.]\d+)?$/.test(q)) return '';
    return q;
  }
  function splitCombinedOptions(text){
    const clean = (text || '').replace(/\s+/g,' ').trim();
    if(!clean) return [];
    const pattern = /(?=(?:^|\s)(?:(?:[A-Z]\d{2,5}-+(?:[A-Z0-9]{2,4})?)\s+(?:-\s+)?|(?:\d{2,5}-\d{2,5}-\d{2,5}|\d{2,5}(?:_\d+)?)\s+-\s+))/g;
    const parts = clean.split(pattern).map(x => x.trim()).filter(Boolean);
    return parts.length > 1 ? parts : [clean];
  }
  function hasOptionChildren(el){
    return !!el.querySelector?.('li, .ui-menu-item, .select2-results__option, [role=option], .autocomplete-suggestion, .tt-suggestion');
  }
  function parseOption(el){
    if(hasOptionChildren(el)) return [];
    const text = (el.innerText || el.textContent || '').replace(/\s+/g,' ').trim();
    return splitCombinedOptions(text).map(part => {
      const parsed = parseOptionText(part, el);
      if(parsed) {
        const q = cleanQty(parsed.estoque || parsed.quantidade);
        parsed.estoque = q;
        parsed.quantidade = q;
      }
      return parsed;
    }).filter(Boolean);
  }
  function collectOptions(term){
    const q = norm(term);
    return [...document.querySelectorAll('li, .ui-menu-item, .select2-results__option, [role=option], .autocomplete-suggestion, .tt-suggestion, div')]
      .filter(visible)
      .map(parseOption)
      .flat()
      .filter(Boolean)
      .filter(o => {
        const n = norm(o.texto);
        return n.includes(q) || n.includes(q.split(/\s+/)[0]);
      });
  }
  function extractProductsFromJson(value, out = []){
    if(value == null || out.length >= 80) return out;
    if(Array.isArray(value)){
      for(const item of value) extractProductsFromJson(item, out);
      return out;
    }
    if(typeof value === 'object'){
      const textFields = ['label','value','text','texto','nome','descricao','desc_produto','produto','name'];
      let text = '';
      for(const f of textFields){
        if(typeof value[f] === 'string' && value[f].trim().length > text.length) text = value[f].trim();
      }
      const code = (value.codigo || value.cod_produto || value.cod || value.code || '').toString().trim();
      if(code && text && !text.toUpperCase().startsWith(code.toUpperCase())) text = code + ' - ' + text;
      const qty = cleanQty(value.estoque || value.quantidade || value.qtd || value.qtde || value.saldo || value.un || '');
      for(const part of splitCombinedOptions(text)){
        const parsed = parseOptionText(part, null);
        if(parsed){
          parsed.estoque = qty;
          parsed.quantidade = qty;
          if(qty && !/\bun\b|qtd|qtde|quantidade|estoque|saldo/i.test(parsed.texto)) parsed.texto += ' | un ' + qty;
          const idRaw = value.id_produto || value.idProduto || value.id || value.produto_id || '';
          const idMatchObj = idRaw.toString().match(/\d{3,}/);
          parsed.idProduto = idMatchObj ? parseInt(idMatchObj[0], 10) : parsed.idProduto;
          out.push(parsed);
        }
      }
      for(const k of Object.keys(value)) extractProductsFromJson(value[k], out);
      return out;
    }
    if(typeof value === 'string'){
      for(const part of splitCombinedOptions(value)){
        const parsed = parseOptionText(part, null);
        if(parsed) out.push(parsed);
      }
    }
    return out;
  }
  function extractProductsFromText(text){
    const doc = new DOMParser().parseFromString(text || '', 'text/html');
    const nodes = [...doc.querySelectorAll('li, option, .ui-menu-item, .select2-results__option, [role=option], div, span')]
      .map(parseOption)
      .flat()
      .filter(Boolean);
    if(nodes.length) return nodes;
    return splitCombinedOptions(text).map(part => parseOptionText(part, null)).filter(Boolean);
  }
  async function fastAutocomplete(term){
    const body = new URLSearchParams();
    body.set('query', term);
    body.set('tipo_produto', 'Produto');
    body.set('identifier', 'SomenteProdutoLista');
    body.set('ServicoOrdem', '1');
    const candidates = ['/consumidor/', 'consumidor/'];
    for(const url of candidates){
      try{
        const resp = await fetch(url, {
          method:'POST',
          credentials:'include',
          headers:{'Content-Type':'application/x-www-form-urlencoded; charset=UTF-8','X-Requested-With':'XMLHttpRequest'},
          body: body.toString()
        });
        if(!resp.ok) continue;
        const txt = await resp.text();
        let produtos = [];
        try { produtos = extractProductsFromJson(JSON.parse(txt)); } catch { produtos = extractProductsFromText(txt); }
        produtos = produtos.filter(p => norm(p.texto).includes(norm(term).split(/\s+/)[0]));
        if(produtos.length) return produtos;
      } catch {}
    }
    return [];
  }
  function fields(){
    return [...document.querySelectorAll('input:not([type=hidden]):not([type=button]):not([type=submit]), textarea')]
      .filter(visible).filter(x => !x.disabled && !x.readOnly);
  }
  function sectionField(section){
    const wanted = norm(section);
    const heads = [...document.querySelectorAll('h1,h2,h3,h4,div,span,label')]
      .filter(x => visible(x) && norm(x.textContent).includes(wanted));
    if(!heads.length) return null;
    const hr = heads[0].getBoundingClientRect();
    return fields()
      .map(f => ({f, r:f.getBoundingClientRect()}))
      .filter(x => x.r.top > hr.bottom)
      .sort((a,b) => a.r.top - b.r.top || a.r.left - b.r.left)[0]?.f || null;
  }
  function labelField(label){
    const wanted = norm(label);
    const labels = [...document.querySelectorAll('label,span,div,td,th')]
      .filter(x => visible(x) && norm(x.textContent).includes(wanted));
    for(const l of labels){
      const lr = l.getBoundingClientRect();
      const candidate = fields()
        .map(f => ({f, r:f.getBoundingClientRect()}))
        .filter(x => x.r.top >= lr.top - 3 && x.r.left >= lr.left - 20)
        .sort((a,b) => ((a.r.top-lr.bottom)*3 + Math.abs(a.r.left-lr.left)) - ((b.r.top-lr.bottom)*3 + Math.abs(b.r.left-lr.left)))[0]?.f;
      if(candidate) return candidate;
    }
    return null;
  }

  if (document.querySelector('input[type=password]')) {
    return { ok:false, mensagem:'O perfil de automacao do Brave precisa estar logado no Altertag.', opcoes:[] };
  }

  const fast = await fastAutocomplete(data.termo);
  if(fast.length){
    const seenFast = new Set();
    const produtosFast = [];
    for(const item of fast){
      const key = norm(item.texto);
      if(seenFast.has(key)) continue;
      seenFast.add(key);
      produtosFast.push(item);
      if(produtosFast.length >= 80) break;
    }
    return { ok:true, mensagem:'Opcoes encontradas no autocomplete Altertag.', opcoes:produtosFast.map(p => p.texto), produtos:produtosFast, fonte:'altertag_autocomplete' };
  }
  if(((data.modo || '').toString().toLowerCase()) === 'rapido'){
    return { ok:true, mensagem:'Autocomplete direto Altertag sem resultado rapido.', opcoes:[], produtos:[], fonte:'altertag_autocomplete' };
  }

  for(let i=0;i<16;i++){
    const txt = norm(document.body?.innerText || '');
    if(txt.includes('dados da ordem') || txt.includes('produtos') || txt.includes('servicos')) break;
    await sleep(500);
  }

  const tipo = norm(data.tipo);
  const campo = tipo.includes('serv') ? (labelField('Servico') || sectionField('Servicos')) : (labelField('Produto') || sectionField('Produtos'));
  if(!campo) return { ok:false, mensagem:'Campo de ' + data.tipo + ' nao encontrado no Altertag.', opcoes:[] };

  const variants = queryVariants(data.termo);
  let raw = [];
  for (const term of variants) {
    setVal(campo, '');
    await sleep(250);
    setVal(campo, term);
    for(let i=0;i<8;i++){
      await sleep(450);
      raw = raw.concat(collectOptions(term));
      if(raw.length >= 50) break;
    }
    if(raw.length) break;
  }
  const seen = new Set();
  const produtos = [];
  for(const item of raw){
    const key = norm(item.texto);
    if(seen.has(key)) continue;
    seen.add(key);
    produtos.push(item);
    if(produtos.length >= 80) break;
  }
  const opcoes = produtos.map(p => p.texto);
  return { ok:true, mensagem:'Opcoes encontradas no Altertag.', opcoes, produtos, fonte:'site' };
})()
"@

    $wsUrl = Get-BravePageTarget -UrlPart 'app.altertag.com.br'
    $eval = Invoke-BraveRuntimeEvaluate -WebSocketUrl $wsUrl -Expression $js
    return $eval.result.result.value
}

function Ensure-BuscaProdutosField {
    param($Busca)

    if ($null -eq $Busca) {
        return @{ ok = $false; mensagem = 'Busca sem resposta.'; opcoes = @(); produtos = @(); fonte = 'desconhecida' }
    }
    if ($Busca -is [hashtable]) {
        if (-not $Busca.ContainsKey('produtos')) { $Busca['produtos'] = @() }
        if (-not $Busca.ContainsKey('opcoes')) { $Busca['opcoes'] = @() }
        if (-not $Busca.ContainsKey('fonte')) { $Busca['fonte'] = 'site' }
        return $Busca
    }
    if (-not $Busca.PSObject.Properties['produtos']) { $Busca | Add-Member -NotePropertyName produtos -NotePropertyValue @() -Force }
    if (-not $Busca.PSObject.Properties['opcoes']) { $Busca | Add-Member -NotePropertyName opcoes -NotePropertyValue @() -Force }
    if (-not $Busca.PSObject.Properties['fonte']) { $Busca | Add-Member -NotePropertyName fonte -NotePropertyValue 'site' -Force }
    return $Busca
}

function Split-AltertagProdutoTexto {
    param([string]$Texto)

    $clean = ([string]$Texto -replace '\s+', ' ').Trim()
    if (-not $clean) { return @() }
    $pattern = '(?=(?:^|\s)(?:(?:[A-Z]\d{2,5}-+(?:[A-Z0-9]{2,4})?)\s+(?:-\s+)?|(?:\d{2,5}-\d{2,5}-\d{2,5}|\d{2,5}(?:_\d+)?)\s+-\s+))'
    $parts = @($clean -split $pattern | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($parts.Count -gt 1) { return $parts }
    return @($clean)
}

function Get-CaijProdutoBuscaAliases {
    param([string]$Termo)

    $t = ([string]$Termo).ToUpper()
    $aliases = @()
    if ($t -match '3420' -and $t -match 'I5' -and $t -match '(11TH|11)') {
        $aliases += @('P023--', 'A023-C2F', 'A023-C2G', 'A023-C3F', 'A023-C3G')
    }
    return @($aliases | Where-Object { $_ } | Select-Object -Unique)
}

function Normalize-AltertagQuantidade {
    param([string]$Quantidade)

    $q = ([string]$Quantidade).Trim()
    if (-not $q) { return '' }
    if ($q -match '\s') { return '' }
    if ($q -notmatch '^-?\d+(?:[,.]\d+)?$') { return '' }
    return $q
}

function Format-AltertagQuantidadeDisplay {
    param([string]$Quantidade)

    $q = Normalize-AltertagQuantidade $Quantidade
    if (-not $q) { return '' }
    [decimal]$decimal = 0
    if ([decimal]::TryParse($q.Replace(',', '.'), [System.Globalization.NumberStyles]::Number, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$decimal)) {
        return $decimal.ToString('0.00', [System.Globalization.CultureInfo]::GetCultureInfo('pt-BR'))
    }
    return $q.Replace('.', ',')
}

function Get-ProdutoSortKey {
    param($Produto)

    $codigo = ([string]$Produto.codigo).Trim().ToUpper()
    if (-not $codigo -and [string]$Produto.texto -match '^([A-Z]*\d+[A-Z0-9._/-]*)\s+(?:-\s+)?') { $codigo = $matches[1].ToUpper() }
    if ($codigo -match '^P') { return '0_' + $codigo }
    if ($codigo -match '^A') { return '1_' + $codigo }
    if ($codigo) { return '2_' + $codigo }
    return '9_' + ([string]$Produto.texto).ToUpper()
}

function Normalize-BuscaProdutos {
    param($Busca)

    $Busca = Ensure-BuscaProdutosField -Busca $Busca
    $produtos = @()
    foreach ($p in @($Busca.produtos)) {
        $texto = [string]$p.texto
        if (-not $texto) { $texto = [string]$p.descricao }
        $partes = @(Split-AltertagProdutoTexto -Texto $texto)
        foreach ($part in $partes) {
            $single = ($partes.Count -eq 1)
            $qtdRaw = ''
            if ($p.estoque) { $qtdRaw = [string]$p.estoque } elseif ($p.quantidade) { $qtdRaw = [string]$p.quantidade }
            $qtd = ''
            if ($single) { $qtd = Normalize-AltertagQuantidade $qtdRaw }
            $codigo = ''
            if ($single -and $p.codigo) { $codigo = [string]$p.codigo }
            elseif ($part -match '^([A-Z]*\d+[A-Z0-9._/-]*)\s+(?:-\s+)?') { $codigo = $matches[1].ToUpper() }
            $descricao = $part
            if ($single -and $p.descricao) { $descricao = [string]$p.descricao }
            $valor = '0.00'
            if ($p.valor) { $valor = [string]$p.valor }
            $idProduto = 0
            if ($single -and $p.idProduto) { $idProduto = [int]$p.idProduto }
            $fonteProduto = [string]$Busca.fonte
            if ($p.fonte) { $fonteProduto = [string]$p.fonte }
            $textoFinal = $part
            $qtdDisplay = Format-AltertagQuantidadeDisplay $qtd
            if ($qtdDisplay -and $textoFinal -notmatch '(?i)\bun\b|qtd|qtde|quantidade|estoque|saldo') {
                $textoFinal = "$textoFinal | un $qtdDisplay"
            }
            $produtos += [pscustomobject]@{
                texto = $textoFinal
                codigo = $codigo
                descricao = $descricao
                valor = $valor
                estoque = $qtd
                quantidade = $qtd
                idProduto = $idProduto
                fonte = $fonteProduto
            }
        }
    }
    foreach ($op in @($Busca.opcoes)) {
        foreach ($part in @(Split-AltertagProdutoTexto -Texto ([string]$op))) {
            if (-not (@($produtos | Where-Object { [string]$_.texto -eq $part }).Count)) {
                $codigoOp = ''
                if ($part -match '^([A-Z]*\d+[A-Z0-9._/-]*)\s+(?:-\s+)?') { $codigoOp = $matches[1].ToUpper() }
                $produtos += [pscustomobject]@{
                    texto = $part
                    codigo = $codigoOp
                    descricao = $part
                    valor = '0.00'
                    estoque = ''
                    quantidade = ''
                    idProduto = 0
                    fonte = [string]$Busca.fonte
                }
            }
        }
    }

    $dedup = @{}
    $norm = @()
    foreach ($p in $produtos) {
        $codKey = ([string]$p.codigo).Trim().ToUpper()
        if (-not $codKey -and [string]$p.texto -match '^([A-Z]*\d+[A-Z0-9._/-]*)\s+(?:-\s+)?') { $codKey = $matches[1].ToUpper() }
        $key = if ($codKey) { "COD:$codKey" } else { "TXT:$(([string]$p.texto).ToUpper())" }
        if (-not $dedup.ContainsKey($key)) {
            $dedup[$key] = $true
            $norm += $p
        }
    }
    $preferenciais = @($norm | Where-Object {
        $codPref = ([string]$_.codigo).Trim().ToUpper()
        if (-not $codPref -and [string]$_.texto -match '^([A-Z]*\d+[A-Z0-9._/-]*)\s+(?:-\s+)?') { $codPref = $matches[1].ToUpper() }
        $codPref -match '^[PA]'
    })
    if ($preferenciais.Count -gt 0) { $norm = $preferenciais }
    $norm = @($norm | Sort-Object -Property @{ Expression = { Get-ProdutoSortKey $_ }; Descending = $false })

    if ($Busca -is [hashtable]) {
        $Busca['produtos'] = $norm
        $Busca['opcoes'] = @($norm | ForEach-Object { [string]$_.texto })
    } else {
        $Busca | Add-Member -NotePropertyName produtos -NotePropertyValue $norm -Force
        $Busca | Add-Member -NotePropertyName opcoes -NotePropertyValue @($norm | ForEach-Object { [string]$_.texto }) -Force
    }
    return $Busca
}

function Get-ProdutosCsvPath {
    if (Test-Path $produtosCsvPadrao) { return $produtosCsvPadrao }
    $maisRecente = Get-ChildItem -Path $desktopUsuario -Filter 'produtos_*.csv' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($maisRecente) { return $maisRecente.FullName }
    return $null
}

function Get-ProdutosExport {
    $csvPath = Get-ProdutosCsvPath
    if (-not $csvPath -or -not (Test-Path $csvPath)) { return @() }

    $item = Get-Item $csvPath -ErrorAction SilentlyContinue
    if (-not $item) { return @() }

    if ($script:produtosCsvCache -and $script:produtosCsvCachePath -eq $csvPath -and $script:produtosCsvCacheStamp -eq $item.LastWriteTimeUtc) {
        return $script:produtosCsvCache
    }

    try {
        $rows = Import-Csv -Path $csvPath -Encoding UTF8 -ErrorAction Stop
        $norm = foreach ($r in $rows) {
            $tipo = [string]$r.'Tipo (Produto/Servico)'
            $situacao = [string]$r.'Situação (Ativo/Inativo)'
            if ($tipo -and $tipo.Trim().ToUpper() -ne 'PRODUTO') { continue }
            if ($situacao -and $situacao.Trim().ToUpper() -eq 'INATIVO') { continue }

            [pscustomobject]@{
                Codigo   = ([string]$r.'Código do Produto (60)').Trim().ToUpper()
                Nome     = ([string]$r.'Nome do Produto (120)').Trim()
                Marca    = ([string]$r.'Marca (25)').Trim()
                Estoque  = ([string]$r.'Estoque Atual').Trim()
                Situacao = $situacao
                Texto    = (([string]$r.'Código do Produto (60)').Trim().ToUpper() + ' ' + ([string]$r.'Nome do Produto (120)').Trim()).Trim()
            }
        }
        $script:produtosCsvCache = @($norm | Where-Object { $_.Codigo -and $_.Nome })
        $script:produtosCsvCachePath = $csvPath
        $script:produtosCsvCacheStamp = $item.LastWriteTimeUtc
        return $script:produtosCsvCache
    } catch {
        return @()
    }
}

function Search-ProdutosExport {
    param([string]$Termo)

    $produtos = Get-ProdutosExport
    if (-not $produtos -or $produtos.Count -eq 0) {
        return @{ ok = $false; mensagem = 'CSV de produtos nao encontrado ou vazio.'; opcoes = @(); fonte = 'csv' }
    }

    $tokens = @($Termo.ToUpper() -split '[^A-Z0-9]+' | Where-Object { $_ -and $_.Trim().Length -ge 2 })
    $hits = foreach ($p in $produtos) {
        $texto = [string]$p.Texto
        $upper = $texto.ToUpper()
        $score = 0

        foreach ($tk in $tokens) {
            if ($upper -match [regex]::Escape($tk)) { $score += 5 }
        }
        if ($upper.StartsWith($Termo.ToUpper())) { $score += 8 }
        if ($upper -match '\bE14\b' -and $Termo.ToUpper() -match '\bE14\b') { $score += 6 }
        if ($upper -match '\bT14\b' -and $Termo.ToUpper() -match '\bT14\b') { $score += 6 }
        if ($upper -match '\bI7\b'  -and $Termo.ToUpper() -match '\bI7\b')  { $score += 4 }
        if ($upper -match '\bI5\b'  -and $Termo.ToUpper() -match '\bI5\b')  { $score += 4 }
        if ($upper -match '\b16GB\b' -and $Termo.ToUpper() -match '\b16GB\b') { $score += 3 }
        if ($upper -match '\b8GB\b'  -and $Termo.ToUpper() -match '\b8GB\b')  { $score += 3 }
        if ($upper -match '\b512GB\b' -and $Termo.ToUpper() -match '\b512\b') { $score += 3 }
        if ($upper -match '\b256GB\b' -and $Termo.ToUpper() -match '\b256\b') { $score += 3 }
        if ($score -gt 0) {
            [pscustomobject]@{ Texto = $texto; Score = $score; Produto = $p }
        }
    }

    $ordenados = @($hits | Sort-Object -Property @{ Expression = 'Score'; Descending = $true }, @{ Expression = 'Texto'; Descending = $false } | Select-Object -First 80)
    $produtos = @($ordenados | ForEach-Object {
        $p = $_.Produto
        $estoque = [string]$p.Estoque
        $texto = [string]$p.Texto
        if ($estoque) { $texto = "$texto | Qtd: $estoque" }
        [pscustomobject]@{
            texto = $texto
            codigo = [string]$p.Codigo
            descricao = [string]$p.Nome
            estoque = $estoque
            quantidade = $estoque
            idProduto = 0
            fonte = 'csv'
        }
    })
    return @{ ok = $true; mensagem = 'Opcoes encontradas na exportacao local de produtos.'; opcoes = @($produtos | ForEach-Object { [string]$_.texto }); produtos = $produtos; fonte = 'csv' }
}

function Get-ClipboardTextSta {
    try {
        return [System.Windows.Forms.Clipboard]::GetText()
    } catch {
        return ''
    }
}

function Get-AltertagLastOsFromVisibleBrave {
    $shell = New-Object -ComObject WScript.Shell
    $activated = $false
    $janelaInfo = ''
    try { $activated = [bool]$shell.AppActivate('Ordem de Servico') } catch {}
    if (-not $activated) {
        try { $activated = [bool]$shell.AppActivate('Ordem de Serviço') } catch {}
    }
    if (-not $activated) {
        try { $activated = [bool]$shell.AppActivate('Brave') } catch {}
    }
    if (-not $activated) {
        try {
            $braveProc = Get-Process -Name brave -ErrorAction SilentlyContinue |
                Where-Object { $_.MainWindowHandle -ne 0 } |
                Sort-Object StartTime -Descending |
                Select-Object -First 1
            if ($braveProc) {
                $janelaInfo = "PID=$($braveProc.Id), Titulo=$($braveProc.MainWindowTitle), Handle=$($braveProc.MainWindowHandle)"
                [CaijWin32]::ShowWindow([IntPtr]$braveProc.MainWindowHandle, 9) | Out-Null
                Start-Sleep -Milliseconds 200
                $activated = [CaijWin32]::SetForegroundWindow([IntPtr]$braveProc.MainWindowHandle)
            }
        } catch {}
    }
    if (-not $activated) {
        if (-not $janelaInfo) { $janelaInfo = 'nenhum processo brave com MainWindowHandle encontrado' }
        return @{ ok=$false; mensagem="Nao consegui ativar a janela visivel do Brave. $janelaInfo"; ultimo=$null }
    }

    Start-Sleep -Milliseconds 500
    try { [System.Windows.Forms.Clipboard]::Clear() } catch {}
    $shell.SendKeys('{ESC}')
    Start-Sleep -Milliseconds 200
    $shell.SendKeys('^a')
    Start-Sleep -Milliseconds 700
    $shell.SendKeys('^c')
    Start-Sleep -Milliseconds 1400

    $texto = [string](Get-ClipboardTextSta)
    if (-not $texto -or $texto.Trim().Length -lt 20) {
        return @{ ok=$false; mensagem='Nao consegui copiar o texto da pagina do Altertag.'; ultimo=$null }
    }

    $nums = @()
    $matches = [System.Text.RegularExpressions.Regex]::Matches($texto, '(?m)(^|\s)(\d{2,8})\s+\d{2}/\d{2}/\d{4}(\s|$)')
    foreach ($m in $matches) {
        $nums += [int]$m.Groups[2].Value
    }

    if (-not $nums -or $nums.Count -eq 0) {
        return @{ ok=$false; mensagem='Texto copiado, mas nao encontrei linhas com OS + data.'; ultimo=$null }
    }

    $ultimo = ($nums | Measure-Object -Maximum).Maximum
    return @{ ok=$true; mensagem='Ultima OS identificada pelo texto copiado do Brave.'; ultimo=[int]$ultimo }
}

function Get-AltertagLastOs {
    $viaTela = Get-AltertagLastOsFromVisibleBrave
    return $viaTela

    $url = 'https://app.altertag.com.br/index.php?Secao=Servicos.Ordem&Modulo=Servicos'
    Start-BraveAutomation -Url $url

    $js = @"
(async function(){
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const norm = s => (s || '').toString().normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().trim();
  const visible = el => {
    if(!el) return false;
    const r = el.getBoundingClientRect();
    const st = getComputedStyle(el);
    return r.width > 1 && r.height > 1 && st.display !== 'none' && st.visibility !== 'hidden';
  };

  if (document.querySelector('input[type=password]')) {
    return { ok:false, mensagem:'Perfil do Brave nao esta logado no Altertag.', ultimo:null };
  }

  for(let i=0;i<20;i++){
    const txt = norm(document.body?.innerText || '');
    if(txt.includes('ordem de servico') || txt.includes('nova ordem de servico')) break;
    await sleep(400);
  }

  const nums = [];
  const rows = [...document.querySelectorAll('tr')];
  for(const tr of rows){
    if(!visible(tr)) continue;
    const tds = [...tr.querySelectorAll('td')].filter(visible);
    if(tds.length < 2) continue;
    const n0 = (tds[0].innerText || '').trim();
    const n1 = (tds[1].innerText || '').trim();
    if(/^\d{2,8}$/.test(n0) && /^\d{2}\/\d{2}\/\d{4}/.test(n1)) nums.push(parseInt(n0,10));
  }

  if(!nums.length){
    const matches = (document.body?.innerText || '').match(/\b\d{2,8}\b/g) || [];
    for(const m of matches){
      const n = parseInt(m,10);
      if(n >= 100 && n <= 99999999) nums.push(n);
    }
  }

  if(!nums.length) return { ok:false, mensagem:'Nao foi possivel identificar a ultima OS na lista.', ultimo:null };
  nums.sort((a,b)=>b-a);
  return { ok:true, mensagem:'Ultima OS identificada no Altertag.', ultimo:nums[0] };
})()
"@

    $wsUrl = Get-BravePageTarget -UrlPart 'app.altertag.com.br'
    $eval = Invoke-BraveRuntimeEvaluate -WebSocketUrl $wsUrl -Expression $js
    return $eval.result.result.value
}

function ConvertFrom-AltertagEnvText {
    param([Parameter(Mandatory=$true)][string]$Text)

    $values = @{}
    foreach ($line in ($Text -split "`r?`n")) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }
        $parts = $trimmed -split '=', 2
        if ($parts.Count -ne 2) { continue }
        $values[$parts[0].Trim()] = $parts[1].Trim().Trim('"').Trim("'")
    }

    $apiBaseUrl = if ($values['ALTERTAG_API_BASE_URL']) {
        [string]$values['ALTERTAG_API_BASE_URL']
    } elseif ($values['ALTERTAG_BASE_URL'] -and ([string]$values['ALTERTAG_BASE_URL']) -match '/v\d+/?$') {
        [string]$values['ALTERTAG_BASE_URL']
    } else {
        $altertagApiBaseUrlPadrao
    }
    $accessToken = if ($values['ALTERTAG_ACCESS_TOKEN']) { [string]$values['ALTERTAG_ACCESS_TOKEN'] } else { [string]$values['ALTERTAG_API_KEY'] }
    $secretAccessToken = if ($values['ALTERTAG_SECRET_ACCESS_TOKEN']) { [string]$values['ALTERTAG_SECRET_ACCESS_TOKEN'] } else { [string]$values['ALTERTAG_API_SECRET'] }

    [pscustomobject]@{
        ApiBaseUrl = $apiBaseUrl.TrimEnd('/')
        AccessToken = $accessToken
        SecretAccessToken = $secretAccessToken
    }
}

function Read-AltertagApiConfig {
    if (-not (Test-Path -LiteralPath $altertagEnvArquivo)) {
        throw "Arquivo altertag.env nao encontrado em $altertagEnvArquivo"
    }
    $cfg = ConvertFrom-AltertagEnvText -Text (Get-Content -LiteralPath $altertagEnvArquivo -Raw)
    if ([string]::IsNullOrWhiteSpace($cfg.AccessToken) -or [string]::IsNullOrWhiteSpace($cfg.SecretAccessToken)) {
        throw 'ALTERTAG_ACCESS_TOKEN/ALTERTAG_SECRET_ACCESS_TOKEN ou ALTERTAG_API_KEY/ALTERTAG_API_SECRET precisam estar preenchidos no altertag.env.'
    }
    return $cfg
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
        'User-Agent' = 'CAIJ-ServidorImpressao/5.1'
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
            idOrdem = [int]$idOrdem
            numero = [int]$numero
            osCodigo = ('C{0:D6}' -f [int]$numero)
            cliente = [string]$item.nome_cliente
            tecnico = $tecnico
            statusOs = [string]$item.status_pedido
            dataCadastro = [string]$item.data_cad_pedido
            dataPedido = [string]$item.data_pedido
            equipamento = [string]$item.equipamento_ordem
            problema = [string]$item.problema_ordem
            garantia = [string]$item.garantia_ordem
            referencia = [string]$item.referencia_ordem
            valorTotal = [string]$item.valor_total_os
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
        idOrdem = [int]$item.id_ordem
        numero = [int]$item.id_pedido
        osCodigo = ('C{0:D6}' -f [int]$item.id_pedido)
        cliente = [string]$item.nome_cliente
        tecnico = $tecnico
        statusOs = [string]$item.status_pedido
        dataCadastro = [string]$item.data_cad_pedido
        dataPedido = [string]$item.data_pedido
        equipamento = [string]$item.equipamento_ordem
        problema = [string]$item.problema_ordem
        garantia = [string]$item.garantia_ordem
        referencia = [string]$item.referencia_ordem
        valorTotal = [string]$item.valor_total_os
    }
}

function Get-VhsysOrdensServicoRecentes {
    param(
        [int]$Limit = 15,
        [string]$Tecnico = '',
        [switch]$IncludeProdutos
    )

    $cfg = Read-AltertagApiConfig
    $limitSafe = [Math]::Max(1, [Math]::Min(50, $Limit))
    $uri = '{0}/ordens-servico?limit={1}&offset=0&lixeira=Nao&order=id_pedido&sort=desc' -f $cfg.ApiBaseUrl.TrimEnd('/'), $limitSafe
    $headers = New-AltertagApiHeaders -AccessToken $cfg.AccessToken -SecretAccessToken $cfg.SecretAccessToken
    $resp = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers -TimeoutSec 15 -ErrorAction Stop
    $ordens = @(ConvertFrom-VhsysOrdensServico -Response $resp | ForEach-Object { $_ })
    if ($IncludeProdutos) {
        Add-VhsysProdutosResumoToOrdens -Ordens $ordens -Config $cfg
    }
    if ($Tecnico) {
        $tec = $Tecnico.Trim().ToUpper()
        $preferidas = @($ordens | Where-Object { ([string]$_.tecnico).Trim().ToUpper() -eq $tec })
        $outras = @($ordens | Where-Object { ([string]$_.tecnico).Trim().ToUpper() -ne $tec })
        return @($preferidas + $outras)
    }
    return $ordens
}

function Resolve-VhsysIdOrdem {
    param(
        [int]$IdOrdem = 0,
        [int]$OsNumero = 0
    )

    if ($IdOrdem -gt 0) { return $IdOrdem }
    if ($OsNumero -lt 1) { throw 'Informe idOrdem ou osNumero.' }

    $ordens = @(Get-VhsysOrdensServicoRecentes -Limit 50)
    $match = @($ordens | Where-Object { [int]$_.numero -eq $OsNumero } | Select-Object -First 1)
    if (-not $match -or [int]$match[0].idOrdem -lt 1) {
        throw "OS $('C{0:D6}' -f [int]$OsNumero) nao encontrada entre as recentes da API vhsys."
    }
    return [int]$match[0].idOrdem
}

function Get-VhsysOrdemServicoDetalhe {
    param(
        [int]$IdOrdem = 0,
        [int]$OsNumero = 0,
        [switch]$IncludeProdutos
    )

    $cfg = Read-AltertagApiConfig
    $id = Resolve-VhsysIdOrdem -IdOrdem $IdOrdem -OsNumero $OsNumero
    $resp = Invoke-VhsysJson -Config $cfg -Path ("/ordens-servico/{0}" -f $id) -Method 'Get' -TimeoutSec 18
    $detalhe = ConvertFrom-VhsysOrdemServicoDetalhe -Response $resp
    if ($IncludeProdutos) {
        $produtos = @(Get-VhsysProdutosOrdemServico -Config $cfg -IdOrdem $id)
        $detalhe | Add-Member -NotePropertyName produtos -NotePropertyValue $produtos -Force
        if ($produtos.Count -gt 0) {
            $detalhe.equipamento = (@($produtos | ForEach-Object { [string]$_.descricao } | Where-Object { $_.Trim() }) -join ' | ')
        }
    }
    return $detalhe
}

function ConvertFrom-VhsysProdutosOrdemServico {
    param([Parameter(Mandatory=$true)]$Response)

    $produtos = @()
    foreach ($item in @($Response.data)) {
        if (-not $item) { continue }
        $produtos += [pscustomobject]@{
            idItemOs = [string]$item.id_ped_produto
            idOrdem = [string]$item.id_ordem
            idProduto = [string]$item.id_produto
            descricao = [string]$item.desc_produto
            quantidade = [string]$item.qtde_produto
            valorTotal = [string]$item.valor_total_produto
        }
    }
    return ,$produtos
}

function Get-VhsysProdutosOrdemServico {
    param(
        [Parameter(Mandatory=$true)]$Config,
        [Parameter(Mandatory=$true)][int]$IdOrdem
    )

    $uri = '{0}/ordens-servico/{1}/produtos' -f $Config.ApiBaseUrl.TrimEnd('/'), $IdOrdem
    $headers = New-AltertagApiHeaders -AccessToken $Config.AccessToken -SecretAccessToken $Config.SecretAccessToken
    try {
        $resp = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers -TimeoutSec 10 -ErrorAction Stop
        return @(ConvertFrom-VhsysProdutosOrdemServico -Response $resp)
    } catch {
        return @()
    }
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
                idProduto = (Get-IndexedValue $item.id_produto $idx).Trim()
                codigo = $cod
                descricao = $desc
                valor = (Get-IndexedValue $item.valor_produto $idx).Trim()
                estoque = $estoque
                texto = if ($cod) { ('{0} - {1}' -f $cod, $desc) } else { $desc }
            }
        }
    }
    return ,$produtos
}
function Search-VhsysProdutosCatalogo {
    param(
        [Parameter(Mandatory=$true)][string]$Termo,
        [int]$Limit = 15
    )

    $cfg = Read-AltertagApiConfig
    $headers = New-AltertagApiHeaders -AccessToken $cfg.AccessToken -SecretAccessToken $cfg.SecretAccessToken
    $limitSafe = [Math]::Max(1, [Math]::Min(50, $Limit))
    $termoClean = ([string]$Termo).Trim()
    if (-not $termoClean) { return @() }

    $queries = New-Object System.Collections.Generic.List[string]
    [void]$queries.Add($termoClean)
    $tokens = @($termoClean -split '\s+' | Where-Object { $_ -and $_.Trim().Length -ge 2 })
    if ($tokens.Count -gt 1) {
        [void]$queries.Add(($tokens -join ' '))
    }
    foreach ($alias in @(Get-CaijProdutoBuscaAliases -Termo $termoClean)) {
        [void]$queries.Add($alias)
    }
    if ($termoClean -match '(?i)\b(thinkpad|latitude|vostro|inspiron|ideapad|notebook)\b') {
        [void]$queries.Add(($tokens | Where-Object { $_ -notmatch '(?i)notebook' }) -join ' ')
    }
    $queries = @($queries | Where-Object { $_ -and $_.Trim() } | Select-Object -Unique)

    $all = @()
    $lastErr = $null
    foreach ($q in $queries) {
        $enc = [System.Uri]::EscapeDataString($q)
        $uris = @(
            ('{0}/produtos?limit={1}&offset=0&lixeira=Nao&desc_produto={2}' -f $cfg.ApiBaseUrl.TrimEnd('/'), $limitSafe, $enc),
            ('{0}/produtos?limit={1}&offset=0&lixeira=Nao&cod_produto={2}' -f $cfg.ApiBaseUrl.TrimEnd('/'), $limitSafe, $enc)
        )
        foreach ($uri in $uris) {
            try {
                $resp = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers -TimeoutSec 12 -ErrorAction Stop
                $all += @(ConvertFrom-VhsysProdutosCatalogo -Response $resp)
            } catch {
                $lastErr = $_.Exception.Message
            }
        }
    }

    $dedup = @{}
    foreach ($p in $all) {
        $key = if ($p.idProduto) { [string]$p.idProduto } elseif ($p.codigo) { [string]$p.codigo } else { [string]$p.texto }
        if (-not $dedup.ContainsKey($key)) { $dedup[$key] = $p }
    }
    $result = @($dedup.Values | Sort-Object -Property texto | Select-Object -First $limitSafe)
    if ($result.Count -eq 0 -and $lastErr) {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Busca produtos API sem resultado: $lastErr"
    }
    return ,$result
}

function Resolve-VhsysProdutoCatalogo {
    param(
        [string]$Codigo,
        [string]$Descricao
    )

    $termos = @()
    if ($Codigo) { $termos += [string]$Codigo }
    if ($Descricao) { $termos += [string]$Descricao }
    foreach ($termoResolve in @($termos | Where-Object { $_ -and $_.Trim() } | Select-Object -Unique)) {
        $hits = @(Search-VhsysProdutosCatalogo -Termo $termoResolve -Limit 20)
        if ($Codigo) {
            $exato = @($hits | Where-Object { ([string]$_.codigo).Trim().ToUpper() -eq ([string]$Codigo).Trim().ToUpper() })
            if ($exato.Count -gt 0) { return $exato[0] }
            continue
        }
        if ($hits.Count -gt 0) { return $hits[0] }
    }
    return $null
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
        id_cliente = $clientePadraoId
        nome_cliente = $clientePadrao
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
        [string]$ValorUnitario = '0.00'
    )

    $payload = [ordered]@{
        qtde_produto = '1'
        id_produto = $IdProduto
        valor_unit_produto = Normalize-VhsysValorUnitario $ValorUnitario
        desc_produto = ([string]$Descricao).Trim()
    }

    @([pscustomobject]$payload)
}

function Test-VhsysProdutoLocalizacao {
    param(
        [Parameter(Mandatory=$true)]$Response,
        [Parameter(Mandatory=$true)][int]$IdProduto,
        [Parameter(Mandatory=$true)][int]$IdAlmoxarifado
    )

    foreach ($produto in @($Response.data)) {
        if ([int]$produto.id_produto -ne $IdProduto) { continue }
        if ($produto.PSObject.Properties['id_almoxarifado'] -and [int]$produto.id_almoxarifado -eq $IdAlmoxarifado) {
            return $true
        }
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
    return $out
}

function Invoke-VhsysJson {
    param(
        [Parameter(Mandatory=$true)]$Config,
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Method,
        $Body = $null,
        [int]$TimeoutSec = 20
    )

    $uri = '{0}{1}' -f $Config.ApiBaseUrl.TrimEnd('/'), $Path
    $headers = New-AltertagApiHeaders -AccessToken $Config.AccessToken -SecretAccessToken $Config.SecretAccessToken
    if ($null -eq $Body) {
        $resp = Invoke-RestMethod -Uri $uri -Method $Method -Headers $headers -TimeoutSec $TimeoutSec -ErrorAction Stop
        return (Assert-VhsysSuccess -Response $resp -Contexto $Path)
    }
    $jsonBody = $Body | ConvertTo-Json -Depth 8 -Compress
    $resp = Invoke-RestMethod -Uri $uri -Method $Method -Headers $headers -Body $jsonBody -TimeoutSec $TimeoutSec -ErrorAction Stop
    return (Assert-VhsysSuccess -Response $resp -Contexto $Path)
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

function Add-VhsysStatusNaOrdemServico {
    param(
        [int]$IdOrdem = 0,
        [int]$OsNumero = 0,
        [Parameter(Mandatory=$true)][string]$Status,
        [string]$Observacao = ''
    )

    $cfg = Read-AltertagApiConfig
    $id = Resolve-VhsysIdOrdem -IdOrdem $IdOrdem -OsNumero $OsNumero
    $payload = New-VhsysOrdemStatusPayload -Status $Status -Observacao $Observacao
    $resp = Invoke-VhsysJson -Config $cfg -Path ("/ordens-servico/{0}/status" -f $id) -Method 'Post' -Body $payload -TimeoutSec 20
    [pscustomobject]@{
        ok = $true
        idOrdem = $id
        status = [string]$payload.tipo_status
        observacao = [string]$payload.obs_status
        resposta = $resp
    }
}

function Add-VhsysProdutoNaOrdemServico {
    param(
        [Parameter(Mandatory=$true)]$Config,
        [Parameter(Mandatory=$true)][int]$IdOrdem,
        [Parameter(Mandatory=$true)][int]$IdPedido,
        [Parameter(Mandatory=$true)][int]$IdProduto,
        [Parameter(Mandatory=$true)][string]$ProdutoDescricao,
        [string]$ProdutoValor = '0.00'
    )

    $prodPath = "/ordens-servico/{0}/produtos" -f $IdOrdem
    $prodPayload = New-VhsysOrdemProdutoPayload -IdProduto $IdProduto -Descricao $ProdutoDescricao -ValorUnitario $ProdutoValor
    $prodResp = Invoke-VhsysJson -Config $Config -Path $prodPath -Method 'Post' -Body $prodPayload -TimeoutSec 25

    return $prodResp
}

function Add-VhsysServicosNaOrdemServico {
    param(
        [Parameter(Mandatory=$true)]$Config,
        [Parameter(Mandatory=$true)][int]$IdOrdem,
        [Parameter(Mandatory=$true)][int]$IdPedido,
        [object[]]$Servicos = @()
    )

    $servPayload = @(New-VhsysOrdemServicosPayload -Servicos $Servicos)
    $servResp = @()
    $servErro = $null
    $servAdicionados = @()
    if ($servPayload.Count -gt 0) {
        $servPath = "/ordens-servico/{0}/servicos" -f $IdOrdem
        try {
            $servResp = @(Invoke-VhsysJson -Config $Config -Path $servPath -Method 'Post' -Body $servPayload -TimeoutSec 25)
            $servAdicionados = @($servPayload | ForEach-Object { [string]$_.desc_servico })
        } catch {
            $erroLote = $_.Exception.Message
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Servicos em lote falharam na OS $IdPedido; tentando um por vez: $erroLote"
            $errosIndividuais = @()
            foreach ($svcPayload in @($servPayload)) {
                try {
                    $respItem = Invoke-VhsysJson -Config $Config -Path $servPath -Method 'Post' -Body @($svcPayload) -TimeoutSec 20
                    $servResp += $respItem
                    $servAdicionados += [string]$svcPayload.desc_servico
                } catch {
                    $errosIndividuais += ('{0}: {1}' -f ([string]$svcPayload.desc_servico), $_.Exception.Message)
                }
            }
            if ($errosIndividuais.Count -gt 0) {
                $servErro = $errosIndividuais -join ' | '
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] OS $IdPedido reparada, mas alguns servicos falharam: $servErro"
            }
        }
    }

    [pscustomobject]@{
        servicos = @($servAdicionados)
        servicosErro = $servErro
        servicosResposta = $servResp
    }
}

function New-VhsysOrdemServico {
    param(
        [Parameter(Mandatory=$true)][string]$Tecnico,
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string]$Referencia,
        [Parameter(Mandatory=$true)][int]$IdProduto,
        [Parameter(Mandatory=$true)][string]$ProdutoDescricao,
        [string]$ProdutoValor = '0.00',
        [object[]]$Servicos = @()
    )

    if (-not ($tecnicosPermitidos -contains $Tecnico.Trim().ToUpper())) {
        throw 'Tecnico invalido. Use: Lucas, Hyrides, Vitor ou Erick'
    }
    if (-not $Serial.Trim()) { throw 'Campo serial obrigatorio' }
    if ($IdProduto -lt 1) { throw 'Produto sem id_produto valido' }
    if (-not $ProdutoDescricao.Trim()) { throw 'Descricao do produto obrigatoria' }

    $cfg = Read-AltertagApiConfig
    $osPayload = New-VhsysOrdemServicoPayload -Tecnico $Tecnico -Serial $Serial -Referencia $Referencia -Equipamento ''
    $osResp = Invoke-VhsysJson -Config $cfg -Path '/ordens-servico' -Method 'Post' -Body $osPayload -TimeoutSec 25
    $idOrdem = [int]$osResp.data.id_ordem
    $idPedido = [int]$osResp.data.id_pedido
    if ($idOrdem -lt 1) { throw 'API vhsys nao retornou id_ordem ao criar OS.' }

    $prodResp = $null
    $produtoErro = $null
    try {
        $prodResp = Add-VhsysProdutoNaOrdemServico -Config $cfg -IdOrdem $idOrdem -IdPedido $idPedido -IdProduto $IdProduto -ProdutoDescricao $ProdutoDescricao -ProdutoValor $ProdutoValor
    } catch {
        $produtoErro = $_.Exception.Message
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] OS $idPedido criada, mas o produto falhou: $produtoErro"
    }
    $servOut = Add-VhsysServicosNaOrdemServico -Config $cfg -IdOrdem $idOrdem -IdPedido $idPedido -Servicos $Servicos

    try {
        Reconcile-OsState -UltimoConfirmado $idPedido -Fonte 'vhsys_api_create' -Observacao 'OS criada pelo CAIJ InfoNotebook.' | Out-Null
    } catch {}

    [pscustomobject]@{
        ok = $true
        idOrdem = $idOrdem
        osNumero = $idPedido
        osCodigo = ('C{0:D6}' -f [int]$idPedido)
        cliente = $clientePadrao
        tecnico = $Tecnico.Trim().ToUpper()
        garantia = $Serial.Trim()
        referencia = $Referencia.Trim()
        produto = $ProdutoDescricao.Trim()
        idProduto = $IdProduto
        idAlmoxarifado = $almoxarifadoBancadaTecnicaId
        produtoErro = $produtoErro
        servicos = @($servOut.servicos)
        servicosErro = $servOut.servicosErro
        produtoResposta = $prodResp
        servicosResposta = $servOut.servicosResposta
    }
}

function Add-VhsysProdutosResumoToOrdens {
    param(
        [Parameter(Mandatory=$true)][object[]]$Ordens,
        [Parameter(Mandatory=$true)]$Config
    )

    foreach ($os in @($Ordens)) {
        $produtos = @()
        try {
            $produtos = @(Get-VhsysProdutosOrdemServico -Config $Config -IdOrdem ([int]$os.idOrdem))
        } catch {
            $produtos = @()
        }
        $nomes = @($produtos | ForEach-Object { [string]$_.descricao } | Where-Object { $_.Trim() -ne '' })
        $resumo = if ($nomes.Count -gt 0) { $nomes -join ' | ' } else { [string]$os.equipamento }
        $os | Add-Member -NotePropertyName produtoResumo -NotePropertyValue $resumo -Force
        if ($nomes.Count -gt 0 -and $resumo) {
            $os.equipamento = $resumo
        }
    }
}

function Sync-OsFromApi {
    $ordens = @(Get-VhsysOrdensServicoRecentes -Limit 10 | ForEach-Object { $_ })
    if (-not $ordens -or $ordens.Count -eq 0) { throw 'API vhsys nao retornou ordens de servico.' }
    $ultima = @($ordens | Sort-Object -Property numero -Descending | Select-Object -First 1)[0]
    $ultimoApi = [int](@($ultima.numero)[0])
    return [pscustomobject]@{
        ok = $true
        ultimoSite = $ultimoApi
        status = 'ok'
        fonte = 'vhsys_api'
        ordens = $ordens
    }
}

function Get-JsonBody {
    param($Request)
    $reader = New-Object System.IO.StreamReader($Request.InputStream, [System.Text.Encoding]::UTF8)
    $raw = $reader.ReadToEnd()
    $reader.Close()
    if (-not $raw -or $raw.Trim() -eq '') { return $null }
    return ($raw | ConvertFrom-Json)
}

function Initialize-OsState {
    if (Test-Path $estadoOsArquivo) { return }
    $initial = [ordered]@{
        ultimoConfirmado = 235
        proximoDisponivel = 236
        status = 'pending_sync'
        fonte = 'local_seed'
        atualizadoEm = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        observacao = 'Estado inicial criado localmente.'
        autoSync = [ordered]@{
            intervaloMin = $autoSyncIntervalMin
            ultimaTentativaEm = $null
            ultimoSucessoEm = $null
            ultimoErro = $null
            ultimoValorSite = $null
            tentativas = 0
            sucessos = 0
        }
    }
    $initial | ConvertTo-Json -Depth 5 | Set-Content -Path $estadoOsArquivo -Encoding UTF8
}

function Get-OsState {
    Initialize-OsState
    $raw = Get-Content -Path $estadoOsArquivo -Raw -ErrorAction Stop
    return ($raw | ConvertFrom-Json -ErrorAction Stop)
}

function Save-OsState {
    param($State)
    if (-not $State.autoSync) {
        $State | Add-Member -NotePropertyName autoSync -NotePropertyValue ([ordered]@{
            intervaloMin = $autoSyncIntervalMin
            ultimaTentativaEm = $null
            ultimoSucessoEm = $null
            ultimoErro = $null
            ultimoValorSite = $null
            tentativas = 0
            sucessos = 0
        }) -Force
    }
    $State.atualizadoEm = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $State | ConvertTo-Json -Depth 5 | Set-Content -Path $estadoOsArquivo -Encoding UTF8
}

function Invoke-WithOsLock {
    param([scriptblock]$Action)
    $m = New-Object System.Threading.Mutex($false, $mutexOsName)
    $hasLock = $false
    try {
        $hasLock = $m.WaitOne(6000)
        if (-not $hasLock) { throw 'Timeout de lock ao atualizar estado de OS.' }
        return & $Action
    } finally {
        if ($hasLock) { try { $m.ReleaseMutex() | Out-Null } catch {} }
        try { $m.Dispose() } catch {}
    }
}

function Reserve-NextOs {
    return Invoke-WithOsLock {
        $st = Get-OsState
        $current = [int]$st.proximoDisponivel
        if ($current -lt 1) { $current = 236 }
        $st.ultimoReservado = $current
        $st.proximoDisponivel = $current + 1
        if (-not $st.status) { $st.status = 'ok' }
        if (-not $st.fonte) { $st.fonte = 'manual_or_seed' }
        Save-OsState -State $st
        return [ordered]@{
            reservado = $current
            proximo = [int]$st.proximoDisponivel
            status = [string]$st.status
            fonte = [string]$st.fonte
            atualizadoEm = [string]$st.atualizadoEm
        }
    }
}

function Reconcile-OsState {
    param(
        [int]$UltimoConfirmado,
        [string]$Fonte = 'external_collector',
        [string]$Observacao = ''
    )
    return Invoke-WithOsLock {
        $st = Get-OsState
        if ($UltimoConfirmado -lt 1) { throw 'UltimoConfirmado invalido.' }
        $st.ultimoConfirmado = $UltimoConfirmado
        $st.proximoDisponivel = $UltimoConfirmado + 1
        $st.status = 'ok'
        $st.fonte = $Fonte
        $st.observacao = $Observacao
        Save-OsState -State $st
        return $st
    }
}

function Sync-OsFromSite {
    return Invoke-WithOsLock {
        $st = Get-OsState
        $now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        if (-not $st.autoSync) {
            $st | Add-Member -NotePropertyName autoSync -NotePropertyValue ([ordered]@{
                intervaloMin = $autoSyncIntervalMin
                ultimaTentativaEm = $null
                ultimoSucessoEm = $null
                ultimoErro = $null
                ultimoValorSite = $null
                tentativas = 0
                sucessos = 0
            }) -Force
        }
        $st.autoSync.intervaloMin = $autoSyncIntervalMin
        $st.autoSync.ultimaTentativaEm = $now
        $st.autoSync.tentativas = [int]$st.autoSync.tentativas + 1

        try {
            try {
                $api = Sync-OsFromApi
                $ultimoApi = [int](@($api.ultimoSite)[0])
                if ($ultimoApi -ge [int]$st.ultimoConfirmado) {
                    $st.ultimoConfirmado = $ultimoApi
                    $st.proximoDisponivel = $ultimoApi + 1
                    $st.status = 'ok'
                    $st.fonte = 'vhsys_api'
                    $st.observacao = 'Reconciliado automaticamente via API oficial vhsys.'
                } else {
                    $st.status = 'divergente'
                    $st.fonte = 'vhsys_api'
                    $st.observacao = "API retornou OS menor ($ultimoApi) que o ultimoConfirmado local ($($st.ultimoConfirmado))."
                }
                $st.autoSync.ultimoValorSite = $ultimoApi
                $st.autoSync.ultimoSucessoEm = $now
                $st.autoSync.ultimoErro = $null
                $st.autoSync.sucessos = [int]$st.autoSync.sucessos + 1
                Save-OsState -State $st
                return [ordered]@{ ok = $true; ultimoSite = $ultimoApi; status = [string]$st.status; fonte = 'vhsys_api' }
            } catch {
                $apiErro = $_.Exception.Message
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] API vhsys falhou: $apiErro"
                throw ([Exception]::new("Falha na API vhsys: $apiErro"))
            }

            $site = Get-AltertagLastOs
            if (-not $site.ok -or -not $site.ultimo) {
                throw ([Exception]::new((if ($site.mensagem) { [string]$site.mensagem } else { 'Falha ao ler OS no site.' })))
            }

            $ultimoSite = [int]$site.ultimo
            $st.autoSync.ultimoValorSite = $ultimoSite
            $st.autoSync.ultimoSucessoEm = $now
            $st.autoSync.ultimoErro = $null
            $st.autoSync.sucessos = [int]$st.autoSync.sucessos + 1

            if ($ultimoSite -ge [int]$st.ultimoConfirmado) {
                $st.ultimoConfirmado = $ultimoSite
                $st.proximoDisponivel = $ultimoSite + 1
                $st.status = 'ok'
                $st.fonte = 'altertag_auto_sync'
                $st.observacao = 'Reconciliado automaticamente com o site.'
            } else {
                $st.status = 'divergente'
                $st.fonte = 'altertag_auto_sync'
                $st.observacao = "Site retornou OS menor ($ultimoSite) que o ultimoConfirmado local ($($st.ultimoConfirmado))."
            }

            Save-OsState -State $st
            return [ordered]@{ ok = $true; ultimoSite = $ultimoSite; status = [string]$st.status }
        } catch {
            $st.status = 'pending_sync'
            $st.fonte = 'altertag_auto_sync'
            $st.observacao = 'Falha na sincronizacao automatica com o site.'
            $st.autoSync.ultimoErro = $_.Exception.Message
            Save-OsState -State $st
            return [ordered]@{ ok = $false; erro = $_.Exception.Message; status = [string]$st.status }
        }
    }
}

function Get-ProdutoMap {
    if (Test-Path $mapaProdutosArquivo) {
        try {
            $raw = Get-Content -Path $mapaProdutosArquivo -Raw -ErrorAction Stop
            $arr = $raw | ConvertFrom-Json -ErrorAction Stop
            if ($arr) { return @($arr) }
        } catch {}
    }
    $seed = @(
        @{
            nome = 'Lenovo T14 i5 11th 8GB 256 SSD'
            modelo_regex = '(?i)Lenovo\s+T14'
            cpu_regex = '(?i)(i5.*11|11.*i5)'
            ram_regex = '(?i)\b8GB\b'
            disco_regex = '(?i)\b(238|240|250|256)GB\b.*SSD'
            produto_codigo = 'A032-C2F'
        },
        @{
            nome = 'Lenovo T14 i5 10th 16GB 256 SSD'
            modelo_regex = '(?i)Lenovo\s+T14'
            cpu_regex = '(?i)(i5.*10|10.*i5)'
            ram_regex = '(?i)\b16GB\b'
            disco_regex = '(?i)\b(238|240|250|256)GB\b.*SSD'
            produto_codigo = 'A031-C3F'
        }
    )
    try { $seed | ConvertTo-Json | Set-Content -Path $mapaProdutosArquivo -Encoding UTF8 } catch {}
    return $seed
}

function Resolve-ProdutoCodigo {
    param(
        [string]$Modelo,
        [string]$Cpu,
        [string]$Ram,
        [string]$Disco,
        [string]$ProdutoCodigoManual
    )
    if ($ProdutoCodigoManual -and $ProdutoCodigoManual.Trim() -ne '') {
        return @{ ok = $true; codigo = $ProdutoCodigoManual.Trim().ToUpper(); regra = 'manual' }
    }

    $produtosCsv = Get-ProdutosExport
    if ($produtosCsv -and $produtosCsv.Count -gt 0) {
        $modeloUp = if ($Modelo) { $Modelo.ToUpper() } else { '' }
        $cpuUp = if ($Cpu) { $Cpu.ToUpper() } else { '' }
        $ramUp = if ($Ram) { $Ram.ToUpper() } else { '' }
        $discoUp = if ($Disco) { $Disco.ToUpper() } else { '' }
        $csvHits = foreach ($p in $produtosCsv) {
            $nome = [string]$p.Nome
            $u = $nome.ToUpper()
            $score = 0
            if ($modeloUp -match '\bE14\b' -and $u -match '\bE14\b') { $score += 6 }
            if ($modeloUp -match '\bT14\b' -and $u -match '\bT14\b') { $score += 6 }
            if ($modeloUp -match '\bVOSTRO\b' -and $u -match '\bVOSTRO\b') { $score += 6 }
            if ($cpuUp -match '\bI7\b' -and $u -match '\bI7\b') { $score += 5 }
            if ($cpuUp -match '\bI5\b' -and $u -match '\bI5\b') { $score += 5 }
            if ($cpuUp -match '11' -and $u -match '11TH') { $score += 4 }
            if ($cpuUp -match '10' -and $u -match '10TH') { $score += 4 }
            if ($ramUp -match '\b16GB\b' -and $u -match '\b16GB\b') { $score += 4 }
            if ($ramUp -match '\b8GB\b' -and $u -match '\b8GB\b') { $score += 4 }
            if ($discoUp -match '\b(476|480|500|512)GB\b' -and $u -match '\b512GB\b') { $score += 4 }
            if ($discoUp -match '\b(238|240|250|256)GB\b' -and $u -match '\b256GB\b') { $score += 4 }
            if ($score -gt 0) {
                [pscustomobject]@{
                    Codigo = [string]$p.Codigo
                    Nome = [string]$p.Nome
                    Score = $score
                }
            }
        }

        $ordenadosCsv = @($csvHits | Sort-Object -Property @{ Expression = 'Score'; Descending = $true }, @{ Expression = 'Nome'; Descending = $false })
        if ($ordenadosCsv.Count -eq 1) {
            return @{ ok = $true; codigo = [string]$ordenadosCsv[0].Codigo; regra = [string]$ordenadosCsv[0].Nome; tipo = 'csv' }
        }
        if ($ordenadosCsv.Count -gt 1) {
            $melhor = [int]$ordenadosCsv[0].Score
            $empatados = @($ordenadosCsv | Where-Object { [int]$_.Score -eq $melhor })
            if ($empatados.Count -eq 1 -and $melhor -ge 12) {
                return @{ ok = $true; codigo = [string]$empatados[0].Codigo; regra = [string]$empatados[0].Nome; tipo = 'csv' }
            }
            return @{ ok = $false; motivo = 'ambigua'; opcoes = @($ordenadosCsv | Select-Object -First 12 | ForEach-Object { '{0} {1}' -f $_.Codigo, $_.Nome }) }
        }
    }

    $mapa = Get-ProdutoMap
    $hitsExatos = @()
    $hitsAprox  = @()
    foreach ($r in $mapa) {
        $checks = @(
            @{ field = 'modelo'; rx = [string]$r.modelo_regex; val = [string]$Modelo }
            @{ field = 'cpu';    rx = [string]$r.cpu_regex;    val = [string]$Cpu }
            @{ field = 'ram';    rx = [string]$r.ram_regex;    val = [string]$Ram }
            @{ field = 'disco';  rx = [string]$r.disco_regex;  val = [string]$Disco }
        )
        $required = 0
        $matched  = 0
        foreach ($c in $checks) {
            if ($c.rx -and $c.rx.Trim() -ne '') {
                $required++
                if ($c.val -match $c.rx) { $matched++ }
            }
        }
        if ($required -gt 0 -and $matched -eq $required) {
            $hitsExatos += $r
            continue
        }
        # Aproximado: permite 1 divergencia quando a regra tem 3+ criterios
        if ($required -ge 3 -and $matched -ge ($required - 1)) {
            $hitsAprox += $r
        }
    }

    if ($hitsExatos.Count -eq 1) {
        return @{ ok = $true; codigo = [string]$hitsExatos[0].produto_codigo; regra = [string]$hitsExatos[0].nome; tipo='exato' }
    }
    if ($hitsExatos.Count -gt 1) {
        return @{ ok = $false; motivo = 'ambigua'; opcoes = @($hitsExatos | ForEach-Object { $_.produto_codigo }) }
    }
    if ($hitsAprox.Count -eq 1) {
        return @{ ok = $true; codigo = [string]$hitsAprox[0].produto_codigo; regra = [string]$hitsAprox[0].nome; tipo='aprox' }
    }
    if ($hitsAprox.Count -gt 1) {
        return @{ ok = $false; motivo = 'ambigua'; opcoes = @($hitsAprox | ForEach-Object { $_.produto_codigo }) }
    }
    return @{ ok = $false; motivo = 'nao_encontrado'; opcoes = @() }
}

function Invoke-AltertagTriagem {
    param(
        [string]$Serial,
        [string]$Tecnico,
        [string]$Cliente,
        [string]$ProdutoCodigo,
        [string]$Grade,
        [string[]]$Servicos,
        [switch]$GradeComoServico = $true
    )

    # Automacao via Brave (perfil logado da maquina principal).
    # Obs: em sites com CAPTCHA/JS moderno pode falhar e retornar erro controlado.
    $url = 'https://app.altertag.com.br/index.php?Secao=Servicos.Ordem&Modulo=Servicos#!cadastrar'
    $result = [ordered]@{
        ok = $false
        osNumero = $null
        mensagem = ''
    }

    try {
        Start-BraveAutomation -Url $url

        $servicosTxt = @()
        if ($GradeComoServico -and $Grade) { $servicosTxt += "GRADE $Grade" }
        if ($Servicos) { $servicosTxt += @($Servicos | Where-Object { $_ -and $_.Trim() -ne '' }) }
        $resumo = @(
            "CLIENTE: $Cliente"
            "TECNICO: $Tecnico"
            "PRODUTO: $ProdutoCodigo"
            "GARANTIA/SERIAL: $Serial"
            "SERVICOS: $($servicosTxt -join ' | ')"
        ) -join [Environment]::NewLine
        try { [System.Windows.Forms.Clipboard]::SetText($resumo) } catch {}

        $data = @{
            cliente = $Cliente
            tecnico = $Tecnico
            produto = $ProdutoCodigo
            garantia = $Serial
            referencia = $Grade
            servicos = $servicosTxt
        } | ConvertTo-Json -Compress

$js = @"
(async function(){
  const data = $data;
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const norm = s => (s || '').toString().normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().trim();
  const visible = el => {
    if(!el) return false;
    const r = el.getBoundingClientRect();
    const st = getComputedStyle(el);
    return r.width > 1 && r.height > 1 && st.visibility !== 'hidden' && st.display !== 'none';
  };
  const log = [];

  function badge(text, color = '#0aa0eb'){
    let b = document.getElementById('caij-automation-badge');
    if(!b){
      b = document.createElement('div');
      b.id = 'caij-automation-badge';
      b.style.cssText = 'position:fixed;z-index:999999;right:14px;top:14px;max-width:360px;background:#07121f;color:white;border:2px solid #0aa0eb;padding:10px 12px;font:12px Segoe UI,Arial;border-radius:4px;box-shadow:0 6px 24px rgba(0,0,0,.28);white-space:pre-line';
      document.body.appendChild(b);
    }
    b.style.borderColor = color;
    b.textContent = text;
  }

  badge('CAIJ: aguardando tela do Altertag...');
  for(let i=0;i<14;i++){
    const txt = norm(document.body?.innerText || '');
    if(txt.includes('dados da ordem') || txt.includes('cliente') || txt.includes('produto')) break;
    await sleep(500);
  }

  if (document.querySelector('input[type=password]')) {
    badge('CAIJ: precisa fazer login neste perfil do Brave.', '#eb4b52');
    return { ok:false, precisaLogin:true, mensagem:'O perfil de automacao do Brave ainda nao esta logado no Altertag.' };
  }

  function setVal(el, value){
    if(!el) return false;
    el.focus();
    const proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
    const setter = Object.getOwnPropertyDescriptor(proto, 'value')?.set;
    if(setter) setter.call(el, value); else el.value = value;
    el.dispatchEvent(new Event('input', {bubbles:true}));
    el.dispatchEvent(new Event('change', {bubbles:true}));
    return true;
  }

  const allFields = () => [...document.querySelectorAll('input:not([type=hidden]):not([type=button]):not([type=submit]), textarea, select')]
    .filter(visible)
    .filter(x => !x.disabled && !x.readOnly);

  function fieldNearLabel(labelText, index = 0){
    const wanted = norm(labelText);
    const labels = [...document.querySelectorAll('label, span, div, td, th, small')]
      .filter(x => visible(x) && norm(x.textContent).includes(wanted));
    for(const label of labels){
      const forId = label.getAttribute && label.getAttribute('for');
      if(forId){
        const byFor = document.getElementById(forId);
        if(byFor && /input|textarea|select/i.test(byFor.tagName)) return byFor;
      }
      let p = label;
      for(let i=0; i<6 && p; i++, p=p.parentElement){
        const fields = [...p.querySelectorAll('input:not([type=hidden]), textarea, select')].filter(visible);
        if(fields[index]) return fields[index];
      }
    }
    return null;
  }

  function fieldByGeometry(labelText){
    const wanted = norm(labelText);
    const labels = [...document.querySelectorAll('label, span, div, td, th, small')]
      .filter(x => visible(x) && norm(x.textContent).includes(wanted));
    const fields = allFields();
    let best = null, bestScore = 999999;
    for(const label of labels){
      const lr = label.getBoundingClientRect();
      for(const f of fields){
        const fr = f.getBoundingClientRect();
        const below = fr.top >= lr.top - 4;
        const nearX = Math.abs(fr.left - lr.left);
        const nearY = Math.abs(fr.top - lr.bottom);
        const right = fr.left >= lr.left - 10;
        if(!below || !right) continue;
        const score = nearY * 3 + nearX;
        if(score < bestScore){ bestScore = score; best = f; }
      }
    }
    return best;
  }

  function sectionFields(sectionName){
    const wanted = norm(sectionName);
    const heads = [...document.querySelectorAll('h1,h2,h3,h4,legend,div,span')]
      .filter(x => visible(x) && norm(x.textContent).includes(wanted));
    if(!heads.length) return [];
    const hr = heads[0].getBoundingClientRect();
    return allFields()
      .map(f => ({f, r:f.getBoundingClientRect()}))
      .filter(x => x.r.top > hr.bottom)
      .sort((a,b) => a.r.top - b.r.top || a.r.left - b.r.left)
      .map(x => x.f);
  }

  function fieldsNearHeading(headingText){
    const wanted = norm(headingText);
    const headings = [...document.querySelectorAll('h1,h2,h3,h4,legend,div,span')]
      .filter(x => visible(x) && norm(x.textContent).includes(wanted));
    if(!headings.length) return [];
    let node = headings[0];
    for(let i=0; i<5 && node; i++, node=node.parentElement){
      const fields = [...node.querySelectorAll('input:not([type=hidden]), textarea, select')].filter(visible);
      if(fields.length) return fields;
    }
    return [];
  }

  function headingBounds(headingText){
    const wanted = norm(headingText);
    const headings = [...document.querySelectorAll('h1,h2,h3,h4,legend,div,span')]
      .filter(x => visible(x) && norm(x.textContent).includes(wanted));
    return headings.length ? headings[0].getBoundingClientRect() : null;
  }

  function fieldsBetweenHeadings(startHeading, endHeadings){
    const start = headingBounds(startHeading);
    if(!start) return [];
    let endTop = Infinity;
    for(const h of endHeadings){
      const r = headingBounds(h);
      if(r && r.top > start.bottom && r.top < endTop) endTop = r.top;
    }
    return allFields()
      .filter(f => /input|textarea/i.test(f.tagName))
      .filter(f => {
        const r = f.getBoundingClientRect();
        return r.top > start.bottom && r.top < endTop - 4;
      });
  }

  function codeFieldsInSection(startHeading, endHeadings){
    const editable = fieldsBetweenHeadings(startHeading, endHeadings);
    const rows = [];
    for(const f of editable){
      const r = f.getBoundingClientRect();
      if(r.width < 80 || r.height < 10) continue;
      let row = rows.find(x => Math.abs(x.top - r.top) < 12);
      if(!row){ row = {top:r.top, fields:[]}; rows.push(row); }
      row.fields.push({f, r});
    }
    return rows
      .sort((a,b) => a.top - b.top)
      .map(row => row.fields.sort((a,b) => b.r.width - a.r.width || a.r.left - b.r.left)[0]?.f)
      .filter(Boolean);
  }

  function serviceCodeFields(){
    return codeFieldsInSection('Servicos', ['Produtos', 'Totais']);
  }

  function productCodeField(){
    const fields = codeFieldsInSection('Produtos', ['Totais', 'Detalhes']);
    return fields.length ? fields[0] : null;
  }

  async function chooseSuggestion(text){
    await sleep(450);
    const wanted = norm(text);
    const opts = [...document.querySelectorAll('li, .ui-menu-item, .select2-results__option, [role=option], .autocomplete-suggestion, .tt-suggestion, div')]
      .filter(x => visible(x) && norm(x.textContent).length > 0)
      .filter(x => {
        const t = norm(x.textContent);
        return t.includes(wanted) || t.includes(wanted.split(/\s+/)[0]) || wanted.includes(t.split(/\s+/)[0]);
      });
    if(opts.length){
      opts[0].dispatchEvent(new MouseEvent('mousedown', {bubbles:true}));
      opts[0].click();
      await sleep(500);
      return true;
    }
    document.activeElement?.dispatchEvent(new KeyboardEvent('keydown', {key:'Enter', code:'Enter', bubbles:true}));
    await sleep(300);
    return false;
  }

  async function fillAuto(label, value){
    const el = fieldNearLabel(label) || fieldByGeometry(label);
    if(!el){ log.push('Campo nao encontrado: ' + label); return false; }
    setVal(el, value);
    await chooseSuggestion(value);
    log.push(label + ': preenchido');
    return true;
  }

  await fillAuto('Cliente', data.cliente);
  await fillAuto('Tecnico', data.tecnico);

  const prod = productCodeField() || fieldNearLabel('Produto') || fieldByGeometry('Produto') || sectionFields('Produtos')[0];
  if(prod){ setVal(prod, data.produto); await chooseSuggestion(data.produto); log.push('Produto: preenchido'); }
  else log.push('Campo nao encontrado: Produto');

  const garantia = fieldNearLabel('Garantia') || fieldByGeometry('Garantia');
  if(garantia){ setVal(garantia, data.garantia); log.push('Garantia: preenchida'); }
  else log.push('Campo nao encontrado: Garantia');

  const referencia = fieldNearLabel('Referencia') || fieldByGeometry('Referencia');
  if(referencia && data.referencia){ setVal(referencia, data.referencia); log.push('Referencia: preenchida'); }

  const servFields = serviceCodeFields();
  if(servFields.length && data.servicos && data.servicos.length){
    setVal(servFields[0], data.servicos[0]);
    await chooseSuggestion(data.servicos[0]);
    log.push('Servico principal: ' + data.servicos[0]);
  }

  if(data.servicos && data.servicos.length > 1){
    for(let i=1; i<data.servicos.length; i++){
      const add = [...document.querySelectorAll('a,button')].find(x => visible(x) && norm(x.textContent).includes('adicionar outro servico'));
      if(add){ add.click(); await sleep(700); }
      const fs = serviceCodeFields();
      const target = fs.find(x => !x.value) || fs[fs.length-1];
      if(target){ setVal(target, data.servicos[i]); await chooseSuggestion(data.servicos[i]); log.push('Servico extra: ' + data.servicos[i]); }
    }
  }

  const save = [...document.querySelectorAll('button,input[type=submit],a')]
    .find(x => visible(x) && /salvar|cadastrar|gravar/i.test(x.innerText || x.value || ''));
  if(save){
    save.scrollIntoView({block:'center'});
    await sleep(300);
    save.click();
    await sleep(1500);
    log.push('Botao salvar/cadastrar acionado');
  } else {
    log.push('Botao salvar/cadastrar nao encontrado');
  }

  badge('CAIJ automacao executada:\n' + log.join('\n'), log.some(x => x.includes('nao encontrado')) ? '#f5be46' : '#00cd7d');

  let os = null;
  const html = document.documentElement.innerText + '\n' + document.documentElement.outerHTML;
  const m = html.match(/(?:numero\s+da\s+os|n[uú]mero\s+da\s+os|os[#:\s]*)(?:\D{0,30})(\d{2,8})/i);
  if(m) os = m[1];

  return { ok:true, osNumero:os, mensagem:'Automacao executada no Altertag.', log };
})()
"@

        $wsUrl = Get-BravePageTarget -UrlPart 'app.altertag.com.br'
        $eval = Invoke-BraveRuntimeEvaluate -WebSocketUrl $wsUrl -Expression $js
        $value = $eval.result.result.value

        if ($value.precisaLogin) {
            $result.ok = $false
            $result.mensagem = $value.mensagem
            return $result
        }

        $result.ok = $true
        $result.osNumero = $value.osNumero
        $logMsg = ''
        if ($value.log) { $logMsg = ' | ' + (($value.log | ForEach-Object { [string]$_ }) -join ' | ') }
        $result.mensagem = if ($value.mensagem) { ([string]$value.mensagem + $logMsg) } else { ('Automacao enviada ao Altertag.' + $logMsg) }
        return $result
    } catch {
        $result.mensagem = $_.Exception.Message
        return $result
    }
}

function Invoke-TriagemLock {
    param([scriptblock]$Script)
    [System.Threading.Monitor]::Enter($script:triagemLock)
    try { & $Script }
    finally { [System.Threading.Monitor]::Exit($script:triagemLock) }
}

function New-TriagemJob {
    param(
        [string]$Serial,
        [string]$Tecnico,
        [string]$Cliente,
        [string]$ProdutoCodigo,
        [string]$Grade,
        [string[]]$Servicos
    )
    $id = [guid]::NewGuid().ToString('N')
    $job = [ordered]@{
        id = $id
        criadoEm = Get-Date
        atualizadoEm = Get-Date
        status = 'queued'
        tentativas = 0
        maxTentativas = 4
        proximaTentativaEm = Get-Date
        erro = $null
        osNumero = $null
        payload = [ordered]@{
            serial = $Serial
            tecnico = $Tecnico
            cliente = $Cliente
            produtoCodigo = $ProdutoCodigo
            grade = $Grade
            servicos = @($Servicos)
        }
    }
    Invoke-TriagemLock {
        $script:triagemJobs[$id] = $job
        [void]$script:triagemQueue.Add($id)
    }
    return $job
}

function Get-TriagemJob {
    param([string]$Id)
    $found = $null
    Invoke-TriagemLock {
        if ($script:triagemJobs.ContainsKey($Id)) { $found = $script:triagemJobs[$Id] }
    }
    return $found
}

function Process-TriagemQueue {
    if ($script:triagemWorkerBusy) { return }
    $script:triagemWorkerBusy = $true
    try {
        $job = $null
        Invoke-TriagemLock {
            foreach ($jid in @($script:triagemQueue)) {
                if (-not $script:triagemJobs.ContainsKey($jid)) { continue }
                $cand = $script:triagemJobs[$jid]
                if ($cand.status -eq 'queued' -and [datetime]$cand.proximaTentativaEm -le (Get-Date)) {
                    $job = $cand
                    break
                }
            }
            if ($job) {
                $job.status = 'running'
                $job.atualizadoEm = Get-Date
                $script:triagemJobs[$job.id] = $job
            }
        }
        if (-not $job) { return }

        $p = $job.payload
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Worker triagem iniciando job=$($job.id) serial=$($p.serial) produto=$($p.produtoCodigo)"
        $out = Invoke-AltertagTriagem -Serial $p.serial -Tecnico $p.tecnico -Cliente $p.cliente -ProdutoCodigo $p.produtoCodigo -Grade $p.grade -Servicos $p.servicos

        Invoke-TriagemLock {
            if ($out.ok) {
                $job.status = 'ok'
                $job.osNumero = $out.osNumero
                $job.erro = $null
                [void]$script:triagemQueue.Remove($job.id)
            } else {
                $job.tentativas = [int]$job.tentativas + 1
                $job.erro = [string]$out.mensagem
                if ($job.tentativas -ge [int]$job.maxTentativas) {
                    $job.status = 'erro'
                    [void]$script:triagemQueue.Remove($job.id)
                } else {
                    $job.status = 'queued'
                    $job.proximaTentativaEm = (Get-Date).AddSeconds(15)
                }
            }
            $job.atualizadoEm = Get-Date
            $script:triagemJobs[$job.id] = $job
        }
    } catch {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Worker triagem erro: $($_.Exception.Message)"
    } finally {
        $script:triagemWorkerBusy = $false
    }
}

Write-Host '======================================'
Write-Host ' CAIJ - Servidor de Impressao v5'
Write-Host " Porta:      $porta"
Write-Host " Impressora: $impressora"
Write-Host ' Aguardando requisicoes...'
Write-Host '======================================'

function Ensure-CaijFirewallRule {
    try {
        $ruleNames = @('CAIJ Servidor 9100', 'CAIJ HTTP Listener 9100', 'CAIJ Servidor Impressao TCP 9100')
        foreach ($ruleName in $ruleNames) {
            $existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
            if ($existing) {
                Set-NetFirewallRule -DisplayName $ruleName -Enabled True -Direction Inbound -Action Allow -Profile Any -EdgeTraversalPolicy Allow -ErrorAction SilentlyContinue | Out-Null
                try {
                    Set-NetFirewallPortFilter -AssociatedNetFirewallRule $existing -Protocol TCP -LocalPort $porta -ErrorAction SilentlyContinue | Out-Null
                } catch {}
                try {
                    Set-NetFirewallAddressFilter -AssociatedNetFirewallRule $existing -LocalAddress Any -RemoteAddress Any -ErrorAction SilentlyContinue | Out-Null
                } catch {}
            } else {
                New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow -Protocol TCP -LocalPort $porta -Profile Any -LocalAddress Any -RemoteAddress Any -EdgeTraversalPolicy Allow | Out-Null
            }
        }

        try {
            & netsh advfirewall firewall add rule name="CAIJ Servidor Impressao TCP 9100" dir=in action=allow protocol=TCP localport=$porta profile=any | Out-Null
        } catch {}

        Write-Host "[OK] Firewall liberado para TCP $porta em todos os perfis"
    } catch {
        Write-Host "[AVISO] Nao foi possivel ajustar firewall automaticamente: $($_.Exception.Message)"
        Write-Host '       Execute o servidor como Administrador.'
    }
}

function Get-CaijServerIp {
    try {
        return (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -match '^192\.168\.' -and $_.IPAddress -ne '127.0.0.1' } |
            Sort-Object InterfaceMetric |
            Select-Object -First 1 -ExpandProperty IPAddress)
    } catch {
        return $null
    }
}

function Test-CaijPortLocal {
    param([string]$Ip)
    if (-not $Ip) { return $false }
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $iar = $tcp.BeginConnect($Ip, $porta, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne(1200, $false)
        if ($ok) { $tcp.EndConnect($iar) }
        $tcp.Close()
        return [bool]$ok
    } catch {
        return $false
    }
}

Ensure-CaijFirewallRule

$listener = New-Object System.Net.HttpListener
foreach ($prefix in @("http://+:$porta/", "http://*:$porta/")) {
    try { $listener.Prefixes.Add($prefix) } catch {}
}
try {
    $ipServidorLocal = Get-CaijServerIp
    if ($ipServidorLocal) {
        try { $listener.Prefixes.Add("http://$ipServidorLocal`:$porta/") } catch {}
        Write-Host "[OK] Listener IPv4: http://$ipServidorLocal`:$porta/"
    }
} catch {}

try {
    $listener.Start()
    Write-Host '[OK] Servidor iniciado. Pressione CTRL+C para parar.'
    $script:caijServerIp = Get-CaijServerIp
    if ($script:caijServerIp) {
        Write-Host "[INFO] URL para notebooks: http://$script:caijServerIp`:$porta"
        Write-Host "[INFO] Teste local do IP remoto: $(Test-CaijPortLocal -Ip $script:caijServerIp)"
    }
} catch {
    Write-Host "[ERRO] Nao foi possivel iniciar: $($_.Exception.Message)"
    Write-Host 'Execute como Administrador.'
    Read-Host 'Pressione Enter para sair'
    exit
}

Initialize-OsState

try {
    $first = Sync-OsFromSite
    if ($first.ok) {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] AutoSync inicial OK. Ultima OS no site: $($first.ultimoSite)"
    } else {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] AutoSync inicial falhou: $($first.erro)"
    }
} catch {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] AutoSync inicial erro: $($_.Exception.Message)"
}

$autoSyncTimer = New-Object System.Timers.Timer
$autoSyncTimer.Interval = $autoSyncIntervalMin * 60 * 1000
$autoSyncTimer.AutoReset = $true
$null = Register-ObjectEvent -InputObject $autoSyncTimer -EventName Elapsed -Action {
    try {
        $res = Sync-OsFromSite
        if ($res.ok) {
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] AutoSync 30min OK. Ultima OS no site: $($res.ultimoSite)"
        } else {
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] AutoSync 30min falhou: $($res.erro)"
        }
    } catch {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] AutoSync 30min erro: $($_.Exception.Message)"
    }
}
$autoSyncTimer.Start()

function Send-JsonResponse {
    param(
        [Parameter(Mandatory = $true)] $Response,
        [Parameter(Mandatory = $true)][string]$Json
    )
    try {
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($Json)
        $Response.ContentType = 'application/json'
        $Response.ContentLength64 = $buffer.Length
        $Response.OutputStream.Write($buffer, 0, $buffer.Length)
    } catch {
        # Cliente desconectou antes/ao escrever (HttpListenerException/IOException/ObjectDisposed).
        # Nao interrompe o loop do servidor.
    } finally {
        try { $Response.OutputStream.Close() } catch {}
    }
}

function Send-TsplToPrinter {
    param(
        [Parameter(Mandatory=$true)][string]$Tspl,
        [string]$Prefix = 'caij_tspl'
    )

    $destino = "\\localhost\$impressora"

    try {
        $tmp = Join-Path $env:TEMP ("{0}_{1}_{2}.txt" -f $Prefix, $PID, ([guid]::NewGuid().ToString('N')))
        [System.IO.File]::WriteAllText($tmp, $Tspl, [System.Text.Encoding]::GetEncoding(850))

        # Nao bloqueia o HttpListener enquanto o spooler/compartilhamento processa a etiqueta.
        # Isso evita timeout de conexao nos outros notebooks durante impressoes lentas.
        $cmdExe = if ($env:ComSpec) { $env:ComSpec } else { 'cmd.exe' }
        $cmd = '/d /c copy /b "{0}" "{1}" >nul 2>&1 & del /q "{0}" >nul 2>&1' -f $tmp, $destino
        Start-Process -FilePath $cmdExe -ArgumentList $cmd -WindowStyle Hidden -ErrorAction Stop | Out-Null

        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Impressao enfileirada: $tmp -> $destino"
        return @{ ok=$true; saida='Enfileirado para impressora'; exitCode=0 }
    } catch {
        try { if ($tmp -and (Test-Path $tmp)) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } } catch {}
        return @{ ok=$false; saida=$_.Exception.Message; exitCode=1 }
    }
}

while ($listener.IsListening) {
    try {
        $context  = $listener.GetContext()
        $request  = $context.Request
        $response = $context.Response
        $horario  = Get-Date -Format 'HH:mm:ss'
        $metodo   = $request.HttpMethod
        $rota     = $request.Url.AbsolutePath

        if ($metodo -eq 'GET' -and $rota -eq '/status') {
            Write-Host "[$horario] Ping de status de $($request.RemoteEndPoint)"
            $json = (@{
                status='ok'
                mensagem='Servidor CAIJ ativo'
                versao='v6.2-popup-servicos'
                modoImpressao='assincrono'
                servidorIp=[string]$script:caijServerIp
                porta=[int]$porta
                url=("http://{0}:{1}" -f $script:caijServerIp, $porta)
            } | ConvertTo-Json -Compress)
            $response.StatusCode = 200

        } elseif ($metodo -eq 'GET' -and $rota -eq '/status-os') {
            try {
                try {
                    $api = Sync-OsFromApi
                    if ($api.ok -and $api.ultimoSite) {
                        $ultimoApiStatus = [int](@($api.ultimoSite)[0])
                        $stAtual = Get-OsState
                        if ($ultimoApiStatus -ge [int]$stAtual.ultimoConfirmado) {
                            Reconcile-OsState -UltimoConfirmado $ultimoApiStatus -Fonte 'vhsys_api' -Observacao 'Reconciliado sob demanda via /status-os.' | Out-Null
                        }
                    }
                } catch {
                    Write-Host "[$horario] /status-os sem refresh API: $($_.Exception.Message)"
                }
                $st = Get-OsState
                $json = (@{
                    status = 'ok'
                    ultimoConfirmado = [int]$st.ultimoConfirmado
                    proximoDisponivel = [int]$st.proximoDisponivel
                    fonte = [string]$st.fonte
                    sincronizacao = [string]$st.status
                    atualizadoEm = [string]$st.atualizadoEm
                    observacao = [string]$st.observacao
                    autoSync = $st.autoSync
                } | ConvertTo-Json -Compress)
                $response.StatusCode = 200
            } catch {
                $json = (@{ status='erro'; mensagem=$_.Exception.Message } | ConvertTo-Json -Compress)
                $response.StatusCode = 500
            }

        } elseif ($metodo -eq 'POST' -and $rota -eq '/proxima-os') {
            try {
                $res = Reserve-NextOs
                $json = (@{
                    status='ok'
                    osNumero=[int]$res.reservado
                    osCodigo=('C{0:D6}' -f [int]$res.reservado)
                    proximoDisponivel=[int]$res.proximo
                    sincronizacao=[string]$res.status
                    fonte=[string]$res.fonte
                    atualizadoEm=[string]$res.atualizadoEm
                } | ConvertTo-Json -Compress)
                $response.StatusCode = 200
            } catch {
                $json = (@{ status='erro'; mensagem=$_.Exception.Message } | ConvertTo-Json -Compress)
                $response.StatusCode = 500
            }

        } elseif ($metodo -eq 'POST' -and $rota -eq '/reconciliar-os') {
            $dados = Get-JsonBody -Request $request
            if (-not $dados -or $null -eq $dados.ultimoConfirmado) {
                $json = '{"status":"erro","mensagem":"Campo ultimoConfirmado obrigatorio"}'
                $response.StatusCode = 400
            } else {
                try {
                    $ultimo = [int]$dados.ultimoConfirmado
                    $fonte = if ($dados.fonte) { [string]$dados.fonte } else { 'external_collector' }
                    $obs = if ($dados.observacao) { [string]$dados.observacao } else { '' }
                    $st = Reconcile-OsState -UltimoConfirmado $ultimo -Fonte $fonte -Observacao $obs
                    $json = (@{
                        status='ok'
                        ultimoConfirmado=[int]$st.ultimoConfirmado
                        proximoDisponivel=[int]$st.proximoDisponivel
                        fonte=[string]$st.fonte
                        sincronizacao=[string]$st.status
                        atualizadoEm=[string]$st.atualizadoEm
                    } | ConvertTo-Json -Compress)
                    $response.StatusCode = 200
                } catch {
                    $json = (@{ status='erro'; mensagem=$_.Exception.Message } | ConvertTo-Json -Compress)
                    $response.StatusCode = 500
                }
            }

        } elseif ($metodo -eq 'GET' -and $rota -eq '/os-recentes') {
            try {
                $limit = 15
                if ($request.QueryString['limit']) {
                    try { $limit = [int]$request.QueryString['limit'] } catch {}
                }
                $tecnico = [string]$request.QueryString['tecnico']
                $includeProdutos = ([string]$request.QueryString['produtos']) -match '^(1|true|sim|yes)$'
                Write-Host "[$horario] Consultando OS recentes via API vhsys"
                $ordens = @(Get-VhsysOrdensServicoRecentes -Limit $limit -Tecnico $tecnico -IncludeProdutos:$includeProdutos | ForEach-Object { $_ })
                $ultima = @($ordens | Sort-Object -Property numero -Descending | Select-Object -First 1)[0]
                $ultimoNumero = if ($ultima) { [int](@($ultima.numero)[0]) } else { $null }
                $proxima = if ($ultimoNumero) { $ultimoNumero + 1 } else { $null }
                $json = (@{
                    status='ok'
                    fonte='vhsys_api'
                    ultimoConfirmado=$ultimoNumero
                    proximoDisponivel=$proxima
                    ordens=$ordens
                } | ConvertTo-Json -Depth 8 -Compress)
                $response.StatusCode = 200
            } catch {
                Write-Host "[$horario] Erro /os-recentes: $($_.Exception.Message)"
                $json = (@{ status='erro'; mensagem=$_.Exception.Message; ordens=@() } | ConvertTo-Json -Compress)
                $response.StatusCode = 500
            }

        } elseif ($metodo -eq 'GET' -and $rota -eq '/os-detalhe') {
            try {
                $idOrdem = 0
                $osNumero = 0
                if ($request.QueryString['idOrdem']) { try { $idOrdem = [int]$request.QueryString['idOrdem'] } catch {} }
                if ($request.QueryString['osNumero']) { try { $osNumero = [int]$request.QueryString['osNumero'] } catch {} }
                $includeProdutos = ([string]$request.QueryString['produtos']) -match '^(1|true|sim|yes)$'
                Write-Host "[$horario] Consultando detalhe OS via API vhsys | idOrdem=$idOrdem | osNumero=$osNumero"
                $detalhe = Get-VhsysOrdemServicoDetalhe -IdOrdem $idOrdem -OsNumero $osNumero -IncludeProdutos:$includeProdutos
                $json = (@{
                    status='ok'
                    fonte='vhsys_api'
                    ordem=$detalhe
                } | ConvertTo-Json -Depth 8 -Compress)
                $response.StatusCode = 200
            } catch {
                Write-Host "[$horario] Erro /os-detalhe: $($_.Exception.Message)"
                $json = (@{ status='erro'; mensagem=$_.Exception.Message; ordem=$null } | ConvertTo-Json -Compress)
                $response.StatusCode = 500
            }

        } elseif ($metodo -eq 'POST' -and $rota -eq '/os-status') {
            $dados = Get-JsonBody -Request $request
            if (-not $dados) {
                $json = '{"status":"erro","mensagem":"Body JSON obrigatorio"}'
                $response.StatusCode = 400
            } else {
                try {
                    $idOrdem = 0
                    $osNumero = 0
                    if ($dados.idOrdem) { $idOrdem = [int]$dados.idOrdem }
                    if ($dados.osNumero) { $osNumero = [int]$dados.osNumero }
                    $tipoStatus = if ($dados.tipoStatus) { [string]$dados.tipoStatus } else { [string]$dados.statusTexto }
                    $obsStatus = if ($dados.observacao) { [string]$dados.observacao } else { '' }
                    if ([string]::IsNullOrWhiteSpace($tipoStatus)) { throw 'Campo tipoStatus obrigatorio.' }
                    Write-Host "[$horario] Registrando status OS via API vhsys | idOrdem=$idOrdem | osNumero=$osNumero | status=$tipoStatus"
                    $out = Add-VhsysStatusNaOrdemServico -IdOrdem $idOrdem -OsNumero $osNumero -Status $tipoStatus -Observacao $obsStatus
                    $json = (@{
                        status='ok'
                        fonte='vhsys_api'
                        mensagem='Status registrado na OS.'
                        idOrdem=$out.idOrdem
                        tipoStatus=$out.status
                        observacao=$out.observacao
                    } | ConvertTo-Json -Depth 5 -Compress)
                    $response.StatusCode = 200
                } catch {
                    Write-Host "[$horario] Erro /os-status: $($_.Exception.Message)"
                    $json = (@{ status='erro'; mensagem=("Falha ao registrar status na OS: " + $_.Exception.Message) } | ConvertTo-Json -Compress)
                    $response.StatusCode = 500
                }
            }

        } elseif ($metodo -eq 'GET' -and $rota -eq '/ultima-os') {
            try {
                Write-Host "[$horario] Consultando ultima OS no Altertag"
                try {
                    $api = Sync-OsFromApi
                    $os = @{ ok=$true; mensagem='Ultima OS identificada via API vhsys.'; ultimo=[int](@($api.ultimoSite)[0]) }
                } catch {
                    $os = Get-AltertagLastOs
                }
                if ($os.ok -and $os.ultimo) {
                    Write-Host "[$horario] Ultima OS detectada: $($os.ultimo)"
                    $json = (@{ status='ok'; mensagem=$os.mensagem; ultimo=[int]$os.ultimo; proximo=([int]$os.ultimo + 1) } | ConvertTo-Json -Compress)
                    $response.StatusCode = 200
                } else {
                    Write-Host "[$horario] Falha ao detectar OS: $($os.mensagem)"
                    $json = (@{ status='erro'; mensagem=$os.mensagem; ultimo=$null } | ConvertTo-Json -Compress)
                    $response.StatusCode = 500
                }
            } catch {
                Write-Host "[$horario] Erro /ultima-os: $($_.Exception.Message)"
                $json = (@{ status='erro'; mensagem=$_.Exception.Message; ultimo=$null } | ConvertTo-Json -Compress)
                $response.StatusCode = 500
            }

        } elseif ($metodo -eq 'POST' -and $rota -eq '/buscar-opcoes-altertag') {
            $dados = Get-JsonBody -Request $request
            if (-not $dados -or -not $dados.termo) {
                $json = '{"status":"erro","mensagem":"Informe tipo e termo para buscar"}'
                $response.StatusCode = 400
            } else {
                try {
                    $tipoBusca = 'produto'
                    if ($dados.tipo) { $tipoBusca = [string]$dados.tipo }
                    $modoBusca = ''
                    if ($dados.modo) { $modoBusca = [string]$dados.modo }
                    $somenteSite = ($modoBusca -match '(?i)^(site|altertag|rapido)$')
                    $usarCatalogo = ($modoBusca -match '(?i)^(catalogo|api|vhsys)$')
                    $termoBusca = [string]$dados.termo
                    if ($tipoBusca -match '(?i)^produto') {
                        $busca = $null
                        if ($usarCatalogo) {
                            Write-Host "[$horario] Buscando produtos via API vhsys: $termoBusca"
                        } else {
                            Write-Host "[$horario] Buscando produtos no autocomplete Altertag: $termoBusca"
                            try { $busca = Search-AltertagOptions -Tipo $tipoBusca -Termo $termoBusca -Modo $modoBusca } catch { $busca = $null }
                            $busca = Normalize-BuscaProdutos -Busca $busca
                        }

                        if ($usarCatalogo -or ((-not $somenteSite) -and (-not $busca.ok -or @($busca.opcoes).Count -eq 0))) {
                            if (-not $usarCatalogo) { Write-Host "[$horario] Autocomplete sem produto; tentando API vhsys: $termoBusca" }
                            $produtosApi = @()
                            try { $produtosApi = @(Search-VhsysProdutosCatalogo -Termo $termoBusca -Limit 20) } catch { $produtosApi = @() }
                            $produtosCsv = @()
                            try {
                                $buscaCsv = Search-ProdutosExport -Termo $termoBusca
                                if ($buscaCsv -and $buscaCsv.ok) { $produtosCsv = @($buscaCsv.produtos) }
                            } catch {
                                $produtosCsv = @()
                            }
                            $produtosCombinados = @($produtosApi + $produtosCsv)
                            if ($produtosCombinados.Count -gt 0) {
                                $busca = @{
                                    ok = $true
                                    mensagem = 'Produtos encontrados via API vhsys e exportacao local.'
                                    opcoes = @($produtosCombinados | ForEach-Object { [string]$_.texto })
                                    produtos = @($produtosCombinados)
                                    fonte = if ($produtosApi.Count -gt 0 -and $produtosCsv.Count -gt 0) { 'vhsys_api+csv' } elseif ($produtosApi.Count -gt 0) { 'vhsys_api' } else { 'csv' }
                                }
                            } else {
                                Write-Host "[$horario] API sem produto; tentando exportacao local: $termoBusca"
                                $busca = Search-ProdutosExport -Termo $termoBusca
                            }
                        }
                        $busca = Normalize-BuscaProdutos -Busca $busca
                    } else {
                        Write-Host "[$horario] Buscando opcoes Altertag: $tipoBusca / $termoBusca"
                        $busca = Search-AltertagOptions -Tipo $tipoBusca -Termo $termoBusca
                        $busca = Normalize-BuscaProdutos -Busca $busca
                    }
                    $busca = Normalize-BuscaProdutos -Busca $busca
                    $statusBusca = if ($busca.ok) { 'ok' } else { 'erro' }
                    $json = (@{ status=$statusBusca; mensagem=$busca.mensagem; opcoes=@($busca.opcoes); produtos=@($busca.produtos); fonte=$busca.fonte } | ConvertTo-Json -Depth 5 -Compress)
                    $response.StatusCode = if ($busca.ok) { 200 } else { 500 }
                } catch {
                    $json = (@{ status='erro'; mensagem=$_.Exception.Message; opcoes=@() } | ConvertTo-Json -Compress)
                    $response.StatusCode = 500
                }
            }

        } elseif ($metodo -eq 'POST' -and $rota -eq '/criar-os-altertag') {
            $dados = Get-JsonBody -Request $request
            if (-not $dados) {
                $json = '{"status":"erro","mensagem":"Body JSON obrigatorio"}'
                $response.StatusCode = 400
            } else {
                try {
                    $tecReq = ([string]$dados.tecnico).Trim().ToUpper()
                    $serialReq = ([string]$dados.serial).Trim()
                    $refReq = ([string]$dados.referencia).Trim()
                    $idProdutoReq = [int]$dados.idProduto
                    $codigoProdutoReq = ([string]$dados.produtoCodigo).Trim()
                    $produtoReq = ([string]$dados.produtoDescricao).Trim()
                    $valorReq = if ($dados.produtoValor) { [string]$dados.produtoValor } else { '0.00' }
                    $servReq = @($dados.servicos)
                    if ($idProdutoReq -lt 1 -and $codigoProdutoReq) {
                        Write-Host "[$horario] Resolvendo produto pelo codigo: $codigoProdutoReq"
                        $produtoResolvido = Resolve-VhsysProdutoCatalogo -Codigo $codigoProdutoReq -Descricao $produtoReq
                        if ($produtoResolvido) {
                            $idProdutoReq = [int]$produtoResolvido.idProduto
                            $produtoReq = [string]$produtoResolvido.descricao
                            $valorReq = [string]$produtoResolvido.valor
                        }
                    }

                    Write-Host "[$horario] Criando OS Altertag via API | Serial=$serialReq | Tecnico=$tecReq | Produto=$idProdutoReq"
                    $out = New-VhsysOrdemServico -Tecnico $tecReq -Serial $serialReq -Referencia $refReq -IdProduto $idProdutoReq -ProdutoDescricao $produtoReq -ProdutoValor $valorReq -Servicos $servReq
                    $json = (@{
                        status='ok'
                        mensagem='OS criada no Altertag.'
                        idOrdem=$out.idOrdem
                        osNumero=$out.osNumero
                        osCodigo=$out.osCodigo
                        cliente=$out.cliente
                        tecnico=$out.tecnico
                        garantia=$out.garantia
                        referencia=$out.referencia
                        produto=$out.produto
                        idProduto=$out.idProduto
                        idAlmoxarifado=$out.idAlmoxarifado
                        produtoErro=$out.produtoErro
                        servicos=@($out.servicos)
                        servicosErro=$out.servicosErro
                    } | ConvertTo-Json -Depth 6 -Compress)
                    $response.StatusCode = 200
                } catch {
                    Write-Host "[$horario] Erro /criar-os-altertag: $($_.Exception.Message)"
                    $json = (@{ status='erro'; mensagem=("Falha ao criar OS Altertag: " + $_.Exception.Message) } | ConvertTo-Json -Compress)
                    $response.StatusCode = 500
                }
            }

        } elseif ($metodo -eq 'POST' -and $rota -eq '/triagem/enfileirar') {
            $dados = Get-JsonBody -Request $request
            if (-not $dados) {
                $json = '{"status":"erro","mensagem":"Body JSON obrigatorio"}'
                $response.StatusCode = 400
            } else {
                try {
                    $serialReq = [string]$dados.serial
                    $tecReq    = ([string]$dados.tecnico).Trim().ToUpper()
                    $modeloReq = [string]$dados.modelo
                    $cpuReq    = [string]$dados.cpu
                    $ramReq    = [string]$dados.ram
                    $discoReq  = [string]$dados.disco
                    $codManual = [string]$dados.produtoCodigo
                    $gradeReq  = [string]$dados.grade
                    $servReq   = @($dados.servicos)
                    if (-not $serialReq -or $serialReq.Trim() -eq '') {
                        $json = '{"status":"erro","mensagem":"Campo serial obrigatorio"}'
                        $response.StatusCode = 400
                    } elseif (-not ($tecnicosPermitidos -contains $tecReq)) {
                        $json = '{"status":"erro","mensagem":"Tecnico invalido. Use: Lucas, Hyrides, Vitor ou Erick"}'
                        $response.StatusCode = 400
                    } else {
                        $resProduto = Resolve-ProdutoCodigo -Modelo $modeloReq -Cpu $cpuReq -Ram $ramReq -Disco $discoReq -ProdutoCodigoManual $codManual
                        if (-not $resProduto.ok) {
                            $json = (@{
                                status='pendente'
                                mensagem='Produto nao resolvido automaticamente'
                                opcoesProdutoCodigo=$resProduto.opcoes
                                detectado=@{ modelo=$modeloReq; cpu=$cpuReq; ram=$ramReq; disco=$discoReq }
                            } | ConvertTo-Json -Compress)
                            $response.StatusCode = 202
                        } else {
                            $codigoProduto = [string]$resProduto.codigo
                            $job = New-TriagemJob -Serial $serialReq.Trim() -Tecnico $tecReq -Cliente $clientePadrao -ProdutoCodigo $codigoProduto -Grade $gradeReq -Servicos $servReq
                            Write-Host "[$horario] Triagem enfileirada | id=$($job.id) | Serial=$($serialReq.Trim()) | Produto=$codigoProduto"
                            $json = (@{
                                status='ok'
                                mensagem='Triagem enfileirada no agente do PC principal.'
                                jobId=[string]$job.id
                                produtoCodigo=$codigoProduto
                                tecnico=$tecReq
                                cliente=$clientePadrao
                                garantia=$serialReq.Trim()
                            } | ConvertTo-Json -Compress)
                            $response.StatusCode = 200
                        }
                    }
                } catch {
                    $json = (@{ status='erro'; mensagem=("Falha ao enfileirar triagem: " + $_.Exception.Message) } | ConvertTo-Json -Compress)
                    $response.StatusCode = 200
                }
            }

        } elseif ($metodo -eq 'GET' -and $rota -eq '/triagem/status') {
            $id = [string]$request.QueryString['id']
            if (-not $id) {
                $json = '{"status":"erro","mensagem":"Parametro id obrigatorio"}'
                $response.StatusCode = 400
            } else {
                $job = Get-TriagemJob -Id $id
                if (-not $job) {
                    $json = (@{ status='erro'; mensagem='Triagem nao encontrada'; jobId=$id } | ConvertTo-Json -Compress)
                    $response.StatusCode = 404
                } else {
                    $json = (@{
                        status='ok'
                        jobId=[string]$job.id
                        triagemStatus=[string]$job.status
                        tentativas=[int]$job.tentativas
                        maxTentativas=[int]$job.maxTentativas
                        osNumero=$job.osNumero
                        erro=$job.erro
                        atualizadoEm=([datetime]$job.atualizadoEm).ToString('yyyy-MM-dd HH:mm:ss')
                    } | ConvertTo-Json -Compress)
                    $response.StatusCode = 200
                }
            }

        } elseif ($metodo -eq 'POST' -and $rota -eq '/cadastrar-triagem') {
            $dados = Get-JsonBody -Request $request
            if (-not $dados) {
                $json = '{"status":"erro","mensagem":"Body JSON obrigatorio"}'
                $response.StatusCode = 400
            } else {
                try {
                $serialReq = [string]$dados.serial
                $tecReq    = ([string]$dados.tecnico).Trim().ToUpper()
                $modeloReq = [string]$dados.modelo
                $cpuReq    = [string]$dados.cpu
                $ramReq    = [string]$dados.ram
                $discoReq  = [string]$dados.disco
                $codManual = [string]$dados.produtoCodigo
                $gradeReq  = [string]$dados.grade
                $servReq   = @($dados.servicos)
                if (-not $serialReq -or $serialReq.Trim() -eq '') {
                    $json = '{"status":"erro","mensagem":"Campo serial obrigatorio"}'
                    $response.StatusCode = 400
                } elseif (-not ($tecnicosPermitidos -contains $tecReq)) {
                    $json = '{"status":"erro","mensagem":"Tecnico invalido. Use: Lucas, Hyrides, Vitor ou Erick"}'
                    $response.StatusCode = 400
                } else {
                    $resProduto = Resolve-ProdutoCodigo -Modelo $modeloReq -Cpu $cpuReq -Ram $ramReq -Disco $discoReq -ProdutoCodigoManual $codManual
                    if (-not $resProduto.ok) {
                        if ($resProduto.motivo -eq 'ambigua') {
                            Write-Host "[$horario] Produto ambiguo. Detectado => Modelo: $modeloReq | CPU: $cpuReq | RAM: $ramReq | Disco: $discoReq"
                            $json = (@{
                                status='pendente'
                                mensagem='Produto ambiguo no mapa'
                                opcoesProdutoCodigo=$resProduto.opcoes
                                detectado=@{ modelo=$modeloReq; cpu=$cpuReq; ram=$ramReq; disco=$discoReq }
                                cliente=$clientePadrao
                                tecnico=$tecReq
                                garantia=$serialReq.Trim()
                            } | ConvertTo-Json -Compress)
                            $response.StatusCode = 202
                        } else {
                            Write-Host "[$horario] Produto nao mapeado. Detectado => Modelo: $modeloReq | CPU: $cpuReq | RAM: $ramReq | Disco: $discoReq"
                            $json = (@{
                                status='pendente'
                                mensagem='Produto nao mapeado. Atualize mapa_produtos.json'
                                detectado=@{ modelo=$modeloReq; cpu=$cpuReq; ram=$ramReq; disco=$discoReq }
                                cliente=$clientePadrao
                                tecnico=$tecReq
                                garantia=$serialReq.Trim()
                            } | ConvertTo-Json -Compress)
                            $response.StatusCode = 202
                        }
                    } else {
                        $codigoProduto = [string]$resProduto.codigo
                        Write-Host "[$horario] Triagem iniciada | Serial=$($serialReq.Trim()) | Tecnico=$tecReq | Produto=$codigoProduto"
                        $out = Invoke-AltertagTriagem -Serial $serialReq.Trim() -Tecnico $tecReq -Cliente $clientePadrao -ProdutoCodigo $codigoProduto -Grade $gradeReq -Servicos $servReq
                    if ($out.ok) {
                        $json = (@{ status='ok'; mensagem=$out.mensagem; osNumero=$out.osNumero; produtoCodigo=$codigoProduto; cliente=$clientePadrao; tecnico=$tecReq; garantia=$serialReq.Trim(); grade=$gradeReq; servicos=$servReq } | ConvertTo-Json -Compress)
                        $response.StatusCode = 200
                    } elseif ($out.mensagem -like 'Pagina aberta no Brave*') {
                        $json = (@{ status='pendente'; mensagem=$out.mensagem; produtoCodigo=$codigoProduto; cliente=$clientePadrao; tecnico=$tecReq; garantia=$serialReq.Trim(); grade=$gradeReq; servicos=$servReq } | ConvertTo-Json -Compress)
                        $response.StatusCode = 202
                    } else {
                        Write-Host "[$horario] Triagem retornou erro de automacao: $($out.mensagem)"
                        $json = (@{ status='erro'; mensagem=$out.mensagem; produtoCodigo=$codigoProduto; cliente=$clientePadrao; tecnico=$tecReq; garantia=$serialReq.Trim() } | ConvertTo-Json -Compress)
                        $response.StatusCode = 200
                    }
                    }
                }
                } catch {
                    Write-Host "[$horario] Erro /cadastrar-triagem: $($_.Exception.Message)"
                    $json = (@{ status='erro'; mensagem=("Falha interna na triagem: " + $_.Exception.Message) } | ConvertTo-Json -Compress)
                    $response.StatusCode = 200
                }
            }

        } elseif ($metodo -eq 'POST' -and $rota -eq '/imprimir-os') {
            $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
            $raw    = $reader.ReadToEnd()
            $reader.Close()
            $dados = $raw | ConvertFrom-Json

            $osTxt = ([string]$dados.os -replace '[^0-9]', '')
            $osCodigo = if ($osTxt) { 'C{0:D6}' -f [int]$osTxt } else { '' }
            $serialTxt = ([string]$dados.serial -replace '[^a-zA-Z0-9]', '')
            $modeloTxt = ([string]$dados.modelo -replace '[^a-zA-Z0-9 \-\.]', '')
            if ($modeloTxt.Length -gt 42) { $modeloTxt = $modeloTxt.Substring(0, 42) }

            if (-not $osTxt) {
                $json = '{"status":"erro","mensagem":"Campo os obrigatorio"}'
                $response.StatusCode = 400
            } else {
                $tspl  = "SIZE 80 mm,30 mm`r`n"
                $tspl += "GAP 3 mm,0 mm`r`n"
                $tspl += "DENSITY 8`r`n"
                $tspl += "SPEED 4`r`n"
                $tspl += "DIRECTION 0`r`n"
                $tspl += "REFERENCE 0,0`r`n"
                $tspl += "OFFSET 0 mm`r`n"
                $tspl += "CODEPAGE 850`r`n"
                $tspl += "CLS`r`n"
                $tspl += "BOX 12,20,628,220,2`r`n"
                $tspl += "TEXT 22,24,`"3`",0,1,1,`"CAIJ INFORMATICA`"`r`n"
                $tspl += "TEXT 22,62,`"4`",0,2,2,`"OS # $osCodigo`"`r`n"
                if ($serialTxt) { $tspl += "TEXT 22,134,`"2`",0,1,1,`"SERIAL: $serialTxt`"`r`n" }
                if ($modeloTxt) { $tspl += "TEXT 22,158,`"2`",0,1,1,`"$modeloTxt`"`r`n" }
                $tspl += "BAR 16,218,612,4`r`n"
                $tspl += "PRINT 1`r`n"

                $printRes = Send-TsplToPrinter -Tspl $tspl -Prefix 'caij_tspl_os'

                if ($printRes.ok) {
                    $json = '{"status":"ok","mensagem":"OS impressa com sucesso"}'
                    $response.StatusCode = 200
                } else {
                    $json = (@{ status='erro'; mensagem='Falha ao enviar OS para impressora'; detalhe=[string]$printRes.saida; exitCode=[int]$printRes.exitCode } | ConvertTo-Json -Compress)
                    $response.StatusCode = 500
                }
            }

        } elseif ($metodo -eq 'POST' -and $rota -eq '/imprimir') {
            $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
            $raw    = $reader.ReadToEnd()
            $reader.Close()
            Write-Host "[$horario] Recebido: $($raw.Substring(0,[math]::Min($raw.Length,80)))"

            $dados = $raw | ConvertFrom-Json
            Write-Host "[$horario] Montando etiqueta para: $($dados.serial)"

            # Limpa caracteres especiais para ASCII
            function Limpar($s, $extra='') {
                if (!$s) { return '' }
                try {
                    $t = [string]$s
                    $t = $t.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', ''
                } catch {
                    $t = [string]$s
                }
                return ($t -replace "[^a-zA-Z0-9 \-\.\(\)\+$extra]", '')
            }
            function Short-Cpu($s) {
                $t = Limpar $s '@'
                if ($t -match '(?i)\b(i[3579])(?:[- ]?)(\d{4,5})') {
                    $prefix = $matches[1].ToUpper()
                    $modelo = [string]$matches[2]
                    $gen = $null
                    if ($modelo.Length -ge 4) {
                        $primeirosDois = [int]$modelo.Substring(0, 2)
                        $primeiro = [int]$modelo.Substring(0, 1)
                        if ($primeirosDois -ge 10 -and $primeirosDois -le 19) {
                            $gen = $primeirosDois
                        } elseif ($primeiro -ge 2 -and $primeiro -le 9) {
                            $gen = $primeiro
                        }
                    }
                    if ($gen) { return "$prefix $gen" }
                    return $prefix
                }
                return $t
            }
            function Short-Gpu($s) {
                $t = Limpar $s
                if ($t -match '(?i)MX\s*450') { return 'MX450 Dedicada' }
                if ($t -match '(?i)MX\s*350') { return 'MX350 Dedicada' }
                if ($t -match '(?i)RTX\s*([0-9]{4})') { return "RTX $($Matches[1]) Dedicada" }
                if ($t -match '(?i)GTX\s*([0-9]{3,4})') { return "GTX $($Matches[1]) Dedicada" }
                if ($t -match '(?i)Iris\s*Xe') { return 'Intel Iris Xe' }
                if ($t -match '(?i)UHD') { return 'Intel UHD' }
                if ($t.Length -gt 32) { return $t.Substring(0, 32) }
                return $t
            }
            function Short-Disco($s) {
                $t = Limpar $s
                $tipo = if ($t -match '(?i)\bSSD\b|NVME|M\.2') { 'SSD' } elseif ($t -match '(?i)\b(HDD|HD)\b') { 'HDD' } else { 'DISCO' }
                if ($t -match '(?i)\b(931|1000|1024)GB\b') { return "1TB $tipo" }
                if ($t -match '(?i)\b(476|480|500|512)GB\b') { return "512GB $tipo" }
                if ($t -match '(?i)\b(238|240|250|256)GB\b') { return "256GB $tipo" }
                if ($t -match '(?i)\b(119|120|128)GB\b') { return "128GB $tipo" }
                if ($t -match '(?i)\b(931|1000|1024)\b') { return "1TB $tipo" }
                if ($t -match '(?i)\b(476|480|500|512)\b') { return "512GB $tipo" }
                if ($t -match '(?i)\b(238|240|250|256)\b') { return "256GB $tipo" }
                if ($t -match '(?i)\b(119|120|128)\b') { return "128GB $tipo" }
                if ($t.Length -gt 28) { return $t.Substring(0, 28) }
                return $t
            }
            function Short-DiscoManual($s) {
                $t = Limpar $s
                if ($t.Length -gt 28) { return $t.Substring(0, 28) }
                return $t
            }
            function Fit-TsplText($s, [int]$maxLen) {
                $t = Limpar $s
                if ($t.Length -le $maxLen) { return $t }
                if ($maxLen -le 3) { return $t.Substring(0, $maxLen) }
                return $t.Substring(0, $maxLen - 3) + '...'
            }
            function Format-BateriaQualidade($s) {
                $raw = ([string]$s).Trim()
                if (-not $raw -or $raw -match '^(?i:N/?A|Nao identificada|Não identificada)$') { return 'N/A' }

                $pctText = ''
                $pctMatch = [regex]::Match($raw, '(\d{1,3})\s*%?')
                if ($pctMatch.Success) {
                    $pct = [math]::Min(100, [math]::Max(0, [int]$pctMatch.Groups[1].Value))
                    $pctText = " ($pct%)"
                }

                if ($raw -match '(?i)\b(excellent|excelente)\b') { return "EXCELLENT$pctText" }
                if ($raw -match '(?i)\b(good|boa|normal)\b') { return "GOOD$pctText" }
                if ($raw -match '(?i)\b(fair|regular)\b') { return "FAIR$pctText" }
                if ($raw -match '(?i)\b(poor|ruim|service|replace|trocar|substituir|manutencao|manutenção)\b') { return "POOR$pctText" }

                if ($pctMatch.Success) {
                    if ($pct -ge 90) { return "EXCELLENT$pctText" }
                    if ($pct -ge 75) { return "GOOD$pctText" }
                    if ($pct -ge 50) { return "FAIR$pctText" }
                    if ($pct -gt 0) { return "POOR$pctText" }
                }
                return Fit-TsplText $raw 12
            }

            $modelo  = Limpar $dados.modelo
            $serial  = $dados.serial -replace '[^a-zA-Z0-9]', ''
            $osNum   = ''
            if ($null -ne $dados.os) { $osNum = ([string]$dados.os -replace '[^0-9]', '') }
            $osCodigo = if ($osNum) { 'C{0:D6}' -f [int]$osNum } else { '' }
            $cpu     = Short-Cpu $dados.cpu
            $ram     = Limpar $dados.ram
            $ramMods = if ($dados.ramMods) { Limpar $dados.ramMods '+' } else { $ram }
            $modoManual = ($dados.PSObject.Properties.Name -contains 'modoManual' -and [bool]$dados.modoManual)
            $disco   = if ($modoManual) { Short-DiscoManual $dados.disco } else { Short-Disco $dados.disco }
            Write-Host "[$horario] Disco recebido: $($dados.disco) -> $disco"
            $bateria = if ($null -ne $dados.bateria -and ([string]$dados.bateria).Trim() -ne '') {
                Limpar $dados.bateria '%()'
            } else {
                ''
            }
            $bateriaQualidade = Format-BateriaQualidade $bateria
            $gpu     = Short-Gpu $dados.gpu
            if (-not $gpu -or $gpu.Trim() -eq '') { $gpu = 'N/A' }
            $mostrarGpu = ($gpu -and $gpu.Trim() -ne '' -and $gpu -notmatch '^(?i:N/?A|Nao identificada|Não identificada)$')
            $mostrarBateria = ($bateria -and $bateria.Trim() -ne '')
            $gradeRaw = if ($dados.grade) { ([string]$dados.grade).Trim().ToUpper() } else { '' }
            if ($gradeRaw -eq 'RNA') { $gradeRaw = 'RMA' }
            if ($gradeRaw -match '^C\s*-\s*PINTURA\s*([123])$') {
                $grade = "C - PINTURA $($matches[1])"
            } elseif ($gradeRaw -match '^(?:GRADE\s*)?T(?:\s*-\s*TRIAGEM)?$') {
                $grade = 'T - TRIAGEM'
            } elseif ($gradeRaw -in @('A','B','RMA')) {
                $grade = $gradeRaw
            } else {
                $grade = ''
            }
            $obs     = if ($dados.obs -and $dados.obs.Length -gt 0) {
                           $tmp = Limpar $dados.obs '!,;:'
                           if ($tmp.Length -gt 180) { $tmp.Substring(0, 180) } else { $tmp }
                       } else { '' }

            # ================================================
            # TSPL 80x50mm = aproximadamente 640x400 dots @ 203dpi.
            # Manter a altura alinhada ao rolo evita feed em branco e erro de gap.
            # Fontes: 1=8x12  2=12x20  3=16x24  4=24x32
            # ================================================
            $diasSemana = @('DOM','SEG','TER','QUA','QUI','SEX','SAB')
            $dataCurta = "$($diasSemana[[int](Get-Date).DayOfWeek]) $(Get-Date -Format 'dd/MM HH:mm')"
            if ($modelo.Length -le 16) {
                $modeloTop = Fit-TsplText $modelo 16
                $modeloFont = '4'
                $modeloY = 26
            } elseif ($modelo.Length -le 25) {
                $modeloTop = Fit-TsplText $modelo 25
                $modeloFont = '3'
                $modeloY = 34
            } else {
                $modeloTop = Fit-TsplText $modelo 42
                $modeloFont = '2'
                $modeloY = 34
            }
            if ($osCodigo) {
                $serialTop = Fit-TsplText $serial 15
                $serialScaleX = 1
            } elseif ($serial.Length -le 12) {
                $serialTop = Fit-TsplText $serial 12
                $serialScaleX = 2
            } else {
                $serialTop = Fit-TsplText $serial 22
                $serialScaleX = 1
            }
            $serialBar = ($serial -replace '[^A-Za-z0-9]', '').ToUpper()
            $gradeBadge = ''
            if ($grade) {
                if ($grade -match '^C\s*-\s*PINTURA\s*([123])$') {
                    $gradeBadge = "GRADE C - PINTURA $($matches[1])"
                } elseif ($grade -match '^T\s*-\s*TRIAGEM$') {
                    $gradeBadge = 'T - TRIAGEM'
                } else {
                    $gradeBadge = $grade
                }
            }

            $tspl  = "SIZE 80 mm,50 mm`r`n"
            $tspl += "GAP 3 mm,0 mm`r`n"
            $tspl += "DENSITY 8`r`n"
            $tspl += "SPEED 2`r`n"
            $tspl += "DIRECTION 0`r`n"
            $tspl += "REFERENCE 0,0`r`n"
            $tspl += "OFFSET 0 mm`r`n"
            $tspl += "CODEPAGE 850`r`n"
            $tspl += "CLS`r`n"

            # Moldura completa ajustada dentro da etiqueta real 80x50mm.
            $tspl += "BOX 2,4,638,398,2`r`n"

            # Modelo no topo, usando o espaco antes ocupado pela marca.
            $tspl += "BOX 10,14,430,74,2`r`n"
            $tspl += "TEXT 24,$modeloY,`"$modeloFont`",0,1,1,`"$modeloTop`"`r`n"

            # Grade em destaque, com texto completo para C - Pintura.
            if ($gradeBadge) {
                $gradeBadge = Fit-TsplText $gradeBadge 22
                $tspl += "BOX 442,14,630,74,3`r`n"
                if ($gradeBadge -match '^GRADE C') {
                    $tspl += "TEXT 452,31,`"1`",0,1,1,`"$gradeBadge`"`r`n"
                } elseif ($gradeBadge.Length -le 3) {
                    $tspl += "TEXT 508,28,`"4`",0,1,1,`"$gradeBadge`"`r`n"
                } else {
                    $tspl += "TEXT 472,32,`"2`",0,1,1,`"$gradeBadge`"`r`n"
                }
            }

            if ($osCodigo) {
                # Serial e OS em caixas separadas.
                $tspl += "BOX 10,84,410,154,3`r`n"
                $tspl += "TEXT 28,94,`"4`",0,$serialScaleX,1,`"$serialTop`"`r`n"
                if ($serialBar.Length -ge 4) {
                    $tspl += "BARCODE 28,128,`"128`",18,0,0,1,2,`"$serialBar`"`r`n"
                }
                $tspl += "BOX 430,84,630,154,3`r`n"
                $tspl += "TEXT 454,103,`"4`",0,1,1,`"$osCodigo`"`r`n"
            } else {
                $tspl += "BOX 10,84,630,154,3`r`n"
                $tspl += "TEXT 28,94,`"4`",0,$serialScaleX,1,`"$serialTop`"`r`n"
                if ($serialBar.Length -ge 4) {
                    $tspl += "BARCODE 28,128,`"128`",18,0,0,1,2,`"$serialBar`"`r`n"
                }
            }

            function Wrap-TsplLines {
                param(
                    [string]$Text,
                    [int]$MaxLen = 46,
                    [int]$MaxLines = 3
                )
                $clean = ([string]$Text -replace '\s+', ' ').Trim()
                if (-not $clean) { return @() }
                $words = $clean -split '\s+'
                $lines = New-Object System.Collections.Generic.List[string]
                $current = ''
                foreach ($word in $words) {
                    $candidate = if ($current) { "$current $word" } else { $word }
                    if ($candidate.Length -le $MaxLen) {
                        $current = $candidate
                        continue
                    }
                    if ($current) {
                        $lines.Add($current)
                        $current = ''
                        if ($lines.Count -ge $MaxLines) { break }
                    }
                    if ($word.Length -le $MaxLen) {
                        $current = $word
                    } else {
                        $remaining = $word
                        while ($remaining.Length -gt $MaxLen -and $lines.Count -lt $MaxLines) {
                            $lines.Add($remaining.Substring(0, $MaxLen))
                            $remaining = $remaining.Substring($MaxLen)
                        }
                        $current = $remaining
                    }
                    if ($lines.Count -ge $MaxLines) { break }
                }
                if ($current -and $lines.Count -lt $MaxLines) { $lines.Add($current) }
                if ($lines.Count -gt $MaxLines) { $lines = @($lines[0..($MaxLines - 1)]) }
                if ($lines.Count -eq $MaxLines -and $current.Length -gt 0) {
                    $last = $lines[$MaxLines - 1]
                    if ($last.Length -gt $MaxLen) {
                        $cutLen = [math]::Min($last.Length, [math]::Max(0, $MaxLen - 3))
                        $lines[$MaxLines - 1] = $last.Substring(0, $cutLen) + '...'
                    }
                }
                return @($lines)
            }

            # Metade inferior: informacoes fixas a esquerda e observacoes a direita.
            $tspl += "BOX 10,166,630,384,2`r`n"
            $tspl += "BAR 318,166,2,218`r`n"
            $tspl += "BAR 10,194,620,2`r`n"

            $cpuInfo = Fit-TsplText $cpu 16
            $ramInfo = Fit-TsplText $ramMods 16
            $discoInfo = Fit-TsplText $disco 16
            $gpuInfo = Fit-TsplText $gpu 16
            $batInfo = Fit-TsplText $bateriaQualidade 16

            $tspl += "TEXT 22,173,`"2`",0,1,1,`"CONFIGURACAO`"`r`n"
            $specY = 204
            $specStep = 32
            $tspl += "TEXT 22,$specY,`"1`",0,1,1,`"CPU`"`r`n"
            $tspl += "TEXT 76,$($specY - 3),`"2`",0,1,1,`"$cpuInfo`"`r`n"
            $tspl += "BAR 20,$($specY + 22),282,1`r`n"
            $specY += $specStep
            $tspl += "TEXT 22,$specY,`"1`",0,1,1,`"RAM`"`r`n"
            $tspl += "TEXT 76,$($specY - 3),`"2`",0,1,1,`"$ramInfo`"`r`n"
            $tspl += "BAR 20,$($specY + 22),282,1`r`n"
            $specY += $specStep
            $tspl += "TEXT 22,$specY,`"1`",0,1,1,`"DISCO`"`r`n"
            $tspl += "TEXT 76,$($specY - 3),`"2`",0,1,1,`"$discoInfo`"`r`n"
            $tspl += "BAR 20,$($specY + 22),282,1`r`n"
            $specY += $specStep
            $tspl += "TEXT 22,$specY,`"1`",0,1,1,`"GPU`"`r`n"
            $tspl += "TEXT 76,$($specY - 3),`"2`",0,1,1,`"$gpuInfo`"`r`n"
            $tspl += "BAR 20,$($specY + 22),282,1`r`n"
            $specY += $specStep
            $tspl += "TEXT 22,$specY,`"1`",0,1,1,`"BAT`"`r`n"
            $tspl += "TEXT 76,$($specY - 3),`"2`",0,1,1,`"$batInfo`"`r`n"

            # Observacoes
            $tspl += "TEXT 334,173,`"2`",0,1,1,`"OBSERVACOES`"`r`n"
            $obsLines = @()
            if ($obs) {
                $obsLines = Wrap-TsplLines -Text $obs -MaxLen 19 -MaxLines 5
                if ($obsLines.Count -gt 0) {
                    $obsY = 208
                    $obsStep = 30
                    foreach ($linhaObs in $obsLines) {
                        $fontObs = '3'
                        $tspl += "TEXT 336,$obsY,`"$fontObs`",0,1,1,`"$linhaObs`"`r`n"
                        $obsY += $obsStep
                    }
                    $tspl += "TEXT 438,358,`"2`",0,1,1,`"$dataCurta`"`r`n"
                } else {
                    $tspl += "TEXT 438,358,`"2`",0,1,1,`"$dataCurta`"`r`n"
                }
            } else {
                $tspl += "TEXT 438,358,`"2`",0,1,1,`"$dataCurta`"`r`n"
            }

            $tspl += "PRINT 1,1`r`n"

            # Salva e envia
            $printRes = Send-TsplToPrinter -Tspl $tspl -Prefix 'caij_tspl'

            if ($printRes.ok) {
                Write-Host "[$horario] Etiqueta enviada com sucesso!"
                $json = '{"status":"ok","mensagem":"Impresso com sucesso"}'
                $response.StatusCode = 200
            } else {
                Write-Host "[$horario] Falha ao imprimir"
                $json = (@{ status='erro'; mensagem='Falha ao enviar para impressora'; detalhe=[string]$printRes.saida; exitCode=[int]$printRes.exitCode } | ConvertTo-Json -Compress)
                $response.StatusCode = 500
            }

        } else {
            $json = '{"status":"erro","mensagem":"Rota nao encontrada"}'
            $response.StatusCode = 404
        }

        Send-JsonResponse -Response $response -Json $json

    } catch {
        if ($listener.IsListening) {
            $msgGlobal = $_.Exception.Message
            Write-Host "[ERRO] Falha global no processamento da requisicao: $msgGlobal"
            try {
                $ejson  = (@{ status='erro'; mensagem=("Erro interno no servidor: " + $msgGlobal) } | ConvertTo-Json -Compress)
                $response.StatusCode      = 500
                Send-JsonResponse -Response $response -Json $ejson
            } catch {}
        }
    }
}

$listener.Stop()
Write-Host 'Servidor parado.'







