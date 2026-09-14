function Get-CaijGradeOptions {
    param([string]$EquipmentType = '')

    @(
        'A'
        'B'
        'C'
        'T - TRIAGEM'
        'RMA'
    )
}

function Normalize-CaijGrade {
    param([string]$Grade)

    $normalized = ([string]$Grade).Trim().ToUpper()
    if ($normalized -eq 'RNA') { return 'RMA' }
    if ($normalized -match '^(?:GRADE\s+)?C(?:\s*-\s*PINTURA\s*[123])?$') { return 'C' }
    if ($normalized -match '^(?:GRADE\s+)?T(?:\s*-\s*TRIAGEM)?$') { return 'T - TRIAGEM' }
    if ($normalized -match '^GRADE\s+([AB])$') { return $matches[1] }
    if ($normalized -in @('A', 'B', 'RMA')) { return $normalized }
    return 'A'
}

function Format-CaijGradeReference {
    param([string]$Grade)

    $normalized = Normalize-CaijGrade $Grade
    if ($normalized -eq 'RMA') {
        return 'RMA'
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

    $normalized = Normalize-CaijGrade $Grade
    return ($normalized -in @('B', 'C'))
}
