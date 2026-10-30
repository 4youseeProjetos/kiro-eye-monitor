<#
    .SYNOPSIS
    Widget de acompanhamento do consumo de creditos Kiro.

    .DESCRIPTION
    Mostra o total da conta em um cartao compacto e expande projetos, dias e
    conversas sob demanda. Toda a leitura acontece no WSL; este processo apenas
    desenha o JSON, mantem a bandeja e persiste preferencias da janela.

    .EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Start-KiroEyeMonitor.ps1

    .EXAMPLE
    .\Start-KiroEyeMonitor.ps1 -Distro Ubuntu-24.04 -BridgePath /home/dev/app/scripts/collect.sh
#>
[CmdletBinding()]
param(
    [string]$Distro = '',
    [string]$BridgePath = '',
    [ValidateRange(1, 120)][int]$RefreshMinutes = 5,
    [ValidateRange(1, 100)][int]$WarnPercent = 75,
    [ValidateRange(1, 100)][int]$CriticalPercent = 90,
    [ValidateRange(1, 50)][int]$TopProjects = 8,
    [ValidateRange(1, 62)][int]$TopDays = 5,
    [ValidateRange(1, 100)][int]$TopChats = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

. "$PSScriptRoot\lib\WslPath.ps1"
. "$PSScriptRoot\lib\WslDistro.ps1"
. "$PSScriptRoot\lib\KiroCollector.ps1"
. "$PSScriptRoot\lib\UsageFormat.ps1"
. "$PSScriptRoot\lib\UsageView.ps1"
. "$PSScriptRoot\lib\WidgetWindow.ps1"
. "$PSScriptRoot\lib\BackgroundCall.ps1"
. "$PSScriptRoot\lib\WindowLog.ps1"
. "$PSScriptRoot\lib\ThresholdAlert.ps1"

$script:PollIntervalMs = 250
$script:ControlNames = @(
    'WidgetFrame', 'StandardPanel', 'MinimalPanel', 'DragHandle', 'MinimalDragHandle',
    'AccountPanel', 'UsagePercentText', 'ExpandedDetails',
    'MinimalPercentText', 'MinimalCreditsText', 'MinimalUsageBar',
    'MinimizeButton', 'MinimalExpandButton', 'MinimalPinButton', 'MinimalCloseButton',
    'PinButton', 'ExpandButton', 'CloseButton',
    'ErrorPanel', 'ErrorText', 'ErrorHintText',
    'PlanText', 'HeadlineText', 'UsageBar', 'PercentText', 'BurnText', 'ProjectionText',
    'CliTotalText', 'ProjectList', 'UnattributedText',
    'MainTabs', 'SummaryTab', 'AnalysisTab',
    'DaySummaryText', 'DayList', 'ChatSummaryText', 'ChatList',
    'StatusText', 'RefreshButton'
)

# Roda em runspace proprio: recebe so primitivos e devolve o texto cru.
$script:TrabalhoDeColeta = {
    param([string]$Distro, [string]$BridgePath)
    & wsl.exe @('-d', $Distro, '--', $BridgePath) 2>&1
}

function Start-Collection {
    <# Dispara uma coleta se nenhuma estiver em andamento. #>
    if ($null -ne $script:ColetaEmCurso) { return }
    $script:Ui.StatusText.Text = 'Coletando...'
    $script:ColetaEmCurso = Start-BackgroundCall -Work $script:TrabalhoDeColeta `
        -ArgumentList @($script:Distro, $script:BridgeResolvido)
}

function Write-CollectionFailure {
    <# Registra a falha bruta e devolve o caminho do log, ou vazio. #>
    param([AllowNull()][pscustomobject]$Report, [AllowEmptyString()][string]$Raw)

    if (-not (Test-KiroCollectorFailure -Report $Report)) { return '' }
    $contexto = @{
        distro = $script:Distro
        ponte  = $script:BridgeResolvido
        log_wsl = if ($Report.PSObject.Properties.Name -contains 'log_path') { $Report.log_path } else { '' }
    }
    return (Write-WindowLogEntry -Path $script:LogPath -Message ([string]$Report.error) `
            -Detail $Raw -Context $contexto)
}

