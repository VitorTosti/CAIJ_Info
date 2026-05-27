#!/bin/zsh

set +e

DIR="${0:A:h}"
CORE="$DIR/CoreCAIJ"
OS_FILE="$CORE/caij_os_counter.txt"
SERVER_FILE="$CORE/caij_servidor_url.txt"
HISTORY_FILE="$CORE/caij_historico_notebooks.json"
PORTABLE_LOG_ROOT="${DIR:h}/CAIJ-Registros"
FALLBACK_LOG_ROOT="$HOME/Documents/CAIJ/Registros"
SERVER_CACHE=""
LAST_SERVER_STATUS="nao verificado"
LAST_OS_SYNC=""

hide_windows_launchers_in_finder() {
  chflags hidden "$DIR/InfoNotebook.bat" "$DIR/TestarNotebook.bat" >/dev/null 2>&1
}

trim() {
  sed 's/^[[:space:]]*//;s/[[:space:]]*$//' <<< "$1"
}

pause_close() {
  echo ""
  read "dummy?Pressione Enter para fechar..."
}

ensure_dirs() {
  mkdir -p "$CORE" >/dev/null 2>&1
}

read_os_number() {
  local n
  n="$(cat "$OS_FILE" 2>/dev/null | tr -dc '0-9')"
  if [[ -z "$n" || "$n" -lt 235 ]]; then
    n=235
  fi
  echo "$n"
}

OS_NUMBER="$(read_os_number)"

save_os_number() {
  OS_NUMBER="$1"
  echo "$OS_NUMBER" > "$OS_FILE" 2>/dev/null
}

format_os() {
  echo "C000$1"
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; :a;N;$!ba;s/\n/\\n/g'
}

json_value_or_null() {
  local v="$1"
  if [[ -z "$v" ]]; then
    printf 'null'
  else
    printf '"%s"' "$(json_escape "$v")"
  fi
}

get_log_root() {
  mkdir -p "$PORTABLE_LOG_ROOT" >/dev/null 2>&1
  if [[ -w "$PORTABLE_LOG_ROOT" ]]; then
    echo "$PORTABLE_LOG_ROOT"
    return
  fi
  mkdir -p "$FALLBACK_LOG_ROOT" >/dev/null 2>&1
  echo "$FALLBACK_LOG_ROOT"
}

sp_first() {
  local text="$1"
  local key="$2"
  awk -F': ' -v key="$key" '$1 ~ "^[[:space:]]*" key "$" { print $2; exit }' <<< "$text"
}

sp_match() {
  local text="$1"
  local pattern="$2"
  awk -F': ' -v pattern="$pattern" 'BEGIN { IGNORECASE=1 } $1 ~ pattern { print $2; exit }' <<< "$text"
}

normalize_size() {
  local raw="$1"
  local gb
  raw="$(tr ',' '.' <<< "$raw")"
  if [[ "$raw" =~ '([0-9]+)(\.[0-9]+)?[[:space:]]*TB' ]]; then
    local tb="${match[1]}"
    if [[ "$tb" == "1" ]]; then
      echo "1TB"
    elif [[ "$tb" == "2" ]]; then
      echo "2TB"
    else
      echo "${tb}TB"
    fi
    return
  fi
  gb="$(sed -nE 's/^[^0-9]*([0-9]+)(\.[0-9]+)?[[:space:]]*GB.*/\1/p' <<< "$raw" | head -n 1)"
  if [[ -z "$gb" ]]; then
    echo "$raw"
  elif (( gb >= 110 && gb <= 130 )); then
    echo "128GB"
  elif (( gb >= 220 && gb <= 260 )); then
    echo "256GB"
  elif (( gb >= 460 && gb <= 520 )); then
    echo "512GB"
  elif (( gb >= 900 && gb <= 1050 )); then
    echo "1TB"
  elif (( gb >= 1800 && gb <= 2100 )); then
    echo "2TB"
  else
    echo "${gb}GB"
  fi
}

