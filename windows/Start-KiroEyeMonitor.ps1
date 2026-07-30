<#
    .SYNOPSIS
    Janela de acompanhamento do consumo de creditos Kiro.

    .DESCRIPTION
    Mostra o total da conta (que ja soma Kiro IDE, kiro-cli, web e mobile, pois
    o pool de credito e unico) e, sob a caixa de selecao, o detalhamento por
    projeto do kiro-cli desta maquina. Toda a leitura acontece no WSL; aqui so
    se desenha o JSON recebido.

    .EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Start-KiroEyeMonitor.ps1

    .EXAMPLE
    .\Start-KiroEyeMonitor.ps1 -Distro Ubuntu -BridgePath /home/dev/app/scripts/collect.sh
#>
[CmdletBinding()]
param(
    [string]$Distro = 'Ubuntu',
    [string]$BridgePath = '',
    [ValidateRange(1, 120)][int]$RefreshMinutes = 5,
    [ValidateRange(1, 100)][int]$WarnPercent = 75,
    [ValidateRange(1, 100)][int]$CriticalPercent = 90,
    [ValidateRange(1, 50)][int]$TopProjects = 8
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

. "$PSScriptRoot\lib\WslPath.ps1"
. "$PSScriptRoot\lib\KiroCollector.ps1"
. "$PSScriptRoot\lib\UsageFormat.ps1"
. "$PSScriptRoot\lib\UsageView.ps1"
. "$PSScriptRoot\lib\BackgroundCall.ps1"

$script:PollIntervalMs = 250
$script:ControlNames = @(
    'PlanText', 'HeadlineText', 'UsageBar', 'PercentText', 'BurnText', 'ProjectionText',
    'DetailToggle', 'DetailPanel', 'CliTotalText', 'ProjectList', 'UnattributedText',
    'StatusText', 'RefreshButton'
)

# Roda em runspace proprio: recebe so primitivos e devolve o texto cru.
$script:TrabalhoDeColeta = {
    param([string]$Distro, [string]$BridgePath, [bool]$AccountOnly)
    $wslArgs = @('-d', $Distro, '--', $BridgePath)
    if ($AccountOnly) { $wslArgs += '--account-only' }
    & wsl.exe @wslArgs 2>&1
}

function Resolve-BridgePath {
    <# Caminho da ponte dentro do WSL, derivado da pasta do script se omitido. #>
    param([string]$Informado, [Parameter(Mandatory)][string]$ScriptRoot)

    if (-not [string]::IsNullOrWhiteSpace($Informado)) { return $Informado }
    $projeto = Split-Path -Parent $ScriptRoot
    return (Convert-WindowsPathToWslPath -Path $projeto).TrimEnd('/') + '/scripts/collect.sh'
}

function Start-Collection {
    <# Dispara uma coleta se nenhuma estiver em andamento. #>
    if ($null -ne $script:ColetaEmCurso) { return }
    $somenteConta = -not $script:Ui.DetailToggle.IsChecked
    $script:Ui.StatusText.Text = 'Coletando...'
    $script:ColetaEmCurso = Start-BackgroundCall -Work $script:TrabalhoDeColeta `
        -ArgumentList @($script:Distro, $script:BridgeResolvido, [bool]$somenteConta)
}

function Complete-Collection {
    <# Colhe a coleta pendente, se ja terminou, e redesenha a janela. #>
    if ($null -eq $script:ColetaEmCurso) { return }
    if (-not (Test-BackgroundCallCompleted -Call $script:ColetaEmCurso)) { return }
    $bruto = Receive-BackgroundCall -Call $script:ColetaEmCurso
    $script:ColetaEmCurso = $null
    $relatorio = ConvertFrom-KiroCollectorOutput -Raw $bruto
    $nivel = Show-UsageReport -Ui $script:Ui -Report $relatorio `
        -WarnPercent $script:WarnPercent -CriticalPercent $script:CriticalPercent `
        -TopProjects $script:TopProjects
    Send-ThresholdAlert -Level $nivel -Report $relatorio
}

function Send-ThresholdAlert {
    <# Avisa na bandeja apenas quando o nivel piora, para nao repetir balao. #>
    param([Parameter(Mandatory)][string]$Level, [Parameter(Mandatory)][pscustomobject]$Report)

    $anterior = $script:UltimoNivel
    $script:UltimoNivel = $Level
    if ($Level -eq 'ok' -or $Level -eq 'falha' -or $Level -eq $anterior) { return }
    $script:Tray.ShowBalloonTip(
        10000,
        "Consumo Kiro em $($Report.account.used_percent)%",
        (Format-KiroProjection -BurnRate $Report.burn_rate -Account $Report.account),
        [System.Windows.Forms.ToolTipIcon]::Warning
    )
}

function New-TrayIcon {
    <# Icone de bandeja usado para os avisos de limiar. #>
    $tray = New-Object System.Windows.Forms.NotifyIcon
    $tray.Icon = if (Test-Path -LiteralPath $script:IconPath) {
        New-Object System.Drawing.Icon($script:IconPath)
    }
    else {
        [System.Drawing.SystemIcons]::Information
    }
    $tray.Text = 'Consumo Kiro'
    $tray.Visible = $true
    $tray.add_DoubleClick({ $script:MainWindow.Activate() })
    return $tray
}

function Register-WindowEvent {
    <# Liga botao, caixa de selecao, posicionamento e limpeza da bandeja. #>
    $script:MainWindow.add_Loaded({ Set-WindowInsideWorkArea -Window $script:MainWindow })
    $script:Ui.RefreshButton.add_Click({ Start-Collection })
    $script:Ui.DetailToggle.add_Checked({
            $script:Ui.DetailPanel.Visibility = 'Visible'
            Start-Collection
        })
    $script:Ui.DetailToggle.add_Unchecked({ $script:Ui.DetailPanel.Visibility = 'Collapsed' })
    $script:MainWindow.add_Closed({
            $script:Tray.Visible = $false
            $script:Tray.Dispose()
        })
}

function Start-Timers {
    <# Um temporizador colhe a coleta; o outro agenda a proxima. #>
    $poll = New-Object System.Windows.Threading.DispatcherTimer
    $poll.Interval = [timespan]::FromMilliseconds($script:PollIntervalMs)
    $poll.add_Tick({ Complete-Collection })
    $poll.Start()

    $auto = New-Object System.Windows.Threading.DispatcherTimer
    $auto.Interval = [timespan]::FromMinutes($script:RefreshMinutes)
    $auto.add_Tick({ Start-Collection })
    $auto.Start()
    return @($poll, $auto)
}

$script:Distro = $Distro
$script:RefreshMinutes = $RefreshMinutes
$script:WarnPercent = $WarnPercent
$script:CriticalPercent = $CriticalPercent
$script:TopProjects = $TopProjects
$script:ColetaEmCurso = $null
$script:UltimoNivel = 'ok'
$script:BridgeResolvido = Resolve-BridgePath -Informado $BridgePath -ScriptRoot $PSScriptRoot
$script:IconPath = Join-Path $PSScriptRoot 'assets\eye.ico'

$script:MainWindow = New-UsageWindow -XamlPath (Join-Path $PSScriptRoot 'MainWindow.xaml')
$null = Set-WindowIcon -Window $script:MainWindow -IconPath $script:IconPath
$script:Ui = Get-WindowControl -Window $script:MainWindow -Names $script:ControlNames
$script:Tray = New-TrayIcon
Register-WindowEvent
$script:Timers = Start-Timers
Start-Collection
$null = $script:MainWindow.ShowDialog()
foreach ($timer in $script:Timers) { $timer.Stop() }
