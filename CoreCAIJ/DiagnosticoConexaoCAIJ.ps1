$ErrorActionPreference = 'SilentlyContinue'

$configPath = Join-Path $PSScriptRoot 'caij_servidor_url.txt'
$url = 'http://192.168.15.127:9100'
if (Test-Path $configPath) {
    $cfg = (Get-Content -LiteralPath $configPath -Raw).Trim()
    if ($cfg) { $url = $cfg.TrimEnd('/') }
}

$uri = [Uri]$url
$hostName = $uri.Host
$port = if ($uri.Port -gt 0) { $uri.Port } else { 9100 }

Write-Host '======================================'
Write-Host ' CAIJ - Diagnostico de Conexao'
Write-Host '======================================'
Write-Host "Servidor: $url"
Write-Host "Host:     $hostName"
Write-Host "Porta:    $port"
Write-Host ''

Write-Host '[1/3] Ping...'
$pingOk = Test-Connection -ComputerName $hostName -Count 2 -Quiet
Write-Host "Ping:     $pingOk"

Write-Host ''
Write-Host '[2/3] Porta TCP...'
$tcp = Test-NetConnection -ComputerName $hostName -Port $port -WarningAction SilentlyContinue
Write-Host "TCP:      $($tcp.TcpTestSucceeded)"
Write-Host "IP usado: $($tcp.RemoteAddress)"

Write-Host ''
Write-Host '[3/3] HTTP /status...'
try {
    $status = Invoke-RestMethod -Uri "$url/status" -TimeoutSec 5 -ErrorAction Stop
    Write-Host 'HTTP:     True'
    Write-Host "Versao:   $($status.versao)"
    Write-Host "URL srv:  $($status.url)"
    Write-Host "Mensagem: $($status.mensagem)"
} catch {
    Write-Host 'HTTP:     False'
    Write-Host "Erro:     $($_.Exception.Message)"
}

Write-Host ''
Write-Host 'Interpretacao rapida:'
Write-Host '- Ping False: notebook nao enxerga o PC principal na rede.'
Write-Host '- Ping True e TCP False: bloqueio de firewall, roteador/AP isolation ou porta 9100 bloqueada.'
Write-Host '- TCP True e HTTP False: servidor nao respondeu corretamente ao /status.'
Write-Host '- Tudo True: conexao com servidor esta OK.'
