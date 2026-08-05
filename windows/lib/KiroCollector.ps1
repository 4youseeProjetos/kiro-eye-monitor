# Invocacao do coletor que roda dentro do WSL.
#
# Toda a leitura de dados vive no WSL; aqui so se transporta JSON. Falhas
# viram um objeto com a propriedade 'error' para que a janela exiba a causa em
# vez de ficar sem resposta.

Set-StrictMode -Version Latest

function Set-KiroCollectorEncoding {
    <#
        .SYNOPSIS
        Faz o PowerShell decodificar a saida do coletor como UTF-8.

        .DESCRIPTION
        O coletor emite JSON em UTF-8, e desde a aba de analise esse JSON carrega
        texto do desenvolvedor: o titulo de cada conversa. Sem este ajuste o
        PowerShell decodifica a saida do wsl.exe com a pagina de codigo do console
        (CP850 no Windows em portugues) e "pesquisa" chega quebrado na janela.

        Devolve $false quando nao ha console para configurar, em vez de estourar:
        a janela vale mais que o acento.

        .EXAMPLE
        $null = Set-KiroCollectorEncoding
    #>
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        return $true
    }
    catch {
        return $false
    }
}

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

function Get-KiroReportText {
    <#
        .SYNOPSIS
        Texto de uma propriedade do relatorio, vazio quando o coletor nao a manda.
        .DESCRIPTION
        Mesma tolerancia de Get-KiroReportList, para escalares: coletor anterior
        ao versionamento nao envia collector_version, e ler a chave ausente
        estouraria sob Set-StrictMode.
        .EXAMPLE
        Get-KiroReportText -Source $Report -Name 'collector_version'
    #>
    param(
        [Parameter(Mandatory)][pscustomobject]$Source,
        [Parameter(Mandatory)][string]$Name
    )
    if ($Source.PSObject.Properties.Name -notcontains $Name) { return '' }
    return [string]$Source.$Name
}

function Get-KiroInstalledVersion {
    <#
        .SYNOPSIS
        Versao gravada pelo install.sh ao copiar a janela.

        .DESCRIPTION
        Arquivo ausente significa janela copiada a mao ou instalada antes do
        versionamento; nesse caso a janela so nao exibe versao, em vez de falhar.

        .EXAMPLE
        Get-KiroInstalledVersion -Path "$PSScriptRoot\VERSION"
    #>
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    try {
        return ([string](Get-Content -LiteralPath $Path -TotalCount 1 -Encoding UTF8)).Trim()
    }
    catch {
        return ''
    }
}

function Test-KiroCollectorFailure {
    <# Indica se o relatorio devolvido representa uma falha. #>
    param([AllowNull()][pscustomobject]$Report)

    if ($null -eq $Report) { return $true }
    return [bool]($Report.PSObject.Properties.Name -contains 'error')
}

function Test-KiroReportHasDetail {
    <#
        .SYNOPSIS
        Indica se o relatorio traz o detalhamento do kiro-cli.
        .DESCRIPTION
        Checa a existencia da propriedade antes do valor porque o relatorio de
        falha nem tem a chave, e Set-StrictMode transforma esse acesso em erro.
        .EXAMPLE
        if (Test-KiroReportHasDetail -Report $relatorio) { ... }
    #>
    param([AllowNull()][pscustomobject]$Report)

    if ($null -eq $Report) { return $false }
    if ($Report.PSObject.Properties.Name -notcontains 'cli_breakdown') { return $false }
    return $null -ne $Report.cli_breakdown
}

function Get-KiroReportList {
    <#
        .SYNOPSIS
        Lista de uma propriedade do relatorio, vazia quando o coletor nao a manda.
        .DESCRIPTION
        Tolera coletor mais antigo que a janela: quem faz git pull sem reinstalar
        fica com as duas metades em versoes diferentes, e a janela nao pode
        morrer por causa de uma chave nova que ainda nao existe do outro lado.

        Devolve uma List, e nao @(), porque array vazio devolvido por funcao e
        desenrolado para $null pelo PowerShell, e ai .Count estoura sob
        Set-StrictMode.
        .EXAMPLE
        Get-KiroReportList -Source $Report.cli_breakdown -Name 'by_day'
    #>
    param(
        [Parameter(Mandatory)][pscustomobject]$Source,
        [Parameter(Mandatory)][string]$Name
    )
    $itens = New-Object 'System.Collections.Generic.List[object]'
    if ($Source.PSObject.Properties.Name -contains $Name) {
        foreach ($item in @($Source.$Name)) {
            if ($null -ne $item) { $itens.Add($item) }
        }
    }
    return , $itens
}