function Complete-Collection {
    <# Colhe a coleta pendente, se terminou, e redesenha o widget. #>
    if ($null -eq $script:ColetaEmCurso) { return }
    if (-not (Test-BackgroundCallCompleted -Call $script:ColetaEmCurso)) { return }
    $bruto = Receive-BackgroundCall -Call $script:ColetaEmCurso
    $script:ColetaEmCurso = $null
    $relatorio = ConvertFrom-KiroCollectorOutput -Raw $bruto
    $null = Write-CollectionFailure -Report $relatorio -Raw ([string]$bruto)
    $nivel = Show-UsageReport -Ui $script:Ui -Report $relatorio `
        -WarnPercent $script:WarnPercent -CriticalPercent $script:CriticalPercent `
        -TopProjects $script:TopProjects -TopDays $script:TopDays -TopChats $script:TopChats `
        -WindowVersion $script:Versao -LogPath $script:LogPath
    Send-ThresholdAlert -Level $nivel -Report $relatorio
}

function Send-ThresholdAlert {
    <# Avisa na bandeja quando entra em falha ou o consumo piora de faixa. #>
    param([Parameter(Mandatory)][string]$Level, [Parameter(Mandatory)][pscustomobject]$Report)

    $anterior = $script:UltimoNivel
    $script:UltimoNivel = $Level
    try {
        if (Test-FailureAlert -Previous $anterior -Current $Level) {
            $aviso = New-FailureAlertContent -Report $Report -LogPath $script:LogPath
            $icone = [System.Windows.Forms.ToolTipIcon]::Error
        }
        elseif (Test-ThresholdWorsened -Previous $anterior -Current $Level) {
            $aviso = New-ThresholdAlertContent -Report $Report
            $icone = [System.Windows.Forms.ToolTipIcon]::Warning
        }
        else { return }
        $script:Tray.ShowBalloonTip(10000, $aviso.Title, $aviso.Message, $icone)
    }
    catch {
        $null = Write-WindowLogEntry -Path $script:LogPath `
            -Message "falha ao avisar na bandeja: $($_.Exception.Message)" `
            -Context @{ nivel = $Level }
    }
}

function Save-CurrentWidgetState {
    <# Persiste a posicao, o modo e a fixacao; falha de disco nao afeta a janela. #>
    return Write-WidgetState -Path $script:StatePath `
        -Left $script:MainWindow.Left -Top $script:MainWindow.Top `
        -Pinned ([bool]$script:Ui.PinButton.IsChecked) `
        -Expanded ($script:ViewMode -eq 'detailed') -ViewMode $script:ViewMode
}

function Get-VirtualScreenBounds {
    <# Retangulo virtual em unidades usadas pelo WPF. #>
    return [pscustomobject]@{
        Left   = [System.Windows.SystemParameters]::VirtualScreenLeft
        Top    = [System.Windows.SystemParameters]::VirtualScreenTop
        Right  = [System.Windows.SystemParameters]::VirtualScreenLeft +
                 [System.Windows.SystemParameters]::VirtualScreenWidth
        Bottom = [System.Windows.SystemParameters]::VirtualScreenTop +
                 [System.Windows.SystemParameters]::VirtualScreenHeight
    }
}

function Limit-MainWindowToVisibleArea {
    <# Preserva monitores secundarios e recupera coordenada de monitor removido. #>
    Limit-WindowToBounds -Window $script:MainWindow -Area (Get-VirtualScreenBounds)
}

