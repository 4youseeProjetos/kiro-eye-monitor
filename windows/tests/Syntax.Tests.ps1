# Analise sintatica de todo .ps1 do projeto.
#
# Existe porque o entrypoint nunca e carregado pelas outras suites — elas
# importam apenas as libs — e uma edicao deixou nele uma funcao duplicada com
# chave sem fechar. O sintoma foi a janela abrir e morrer sem log, o pior tipo
# de falha para quem instala.

$script:RaizWindows = Split-Path -Parent $PSScriptRoot

function Get-ScriptSyntaxError {
    <# Erros de parse do arquivo, lista vazia quando esta correto. #>
    param([Parameter(Mandatory)][string]$Path)

    $erros = $null
    [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$erros) | Out-Null
    if ($null -eq $erros) { return @() }
    return @($erros)
}

Describe 'Sintaxe dos scripts PowerShell' {

    $arquivos = @(Get-ChildItem -Path $script:RaizWindows -Filter '*.ps1' -Recurse |
            Where-Object { $_.FullName -notlike '*\tests\*' })

    It 'encontra os scripts do projeto' {
        $arquivos.Count -ge 8 | Should Be $true
    }

    It 'inclui o entrypoint, que nenhuma outra suite carrega' {
        @($arquivos | Where-Object { $_.Name -eq 'Start-KiroEyeMonitor.ps1' }).Count | Should Be 1
    }

    foreach ($arquivo in $arquivos) {
        It "analisa $($arquivo.Name) sem erro de sintaxe" {
            $problemas = Get-ScriptSyntaxError -Path $arquivo.FullName
            $relato = ($problemas | ForEach-Object { "linha $($_.Extent.StartLineNumber): $($_.Message)" }) -join '; '
            $relato | Should BeNullOrEmpty
        }
    }
}

function Get-NonAsciiStringLiteral {
    <#
        Textos de string com caractere fora do ASCII, por arquivo.

        Usa os tokens do parser em vez de varrer o arquivo inteiro: comentario
        com acento e inofensivo, string exibida na janela nao.
    #>
    param([Parameter(Mandatory)][string]$Path)

    $tokens = $null
    [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$null) | Out-Null
    $kinds = @('StringLiteral', 'StringExpandable', 'HereStringLiteral', 'HereStringExpandable')
    return @($tokens |
            Where-Object { $kinds -contains $_.Kind.ToString() } |
            Where-Object { $_.Text -match '[^\x00-\x7F]' } |
            ForEach-Object { "linha $($_.Extent.StartLineNumber): $($_.Text)" })
}

Describe 'Texto exibido pela janela' {

    # O PowerShell 5.1 le .ps1 sem BOM como ANSI, entao acento e travessao no
    # fonte chegam quebrados na tela: "rode" viraria "rode â€"". Texto vindo do
    # coletor nao tem esse problema, porque a saida e decodificada como UTF-8.
    $arquivos = @(Get-ChildItem -Path $script:RaizWindows -Filter '*.ps1' -Recurse |
            Where-Object { $_.FullName -notlike '*\tests\*' })

    foreach ($arquivo in $arquivos) {
        It "$($arquivo.Name) so tem string em ASCII" {
            $achados = Get-NonAsciiStringLiteral -Path $arquivo.FullName
            ($achados -join '; ') | Should BeNullOrEmpty
        }
    }
}
