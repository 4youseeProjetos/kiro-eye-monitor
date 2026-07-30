# Execucao de trabalho fora da thread de UI.
#
# A coleta chama wsl.exe e leva alguns segundos; rodar na thread da janela
# congelaria a interface. O runspace recebe apenas dados primitivos, entao o
# scriptblock de trabalho nao depende dos modulos carregados aqui.

Set-StrictMode -Version Latest

function Start-BackgroundCall {
    <#
        .SYNOPSIS
        Dispara um scriptblock em runspace proprio e devolve o handle.
        .EXAMPLE
        $call = Start-BackgroundCall -Work { param($x) $x * 2 } -ArgumentList @(21)
    #>
    param(
        [Parameter(Mandatory)][scriptblock]$Work,
        [object[]]$ArgumentList = @()
    )
    $shell = [powershell]::Create()
    $null = $shell.AddScript($Work.ToString())
    foreach ($argumento in $ArgumentList) { $null = $shell.AddArgument($argumento) }
    return [pscustomobject]@{
        Shell  = $shell
        Handle = $shell.BeginInvoke()
    }
}

function Test-BackgroundCallCompleted {
    <# Indica se a chamada terminou, sem bloquear. #>
    param([Parameter(Mandatory)][pscustomobject]$Call)
    return [bool]$Call.Handle.IsCompleted
}

function Receive-BackgroundCall {
    <# Colhe o resultado e libera o runspace; devolve texto vazio em falha. #>
    param([Parameter(Mandatory)][pscustomobject]$Call)

    try {
        return ($Call.Shell.EndInvoke($Call.Handle) | Out-String)
    }
    catch {
        return ''
    }
    finally {
        $Call.Shell.Dispose()
    }
}