collect_info() {
  local hw displays storage power
  hw="$(system_profiler SPHardwareDataType 2>/dev/null)"
  displays="$(system_profiler SPDisplaysDataType 2>/dev/null)"
  storage="$(system_profiler SPStorageDataType 2>/dev/null)"
  power="$(system_profiler SPPowerDataType 2>/dev/null)"

  MODEL_NAME="$(sp_match "$hw" "Model Name|Nome.*Modelo")"
  MODEL_ID="$(sp_match "$hw" "Model Identifier|Identificador.*Modelo")"
  SERIAL="$(sp_match "$hw" "Serial Number|Numero.*Serie|rie")"
  CHIP="$(sp_match "$hw" "^ *Chip$")"
  if [[ -z "$CHIP" ]]; then
    CHIP="$(sp_match "$hw" "Processor Name|Nome do Processador|Processador")"
  fi
  CORES="$(sp_match "$hw" "Total Number of Cores|Nucleos|cleos")"
  MEMORY="$(sp_match "$hw" "Memory|Mem")"
  GPU="$(sp_match "$displays" "Chipset Model|Modelo do Chipset")"
  RESOLUTION="$(sp_match "$displays" "Resolution|Resol")"
  STORAGE_RAW="$(sp_match "$storage" "Capacity|Capacidade")"
  if [[ -z "$STORAGE_RAW" ]]; then
    STORAGE_RAW="$(diskutil info / 2>/dev/null | awk -F': *' '/Disk Size|Tamanho do Disco/ { print $2; exit }')"
  fi
  STORAGE_SIZE="$(normalize_size "$STORAGE_RAW")"
  DISK_NAME="$(sp_match "$storage" "Medium Type|Tipo de Midia|Media Type|Nome do Dispositivo|Device Name")"
  BAT_CAP="$(sp_match "$power" "Maximum Capacity|Capacidade.*xima")"
  BAT_COND="$(sp_match "$power" "Condition|Condi")"

  if [[ -z "$MODEL_NAME" ]]; then MODEL_NAME="MacBook"; fi
  if [[ "$CHIP" =~ 'Apple[[:space:]]+(M[0-9])' && "$MODEL_NAME" != *"${match[1]}"* ]]; then
    MODEL="Apple $MODEL_NAME ${match[1]}"
  else
    MODEL="Apple $MODEL_NAME"
  fi
  if [[ -z "$SERIAL" ]]; then
    SERIAL="$(ioreg -l 2>/dev/null | awk -F' = ' '/IOPlatformSerialNumber/ { gsub(/"/, "", $2); print $2; exit }')"
  fi
  if [[ -z "$SERIAL" ]]; then SERIAL="N/A"; fi
  if [[ -z "$CHIP" ]]; then CHIP="N/A"; fi
  if [[ -n "$CORES" ]]; then NUCLEOS="$CORES nucleos"; else NUCLEOS="N/A"; fi
  if [[ "$MEMORY" =~ '([0-9]+)[[:space:]]*GB' ]]; then
    RAM="${match[1]}GB Unificada"
  elif [[ -n "$MEMORY" ]]; then
    RAM="$MEMORY"
  else
    RAM="N/A"
  fi
  if [[ -z "$GPU" && "$CHIP" == Apple* ]]; then GPU="$CHIP"; fi
  if [[ -n "$GPU" ]]; then GPU="$GPU (Integrada)"; else GPU="Nao identificada"; fi
  if [[ -z "$RESOLUTION" ]]; then RESOLUTION="Nao detectada"; fi
  if [[ -z "$STORAGE_SIZE" ]]; then STORAGE_SIZE="N/A"; fi
  if [[ -n "$DISK_NAME" && "$DISK_NAME" != "SSD" ]]; then
    DISK="$STORAGE_SIZE SSD - $DISK_NAME"
  else
    DISK="$STORAGE_SIZE SSD - Apple Storage"
  fi
  if [[ -n "$BAT_CAP" ]]; then
    BATTERY="$BAT_CAP"
    if [[ -n "$BAT_COND" ]]; then BATTERY="$BATTERY ($BAT_COND)"; fi
  else
    BATTERY="N/A"
  fi
}

