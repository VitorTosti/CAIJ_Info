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
LAST_CONFIRMED_SEEN=""
BATTERY_CYCLES=""
INTERNET_STATUS="verificando"
MAC_SESSION_ID="mac-$(date '+%Y%m%d%H%M%S')-$$"

UPDATER="$CORE/AtualizarCAIJ.command"
if [[ -f "$UPDATER" && "$1" != "--caij-after-update" ]]; then
  UPDATE_ROOT="$DIR"
  # Pendrives de recuperacao do Windows normalmente usam NTFS, que o macOS
  # monta como somente leitura. Nesse caso o pendrive inicia o app, enquanto
  # a copia executavel e atualizavel fica no cache privado do usuario.
  if [[ ! -w "$DIR" || ! -w "$CORE" ]]; then
    UPDATE_ROOT="$HOME/Library/Application Support/CAIJ/InfoNotebook"
    mkdir -p "$UPDATE_ROOT/CoreCAIJ" >/dev/null 2>&1
    for local_file in caij_servidor_url.txt caij_os_counter.txt caij_historico_notebooks.json caij_os_por_serial.json caij_modelos_manuais.json caij_ultimo_modelo_manual.json; do
      if [[ ! -f "$UPDATE_ROOT/CoreCAIJ/$local_file" && -f "$CORE/$local_file" ]]; then
        cp -p "$CORE/$local_file" "$UPDATE_ROOT/CoreCAIJ/$local_file" >/dev/null 2>&1
      fi
    done
  fi

  /bin/zsh "$UPDATER" --app-root "$UPDATE_ROOT" >/dev/null 2>&1
  UPDATE_EXIT=$?
  if [[ "$UPDATE_ROOT" != "$DIR" && -f "$UPDATE_ROOT/InfoNotebookMac.command" ]]; then
    exec /bin/zsh "$UPDATE_ROOT/InfoNotebookMac.command" --caij-after-update
  elif [[ "$UPDATE_EXIT" -eq 10 ]]; then
    exec /bin/zsh "$DIR/InfoNotebookMac.command" --caij-after-update
  fi
fi

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
  printf 'C%06d\n' "$1"
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

