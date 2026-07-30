# Testes de renderizacao: carregam o XAML de verdade e conferem os textos
# escritos nos controles, sem abrir janela (Pester 3).

Add-Type -AssemblyName PresentationFramework

. "$PSScriptRoot\..\lib\KiroCollector.ps1"
. "$PSScriptRoot\..\lib\UsageFormat.ps1"
. "$PSScriptRoot\..\lib\UsageView.ps1"

$script:XamlPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'MainWindow.xaml'
$script:Nomes = @(
    'ErrorPanel', 'ErrorText', 'ErrorHintText',
    'PlanText', 'HeadlineText', 'UsageBar', 'PercentText', 'BurnText', 'ProjectionText',
    'DetailToggle', 'DetailPanel', 'CliTotalText', 'ProjectList', 'UnattributedText',
    'StatusText', 'RefreshButton'
)

function New-TestUi {
    $janela = New-UsageWindow -XamlPath $script:XamlPath
    return Get-WindowControl -Window $janela -Names $script:Nomes
}

# Relatorio equivalente ao que o coletor devolveu de verdade nesta maquina.
function New-TestReport {
    param([switch]$SemDetalhe, [int]$Percent = 23)
    $relatorio = [pscustomobject]@{
        account              = [pscustomobject]@{
            plan_name         = 'KIRO POWER'
            credits_used      = 2349.92
            credits_included  = 10000.0
            credits_remaining = 7650.08
            used_percent      = $Percent
            resets_on         = '2026-08-01'
            captured_at       = '2026-07-30T15:25:41+00:00'
        }
        cycle_pace           = [pscustomobject]@{
            period_start          = '2026-07-01'
            period_end            = '2026-08-01'
            elapsed_days          = 29.5
            total_days            = 31.0
            remaining_days        = 1.5
            credits_per_day       = 79.66
            projected_cycle_usage = 2469.46
            projected_exhaustion  = '2026-11-16'
            exhausts_before_reset = $false
        }
        cli_breakdown        = $null
        unattributed_credits = $null
    }
    if (-not $SemDetalhe) {
        $relatorio.cli_breakdown = [pscustomobject]@{
            period_start  = '2026-07-01'
            total_credits = 1532.38
            turn_count    = 252
            by_project    = @(
                [pscustomobject]@{ label = '/home/dev/loja-online'; credits = 603.4; turn_count = 94 },
                [pscustomobject]@{ label = '/home/dev/painel-interno'; credits = 261.49; turn_count = 40 }
            )
            by_model      = @()
        }
        $relatorio.unattributed_credits = 817.54
    }
    return $relatorio
}

Describe 'Show-UsageReport com o total da conta' {

    $ui = New-TestUi
    $nivel = Show-UsageReport -Ui $ui -Report (New-TestReport -SemDetalhe) `
        -WarnPercent 75 -CriticalPercent 90 -TopProjects 8

    It 'classifica 23% como ok' { $nivel | Should Be 'ok' }

    It 'mostra plano e data de reset' {
        $ui.PlanText.Text | Should Be 'KIRO POWER  |  reseta em 2026-08-01'
    }

    It 'mostra usado e cota na linha principal' {
        $ui.HeadlineText.Text | Should Match 'creditos$'
        $ui.HeadlineText.Text | Should Match '10'
    }

    It 'move a barra para o percentual da conta' { $ui.UsageBar.Value | Should Be 23 }

    It 'informa o saldo restante' { $ui.PercentText.Text | Should Match '23% consumido' }

    It 'mostra o ritmo do mes' { $ui.BurnText.Text | Should Match 'creditos/dia' }

    It 'mostra a projecao do ciclo' { $ui.ProjectionText.Text | Should Match 'ate o reset em 2026-08-01' }

    It 'registra o horario da coleta' { $ui.StatusText.Text | Should Match '^Atualizado ' }

    It 'convida a marcar a caixa quando nao ha detalhamento' {
        $ui.CliTotalText.Text | Should Match 'Marque a caixa'
    }

    It 'nao mostra linha de nao atribuido sem detalhamento' {
        $ui.UnattributedText.Text | Should Be ''
    }
}

Describe 'Show-UsageReport com o detalhamento do kiro-cli' {

    $ui = New-TestUi
    $null = Show-UsageReport -Ui $ui -Report (New-TestReport) `
        -WarnPercent 75 -CriticalPercent 90 -TopProjects 8

    It 'resume total, turnos e inicio do ciclo' {
        $ui.CliTotalText.Text | Should Match '252 turnos desde 2026-07-01'
    }

    It 'lista os projetos pelo nome da pasta' {
        @($ui.ProjectList.ItemsSource)[0].Nome | Should Be 'loja-online'
    }

    It 'guarda o caminho completo e os turnos na dica' {
        @($ui.ProjectList.ItemsSource)[0].Caminho | Should Match '/home/dev/loja-online  \(94 turnos\)'
    }

    It 'ordena preservando a ordem vinda do coletor' {
        @($ui.ProjectList.ItemsSource)[1].Nome | Should Be 'painel-interno'
    }

    It 'explica o credito nao atribuido' {
        $ui.UnattributedText.Text | Should Match 'Nao atribuido'
        $ui.UnattributedText.Text | Should Match 'Kiro IDE'
    }
}

