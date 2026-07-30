# Testes do posicionamento da janela (Pester 3).
#
# Regressao: com dois monitores de escalas diferentes, WindowStartupLocation
# CenterScreen colocava a janela em x=4614 com area util de 3840 de largura,
# ou seja, fora do desktop.

Add-Type -AssemblyName PresentationFramework

. "$PSScriptRoot\..\lib\KiroCollector.ps1"
. "$PSScriptRoot\..\lib\UsageFormat.ps1"
. "$PSScriptRoot\..\lib\UsageView.ps1"

$script:XamlPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'MainWindow.xaml'

Describe 'Get-EffectiveSize' {

    It 'prefere a dimensao medida' {
        Get-EffectiveSize -Actual 430 -Declared 999 -Fallback 100 | Should Be 430
    }

    It 'cai para a declarada quando a medida ainda e zero' {
        Get-EffectiveSize -Actual 0 -Declared 430 -Fallback 100 | Should Be 430
    }

    It 'cai para o padrao quando a declarada e NaN' {
        Get-EffectiveSize -Actual 0 -Declared ([double]::NaN) -Fallback 480 | Should Be 480
    }

    It 'cai para o padrao quando nada foi informado' {
        Get-EffectiveSize -Actual $null -Declared $null -Fallback 480 | Should Be 480
    }
}

Describe 'Set-WindowInsideWorkArea' {

    $area = [System.Windows.SystemParameters]::WorkArea
    $janela = New-UsageWindow -XamlPath $script:XamlPath
    Set-WindowInsideWorkArea -Window $janela -Margin 24

    It 'nao deixa a janela passar da borda direita' {
        ($janela.Left + $janela.Width) | Should BeLessThan ($area.Right + 1)
    }

    It 'nao deixa a janela passar da borda esquerda' {
        $janela.Left | Should Not BeLessThan $area.Left
    }

    It 'nao deixa a janela passar da borda superior' {
        $janela.Top | Should Not BeLessThan $area.Top
    }

    It 'mantem a janela dentro da altura da area util' {
        $janela.Top | Should BeLessThan $area.Bottom
    }
}
