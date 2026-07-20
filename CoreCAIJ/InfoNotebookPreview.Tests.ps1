param(
    [string]$ScriptPath = (Join-Path $PSScriptRoot 'InfoNotebook.ps1')
)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Name
    )
    if (-not $Condition) {
        throw "FAIL: $Name"
    }
}

$scriptText = Get-Content -Path $ScriptPath -Raw

Assert-True ($scriptText -notmatch '(?m)^\s*B\s+14\s+238\s+458\s+1\s*$') 'previa com observacao nao deve desenhar separador solto'

'OK: InfoNotebookPreview tests'
