# Renderizacao do relatorio nos controles da janela.
#
# Separado do entrypoint para poder ser exercitado sem abrir janela: os testes
# carregam o XAML, chamam Show-UsageReport e conferem os textos resultantes.

Set-StrictMode -Version Latest

$script:RecursoPorNivel = @{
    'critico' = 'CorCritica'
    'atencao' = 'CorAtencao'
    'ok'      = 'CorOk'
}
$script:NivelFalha = 'falha'
# Ausencia de detalhamento hoje e leitura incompleta, e nao escolha do usuario:
# toda coleta da janela pede o detalhe.
$script:SemDetalhamento = 'Sem detalhamento do kiro-cli nesta leitura.'

function New-UsageWindow {
    <#
        .SYNOPSIS
        Carrega o XAML da janela.
        .EXAMPLE
        $janela = New-UsageWindow -XamlPath 'C:\app\MainWindow.xaml'
    #>
    param([Parameter(Mandatory)][string]$XamlPath)
    $xaml = [xml](Get-Content -Path $XamlPath -Raw -Encoding UTF8)
    return [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
}

function Set-WindowInsideWorkArea {
    <#
        .SYNOPSIS
        Ancora a janela no canto inferior direito da area util.

        .DESCRIPTION
        Posicionamento inicial, uma vez por sessao. Mudanca de tamanho depois
        disso nao passa por aqui: reancorar a cada SizeChanged arrastava a janela
        de volta para o canto quando o dev trocava de aba, mesmo se ele a tivesse
        movido para outro monitor. Para isso existem Move-WindowKeepingBottom e
        Limit-WindowToWorkArea, que preservam onde a janela esta.

        WindowStartupLocation="CenterScreen" posicionava a janela fora do
        desktop nesta maquina (dois monitores com escalas de DPI diferentes: o
        retangulo saia em x=4614 com area util de 3840). SystemParameters.WorkArea
        vem nas mesmas unidades independentes de dispositivo que o WPF usa para
        Left/Top, entao o calculo aqui e consistente.

        .EXAMPLE
        Set-WindowInsideWorkArea -Window $janela -Margin 24
    #>
    param(
        [Parameter(Mandatory)]$Window,
        [int]$Margin = 24
    )
    $area = [System.Windows.SystemParameters]::WorkArea
    $largura = Get-EffectiveSize -Actual $Window.ActualWidth -Declared $Window.Width -Fallback 430
    $altura = Get-EffectiveSize -Actual $Window.ActualHeight -Declared $Window.Height -Fallback 480
    $Window.Left = [math]::Max($area.Left, $area.Right - $largura - $Margin)
    $Window.Top = [math]::Max($area.Top, $area.Bottom - $altura - $Margin)
}

function Move-WindowKeepingBottom {
    <#
        .SYNOPSIS
        Mantem a borda inferior parada quando a altura muda.

        .DESCRIPTION
        A janela tem SizeToContent="Height", entao trocar de aba muda a altura: a
        aba de analise e mais alta que o resumo. Crescendo para baixo, a janela
        ancorada no canto inferior passava da area util; crescendo para cima, o
        rodape e o botao Atualizar ficam onde estavam e a troca de aba nao parece
        um pulo.

        Ignora a primeira medida, quando PreviousHeight ainda e zero: ali quem
        posiciona e Set-WindowInsideWorkArea, no evento Loaded.

        .EXAMPLE
        Move-WindowKeepingBottom -Window $janela -PreviousHeight 753 -NewHeight 926
    #>
    param(
        [Parameter(Mandatory)]$Window,
        [Parameter(Mandatory)][double]$PreviousHeight,
        [Parameter(Mandatory)][double]$NewHeight
    )
    if ($PreviousHeight -le 0 -or [double]::IsNaN($Window.Top)) { return }
    $Window.Top = $Window.Top - ($NewHeight - $PreviousHeight)
}

function Limit-WindowToWorkArea {
    <#
        .SYNOPSIS
        Empurra a janela de volta para dentro da area util, sem reposicionar.

        .DESCRIPTION
        Corrige so o que passou da borda, e pelo minimo necessario, para que a
        janela continue onde o dev a deixou. Sem posicao definida ainda
        (Left/Top em NaN antes do Loaded) nao ha o que corrigir.

        .EXAMPLE
        Limit-WindowToWorkArea -Window $janela
    #>
    param([Parameter(Mandatory)]$Window)
    if ([double]::IsNaN($Window.Left) -or [double]::IsNaN($Window.Top)) { return }
    $area = [System.Windows.SystemParameters]::WorkArea
    $largura = Get-EffectiveSize -Actual $Window.ActualWidth -Declared $Window.Width -Fallback 430
    $altura = Get-EffectiveSize -Actual $Window.ActualHeight -Declared $Window.Height -Fallback 480
    $Window.Left = Get-CoordinateInsideRange -Value $Window.Left -Size $largura -Min $area.Left -Max $area.Right
    $Window.Top = Get-CoordinateInsideRange -Value $Window.Top -Size $altura -Min $area.Top -Max $area.Bottom
}

function Get-CoordinateInsideRange {
    <#
        Menor deslocamento que traz o intervalo [Value, Value+Size] para dentro
        de [Min, Max]. Nao cabendo, Min ganha: e melhor perder a borda de baixo
        do que a barra de titulo, que e por onde se arrasta a janela.
    #>
    param(
        [Parameter(Mandatory)][double]$Value,
        [Parameter(Mandatory)][double]$Size,
        [Parameter(Mandatory)][double]$Min,
        [Parameter(Mandatory)][double]$Max
    )
    if ($Value + $Size -gt $Max) { $Value = $Max - $Size }
    return [math]::Max($Min, $Value)
}

function Get-EffectiveSize {
    <# Primeira dimensao utilizavel: medida, declarada ou padrao. #>
    param(
        [Parameter(Mandatory)][AllowNull()][object]$Actual,
        [Parameter(Mandatory)][AllowNull()][object]$Declared,
        [Parameter(Mandatory)][double]$Fallback
    )
    foreach ($candidato in @($Actual, $Declared)) {
        $valor = $candidato -as [double]
        if ($null -ne $valor -and $valor -gt 0 -and -not [double]::IsNaN($valor)) { return $valor }
    }
    return $Fallback
}

function Get-WindowControl {
    <# Mapa nome -> controle, para evitar FindName espalhado pelo codigo. #>
    param([Parameter(Mandatory)]$Window, [Parameter(Mandatory)][string[]]$Names)
    $mapa = @{}
    foreach ($nome in $Names) { $mapa[$nome] = $Window.FindName($nome) }
    return $mapa
}

function Get-UsageBarBrush {
    <#
        .SYNOPSIS
        Pincel da barra conforme o nivel de alerta.

        .DESCRIPTION
        As cores vivem no MainWindow.xaml; aqui so se resolve a chave. Qualquer
        FrameworkElement da janela alcanca os recursos dela via FindResource.

        .EXAMPLE
        Get-UsageBarBrush -Level 'critico' -Element $Ui.UsageBar
    #>
    param(
        [Parameter(Mandatory)][string]$Level,
        [Parameter(Mandatory)]$Element
    )
    $chave = $script:RecursoPorNivel[$Level]
    if (-not $chave) { $chave = $script:RecursoPorNivel['ok'] }
    return $Element.FindResource($chave)
}

function ConvertTo-ProjectRow {
    <#
        Linhas da lista de projetos, recortadas ao topo configurado.

        Devolve uma List para nao ser desempacotada pelo PowerShell quando ha
        so um projeto: ItemsSource exige uma colecao, nao um objeto solto.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Groups,
        [Parameter(Mandatory)][int]$Top
    )
    $linhas = New-Object 'System.Collections.Generic.List[object]'
    foreach ($grupo in ($Groups | Select-Object -First $Top)) {
        $linhas.Add([pscustomobject]@{
                Nome     = Split-Path -Leaf $grupo.label
                Caminho  = "$($grupo.label)  ($($grupo.turn_count) turnos)"
                Creditos = Format-KiroCredits -Value ([double]$grupo.credits)
            })
    }
    return , $linhas
}

