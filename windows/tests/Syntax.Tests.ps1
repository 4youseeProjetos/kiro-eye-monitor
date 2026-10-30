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

Describe 'Entrypoint do widget' {

    $entrypoint = Join-Path $script:RaizWindows 'Start-KiroEyeMonitor.ps1'
    $conteudo = Get-Content -LiteralPath $entrypoint -Raw -Encoding UTF8

    It 'carrega o modulo de comportamento do widget' {
        [bool]($conteudo -match 'lib\\WidgetWindow\.ps1') | Should Be $true
    }

    It 'registra os controles interativos do cabecalho' {
        [bool]($conteudo -match "'DragHandle'") | Should Be $true
        [bool]($conteudo -match "'PinButton'") | Should Be $true
        [bool]($conteudo -match "'ExpandButton'") | Should Be $true
        [bool]($conteudo -match "'CloseButton'") | Should Be $true
    }

    It 'registra os controles do modo minimo' {
        [bool]($conteudo -match "'MinimalPanel'") | Should Be $true
        [bool]($conteudo -match "'MinimalDragHandle'") | Should Be $true
        [bool]($conteudo -match "'MinimizeButton'") | Should Be $true
        [bool]($conteudo -match "'MinimalExpandButton'") | Should Be $true
        [bool]($conteudo -match "'MinimalPinButton'") | Should Be $true
        [bool]($conteudo -match "'MinimalCloseButton'") | Should Be $true
        [bool]($conteudo -match 'MinimalPinButton\.add_Click') | Should Be $true
    }

    It 'oferece os tres modos no menu da bandeja' {
        [bool]($conteudo -match "Visualizacao minima") | Should Be $true
        [bool]($conteudo -match "Visualizacao normal") | Should Be $true
        [bool]($conteudo -match "Visualizacao detalhada") | Should Be $true
    }

    It 'cria um menu de contexto para o icone da bandeja' {
        [bool]($conteudo -match 'ContextMenuStrip') | Should Be $true
    }

    It 'mantem o dispatcher vivo quando a janela e escondida' {
        [bool]($conteudo -match 'System\.Windows\.Application') | Should Be $true
        [bool]($conteudo -notmatch '\.ShowDialog\(') | Should Be $true
    }
}