normalize_grade() {
  local grade pintura
  grade="$(trim "$1" | tr '[:lower:]' '[:upper:]')"
  pintura="$(trim "$2" | tr '[:lower:]' '[:upper:]')"
  if [[ -z "$grade" ]]; then grade="A"; fi
  grade="${grade#GRADE }"

  if [[ "$grade" == "C" || "$grade" =~ '^C[[:space:]]*-[[:space:]]*PINTURA[[:space:]]*[123]$' ]]; then
    echo "C"
    return
  fi

  if [[ "$grade" =~ '^(GRADE[[:space:]]*)?T([[:space:]]*-[[:space:]]*TRIAGEM)?$' ]]; then
    echo "T - TRIAGEM"
    return
  fi

  echo "$grade"
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

mac_model_year() {
  local identifier="$1" chip="$2" model_name="$3"
  identifier="${identifier//MacBookPro1,5,/MacBookPro15,}"
  case "$identifier" in
    MacBookPro18,*) echo "2021"; return ;;
    MacBookPro17,1) echo "2020"; return ;;
    MacBookPro16,2|MacBookPro16,3) echo "2020"; return ;;
    MacBookPro16,1|MacBookPro16,4) echo "2019"; return ;;
    MacBookPro15,2) echo "2018"; return ;;
    MacBookPro15,3|MacBookPro15,4) echo "2019"; return ;;
    MacBookPro15,1) [[ "$chip" =~ 'i[3579]-9' ]] && echo "2019" || echo "2018"; return ;;
    MacBookPro14,*) echo "2017"; return ;;
    MacBookPro13,*) echo "2016"; return ;;
    MacBookPro12,1) echo "2015"; return ;;
    MacBookPro11,4|MacBookPro11,5) echo "2015"; return ;;
    MacBookAir10,1) echo "2020"; return ;;
    MacBookAir9,1) echo "2020"; return ;;
    MacBookAir8,2) echo "2019"; return ;;
    MacBookAir8,1) echo "2018"; return ;;
    Mac14,15) echo "2023"; return ;;
  esac
  if [[ "$chip" =~ 'Apple[[:space:]]+M1' ]]; then
    [[ "$model_name" == *"Pro"* && "$identifier" == MacBookPro18,* ]] && echo "2021" || echo "2020"
  elif [[ "$chip" =~ 'Apple[[:space:]]+M2' ]]; then
    [[ "$chip" == *" Pro"* || "$chip" == *" Max"* ]] && echo "2023" || echo "2022"
  elif [[ "$chip" =~ 'Apple[[:space:]]+M3' ]]; then
    echo "2023"
  elif [[ "$chip" =~ 'Apple[[:space:]]+M4' ]]; then
    echo "2024"
  elif [[ "$chip" =~ 'i[3579]-([0-9]{4,5})' ]]; then
    local cpu_model="${match[1]}"
    if [[ "$cpu_model" == 10* ]]; then echo "2020"
    elif [[ ${#cpu_model} -ge 5 ]]; then echo "20${cpu_model[1,2]}"
    else echo "201${cpu_model[1,1]}"
    fi
  fi
}

collect_info() {
  local hw displays storage power cpu_brand bat_ioreg bat_health bat_max bat_design bat_pct bat_cycles chip_label model_year
  BATTERY_CYCLES=""
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
  if [[ "$CHIP" != Apple* ]]; then
    cpu_brand="$(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
    if [[ -n "$cpu_brand" ]]; then CHIP="$cpu_brand"; fi
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
  bat_cycles="$(sp_match "$power" "Cycle Count|Contagem.*Ciclos|Numero.*Ciclos")"
  bat_cycles="$(sed 's/[^0-9]//g' <<< "$bat_cycles")"

  if [[ -z "$MODEL_NAME" ]]; then MODEL_NAME="MacBook"; fi
  chip_label=""
  if [[ "$CHIP" =~ 'Apple[[:space:]]+(M[0-9]+)' ]]; then
    chip_label="${match[1]}"
  elif [[ "$CHIP" =~ 'i([3579])' ]]; then
    chip_label="I${match[1]}"
  fi
  MODEL="$MODEL_NAME"
  if [[ -n "$chip_label" && "$MODEL_NAME" != *"$chip_label"* ]]; then MODEL="$MODEL $chip_label"; fi
  model_year="$(mac_model_year "$MODEL_ID" "$CHIP" "$MODEL_NAME")"
  if [[ -n "$model_year" ]]; then MODEL="$MODEL ($model_year)"; fi
  if [[ -z "$SERIAL" ]]; then
    SERIAL="$(ioreg -l 2>/dev/null | awk -F' = ' '/IOPlatformSerialNumber/ { gsub(/"/, "", $2); print $2; exit }')"
  fi
  if [[ -z "$SERIAL" ]]; then SERIAL="N/A"; fi
  if [[ -z "$CHIP" ]]; then CHIP="N/A"; fi
  if [[ -n "$CORES" ]]; then NUCLEOS="$CORES nucleos"; else NUCLEOS="N/A"; fi
  if [[ "$MEMORY" =~ '([0-9]+)[[:space:]]*GB' ]]; then
    if [[ "$CHIP" == Apple* ]]; then
      RAM="${match[1]}GB Unificada"
    else
      RAM="${match[1]}GB"
    fi
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
  if [[ "$BAT_CAP" =~ '([0-9]+)' && "${match[1]}" -gt 0 ]]; then
    BATTERY="$BAT_CAP"
    if [[ -n "$BAT_COND" ]]; then BATTERY="$BATTERY ($BAT_COND)"; fi
  else
    bat_ioreg="$(ioreg -r -c AppleSmartBattery 2>/dev/null)"
    bat_health="$(awk '/"StateOfHealth"/ {line=$0; sub(/^.*"StateOfHealth"[^=]*=[^0-9]*/, "", line); sub(/[^0-9].*$/, "", line); n=line+0; if (n > max) max=n} END {if (max > 0) print max}' <<< "$bat_ioreg")"
    bat_max="$(awk '/"AppleRawMaxCapacity"/ {line=$0; sub(/^.*"AppleRawMaxCapacity"[^=]*=[^0-9]*/, "", line); sub(/[^0-9].*$/, "", line); n=line+0; if (n > max) max=n} END {if (max > 0) print max}' <<< "$bat_ioreg")"
    bat_design="$(awk '/"AppleRawDesignCapacity"/ {line=$0; sub(/^.*"AppleRawDesignCapacity"[^=]*=[^0-9]*/, "", line); sub(/[^0-9].*$/, "", line); n=line+0; if (n > max) max=n} END {if (max > 0) print max}' <<< "$bat_ioreg")"
    if [[ "$bat_health" == <-> && "$bat_health" -gt 0 && "$bat_health" -le 100 ]]; then
      BATTERY="${bat_health}%"
      if [[ -n "$BAT_COND" ]]; then BATTERY="$BATTERY ($BAT_COND)"; fi
    else
      if [[ "$bat_max" != <-> || "$bat_max" -le 0 || "$bat_design" != <-> || "$bat_design" -le 0 ]]; then
        bat_max="$(awk '/"NominalChargeCapacity"/ {line=$0; sub(/^.*"NominalChargeCapacity"[^=]*=[^0-9]*/, "", line); sub(/[^0-9].*$/, "", line); n=line+0; if (n > max) max=n} END {if (max > 0) print max}' <<< "$bat_ioreg")"
        bat_design="$(awk '/"DesignCapacity"/ {line=$0; sub(/^.*"DesignCapacity"[^=]*=[^0-9]*/, "", line); sub(/[^0-9].*$/, "", line); n=line+0; if (n > max) max=n} END {if (max > 0) print max}' <<< "$bat_ioreg")"
      fi
      if [[ "$bat_max" != <-> || "$bat_max" -le 0 || "$bat_design" != <-> || "$bat_design" -le 0 ]]; then
        bat_max="$(awk '/"MaxCapacity"/ {line=$0; sub(/^.*"MaxCapacity"[^=]*=[^0-9]*/, "", line); sub(/[^0-9].*$/, "", line); n=line+0; if (n > max) max=n} END {if (max > 0) print max}' <<< "$bat_ioreg")"
        bat_design="$(awk '/"DesignCapacity"/ {line=$0; sub(/^.*"DesignCapacity"[^=]*=[^0-9]*/, "", line); sub(/[^0-9].*$/, "", line); n=line+0; if (n > max) max=n} END {if (max > 0) print max}' <<< "$bat_ioreg")"
      fi
      if [[ "$bat_max" == <-> && "$bat_max" -gt 0 && "$bat_design" == <-> && "$bat_design" -gt 0 ]]; then
        bat_pct=$(( (100 * bat_max + bat_design / 2) / bat_design ))
        if (( bat_pct > 100 )); then bat_pct=100; fi
        BATTERY="${bat_pct}%"
        if [[ -n "$BAT_COND" ]]; then BATTERY="$BATTERY ($BAT_COND)"; fi
      else
        BATTERY="N/A"
        {
          echo "=== system_profiler SPPowerDataType ==="
          grep -Ei 'Capacity|Capacidade|Condition|Condi|Cycle Count|Ciclos' <<< "$power"
          echo "=== ioreg AppleSmartBattery ==="
          grep -Ei 'Capacity|StateOfHealth|CycleCount|Condition' <<< "$bat_ioreg"
        } > "$CORE/mac-ui/battery-diagnostic.txt" 2>/dev/null
      fi
    fi
  fi
  if [[ "$bat_cycles" != <-> || "$bat_cycles" -le 0 ]]; then
    if [[ -z "$bat_ioreg" ]]; then bat_ioreg="$(ioreg -r -c AppleSmartBattery 2>/dev/null)"; fi
    bat_cycles="$(awk '/"CycleCount"/ {line=$0; sub(/^.*"CycleCount"[^=]*=[^0-9]*/, "", line); sub(/[^0-9].*$/, "", line); n=line+0; if (n > max) max=n} END {if (max > 0) print max}' <<< "$bat_ioreg")"
  fi
  if [[ "$bat_cycles" == <-> && "$bat_cycles" -gt 0 ]]; then
    BATTERY_CYCLES="$bat_cycles"
    BATTERY="$BATTERY | $bat_cycles ciclos"
  fi
}

