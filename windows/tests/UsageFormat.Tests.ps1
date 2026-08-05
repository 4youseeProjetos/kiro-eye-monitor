# Testes da formatacao exibida na janela (Pester 3).

. "$PSScriptRoot\..\lib\UsageFormat.ps1"

Describe 'Format-KiroCredits' {

    It 'formata com duas casas e volta a ser o mesmo numero na cultura local' {
        $texto = Format-KiroCredits -Value 2349.92
        [double]::Parse($texto, [System.Globalization.NumberStyles]::Number, [cultureinfo]::CurrentCulture) |
            Should Be 2349.92
    }

    It 'arredonda para duas casas' {
        Format-KiroCredits -Value 0.005 | Should Match '0'
    }
}

Describe 'Get-KiroAlertLevel' {

    It 'consumo baixo fica ok' {
        Get-KiroAlertLevel -UsedPercent 23 -WarnPercent 75 -CriticalPercent 90 | Should Be 'ok'
    }

    It 'no limiar de atencao muda de nivel' {
        Get-KiroAlertLevel -UsedPercent 75 -WarnPercent 75 -CriticalPercent 90 | Should Be 'atencao'
    }

    It 'no limiar critico muda de nivel' {
        Get-KiroAlertLevel -UsedPercent 90 -WarnPercent 75 -CriticalPercent 90 | Should Be 'critico'
    }

    It 'acima do critico permanece critico' {
        Get-KiroAlertLevel -UsedPercent 130 -WarnPercent 75 -CriticalPercent 90 | Should Be 'critico'
    }
}

Describe 'Format-KiroCyclePace' {

    It 'avisa quando o ciclo acabou de comecar' {
        Format-KiroCyclePace -Pace $null | Should Match 'primeira hora do ciclo'
    }

    It 'mostra creditos por dia e a amostra do mes' {
        $ritmo = [pscustomobject]@{
            credits_per_day = 79.64
            elapsed_days    = 29.5
            total_days      = 31.0
        }
        $texto = Format-KiroCyclePace -Pace $ritmo
        $texto | Should Match 'creditos/dia'
        $texto | Should Match '29,5 de 31 dias|29\.5 de 31 dias'
    }
}

Describe 'Format-KiroProjection' {

    $conta = [pscustomobject]@{ resets_on = '2026-08-01' }

    It 'sem ritmo informa apenas a data de reset' {
        Format-KiroProjection -Pace $null -Account $conta | Should Match '2026-08-01'
    }

    It 'projeta o consumo do mes quando a cota nao estoura' {
        $ritmo = [pscustomobject]@{
            projected_cycle_usage = 2469.0
            exhausts_before_reset  = $false
            period_end            = '2026-08-01'
            projected_exhaustion  = $null
        }
        Format-KiroProjection -Pace $ritmo -Account $conta |
            Should Match 'creditos ate o reset em 2026-08-01'
    }

    It 'avisa quando a cota acaba antes do reset' {
        $ritmo = [pscustomobject]@{
            projected_cycle_usage = 15000.0
            exhausts_before_reset  = $true
            period_end            = '2026-08-01'
            projected_exhaustion  = '2026-07-21'
        }
        Format-KiroProjection -Pace $ritmo -Account $conta |
            Should Match 'cota acaba em 2026-07-21, antes do reset'
    }
}

Describe 'Format-KiroUnattributed' {

    It 'omite a linha quando nao ha detalhamento' {
        Format-KiroUnattributed -Credits $null | Should Be ''
    }

    It 'explica a origem do resto nao rastreado' {
        Format-KiroUnattributed -Credits 817.54 | Should Match 'Kiro IDE'
    }
}

Describe 'Format-KiroDayLabel' {

    It 'mostra dia da semana e data curta' {
        Format-KiroDayLabel -IsoDate '2026-08-04' | Should Match '04/08$'
    }

    It 'nao converte fuso: o coletor ja manda o dia local' {
        Format-KiroDayLabel -IsoDate '2026-08-04' | Should Not Match '03/08'
    }

    It 'data ilegivel volta como veio, em vez de virar tracinho' {
        Format-KiroDayLabel -IsoDate 'ontem' | Should Be 'ontem'
    }
}

Describe 'Format-KiroChatTitle' {

    It 'mantem titulo curto intacto' {
        Format-KiroChatTitle -Title 'arrumar o build' | Should Be 'arrumar o build'
    }

    It 'junta as linhas do primeiro prompt em uma so' {
        Format-KiroChatTitle -Title "arrumar`n  o build" | Should Be 'arrumar o build'
    }

    It 'corta no limite da coluna' {
        $texto = Format-KiroChatTitle -Title ('x' * 200) -MaxLength 20
        $texto.Length | Should Be 20
        $texto.EndsWith('...') | Should Be $true
    }

    It 'conversa sem titulo recebe rotulo proprio' {
        Format-KiroChatTitle -Title '   ' | Should Be '(sem titulo)'
    }
}

Describe 'Get-KiroBarWidth' {

    It 'o maior dia ocupa a largura toda' {
        Get-KiroBarWidth -Value 120 -Max 120 -MaxWidth 200 | Should Be 200
    }

    It 'dia intermediario fica proporcional' {
        Get-KiroBarWidth -Value 30 -Max 120 -MaxWidth 200 | Should Be 50
    }

    It 'consumo minimo ainda aparece' {
        Get-KiroBarWidth -Value 0.01 -Max 120 -MaxWidth 200 | Should Be 2
    }

    It 'sem consumo nao desenha barra' {
        Get-KiroBarWidth -Value 0 -Max 120 -MaxWidth 200 | Should Be 0
    }

    It 'pico zerado nao divide por zero' {
        Get-KiroBarWidth -Value 0 -Max 0 -MaxWidth 200 | Should Be 0
    }
}

