#!/bin/zsh

set +e

CORE_DIR="${0:A:h}"
APP_ROOT="${CORE_DIR:h}"
if [[ "$1" == "--app-root" && -n "$2" ]]; then
  APP_ROOT="$2"
  CORE_DIR="$APP_ROOT/CoreCAIJ"
fi

SERVER_FILE="$CORE_DIR/caij_servidor_url.txt"
VERSION_FILE="$CORE_DIR/caij_versao_app.txt"
STATUS_FILE="$CORE_DIR/caij_atualizacao_status.txt"
CONFIGURED_URL="$(tr -d '\r\n' < "$SERVER_FILE" 2>/dev/null)"
CONFIGURED_URL="${CONFIGURED_URL%/}"

update_status() {
  print -r -- "$(date '+%Y-%m-%d %H:%M:%S') | $1" > "$STATUS_FILE" 2>/dev/null
}

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/caij-update.XXXXXX")" || exit 0
MANIFEST="$TMP_ROOT/manifest.json"
ZIP_FILE="$TMP_ROOT/caij-app.zip"
STAGE="$TMP_ROOT/stage"
BACKUP="$TMP_ROOT/backup"
mkdir -p "$STAGE" "$BACKUP"

cleanup() { rm -rf "$TMP_ROOT" >/dev/null 2>&1; }
trap cleanup EXIT

BASE_URL=""
SERVER_CANDIDATES=(
  "$CONFIGURED_URL"
  "http://INFOCAIJ.local:9100"
  "http://INFOCAIJ:9100"
  "http://192.168.15.11:9100"
)
for CANDIDATE in "${SERVER_CANDIDATES[@]}"; do
  CANDIDATE="${CANDIDATE%/}"
  [[ "$CANDIDATE" != http://* && "$CANDIDATE" != https://* ]] && continue
  if curl -fsS --connect-timeout 2 --max-time 5 "$CANDIDATE/atualizacao/manifesto" -o "$MANIFEST" 2>/dev/null; then
    BASE_URL="$CANDIDATE"
    print -rn -- "$BASE_URL" > "$SERVER_FILE" 2>/dev/null
    break
  fi
done
if [[ -z "$BASE_URL" ]]; then
  update_status "Servidor de atualizacoes indisponivel; versao local mantida."
  exit 0
fi
REMOTE_VERSION="$(sed -n 's/.*"version":"\([^"]*\)".*/\1/p' "$MANIFEST")"
EXPECTED_HASH="$(sed -n 's/.*"sha256":"\([^"]*\)".*/\1/p' "$MANIFEST" | tr '[:upper:]' '[:lower:]')"
PACKAGE_URL="$(sed -n 's/.*"packageUrl":"\([^"]*\)".*/\1/p' "$MANIFEST")"
LOCAL_VERSION="$(tr -d '\r\n' < "$VERSION_FILE" 2>/dev/null)"

if [[ -z "$REMOTE_VERSION" || -z "$EXPECTED_HASH" || -z "$PACKAGE_URL" ]]; then
  update_status "Manifesto de atualizacao invalido."
  exit 0
fi
if [[ "$LOCAL_VERSION" == "$REMOTE_VERSION" ]]; then
  update_status "Versao $LOCAL_VERSION ja esta atualizada."
  exit 0
fi
[[ "$PACKAGE_URL" != http://* && "$PACKAGE_URL" != https://* ]] && PACKAGE_URL="$BASE_URL/${PACKAGE_URL#/}"

if ! curl -fsS --max-time 60 "$PACKAGE_URL" -o "$ZIP_FILE" 2>/dev/null; then
  update_status "Falha ao baixar a versao $REMOTE_VERSION."
  exit 0
fi
ACTUAL_HASH="$(shasum -a 256 "$ZIP_FILE" 2>/dev/null | awk '{print tolower($1)}')"
if [[ "$ACTUAL_HASH" != "$EXPECTED_HASH" ]]; then
  update_status "Pacote $REMOTE_VERSION rejeitado: SHA256 divergente."
  exit 0
fi
if ! unzip -q "$ZIP_FILE" -d "$STAGE" 2>/dev/null; then
  update_status "Pacote $REMOTE_VERSION nao pode ser extraido."
  exit 0
fi
LIST_FILE="$STAGE/_caij_update_files.txt"
if [[ ! -f "$LIST_FILE" ]]; then
  update_status "Pacote $REMOTE_VERSION sem lista de arquivos."
  exit 0
fi

COPIED_LIST="$TMP_ROOT/copied.txt"
CREATED_LIST="$TMP_ROOT/created.txt"
: > "$COPIED_LIST"
: > "$CREATED_LIST"
FAILED=0

while IFS= read -r RAW_PATH || [[ -n "$RAW_PATH" ]]; do
  RELATIVE="${RAW_PATH//$'\r'/}"
  [[ -z "$RELATIVE" ]] && continue
  case "$RELATIVE" in
    /*|*"../"*|".."|*"/..") FAILED=1; break ;;
    CoreCAIJ/caij_historico_notebooks.json|CoreCAIJ/caij_os_counter.txt|CoreCAIJ/caij_os_por_serial.json|CoreCAIJ/caij_servidor_url.txt|CoreCAIJ/caij_modelos_manuais.json|CoreCAIJ/caij_ultimo_modelo_manual.json) FAILED=1; break ;;
  esac
  SOURCE="$STAGE/$RELATIVE"
  TARGET="$APP_ROOT/$RELATIVE"
  [[ ! -f "$SOURCE" ]] && FAILED=1 && break
  mkdir -p "${TARGET:h}" || { FAILED=1; break; }
  if [[ -f "$TARGET" ]]; then
    mkdir -p "$BACKUP/${RELATIVE:h}" || { FAILED=1; break; }
    cp -p "$TARGET" "$BACKUP/$RELATIVE" || { FAILED=1; break; }
    print -r -- "$RELATIVE" >> "$COPIED_LIST"
  else
    print -r -- "$RELATIVE" >> "$CREATED_LIST"
  fi
  # Grave ao lado e renomeie. Isso evita truncar o proprio atualizador ou o
  # inicializador enquanto o zsh ainda esta executando esses arquivos.
  TEMP_TARGET="${TARGET}.caij-new.$$"
  rm -f "$TEMP_TARGET" >/dev/null 2>&1
  cp -p "$SOURCE" "$TEMP_TARGET" || { FAILED=1; break; }
  mv -f "$TEMP_TARGET" "$TARGET" || { rm -f "$TEMP_TARGET"; FAILED=1; break; }
done < "$LIST_FILE"

if [[ "$FAILED" -eq 1 ]]; then
  while IFS= read -r RELATIVE; do [[ -f "$BACKUP/$RELATIVE" ]] && cp -p "$BACKUP/$RELATIVE" "$APP_ROOT/$RELATIVE"; done < "$COPIED_LIST"
  while IFS= read -r RELATIVE; do [[ -f "$APP_ROOT/$RELATIVE" ]] && rm -f "$APP_ROOT/$RELATIVE"; done < "$CREATED_LIST"
  update_status "Falha ao instalar $REMOTE_VERSION; arquivos anteriores restaurados."
  exit 0
fi

print -rn -- "$REMOTE_VERSION" > "$VERSION_FILE"
chmod +x "$APP_ROOT/InfoNotebookMac.command" "$CORE_DIR/AtualizarCAIJ.command" 2>/dev/null
update_status "Versao $REMOTE_VERSION instalada com sucesso."
# Codigo especial: o launcher deve reiniciar para usar imediatamente os
# arquivos que acabaram de substituir a versao carregada na memoria.
exit 10
