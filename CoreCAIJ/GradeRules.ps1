function Get-CaijGradeOptions {
    param([string]$EquipmentType = '')

    if ($EquipmentType -eq 'Celular') {
        return @(
            'A'
            'B'
            'C'
            'T - TRIAGEM'
            'RMA'
        )
    }

    @(
        'A'
        'B'
        'C - PINTURA 1'
        'C - PINTURA 2'
        'C - PINTURA 3'
        'T - TRIAGEM'
        'RMA'
    )
}

function Format-CaijGradeReference {
    param([string]$Grade)

    $normalized = ([string]$Grade).Trim().ToUpper()
    if ($normalized -eq 'RMA') {
        return 'RMA'
    }
    if ($normalized -match '^C\s*-\s*PINTURA\s*([123])$') {
        return "GRADE C - PINTURA $($matches[1])"
    }
    if ($normalized -eq 'C') {
        return 'GRADE C'
    }
    if ($normalized -match '^T\s*-\s*TRIAGEM$') {
        return 'GRADE T - TRIAGEM'
    }
    if ($normalized -in @('A', 'B')) {
        return "GRADE $normalized"
    }
    return 'GRADE A'
}

function Test-CaijGradeRequiresObs {
    param([string]$Grade)

    $normalized = ([string]$Grade).Trim().ToUpper()
    return ($normalized -in @('B', 'C') -or $normalized -match '^C\s*-\s*PINTURA\s*[123]$')
}
