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

$script:TituloAusente = '(sem titulo)'
$script:LimiteTitulo = 52

function Format-KiroDayLabel {
    <#
        .SYNOPSIS
        Dia da serie por dia, com o dia da semana que ajuda a reconhecer o pico.
        .DESCRIPTION
        O coletor manda o dia local ja resolvido, entao aqui nao ha conversao de
        fuso: so formatacao. Data ilegivel volta como veio, para a janela nao
        esconder um contrato que mudou.
        .EXAMPLE
        Format-KiroDayLabel -IsoDate '2026-08-04'   # 'ter 04/08'
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$IsoDate)

    [datetime]$data = [datetime]::MinValue
    $lido = [datetime]::TryParseExact(
        $IsoDate, 'yyyy-MM-dd', [cultureinfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None, [ref]$data)
    if (-not $lido) { return $IsoDate }
    return $data.ToString('ddd dd/MM')
}

function Format-KiroChatTitle {
    <#
        .SYNOPSIS
        Titulo da conversa em uma linha, cortado no limite da coluna.
        .DESCRIPTION
        O titulo e o primeiro prompt da conversa, que pode ter varias linhas.
        .EXAMPLE
        Format-KiroChatTitle -Title "arrumar`n o build" -MaxLength 20
    #>
    param(
        [AllowNull()][AllowEmptyString()][string]$Title,
        [ValidateRange(8, 200)][int]$MaxLength = 52
    )
    $limpo = ($Title -replace '\s+', ' ').Trim()
    if ([string]::IsNullOrEmpty($limpo)) { return $script:TituloAusente }
    if ($limpo.Length -le $MaxLength) { return $limpo }
    return $limpo.Substring(0, $MaxLength - 3) + '...'
}

function Get-KiroBarWidth {
    <#
        .SYNOPSIS
        Largura em pixels da barra de um dia, proporcional ao maior dia.
        .DESCRIPTION
        Dia com consumo minimo recebe 2 pixels em vez de zero: barra invisivel
        se confunde com dia sem consumo.
        .EXAMPLE
        Get-KiroBarWidth -Value 30 -Max 120 -MaxWidth 200   # 50
    #>
    param(
        [Parameter(Mandatory)][double]$Value,
        [Parameter(Mandatory)][double]$Max,
        [Parameter(Mandatory)][double]$MaxWidth
    )
    if ($Value -le 0 -or $Max -le 0) { return 0.0 }
    return [math]::Max(2.0, [math]::Round($MaxWidth * $Value / $Max, 1))
}

function Format-KiroDaySummary {
    <#
        .SYNOPSIS
        Resume a serie por dia: quantos dias, media e o pico do ciclo.

        .DESCRIPTION
        As contas cobrem o ciclo inteiro mesmo quando a lista mostra so os dias
        mais recentes: a media do mes nao pode mudar por causa do recorte da tela.
        Havendo corte, o texto diz quantos dias a lista traz.

        .EXAMPLE
        Format-KiroDaySummary -Days $Report.cli_breakdown.by_day -Top 5
    #>
    param(
        [AllowNull()][AllowEmptyCollection()][object[]]$Days,
        [Parameter(Mandatory)][ValidateRange(1, 62)][int]$Top
    )
    $dias = @()
    if ($null -ne $Days) { $dias = @($Days) }
    if ($dias.Count -eq 0) { return 'Nenhum turno do kiro-cli neste ciclo.' }
    $total = ($dias | Measure-Object -Property credits -Sum).Sum
    $pico = @($dias | Sort-Object -Property credits -Descending)[0]
    $media = Format-KiroCredits -Value ([double]$total / $dias.Count)
    $maior = Format-KiroCredits -Value ([double]$pico.credits)
    $quando = Format-KiroDayLabel -IsoDate ([string]$pico.day)
    $cabeca = "$($dias.Count) dias com consumo"
    if ($dias.Count -gt $Top) { $cabeca += " (lista: os $Top mais recentes)" }
    return "$cabeca  |  media $media/dia  |  pico $maior em $quando"
}

function Format-KiroChatSummary {
    <#
        .SYNOPSIS
        Resume a serie por conversa: quantas houve e o peso da maior.
        .DESCRIPTION
        A fatia da maior conversa e o numero que responde "foi um chat que
        pesou ou o mes inteiro".
        .EXAMPLE
        Format-KiroChatSummary -Chats $Report.cli_breakdown.by_chat
    #>
    param([AllowNull()][AllowEmptyCollection()][object[]]$Chats)

    # Nome diferente do parametro de proposito: variavel em PowerShell nao
    # distingue maiuscula, e $chats sobrescreveria $Chats.
    $conversas = @()
    if ($null -ne $Chats) { $conversas = @($Chats) }
    if ($conversas.Count -eq 0) { return 'Nenhuma conversa com credito neste ciclo.' }
    $total = [double]($conversas | Measure-Object -Property credits -Sum).Sum
    $maior = @($conversas | Sort-Object -Property credits -Descending)[0]
    if ($total -le 0) { return "$($conversas.Count) conversas neste ciclo" }
    $fatia = [int][math]::Round(100 * [double]$maior.credits / $total)
    return "$($conversas.Count) conversas  |  a maior concentra $fatia% do consumo do kiro-cli"
}

function Format-KiroChatDetail {
    <#
        .SYNOPSIS
        Segunda linha de uma conversa: projeto, turnos e ultimo uso.
        .EXAMPLE
        Format-KiroChatDetail -Chat $Report.cli_breakdown.by_chat[0]
    #>
    param([Parameter(Mandatory)][pscustomobject]$Chat)

    $projeto = Split-Path -Leaf ([string]$Chat.project_path)
    $ultimo = Format-KiroLocalTime -IsoTimestamp ([string]$Chat.last_turn_at)
    return "$projeto  |  $($Chat.turn_count) turnos  |  ultimo em $ultimo"
}

function Format-KiroStatusLine {
    <#
        .SYNOPSIS
        Rodape: horario da coleta, versao e aviso de metades desencontradas.

        .DESCRIPTION
        A janela vive em %LOCALAPPDATA% e o coletor no clone do repositorio, entao
        um git pull sem reinstalar atualiza so metade. Comparar as duas versoes e
        o que responde "a atualizacao pegou?" sem abrir log nenhum.

        Coletor sem versao e coletor anterior ao versionamento, nao divergencia
        comprovada: nesse caso o rodape mostra so a versao da janela.

        Texto em ASCII de proposito: o PowerShell 5.1 le .ps1 sem BOM como ANSI,
        entao um travessao no fonte chega quebrado na tela.

        .EXAMPLE
        Format-KiroStatusLine -CapturedAt $Report.account.captured_at `
            -WindowVersion '0.2.0' -CollectorVersion '0.2.0'
    #>
    param(
        [AllowNull()][AllowEmptyString()][string]$CapturedAt,
        [AllowNull()][AllowEmptyString()][string]$WindowVersion,
        [AllowNull()][AllowEmptyString()][string]$CollectorVersion
    )
    $base = 'Atualizado ' + (Format-KiroLocalTime -IsoTimestamp $CapturedAt)
    if ([string]::IsNullOrWhiteSpace($WindowVersion)) { return $base }
    if (-not [string]::IsNullOrWhiteSpace($CollectorVersion) -and
        $CollectorVersion -ne $WindowVersion) {
        return "$base  |  janela v$WindowVersion, coletor v$CollectorVersion" +
        '  |  rode ./install.sh no WSL'
    }
    return "$base  |  v$WindowVersion"
}

