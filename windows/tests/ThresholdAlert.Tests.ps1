. "$PSScriptRoot\..\lib\UsageFormat.ps1"
. "$PSScriptRoot\..\lib\ThresholdAlert.ps1"

function New-RelatorioDeTeste {
    param([int]$Percentual = 80, [switch]$SemRitmo)

    $relatorio = [pscustomobject]@{
        account = [pscustomobject]@{
            used_percent = $Percentual
            resets_on    = '2026-08-01'
        }
    }
    if (-not $SemRitmo) {
        $relatorio | Add-Member -NotePropertyName cycle_pace -NotePropertyValue ([pscustomobject]@{
                exhausts_before_reset = $false
                projected_cycle_usage = 8123.45
                period_end            = '2026-08-01'
                projected_exhaustion  = $null
            })
    }
    return $relatorio
}

Describe 'Test-FailureAlert' {
    It 'avisa ao entrar em falha' {
        Test-FailureAlert -Previous 'ok' -Current 'falha' | Should Be $true
    }

    It 'nao repete o aviso enquanto a falha persiste' {
        Test-FailureAlert -Previous 'falha' -Current 'falha' | Should Be $false
    }

    It 'nao avisa quando a coleta volta a funcionar' {
        Test-FailureAlert -Previous 'falha' -Current 'ok' | Should Be $false
    }
}

Describe 'New-FailureAlertContent' {
    It 'traz a mensagem do erro e o caminho do log do WSL' {
        $relatorio = [pscustomobject]@{
            error    = "executavel nao encontrado: 'kiro-cli'"
            log_path = '/home/dev/.local/state/kiro-eye-monitor/erros.jsonl'
        }

        $aviso = New-FailureAlertContent -Report $relatorio -LogPath 'C:\log\janela.jsonl'

        $aviso.Title | Should Be 'kiro-eye-monitor: falha ao ler o consumo'
        $aviso.Message | Should Match "kiro-cli"
        $aviso.Message | Should Match 'diagnostico\.sh'
        $aviso.Message | Should Match 'erros\.jsonl'
    }

    It 'usa o log da janela quando a falha nao chegou ao coletor' {
        $relatorio = [pscustomobject]@{ error = 'resposta nao e JSON' }

        (New-FailureAlertContent -Report $relatorio -LogPath 'C:\log\janela.jsonl').Message |
            Should Match 'janela\.jsonl'
    }
}

Describe 'Test-ThresholdWorsened' {
    It 'avisa quando sai de ok para atencao' {
        Test-ThresholdWorsened -Previous 'ok' -Current 'atencao' | Should Be $true
    }

    It 'avisa quando piora de atencao para critico' {
        Test-ThresholdWorsened -Previous 'atencao' -Current 'critico' | Should Be $true
    }

    It 'nao repete o aviso no mesmo nivel' {
        Test-ThresholdWorsened -Previous 'critico' -Current 'critico' | Should Be $false
    }

    It 'nao avisa quando volta para ok' {
        Test-ThresholdWorsened -Previous 'critico' -Current 'ok' | Should Be $false
    }

    It 'nao trata falha de coleta como consumo alto' {
        Test-ThresholdWorsened -Previous 'ok' -Current 'falha' | Should Be $false
    }
}

Describe 'New-ThresholdAlertContent' {
    It 'usa o percentual da conta no titulo' {
        (New-ThresholdAlertContent -Report (New-RelatorioDeTeste -Percentual 91)).Title |
            Should Be 'kiro-eye-monitor em 91%'
    }

    It 'usa o ritmo do ciclo na mensagem' {
        # Regressao: a chamada pedia o antigo -BurnRate $Report.burn_rate, campo
        # que deixou de existir na troca para cycle_pace, e derrubava a janela
        # no primeiro aviso sob Set-StrictMode.
        (New-ThresholdAlertContent -Report (New-RelatorioDeTeste)).Message |
            Should Match 'Nesse ritmo: 8.123,45 creditos ate o reset em 2026-08-01'
    }

    It 'nao lanca quando o relatorio nao traz o ritmo' {
        (New-ThresholdAlertContent -Report (New-RelatorioDeTeste -SemRitmo)).Message |
            Should Be 'Ciclo reseta em 2026-08-01'
    }
}
