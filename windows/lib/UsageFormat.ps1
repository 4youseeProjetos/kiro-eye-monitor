# Formatacao dos valores do relatorio para exibicao.
#
# Creditos aparecem com duas casas porque essa e a granularidade do medidor do
# Kiro. Datas do coletor chegam em UTC e sao mostradas na hora local.

Set-StrictMode -Version Latest

$script:NivelOk = 'ok'
$script:NivelAtencao = 'atencao'
$script:NivelCritico = 'critico'

function Format-KiroCredits {
    <# 2349.92 -> '2.349,92' conforme a cultura do Windows. #>
    param([Parameter(Mandatory)][double]$Value)
    return '{0:N2}' -f $Value
}

function Format-KiroLocalTime {
    <# ISO-8601 UTC do coletor -> hora local curta. #>
    param([AllowNull()][string]$IsoTimestamp)

    if ([string]::IsNullOrWhiteSpace($IsoTimestamp)) { return '--' }
    try {
        return ([datetimeoffset]$IsoTimestamp).ToLocalTime().ToString('dd/MM HH:mm')
    }
    catch {
        return $IsoTimestamp
    }
}

function Get-KiroAlertLevel {
    <#
        .SYNOPSIS
        Nivel de alerta a partir do percentual consumido.
        .EXAMPLE
        Get-KiroAlertLevel -UsedPercent 92 -WarnPercent 75 -CriticalPercent 90  # 'critico'
    #>
    param(
        [Parameter(Mandatory)][int]$UsedPercent,
        [Parameter(Mandatory)][int]$WarnPercent,
        [Parameter(Mandatory)][int]$CriticalPercent
    )
    if ($UsedPercent -ge $CriticalPercent) { return $script:NivelCritico }
    if ($UsedPercent -ge $WarnPercent) { return $script:NivelAtencao }
    return $script:NivelOk
}

function Format-KiroAccountHeadline {
    <# Linha principal: usado de cota. #>
    param([Parameter(Mandatory)][pscustomobject]$Account)
    $usado = Format-KiroCredits -Value ([double]$Account.credits_used)
    $cota = Format-KiroCredits -Value ([double]$Account.credits_included)
    return "$usado / $cota creditos"
}

function Format-KiroCyclePace {
    <#
        .SYNOPSIS
        Ritmo medio do mes, com a amostra em que ele se baseia.
        .EXAMPLE
        Format-KiroCyclePace -Pace $relatorio.cycle_pace
    #>
    param([AllowNull()][pscustomobject]$Pace)

    if ($null -eq $Pace) { return 'Ritmo do mes: aguardando a primeira hora do ciclo' }
    $porDia = Format-KiroCredits -Value ([double]$Pace.credits_per_day)
    $decorridos = '{0:N1}' -f ([double]$Pace.elapsed_days)
    $total = '{0:N0}' -f ([double]$Pace.total_days)
    return "Ritmo do mes: $porDia creditos/dia  (media de $decorridos de $total dias)"
}

$script:LinhasDeRuido = @(
    '^\s*\+',                       # continuacao e marcadores do PowerShell
    '^\s*No linha:\d+',             # cabecalho de erro, Windows em portugues
    '^\s*At line:\d+',              # idem, em ingles
    '^\s*CategoryInfo',
    '^\s*FullyQualifiedErrorId'
)
$script:LimiteResumo = 220

function Format-KiroErrorSummary {
    <#
        .SYNOPSIS
        Reduz a mensagem de falha ao que interessa na janela.
        .DESCRIPTION
        A saida crua traz o despejo de erro do PowerShell (posicao no script,
        CategoryInfo, til apontando a linha). Isso e util no log, nao na tela.
        .EXAMPLE
        Format-KiroErrorSummary -Message $Report.error
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Message)

    $uteis = @($Message -split "`r?`n" | Where-Object {
            $linha = $_
            if ([string]::IsNullOrWhiteSpace($linha)) { return $false }
            foreach ($ruido in $script:LinhasDeRuido) {
                if ($linha -match $ruido) { return $false }
            }
            return $true
        })
    if ($uteis.Count -eq 0) { return $Message.Trim() }
    $resumo = ($uteis[0..([Math]::Min(1, $uteis.Count - 1))] | ForEach-Object { $_.Trim() }) -join ' '
    if ($resumo.Length -le $script:LimiteResumo) { return $resumo }
    return $resumo.Substring(0, $script:LimiteResumo) + '...'
}

function Format-KiroFailureHint {
    <#
        .SYNOPSIS
        Diz ao desenvolvedor o que fazer diante da falha, e onde estao os detalhes.
        .DESCRIPTION
        Prefere o log do WSL, que traz o ambiente e o traceback; o log da janela
        e a alternativa quando a falha nem chegou ao coletor.
        .EXAMPLE
        Format-KiroFailureHint -Report $relatorio -LogPath 'C:\...\janela.jsonl'
    #>
    param(
        [Parameter(Mandatory)][pscustomobject]$Report,
        [AllowEmptyString()][string]$LogPath = ''
    )
    $log = if ($Report.PSObject.Properties.Name -contains 'log_path' -and
        -not [string]::IsNullOrWhiteSpace($Report.log_path)) { [string]$Report.log_path }
    else { $LogPath }

    $texto = 'No WSL, rode ./scripts/diagnostico.sh na pasta do projeto e envie a saida.'
    if ([string]::IsNullOrWhiteSpace($log)) { return $texto }
    return "$texto Detalhes desta falha em: $log"
}

function Format-KiroProjection {
    <# Projecao do ciclo: consumo no fim do mes ou data de esgotamento. #>
    param(
        [AllowNull()][pscustomobject]$Pace,
        [Parameter(Mandatory)][pscustomobject]$Account
    )
    if ($null -eq $Pace) { return "Ciclo reseta em $($Account.resets_on)" }
    if ($Pace.exhausts_before_reset) {
        return "Nesse ritmo a cota acaba em $($Pace.projected_exhaustion), antes do reset em $($Pace.period_end)"
    }
    $fimCiclo = Format-KiroCredits -Value ([double]$Pace.projected_cycle_usage)
    return "Nesse ritmo: $fimCiclo creditos ate o reset em $($Pace.period_end)"
}

function Format-KiroUnattributed {
    <# Explica o resto que a fonte B nao cobre. #>
    param([AllowNull()][object]$Credits)

    if ($null -eq $Credits) { return '' }
    $valor = Format-KiroCredits -Value ([double]$Credits)
    return "Nao atribuido: $valor  (Kiro IDE, web ou outra maquina)"
}
