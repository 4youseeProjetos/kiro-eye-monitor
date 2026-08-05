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
    'CliTotalText', 'ProjectList', 'UnattributedText',
    'MainTabs', 'SummaryTab', 'AnalysisTab',
    'DaySummaryText', 'DayList', 'ChatSummaryText', 'ChatList',
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
        collector_version    = '0.2.0'
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
            by_day        = @(
                [pscustomobject]@{ day = '2026-07-30'; credits = 3.03; turn_count = 1; chat_count = 1 },
                [pscustomobject]@{ day = '2026-07-29'; credits = 119.07; turn_count = 27; chat_count = 5 },
                [pscustomobject]@{ day = '2026-07-28'; credits = 1.82; turn_count = 1; chat_count = 1 }
            )
            by_chat       = @(
                [pscustomobject]@{
                    session_id   = 'ffc49450-8e41-42a1-9d38-7441322e2676'
                    title        = "revisar o parser do /usage`ne o agregador"
                    project_path = '/home/dev/loja-online'
                    credits      = 84.55
                    turn_count   = 15
                    first_turn_at = '2026-07-29T11:57:54+00:00'
                    last_turn_at  = '2026-07-30T13:00:06+00:00'
                },
                [pscustomobject]@{
                    session_id   = '0912b62a-0d3a-46f2-b349-a65e8bd58b8e'
                    title        = 'ajustar o instalador'
                    project_path = '/home/dev/painel-interno'
                    credits      = 21.4
                    turn_count   = 6
                    first_turn_at = '2026-07-28T09:10:00+00:00'
                    last_turn_at  = '2026-07-28T10:30:00+00:00'
                }
            )
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

    It 'diz que a leitura veio sem detalhamento, em vez de deixar tracinho' {
        $ui.CliTotalText.Text | Should Match 'Sem detalhamento'
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

Describe 'Aba de analise com as series por dia e por chat' {

    $ui = New-TestUi
    $null = Show-UsageReport -Ui $ui -Report (New-TestReport) `
        -WarnPercent 75 -CriticalPercent 90 -TopProjects 8

    It 'existe a aba de analise no XAML' {
        $ui.AnalysisTab | Should Not BeNullOrEmpty
        $ui.AnalysisTab.Header | Should Be 'Analise'
    }

    It 'a aba aberta ao iniciar continua sendo o resumo' {
        $ui.SummaryTab.IsSelected | Should Be $true
    }

    It 'resume os dias com consumo do ciclo' {
        $ui.DaySummaryText.Text | Should Match '^3 dias com consumo'
    }

    It 'lista um dia por linha, do mais recente para o mais antigo' {
        @($ui.DayList.ItemsSource).Count | Should Be 3
        @($ui.DayList.ItemsSource)[0].Dia | Should Match '30/07'
    }

    It 'a barra do dia de pico e a mais larga' {
        $linhas = @($ui.DayList.ItemsSource)
        $linhas[1].Largura | Should BeGreaterThan $linhas[0].Largura
    }

    It 'guarda turnos e conversas do dia na dica' {
        @($ui.DayList.ItemsSource)[1].Dica | Should Match '27 turnos em 5 conversas'
    }

    It 'resume as conversas e o peso da maior' {
        $ui.ChatSummaryText.Text | Should Match '^2 conversas'
        $ui.ChatSummaryText.Text | Should Match '% do consumo'
    }

    It 'lista as conversas da mais cara para a mais barata' {
        @($ui.ChatList.ItemsSource)[0].Titulo | Should Match 'revisar o parser'
        @($ui.ChatList.ItemsSource)[1].Titulo | Should Be 'ajustar o instalador'
    }

    It 'titulo de varias linhas cabe em uma linha' {
        @($ui.ChatList.ItemsSource)[0].Titulo | Should Not Match "`n"
    }

    It 'a segunda linha da conversa traz projeto, turnos e ultimo uso' {
        $detalhe = @($ui.ChatList.ItemsSource)[0].Detalhe
        $detalhe | Should Match 'loja-online'
        $detalhe | Should Match '15 turnos'
        $detalhe | Should Match 'ultimo em'
    }

    It 'a dica preserva o titulo inteiro e o caminho do projeto' {
        @($ui.ChatList.ItemsSource)[0].Dica | Should Match '/home/dev/loja-online'
    }
}