cpu_short() {
  local cpu="$1"
  if [[ "$cpu" =~ 'Apple[[:space:]]+(M[0-9][^ ]*)' ]]; then
    echo "Apple ${match[1]}"
  elif [[ "$cpu" =~ 'i([3579]).*([0-9]{4,5})' ]]; then
    local model="${match[2]}"
    local generation suffix mod100 mod10 first_two
    first_two="${model[1,2]}"
    if (( first_two >= 10 && first_two <= 19 )); then
      generation="$first_two"
    else
      generation="${model[1,1]}"
    fi
    suffix="th"
    mod100=$(( generation % 100 ))
    mod10=$(( generation % 10 ))
    if (( mod100 < 11 || mod100 > 13 )); then
      case "$mod10" in
        1) suffix="st" ;;
        2) suffix="nd" ;;
        3) suffix="rd" ;;
      esac
    fi
    echo "i${match[1]} ${generation}${suffix}"
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
  echo "http://INFOCAIJ.local:9100"
  echo "http://INFOCAIJ:9100"
  echo "http://192.168.15.11:9100"
  ifconfig 2>/dev/null | awk '/inet / && $2 !~ /^127\.|^169\.254\./ { split($2,a,"."); print "http://" a[1] "." a[2] "." a[3] ".11:9100" }'
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
  SERVER_CACHE="http://INFOCAIJ.local:9100"
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