function Show-AccountSection {
    <# Preenche a parte principal e devolve o nivel de alerta. #>
    param(
        [Parameter(Mandatory)][hashtable]$Ui,
        [Parameter(Mandatory)][pscustomobject]$Report,
        [Parameter(Mandatory)][int]$WarnPercent,
        [Parameter(Mandatory)][int]$CriticalPercent
    )
    $conta = $Report.account
    $nivel = Get-KiroAlertLevel -UsedPercent ([int]$conta.used_percent) `
        -WarnPercent $WarnPercent -CriticalPercent $CriticalPercent
    $Ui.PlanText.Text = "$($conta.plan_name)  |  reseta em $($conta.resets_on)"
    $Ui.HeadlineText.Text = Format-KiroAccountHeadline -Account $conta
    $Ui.UsageBar.Value = [double]$conta.used_percent
    $Ui.UsageBar.Foreground = Get-UsageBarBrush -Level $nivel -Element $Ui.UsageBar
    $restante = Format-KiroCredits -Value ([double]$conta.credits_remaining)
    $Ui.PercentText.Text = "$($conta.used_percent)% consumido  |  restam $restante creditos"
    $Ui.BurnText.Text = Format-KiroCyclePace -Pace $Report.cycle_pace
    $Ui.ProjectionText.Text = Format-KiroProjection -Pace $Report.cycle_pace -Account $conta
    return $nivel
}

function Set-WindowIcon {
    <#
        .SYNOPSIS
        Aplica o icone do olho na janela, se o arquivo existir.

        .DESCRIPTION
        Definido em codigo, e nao no XAML, porque o XAML carregado por
        XamlReader nao tem URI base para resolver caminho relativo.

        Escolhe o maior frame do .ico: BitmapFrame.Create devolveria apenas o
        primeiro (16x16), que a barra de tarefas e o Alt+Tab teriam de ampliar.

        .EXAMPLE
        Set-WindowIcon -Window $janela -IconPath 'C:\app\assets\eye.ico'
    #>
    param([Parameter(Mandatory)]$Window, [Parameter(Mandatory)][string]$IconPath)

    if (-not (Test-Path -LiteralPath $IconPath)) { return $false }
    $Window.Icon = Get-LargestIconFrame -IconPath $IconPath
    return $true
}

function Get-LargestIconFrame {
    <# Frame de maior resolucao dentro de um arquivo .ico. #>
    param([Parameter(Mandatory)][string]$IconPath)

    $decodificador = New-Object System.Windows.Media.Imaging.IconBitmapDecoder(
        (New-Object System.Uri($IconPath)),
        [System.Windows.Media.Imaging.BitmapCreateOptions]::None,
        [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    )
    return $decodificador.Frames | Sort-Object -Property PixelWidth -Descending | Select-Object -First 1
}

function Show-DetailSection {
    <#
        Preenche o detalhamento por projeto do kiro-cli.

        Ausencia de detalhamento hoje significa leitura incompleta, e nao escolha
        do usuario: toda coleta da janela pede o detalhe.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Ui,
        [Parameter(Mandatory)][pscustomobject]$Report,
        [Parameter(Mandatory)][int]$TopProjects
    )
    if (-not (Test-KiroReportHasDetail -Report $Report)) {
        $Ui.CliTotalText.Text = $script:SemDetalhamento
        $Ui.ProjectList.ItemsSource = @()
        $Ui.UnattributedText.Text = ''
        return
    }
    $detalhe = $Report.cli_breakdown
    $total = Format-KiroCredits -Value ([double]$detalhe.total_credits)
    $Ui.CliTotalText.Text = "kiro-cli nesta maquina: $total creditos em " +
    "$($detalhe.turn_count) turnos desde $($detalhe.period_start)"
    $Ui.ProjectList.ItemsSource = ConvertTo-ProjectRow -Groups $detalhe.by_project -Top $TopProjects
    $Ui.UnattributedText.Text = Format-KiroUnattributed -Credits $Report.unattributed_credits
}

$script:LarguraDaBarraDeDia = 190

function ConvertTo-DayRow {
    <#
        Linhas da serie por dia, com a barra proporcional ao dia de maior consumo.

        Devolve uma List para nao ser desempacotada pelo PowerShell quando ha um
        dia so: ItemsSource exige colecao.
    #>
    param(
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$Days,
        [Parameter(Mandatory)][int]$Top,
        [double]$BarWidth = $script:LarguraDaBarraDeDia
    )
    $linhas = New-Object 'System.Collections.Generic.List[object]'
    $dias = @()
    if ($null -ne $Days) { $dias = @($Days) }
    if ($dias.Count -eq 0) { return , $linhas }
    $pico = [double](@($dias | Sort-Object -Property credits -Descending)[0].credits)
    foreach ($dia in ($dias | Select-Object -First $Top)) {
        $linhas.Add([pscustomobject]@{
                Dia      = Format-KiroDayLabel -IsoDate ([string]$dia.day)
                Largura  = Get-KiroBarWidth -Value ([double]$dia.credits) -Max $pico -MaxWidth $BarWidth
                Creditos = Format-KiroCredits -Value ([double]$dia.credits)
                Dica     = "$($dia.turn_count) turnos em $($dia.chat_count) conversas"
            })
    }
    return , $linhas
}

function ConvertTo-ChatRow {
    <#
        Linhas da serie por conversa, recortadas ao topo configurado.

        A dica guarda o titulo inteiro e o caminho do projeto, que nao cabem na
        largura da janela.
    #>
    param(
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$Chats,
        [Parameter(Mandatory)][int]$Top
    )
    $linhas = New-Object 'System.Collections.Generic.List[object]'
    if ($null -eq $Chats) { return , $linhas }
    foreach ($chat in (@($Chats) | Select-Object -First $Top)) {
        $linhas.Add([pscustomobject]@{
                Titulo   = Format-KiroChatTitle -Title ([string]$chat.title)
                Creditos = Format-KiroCredits -Value ([double]$chat.credits)
                Detalhe  = Format-KiroChatDetail -Chat $chat
                Dica     = "$($chat.title)`n$($chat.project_path)"
            })
    }
    return , $linhas
}