Describe 'Format-KiroDaySummary' {

    $dias = @(
        [pscustomobject]@{ day = '2026-08-05'; credits = 3.03; turn_count = 1; chat_count = 1 },
        [pscustomobject]@{ day = '2026-08-04'; credits = 119.07; turn_count = 27; chat_count = 5 }
    )

    It 'conta os dias com consumo' {
        Format-KiroDaySummary -Days $dias -Top 5 | Should Match '^2 dias com consumo'
    }

    It 'aponta o dia de pico' {
        Format-KiroDaySummary -Days $dias -Top 5 | Should Match 'pico .* em .*04/08'
    }

    It 'informa a media por dia' {
        Format-KiroDaySummary -Days $dias -Top 5 | Should Match 'media .*/dia'
    }

    It 'nao avisa de corte quando a lista cabe inteira' {
        Format-KiroDaySummary -Days $dias -Top 5 | Should Not Match 'lista:'
    }

    It 'avisa quando a lista mostra menos dias do que o ciclo teve' {
        Format-KiroDaySummary -Days $dias -Top 1 | Should Match 'lista: o 1 mais recente|lista: os 1 mais recentes'
    }

    It 'a media continua sendo do ciclo, e nao dos dias exibidos' {
        # 122,10 em dois dias da 61,05, mesmo mostrando um dia so.
        Format-KiroDaySummary -Days $dias -Top 1 | Should Match 'media 61,05/dia|media 61\.05/dia'
    }

    It 'ciclo sem turno explica o vazio' {
        Format-KiroDaySummary -Days @() -Top 5 | Should Match 'Nenhum turno'
    }
}

Describe 'Format-KiroChatSummary' {

    $chats = @(
        [pscustomobject]@{ title = 'a'; credits = 75.0 },
        [pscustomobject]@{ title = 'b'; credits = 25.0 }
    )

    It 'conta as conversas' {
        Format-KiroChatSummary -Chats $chats | Should Match '^2 conversas'
    }

    It 'mostra a fatia da maior conversa' {
        Format-KiroChatSummary -Chats $chats | Should Match '75% do consumo'
    }

    It 'ciclo sem conversa explica o vazio' {
        Format-KiroChatSummary -Chats @() | Should Match 'Nenhuma conversa'
    }
}

Describe 'Format-KiroChatDetail' {

    $chat = [pscustomobject]@{
        project_path = '/home/dev/loja-online'
        turn_count   = 15
        last_turn_at = '2026-08-04T18:12:00+00:00'
    }

    It 'mostra o projeto pelo nome da pasta' {
        Format-KiroChatDetail -Chat $chat | Should Match 'loja-online'
    }

    It 'mostra a contagem de turnos' {
        Format-KiroChatDetail -Chat $chat | Should Match '15 turnos'
    }

    It 'mostra o ultimo uso em hora local' {
        Format-KiroChatDetail -Chat $chat | Should Match 'ultimo em \d\d/\d\d \d\d:\d\d'
    }
}


Describe 'Format-KiroLocalTime' {

    It 'converte ISO-8601 para dia e hora curtos' {
        Format-KiroLocalTime -IsoTimestamp '2026-07-30T15:25:41+00:00' | Should Match '^\d{2}/\d{2} \d{2}:\d{2}$'
    }

    It 'devolve marcador quando nao ha horario' {
        Format-KiroLocalTime -IsoTimestamp $null | Should Be '--'
    }
}

Describe 'Format-KiroErrorSummary' {
    It 'mantem mensagem simples intacta' {
        Format-KiroErrorSummary -Message "executavel nao encontrado: 'kiro-cli'" |
            Should Be "executavel nao encontrado: 'kiro-cli'"
    }

    It 'descarta o despejo de erro do PowerShell' {
        $bruto = @'
resposta nao e JSON: wsl.exe : /bin/bash: line 1: /nao/existe/collect.sh: No such file or directory
No linha:5 caractere:5
+     & wsl.exe @wslArgs 2>&1
+     ~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : NotSpecified: (...)
    + FullyQualifiedErrorId : NativeCommandError
'@
        $resumo = Format-KiroErrorSummary -Message $bruto

        $resumo | Should Match 'No such file or directory'
        $resumo | Should Not Match 'CategoryInfo'
        $resumo | Should Not Match 'FullyQualifiedErrorId'
        $resumo | Should Not Match 'caractere'
    }

    It 'descarta o cabecalho em ingles tambem' {
        Format-KiroErrorSummary -Message "falhou`nAt line:5 char:5" | Should Be 'falhou'
    }

    It 'trunca mensagem muito longa' {
        $resultado = Format-KiroErrorSummary -Message ('x' * 400)

        $resultado.EndsWith('...') | Should Be $true
        $resultado.Length | Should BeLessThan 230
    }

    It 'devolve a mensagem original quando so ha ruido' {
        Format-KiroErrorSummary -Message '+ apenas ruido' | Should Be '+ apenas ruido'
    }
}
