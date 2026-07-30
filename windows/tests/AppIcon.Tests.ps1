# Testes do icone do app (Pester 3).
#
# O icone e gerado por src/kiro_eye_monitor/eye_icon.py e copiado em assets/eye.ico.

Add-Type -AssemblyName PresentationFramework

. "$PSScriptRoot\..\lib\KiroCollector.ps1"
. "$PSScriptRoot\..\lib\UsageFormat.ps1"
. "$PSScriptRoot\..\lib\UsageView.ps1"

$script:Raiz = Split-Path -Parent $PSScriptRoot
$script:XamlPath = Join-Path $script:Raiz 'MainWindow.xaml'
$script:IconPath = Join-Path $script:Raiz 'assets\eye.ico'

Describe 'Set-WindowIcon' {

    It 'o arquivo de icone acompanha a instalacao' {
        Test-Path -LiteralPath $script:IconPath | Should Be $true
    }

    It 'aplica o icone na janela' {
        $janela = New-UsageWindow -XamlPath $script:XamlPath
        Set-WindowIcon -Window $janela -IconPath $script:IconPath | Should Be $true
        $janela.Icon | Should Not BeNullOrEmpty
    }

    It 'o icone carregado e quadrado' {
        $janela = New-UsageWindow -XamlPath $script:XamlPath
        $null = Set-WindowIcon -Window $janela -IconPath $script:IconPath
        $janela.Icon.PixelWidth | Should Be $janela.Icon.PixelHeight
    }

    It 'usa o maior frame do arquivo, nao o de 16 pixels' {
        $maior = Get-LargestIconFrame -IconPath $script:IconPath
        $maior.PixelWidth | Should BeGreaterThan 16
    }

    It 'o centro do olho e azul' {
        $frame = Get-LargestIconFrame -IconPath $script:IconPath
        $largura = $frame.PixelWidth
        $recorte = New-Object System.Windows.Media.Imaging.CroppedBitmap(
            $frame, (New-Object System.Windows.Int32Rect([int]($largura / 2), [int]($largura / 2), 1, 1)))
        $pixel = New-Object 'byte[]' 4
        $recorte.CopyPixels($pixel, 4, 0)
        # BGRA: azul dominante sobre vermelho.
        $pixel[0] | Should BeGreaterThan $pixel[2]
        $pixel[0] | Should BeGreaterThan 200
    }

    It 'ausencia do arquivo nao derruba a janela' {
        $janela = New-UsageWindow -XamlPath $script:XamlPath
        Set-WindowIcon -Window $janela -IconPath 'C:\nao\existe\eye.ico' | Should Be $false
    }

    It 'o icone tambem carrega como icone de bandeja' {
        Add-Type -AssemblyName System.Drawing
        $icone = New-Object System.Drawing.Icon($script:IconPath)
        $icone.Width | Should BeGreaterThan 0
        $icone.Dispose()
    }
}