check_os_alert() {
  local mode="$1" base resp confirmed next
  base="$(get_server_base_url)"
  resp="$(curl -fsS --max-time 5 "$base/status-os-local" 2>/dev/null)"
  confirmed="$(sed -nE 's/.*"ultimoConfirmado"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' <<< "$resp")"
  next="$(sed -nE 's/.*"proximoDisponivel"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' <<< "$resp")"
  [[ -z "$confirmed" || -z "$next" ]] && return 1

  if [[ -z "$LAST_CONFIRMED_SEEN" ]]; then
    LAST_CONFIRMED_SEEN="$confirmed"
    save_os_number "$next"
    return 0
  fi

  if (( confirmed > LAST_CONFIRMED_SEEN )); then
    LAST_CONFIRMED_SEEN="$confirmed"
    save_os_number "$next"
    LAST_SERVER_STATUS="online"
    LAST_OS_SYNC="$(date '+%d/%m %H:%M')"
    if [[ "$mode" == "dialog" ]]; then
      dialog_message "Nova OS criada" "$(format_os "$confirmed") foi criada em outra estacao.

Proxima OS disponivel: $(format_os "$next")"
    else
      echo "ALERTA: $(format_os "$confirmed") criada | proxima OS: $(format_os "$next")"
    fi
  fi
  return 0
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
{"os":$os_json,"modelo":"$(json_escape "$MODEL")","serial":"$serial_json","tipoEquipamento":"Notebook","cpu":"$(json_escape "$(cpu_short "$CHIP")")","gpu":$gpu_json,"ram":"$(json_escape "$(ram_short "$RAM")")","ramMods":"$(json_escape "$(ram_short "$RAM")")","disco":"$(json_escape "$(disk_short "$DISK")")","fichaCpu":"$(json_escape "$CHIP")","fichaGpu":"$(json_escape "$GPU")","fichaRam":"$(json_escape "$RAM")","fichaDisco":"$(json_escape "$DISK")","modoManual":false,"bateria":"$(json_escape "$BATTERY")","grade":"$(json_escape "$grade")","obs":"$(json_escape "$obs")"}
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

write_web_runtime_data() {
  local runtime_file
  runtime_file="$CORE/mac-ui/runtime-data.json"
  mkdir -p "$CORE/mac-ui" >/dev/null 2>&1
  cat > "$runtime_file" <<JSON
{
  "osNumero": $OS_NUMBER,
  "lastServerStatus": "$(json_escape "$LAST_SERVER_STATUS")",
  "lastOsSync": "$(json_escape "$LAST_OS_SYNC")",
  "info": {
    "modelo": "$(json_escape "$MODEL")",
    "serial": "$(json_escape "$SERIAL")",
    "cpu": "$(json_escape "$CHIP")",
    "gpu": "$(json_escape "$GPU")",
    "ram": "$(json_escape "$RAM")",
    "disco": "$(json_escape "$DISK")",
    "bateria": "$(json_escape "$BATTERY")"
  }
}
JSON
  echo "$runtime_file"
}

portable_runtime_json() {
  local version server_url
  version="$(tr -d '\r\n' < "$CORE/caij_versao_app.txt" 2>/dev/null)"
  server_url="$(get_server_base_url)"
  cat <<JSON
{
  "osNumero": $OS_NUMBER,
  "serverUrl": "$(json_escape "$server_url")",
  "lastServerStatus": "$(json_escape "$LAST_SERVER_STATUS")",
  "lastOsSync": "$(json_escape "$LAST_OS_SYNC")",
  "internetStatus": "$(json_escape "$INTERNET_STATUS")",
  "sessionId": "$(json_escape "$MAC_SESSION_ID")",
  "version": "$(json_escape "$version")",
  "info": {
    "modelo": "$(json_escape "$MODEL")",
    "serial": "$(json_escape "$SERIAL")",
    "cpu": "$(json_escape "$CHIP")",
    "gpu": "$(json_escape "$GPU")",
    "ram": "$(json_escape "$RAM")",
    "disco": "$(json_escape "$DISK")",
    "bateria": "$(json_escape "$BATTERY")"
  }
}
JSON
}

write_portable_runtime_data() {
  local runtime_file runtime_json
  runtime_file="$CORE/mac-ui/caij-runtime.js"
  runtime_json="$(portable_runtime_json)"
  mkdir -p "$CORE/mac-ui" >/dev/null 2>&1
  printf 'window.CAIJ_NATIVE_RUNTIME = %s;\n' "$runtime_json" > "$runtime_file" || return 1
  echo "$runtime_file"
}

launch_local_static_ui() {
  local ruby_bin port candidate_port server_pid cache_key ui_url ready attempt
  if [[ "${CAIJ_MAC_TERMINAL:-}" == "1" ]]; then return 1; fi
  ruby_bin="/usr/bin/ruby"
  [[ -x "$ruby_bin" && -f "$CORE/mac-ui/index.html" && -f "$CORE/mac-ui/portable.js" ]] || return 1
  write_portable_runtime_data >/dev/null || return 1

  port=""
  for attempt in {0..12}; do
    candidate_port=$((17654 + attempt))
    if ! lsof -nP -iTCP:"$candidate_port" -sTCP:LISTEN >/dev/null 2>&1; then
      port="$candidate_port"
      break
    fi
  done
  [[ -n "$port" ]] || return 1

  "$ruby_bin" -run -e httpd "$CORE/mac-ui" -b 127.0.0.1 -p "$port" >/dev/null 2>&1 &
  server_pid=$!
  ready="nao"
  for attempt in {1..30}; do
    if curl -fsS --connect-timeout 1 --max-time 2 "http://127.0.0.1:$port/" >/dev/null 2>&1; then
      ready="sim"
      break
    fi
    kill -0 "$server_pid" >/dev/null 2>&1 || break
    sleep 0.2
  done
  if [[ "$ready" != "sim" ]]; then
    kill "$server_pid" >/dev/null 2>&1 || true
    wait "$server_pid" >/dev/null 2>&1 || true
    return 1
  fi

  cache_key="$(tr -d '\r\n' < "$CORE/caij_versao_app.txt" 2>/dev/null)"
  [[ -z "$cache_key" ]] && cache_key="$(date '+%s')"
  ui_url="http://127.0.0.1:$port/?app=$cache_key"
  if ! open -a Safari "$ui_url" >/dev/null 2>&1; then
    kill "$server_pid" >/dev/null 2>&1 || true
    wait "$server_pid" >/dev/null 2>&1 || true
    return 1
  fi

  osascript <<'APPLESCRIPT' >/dev/null 2>&1 || true
tell application "Finder" to set screenBounds to bounds of window of desktop
tell application "Safari"
  activate
  if (count of windows) > 0 then set bounds of front window to screenBounds
end tell
APPLESCRIPT
  osascript -e 'tell application "Terminal" to if (count of windows) > 0 then set miniaturized of front window to true' >/dev/null 2>&1 || true
  while kill -0 "$server_pid" >/dev/null 2>&1 && pgrep -x Safari >/dev/null 2>&1; do sleep 1; done
  kill "$server_pid" >/dev/null 2>&1 || true
  wait "$server_pid" >/dev/null 2>&1 || true
  return 0
}

launch_portable_web_ui() {
  local ui_file ui_url cache_key server_url runtime_json runtime_token hosted_mode command_reply native_command
  if [[ "${CAIJ_MAC_TERMINAL:-}" == "1" ]]; then return 1; fi
  ui_file="$CORE/mac-ui/index.html"
  [[ -f "$ui_file" && -f "$CORE/mac-ui/portable.js" ]] || return 1
  cache_key="$(tr -d '\r\n' < "$CORE/caij_versao_app.txt" 2>/dev/null)"
  [[ -z "$cache_key" ]] && cache_key="$(date '+%s')"
  server_url="$(get_server_base_url)"
  runtime_json="$(portable_runtime_json)"
  runtime_token="$(printf '%s' "$runtime_json" | base64 | tr -d '\r\n=' | tr '+/' '-_')"
  hosted_mode="nao"

  if [[ -n "$server_url" ]] && curl -fsS --connect-timeout 2 --max-time 4 "$server_url/status" >/dev/null 2>&1; then
    # A UI vem do proprio servidor. Assim busca de produtos, cadastro de OS e
    # impressao usam a mesma origem e nao sao bloqueados pelo Safari.
    ui_url="$server_url/mac/?app=$cache_key#runtime=$runtime_token"
    hosted_mode="sim"
  else
    write_portable_runtime_data >/dev/null || return 1
    ui_url="file://$ui_file?app=$cache_key"
    ui_url="${ui_url// /%20}"
  fi
  if open -a Safari "$ui_url" >/dev/null 2>&1; then
    sleep 0.5
    osascript <<'APPLESCRIPT' >/dev/null 2>&1 || true
tell application "Finder" to set screenBounds to bounds of window of desktop
tell application "Safari"
  activate
  if (count of windows) > 0 then set bounds of front window to screenBounds
end tell
APPLESCRIPT
    if [[ "$hosted_mode" == "sim" ]]; then
      osascript -e 'tell application "Terminal" to if (count of windows) > 0 then set miniaturized of front window to true' >/dev/null 2>&1 || true
      while pgrep -x Safari >/dev/null 2>&1; do
        command_reply="$(curl -fsS --connect-timeout 1 --max-time 3 "$server_url/mac/comando?session=$MAC_SESSION_ID" 2>/dev/null)"
        native_command="$(sed -n 's/.*"command":"\([^"]*\)".*/\1/p' <<< "$command_reply")"
        if [[ "$native_command" == "open-tests" ]]; then
          open_native_tests "hosted"
        elif [[ "$native_command" == "quit" ]]; then
          break
        fi
        sleep 1
      done
    fi
    return 0
  fi
  return 1
}

launch_web_ui() {
  local python_bin runtime_file
  if [[ "${CAIJ_MAC_TERMINAL:-}" == "1" ]]; then return 1; fi
  python_bin=""
  for candidate in /opt/homebrew/bin/python3 /usr/local/bin/python3 "$HOME/.pyenv/shims/python3"; do
    if [[ -x "$candidate" ]]; then
      python_bin="$candidate"
      break
    fi
  done
  if [[ -z "$python_bin" ]]; then return 1; fi
  if [[ ! -f "$CORE/mac-ui/server.py" ]]; then return 1; fi

  runtime_file="$(write_web_runtime_data)"
  echo "Abrindo interface visual do Info Notebook Mac..."
  echo "Feche esta janela apenas quando terminar de usar a interface."
  "$python_bin" "$CORE/mac-ui/server.py" --core "$CORE" --data "$runtime_file" --host 127.0.0.1 --port 0
}

dialog_input() {
  osascript - "$1" "$2" <<'APPLESCRIPT'
on run argv
  try
    set r to display dialog (item 1 of argv) default answer (item 2 of argv) buttons {"Cancelar", "OK"} default button "OK"
    return text returned of r
  on error number -128
    return "__CAIJ_CANCEL__"
  end try
end run
APPLESCRIPT
}

dialog_choose() {
  osascript - "$1" "$2" <<'APPLESCRIPT'
on run argv
  try
    set promptText to item 1 of argv
    set rawItems to item 2 of argv
    set AppleScript's text item delimiters to "|"
    set choices to text items of rawItems
    set picked to choose from list choices with prompt promptText default items {item 1 of choices} without multiple selections allowed
    if picked is false then return "__CAIJ_CANCEL__"
    return item 1 of picked
  on error number -128
    return "__CAIJ_CANCEL__"
  end try
end run
APPLESCRIPT
}

dialog_confirm() {
  osascript - "$1" "$2" <<'APPLESCRIPT'
on run argv
  try
    set r to display dialog (item 1 of argv) buttons {"Cancelar", item 2 of argv} default button (item 2 of argv)
    return button returned of r
  on error number -128
    return "__CAIJ_CANCEL__"
  end try
end run
APPLESCRIPT
}

dialog_message() {
  osascript - "$1" "$2" <<'APPLESCRIPT'
on run argv
  display dialog (item 2 of argv) buttons {"OK"} default button "OK" with title (item 1 of argv)
end run
APPLESCRIPT
}

check_internet_connection() {
  local marker pid_one pid_two
  marker="$(mktemp "${TMPDIR:-/tmp}/caij-internet.XXXXXX")" || return 1
  rm -f "$marker"
  (
    curl -fsS --connect-timeout 1 --max-time 3 -o /dev/null "https://captive.apple.com/hotspot-detect.html" 2>/dev/null && : > "$marker"
  ) &
  pid_one=$!
  (
    curl -fsS --connect-timeout 1 --max-time 3 -o /dev/null "https://www.cloudflare.com/cdn-cgi/trace" 2>/dev/null && : > "$marker"
  ) &
  pid_two=$!
  wait "$pid_one" >/dev/null 2>&1 || true
  wait "$pid_two" >/dev/null 2>&1 || true
  if [[ -f "$marker" ]]; then
    rm -f "$marker"
    INTERNET_STATUS="online"
    return 0
  fi
  INTERNET_STATUS="offline"
  return 1
}

warn_if_no_internet() {
  if check_internet_connection; then return 0; fi
  if command -v osascript >/dev/null 2>&1 && [[ "${CAIJ_MAC_TERMINAL:-}" != "1" ]]; then
    dialog_message "Mac sem internet" "Este Mac esta sem acesso a internet.

Conecte-o ao Wi-Fi CAIJ. O InfoNotebook continuara abrindo, mas atualizacoes e recursos online podem ficar indisponiveis."
  else
    echo "AVISO: Mac sem internet. Conecte ao Wi-Fi CAIJ."
  fi
  return 1
}

clipboard_tests_observation() {
  local value
  command -v pbpaste >/dev/null 2>&1 || return 0
  value="$(pbpaste 2>/dev/null | tr -d '\r' | sed -n '1p')"
  value="$(trim "$value")"
  if [[ "$value" =~ '^TESTES:[[:space:]]*(OK|FALHOU|PENDENTE)$' ]]; then
    echo "$value"
  fi
}

html_escape() {
  printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'
}

open_native_info_table() {
  local table_file
  table_file="$CORE/mac-ui/informacoes-mac.html"
  mkdir -p "${table_file:h}" >/dev/null 2>&1
  cat > "$table_file" <<HTML
<!doctype html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>InfoNotebook - Informacoes do Mac</title>
  <style>
    :root { color-scheme: light; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
    body { margin: 0; background: #f3f6f8; color: #17212b; }
    main { width: min(860px, calc(100% - 32px)); margin: 32px auto; }
    .eyebrow { color: #5865d8; font-size: 12px; font-weight: 800; letter-spacing: .08em; text-transform: uppercase; }
    h1 { margin: 8px 0 6px; font-size: clamp(26px, 4vw, 38px); }
    p { margin: 0 0 20px; color: #637080; }
    .table-wrap { overflow: hidden; border: 1px solid #d8e0e7; border-radius: 12px; background: white; box-shadow: 0 14px 38px rgba(26, 39, 52, .08); }
    table { width: 100%; border-collapse: collapse; table-layout: fixed; }
    thead { background: #f4f7fa; }
    th, td { padding: 14px 18px; border-bottom: 1px solid #e8edf2; text-align: left; vertical-align: top; overflow-wrap: anywhere; }
    thead th { color: #657180; font-size: 11px; letter-spacing: .07em; text-transform: uppercase; }
    tbody th { width: 30%; color: #657180; font-size: 12px; letter-spacing: .04em; text-transform: uppercase; }
    tbody td { font-size: 15px; font-weight: 650; }
    tbody tr:last-child th, tbody tr:last-child td { border-bottom: 0; }
    .os { margin-top: 16px; color: #5865d8; font-weight: 750; }
  </style>
</head>
<body><main>
  <div class="eyebrow">Diagnostico tecnico</div>
  <h1>Informacoes do Mac</h1>
  <p>Dados coletados automaticamente ao abrir o InfoNotebook.</p>
  <div class="table-wrap"><table>
    <thead><tr><th>Informacao</th><th>Valor detectado</th></tr></thead>
    <tbody>
      <tr><th>Modelo</th><td>$(html_escape "$MODEL")</td></tr>
      <tr><th>Serial</th><td>$(html_escape "$SERIAL")</td></tr>
      <tr><th>CPU</th><td>$(html_escape "$CHIP")</td></tr>
      <tr><th>GPU</th><td>$(html_escape "$GPU")</td></tr>
      <tr><th>RAM</th><td>$(html_escape "$RAM")</td></tr>
      <tr><th>Disco</th><td>$(html_escape "$DISK")</td></tr>
      <tr><th>Bateria</th><td>$(html_escape "$BATTERY")</td></tr>
    </tbody>
  </table></div>
  <div class="os">OS atual: $(format_os "$OS_NUMBER")</div>
</main></body></html>
HTML
  if open -a Safari "$table_file" >/dev/null 2>&1; then
    osascript -e 'tell application "Safari" to activate' >/dev/null 2>&1
    sleep 2
    return 0
  fi
  if open "$table_file" >/dev/null 2>&1; then
    sleep 2
    return 0
  fi
  dialog_message "Tabela indisponivel" "Nao foi possivel abrir a tabela no navegador. Arquivo: $table_file"
  return 1
}

start_native_os_monitor() {
  (
    local last_seen="" base resp confirmed next local_os
    while true; do
      base="$(get_server_base_url)"
      resp="$(curl -fsS --max-time 5 "$base/status-os-local" 2>/dev/null)"
      confirmed="$(sed -nE 's/.*"ultimoConfirmado"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' <<< "$resp")"
      next="$(sed -nE 's/.*"proximoDisponivel"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' <<< "$resp")"
      if [[ -n "$confirmed" && -n "$next" ]]; then
        local_os="$(sed -nE 's/[^0-9]*([0-9]+).*/\1/p' "$OS_FILE" 2>/dev/null)"
        if [[ -n "$last_seen" ]] && (( confirmed > last_seen )) && [[ "$confirmed" != "$local_os" ]]; then
          osascript - "$(format_os "$confirmed")" "$(format_os "$next")" <<'APPLESCRIPT' >/dev/null 2>&1
on run argv
  tell application "System Events"
    activate
    display dialog ((item 1 of argv) & " foi criada em outra estacao." & return & return & "Proxima OS disponivel: " & (item 2 of argv)) with title "InfoNotebook - Nova OS" buttons {"Entendido"} default button 1 with icon note
  end tell
end run
APPLESCRIPT
        fi
        last_seen="$confirmed"
      fi
      sleep 4
    done
  ) &
  NATIVE_OS_MONITOR_PID=$!
}

stop_native_os_monitor() {
  if [[ -n "$NATIVE_OS_MONITOR_PID" ]]; then
    kill "$NATIVE_OS_MONITOR_PID" >/dev/null 2>&1 || true
    wait "$NATIVE_OS_MONITOR_PID" >/dev/null 2>&1 || true
    NATIVE_OS_MONITOR_PID=""
  fi
}

dialog_create_os() {
  local tecnico serial codigo descricao referencia obs suggested_obs confirm base payload resp criada mensagem
  tecnico="$(dialog_choose "Quem esta realizando a OS?" "Vitor|Lucas|Hyrides|Erick|Outro")"
  [[ "$tecnico" == "__CAIJ_CANCEL__" ]] && return
  if [[ "$tecnico" == "Outro" ]]; then
    tecnico="$(dialog_input "Nome do tecnico" "")"
    [[ "$tecnico" == "__CAIJ_CANCEL__" || -z "$(trim "$tecnico")" ]] && return
  fi
  serial="$(dialog_input "Serial do equipamento" "$SERIAL")"
  [[ "$serial" == "__CAIJ_CANCEL__" || -z "$(trim "$serial")" ]] && return
  codigo="$(dialog_input "Codigo do produto no Altertag" "")"
  [[ "$codigo" == "__CAIJ_CANCEL__" || -z "$(trim "$codigo")" ]] && return
  descricao="$(dialog_input "Descricao do produto" "$MODEL")"
  [[ "$descricao" == "__CAIJ_CANCEL__" ]] && return
  referencia="$(dialog_choose "Referencia" "GRADE A|GRADE B|GRADE C|GRADE T - TRIAGEM|RMA")"
  [[ "$referencia" == "__CAIJ_CANCEL__" ]] && return
  suggested_obs="$(clipboard_tests_observation)"
  obs="$(dialog_input "Observacao" "$suggested_obs")"
  [[ "$obs" == "__CAIJ_CANCEL__" ]] && return
  confirm="$(dialog_confirm "Tecnico: $tecnico
Serial: $serial
Produto: $codigo - $descricao
Referencia: $referencia" "Criar OS")"
  [[ "$confirm" == "__CAIJ_CANCEL__" ]] && return

  payload="{\"tecnico\":\"$(json_escape "$tecnico")\",\"serial\":\"$(json_escape "$serial")\",\"referencia\":\"$(json_escape "$referencia")\",\"idProduto\":0,\"produtoCodigo\":\"$(json_escape "$codigo")\",\"produtoDescricao\":\"$(json_escape "$descricao")\",\"produtoValor\":\"0.00\",\"servicos\":[],\"tipoEquipamento\":\"Notebook\",\"observacao\":\"$(json_escape "$obs")\"}"
  base="$(get_server_base_url)"
  resp="$(curl -fsS --max-time 45 -X POST -H 'Content-Type: application/json; charset=utf-8' -d "$payload" "$base/criar-os-altertag" 2>/dev/null)"
  criada="$(sed -nE 's/.*"osNumero"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' <<< "$resp")"
  mensagem="$(sed -nE 's/.*"mensagem"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' <<< "$resp")"
  if [[ -n "$criada" ]]; then
    save_os_number "$criada"
    LAST_CONFIRMED_SEEN="$criada"
    local prev_model prev_serial
    prev_model="$MODEL"
    prev_serial="$SERIAL"
    MODEL="$descricao"
    SERIAL="$serial"
    dialog_print_label "$referencia" "$obs" "sim" "sim"
    MODEL="$prev_model"
    SERIAL="$prev_serial"
    dialog_message "OS criada" "$(format_os "$criada") criada com sucesso para $tecnico."
  else
    dialog_message "Falha ao criar OS" "${mensagem:-Nao foi possivel criar a OS no Altertag.}"
  fi
}

dialog_edit_manual() {
  local v
  v="$(dialog_input "Modelo" "$MODEL")"; [[ "$v" == "__CAIJ_CANCEL__" ]] && return 1; [[ -n "$v" ]] && MODEL="$v"
  v="$(dialog_input "Serial" "$SERIAL")"; [[ "$v" == "__CAIJ_CANCEL__" ]] && return 1; [[ -n "$v" ]] && SERIAL="$v"
  v="$(dialog_input "CPU" "$CHIP")"; [[ "$v" == "__CAIJ_CANCEL__" ]] && return 1; [[ -n "$v" ]] && CHIP="$v"
  v="$(dialog_input "RAM" "$RAM")"; [[ "$v" == "__CAIJ_CANCEL__" ]] && return 1; [[ -n "$v" ]] && RAM="$v"
  v="$(dialog_input "GPU" "$GPU")"; [[ "$v" == "__CAIJ_CANCEL__" ]] && return 1; [[ -n "$v" ]] && GPU="$v"
  v="$(dialog_input "Disco" "$DISK")"; [[ "$v" == "__CAIJ_CANCEL__" ]] && return 1; [[ -n "$v" ]] && DISK="$v"
  v="$(dialog_input "Bateria" "$BATTERY")"; [[ "$v" == "__CAIJ_CANCEL__" ]] && return 1; [[ -n "$v" ]] && BATTERY="$v"
}

dialog_set_os_manual() {
  local quiet="${1:-nao}"
  local newos
  while true; do
    newos="$(dialog_input "Numero da OS" "$OS_NUMBER")"
    [[ "$newos" == "__CAIJ_CANCEL__" ]] && return 1
    newos="$(trim "$newos")"
    if [[ "$newos" =~ '^[0-9]{2,8}$' ]]; then
      save_os_number "$newos"
      if [[ "$quiet" != "sim" ]]; then
        dialog_message "OS atualizada" "OS atual: $(format_os "$OS_NUMBER")"
      fi
      return 0
    fi
    dialog_message "Numero invalido" "Digite apenas numeros, por exemplo: $OS_NUMBER"
  done
}

dialog_print_label() {
  local default_grade="$1"
  local default_obs="$2"
  local default_include_os="$3"
  local skip_reserve="$4"
  local grade obs include_os preview action edit_choice payload base printed_os battery_summary cycles_summary obs_option include_label

  if [[ -n "$default_grade" ]]; then
    grade="$(normalize_grade "$default_grade" "")"
  else
    grade="A"
  fi

  obs="$default_obs"
  if [[ -z "$(trim "$obs")" ]]; then
    obs="$(clipboard_tests_observation)"
  fi

  if [[ -n "$default_include_os" ]]; then
    include_os="$default_include_os"
  else
    include_os="sim"
  fi

  battery_summary="$(sed -E 's/[[:space:]]*\|[[:space:]]*[0-9]+ ciclos.*$//' <<< "$BATTERY")"
  [[ -z "$battery_summary" ]] && battery_summary="Nao detectada"
  cycles_summary="${BATTERY_CYCLES:-Nao detectado}"

  while true; do
    preview="RESUMO DA ETIQUETA

Modelo: $MODEL
Serial: $SERIAL
CPU: $(cpu_short "$CHIP")
RAM: $(ram_short "$RAM")
Armazenamento: $(disk_short "$DISK")
GPU: $(gpu_short "$GPU")
Bateria: $battery_summary
Ciclos: $cycles_summary

Os campos editaveis aparecem na lista abaixo."

    obs_option="$(printf '%s' "${obs:-Sem observacao}" | tr '\n|' ' /' | cut -c1-64)"
    if [[ "$include_os" == "sim" ]]; then include_label="Sim"; else include_label="Nao"; fi
    action="$(dialog_choose "$preview" "OS atual: $(format_os "$OS_NUMBER")|Grade: $grade|Observacao: $obs_option|Incluir OS: $include_label|IMPRIMIR ETIQUETA|Cancelar")"
    case "$action" in
      "OS atual:"*)
        if dialog_set_os_manual "sim"; then
          include_os="sim"
          skip_reserve="sim"
        fi
        ;;
      "Grade:"*)
        edit_choice="$(dialog_choose "Selecione a grade da etiqueta" "A|B|C|T - TRIAGEM|RMA")"
        if [[ "$edit_choice" != "__CAIJ_CANCEL__" ]]; then
          grade="$(normalize_grade "$edit_choice" "")"
        fi
        ;;
      "Observacao:"*)
        edit_choice="$(dialog_input "Observacoes para etiqueta" "$obs")"
        [[ "$edit_choice" != "__CAIJ_CANCEL__" ]] && obs="$edit_choice"
        ;;
      "Incluir OS:"*)
        if [[ "$include_os" == "sim" ]]; then include_os="nao"; else include_os="sim"; fi
        ;;
      "IMPRIMIR ETIQUETA")
        if [[ ( "$grade" == "B" || "$grade" == "C" ) && -z "$(trim "$obs")" ]]; then
          dialog_message "Observacao obrigatoria" "Informe uma observacao para etiquetas Grade B ou Grade C."
        else
          break
        fi
        ;;
      "Cancelar"|"__CAIJ_CANCEL__") return ;;
    esac
  done

  if [[ "$include_os" == "sim" && "$skip_reserve" != "sim" ]]; then
    reserve_os >/dev/null 2>&1 || true
  fi
  if [[ "$include_os" == "sim" ]]; then printed_os="$(format_os "$OS_NUMBER")"; else printed_os="sem OS"; fi

  payload="$(make_payload "$include_os" "$grade" "$obs")"
  base="$(get_server_base_url)"
  if curl -fsS --max-time 20 -X POST -H 'Content-Type: application/json; charset=utf-8' -d "$payload" "$base/imprimir" >/dev/null 2>&1; then
    LAST_SERVER_STATUS="online"
    add_log "ok" "Etiqueta enviada com sucesso" "$grade" "$obs"
    [[ "$include_os" == "sim" ]] && sync_os >/dev/null 2>&1
    dialog_message "Etiqueta enviada" "Etiqueta enviada com sucesso. OS $printed_os"
  else
    LAST_SERVER_STATUS="offline"
    add_log "erro" "Falha ao enviar etiqueta" "$grade" "$obs"
    dialog_message "Falha ao imprimir" "Verifique se o Mac esta na rede da CAIJ e se o servidor esta ligado."
  fi
}

launch_dialog_ui() {
  local op battery_summary cycles_summary
  if [[ "${CAIJ_MAC_TERMINAL:-}" == "1" ]]; then return 1; fi
  if ! command -v osascript >/dev/null 2>&1; then return 1; fi

  start_native_os_monitor
  trap stop_native_os_monitor EXIT INT TERM
  while true; do
    battery_summary="$(sed -E 's/[[:space:]]*\|[[:space:]]*[0-9]+ ciclos.*$//' <<< "$BATTERY")"
    [[ -z "$battery_summary" ]] && battery_summary="Nao detectada"
    cycles_summary="${BATTERY_CYCLES:-Nao detectado}"
    op="$(dialog_choose "CAIJ Info Notebook Mac

OS: $(format_os "$OS_NUMBER")
Modelo: $MODEL
Serial: $SERIAL

Memoria: ${RAM:-Nao detectada}
Armazenamento: $(disk_short "$DISK")
Bateria: $battery_summary
Ciclos: $cycles_summary" "Testes do Mac|Cadastrar OS|Imprimir etiqueta|Editar dados|Sincronizar OS|Recoletar dados|Sair")"
    case "$op" in
      "Testes do Mac")
        open_native_tests
        ;;
      "Cadastrar OS") dialog_create_os ;;
      "Imprimir etiqueta") dialog_print_label ;;
      "Editar dados") dialog_edit_manual ;;
      "Sincronizar OS")
        if sync_os >/dev/null 2>&1; then
          dialog_message "OS sincronizada" "OS atual: $(format_os "$OS_NUMBER")"
        else
          dialog_message "Servidor offline" "Nao foi possivel sincronizar OS."
        fi
        ;;
      "Recoletar dados") collect_info; dialog_message "Dados atualizados" "Dados do MacBook coletados novamente." ;;
      "Sair"|"__CAIJ_CANCEL__") stop_native_os_monitor; exit 0 ;;
    esac
  done
}