Describe 'Show-UsageReport limitando a lista' {

    It 'respeita o topo configurado' {
        $ui = New-TestUi
        $null = Show-UsageReport -Ui $ui -Report (New-TestReport) `
            -WarnPercent 75 -CriticalPercent 90 -TopProjects 1
        @($ui.ProjectList.ItemsSource).Count | Should Be 1
    }
}

Describe 'Show-UsageReport nos limiares de alerta' {

    It 'consumo normal pinta a barra com o azul da logo' {
        $ui = New-TestUi
        $null = Show-UsageReport -Ui $ui -Report (New-TestReport) `
            -WarnPercent 75 -CriticalPercent 90 -TopProjects 8
        $ui.UsageBar.Foreground.ToString() | Should Be '#FF0096FF'
    }

    It 'sinaliza atencao a partir do limiar configurado' {
        $ui = New-TestUi
        Show-UsageReport -Ui $ui -Report (New-TestReport -Percent 80) `
            -WarnPercent 75 -CriticalPercent 90 -TopProjects 8 | Should Be 'atencao'
    }

    It 'sinaliza critico e pinta a barra' {
        $ui = New-TestUi
        $nivel = Show-UsageReport -Ui $ui -Report (New-TestReport -Percent 95) `
            -WarnPercent 75 -CriticalPercent 90 -TopProjects 8
        $nivel | Should Be 'critico'
        $ui.UsageBar.Foreground.ToString() | Should Be '#FFF48771'
    }
}

Describe 'Show-UsageReport quando a coleta falha' {

    $ui = New-TestUi
    $relatorio = [pscustomobject]@{
        error    = "executavel nao encontrado: 'kiro-cli'"
        log_path = '/home/dev/.local/state/kiro-eye-monitor/erros.jsonl'
    }
    $nivel = Show-UsageReport -Ui $ui -Report $relatorio -WarnPercent 75 -CriticalPercent 90 `
        -TopProjects 8 -LogPath 'C:\log\janela.jsonl'

    It 'devolve nivel de falha' { $nivel | Should Be 'falha' }

    It 'abre o painel de erro, que comeca escondido' {
        # Antes a falha aparecia so numa linha cinza no rodape, enquanto o resto
        # da janela seguia com "Carregando..." e "--".
        $ui.ErrorPanel.Visibility | Should Be 'Visible'
    }

    It 'mostra a causa em destaque, sem o despejo do PowerShell' {
        $ui.ErrorText.Text | Should Be "executavel nao encontrado: 'kiro-cli'"
    }

    It 'limpa os numeros antigos em vez de deixar tracinhos' {
        $ui.BurnText.Text | Should Be ''
        $ui.ProjectionText.Text | Should Be ''
    }

    It 'diz o que fazer e onde estao os detalhes' {
        $ui.ErrorHintText.Text | Should Match 'diagnostico\.sh'
        $ui.ErrorHintText.Text | Should Match 'erros\.jsonl'
    }

    It 'deixa claro que os numeros nao sao validos' {
        $ui.HeadlineText.Text | Should Be 'sem dados'
        $ui.PercentText.Text | Should Be ''
    }

    It 'registra o horario da tentativa' {
        $ui.StatusText.Text | Should Match '^Falha as \d\d:\d\d$'
    }
}

Describe 'Show-UsageReport depois que a coleta volta a funcionar' {

    $ui = New-TestUi
    Show-UsageReport -Ui $ui -Report ([pscustomobject]@{ error = 'falhou' }) `
        -WarnPercent 75 -CriticalPercent 90 -TopProjects 8 | Out-Null
    Show-UsageReport -Ui $ui -Report (New-TestReport) `
        -WarnPercent 75 -CriticalPercent 90 -TopProjects 8 | Out-Null

    It 'esconde o painel de erro' {
        $ui.ErrorPanel.Visibility | Should Be 'Collapsed'
    }

    It 'volta a mostrar os creditos' {
        $ui.HeadlineText.Text | Should Match 'creditos'
    }
}
