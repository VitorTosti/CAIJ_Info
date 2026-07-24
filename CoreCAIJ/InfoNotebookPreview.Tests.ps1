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
$gradeRulesText = Get-Content -Path (Join-Path $PSScriptRoot 'GradeRules.ps1') -Raw

Assert-True ($scriptText -notmatch '(?m)^\s*B\s+14\s+238\s+458\s+1\s*$') 'previa com observacao nao deve desenhar separador solto'
Assert-True ($gradeRulesText -match 'GRADE T - TRIAGEM') 'referencia da OS mantem Grade T - Triagem'
Assert-True ($scriptText -match "\@\{L='T'; D='Triagem'\}") 'popup mostra botao Grade T'
Assert-True ($scriptText -match "\`$tecNomes\s*=\s*@\('Lucas',\s*'Hyrides',\s*'Vitor',\s*'Erick'\)") 'cadastro mostra tecnico Erick'
Assert-True ($scriptText -match 'Get-CaijGradeOptions') 'cadastro usa todas as grades'
Assert-True ($scriptText -match 'ContextMenuStrip') 'cadastro abre menu de grades'
Assert-True ($scriptText -match '\$btnGradeOs') 'referencia usa botao de grade'
Assert-True ($scriptText -notmatch '\$txtGradeOs\s*=\s*New-Object System\.Windows\.Forms\.TextBox') 'referencia nao usa texto livre'
Assert-True ($scriptText -match 'Test-CaijGradeRequiresObs') 'validacao de OBS usa regra central'
Assert-True ($scriptText -match "\`$gradeTxt\s*=\s*.*'T - TRIAGEM'") 'previa encurta selo da triagem'

$serverPath = Join-Path $PSScriptRoot 'ServidorImpressao.ps1'
$serverText = Get-Content -Path $serverPath -Raw
Assert-True ($serverText -match "'ERICK'") 'servidor permite tecnico Erick'
Assert-True ($serverText -match 'T - TRIAGEM') 'servidor reconhece Grade T - Triagem'
Assert-True ($serverText -match "\`$gradeBadge\s*=\s*'T - TRIAGEM'") 'impressao encurta selo da triagem'
Assert-True ($serverText -match 'Test-VhsysProdutoLocalizacao') 'servidor confirma localizacao depois do cadastro'
Assert-True ($serverText -notmatch '-SemLocalizacao') 'servidor nao permite fallback sem localizacao'
Assert-True ($serverText -notmatch 'tentando sem localizacao') 'servidor nao mascara falha da localizacao'
Assert-True ($serverText -match 'Produto da OS .* nao confirmou a localizacao T.+CNICA_BT') 'servidor informa localizacao ausente'

'OK: InfoNotebookPreview tests'
