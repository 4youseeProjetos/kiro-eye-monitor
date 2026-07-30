# Instruções para agentes

Este repositório instala uma janela no Windows que mostra o consumo de créditos
Kiro, lendo os dados de dentro do WSL.

Se um usuário pedir para instalar este projeto, siga o roteiro abaixo. Ele é
curto de propósito: quase tudo já está automatizado no `install.sh`.

## Instalar

Rode **de dentro do WSL** (não do PowerShell):

```bash
git clone https://github.com/4youseeProjetos/kiro-eye-monitor.git ~/kiro-eye-monitor
cd ~/kiro-eye-monitor
./install.sh --desktop
```

O `install.sh` detecta a distro, copia a janela para `%LOCALAPPDATA%\KiroEyeMonitor`,
cria o atalho na área de trabalho e abre o app. Use `--startup` se o usuário
quiser que abra junto com o Windows, e `--no-desktop` se ele não quiser atalho.

Não clone para dentro de `/mnt/c`: funciona, mas a leitura dos arquivos de sessão
fica lenta pelo sistema de arquivos do Windows.

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

A janela em si aparece com o título **Consumo Kiro**.

## Erros comuns

| Sintoma | Causa |
| --- | --- |
| `install.sh` reclama de `WSL_DISTRO_NAME` vazio | rodou fora do WSL |
| `{"error":"python3 nao encontrado..."}` | falta python3 na distro |
| Janela mostra "Falha: executavel nao encontrado: 'kiro-cli'" | kiro-cli não está no PATH da distro |
| PowerShell travado ao rodar um `.ps1` | tentou executar a partir de `\\wsl.localhost`; a instalação começa no WSL justamente por isso |

## Não faça

- Não rode `install.sh` pelo PowerShell nem por caminho UNC.
- Não commite nem faça push sem o usuário pedir.
- Não altere o `LICENSE` nem o titular do copyright.

## Rodar os testes (só se pedirem)

```bash
uv run --group dev pytest -q
```

Os testes do lado Windows usam Pester e precisam ser copiados para disco local
antes, porque o Pester 3 não roda a partir de caminho UNC. Veja o README.