open_native_tests() {
  local tests_file tests_title tests_url return_mode
  return_mode="$1"
  tests_file="$CORE/mac-ui/index.html"
  if [[ ! -f "$tests_file" ]]; then
    dialog_message "Central indisponivel" "A interface local do Mac nao foi encontrada. Conecte o Mac a rede CAIJ e abra o aplicativo novamente para atualizar."
    return 1
  fi
  tests_url="file://$tests_file?tests=1"
  tests_url="${tests_url// /%20}"
  if [[ -n "$tests_url" ]] && open -a Safari "$tests_url" >/dev/null 2>&1; then
    # O menu do InfoNotebook continua vivo, mas sua janela fica recolhida
    # enquanto o tecnico trabalha na Central de Testes.
    osascript -e 'tell application "Terminal" to if (count of windows) > 0 then set miniaturized of front window to true' >/dev/null 2>&1 || true
    osascript -e 'tell application "Safari" to activate' >/dev/null 2>&1 || true
    while true; do
      tests_title="$(osascript <<'APPLESCRIPT' 2>/dev/null
tell application "System Events"
  if not (exists process "Safari") then return "__CAIJ_TESTS_CLOSED__"
end tell
tell application "Safari"
  if (count of windows) is 0 then return "__CAIJ_TESTS_CLOSED__"
  repeat with safariWindow in windows
    repeat with safariTab in tabs of safariWindow
      try
        if (URL of safariTab contains "mac-ui/index.html") then return name of safariTab
      end try
    end repeat
  end repeat
  return "__CAIJ_TESTS_CLOSED__"
end tell
APPLESCRIPT
)"
      if [[ "$tests_title" == "CAIJ_TESTES_CONCLUIDOS" || "$tests_title" == "__CAIJ_TESTS_CLOSED__" ]]; then
        break
      fi
      sleep 1
    done
    if [[ "$tests_title" == "CAIJ_TESTES_CONCLUIDOS" ]]; then
      osascript -e 'tell application "Safari" to if (count of windows) > 0 then close current tab of front window' >/dev/null 2>&1 || true
    fi
    if [[ "$return_mode" == "hosted" ]]; then
      osascript -e 'tell application "Safari" to activate' >/dev/null 2>&1 || true
    else
      osascript <<'APPLESCRIPT' >/dev/null 2>&1 || true
