# Runner usado no desenvolvimento: roda o Pester e resume o resultado em uma
# linha, com uma linha por falha.
#
# Existe porque o Pester 3 nao executa a partir de caminho UNC: quem desenvolve
# no WSL copia a pasta windows para disco local do Windows e chama este script
# de la.
#
# Uso, dentro do WSL:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass \
#     -File 'C:\Temp\kiro-win\tools\Invoke-LocalPester.ps1' -OutFile 'C:\Temp\kiro-win\resultado.txt'
[CmdletBinding()]
param(
    [string]$TestPath = '',
    [string]$OutFile = ''
)

$ErrorActionPreference = 'Stop'

# Resolvido aqui, e nao no default do parametro: com -File o $PSScriptRoot do
# bloco param chega vazio no PowerShell 5.1, e o Join-Path falha.
$caminho = if ($TestPath) { $TestPath } else { Join-Path (Split-Path -Parent $PSScriptRoot) 'tests' }

$resultado = Invoke-Pester -Path $caminho -PassThru -Quiet
$linhas = New-Object 'System.Collections.Generic.List[string]'
$linhas.Add("TOTAL=$($resultado.TotalCount) PASSOU=$($resultado.PassedCount) FALHOU=$($resultado.FailedCount)")
foreach ($teste in ($resultado.TestResult | Where-Object { -not $_.Passed })) {
    $motivo = ($teste.FailureMessage -replace "`r?`n", ' | ')
    $linhas.Add("FALHA: $($teste.Describe) > $($teste.Name) :: $motivo")
}
if ($OutFile) { $linhas | Set-Content -Path $OutFile -Encoding UTF8 }
$linhas | ForEach-Object { Write-Output $_ }
exit $resultado.FailedCount
