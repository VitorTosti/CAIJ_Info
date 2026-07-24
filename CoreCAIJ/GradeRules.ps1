function Get-CaijGradeOptions {
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
    return ($normalized -eq 'B' -or $normalized -match '^C\s*-\s*PINTURA\s*[123]$')
}
