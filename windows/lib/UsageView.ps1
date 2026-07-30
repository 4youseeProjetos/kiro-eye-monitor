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
    <# Preenche o detalhamento do kiro-cli, quando presente no relatorio. #>
    param(
        [Parameter(Mandatory)][hashtable]$Ui,
        [Parameter(Mandatory)][pscustomobject]$Report,
        [Parameter(Mandatory)][int]$TopProjects
    )
    if ($null -eq $Report.cli_breakdown) {
        $Ui.CliTotalText.Text = 'Marque a caixa para carregar o detalhamento.'
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
        [Parameter(Mandatory)][int]$TopProjects
    )
    if (Test-KiroCollectorFailure -Report $Report) {
        $Ui.StatusText.Text = "Falha: $($Report.error)"
        return $script:NivelFalha
    }
    $nivel = Show-AccountSection -Ui $Ui -Report $Report `
        -WarnPercent $WarnPercent -CriticalPercent $CriticalPercent
    Show-DetailSection -Ui $Ui -Report $Report -TopProjects $TopProjects
    $Ui.StatusText.Text = 'Atualizado ' + (Format-KiroLocalTime -IsoTimestamp $Report.account.captured_at)
    return $nivel
}
