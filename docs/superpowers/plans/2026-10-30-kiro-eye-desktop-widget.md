# Kiro Eye Desktop Widget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Converter a janela WPF do Kiro Eye Monitor em um widget compacto, expansível e persistente no desktop do Windows.

**Architecture:** O coletor Python e seu JSON permanecem inalterados. O XAML define o cartão; `UsageView.ps1` desenha dados; um novo `WidgetWindow.ps1` concentra estado e comportamento de janela; o entrypoint liga eventos, bandeja e ciclo de vida.

**Tech Stack:** Windows PowerShell 5.1, WPF/XAML, Windows Forms NotifyIcon, Pester 3, Python 3.12 e pytest.

## Global Constraints

- Preservar o contrato JSON e todos os arquivos de `src/kiro_eye_monitor/`.
- Não adicionar dependências de runtime.
- Manter strings exibidas por `.ps1` em ASCII; texto Unicode pode permanecer no XAML UTF-8.
- Não usar APIs internas do Explorer nem o Widgets Board.
- Não criar commit sem pedido explícito do usuário; as etapas de commit foram omitidas por regra do repositório.

---

### Task 1: Contrato visual do widget

**Files:**
- Modify: `windows/tests/UsageView.Tests.ps1`
- Modify: `windows/MainWindow.xaml`
- Modify: `windows/lib/UsageView.ps1`

**Interfaces:**
- Consumes: o mesmo objeto `UsageReport` já entregue a `Show-UsageReport`.
- Produces: controles `WidgetFrame`, `DragHandle`, `AccountPanel`, `UsagePercentText`, `ExpandedDetails`, `PinButton`, `ExpandButton` e `CloseButton`.

- [x] **Step 1: Escrever testes que carreguem o XAML e exijam o contrato de widget**

Adicionar asserções para `WindowStyle=None`, `AllowsTransparency=True`, `ShowInTaskbar=False`, `ResizeMode=NoResize`, largura compacta, detalhes recolhidos e presença dos novos controles.

- [x] **Step 2: Rodar o teste focado e confirmar RED**

Run:

```powershell
Invoke-Pester -Path .\windows\tests\UsageView.Tests.ps1
```

Expected: falha porque as propriedades e os controles ainda não existem.

- [x] **Step 3: Reestruturar o XAML como cartão compacto**

Definir a janela transparente sem moldura, o cabeçalho de arraste, a hierarquia do resumo, a área de erro substitutiva e o painel de detalhes com altura máxima e rolagem. Manter os nomes atuais consumidos pelo renderer e acrescentar os nomes novos.

- [x] **Step 4: Atualizar o renderer**

Adicionar `UsagePercentText` e `AccountPanel` ao mapa. Em sucesso, mostrar o painel da conta e preencher o percentual. Em falha, ocultar a conta e limpar o percentual. Renomear visualmente a primeira aba para **Projetos**, sem mudar a semântica dos dados.

- [x] **Step 5: Rodar os testes focados e confirmar GREEN**

Run:

```powershell
Invoke-Pester -Path .\windows\tests\UsageView.Tests.ps1
```

Expected: todos os testes da renderização passam.

### Task 2: Estado e comportamento persistente

**Files:**
- Create: `windows/lib/WidgetWindow.ps1`
- Create: `windows/tests/WidgetWindow.Tests.ps1`
- Modify: `windows/tests/WindowPlacement.Tests.ps1`
- Modify: `windows/lib/UsageView.ps1`

**Interfaces:**
- Produces: `Get-WidgetStatePath`, `Read-WidgetState`, `Write-WidgetState`, `Set-WidgetExpanded`, `Set-WidgetPinned`, `Restore-WidgetPosition`, `New-WidgetInstanceCoordinator`, `Test-WidgetShowRequested` e `Close-WidgetInstanceCoordinator`.
- Consumes: uma janela WPF, o mapa de controles e caminhos sob `%LOCALAPPDATA%`.

- [x] **Step 1: Escrever testes para preferências e toggles**

