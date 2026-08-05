<#
    .SYNOPSIS
    Janela de acompanhamento do consumo de creditos Kiro.

    .DESCRIPTION
    Mostra o total da conta (que ja soma Kiro IDE, kiro-cli, web e mobile, pois
    o pool de credito e unico) com o detalhamento por projeto do kiro-cli desta
    maquina, e uma aba de analise com o consumo por dia e por conversa. Toda a
    leitura acontece no WSL; aqui so se desenha o JSON recebido.

    .EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Start-KiroEyeMonitor.ps1

    .EXAMPLE
    .\Start-KiroEyeMonitor.ps1 -Distro Ubuntu-24.04 -BridgePath /home/dev/app/scripts/collect.sh
#>
[CmdletBinding()]
param(
    # Vazio significa "a distro padrao do WSL desta maquina". Nao ha nome
    # cravado: o nome varia entre desenvolvedores (Ubuntu, Ubuntu-24.04, Debian)
    # e o wsl.exe exige o nome exato.
    [string]$Distro = '',
    [string]$BridgePath = '',
    [ValidateRange(1, 120)][int]$RefreshMinutes = 5,
    [ValidateRange(1, 100)][int]$WarnPercent = 75,
    [ValidateRange(1, 100)][int]$CriticalPercent = 90,
    [ValidateRange(1, 50)][int]$TopProjects = 8,
    # A aba de analise lista os dias mais recentes com consumo e as conversas
    # mais caras do ciclo. Cinco dias cobrem a semana de trabalho; a media e o
    # pico exibidos continuam sendo do ciclo inteiro.
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
. "$PSScriptRoot\lib\BackgroundCall.ps1"
. "$PSScriptRoot\lib\WindowLog.ps1"
. "$PSScriptRoot\lib\ThresholdAlert.ps1"

$script:PollIntervalMs = 250
$script:ControlNames = @(
    'ErrorPanel', 'ErrorText', 'ErrorHintText',
    'PlanText', 'HeadlineText', 'UsageBar', 'PercentText', 'BurnText', 'ProjectionText',
    'CliTotalText', 'ProjectList', 'UnattributedText',
    'MainTabs', 'SummaryTab', 'AnalysisTab',
    'DaySummaryText', 'DayList', 'ChatSummaryText', 'ChatList',
    'StatusText', 'RefreshButton'
)

# Roda em runspace proprio: recebe so primitivos e devolve o texto cru.
#
# Sempre com detalhamento: varrer as sessoes custa ~36 ms contra ~1,8 s do
# kiro-cli /usage na mesma coleta, e as duas abas dependem dele. O
# --account-only continua existindo na ponte, para depuracao pela linha de
# comando.
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
    <# Registra a falha bruta e devolve o caminho do log, ou '' se nao houve falha. #>
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
    <# Colhe a coleta pendente, se ja terminou, e redesenha a janela. #>
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
    <# Avisa na bandeja quando entra em falha ou quando o consumo piora de faixa. #>
    param([Parameter(Mandatory)][string]$Level, [Parameter(Mandatory)][pscustomobject]$Report)

    $anterior = $script:UltimoNivel
    $script:UltimoNivel = $Level
    # Aviso e acessorio: relatorio com campo faltando nao pode fechar a janela,
    # que e a informacao principal. A falha vai para o log.
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

function New-TrayIcon {
    <# Icone de bandeja usado para os avisos de limiar. #>
    $tray = New-Object System.Windows.Forms.NotifyIcon
    $tray.Icon = if (Test-Path -LiteralPath $script:IconPath) {
        New-Object System.Drawing.Icon($script:IconPath)
    }
    else {
        [System.Drawing.SystemIcons]::Information
    }
    $tray.Text = 'kiro-eye-monitor'
    $tray.Visible = $true
    $tray.add_DoubleClick({ $script:MainWindow.Activate() })
    return $tray
}

function Register-WindowEvent {
    <# Liga botao, posicionamento da janela e limpeza da bandeja. #>
    $script:MainWindow.add_Loaded({ Set-WindowInsideWorkArea -Window $script:MainWindow })
    # Trocar de aba muda a altura (SizeToContent="Height"); sem reancorar, a aba
    # de analise cresce para fora da area util.
    $script:MainWindow.add_SizeChanged({ Set-WindowInsideWorkArea -Window $script:MainWindow })
    $script:Ui.RefreshButton.add_Click({ Start-Collection })
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

function Resolve-DistroOrAlert {
    <#
        .SYNOPSIS
        Resolve a distro e, se nao der, avisa em caixa de dialogo.
        .DESCRIPTION
        A janela abre com console oculto, entao erro em texto nao chega ao
        usuario: sem a caixa de dialogo, o duplo clique no atalho pareceria
        nao fazer nada.
        .EXAMPLE
        $distro = Resolve-DistroOrAlert -Requested $Distro
    #>
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

$script:Distro = Resolve-DistroOrAlert -Requested $Distro
# Antes de qualquer coleta: a saida do coletor e UTF-8 e traz titulo de conversa.
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
# Gravado pelo install.sh ao copiar a janela; vazio quando a copia foi manual.
$script:Versao = Get-KiroInstalledVersion -Path (Join-Path $PSScriptRoot 'VERSION')
$script:LogPath = Get-WindowLogPath -BaseDir $env:LOCALAPPDATA

$script:MainWindow = New-UsageWindow -XamlPath (Join-Path $PSScriptRoot 'MainWindow.xaml')
$null = Set-WindowIcon -Window $script:MainWindow -IconPath $script:IconPath
$script:Ui = Get-WindowControl -Window $script:MainWindow -Names $script:ControlNames
$script:Tray = New-TrayIcon
Register-WindowEvent
$script:Timers = Start-Timers
Start-Collection
$null = $script:MainWindow.ShowDialog()
foreach ($timer in $script:Timers) { $timer.Stop() }