function Show-AnalysisSection {
    <#
        .SYNOPSIS
        Preenche a aba de analise: consumo por dia e por conversa.
        .DESCRIPTION
        Sem detalhamento no relatorio as listas ficam vazias e o texto diz o que
        fazer, em vez de deixar os tracinhos do XAML na tela.
        .EXAMPLE
        Show-AnalysisSection -Ui $ui -Report $relatorio -TopDays 14 -TopChats 10
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Ui,
        [Parameter(Mandatory)][pscustomobject]$Report,
        [Parameter(Mandatory)][int]$TopDays,
        [Parameter(Mandatory)][int]$TopChats
    )
    if (-not (Test-KiroReportHasDetail -Report $Report)) {
        Clear-AnalysisSection -Ui $Ui -Message $script:SemDetalhamento
        return
    }
    $dias = Get-KiroReportList -Source $Report.cli_breakdown -Name 'by_day'
    $chats = Get-KiroReportList -Source $Report.cli_breakdown -Name 'by_chat'
    $Ui.DaySummaryText.Text = Format-KiroDaySummary -Days $dias -Top $TopDays
    $Ui.DayList.ItemsSource = ConvertTo-DayRow -Days $dias -Top $TopDays
    $Ui.ChatSummaryText.Text = Format-KiroChatSummary -Chats $chats
    $Ui.ChatList.ItemsSource = ConvertTo-ChatRow -Chats $chats -Top $TopChats
}