Cobrir arquivo ausente, JSON inválido, gravação/leitura de coordenadas e flags, expansão, fixação e restauração de posição válida.

- [x] **Step 2: Escrever teste de instância única**

Criar dois coordenadores com um nome aleatório. O primeiro deve ser primário; o segundo deve sinalizar o primeiro e informar que não é primário.

- [x] **Step 3: Escrever regressão para coordenada fora da tela virtual**

Testar uma função de limitação com área fornecida explicitamente, incluindo monitor à esquerda com coordenada negativa e monitor removido.

- [x] **Step 4: Rodar os novos testes e confirmar RED**

Run:

```powershell
Invoke-Pester -Path .\windows\tests\WidgetWindow.Tests.ps1,.\windows\tests\WindowPlacement.Tests.ps1
```

Expected: falha porque o módulo e as funções ainda não existem.

- [x] **Step 5: Implementar o módulo `WidgetWindow.ps1`**

Ler estado com padrões seguros; gravar JSON por arquivo temporário; alternar `Visibility`, `IsChecked` e `Topmost`; restaurar apenas números finitos; coordenar instância via mutex e evento nomeados; nunca propagar falha de preferência.

- [x] **Step 6: Generalizar a limitação de posição**

Extrair a limitação para uma área retangular e usar a área virtual quando a janela estiver fora da tela principal. Preservar os testes de posicionamento existentes.

- [x] **Step 7: Rodar os testes focados e confirmar GREEN**

Run:

```powershell
Invoke-Pester -Path .\windows\tests\WidgetWindow.Tests.ps1,.\windows\tests\WindowPlacement.Tests.ps1
```

Expected: todos passam.

### Task 3: Ciclo de vida, arraste e bandeja

**Files:**
- Modify: `windows/Start-KiroEyeMonitor.ps1`
- Modify: `windows/tests/Syntax.Tests.ps1`

**Interfaces:**
- Consumes: funções de `WidgetWindow.ps1` e controles novos do XAML.
- Produces: widget ocultável, tray com comandos, persistência após interação e reativação da instância existente.

- [x] **Step 1: Acrescentar verificações estruturais do entrypoint**

Os testes devem exigir que o entrypoint carregue `WidgetWindow.ps1`, registre os novos controles e não dependa mais exclusivamente de `ShowDialog()`.

- [x] **Step 2: Rodar os testes e confirmar RED**

Run:

```powershell
Invoke-Pester -Path .\windows\tests\Syntax.Tests.ps1
```

Expected: falha nas novas exigências estruturais.

- [x] **Step 3: Integrar estado e instância única no startup**

Criar o coordenador antes da janela. A segunda execução envia o sinal de exibição e termina. A instância principal restaura posição, expansão e fixação.

- [x] **Step 4: Ligar os eventos da janela**

Arrastar por `DragHandle`; salvar após arraste, expansão e fixação; esconder por `CloseButton`; atualizar por `RefreshButton`; restaurar por sinal ou bandeja.

- [x] **Step 5: Completar o menu da bandeja**

Adicionar **Mostrar/ocultar**, **Atualizar**, **Sempre no topo** e **Sair**. Continuar emitindo os alertas de limiar existentes.

- [x] **Step 6: Trocar o ciclo modal pela aplicação WPF explícita**

Usar `Application` com `ShutdownMode=OnExplicitShutdown` para permitir esconder a janela sem encerrar coleta e timers. Encerrar somente pelo item **Sair** ou pelo fim da sessão.

- [x] **Step 7: Rodar os testes focados e confirmar GREEN**

Run:

```powershell
Invoke-Pester -Path .\windows\tests\Syntax.Tests.ps1,.\windows\tests\WidgetWindow.Tests.ps1
```

Expected: todos passam.

### Task 4: Três modos de visualização

