# Estado e comportamento da janela de widget (Pester 3).

Add-Type -AssemblyName PresentationFramework

$script:Modulo = Join-Path $PSScriptRoot '..\lib\WidgetWindow.ps1'
if (Test-Path -LiteralPath $script:Modulo) { . $script:Modulo }

function New-TestWidgetUi {
    return @{
        MinimalPanel    = [pscustomobject]@{ Visibility = 'Collapsed' }
        StandardPanel   = [pscustomobject]@{ Visibility = 'Visible' }
        ExpandedDetails = [pscustomobject]@{ Visibility = 'Collapsed' }
        ExpandButton    = [pscustomobject]@{ IsChecked = $false; ToolTip = '' }
        PinButton       = [pscustomobject]@{ IsChecked = $false; ToolTip = '' }
        MinimalPinButton = [pscustomobject]@{ IsChecked = $false; ToolTip = '' }
    }
}

Describe 'Estado persistido do widget' {

    It 'usa valores seguros quando o arquivo nao existe' {
        $estado = Read-WidgetState -Path (Join-Path $TestDrive 'ausente.json')
        $estado.Left | Should BeNullOrEmpty
        $estado.Top | Should BeNullOrEmpty
        $estado.Pinned | Should Be $false
        $estado.Expanded | Should Be $false
        $estado.ViewMode | Should Be 'normal'
    }

    It 'ignora JSON invalido sem propagar falha' {
        $caminho = Join-Path $TestDrive 'invalido.json'
        Set-Content -LiteralPath $caminho -Value '{nao-json' -Encoding UTF8
        { Read-WidgetState -Path $caminho } | Should Not Throw
        $estado = Read-WidgetState -Path $caminho
        $estado.Pinned | Should Be $false
        $estado.Expanded | Should Be $false
        $estado.ViewMode | Should Be 'normal'
    }

    It 'converte o estado antigo expandido para o modo detalhado' {
        $caminho = Join-Path $TestDrive 'legado.json'
        Set-Content -LiteralPath $caminho -Value '{"expanded":true}' -Encoding UTF8
        $estado = Read-WidgetState -Path $caminho
        $estado.ViewMode | Should Be 'detailed'
        $estado.Expanded | Should Be $true
    }

    It 'troca modo desconhecido pelo normal' {
        $caminho = Join-Path $TestDrive 'modo-invalido.json'
        Set-Content -LiteralPath $caminho -Value '{"view_mode":"gigante"}' -Encoding UTF8
        (Read-WidgetState -Path $caminho).ViewMode | Should Be 'normal'
    }

    It 'grava e restaura coordenadas e preferencias' {
        $caminho = Join-Path (Join-Path $TestDrive 'estado') 'widget-state.json'
        Write-WidgetState -Path $caminho -Left -1250.5 -Top 84.25 -Pinned $true `
            -Expanded $false -ViewMode 'minimal' | Should Be $true

        $estado = Read-WidgetState -Path $caminho
        $estado.Left | Should Be -1250.5
        $estado.Top | Should Be 84.25
        $estado.Pinned | Should Be $true
        $estado.Expanded | Should Be $false
        $estado.ViewMode | Should Be 'minimal'
    }

    It 'usa a pasta de estado fora da instalacao' {
        Get-WidgetStatePath -BaseDir 'C:\Users\dev\AppData\Local' |
            Should Be 'C:\Users\dev\AppData\Local\kiro-eye-monitor\widget-state.json'
    }
}

Describe 'Controles do widget' {

    It 'alterna entre os tres modos de visualizacao' {
        $ui = New-TestWidgetUi

        Set-WidgetViewMode -Ui $ui -Mode 'minimal'
        $ui.MinimalPanel.Visibility | Should Be 'Visible'
        $ui.StandardPanel.Visibility | Should Be 'Collapsed'
        $ui.ExpandedDetails.Visibility | Should Be 'Collapsed'
        $ui.ExpandButton.IsChecked | Should Be $false

        Set-WidgetViewMode -Ui $ui -Mode 'normal'
        $ui.MinimalPanel.Visibility | Should Be 'Collapsed'
        $ui.StandardPanel.Visibility | Should Be 'Visible'
        $ui.ExpandedDetails.Visibility | Should Be 'Collapsed'
        $ui.ExpandButton.IsChecked | Should Be $false

        Set-WidgetViewMode -Ui $ui -Mode 'detailed'
        $ui.MinimalPanel.Visibility | Should Be 'Collapsed'
        $ui.StandardPanel.Visibility | Should Be 'Visible'
        $ui.ExpandedDetails.Visibility | Should Be 'Visible'
        $ui.ExpandButton.IsChecked | Should Be $true
    }

    It 'recusa modo de visualizacao desconhecido' {
        $ui = New-TestWidgetUi
        { Set-WidgetViewMode -Ui $ui -Mode 'gigante' } | Should Throw
    }

    It 'expande e recolhe a area de detalhes' {
        $ui = New-TestWidgetUi
        Set-WidgetExpanded -Ui $ui -Expanded $true
        $ui.ExpandedDetails.Visibility | Should Be 'Visible'
        $ui.ExpandButton.IsChecked | Should Be $true

        Set-WidgetExpanded -Ui $ui -Expanded $false
        $ui.ExpandedDetails.Visibility | Should Be 'Collapsed'
        $ui.ExpandButton.IsChecked | Should Be $false
    }

    It 'alterna o modo sempre no topo' {
        $ui = New-TestWidgetUi
        $janela = [pscustomobject]@{ Topmost = $false }
        Set-WidgetPinned -Window $janela -Ui $ui -Pinned $true
        $janela.Topmost | Should Be $true
        $ui.PinButton.IsChecked | Should Be $true
        $ui.MinimalPinButton.IsChecked | Should Be $true

        Set-WidgetPinned -Window $janela -Ui $ui -Pinned $false
        $janela.Topmost | Should Be $false
        $ui.PinButton.IsChecked | Should Be $false
        $ui.MinimalPinButton.IsChecked | Should Be $false
    }

    It 'restaura coordenadas finitas' {
        $janela = [pscustomobject]@{ Left = 0.0; Top = 0.0 }
        $estado = [pscustomobject]@{ Left = -800.5; Top = 120.25 }
        Restore-WidgetPosition -Window $janela -State $estado | Should Be $true
        $janela.Left | Should Be -800.5
        $janela.Top | Should Be 120.25
    }

    It 'recusa coordenada invalida' {
        $janela = [pscustomobject]@{ Left = 10.0; Top = 20.0 }
        $estado = [pscustomobject]@{ Left = [double]::NaN; Top = 120.0 }
        Restore-WidgetPosition -Window $janela -State $estado | Should Be $false
        $janela.Left | Should Be 10.0
        $janela.Top | Should Be 20.0
    }
}

Describe 'Instancia unica do widget' {

    It 'a segunda instancia sinaliza a primeira para aparecer' {
        $nome = 'KiroEyeMonitor.Tests.' + [guid]::NewGuid().ToString('N')
        $primeiro = $null
        $segundo = $null
        try {
            $primeiro = New-WidgetInstanceCoordinator -Name $nome
            $primeiro.IsPrimary | Should Be $true

            $segundo = New-WidgetInstanceCoordinator -Name $nome
            $segundo.IsPrimary | Should Be $false
            Test-WidgetShowRequested -Coordinator $primeiro | Should Be $true
        }
        finally {
            if (Get-Command Close-WidgetInstanceCoordinator -ErrorAction SilentlyContinue) {
                if ($null -ne $segundo) { Close-WidgetInstanceCoordinator -Coordinator $segundo }
                if ($null -ne $primeiro) { Close-WidgetInstanceCoordinator -Coordinator $primeiro }
            }
        }
    }
}