function Sync-TrayViewMode {
    <# Marca na bandeja exatamente o modo ativo. #>
    if ($null -ne $script:TrayMinimalItem) {
        $script:TrayMinimalItem.Checked = $script:ViewMode -eq 'minimal'
        $script:TrayNormalItem.Checked = $script:ViewMode -eq 'normal'
        $script:TrayDetailedItem.Checked = $script:ViewMode -eq 'detailed'
    }
}

function Set-CurrentWidgetViewMode {
    <# Aplica, mede, limita e persiste uma transicao de visualizacao. #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('minimal', 'normal', 'detailed')]
        [string]$Mode
    )

    $script:ViewMode = $Mode
    Set-WidgetViewMode -Ui $script:Ui -Mode $Mode
    $script:MainWindow.UpdateLayout()
    Sync-TrayViewMode
    $null = Save-CurrentWidgetState
}

function Set-CurrentWidgetPinned {
    <# Sincroniza os dois botoes, a bandeja, o z-order e o estado persistido. #>
    param([Parameter(Mandatory)][bool]$Pinned)

    Set-WidgetPinned -Window $script:MainWindow -Ui $script:Ui -Pinned $Pinned
    if ($null -ne $script:TrayPinItem) { $script:TrayPinItem.Checked = $Pinned }
    $null = Save-CurrentWidgetState
}

function Show-MainWindow {
    <# Mostra e ativa o widget, inclusive depois de ocultado pela tecla X. #>
    if (-not $script:MainWindow.IsVisible) { $script:MainWindow.Show() }
    if ($script:MainWindow.WindowState -eq [System.Windows.WindowState]::Minimized) {
        $script:MainWindow.WindowState = [System.Windows.WindowState]::Normal
    }
    $null = $script:MainWindow.Activate()
}

function Toggle-MainWindow {
    <# Alterna a visibilidade sem interromper timers e alertas. #>
    if ($script:MainWindow.IsVisible) {
        $null = Save-CurrentWidgetState
        $script:MainWindow.Hide()
    }
    else {
        Show-MainWindow
    }
}

function Remove-TrayIcon {
    <# Libera icone e menu de contexto uma unica vez. #>
    if ($null -eq $script:Tray) { return }
    $script:Tray.Visible = $false
    if ($null -ne $script:Tray.ContextMenuStrip) {
        $script:Tray.ContextMenuStrip.Dispose()
    }
    $script:Tray.Dispose()
    $script:Tray = $null
    $script:TrayPinItem = $null
    $script:TrayMinimalItem = $null
    $script:TrayNormalItem = $null
    $script:TrayDetailedItem = $null
}

function Stop-WidgetApplication {
    <# Encerra explicitamente; fechar pelo cartao apenas oculta. #>
    if ($script:Exiting) { return }
    $script:Exiting = $true
    $null = Save-CurrentWidgetState
    if ($script:MainWindow.IsVisible) { $script:MainWindow.Close() }
    else { $script:App.Shutdown() }
}

