# Testes da ponte PowerShell -> coletor no WSL (Pester 3).

. "$PSScriptRoot\..\lib\KiroCollector.ps1"

Describe 'Get-KiroCollectorArgument' {

    $config = New-KiroCollectorConfig -Distro 'Ubuntu' -BridgePath '/home/dev/app/scripts/collect.sh'

    It 'monta os argumentos da coleta completa' {
        (Get-KiroCollectorArgument -Config $config) -join ' ' |
            Should Be '-d Ubuntu -- /home/dev/app/scripts/collect.sh'
    }

    It 'acrescenta --account-only quando pedido' {
        (Get-KiroCollectorArgument -Config $config -AccountOnly) -join ' ' |
            Should Be '-d Ubuntu -- /home/dev/app/scripts/collect.sh --account-only'
    }
}

Describe 'ConvertFrom-KiroCollectorOutput' {

    It 'converte o relatorio em objeto' {
        $saida = ConvertFrom-KiroCollectorOutput -Raw '{"account":{"plan_name":"KIRO POWER"}}'
        $saida.account.plan_name | Should Be 'KIRO POWER'
    }

    It 'trata saida vazia como falha' {
        (ConvertFrom-KiroCollectorOutput -Raw '').error | Should Be 'o coletor nao devolveu dados'
    }

    It 'trata saida nao-JSON como falha citando o texto' {
        (ConvertFrom-KiroCollectorOutput -Raw 'wsl: distro nao encontrada').error |
            Should Match 'distro nao encontrada'
    }

    It 'preserva o erro estruturado vindo do coletor' {
        (ConvertFrom-KiroCollectorOutput -Raw '{"error":"uv nao encontrado"}').error |
            Should Be 'uv nao encontrado'
    }
}

Describe 'Test-KiroCollectorFailure' {

    It 'reconhece relatorio com erro' {
        Test-KiroCollectorFailure -Report ([pscustomobject]@{ error = 'x' }) | Should Be $true
    }

    It 'reconhece relatorio valido' {
        $ok = [pscustomobject]@{ account = [pscustomobject]@{ plan_name = 'KIRO FREE' } }
        Test-KiroCollectorFailure -Report $ok | Should Be $false
    }

    It 'trata ausencia de relatorio como falha' {
        Test-KiroCollectorFailure -Report $null | Should Be $true
    }
}

Describe 'Set-KiroCollectorEncoding' {

    It 'passa o console para UTF-8, para o titulo de conversa nao chegar quebrado' {
        $anterior = [Console]::OutputEncoding
        try {
            Set-KiroCollectorEncoding | Should Be $true
            [Console]::OutputEncoding.CodePage | Should Be 65001
        }
        finally {
            [Console]::OutputEncoding = $anterior
        }
    }
}

Describe 'Test-KiroReportHasDetail' {

    It 'reconhece relatorio com detalhamento' {
        $relatorio = [pscustomobject]@{ cli_breakdown = [pscustomobject]@{ total_credits = 1.0 } }
        Test-KiroReportHasDetail -Report $relatorio | Should Be $true
    }

    It 'detalhamento nulo conta como ausente' {
        Test-KiroReportHasDetail -Report ([pscustomobject]@{ cli_breakdown = $null }) | Should Be $false
    }

    It 'relatorio de falha nem tem a chave e nao pode estourar' {
        # Set-StrictMode transforma acesso a propriedade inexistente em erro.
        Test-KiroReportHasDetail -Report ([pscustomobject]@{ error = 'x' }) | Should Be $false
    }

    It 'ausencia de relatorio conta como sem detalhamento' {
        Test-KiroReportHasDetail -Report $null | Should Be $false
    }
}

Describe 'Get-KiroReportList' {

    It 'devolve a lista quando o coletor a manda' {
        $detalhe = [pscustomobject]@{ by_day = @(
                [pscustomobject]@{ day = '2026-08-04'; credits = 1.0 }
            )
        }
        (Get-KiroReportList -Source $detalhe -Name 'by_day').Count | Should Be 1
    }

    It 'coletor mais antigo, sem a chave, devolve lista vazia em vez de nulo' {
        # Nulo aqui estouraria no .Count de quem consome, sob Set-StrictMode.
        $detalhe = [pscustomobject]@{ by_project = @() }
        $lista = Get-KiroReportList -Source $detalhe -Name 'by_day'

        ($null -eq $lista) | Should Be $false
        $lista.Count | Should Be 0
    }
}
