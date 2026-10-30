# Estado e comportamento reutilizavel da janela de widget.
#
# Mantem preferencias fora da pasta de instalacao, que o install.sh recria, e
# concentra operacoes pequenas que podem ser testadas sem abrir a janela real.

Set-StrictMode -Version Latest

function Get-WidgetStatePath {
    <# Caminho persistente das preferencias do widget. #>
    param([Parameter(Mandatory)][string]$BaseDir)

    return Join-Path (Join-Path $BaseDir 'kiro-eye-monitor') 'widget-state.json'
}

function New-DefaultWidgetState {
    <# Estado seguro para primeira execucao ou arquivo ilegivel. #>
    return [pscustomobject]@{
        Left     = $null
        Top      = $null
        Pinned   = $false
        Expanded = $false
        ViewMode = 'normal'
    }
}

function Get-WidgetPropertyValue {
    <# Le propriedade opcional sem violar Set-StrictMode. #>
    param(
        [AllowNull()][object]$Source,
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][object]$Default = $null
    )

    if ($null -eq $Source) { return $Default }
    if ($Source.PSObject.Properties.Name -notcontains $Name) { return $Default }
    return $Source.$Name
}

function ConvertTo-FiniteWidgetCoordinate {
    <# Converte numero persistido; NaN, infinito e texto invalido viram ausencia. #>
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return $null }
    try {
        $numero = [Convert]::ToDouble($Value, [Globalization.CultureInfo]::InvariantCulture)
    }
    catch {
        return $null
    }
    if ([double]::IsNaN($numero) -or [double]::IsInfinity($numero)) { return $null }
    return $numero
}

function ConvertTo-WidgetBoolean {
    <# Aceita somente booleano JSON real; strings ambiguas caem para falso. #>
    param([AllowNull()][object]$Value)

    if ($Value -is [bool]) { return [bool]$Value }
    return $false
}

function Resolve-WidgetViewMode {
    <# Usa o modo novo quando valido e converte a flag legada quando necessario. #>
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory)][bool]$LegacyExpanded
    )

    $modo = [string]$Value
    if (@('minimal', 'normal', 'detailed') -contains $modo) { return $modo }
    if ($LegacyExpanded) { return 'detailed' }
    return 'normal'
}

function Read-WidgetState {
    <# Le preferencias sem permitir que arquivo ausente ou corrompido derrube o app. #>
    param([Parameter(Mandatory)][string]$Path)

    $estado = New-DefaultWidgetState
    if (-not (Test-Path -LiteralPath $Path)) { return $estado }
    try {
        $dados = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        $estado.Left = ConvertTo-FiniteWidgetCoordinate `
            -Value (Get-WidgetPropertyValue -Source $dados -Name 'left')
        $estado.Top = ConvertTo-FiniteWidgetCoordinate `
            -Value (Get-WidgetPropertyValue -Source $dados -Name 'top')
        $estado.Pinned = ConvertTo-WidgetBoolean `
            -Value (Get-WidgetPropertyValue -Source $dados -Name 'pinned')
        $legadoExpandido = ConvertTo-WidgetBoolean `
            -Value (Get-WidgetPropertyValue -Source $dados -Name 'expanded')
        $estado.ViewMode = Resolve-WidgetViewMode `
            -Value (Get-WidgetPropertyValue -Source $dados -Name 'view_mode') `
            -LegacyExpanded $legadoExpandido
        $estado.Expanded = $estado.ViewMode -eq 'detailed'
    }
    catch {
        return (New-DefaultWidgetState)
    }
    return $estado
}

function Write-WidgetState {
    <# Grava preferencias de forma atomica; devolve falso em vez de propagar falha. #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowNull()][object]$Left,
        [AllowNull()][object]$Top,
        [Parameter(Mandatory)][bool]$Pinned,
        [Parameter(Mandatory)][bool]$Expanded,
        [AllowEmptyString()][string]$ViewMode = ''
    )

    $temporario = "$Path.$PID.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $pasta = Split-Path -Parent $Path
        if (-not (Test-Path -LiteralPath $pasta)) {
            New-Item -ItemType Directory -Path $pasta -Force | Out-Null
        }
        $modoResolvido = Resolve-WidgetViewMode -Value $ViewMode -LegacyExpanded $Expanded
        $dados = [ordered]@{
            version   = 1
            left      = ConvertTo-FiniteWidgetCoordinate -Value $Left
            top       = ConvertTo-FiniteWidgetCoordinate -Value $Top
            pinned    = $Pinned
            expanded  = $modoResolvido -eq 'detailed'
            view_mode = $modoResolvido
        }
        $dados | ConvertTo-Json -Compress | Set-Content -LiteralPath $temporario -Encoding UTF8
        Move-Item -LiteralPath $temporario -Destination $Path -Force
        return $true
    }
    catch {
        if (Test-Path -LiteralPath $temporario) {
            Remove-Item -LiteralPath $temporario -Force -ErrorAction SilentlyContinue
        }
        return $false
    }
}

