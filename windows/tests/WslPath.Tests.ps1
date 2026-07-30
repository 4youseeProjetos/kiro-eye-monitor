# Testes da traducao de caminho Windows -> WSL (Pester 3, o que vem no Windows).

. "$PSScriptRoot\..\lib\WslPath.ps1"

Describe 'Convert-WindowsPathToWslPath' {

    It 'converte caminho UNC wsl.localhost' {
        Convert-WindowsPathToWslPath -Path '\\wsl.localhost\Ubuntu\home\dev\app' |
            Should Be '/home/dev/app'
    }

    It 'converte caminho UNC wsl$ antigo' {
        Convert-WindowsPathToWslPath -Path '\\wsl$\Ubuntu\home\dev\app\scripts' |
            Should Be '/home/dev/app/scripts'
    }

    It 'converte unidade do Windows para /mnt' {
        Convert-WindowsPathToWslPath -Path 'C:\Users\dev\app' | Should Be '/mnt/c/Users/dev/app'
    }

    It 'usa letra de unidade minuscula' {
        Convert-WindowsPathToWslPath -Path 'D:\tmp' | Should Be '/mnt/d/tmp'
    }

    It 'mantem caminho ja no formato POSIX' {
        Convert-WindowsPathToWslPath -Path '/home/dev/app' | Should Be '/home/dev/app'
    }
}

Describe 'Resolve-BridgePath' {
    BeforeEach {
        $script:pasta = Join-Path $env:TEMP ("ponte-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:pasta -Force | Out-Null
    }
    AfterEach {
        Remove-Item -LiteralPath $script:pasta -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'prefere o caminho informado' {
        Set-Content -LiteralPath (Join-Path $script:pasta 'bridge-path.txt') -Value '/anotado/collect.sh'
        Resolve-BridgePath -Informado '/pedido/collect.sh' -ScriptRoot $script:pasta |
            Should Be '/pedido/collect.sh'
    }

    It 'usa a anotacao da instalacao quando nada e informado' {
        Set-Content -LiteralPath (Join-Path $script:pasta 'bridge-path.txt') -Value '/home/dev/app/scripts/collect.sh'
        Resolve-BridgePath -Informado '' -ScriptRoot $script:pasta |
            Should Be '/home/dev/app/scripts/collect.sh'
    }

    It 'ignora espacos e quebra de linha da anotacao' {
        Set-Content -LiteralPath (Join-Path $script:pasta 'bridge-path.txt') -Value "  /home/dev/app/scripts/collect.sh `r`n"
        Resolve-BridgePath -Informado '' -ScriptRoot $script:pasta |
            Should Be '/home/dev/app/scripts/collect.sh'
    }

    It 'deduz pela pasta do projeto quando nao ha anotacao' {
        Resolve-BridgePath -Informado '' -ScriptRoot '\\wsl.localhost\Ubuntu\home\dev\app\windows' |
            Should Be '/home/dev/app/scripts/collect.sh'
    }

    It 'deduz em disco do Windows quando nao ha anotacao' {
        Resolve-BridgePath -Informado '' -ScriptRoot 'C:\projetos\app\windows' |
            Should Be '/mnt/c/projetos/app/scripts/collect.sh'
    }
}