function Clear-AnalysisSection {
    <# Esvazia a aba de analise com um recado no lugar dos numeros. #>
    param(
        [Parameter(Mandatory)][hashtable]$Ui,
        [Parameter(Mandatory)][string]$Message
    )
    $Ui.DaySummaryText.Text = $Message
    $Ui.ChatSummaryText.Text = $Message
    $Ui.DayList.ItemsSource = @()
    $Ui.ChatList.ItemsSource = @()
}

function Show-FailurePanel {
    <#
        .SYNOPSIS
        Mostra a falha no topo, com onde olhar e o que rodar.
        .EXAMPLE
        Show-FailurePanel -Ui $ui -Report $relatorio -LogPath 'C:\...\janela.jsonl'
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Ui,
        [Parameter(Mandatory)][pscustomobject]$Report,
        [AllowEmptyString()][string]$LogPath = ''
    )
    $Ui.ErrorPanel.Visibility = 'Visible'
    $Ui.ErrorText.Text = Format-KiroErrorSummary -Message ([string]$Report.error)
    $Ui.ErrorHintText.Text = Format-KiroFailureHint -Report $Report -LogPath $LogPath
    $Ui.HeadlineText.Text = 'sem dados'
    $Ui.PlanText.Text = 'nao foi possivel consultar a conta'
    $Ui.PercentText.Text = ''
    $Ui.BurnText.Text = ''
    $Ui.ProjectionText.Text = ''
    Clear-AnalysisSection -Ui $Ui -Message 'sem dados'
}

