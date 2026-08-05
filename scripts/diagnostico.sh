#!/usr/bin/env bash
# Retrato do ambiente para diagnosticar falha na maquina de outro desenvolvedor.
#
# Rode de dentro do WSL, na raiz do repositorio, e mande a saida inteira:
#   ./scripts/diagnostico.sh
#
# Nao expoe credencial: mostra caminhos, versoes e as ultimas falhas
# registradas, nunca o conteudo das sessoes nem token de login.
set -uo pipefail

PROJECT_DIR=$(cd -- "$(dirname -- "$0")/.." && pwd)
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/kiro-eye-monitor/config"
LOG="${XDG_STATE_HOME:-$HOME/.local/state}/kiro-eye-monitor/erros.jsonl"
ULTIMAS_FALHAS=5

secao() {
    printf '\n== %s ==\n' "$1"
}

valor() {
    # valor <rotulo> <conteudo>
    printf '%-18s %s\n' "$1" "${2:-(vazio)}"
}

ambiente() {
    secao 'ambiente'
    valor 'versao' "$(sed -n 's/^__version__ = "\(.*\)"$/\1/p' \
        "$PROJECT_DIR/src/kiro_eye_monitor/__init__.py")"
    valor 'commit' "$(git -C "$PROJECT_DIR" rev-parse --short HEAD 2>/dev/null || echo '(sem git)')"
    valor 'distro' "${WSL_DISTRO_NAME:-(fora do WSL)}"
    valor 'kernel' "$(uname -r)"
    valor 'wsl interop' "$([ -e /run/WSL ] && echo presente || echo ausente)"
    valor 'python3' "$(command -v python3 || echo '(ausente)')"
    valor 'versao python' "$(python3 --version 2>&1 || true)"
    valor 'kiro-cli' "$(command -v kiro-cli || echo '(fora do PATH)')"
    valor 'projeto' "$PROJECT_DIR"
    valor 'PATH' "$PATH"
}

discos_do_windows() {
    secao 'discos do Windows montados'
    awk '$3 == "9p" || $3 == "drvfs" || $3 == "virtiofs" { printf "%-24s %s\n", $2, $3 }' /proc/mounts
}

configuracao() {
    secao 'configuracao gravada pelo install.sh'
    if [ -f "$CONFIG" ]; then
        cat "$CONFIG"
    else
        printf '%s nao existe — rode ./install.sh\n' "$CONFIG"
    fi
}

sessoes() {
    secao 'sessoes do kiro-cli'
    local dir="${KIRO_HOME:-$HOME/.kiro}/sessions/cli"
    if [ -d "$dir" ]; then
        valor 'diretorio' "$dir"
        valor 'arquivos json' "$(find "$dir" -maxdepth 1 -name '*.json' | wc -l)"
    else
        valor 'diretorio' "$dir (inexistente)"
    fi
}

coleta_de_teste() {
    secao 'coleta de teste (--account-only)'
    # PATH reduzido de proposito: reproduz o shell que o wsl.exe usa ao chamar
    # a ponte a partir do Windows, onde a falha costuma aparecer.
    env -i HOME="$HOME" PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        WSL_DISTRO_NAME="${WSL_DISTRO_NAME:-}" \
        timeout 90 "$PROJECT_DIR/scripts/collect.sh" --account-only 2>&1 |
        cut -c1-400
    printf 'codigo de saida: %s\n' "${PIPESTATUS[0]}"
}

ultimas_falhas() {
    secao "ultimas $ULTIMAS_FALHAS falhas registradas"
    if [ -f "$LOG" ]; then
        valor 'log' "$LOG"
        tail -n "$ULTIMAS_FALHAS" "$LOG"
    else
        printf 'nenhuma falha registrada em %s\n' "$LOG"
    fi
}

main() {
    printf 'diagnostico kiro-eye-monitor — %s\n' "$(date -Is)"
    ambiente
    discos_do_windows
    configuracao
    sessoes
    coleta_de_teste
    ultimas_falhas
    printf '\nfim do diagnostico\n'
}

main "$@"
