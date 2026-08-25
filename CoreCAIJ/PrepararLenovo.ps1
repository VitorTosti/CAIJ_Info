param(
    [string]$AppRoot = '',
    [string]$ManufacturerOverride = '',
    [ValidateSet('auto','enabled','disabled')][string]$PortcodeStateOverride = 'auto',
    [string]$UtilityPathOverride = '',
    [switch]$CheckOnly,
    [switch]$NoDialogs
)

$ErrorActionPreference = 'Stop'
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $AppRoot) { $AppRoot = Split-Path -Parent $scriptDirectory }
$expectedHash = '6C4165F5BF6F93D211F43BFB061354278120F52862B2282443BF182A9F1236A2'
$desiredMap = [byte[]](
    0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00,
    0x02,0x00,0x00,0x00, 0x73,0x00,0x1D,0xE0,
    0x00,0x00,0x00,0x00
)

function Show-LenovoMessage {
    param(
        [string]$Text,
        [string]$Title = 'InfoNotebook - Teclado Lenovo',
        [ValidateSet('Information','Warning','Error')][string]$Icon = 'Information'
    )
    if ($NoDialogs) { return }
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        $Text,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::$Icon
    ) | Out-Null
}

function Test-PortcodeEnabled {
    if ($PortcodeStateOverride -eq 'enabled') { return $true }
    if ($PortcodeStateOverride -eq 'disabled') { return $false }
    try {
        $current = [byte[]](Get-ItemPropertyValue `
            -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout' `
            -Name 'Scancode Map' `
            -ErrorAction Stop)
        if ($current.Length -ne $desiredMap.Length) { return $false }
        for ($index = 0; $index -lt $desiredMap.Length; $index++) {
            if ($current[$index] -ne $desiredMap[$index]) { return $false }
        }
        return $true
    } catch {
        return $false
    }
}

function Get-LenovoPortcodeUtilityCandidates {
    $driveRoot = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($AppRoot))
    $candidates = @()
    if ($UtilityPathOverride) { $candidates += $UtilityPathOverride }
    $candidates += (Join-Path $scriptDirectory 'tools\lenovo\portcoderev2.exe')
    $candidates += (Join-Path $driveRoot 'Interrogação teclado Lenovo\portcoderev2.exe')
    $candidates += (Join-Path $driveRoot 'Interrogacao teclado Lenovo\portcoderev2.exe')
    return @($candidates | Where-Object { $_ } | Select-Object -Unique)
}

$manufacturer = if ($ManufacturerOverride) {
    $ManufacturerOverride.Trim()
} else {
    try {
        ([string](Get-ItemPropertyValue `
            -LiteralPath 'HKLM:\HARDWARE\DESCRIPTION\System\BIOS' `
            -Name 'SystemManufacturer' `
            -ErrorAction Stop)).Trim()
    } catch {
        try { ([string](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).Manufacturer).Trim() } catch { '' }
    }
}

if ($manufacturer -notmatch '(?i)Lenovo') { exit 0 }
if (Test-PortcodeEnabled) { exit 0 }

$utilityPath = ''
$invalidUtilities = New-Object System.Collections.Generic.List[string]
foreach ($candidate in @(Get-LenovoPortcodeUtilityCandidates)) {
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
    try {
        $hash = (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash
        $signature = Get-AuthenticodeSignature -LiteralPath $candidate
        $signer = if ($signature.SignerCertificate) { [string]$signature.SignerCertificate.Subject } else { '' }
        if ($hash -eq $expectedHash -and $signature.Status -eq 'Valid' -and $signer -match '(?i)(CN|O)=Lenovo') {
            $utilityPath = $candidate
            break
        }
        $invalidUtilities.Add($candidate)
    } catch {
        $invalidUtilities.Add($candidate)
    }
}

if (-not $utilityPath -and $invalidUtilities.Count -eq 0) {
    Show-LenovoMessage `
        -Icon Error `
        -Text "Este Lenovo ainda nao possui a correcao da tecla de interrogacao.`n`nO arquivo portcoderev2.exe nao foi encontrado no pendrive. O InfoNotebook nao sera aberto para evitar que a maquina siga sem a correcao."
    exit 20
}

if (-not $utilityPath) {
    Show-LenovoMessage -Icon Error -Text "O utilitario Lenovo encontrado esta vazio, corrompido ou sem a assinatura oficial esperada.`n`nO InfoNotebook nao sera aberto. Execute novamente a atualizacao do pendrive."
    exit 21
}

if ($CheckOnly) { exit 10 }

Show-LenovoMessage `
    -Icon Warning `
    -Text "Este Lenovo ainda precisa ativar a tecla de interrogacao.`n`nO utilitario oficial Lenovo sera executado como administrador e o computador sera reiniciado automaticamente. Salve qualquer outro trabalho antes de continuar."

try {
    $process = Start-Process -FilePath $utilityPath -Verb RunAs -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "O utilitario Lenovo terminou com o codigo $($process.ExitCode)." }
} catch {
    Show-LenovoMessage -Icon Error -Text "A correcao Lenovo nao foi executada.`n`nAceite a solicitacao de administrador ao abrir novamente o InfoNotebook.`n`nDetalhe: $($_.Exception.Message)"
    exit 22
}

if (Test-PortcodeEnabled) {
    Show-LenovoMessage -Icon Information -Text 'A correcao Lenovo foi aplicada. Reinicie o computador antes de continuar a triagem.'
    exit 11
}

Show-LenovoMessage -Icon Error -Text 'O utilitario Lenovo terminou, mas a correcao da tecla nao foi confirmada. O InfoNotebook nao sera aberto.'
exit 23
