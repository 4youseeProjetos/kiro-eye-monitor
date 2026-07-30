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
