# Instruções para agentes

Este repositório instala uma janela no Windows que mostra o consumo de créditos
Kiro, lendo os dados de dentro do WSL.

Se um usuário pedir para instalar este projeto, siga o roteiro abaixo. Ele é
curto de propósito: quase tudo já está automatizado no `install.sh`.

## Primeiro: é instalação ou atualização?

```bash
cat ~/.config/kiro-eye-monitor/config 2>/dev/null
```

Se o arquivo existe, o projeto já está nesta máquina: vá para **Atualizar**. Não
clone de novo — `git clone` sobre um diretório existente falha, e clonar em outro
lugar cria uma segunda cópia com a janela apontando para a antiga.

## Instalar

**Obrigatório: rode dentro do WSL.** Não adapte para PowerShell, não traduza os
comandos, não tente uma alternativa. O coletor lê os dados de dentro do WSL e o
PowerShell 5.1 trava ao executar scripts a partir de `\\wsl.localhost` — não
existe caminho equivalente pelo Windows.

Confira primeiro em que ambiente você está: `echo $WSL_DISTRO_NAME` precisa
retornar o nome de uma distro. Se retornar vazio, você está fora do WSL.

Dentro do WSL:

```bash
git clone https://github.com/4youseeProjetos/kiro-eye-monitor.git ~/kiro-eye-monitor
cd ~/kiro-eye-monitor
./install.sh --desktop
```

Se a sua sessão é do lado Windows, entre no WSL no próprio comando:

```powershell
wsl.exe -- bash -lc 'cd ~ && git clone https://github.com/4youseeProjetos/kiro-eye-monitor.git && cd kiro-eye-monitor && ./install.sh --desktop'
```

O `install.sh` detecta a distro, copia a janela para `%LOCALAPPDATA%\KiroEyeMonitor`,
cria o atalho na área de trabalho e abre o app. Use `--startup` se o usuário
quiser que abra junto com o Windows, e `--no-desktop` se ele não quiser atalho.

Não clone para dentro de `/mnt/c`: funciona, mas a leitura dos arquivos de sessão
fica lenta pelo sistema de arquivos do Windows.

## Atualizar

São dois passos, e **os dois são obrigatórios**: o `git pull` atualiza o coletor,
que roda do clone; o `install.sh` recopia a janela para `%LOCALAPPDATA%`. Só o
`git pull` deixa metade nova e metade velha.

Descubra onde está o clone, em vez de presumir `~/kiro-eye-monitor`:

```bash
grep '^PROJECT_DIR=' ~/.config/kiro-eye-monitor/config | cut -d= -f2-
```

Saída vazia significa instalação feita antes desse registro. Nesse caso, tente
`~/kiro-eye-monitor`; se não existir, o caminho da ponte está em
`bridge-path.txt`, dentro de `%LOCALAPPDATA%\KiroEyeMonitor`, e o clone é o
diretório que contém aquele `scripts/`. Não achando, pergunte ao usuário onde ele
clonou — não clone de novo.

Com o caminho em mãos:

```bash
cd <clone> && git pull && ./install.sh -y
```

O `install.sh` encerra a janela aberta, recopia, recria os atalhos e reabre. Não
peça ao usuário para fechar a janela antes, e não apague o clone: o histórico de
leituras e o log de falhas ficam fora dele, mas apagar não ajuda em nada.

Confirme que pegou comparando as duas metades:

```bash
./scripts/diagnostico.sh | head -5
```

A linha `versao` é a do coletor. O rodapé da janela mostra a da janela; se as duas
diferirem, ele avisa e diz para rodar o `install.sh` — nesse caso o passo do
instalador não rodou.

## Antes de instalar, confira

- `echo $WSL_DISTRO_NAME` precisa retornar algo. Sem isso você não está no WSL.
- `python3 --version` — o coletor usa só a biblioteca padrão. Se faltar:
  `sudo apt install -y python3`.
- `kiro-cli whoami` — precisa estar logado. Sem isso a janela abre mas mostra
  falha no lugar dos números. Instalar o projeto ainda assim é válido.

## Verificar que funcionou

```bash
scripts/collect.sh --account-only
```

Deve imprimir um JSON com `account.plan_name` e `account.credits_used`. Se vier
`{"error": ...}`, a mensagem diz a causa.

A janela em si aparece com o título **kiro-eye-monitor**.

## Erros comuns

| Sintoma | Causa |
| --- | --- |
| `install.sh` reclama de `WSL_DISTRO_NAME` vazio | rodou fora do WSL |
| `git clone` diz `destination path already exists` | é atualização, não instalação; use a seção Atualizar |
| Rodapé da janela diz `janela vX, coletor vY` | fez `git pull` sem rodar o `install.sh` depois |
| Números novos no coletor e janela sem a mudança | mesma causa: a janela é uma cópia em `%LOCALAPPDATA%` |
| `{"error":"python3 nao encontrado..."}` | falta python3 na distro |
| Janela mostra "Falha: executavel nao encontrado: 'kiro-cli'" | kiro-cli não está no PATH da distro |
| Caixa de diálogo `distro WSL 'X' nao existe nesta maquina` | nome de distro errado; a própria mensagem lista as instaladas |
| Qualquer falha sem causa óbvia | rode `./scripts/diagnostico.sh` e leia a saída antes de mexer em qualquer coisa |
| PowerShell travado ao rodar um `.ps1` | tentou executar a partir de `\\wsl.localhost`; a instalação começa no WSL justamente por isso |

## Não faça

- Não rode `install.sh` pelo PowerShell nem por caminho UNC.
- Não clone de novo quando já existe instalação, e não clone em outro diretório
  para contornar o erro do `git clone`: a janela instalada aponta para o clone
  antigo, e você acabaria com duas cópias e uma atualização que não pega.
- Não pare no `git pull` ao atualizar. Sem o `install.sh`, a janela continua a
  antiga.
- Não apague o clone nem a pasta `%LOCALAPPDATA%\KiroEyeMonitor` para "limpar":
  o instalador já recria a segunda, e apagar não resolve falha nenhuma.
- Não pergunte ao usuário caminhos que o `install.sh` detecta sozinho. Use
  `--kiro-cli` ou `--sessions-dir` apenas quando a detecção falhar e você já
  souber o caminho certo.
- Não passe `-Distro Ubuntu` por palpite. O parâmetro é opcional: sem ele o app
  usa a distro padrão do WSL. Nomes como `Ubuntu-24.04` são comuns e `Ubuntu`
  cravado quebra a chamada do `wsl.exe`.
- Não commite nem faça push sem o usuário pedir.
- Não altere o `LICENSE` nem o titular do copyright.

## Rodar os testes (só se pedirem)

```bash
uv run --group dev pytest -q
```

Os testes do lado Windows usam Pester e precisam ser copiados para disco local
antes, porque o Pester 3 não roda a partir de caminho UNC. O runner
`windows/tools/Invoke-LocalPester.ps1` resume o resultado em uma linha, com uma
linha por falha, que é o formato legível quando a chamada parte do WSL. Veja o
README.
