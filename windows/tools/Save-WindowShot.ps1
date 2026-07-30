# Captura a janela do app em PNG usando PrintWindow.
#
# Auxiliar de verificacao manual: CopyFromScreen fotografa o que esta na frente,
# entao pegava o terminal quando a janela ficava atras. PrintWindow pede ao
# proprio Windows para redesenhar o conteudo da janela num bitmap.
#
# Uso: .\Save-WindowShot.ps1 -Destination C:\temp\janela.png
[CmdletBinding()]
param(
    [string]$WindowTitle = 'Consumo Kiro',
    [Parameter(Mandatory)][string]$Destination
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing, UIAutomationClient, UIAutomationTypes
Add-Type -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
public struct RECT { public int Left, Top, Right, Bottom; }
'@ -Name Shot -Namespace Native

$PW_RENDERFULLCONTENT = 2

function Get-AppWindowHandle {
    <# Handle nativo da janela com o titulo informado. #>
    param([Parameter(Mandatory)][string]$Title)
    $raiz = [System.Windows.Automation.AutomationElement]::RootElement
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::NameProperty, $Title)
    $janela = $raiz.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
    if ($null -eq $janela) { throw "janela '$Title' nao encontrada" }
    return [IntPtr]$janela.Current.NativeWindowHandle
}

$handle = Get-AppWindowHandle -Title $WindowTitle
$rect = New-Object Native.Shot+RECT
$null = [Native.Shot]::GetWindowRect($handle, [ref]$rect)
$largura = $rect.Right - $rect.Left
$altura = $rect.Bottom - $rect.Top

$bitmap = New-Object System.Drawing.Bitmap($largura, $altura)
$grafico = [System.Drawing.Graphics]::FromImage($bitmap)
$dc = $grafico.GetHdc()
$null = [Native.Shot]::PrintWindow($handle, $dc, $PW_RENDERFULLCONTENT)
$grafico.ReleaseHdc($dc)
$bitmap.Save($Destination, [System.Drawing.Imaging.ImageFormat]::Png)
$grafico.Dispose()
$bitmap.Dispose()

Write-Output "capturado ${largura}x${altura} em $Destination"
