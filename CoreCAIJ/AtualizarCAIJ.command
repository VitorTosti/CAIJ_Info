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
BASE_URL="$(tr -d '\r\n' < "$SERVER_FILE" 2>/dev/null)"
BASE_URL="${BASE_URL%/}"
[[ "$BASE_URL" != http://* && "$BASE_URL" != https://* ]] && exit 0

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/caij-update.XXXXXX")" || exit 0
MANIFEST="$TMP_ROOT/manifest.json"
ZIP_FILE="$TMP_ROOT/caij-app.zip"
STAGE="$TMP_ROOT/stage"
BACKUP="$TMP_ROOT/backup"
mkdir -p "$STAGE" "$BACKUP"

cleanup() { rm -rf "$TMP_ROOT" >/dev/null 2>&1; }
trap cleanup EXIT

curl -fsS --max-time 5 "$BASE_URL/atualizacao/manifesto" -o "$MANIFEST" 2>/dev/null || exit 0
REMOTE_VERSION="$(sed -n 's/.*"version":"\([^"]*\)".*/\1/p' "$MANIFEST")"
EXPECTED_HASH="$(sed -n 's/.*"sha256":"\([^"]*\)".*/\1/p' "$MANIFEST" | tr '[:upper:]' '[:lower:]')"
PACKAGE_URL="$(sed -n 's/.*"packageUrl":"\([^"]*\)".*/\1/p' "$MANIFEST")"
LOCAL_VERSION="$(tr -d '\r\n' < "$VERSION_FILE" 2>/dev/null)"

[[ -z "$REMOTE_VERSION" || -z "$EXPECTED_HASH" || -z "$PACKAGE_URL" ]] && exit 0
[[ "$LOCAL_VERSION" == "$REMOTE_VERSION" ]] && exit 0
[[ "$PACKAGE_URL" != http://* && "$PACKAGE_URL" != https://* ]] && PACKAGE_URL="$BASE_URL/${PACKAGE_URL#/}"

curl -fsS --max-time 60 "$PACKAGE_URL" -o "$ZIP_FILE" 2>/dev/null || exit 0
ACTUAL_HASH="$(shasum -a 256 "$ZIP_FILE" 2>/dev/null | awk '{print tolower($1)}')"
[[ "$ACTUAL_HASH" != "$EXPECTED_HASH" ]] && exit 0
unzip -q "$ZIP_FILE" -d "$STAGE" 2>/dev/null || exit 0
LIST_FILE="$STAGE/_caij_update_files.txt"
[[ ! -f "$LIST_FILE" ]] && exit 0

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
  cp -p "$SOURCE" "$TARGET" || { FAILED=1; break; }
done < "$LIST_FILE"

if [[ "$FAILED" -eq 1 ]]; then
  while IFS= read -r RELATIVE; do [[ -f "$BACKUP/$RELATIVE" ]] && cp -p "$BACKUP/$RELATIVE" "$APP_ROOT/$RELATIVE"; done < "$COPIED_LIST"
  while IFS= read -r RELATIVE; do [[ -f "$APP_ROOT/$RELATIVE" ]] && rm -f "$APP_ROOT/$RELATIVE"; done < "$CREATED_LIST"
  exit 0
fi

print -rn -- "$REMOTE_VERSION" > "$VERSION_FILE"
chmod +x "$APP_ROOT/InfoNotebookMac.command" "$CORE_DIR/AtualizarCAIJ.command" 2>/dev/null
exit 0