cpu_short() {
  local cpu="$1"
  if [[ "$cpu" =~ 'Apple[[:space:]]+(M[0-9][^ ]*)' ]]; then
    echo "Apple ${match[1]}"
  elif [[ "$cpu" =~ 'i([3579]).*([0-9]{4,5})' ]]; then
    local model="${match[2]}"
    if [[ ${#model} -ge 5 ]]; then
      echo "I${match[1]} ${model[1,2]}"
    else
      echo "I${match[1]} ${model[1,1]}"
    fi
  else
    echo "$cpu"
  fi
}

ram_short() {
  local ram="$1"
  if [[ "$ram" =~ '([0-9]+)GB' ]]; then
    if grep -qi 'Unificada' <<< "$ram"; then
      echo "${match[1]}GB Unificada"
    elif [[ "$ram" =~ '(LPDDR[345]|DDR[345])' ]]; then
      echo "${match[1]}GB ${match[2]:u}"
    else
      echo "${match[1]}GB"
    fi
  else
    echo "$ram"
  fi
}

gpu_short() {
  local gpu="$1"
  if [[ -z "$gpu" || "$gpu" == "N/A" || "$gpu" == "Nao identificada" || "$gpu" == "Não identificada" ]]; then
    echo ""
  elif [[ "$gpu" =~ 'Apple[[:space:]]+(M[0-9][^ (]*)' ]]; then
    echo "Apple ${match[1]}"
  else
    echo "${gpu[1,28]}"
  fi
}

disk_short() {
  local disk="$1"
  if grep -qi '1TB' <<< "$disk"; then echo "1TB SSD"
  elif grep -Eq '512GB|494GB|500GB' <<< "$disk"; then echo "512GB SSD"
  elif grep -Eq '256GB|250GB|240GB' <<< "$disk"; then echo "256GB SSD"
  elif grep -Eq '128GB|120GB' <<< "$disk"; then echo "128GB SSD"
  else echo "${disk[1,18]}"
  fi
}

server_candidates() {
  if [[ -s "$SERVER_FILE" ]]; then
    local cfg
    cfg="$(trim "$(cat "$SERVER_FILE")")"
    if [[ "$cfg" == http* ]]; then echo "${cfg%/}"; else echo "http://$cfg:9100"; fi
  fi
  if [[ -n "$CAIJ_SERVIDOR_URL" ]]; then echo "${CAIJ_SERVIDOR_URL%/}"; fi
  if [[ -n "$CAIJ_SERVIDOR_IP" ]]; then echo "http://$CAIJ_SERVIDOR_IP:9100"; fi
  echo "http://192.168.15.54:9100"
  ifconfig 2>/dev/null | awk '/inet / && $2 !~ /^127\.|^169\.254\./ { split($2,a,"."); print "http://" a[1] "." a[2] "." a[3] ".54:9100" }'
}

test_server() {
  curl -fsS --max-time 2 "$1/status" >/dev/null 2>&1
}

get_server_base_url() {
  if [[ -n "$SERVER_CACHE" ]] && test_server "$SERVER_CACHE"; then
    echo "$SERVER_CACHE"
    return
  fi
  local candidate
  while IFS= read -r candidate; do
    if [[ -n "$candidate" ]] && test_server "$candidate"; then
      SERVER_CACHE="$candidate"
      echo "$SERVER_CACHE" > "$SERVER_FILE" 2>/dev/null
      echo "$SERVER_CACHE"
      return
    fi
  done < <(server_candidates | awk '!seen[$0]++')
  SERVER_CACHE="http://192.168.15.54:9100"
  echo "$SERVER_CACHE"
}

sync_os() {
  local base resp next
  base="$(get_server_base_url)"
  resp="$(curl -fsS --max-time 12 "$base/status-os" 2>/dev/null)"
  next="$(sed -nE 's/.*"proximoDisponivel"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' <<< "$resp")"
  if [[ -n "$next" ]]; then
    save_os_number "$next"
    LAST_SERVER_STATUS="online"
    LAST_OS_SYNC="$(date '+%d/%m %H:%M')"
    echo "OS sincronizada: $(format_os "$OS_NUMBER")"
    return 0
  fi
  echo "Nao foi possivel sincronizar OS."
  return 1
}

reserve_os() {
  local base resp next
  base="$(get_server_base_url)"
  resp="$(curl -fsS --max-time 12 -X POST -H 'Content-Type: application/json; charset=utf-8' -d '{}' "$base/proxima-os" 2>/dev/null)"
  next="$(sed -nE 's/.*"osNumero"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' <<< "$resp")"
  if [[ -n "$next" ]]; then
    save_os_number "$next"
    echo "OS reservada: $(format_os "$OS_NUMBER")"
    return 0
  fi
  return 1
}

make_payload() {
  local include_os="$1"
  local grade="$2"
  local obs="$3"
  local os_json="null"
  local serial_json
  local gpu
  local gpu_json

  if [[ "$include_os" == "sim" ]]; then os_json="$OS_NUMBER"; fi
  if [[ -z "$SERIAL" || "$SERIAL" == "N/A" ]]; then SERIAL="XXXXXX"; fi
  gpu="$(gpu_short "$GPU")"
  gpu_json="$(json_value_or_null "$gpu")"
  serial_json="$(json_escape "$SERIAL")"

  cat <<JSON
{"os":$os_json,"modelo":"$(json_escape "$MODEL")","serial":"$serial_json","cpu":"$(json_escape "$(cpu_short "$CHIP")")","gpu":$gpu_json,"ram":"$(json_escape "$(ram_short "$RAM")")","ramMods":"$(json_escape "$(ram_short "$RAM")")","disco":"$(json_escape "$(disk_short "$DISK")")","modoManual":false,"bateria":"$(json_escape "$BATTERY")","grade":"$(json_escape "$grade")","obs":"$(json_escape "$obs")"}
JSON
}

add_log() {
  local status="$1"
  local message="$2"
  local grade="$3"
  local obs="$4"
  local log_root log_file now host user line
  log_root="$(get_log_root)"
  log_file="$log_root/impressao-$(date '+%Y-%m-%d').log"
  now="$(date '+%Y-%m-%d %H:%M:%S')"
  host="$(hostname 2>/dev/null)"
  user="$(whoami 2>/dev/null)"
  line="{\"dataHora\":\"$(json_escape "$now")\",\"os\":\"$(format_os "$OS_NUMBER")\",\"osNumero\":$OS_NUMBER,\"status\":\"$(json_escape "$status")\",\"acao\":\"impressao\",\"mensagem\":\"$(json_escape "$message")\",\"serial\":\"$(json_escape "$SERIAL")\",\"modelo\":\"$(json_escape "$MODEL")\",\"grade\":\"$(json_escape "$grade")\",\"observacoes\":\"$(json_escape "$obs")\",\"servidor\":\"$(json_escape "$LAST_SERVER_STATUS")\",\"osSincronizadaEm\":\"$(json_escape "$LAST_OS_SYNC")\",\"computador\":\"$(json_escape "$host")\",\"usuario\":\"$(json_escape "$user")\"}"
  echo "$line" >> "$log_file" 2>/dev/null
}

show_info() {
  clear
  echo "============================================="
  echo " CAIJ INFORMATICA - INFO NOTEBOOK MAC"
  echo "============================================="
  echo "OS:       $(format_os "$OS_NUMBER")"
  echo "Modelo:   $MODEL"
  echo "Serial:   $SERIAL"
  echo "CPU:      $CHIP"
  echo "Nucleos:  $NUCLEOS"
  echo "RAM:      $RAM"
  echo "GPU:      $GPU"
  echo "Tela:     $RESOLUTION"
  echo "Disco:    $DISK"
  echo "Bateria:  $BATTERY"
  echo "============================================="
}

edit_manual() {
  local v
  echo ""
  echo "Edicao manual: Enter mantem o valor atual."
  read "v?Modelo [$MODEL]: "; if [[ -n "$v" ]]; then MODEL="$v"; fi
  read "v?Serial [$SERIAL]: "; if [[ -n "$v" ]]; then SERIAL="$v"; fi
  read "v?CPU [$CHIP]: "; if [[ -n "$v" ]]; then CHIP="$v"; fi
  read "v?RAM [$RAM]: "; if [[ -n "$v" ]]; then RAM="$v"; fi
  read "v?GPU [$GPU]: "; if [[ -n "$v" ]]; then GPU="$v"; fi
  read "v?Disco [$DISK]: "; if [[ -n "$v" ]]; then DISK="$v"; fi
  read "v?Bateria [$BATTERY]: "; if [[ -n "$v" ]]; then BATTERY="$v"; fi
}

print_label() {
  local grade obs inc include_os payload base confirm
  read "grade?Grade (A/B/C/RMA) [A]: "
  if [[ -z "$grade" ]]; then grade="A"; fi
  read "obs?Observacoes para etiqueta: "
  read "inc?Incluir OS na etiqueta? (S/n): "
  if [[ "$inc" =~ '^[Nn]' ]]; then include_os="nao"; else include_os="sim"; fi

  echo ""
  echo "Previa da etiqueta:"
  echo "OS:      $([[ "$include_os" == "sim" ]] && format_os "$OS_NUMBER" || echo "sem OS")"
  echo "Modelo:  $MODEL"
  echo "Serial:  $SERIAL"
  echo "CPU:     $(cpu_short "$CHIP")"
  echo "RAM:     $(ram_short "$RAM")"
  echo "Disco:   $(disk_short "$DISK")"
  echo "GPU:     $(gpu_short "$GPU")"
  echo "Grade:   $grade"
  echo "Obs:     $obs"
  echo ""
  read "confirm?Confirmar impressao? (S/n): "
  if [[ "$confirm" =~ '^[Nn]' ]]; then return; fi

  if [[ "$include_os" == "sim" ]]; then
    reserve_os || echo "Falha ao reservar OS no servidor; usando OS local."
  fi

  payload="$(make_payload "$include_os" "$grade" "$obs")"
  base="$(get_server_base_url)"
  if curl -fsS --max-time 20 -X POST -H 'Content-Type: application/json; charset=utf-8' -d "$payload" "$base/imprimir" >/dev/null 2>&1; then
    LAST_SERVER_STATUS="online"
    add_log "ok" "Etiqueta enviada com sucesso" "$grade" "$obs"
    echo "Etiqueta enviada | historico salvo | OS $(format_os "$OS_NUMBER")"
    [[ "$include_os" == "sim" ]] && sync_os >/dev/null 2>&1
  else
    LAST_SERVER_STATUS="offline"
    add_log "erro" "Falha ao enviar etiqueta" "$grade" "$obs"
    echo "Falha ao imprimir. Verifique se o Mac esta na rede da CAIJ e se o servidor esta ligado."
  fi
  echo ""
  read "dummy?Pressione Enter para continuar..."
}

ensure_dirs
hide_windows_launchers_in_finder
collect_info
sync_os >/dev/null 2>&1

while true; do
  show_info
  echo ""
  echo "[1] Imprimir etiqueta via rede"
  echo "[2] Editar dados manualmente"
  echo "[3] Definir OS manual"
  echo "[4] Sincronizar OS com servidor"
  echo "[5] Recoletar dados do MacBook"
  echo "[0] Sair"
  read "op?Opcao: "
  case "$op" in
    1) print_label ;;
    2) edit_manual ;;
    3)
      read "newos?Numero da OS: "
      if [[ "$newos" =~ '^[0-9]{2,8}$' ]]; then save_os_number "$newos"; else echo "Numero invalido."; sleep 1; fi
      ;;
    4) sync_os; sleep 1 ;;
    5) collect_info ;;
    0) exit 0 ;;
    *) echo "Opcao invalida."; sleep 1 ;;
  esac
done
