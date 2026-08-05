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

# Regressao: a aba de analise e mais alta que o resumo e a janela usa
# SizeToContent="Height". O SizeChanged reancorava a janela, entao trocar de aba
# a arrastava sozinha para o canto inferior direito.
Describe 'Move-WindowKeepingBottom' {

    It 'sobe a janela quando a altura cresce, para a base ficar parada' {
        $janela = New-Object System.Windows.Window
        $janela.Top = 300
        Move-WindowKeepingBottom -Window $janela -PreviousHeight 750 -NewHeight 920
        $janela.Top | Should Be 130
    }

    It 'desce a janela quando a altura diminui' {
        $janela = New-Object System.Windows.Window
        $janela.Top = 130
        Move-WindowKeepingBottom -Window $janela -PreviousHeight 920 -NewHeight 750
        $janela.Top | Should Be 300
    }

    It 'ignora a primeira medida, quando ainda nao havia altura' {
        $janela = New-Object System.Windows.Window
        $janela.Top = 300
        Move-WindowKeepingBottom -Window $janela -PreviousHeight 0 -NewHeight 750
        $janela.Top | Should Be 300
    }
}

Describe 'Limit-WindowToWorkArea' {

    $area = [System.Windows.SystemParameters]::WorkArea

    It 'preserva a posicao de quem ja esta dentro da area util' {
        $janela = New-Object System.Windows.Window
        $janela.Width = 470
        $janela.Height = 400
        $janela.Left = $area.Left + 60
        $janela.Top = $area.Top + 40
        Limit-WindowToWorkArea -Window $janela
        $janela.Left | Should Be ($area.Left + 60)
        $janela.Top | Should Be ($area.Top + 40)
    }

    It 'puxa para cima a janela que passou da borda inferior' {
        $janela = New-Object System.Windows.Window
        $janela.Width = 470
        $janela.Height = 400
        $janela.Left = $area.Left
        $janela.Top = $area.Bottom - 100
        Limit-WindowToWorkArea -Window $janela
        $janela.Top | Should Be ($area.Bottom - 400)
    }

    It 'prefere a barra de titulo quando a janela e mais alta que a area util' {
        $janela = New-Object System.Windows.Window
        $janela.Width = 470
        $janela.Height = $area.Height + 200
        $janela.Left = $area.Left
        $janela.Top = $area.Top + 50
        Limit-WindowToWorkArea -Window $janela
        $janela.Top | Should Be $area.Top
    }

    It 'nao estoura na janela que ainda nao tem posicao' {
        $janela = New-Object System.Windows.Window
        { Limit-WindowToWorkArea -Window $janela } | Should Not Throw
    }
}

Describe 'Get-CoordinateInsideRange' {

    It 'devolve o valor intocado quando o intervalo cabe' {
        Get-CoordinateInsideRange -Value 100 -Size 50 -Min 0 -Max 200 | Should Be 100
    }

    It 'recua o minimo necessario para caber no limite superior' {
        Get-CoordinateInsideRange -Value 180 -Size 50 -Min 0 -Max 200 | Should Be 150
    }

    It 'nao passa do limite inferior' {
        Get-CoordinateInsideRange -Value -30 -Size 50 -Min 0 -Max 200 | Should Be 0
    }
}
