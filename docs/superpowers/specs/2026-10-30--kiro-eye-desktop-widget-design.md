# Kiro Eye Monitor como widget de desktop

## Objetivo

Transformar a janela WPF existente em um cartão compacto para a área de trabalho do Windows, sem alterar o coletor Python, o contrato JSON ou as fontes de consumo do Kiro.

## Escopo aprovado

- O widget oferece três modos: **mínimo**, **normal** e **detalhado**.
- O modo normal é o padrão e mostra plano, percentual, créditos usados, saldo, ritmo e projeção.
- O modo mínimo é uma faixa curta com percentual, créditos usados/cota e uma barra fina de progresso.
- O modo detalhado expande o cartão normal para mostrar projetos, dias e conversas.
- O botão **Fixar** alterna entre janela normal, coberta pelos demais aplicativos, e janela sempre no topo.
- O cartão não usa a moldura padrão do Windows, não aparece na barra de tarefas e pode ser arrastado pelo cabeçalho.
- Posição, estado expandido e modo fixado sobrevivem ao reinício.
- Fechar pelo cartão apenas esconde o widget. O ícone da bandeja permite mostrar, atualizar, fixar e encerrar.
- Uma segunda execução sinaliza a instância existente para reaparecer, em vez de abrir outro widget.

## Fora do escopo

- Não criar um provedor para o Widgets Board do Windows 11.
- Não anexar a janela às estruturas internas `WorkerW` ou `Progman` do Explorer.
- Não adicionar Rainmeter, WinUI, Windows App SDK, MSIX ou dependências Python.
- Não alterar cálculo, persistência ou coleta de consumo.

## Interface

O estado compacto terá largura de 380 DIPs e altura determinada pelo conteúdo. O cartão terá fundo escuro, cantos arredondados, sombra discreta e uma única cor de destaque que muda nos níveis de atenção e crítico.

O cabeçalho normal conterá o nome do produto, a última atualização e os controles
**Menor**, **Fixar**, **Detalhes** e **Fechar**. A região do título será a alça
de arraste. **Menor** abre o modo mínimo; **Detalhes** alterna entre normal e
detalhado.

O modo mínimo terá sua própria alça de arraste, o percentual, o consumo no
formato `usado / cota`, uma barra fina, **Expandir** e **Fechar**. Os três modos
também estarão disponíveis no menu da bandeja.

A área principal exibirá o percentual como número de maior hierarquia, seguida pelo consumo total, barra de progresso, saldo e duas linhas curtas para ritmo e projeção. Em falha, essa área será substituída pelo painel de erro; números antigos não continuarão visíveis.

A área expandida manterá os dados atuais em duas abas: **Projetos** e **Análise**. Ela terá altura máxima e rolagem para não ultrapassar a tela.

## Arquitetura

- `windows/MainWindow.xaml`: aparência, hierarquia visual e controles nomeados.
- `windows/lib/UsageView.ps1`: mapeamento do relatório JSON para os controles.
- `windows/lib/WidgetWindow.ps1`: estado persistido, expansão, fixação, visibilidade e coordenação de instância única.
- `windows/Start-KiroEyeMonitor.ps1`: eventos, bandeja, timers e ciclo de vida da aplicação WPF.
- `%LOCALAPPDATA%\kiro-eye-monitor\widget-state.json`: posição, modo de visualização e preferência de fixação; fica fora da pasta recriada pelo instalador.

O coletor continuará sendo chamado em runspace separado por `wsl.exe`. Ocultar o widget não interromperá as atualizações automáticas nem os alertas.

## Compatibilidade e falhas

- Continuar compatível com Windows PowerShell 5.1 e WPF disponível no Windows 10/11.
- Strings em `.ps1` permanecem ASCII para evitar a leitura ANSI do PowerShell 5.1; o XAML continua UTF-8.
- Estado ausente, antigo ou inválido cai para os padrões: modo normal, não fixado e canto inferior direito.
- Coordenadas restauradas são limitadas à área virtual visível para lidar com monitor desconectado.
- Falha ao ler ou gravar preferências não derruba o monitor.

## Validação

- Testes Pester verificam propriedades da janela, conteúdo e transições dos três modos, fixação, persistência, estado inválido e instância única.
- Os testes existentes de renderização, erro, posicionamento, ícone, formatação e sintaxe continuam passando.
- O pytest garante que o coletor permaneceu intacto.
- A instalação local é refeita com atalho de desktop e inicialização automática; uma captura confirma o resultado real no Windows.
