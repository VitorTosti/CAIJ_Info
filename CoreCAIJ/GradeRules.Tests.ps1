$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'GradeRules.ps1')

function Assert-Equal {
    param($Actual, $Expected, [string]$Name)
    if ($Actual -ne $Expected) {
        throw "FAIL: $Name | esperado=[$Expected] atual=[$Actual]"
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Name)
    if (-not $Condition) {
        throw "FAIL: $Name"
    }
}

$options = @(Get-CaijGradeOptions)
Assert-Equal ($options -join '|') 'A|B|C - PINTURA 1|C - PINTURA 2|C - PINTURA 3|T - TRIAGEM|RMA' 'opcoes de grade'
$cellOptions = @(Get-CaijGradeOptions -EquipmentType 'Celular')
Assert-Equal ($cellOptions -join '|') 'A|B|C|T - TRIAGEM|RMA' 'celular usa grade C sem pintura'
Assert-Equal (Format-CaijGradeReference 'A') 'GRADE A' 'referencia A'
Assert-Equal (Format-CaijGradeReference 'C') 'GRADE C' 'referencia C simples'
Assert-Equal (Format-CaijGradeReference 'C - PINTURA 2') 'GRADE C - PINTURA 2' 'referencia pintura'
Assert-Equal (Format-CaijGradeReference 'T - TRIAGEM') 'GRADE T - TRIAGEM' 'referencia triagem'
Assert-Equal (Format-CaijGradeReference 'RMA') 'RMA' 'referencia RMA'
Assert-True (Test-CaijGradeRequiresObs 'B') 'B exige observacao'
Assert-True (Test-CaijGradeRequiresObs 'C - PINTURA 1') 'C exige observacao'
Assert-True (Test-CaijGradeRequiresObs 'C') 'C simples exige observacao'
Assert-True (-not (Test-CaijGradeRequiresObs 'T - TRIAGEM')) 'T nao exige observacao'
Assert-True (-not (Test-CaijGradeRequiresObs 'A')) 'A nao exige observacao'

'OK: GradeRules tests'
