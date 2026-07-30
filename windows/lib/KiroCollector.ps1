# Invocacao do coletor que roda dentro do WSL.
#
# Toda a leitura de dados vive no WSL; aqui so se transporta JSON. Falhas
# viram um objeto com a propriedade 'error' para que a janela exiba a causa em
# vez de ficar sem resposta.

Set-StrictMode -Version Latest

function New-KiroCollectorConfig {
    <#
        .SYNOPSIS
        Configuracao da ponte para o coletor no WSL.
        .EXAMPLE
        New-KiroCollectorConfig -Distro 'Ubuntu' -BridgePath '/home/dev/app/scripts/collect.sh'
    #>
    param(
        [Parameter(Mandatory)][string]$Distro,
        [Parameter(Mandatory)][string]$BridgePath
    )
    return [pscustomobject]@{
        Distro     = $Distro
        BridgePath = $BridgePath
    }
}

function Get-KiroCollectorArgument {
    <# Argumentos do wsl.exe para uma coleta. #>
    param(
        [Parameter(Mandatory)][pscustomobject]$Config,
        [switch]$AccountOnly
    )
    $wslArgs = @('-d', $Config.Distro, '--', $Config.BridgePath)
    if ($AccountOnly) { $wslArgs += '--account-only' }
    return $wslArgs
}

function ConvertFrom-KiroCollectorOutput {
    <# Converte a saida do coletor em objeto, sem lancar excecao. #>
    param([AllowNull()][string]$Raw)

    if ([string]::IsNullOrWhiteSpace($Raw)) {
        return [pscustomobject]@{ error = 'o coletor nao devolveu dados' }
    }
    try {
        return $Raw | ConvertFrom-Json
    }
    catch {
        $trecho = $Raw.Trim()
        if ($trecho.Length -gt 300) { $trecho = $trecho.Substring(0, 300) + '...' }
        return [pscustomobject]@{ error = "resposta nao e JSON: $trecho" }
    }
}

function Invoke-KiroCollector {
    <#
        .SYNOPSIS
        Roda o coletor no WSL e devolve o relatorio como objeto.
        .EXAMPLE
        Invoke-KiroCollector -Config $config -AccountOnly
    #>
    param(
        [Parameter(Mandatory)][pscustomobject]$Config,
        [switch]$AccountOnly
    )
    $wslArgs = Get-KiroCollectorArgument -Config $Config -AccountOnly:$AccountOnly
    try {
        $raw = (& wsl.exe @wslArgs 2>&1 | Out-String)
    }
    catch {
        return [pscustomobject]@{ error = "falha ao chamar wsl.exe: $($_.Exception.Message)" }
    }
    return ConvertFrom-KiroCollectorOutput -Raw $raw
}

function Test-KiroCollectorFailure {
    <# Indica se o relatorio devolvido representa uma falha. #>
    param([AllowNull()][pscustomobject]$Report)

    if ($null -eq $Report) { return $true }
    return [bool]($Report.PSObject.Properties.Name -contains 'error')
}
