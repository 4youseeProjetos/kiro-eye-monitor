# Descoberta da distro WSL onde o coletor deve rodar.
#
# O wsl.exe exige o nome exato registrado na maquina, e esse nome varia entre
# desenvolvedores: 'Ubuntu', 'Ubuntu-24.04', 'Debian'. Supor um nome fixo
# quebra a instalacao de quem usa outro, por isso aqui se le o que a maquina
# realmente tem.
#
# A leitura vem do registro, e nao de 'wsl.exe --list', porque a saida do
# wsl.exe e UTF-16 com enfeites de tabela e muda conforme o idioma do Windows.

Set-StrictMode -Version Latest

$script:ChaveLxss = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'

function Get-WslDistroInventory {
    <#
        .SYNOPSIS
        Nomes das distros WSL instaladas e qual delas e a padrao.
        .EXAMPLE
        (Get-WslDistroInventory).Names  # @('Ubuntu-24.04', 'docker-desktop')
    #>
    if (-not (Test-Path -LiteralPath $script:ChaveLxss)) {
        return [pscustomobject]@{ Names = @(); Default = '' }
    }
    $raiz = Get-ItemProperty -LiteralPath $script:ChaveLxss -ErrorAction SilentlyContinue
    $guidPadrao = if ($null -ne $raiz -and
        $raiz.PSObject.Properties.Name -contains 'DefaultDistribution') {
        $raiz.DefaultDistribution
    }
    else { '' }

    $nomes = [System.Collections.Generic.List[string]]::new()
    $padrao = ''
    foreach ($chave in Get-ChildItem -LiteralPath $script:ChaveLxss -ErrorAction SilentlyContinue) {
        $nome = (Get-ItemProperty -LiteralPath $chave.PSPath -ErrorAction SilentlyContinue).DistributionName
        if ([string]::IsNullOrWhiteSpace($nome)) { continue }
        $nomes.Add($nome)
        if ($chave.PSChildName -eq $guidPadrao) { $padrao = $nome }
    }
    return [pscustomobject]@{ Names = $nomes.ToArray(); Default = $padrao }
}

function Select-InstalledDistro {
    <# Nome canonico da distro instalada que corresponde ao pedido, ou ''. #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Requested,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Installed
    )
    foreach ($nome in $Installed) {
        if ($nome -eq $Requested) { return $nome }
    }
    foreach ($nome in $Installed) {
        if ($nome.Equals($Requested, [System.StringComparison]::OrdinalIgnoreCase)) { return $nome }
    }
    # Resgata lancador antigo que gravou 'Ubuntu' numa maquina com 'Ubuntu-24.04'.
    $porPrefixo = @($Installed | Where-Object {
            $_.StartsWith("$Requested-", [System.StringComparison]::OrdinalIgnoreCase)
        })
    if ($porPrefixo.Count -eq 1) { return $porPrefixo[0] }
    return ''
}

function Test-DockerInfrastructureDistro {
    <#
        .SYNOPSIS
        Indica se a distro e apoio interno do Docker Desktop.
        .DESCRIPTION
        Sao distros minimas, sem python3 nem kiro-cli, e nunca o alvo do
        monitor. Aparecem na lista do WSL e as vezes como distro padrao,
        entao ficam de fora da escolha automatica.
        .EXAMPLE
        Test-DockerInfrastructureDistro -Name 'docker-desktop-data'  # $true
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Name)

    return $Name -match '^docker-desktop(-data)?$'
}

function Select-AutomaticDistro {
    <# Distro usada quando nada e pedido: a padrao, fugindo das do Docker. #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string[]]$Installed,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Default
    )
    $uteis = @($Installed | Where-Object { -not (Test-DockerInfrastructureDistro -Name $_) })
    if ($uteis.Count -eq 0) { return $Installed[0] }
    if ($Default -and ($uteis -contains $Default)) { return $Default }
    return $uteis[0]
}

function Resolve-WslDistroName {
    <#
        .SYNOPSIS
        Decide em qual distro rodar, validando contra as instaladas.
        .DESCRIPTION
        Sem pedido explicito, usa a distro padrao do WSL. Com pedido, exige que
        exista, para falhar com mensagem clara em vez de deixar o wsl.exe
        devolver erro cru.
        .EXAMPLE
        Resolve-WslDistroName -Requested '' -Installed @('Ubuntu-24.04') -Default 'Ubuntu-24.04'
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Requested,
        [Parameter(Mandatory)][AllowEmptyString()][AllowEmptyCollection()][string[]]$Installed,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Default
    )
    $reais = @($Installed | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($reais.Count -eq 0) {
        throw 'nenhuma distro WSL instalada nesta maquina; instale uma com "wsl --install -d Ubuntu" e reinstale o kiro-eye-monitor'
    }
    if ([string]::IsNullOrWhiteSpace($Requested)) {
        return Select-AutomaticDistro -Installed $reais -Default $Default
    }
    $escolhida = Select-InstalledDistro -Requested $Requested -Installed $reais
    if (-not [string]::IsNullOrWhiteSpace($escolhida)) { return $escolhida }
    throw ("distro WSL '$Requested' nao existe nesta maquina; " +
        "instaladas: $($reais -join ', '). Rode com -Distro <nome exato>")
}
