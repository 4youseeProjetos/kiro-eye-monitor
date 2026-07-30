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
