<#
    .SYNOPSIS
    Gera o lancador e os atalhos da janela de consumo Kiro.

    .DESCRIPTION
    Escreve Start-KiroEyeMonitor.cmd na pasta de instalacao e, se pedido, atalhos na
    area de trabalho e na pasta Inicializar. Os atalhos apontam direto para o
    powershell.exe, e nao para o .cmd, para nao piscar janela de console, e usam
    o icone do olho.

    Nao copia arquivos: quem copia e o install.sh, do lado do WSL. O PowerShell
    5.1 travava ao executar scripts a partir de \\wsl.localhost, por isso a
    instalacao comeca no WSL e este script ja roda de disco local.

    .EXAMPLE
    .\New-KiroEyeMonitorLauncher.ps1 -BridgePath /home/dev/app/scripts/collect.sh -Distro Ubuntu -AddToDesktop
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BridgePath,
    [Parameter(Mandatory)][string]$Distro,
    [string]$InstallDir = $PSScriptRoot,
    [switch]$AddToDesktop,
    [switch]$AddToStartup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:LauncherName = 'Start-KiroEyeMonitor.cmd'
$script:ShortcutName = 'kiro-eye-monitor.lnk'
$script:MinimizedWindow = 7

function Get-WindowArgument {
    <# Argumentos do powershell.exe que abrem a janela sem console. #>
    param(
        [Parameter(Mandatory)][string]$InstallDir,
        [Parameter(Mandatory)][string]$Distro,
        [Parameter(Mandatory)][string]$BridgePath
    )
    $janela = Join-Path $InstallDir 'Start-KiroEyeMonitor.ps1'
    return "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$janela`" " +
    "-Distro `"$Distro`" -BridgePath `"$BridgePath`""
}

function New-Launcher {
    <# .cmd para quem preferir abrir por linha de comando. #>
    param([Parameter(Mandatory)][string]$InstallDir, [Parameter(Mandatory)][string]$Arguments)

    $conteudo = @"
@echo off
rem Gerado por New-KiroEyeMonitorLauncher.ps1
start "" powershell.exe $Arguments %*
"@
    $caminho = Join-Path $InstallDir $script:LauncherName
    Set-Content -LiteralPath $caminho -Value $conteudo -Encoding ASCII
    return $caminho
}

function New-AppShortcut {
    <#
        .SYNOPSIS
        Cria um atalho para a janela na pasta informada.
        .EXAMPLE
        New-AppShortcut -Folder ([Environment]::GetFolderPath('Desktop')) -Arguments $args -IconPath $ico
    #>
    param(
        [Parameter(Mandatory)][string]$Folder,
        [Parameter(Mandatory)][string]$Arguments,
        [Parameter(Mandatory)][string]$InstallDir,
        [Parameter(Mandatory)][string]$IconPath
    )
    $destino = Join-Path $Folder $script:ShortcutName
    $shell = New-Object -ComObject WScript.Shell
    $atalho = $shell.CreateShortcut($destino)
    $atalho.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $atalho.Arguments = $Arguments
    $atalho.WorkingDirectory = $InstallDir
    $atalho.WindowStyle = $script:MinimizedWindow
    $atalho.Description = 'Consumo de creditos Kiro'
    if (Test-Path -LiteralPath $IconPath) { $atalho.IconLocation = $IconPath }
    $atalho.Save()
    return $destino
}

$argumentos = Get-WindowArgument -InstallDir $InstallDir -Distro $Distro -BridgePath $BridgePath
$icone = Join-Path $InstallDir 'assets\eye.ico'

Write-Output "lancador:  $(New-Launcher -InstallDir $InstallDir -Arguments $argumentos)"

if ($AddToDesktop) {
    $pasta = [Environment]::GetFolderPath('Desktop')
    Write-Output "desktop:   $(New-AppShortcut -Folder $pasta -Arguments $argumentos -InstallDir $InstallDir -IconPath $icone)"
}
if ($AddToStartup) {
    $pasta = [Environment]::GetFolderPath('Startup')
    Write-Output "autostart: $(New-AppShortcut -Folder $pasta -Arguments $argumentos -InstallDir $InstallDir -IconPath $icone)"
}