**Files:**
- Modify: `windows/tests/UsageView.Tests.ps1`
- Modify: `windows/tests/WidgetWindow.Tests.ps1`
- Modify: `windows/tests/Syntax.Tests.ps1`
- Modify: `windows/MainWindow.xaml`
- Modify: `windows/lib/UsageView.ps1`
- Modify: `windows/lib/WidgetWindow.ps1`
- Modify: `windows/Start-KiroEyeMonitor.ps1`

**Interfaces:**
- Produces: `Set-WidgetViewMode -Ui <hashtable> -Mode <minimal|normal|detailed>` e estado `ViewMode` persistido.
- Consumes: os mesmos campos de conta usados pelo resumo normal.

- [x] **Step 1: Escrever testes RED para o modo mínimo**

Exigir `MinimalPanel`, `MinimalDragHandle`, `MinimalPercentText`, `MinimalCreditsText`, `MinimalUsageBar`, `MinimalExpandButton`, `MinimalCloseButton` e `MinimizeButton`. Verificar percentual, consumo/cota e nível da barra.

- [x] **Step 2: Escrever testes RED para transições e persistência**

Cobrir os modos `minimal`, `normal` e `detailed`; fallback do estado antigo `expanded`; gravação de `view_mode`; rejeição de modo desconhecido.

- [x] **Step 3: Confirmar RED nas suítes focadas**

Run:

```powershell
Invoke-Pester -Path .\windows\tests\UsageView.Tests.ps1,.\windows\tests\WidgetWindow.Tests.ps1,.\windows\tests\Syntax.Tests.ps1
```

Expected: falhas apenas pelos novos controles, renderer e API ausentes.

- [x] **Step 4: Implementar a faixa mínima e o renderer**

Adicionar o painel alternativo de baixa altura no mesmo `WidgetFrame`. Espelhar percentual, créditos e barra no renderer; em falha, trocar os números por uma indicação curta sem exibir valores antigos.

- [x] **Step 5: Implementar `Set-WidgetViewMode` e compatibilidade de estado**

Alternar visibilidade dos painéis, manter `ExpandButton.IsChecked` coerente e ler arquivos antigos que só tenham `expanded`. Gravar `view_mode` junto com a flag legada.

- [x] **Step 6: Integrar botões e menu da bandeja**

`Menor` muda para mínimo, `Expandir` volta ao normal e `Detalhes` alterna normal/detalhado. O submenu **Visualização** expõe os três modos e mantém o item atual marcado.

- [x] **Step 7: Confirmar GREEN e repetir as suítes completas**

Run Pester completo, pytest e `git diff --check`. Expected: zero falhas e nenhum arquivo de `src/` ou `scripts/` alterado.

### Task 5: Regressão completa, documentação e instalação

**Files:**
- Modify: `README.md`
- Modify: `docs/janela.png`

**Interfaces:**
- Consumes: instalador existente e `windows/tools/Save-WindowShot.ps1`.
- Produces: documentação coerente e cópia local instalada do widget.

- [x] **Step 1: Rodar toda a suíte Pester em disco local do Windows**

Run, após copiar `windows/` para `%TEMP%`:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:TEMP\kiro-win\tools\Invoke-LocalPester.ps1"
```

Expected: zero falhas.

- [x] **Step 2: Rodar pytest**

Run:

```bash
uv run --group dev pytest -q
```

Expected: zero falhas.

- [x] **Step 3: Atualizar o README**

Explicar estado compacto, detalhes, arraste, fixação, bandeja, persistência e inicialização automática.

- [x] **Step 4: Reinstalar a cópia local**

Run:

```bash
./install.sh --desktop --startup
```

Expected: cópia atualizada em `%LOCALAPPDATA%\KiroEyeMonitor`, atalhos criados e widget aberto.

- [x] **Step 5: Capturar e inspecionar a janela real**

Salvar a captura em `docs/janela.png`, abrir a imagem e verificar moldura, recorte, hierarquia, texto, rolagem e ausência de sobreposição.

- [x] **Step 6: Verificar instalação e repositório**

Confirmar processo único, arquivo de estado fora da pasta instalada, coleta real sem erro e `git diff --check`. Relatar qualquer item não verificável.
