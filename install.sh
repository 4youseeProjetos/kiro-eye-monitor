#!/usr/bin/env bash
# Instala e abre a janela de consumo Kiro.
#
# Rode de dentro do WSL, na raiz do repositorio:
#   ./install.sh
#
# A instalacao comeca aqui, e nao no PowerShell, por dois motivos: o coletor le
# os dados de dentro do WSL, e o PowerShell 5.1 trava ao executar scripts a
# partir de \\wsl.localhost.
set -euo pipefail

PROJECT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
# Preenchidos por resolver_windows: nada de caminho cravado. A letra do disco do
# Windows pode nao ser C:, e a raiz de montagem muda com "root =" no
# /etc/wsl.conf, entao os dois sao descobertos em tempo de execucao.
WIN_ROOT=''
POWERSHELL=''
APP_TITLE='kiro-eye-monitor'
REPO_URL='https://github.com/4youseeProjetos/kiro-eye-monitor.git'
WINDOW_SCRIPT='Start-KiroEyeMonitor.ps1'
ADD_DESKTOP=''
ADD_STARTUP=''
ASSUME_YES=''
KIRO_CLI_PATH=''
SESSIONS_PATH=''

falhar() {
    printf 'erro: %s\n' "$1" >&2
    exit 1
}

uso() {
    cat <<'FIM'
uso: ./install.sh [opcoes]

  --desktop      cria atalho na area de trabalho sem perguntar
  --no-desktop   nao cria atalho na area de trabalho
  --startup      abre junto com o Windows
  --kiro-cli C   caminho do kiro-cli, se a deteccao nao achar
  --sessions-dir D  diretorio de sessoes do kiro-cli, se nao for o padrao
  -y, --yes      aceita os padroes (atalho na area de trabalho: sim)
  -h, --help     mostra esta ajuda
FIM
}

ler_argumentos() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --desktop) ADD_DESKTOP='sim' ;;
            --no-desktop) ADD_DESKTOP='nao' ;;
            --startup) ADD_STARTUP='sim' ;;
            --kiro-cli) shift; [ $# -gt 0 ] || falhar '--kiro-cli exige um caminho'; KIRO_CLI_PATH="$1" ;;
            --sessions-dir) shift; [ $# -gt 0 ] || falhar '--sessions-dir exige um caminho'; SESSIONS_PATH="$1" ;;
            -y|--yes) ASSUME_YES='sim' ;;
            -h|--help) uso; exit 0 ;;
            *) uso >&2; falhar "argumento desconhecido: $1" ;;
        esac
        shift
    done
}

listar_discos_windows() {
    # Pontos de montagem dos discos do Windows, como o WSL os expoe.
    awk '$3 == "9p" || $3 == "drvfs" || $3 == "virtiofs" { print $2 }' /proc/mounts
}

resolver_windows() {
    # Acha um disco montado que contenha a instalacao do Windows.
    local disco
    for disco in $(listar_discos_windows); do
        if [ -x "$disco/Windows/System32/WindowsPowerShell/v1.0/powershell.exe" ]; then
            WIN_ROOT="$disco"
            POWERSHELL="$disco/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
            return 0
        fi
    done
    # Sobra o PATH de interoperabilidade, que o wsl.conf pode ter desligado.
    POWERSHELL=$(command -v powershell.exe 2>/dev/null || true)
    [ -n "$POWERSHELL" ] || return 1
    WIN_ROOT='/'
}

powershell_em() {
    # powershell_em <argumentos...> — roda de um diretorio que o Windows enxerga,
    # porque o PowerShell reclama quando o diretorio atual e um caminho UNC.
    (cd "$WIN_ROOT" && "$POWERSHELL" "$@")
}

exigir_wsl() {
    if [ -z "${WSL_DISTRO_NAME:-}" ]; then
        printf 'erro: este instalador roda obrigatoriamente dentro do WSL.\n' >&2
        printf '      WSL_DISTRO_NAME esta vazio, ou seja, nao ha distro em volta deste shell.\n' >&2
        printf '      O coletor le os dados de dentro do WSL e o PowerShell 5.1 trava ao\n' >&2
        printf '      executar scripts a partir de \\\\wsl.localhost, entao nao ha versao\n' >&2
        printf '      equivalente para o PowerShell.\n\n' >&2
        printf '      Do terminal do Windows, entre no WSL e repita a instalacao:\n' >&2
        printf "        wsl.exe -- bash -lc 'cd ~ && git clone %s kiro-eye-monitor && cd kiro-eye-monitor && ./install.sh --desktop'\n" \
            "$REPO_URL" >&2
        exit 1
    fi
    resolver_windows ||
        falhar "powershell.exe nao encontrado nos discos do Windows ($(listar_discos_windows | tr '\n' ' ')); a interoperabilidade com o Windows esta desligada em /etc/wsl.conf?"
}

