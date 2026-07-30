#!/bin/sh
# Ponte estavel entre a janela do Windows e o coletor.
#
# Chamada de la como:
#   wsl.exe -d <distro> -- <projeto>/scripts/collect.sh [--account-only]
#
# Usa o python3 da distro, sem gerenciador de pacote: o coletor nao tem
# dependencia de runtime alem da biblioteca padrao. O uv e usado somente para
# rodar os testes.
#
# Os caminhos do kiro-cli e do diretorio de sessoes vem do arquivo de
# configuracao gravado pelo install.sh. Sem isso sobraria adivinhar o PATH, que
# num shell nao-interativo do wsl.exe nao inclui ~/.local/bin.
set -eu

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/kiro-eye-monitor/config"
LOG="${XDG_STATE_HOME:-$HOME/.local/state}/kiro-eye-monitor/erros.jsonl"

PATH="$HOME/.local/bin:$PATH"
export PATH

ler_config() {
    # ler_config <CHAVE> — ultima ocorrencia da chave, ou vazio.
    [ -f "$CONFIG" ] || return 0
    sed -n "s/^$1=//p" "$CONFIG" | tail -n 1
}

registrar_falha() {
    # registrar_falha <mensagem> — uma linha JSON, no mesmo log do coletor.
    mkdir -p "$(dirname "$LOG")" 2>/dev/null || return 0
    printf '{"quando":"%s","mensagem":"%s","ambiente":{"origem":"collect.sh","distro":"%s","path":"%s","config":"%s"}}\n' \
        "$(date -Is)" "$1" "${WSL_DISTRO_NAME:-}" "$PATH" "$CONFIG" >>"$LOG" 2>/dev/null || true
}

responder_falha() {
    # responder_falha <mensagem> — JSON que a janela sabe exibir, e log.
    registrar_falha "$1"
    printf '{"error":"%s","log_path":"%s"}\n' "$1" "$LOG"
    exit 1
}

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PYTHON="${KIRO_USAGE_PYTHON:-$(ler_config PYTHON)}"
PYTHON="${PYTHON:-python3}"

if ! command -v "$PYTHON" >/dev/null 2>&1; then
    responder_falha "python3 nao encontrado na distro; instale com: sudo apt install -y python3"
fi

set -- "$@"
KIRO_CLI=$(ler_config KIRO_CLI)
[ -n "$KIRO_CLI" ] && set -- "$@" --kiro-cli "$KIRO_CLI"
SESSIONS_DIR=$(ler_config SESSIONS_DIR)
[ -n "$SESSIONS_DIR" ] && set -- "$@" --sessions-dir "$SESSIONS_DIR"

cd "$PROJECT_DIR"
PYTHONPATH="$PROJECT_DIR/src" exec "$PYTHON" -m kiro_eye_monitor.main "$@"
