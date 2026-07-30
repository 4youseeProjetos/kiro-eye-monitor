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
# O PATH de um shell nao-interativo do wsl.exe nao inclui ~/.local/bin, onde
# fica o kiro-cli, por isso ele e reposto aqui. Somente o JSON vai para stdout.
set -eu

PATH="$HOME/.local/bin:$PATH"
export PATH

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PYTHON="${KIRO_USAGE_PYTHON:-python3}"

if ! command -v "$PYTHON" >/dev/null 2>&1; then
    printf '{"error":"python3 nao encontrado na distro; instale com: sudo apt install -y python3"}\n'
    exit 1
fi

cd "$PROJECT_DIR"
PYTHONPATH="$PROJECT_DIR/src" exec "$PYTHON" -m kiro_eye_monitor.main "$@"
