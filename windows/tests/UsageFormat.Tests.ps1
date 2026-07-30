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
