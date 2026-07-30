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