function New-TrayIcon {
    <# Icone, alertas e comandos de ciclo de vida do widget. #>
    $tray = New-Object System.Windows.Forms.NotifyIcon
    $tray.Icon = if (Test-Path -LiteralPath $script:IconPath) {
        New-Object System.Drawing.Icon($script:IconPath)
    }
    else {
        [System.Drawing.SystemIcons]::Information
    }
    $tray.Text = 'kiro-eye-monitor'

    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $mostrar = $menu.Items.Add('Mostrar/ocultar')
    $atualizar = $menu.Items.Add('Atualizar agora')
    $null = $menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

    $script:TrayMinimalItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $script:TrayMinimalItem.Text = 'Visualizacao minima'
    $null = $menu.Items.Add($script:TrayMinimalItem)
    $script:TrayNormalItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $script:TrayNormalItem.Text = 'Visualizacao normal'
    $null = $menu.Items.Add($script:TrayNormalItem)
    $script:TrayDetailedItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $script:TrayDetailedItem.Text = 'Visualizacao detalhada'
    $null = $menu.Items.Add($script:TrayDetailedItem)

    $script:TrayPinItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $script:TrayPinItem.Text = 'Sempre no topo'
    $script:TrayPinItem.CheckOnClick = $true
    $script:TrayPinItem.Checked = [bool]$script:Ui.PinButton.IsChecked
    $null = $menu.Items.Add($script:TrayPinItem)
    $null = $menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    $sair = $menu.Items.Add('Sair')

    $mostrar.add_Click({ Toggle-MainWindow })
    $atualizar.add_Click({ Start-Collection })
    $script:TrayMinimalItem.add_Click({ Set-CurrentWidgetViewMode -Mode 'minimal' })
    $script:TrayNormalItem.add_Click({ Set-CurrentWidgetViewMode -Mode 'normal' })
    $script:TrayDetailedItem.add_Click({ Set-CurrentWidgetViewMode -Mode 'detailed' })
    $script:TrayPinItem.add_Click({
            Set-CurrentWidgetPinned -Pinned ([bool]$script:TrayPinItem.Checked)
        })
    $sair.add_Click({ Stop-WidgetApplication })
    Sync-TrayViewMode

    $tray.ContextMenuStrip = $menu
    $tray.add_DoubleClick({ Show-MainWindow })
    $tray.Visible = $true
    return $tray
}

