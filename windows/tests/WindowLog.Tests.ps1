. "$PSScriptRoot\..\lib\WindowLog.ps1"

Describe 'Get-WindowLogPath' {
    It 'fica fora da pasta de instalacao, que o instalador apaga' {
        Get-WindowLogPath -BaseDir 'C:\Users\dev\AppData\Local' |
            Should Be 'C:\Users\dev\AppData\Local\kiro-eye-monitor\janela.jsonl'
    }
}

Describe 'Write-WindowLogEntry' {
    BeforeEach {
        $script:pasta = Join-Path $env:TEMP ("log-" + [guid]::NewGuid().ToString('N'))
        $script:arquivo = Join-Path $script:pasta 'janela.jsonl'
    }
    AfterEach {
        Remove-Item -LiteralPath $script:pasta -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'cria o diretorio e grava uma linha JSON' {
        Write-WindowLogEntry -Path $script:arquivo -Message 'resposta nao e JSON' | Out-Null

        $entrada = Get-Content -LiteralPath $script:arquivo -Raw | ConvertFrom-Json
        $entrada.mensagem | Should Be 'resposta nao e JSON'
        $entrada.quando | Should Not BeNullOrEmpty
    }

    It 'guarda o contexto informado' {
        Write-WindowLogEntry -Path $script:arquivo -Message 'falhou' `
            -Context @{ distro = 'Ubuntu-24.04'; ponte = '/home/dev/app/scripts/collect.sh' } | Out-Null

        $entrada = Get-Content -LiteralPath $script:arquivo -Raw | ConvertFrom-Json
        $entrada.ambiente.distro | Should Be 'Ubuntu-24.04'
        $entrada.ambiente.ponte | Should Be '/home/dev/app/scripts/collect.sh'
    }

    It 'guarda a saida bruta que a janela nao mostra inteira' {
        $bruto = "wsl.exe : erro cru`nlinha 2 com detalhe tecnico"

        Write-WindowLogEntry -Path $script:arquivo -Message 'curta' -Detail $bruto | Out-Null

        $entrada = Get-Content -LiteralPath $script:arquivo -Raw | ConvertFrom-Json
        $entrada.detalhe | Should Match 'detalhe tecnico'
    }

    It 'omite detalhe vazio' {
        Write-WindowLogEntry -Path $script:arquivo -Message 'curta' -Detail '' | Out-Null

        $entrada = Get-Content -LiteralPath $script:arquivo -Raw | ConvertFrom-Json
        $entrada.PSObject.Properties.Name -contains 'detalhe' | Should Be $false
    }

    It 'acrescenta sem apagar as falhas anteriores' {
        Write-WindowLogEntry -Path $script:arquivo -Message 'primeira' | Out-Null
        Write-WindowLogEntry -Path $script:arquivo -Message 'segunda' | Out-Null

        @(Get-Content -LiteralPath $script:arquivo).Count | Should Be 2
    }

    It 'devolve o caminho do log mesmo quando nao consegue gravar' {
        $impossivel = Join-Path $script:arquivo 'dentro-de-arquivo\janela.jsonl'
        New-Item -ItemType Directory -Path $script:pasta -Force | Out-Null
        Set-Content -LiteralPath $script:arquivo -Value 'nao sou pasta'

        Write-WindowLogEntry -Path $impossivel -Message 'falhou' | Should Be $impossivel
    }
}

Describe 'Limit-LogText' {
    It 'mantem texto curto intacto' {
        Limit-LogText -Text '  erro curto  ' | Should Be 'erro curto'
    }

    It 'trunca texto muito longo' {
        $resultado = Limit-LogText -Text ('x' * 5000)

        $resultado.EndsWith('...(truncado)') | Should Be $true
        $resultado.Length | Should BeLessThan 4100
    }
}