function Show-UsageReport {
    <#
        .SYNOPSIS
        Desenha o relatorio inteiro e devolve o nivel de alerta resultante.
        .EXAMPLE
        $nivel = Show-UsageReport -Ui $ui -Report $relatorio -WarnPercent 75 -CriticalPercent 90 -TopProjects 8
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Ui,
        [Parameter(Mandatory)][pscustomobject]$Report,
        [Parameter(Mandatory)][int]$WarnPercent,
        [Parameter(Mandatory)][int]$CriticalPercent,
        [Parameter(Mandatory)][int]$TopProjects,
        # Cinco dias e o que responde "como esta esta semana" sem virar tabela;
        # a media e o pico do resumo continuam cobrindo o ciclo inteiro.
        [ValidateRange(1, 62)][int]$TopDays = 5,
        [ValidateRange(1, 100)][int]$TopChats = 10,
        [AllowEmptyString()][string]$WindowVersion = '',
        [AllowEmptyString()][string]$LogPath = ''
    )
    if (Test-KiroCollectorFailure -Report $Report) {
        Show-FailurePanel -Ui $Ui -Report $Report -LogPath $LogPath
        $Ui.StatusText.Text = 'Falha as ' + (Get-Date).ToString('HH:mm')
        return $script:NivelFalha
    }
    $Ui.ErrorPanel.Visibility = 'Collapsed'
    $nivel = Show-AccountSection -Ui $Ui -Report $Report `
        -WarnPercent $WarnPercent -CriticalPercent $CriticalPercent
    Show-DetailSection -Ui $Ui -Report $Report -TopProjects $TopProjects
    Show-AnalysisSection -Ui $Ui -Report $Report -TopDays $TopDays -TopChats $TopChats
    $Ui.StatusText.Text = Format-KiroStatusLine -CapturedAt $Report.account.captured_at `
        -WindowVersion $WindowVersion `
        -CollectorVersion (Get-KiroReportText -Source $Report -Name 'collector_version')
    return $nivel
}