exigir_python() {
    command -v python3 >/dev/null 2>&1 ||
        falhar 'python3 nao encontrado; instale com: sudo apt install -y python3'
}

avisar_sobre_kiro_cli() {
    command -v kiro-cli >/dev/null 2>&1 && return 0
    printf 'aviso: kiro-cli nao esta no PATH desta distro.\n'
    printf '       A janela abre, mas mostra falha ate o kiro-cli ser instalado e logado.\n'
}

detectar_kiro_cli() {
    # O shell de login do desenvolvedor conhece o PATH completo; o shell que o
    # wsl.exe usa para chamar a ponte, nao. Por isso o caminho absoluto e
    # descoberto aqui e gravado na configuracao.
    local achado=''
    achado=$(command -v kiro-cli 2>/dev/null || true)
    [ -n "$achado" ] || achado=$("$SHELL" -lc 'command -v kiro-cli' 2>/dev/null || true)
    printf '%s' "$achado"
}

detectar_sessoes() {
    # Respeita KIRO_HOME, que o proprio kiro-cli usa para mudar de lugar.
    local base="${KIRO_HOME:-$HOME/.kiro}"
    [ -d "$base/sessions/cli" ] && printf '%s' "$base/sessions/cli"
}

perguntar_caminho() {
    # perguntar_caminho <pergunta> — vazio se nao houver terminal, para nao
    # travar instalacao por agente nem com -y.
    local resposta=''
    [ -t 0 ] || return 0
    [ -n "$ASSUME_YES" ] && return 0
    printf '%s\n' "$1" >&2
    printf 'caminho (Enter para deixar em branco): ' >&2
    read -r resposta || resposta=''
    printf '%s' "$resposta"
}

resolver_kiro_cli() {
    [ -n "$KIRO_CLI_PATH" ] && return 0
    KIRO_CLI_PATH=$(detectar_kiro_cli)
    [ -n "$KIRO_CLI_PATH" ] && return 0
    KIRO_CLI_PATH=$(perguntar_caminho 'Nao achei o kiro-cli. Se ele existe nesta distro, informe o caminho.')
}

resolver_sessoes() {
    [ -n "$SESSIONS_PATH" ] && return 0
    SESSIONS_PATH=$(detectar_sessoes)
    [ -n "$SESSIONS_PATH" ] && return 0
    SESSIONS_PATH=$(perguntar_caminho 'Nao achei ~/.kiro/sessions/cli. Informe o caminho, se souber.')
}

validar_caminhos() {
    if [ -n "$KIRO_CLI_PATH" ] && [ ! -x "$KIRO_CLI_PATH" ]; then
        falhar "kiro-cli informado nao e executavel: $KIRO_CLI_PATH"
    fi
    if [ -n "$SESSIONS_PATH" ] && [ ! -d "$SESSIONS_PATH" ]; then
        falhar "diretorio de sessoes informado nao existe: $SESSIONS_PATH"
    fi
}

gravar_configuracao() {
    # Lida pelo scripts/collect.sh a cada coleta.
    local config="${XDG_CONFIG_HOME:-$HOME/.config}/kiro-eye-monitor/config"
    mkdir -p "$(dirname "$config")"
    {
        printf '# Gerado por install.sh em %s\n' "$(date -Is)"
        [ -n "$KIRO_CLI_PATH" ] && printf 'KIRO_CLI=%s\n' "$KIRO_CLI_PATH"
        [ -n "$SESSIONS_PATH" ] && printf 'SESSIONS_DIR=%s\n' "$SESSIONS_PATH"
        printf 'PYTHON=%s\n' "$(command -v python3)"
    } >"$config"
    printf 'config: %s\n' "$config"
    [ -n "$KIRO_CLI_PATH" ] && printf 'kiro-cli: %s\n' "$KIRO_CLI_PATH"
    [ -n "$SESSIONS_PATH" ] && printf 'sessoes: %s\n' "$SESSIONS_PATH"
    return 0
}