Describe 'Rodape com a versao da janela' {

    It 'mostra a versao instalada ao lado do horario' {
        $ui = New-TestUi
        $null = Show-UsageReport -Ui $ui -Report (New-TestReport) `
            -WarnPercent 75 -CriticalPercent 90 -TopProjects 8 -WindowVersion '0.2.0'
        $ui.StatusText.Text | Should Match 'v0\.2\.0$'
    }

    It 'avisa quando o coletor esta em outra versao' {
        $ui = New-TestUi
        $relatorio = New-TestReport
        $relatorio.collector_version = '0.9.9'
        $null = Show-UsageReport -Ui $ui -Report $relatorio `
            -WarnPercent 75 -CriticalPercent 90 -TopProjects 8 -WindowVersion '0.2.0'
        $ui.StatusText.Text | Should Match 'janela v0\.2\.0, coletor v0\.9\.9'
    }

    It 'sem versao instalada o rodape fica como antes' {
        $ui = New-TestUi
        $null = Show-UsageReport -Ui $ui -Report (New-TestReport) `
            -WarnPercent 75 -CriticalPercent 90 -TopProjects 8
        $ui.StatusText.Text | Should Match '^Atualizado \d\d/\d\d \d\d:\d\d$'
    }
}

Describe 'Aba de analise limitando as listas' {
    It 'respeita o topo de dias e de conversas' {
        $ui = New-TestUi
        $null = Show-UsageReport -Ui $ui -Report (New-TestReport) `
            -WarnPercent 75 -CriticalPercent 90 -TopProjects 8 -TopDays 2 -TopChats 1
        @($ui.DayList.ItemsSource).Count | Should Be 2
        @($ui.ChatList.ItemsSource).Count | Should Be 1
    }

    It 'por padrao mostra no maximo os cinco dias mais recentes com consumo' {
        $ui = New-TestUi
        $relatorio = New-TestReport
        $relatorio.cli_breakdown.by_day = @(
            [pscustomobject]@{ day = '2026-07-30'; credits = 9.0; turn_count = 2; chat_count = 1 },
            [pscustomobject]@{ day = '2026-07-29'; credits = 8.0; turn_count = 2; chat_count = 1 },
            [pscustomobject]@{ day = '2026-07-28'; credits = 7.0; turn_count = 2; chat_count = 1 },
            [pscustomobject]@{ day = '2026-07-27'; credits = 6.0; turn_count = 2; chat_count = 1 },
            [pscustomobject]@{ day = '2026-07-26'; credits = 5.0; turn_count = 2; chat_count = 1 },
            [pscustomobject]@{ day = '2026-07-25'; credits = 4.0; turn_count = 2; chat_count = 1 },
            [pscustomobject]@{ day = '2026-07-24'; credits = 3.0; turn_count = 2; chat_count = 1 }
        )
        $null = Show-UsageReport -Ui $ui -Report $relatorio `
            -WarnPercent 75 -CriticalPercent 90 -TopProjects 8

        @($ui.DayList.ItemsSource).Count | Should Be 5
        @($ui.DayList.ItemsSource)[0].Dia | Should Match '30/07'
        @($ui.DayList.ItemsSource)[4].Dia | Should Match '26/07'
    }

    It 'o resumo avisa que a lista de dias foi cortada' {
        $ui = New-TestUi
        $relatorio = New-TestReport
        $relatorio.cli_breakdown.by_day = @(
            [pscustomobject]@{ day = '2026-07-30'; credits = 9.0; turn_count = 2; chat_count = 1 },
            [pscustomobject]@{ day = '2026-07-29'; credits = 8.0; turn_count = 2; chat_count = 1 },
            [pscustomobject]@{ day = '2026-07-28'; credits = 7.0; turn_count = 2; chat_count = 1 },
            [pscustomobject]@{ day = '2026-07-27'; credits = 6.0; turn_count = 2; chat_count = 1 },
            [pscustomobject]@{ day = '2026-07-26'; credits = 5.0; turn_count = 2; chat_count = 1 },
            [pscustomobject]@{ day = '2026-07-25'; credits = 4.0; turn_count = 2; chat_count = 1 }
        )
        $null = Show-UsageReport -Ui $ui -Report $relatorio `
            -WarnPercent 75 -CriticalPercent 90 -TopProjects 8

        $ui.DaySummaryText.Text | Should Match '^6 dias com consumo \(lista: os 5 mais recentes\)'
    }
}

Describe 'Aba de analise sem detalhamento carregado' {

    $ui = New-TestUi
    $null = Show-UsageReport -Ui $ui -Report (New-TestReport -SemDetalhe) `
        -WarnPercent 75 -CriticalPercent 90 -TopProjects 8

    It 'esvazia as listas' {
        @($ui.DayList.ItemsSource).Count | Should Be 0
        @($ui.ChatList.ItemsSource).Count | Should Be 0
    }

    It 'diz que a leitura veio sem detalhamento, em vez de deixar tracinho' {
        $ui.DaySummaryText.Text | Should Match 'Sem detalhamento'
        $ui.ChatSummaryText.Text | Should Match 'Sem detalhamento'
    }
}

Describe 'Aba de analise com coletor mais antigo que a janela' {

    It 'relatorio sem by_day nem by_chat nao derruba a renderizacao' {
        # Quem faz git pull sem reinstalar fica com as duas metades em versoes
        # diferentes; a janela precisa sobreviver a chave que ainda nao existe.
        $ui = New-TestUi
        $antigo = New-TestReport
        $antigo.cli_breakdown = [pscustomobject]@{
            period_start  = '2026-07-01'
            total_credits = 10.0
            turn_count    = 2
            by_project    = @()
            by_model      = @()
        }
        $null = Show-UsageReport -Ui $ui -Report $antigo `
            -WarnPercent 75 -CriticalPercent 90 -TopProjects 8

        @($ui.DayList.ItemsSource).Count | Should Be 0
        $ui.DaySummaryText.Text | Should Match 'Nenhum turno'
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

    It 'limpa a aba de analise, que tambem depende da coleta' {
        $ui.DaySummaryText.Text | Should Be 'sem dados'
        $ui.ChatSummaryText.Text | Should Be 'sem dados'
        @($ui.DayList.ItemsSource).Count | Should Be 0
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
