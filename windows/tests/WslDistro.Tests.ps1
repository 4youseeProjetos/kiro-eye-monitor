. "$PSScriptRoot\..\lib\WslDistro.ps1"

Describe 'Resolve-WslDistroName' {
    It 'usa a distro padrao quando nada e pedido' {
        Resolve-WslDistroName -Requested '' -Installed @('Ubuntu-24.04', 'docker-desktop') `
            -Default 'Ubuntu-24.04' | Should Be 'Ubuntu-24.04'
    }

    It 'cai na primeira instalada quando o registro nao aponta padrao' {
        Resolve-WslDistroName -Requested '' -Installed @('Debian', 'docker-desktop') -Default '' |
            Should Be 'Debian'
    }

    It 'aceita o nome exato' {
        Resolve-WslDistroName -Requested 'docker-desktop' -Installed @('Ubuntu', 'docker-desktop') `
            -Default 'Ubuntu' | Should Be 'docker-desktop'
    }

    It 'ignora diferenca de caixa e devolve o nome canonico' {
        Resolve-WslDistroName -Requested 'ubuntu-24.04' -Installed @('Ubuntu-24.04') `
            -Default 'Ubuntu-24.04' | Should Be 'Ubuntu-24.04'
    }

    It 'resolve Ubuntu para Ubuntu-24.04 quando so ha um candidato com esse prefixo' {
        # Caso relatado por desenvolvedor: lancador antigo gravou -Distro Ubuntu.
        Resolve-WslDistroName -Requested 'Ubuntu' -Installed @('Ubuntu-24.04', 'docker-desktop') `
            -Default 'Ubuntu-24.04' | Should Be 'Ubuntu-24.04'
    }

    It 'recusa prefixo ambiguo em vez de escolher por conta propria' {
        { Resolve-WslDistroName -Requested 'Ubuntu' -Installed @('Ubuntu-22.04', 'Ubuntu-24.04') `
                -Default 'Ubuntu-22.04' } | Should Throw
    }

    It 'lista as instaladas quando a pedida nao existe' {
        $erro = ''
        try {
            Resolve-WslDistroName -Requested 'Fedora' -Installed @('Ubuntu-24.04') -Default 'Ubuntu-24.04'
        }
        catch { $erro = $_.Exception.Message }
        $erro | Should Match 'Fedora'
        $erro | Should Match 'Ubuntu-24\.04'
    }

    It 'avisa quando nao ha distro alguma' {
        { Resolve-WslDistroName -Requested '' -Installed @() -Default '' } |
            Should Throw 'nenhuma distro WSL instalada'
    }

    It 'descarta nome vazio vindo do registro' {
        Resolve-WslDistroName -Requested '' -Installed @('', 'Ubuntu-24.04') -Default '' |
            Should Be 'Ubuntu-24.04'
    }
}

Describe 'Get-WslDistroInventory' {
    It 'devolve nomes e padrao a partir do registro desta maquina' {
        $inventario = Get-WslDistroInventory
        $inventario.PSObject.Properties.Name -contains 'Names' | Should Be $true
        $inventario.PSObject.Properties.Name -contains 'Default' | Should Be $true
    }

    It 'enxerga a distro onde o projeto vive' {
        # A suite roda a partir do WSL, logo ha pelo menos uma distro registrada.
        @(Get-WslDistroInventory).Names.Count -gt 0 | Should Be $true
    }
}

Describe 'Select-AutomaticDistro' {
    It 'pula as distros do Docker quando uma delas e a padrao' {
        Select-AutomaticDistro -Installed @('docker-desktop', 'docker-desktop-data', 'Ubuntu-24.04') `
            -Default 'docker-desktop' | Should Be 'Ubuntu-24.04'
    }

    It 'mantem a padrao quando ela e utilizavel' {
        Select-AutomaticDistro -Installed @('docker-desktop', 'Debian', 'Ubuntu') -Default 'Ubuntu' |
            Should Be 'Ubuntu'
    }

    It 'usa a primeira util quando a padrao nao esta na lista' {
        Select-AutomaticDistro -Installed @('docker-desktop', 'Debian') -Default 'Sumida' |
            Should Be 'Debian'
    }

    It 'aceita a do Docker se for a unica instalada' {
        # Preferivel tentar e mostrar a falha real a inventar que nao ha distro.
        Select-AutomaticDistro -Installed @('docker-desktop') -Default 'docker-desktop' |
            Should Be 'docker-desktop'
    }

    It 'nao confunde distro cujo nome apenas comeca com docker-desktop' {
        Test-DockerInfrastructureDistro -Name 'docker-desktop-dev-ubuntu' | Should Be $false
        Test-DockerInfrastructureDistro -Name 'docker-desktop' | Should Be $true
        Test-DockerInfrastructureDistro -Name 'docker-desktop-data' | Should Be $true
    }

    It 'e usada pela resolucao quando nada e pedido' {
        Resolve-WslDistroName -Requested '' -Installed @('docker-desktop', 'Ubuntu-24.04') `
            -Default 'docker-desktop' | Should Be 'Ubuntu-24.04'
    }

    It 'nao interfere quando a do Docker e pedida de proposito' {
        Resolve-WslDistroName -Requested 'docker-desktop' -Installed @('docker-desktop', 'Ubuntu') `
            -Default 'Ubuntu' | Should Be 'docker-desktop'
    }
}
