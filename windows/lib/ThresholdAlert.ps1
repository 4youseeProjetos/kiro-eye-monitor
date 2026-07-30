# Aviso de bandeja quando o consumo piora de faixa.
#
# Vive fora do entrypoint porque ficou sem teste enquanto morava la, e uma
# renomeacao de campo passou batido: a chamada continuava pedindo o antigo
# burn_rate depois da troca para cycle_pace. Sob Set-StrictMode, ler
# propriedade inexistente lanca excecao e derruba a janela — e so no primeiro
# aviso, ou seja, apenas na maquina de quem passa de 75%.

Set-StrictMode -Version Latest

$script:NiveisSemAviso = @('ok', 'falha')

function Test-ThresholdWorsened {
    <#
        .SYNOPSIS
        Indica se vale avisar: so quando o nivel piora de verdade.
        .DESCRIPTION
        Repetir balao a cada coleta seria ruido, e falha de coleta nao e
        consumo alto.
        .EXAMPLE
        Test-ThresholdWorsened -Previous 'ok' -Current 'atencao'  # $true
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Previous,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Current
    )
    if ($script:NiveisSemAviso -contains $Current) { return $false }
    return $Current -ne $Previous
}

function New-ThresholdAlertContent {
    <#
        .SYNOPSIS
        Titulo e texto do balao, a partir do relatorio do coletor.
        .EXAMPLE
        New-ThresholdAlertContent -Report $relatorio
    #>
    param([Parameter(Mandatory)][pscustomobject]$Report)

    $ritmo = if ($Report.PSObject.Properties.Name -contains 'cycle_pace') { $Report.cycle_pace } else { $null }
    return [pscustomobject]@{
        Title   = "kiro-eye-monitor em $($Report.account.used_percent)%"
        Message = Format-KiroProjection -Pace $ritmo -Account $Report.account
    }
}
