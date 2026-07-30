# Traducao de caminho do Windows para o caminho equivalente dentro do WSL.
#
# A janela normalmente roda a partir de \\wsl.localhost\Ubuntu\home\... (o
# projeto vive no WSL), mas tambem pode ser copiada para um disco do Windows,
# que o WSL enxerga em /mnt/<letra>.

Set-StrictMode -Version Latest

function Convert-WindowsPathToWslPath {
    <#
        .SYNOPSIS
        Converte um caminho do Windows no caminho visto de dentro do WSL.
        .EXAMPLE
        Convert-WindowsPathToWslPath -Path '\\wsl.localhost\Ubuntu\home\dev\app'  # /home/dev/app
    #>
    param([Parameter(Mandatory)][string]$Path)

    $uncMatch = [regex]::Match($Path, '^\\\\wsl(?:\$|\.localhost)\\[^\\]+\\(?<resto>.*)$')
    if ($uncMatch.Success) {
        return '/' + ($uncMatch.Groups['resto'].Value -replace '\\', '/')
    }
    $driveMatch = [regex]::Match($Path, '^(?<letra>[A-Za-z]):\\(?<resto>.*)$')
    if ($driveMatch.Success) {
        $letra = $driveMatch.Groups['letra'].Value.ToLowerInvariant()
        return "/mnt/$letra/" + ($driveMatch.Groups['resto'].Value -replace '\\', '/')
    }
    return $Path -replace '\\', '/'
}

function Get-RecordedBridgePath {
    <# Ponte anotada na instalacao, ou '' se o arquivo nao existe. #>
    param([Parameter(Mandatory)][string]$ScriptRoot)

    $anotacao = Join-Path $ScriptRoot 'bridge-path.txt'
    if (-not (Test-Path -LiteralPath $anotacao)) { return '' }
    return (Get-Content -LiteralPath $anotacao -Raw).Trim()
}

function Resolve-BridgePath {
    <#
        .SYNOPSIS
        Caminho do collect.sh dentro do WSL.
        .DESCRIPTION
        Ordem: o que foi pedido, depois o anotado na instalacao, por fim a
        deducao pela pasta do script. A anotacao existe porque a copia
        instalada em %LOCALAPPDATA% nao fica dentro do projeto, e a deducao
        acertaria apenas quando se roda direto do clone.
        .EXAMPLE
        Resolve-BridgePath -Informado '' -ScriptRoot 'C:\app\windows'
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Informado,
        [Parameter(Mandatory)][string]$ScriptRoot
    )
    if (-not [string]::IsNullOrWhiteSpace($Informado)) { return $Informado }
    $anotado = Get-RecordedBridgePath -ScriptRoot $ScriptRoot
    if (-not [string]::IsNullOrWhiteSpace($anotado)) { return $anotado }
    $projeto = Split-Path -Parent $ScriptRoot
    return (Convert-WindowsPathToWslPath -Path $projeto).TrimEnd('/') + '/scripts/collect.sh'
}
