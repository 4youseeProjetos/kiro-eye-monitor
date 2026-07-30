# Log de falhas do lado Windows, uma linha JSON por evento.
#
# O coletor do WSL grava o proprio log, mas parte das falhas nem chega la: o
# wsl.exe pode nao encontrar a distro, a interoperabilidade pode estar
# desligada, ou a saida pode vir truncada. A janela mostra so a mensagem curta,
# entao o texto bruto fica aqui.
#
# Fora da pasta de instalacao de proposito: o install.sh apaga e recria aquela
# pasta, o que levaria o historico embora justamente quando se reinstala para
# tentar resolver a falha.

Set-StrictMode -Version Latest

$script:LimiteBytes = 512KB
$script:LimiteTexto = 4000

function Get-WindowLogPath {
    <#
        .SYNOPSIS
        Arquivo de log da janela dentro do LOCALAPPDATA.
        .EXAMPLE
        Get-WindowLogPath -BaseDir $env:LOCALAPPDATA
    #>
    param([Parameter(Mandatory)][string]$BaseDir)

    return Join-Path (Join-Path $BaseDir 'kiro-eye-monitor') 'janela.jsonl'
}

function Write-WindowLogEntry {
    <#
        .SYNOPSIS
        Acrescenta uma falha ao log e devolve o caminho do arquivo.
        .DESCRIPTION
        Nunca lanca excecao: falha de log nao pode derrubar a janela.
        .EXAMPLE
        Write-WindowLogEntry -Path $log -Message 'resposta nao e JSON' -Detail $bruto -Context @{ distro = 'Ubuntu' }
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Message,
        [AllowEmptyString()][string]$Detail = '',
        [hashtable]$Context = @{}
    )
    try {
        $pasta = Split-Path -Parent $Path
        if (-not (Test-Path -LiteralPath $pasta)) {
            New-Item -ItemType Directory -Path $pasta -Force | Out-Null
        }
        Reset-WindowLogIfLarge -Path $Path
        $entrada = [ordered]@{
            quando   = (Get-Date).ToString('o')
            mensagem = $Message
            ambiente = $Context
        }
        if (-not [string]::IsNullOrWhiteSpace($Detail)) {
            $entrada['detalhe'] = Limit-LogText -Text $Detail
        }
        $linha = ($entrada | ConvertTo-Json -Compress -Depth 4)
        Add-Content -LiteralPath $Path -Value $linha -Encoding UTF8
    }
    catch {
        return $Path
    }
    return $Path
}

function Limit-LogText {
    <# Recorta texto longo para o log nao virar despejo de tela inteira. #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $limpo = $Text.Trim()
    if ($limpo.Length -le $script:LimiteTexto) { return $limpo }
    return $limpo.Substring(0, $script:LimiteTexto) + '...(truncado)'
}

function Reset-WindowLogIfLarge {
    <# Mantem so a geracao anterior, para o log nao crescer sem fim. #>
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return }
    if ((Get-Item -LiteralPath $Path).Length -lt $script:LimiteBytes) { return }
    $anterior = "$Path.1"
    if (Test-Path -LiteralPath $anterior) { Remove-Item -LiteralPath $anterior -Force }
    Move-Item -LiteralPath $Path -Destination $anterior -Force
}