tell application "Terminal"
  if (count of windows) > 0 then set miniaturized of front window to false
  activate
end tell
APPLESCRIPT
    fi
    return 0
  fi
  dialog_message "Nao foi possivel abrir" "Abra manualmente CoreCAIJ/mac-ui/index.html no Safari."
  return 1
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
  local grade pintura obs inc include_os payload base confirm
  read "grade?Grade (A/B/C/T/RMA) [A]: "
  if [[ -z "$grade" ]]; then grade="A"; fi
  if [[ "$(trim "$grade" | tr '[:lower:]' '[:upper:]')" == "C" ]]; then
    while true; do
      read "pintura?Tipo de pintura para Grade C (1/2/3): "
      grade="$(normalize_grade "C" "$pintura")"
      if [[ "$grade" != "C" ]]; then break; fi
      echo "Selecione Pintura 1, 2 ou 3 antes de continuar."
    done
  else
    grade="$(normalize_grade "$grade" "")"
  fi
  read "obs?Observacoes para etiqueta: "
  while [[ ( "$grade" == "B" || "$grade" =~ '^C[[:space:]]*-[[:space:]]*PINTURA' ) && -z "$(trim "$obs")" ]]; do
    echo "Observacoes sao obrigatorias para Grade B e Grade C - Pintura."
    read "obs?Observacoes para etiqueta: "
  done
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
warn_if_no_internet || true
collect_info
sync_os >/dev/null 2>&1

if launch_web_ui; then
  exit 0
fi

if launch_local_static_ui; then
  exit 0
fi

if launch_portable_web_ui; then
  exit 0
fi

if launch_dialog_ui; then
  exit 0
fi

echo "Interface visual indisponivel; abrindo modo terminal."
sleep 1

while true; do
  check_os_alert "terminal"
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