perguntar() {
    # perguntar <pergunta> <padrao sim|nao>
    local pergunta="$1" padrao="$2" resposta=''
    if [ -n "$ASSUME_YES" ] || [ ! -t 0 ]; then
        printf '%s [%s]\n' "$pergunta" "$padrao"
        [ "$padrao" = 'sim' ] && return 0 || return 1
    fi
    printf '%s [S/n] ' "$pergunta"
    read -r resposta || resposta=''
    case "${resposta:-s}" in
        [sS]*|'') return 0 ;;
        *) return 1 ;;
    esac
}

resolver_desktop() {
    [ -n "$ADD_DESKTOP" ] && return 0
    if perguntar 'Criar atalho na area de trabalho?' 'sim'; then
        ADD_DESKTOP='sim'
    else
        ADD_DESKTOP='nao'
    fi
}

local_appdata_windows() {
    # Pergunta ao proprio Windows para nao chutar o nome do usuario.
    powershell_em -NoProfile -Command '[Console]::Out.Write($env:LOCALAPPDATA)' |
        tr -d '\r\0'
}

encerrar_instancia_aberta() {
    # A janela aberta mantem assets/eye.ico bloqueado, impedindo a sobrescrita.
    #
    # A busca e pela linha de comando do processo, e nao pelo titulo da janela:
    # o titulo pode mudar entre versoes, e uma instancia com titulo antigo
    # sobreviveria ao encerramento e travaria a copia.
    powershell_em -NoProfile -Command \
        "Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" |
         Where-Object { \$_.CommandLine -like '*$WINDOW_SCRIPT*' } |
         ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }" >/dev/null 2>&1 || true
    sleep 1
}

copiar_janela() {
    # copiar_janela <destino wsl>
    local destino="$1"
    rm -rf "$destino"
    mkdir -p "$destino"
    cp -r "$PROJECT_DIR/windows/." "$destino/"
    rm -rf "$destino/tests" "$destino/tools"
}

gerar_atalhos() {
    # gerar_atalhos <install dir windows>
    local instalacao="$1"
    local opcoes=()
    [ "$ADD_DESKTOP" = 'sim' ] && opcoes+=('-AddToDesktop')
    [ -n "$ADD_STARTUP" ] && opcoes+=('-AddToStartup')
    powershell_em -NoProfile -ExecutionPolicy Bypass \
        -File "$instalacao\\New-KiroEyeMonitorLauncher.ps1" \
        -BridgePath "$PROJECT_DIR/scripts/collect.sh" \
        -Distro "$WSL_DISTRO_NAME" \
        -InstallDir "$instalacao" \
        "${opcoes[@]+"${opcoes[@]}"}"
}

abrir_app() {
    # abrir_app <install dir windows>
    powershell_em -NoProfile -Command \
        "Start-Process -FilePath '$1\\Start-KiroEyeMonitor.cmd' -WindowStyle Hidden" >/dev/null 2>&1
}

atualizar_cache_de_icones() {
    # O Explorer guarda o icone dos atalhos em iconcache_*.db e continuaria
    # mostrando a versao anterior depois de trocar o eye.ico. O ie4uinit
    # recarrega os icones do shell sem reiniciar o Explorer.
    powershell_em -NoProfile -Command \
        'Start-Process -FilePath "$env:SystemRoot\System32\ie4uinit.exe" -ArgumentList "-show" -Wait' \
        >/dev/null 2>&1 || true
}

main() {
    ler_argumentos "$@"
    exigir_wsl
    exigir_python
    chmod +x "$PROJECT_DIR/scripts/collect.sh"

    printf 'distro: %s\n' "$WSL_DISTRO_NAME"
    avisar_sobre_kiro_cli
    resolver_kiro_cli
    resolver_sessoes
    validar_caminhos
    gravar_configuracao
    resolver_desktop

    local instalacao_win instalacao_wsl
    instalacao_win="$(local_appdata_windows)\\KiroEyeMonitor"
    instalacao_wsl=$(wslpath -u "$instalacao_win")

    encerrar_instancia_aberta
    copiar_janela "$instalacao_wsl"
    printf 'instalado: %s\n' "$instalacao_win"
    gerar_atalhos "$instalacao_win"
    atualizar_cache_de_icones

    abrir_app "$instalacao_win"
    printf '\nPronto. A janela ja esta abrindo.\n'
    printf 'Para abrir depois: atalho "%s" ou %s\\Start-KiroEyeMonitor.cmd\n' "$APP_TITLE" "$instalacao_win"
}

main "$@"