function Register-WindowEvent {
    <# Liga arraste, botoes, posicionamento, estado e encerramento. #>
    $script:MainWindow.add_Loaded({
            if ($script:RestoredPosition) { Limit-MainWindowToVisibleArea }
            else { Set-WindowInsideWorkArea -Window $script:MainWindow }
        })
    $script:MainWindow.add_SizeChanged({
            param($janela, $evento)
            Move-WindowKeepingBottom -Window $janela `
                -PreviousHeight $evento.PreviousSize.Height -NewHeight $evento.NewSize.Height
            Limit-MainWindowToVisibleArea
        })
    $arrastar = {
        param($origem, $evento)
        if ($evento.ChangedButton -ne [System.Windows.Input.MouseButton]::Left) { return }
        try {
            $script:MainWindow.DragMove()
            $null = Save-CurrentWidgetState
        }
        catch {
            # DragMove falha se o botao for liberado antes de o evento chegar.
        }
    }
    $script:Ui.DragHandle.add_MouseLeftButtonDown($arrastar)
    $script:Ui.MinimalDragHandle.add_MouseLeftButtonDown($arrastar)
    $script:Ui.MinimizeButton.add_Click({ Set-CurrentWidgetViewMode -Mode 'minimal' })
    $script:Ui.MinimalExpandButton.add_Click({ Set-CurrentWidgetViewMode -Mode 'normal' })
    $script:Ui.ExpandButton.add_Click({
            $modo = if ([bool]$script:Ui.ExpandButton.IsChecked) { 'detailed' } else { 'normal' }
            Set-CurrentWidgetViewMode -Mode $modo
        })
    $script:Ui.PinButton.add_Click({
            Set-CurrentWidgetPinned -Pinned ([bool]$script:Ui.PinButton.IsChecked)
        })
    $script:Ui.MinimalPinButton.add_Click({
            Set-CurrentWidgetPinned -Pinned ([bool]$script:Ui.MinimalPinButton.IsChecked)
        })
    $script:Ui.CloseButton.add_Click({ Toggle-MainWindow })
    $script:Ui.MinimalCloseButton.add_Click({ Toggle-MainWindow })
    $script:Ui.RefreshButton.add_Click({ Start-Collection })
    $script:MainWindow.add_Closed({
            $null = Save-CurrentWidgetState
            Remove-TrayIcon
            if ($null -ne $script:App) { $script:App.Shutdown() }
        })
}

function Start-Timers {
    <# Um timer colhe a coleta e o sinal; o outro agenda a proxima coleta. #>
    $poll = New-Object System.Windows.Threading.DispatcherTimer
    $poll.Interval = [timespan]::FromMilliseconds($script:PollIntervalMs)
    $poll.add_Tick({
            Complete-Collection
            if (Test-WidgetShowRequested -Coordinator $script:InstanceCoordinator) {
                Show-MainWindow
            }
        })
    $poll.Start()

    $auto = New-Object System.Windows.Threading.DispatcherTimer
    $auto.Interval = [timespan]::FromMinutes($script:RefreshMinutes)
    $auto.add_Tick({ Start-Collection })
    $auto.Start()
    return @($poll, $auto)
}

function Resolve-DistroOrAlert {
    <# Resolve a distro e mostra uma caixa de dialogo quando nao puder. #>
    param([AllowEmptyString()][string]$Requested)

    $inventario = Get-WslDistroInventory
    try {
        return Resolve-WslDistroName -Requested $Requested `
            -Installed $inventario.Names -Default $inventario.Default
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message, 'kiro-eye-monitor',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        exit 1
    }
}

$script:InstanceCoordinator = New-WidgetInstanceCoordinator -Name 'KiroEyeMonitor.Widget'
if (-not $script:InstanceCoordinator.IsPrimary) {
    Close-WidgetInstanceCoordinator -Coordinator $script:InstanceCoordinator
    exit 0
}

$script:Timers = @()
$script:Tray = $null
$script:TrayPinItem = $null
$script:TrayMinimalItem = $null
$script:TrayNormalItem = $null
$script:TrayDetailedItem = $null
$script:App = $null
$script:Exiting = $false

try {
    $script:Distro = Resolve-DistroOrAlert -Requested $Distro
    $null = Set-KiroCollectorEncoding
    $script:RefreshMinutes = $RefreshMinutes
    $script:WarnPercent = $WarnPercent
    $script:CriticalPercent = $CriticalPercent
    $script:TopProjects = $TopProjects
    $script:TopDays = $TopDays
    $script:TopChats = $TopChats
    $script:ColetaEmCurso = $null
    $script:UltimoNivel = 'ok'
    $script:BridgeResolvido = Resolve-BridgePath -Informado $BridgePath -ScriptRoot $PSScriptRoot
    $script:IconPath = Join-Path $PSScriptRoot 'assets\eye.ico'
    $script:Versao = Get-KiroInstalledVersion -Path (Join-Path $PSScriptRoot 'VERSION')
    $script:LogPath = Get-WindowLogPath -BaseDir $env:LOCALAPPDATA
    $script:StatePath = Get-WidgetStatePath -BaseDir $env:LOCALAPPDATA

    $script:MainWindow = New-UsageWindow -XamlPath (Join-Path $PSScriptRoot 'MainWindow.xaml')
    $null = Set-WindowIcon -Window $script:MainWindow -IconPath $script:IconPath
    $script:Ui = Get-WindowControl -Window $script:MainWindow -Names $script:ControlNames

    $estado = Read-WidgetState -Path $script:StatePath
    $script:ViewMode = [string]$estado.ViewMode
    Set-WidgetViewMode -Ui $script:Ui -Mode $script:ViewMode
    Set-WidgetPinned -Window $script:MainWindow -Ui $script:Ui -Pinned ([bool]$estado.Pinned)
    $script:RestoredPosition = Restore-WidgetPosition -Window $script:MainWindow -State $estado

    $script:App = New-Object System.Windows.Application
    $script:App.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown
    $script:Tray = New-TrayIcon
    Register-WindowEvent
    $script:Timers = Start-Timers
    Start-Collection
    $null = $script:App.Run($script:MainWindow)
}
finally {
    foreach ($timer in $script:Timers) { $timer.Stop() }
    Remove-TrayIcon
    Close-WidgetInstanceCoordinator -Coordinator $script:InstanceCoordinator
}
