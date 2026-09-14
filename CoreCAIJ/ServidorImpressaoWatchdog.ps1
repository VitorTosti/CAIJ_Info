param(
    [string]$ServerPath = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'ServidorImpressao.ps1')
)

$ErrorActionPreference = 'SilentlyContinue'
$mutex = New-Object Threading.Mutex($false, 'Local\CAIJ-ServidorImpressao-Watchdog')
$ownsMutex = $false
$nextAttempt = [DateTime]::MinValue
try {
    $ownsMutex = $mutex.WaitOne(0, $false)
    if (-not $ownsMutex) { exit 0 }

    while ($true) {
        $online = $false
        try {
            $status = Invoke-RestMethod -Uri 'http://127.0.0.1:9100/status' -Method Get -TimeoutSec 2 -ErrorAction Stop
            $online = ($status.status -eq 'ok')
        } catch {}

        if (-not $online -and (Get-Date) -ge $nextAttempt -and (Test-Path -LiteralPath $ServerPath -PathType Leaf)) {
            # A regra de firewall ja e preparada pelo instalador. Reaplica-la em
            # toda recuperacao pode bloquear o processo oculto aguardando UAC.
            $env:CAIJ_SKIP_FIREWALL = '1'
            $arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -NoFailurePrompt' -f $ServerPath
            $child = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WindowStyle Hidden -PassThru
            # Uma falha de permissao termina sem prompt. O intervalo impede uma
            # tempestade de processos caso a porta volte a ficar indisponivel.
            if ($child) { [void]$child.WaitForExit(8000) }
            $nextAttempt = (Get-Date).AddSeconds(60)
        }
        Start-Sleep -Seconds 5
    }
} finally {
    if ($ownsMutex) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