function Set-WidgetViewMode {
    <# Alterna entre faixa minima, cartao normal e cartao detalhado. #>
    param(
        [Parameter(Mandatory)][hashtable]$Ui,
        [Parameter(Mandatory)]
        [ValidateSet('minimal', 'normal', 'detailed')]
        [string]$Mode
    )

    $Ui.MinimalPanel.Visibility = if ($Mode -eq 'minimal') { 'Visible' } else { 'Collapsed' }
    $Ui.StandardPanel.Visibility = if ($Mode -eq 'minimal') { 'Collapsed' } else { 'Visible' }
    Set-WidgetExpanded -Ui $Ui -Expanded ($Mode -eq 'detailed')
}

function Set-WidgetExpanded {
    <# Sincroniza a area de detalhes e o botao que a controla. #>
    param(
        [Parameter(Mandatory)][hashtable]$Ui,
        [Parameter(Mandatory)][bool]$Expanded
    )

    $Ui.ExpandedDetails.Visibility = if ($Expanded) { 'Visible' } else { 'Collapsed' }
    $Ui.ExpandButton.IsChecked = $Expanded
    $Ui.ExpandButton.ToolTip = if ($Expanded) {
        'Ocultar projetos e analise'
    }
    else {
        'Mostrar projetos e analise'
    }
}

function Set-WidgetPinned {
    <# Alterna a janela entre z-order normal e sempre no topo. #>
    param(
        [Parameter(Mandatory)]$Window,
        [Parameter(Mandatory)][hashtable]$Ui,
        [Parameter(Mandatory)][bool]$Pinned
    )

    $Window.Topmost = $Pinned
    $dica = if ($Pinned) {
        'Deixar que outras janelas cubram o widget'
    }
    else {
        'Manter sobre outras janelas'
    }
    $Ui.PinButton.IsChecked = $Pinned
    $Ui.PinButton.ToolTip = $dica
    $Ui.MinimalPinButton.IsChecked = $Pinned
    $Ui.MinimalPinButton.ToolTip = $dica
}

function Restore-WidgetPosition {
    <# Aplica coordenadas apenas quando as duas sao numeros finitos. #>
    param(
        [Parameter(Mandatory)]$Window,
        [Parameter(Mandatory)][pscustomobject]$State
    )

    $left = ConvertTo-FiniteWidgetCoordinate `
        -Value (Get-WidgetPropertyValue -Source $State -Name 'Left')
    $top = ConvertTo-FiniteWidgetCoordinate `
        -Value (Get-WidgetPropertyValue -Source $State -Name 'Top')
    if ($null -eq $left -or $null -eq $top) { return $false }
    $Window.Left = $left
    $Window.Top = $top
    return $true
}

function New-WidgetInstanceCoordinator {
    <# Mutex impede duplicata; evento pede que a instancia primaria reapareca. #>
    param([Parameter(Mandatory)][string]$Name)

    $prefixo = if ($Name -match '^(Local|Global)\\') { $Name } else { "Local\$Name" }
    $criado = $false
    $mutex = New-Object System.Threading.Mutex($true, "$prefixo.Mutex", [ref]$criado)
    $evento = New-Object System.Threading.EventWaitHandle(
        $false,
        [System.Threading.EventResetMode]::AutoReset,
        "$prefixo.Show"
    )
    if (-not $criado) { $null = $evento.Set() }
    return [pscustomobject]@{
        IsPrimary = [bool]$criado
        Mutex     = $mutex
        ShowEvent = $evento
    }
}

function Test-WidgetShowRequested {
    <# Consulta sem bloquear se outra execucao pediu para mostrar o widget. #>
    param([Parameter(Mandatory)][pscustomobject]$Coordinator)

    return [bool]$Coordinator.ShowEvent.WaitOne(0)
}

function Close-WidgetInstanceCoordinator {
    <# Libera os handles nomeados; so a instancia primaria possui o mutex. #>
    param([Parameter(Mandatory)][pscustomobject]$Coordinator)

    if ($null -ne $Coordinator.ShowEvent) { $Coordinator.ShowEvent.Dispose() }
    if ($null -ne $Coordinator.Mutex) {
        if ($Coordinator.IsPrimary) {
            try { $Coordinator.Mutex.ReleaseMutex() }
            catch [System.ApplicationException] { }
        }
        $Coordinator.Mutex.Dispose()
    }
}
