#!/usr/bin/env python3
import argparse
import json
import mimetypes
import os
import pathlib
import re
import shutil
import socket
import subprocess
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


PORTA_SERVIDOR = 9100
FALLBACK_SERVER = "http://INFOCAIJ:9100"
FALLBACK_SERVER_LOCAL = "http://INFOCAIJ.local:9100"
FALLBACK_SERVER_IP = "http://192.168.15.11:9100"


def format_os(value):
    return "C{:06d}".format(max(int(value), 0))


def normalize_server_url(value):
    raw = (value or "").strip().rstrip("/")
    if not raw:
        return FALLBACK_SERVER
    if raw.startswith("http://") or raw.startswith("https://"):
        return raw
    return "http://{}:{}".format(raw, PORTA_SERVIDOR)


def cpu_short(cpu):
    text = (cpu or "").strip()
    match = re.search(r"Apple\s+(M[0-9][^\s(]*)", text, re.I)
    if match:
        return "Apple {}".format(match.group(1))
    match = re.search(r"i([3579]).*?([0-9]{4,5})", text, re.I)
    if match:
        model = match.group(2)
        first_two = int(model[:2])
        generation = first_two if 10 <= first_two <= 19 else int(model[:1])
        mod100 = generation % 100
        suffix = "th"
        if not 11 <= mod100 <= 13:
            suffix = {1: "st", 2: "nd", 3: "rd"}.get(generation % 10, "th")
        return "i{} {}{}".format(match.group(1), generation, suffix)
    return text or "N/A"


def ram_short(ram):
    text = (ram or "").strip()
    match = re.search(r"([0-9]+)\s*GB", text, re.I)
    if not match:
        return text or "N/A"
    size = match.group(1)
    if re.search(r"Unificada", text, re.I):
        return "{}GB Unificada".format(size)
    kind = re.search(r"(LPDDR[345]|DDR[345])", text, re.I)
    if kind:
        return "{}GB {}".format(size, kind.group(1).upper())
    return "{}GB".format(size)


def disk_short(disk):
    text = (disk or "").strip()
    if re.search(r"1TB|\b(931|1000|1024)GB\b", text, re.I):
        return "1TB SSD"
    if re.search(r"\b(476|480|494|500|512)GB\b", text, re.I):
        return "512GB SSD"
    if re.search(r"\b(238|240|250|256)GB\b", text, re.I):
        return "256GB SSD"
    if re.search(r"\b(119|120|128)GB\b", text, re.I):
        return "128GB SSD"
    match = re.search(r"^(\d+GB)\s+(SSD|HDD)", text, re.I)
    if match:
        return "{} {}".format(match.group(1), match.group(2).upper())
    return text[:18] if text else "N/A"


def gpu_short(gpu):
    text = (gpu or "").strip()
    if not text or re.search(r"^(N/?A|Nao identificada|Nao identificada)$", text, re.I):
        return None
    match = re.search(r"Apple\s+(M[0-9][^(\s]*)", text, re.I)
    if match:
        return "Apple {}".format(match.group(1))
    if re.search(r"Iris\s*Xe", text, re.I):
        return "Intel Iris Xe"
    if re.search(r"UHD", text, re.I):
        return "Intel UHD"
    return text[:28]


def build_print_payload(info, os_numero, grade, obs, include_os, equipment_type="Notebook"):
    serial = (info.get("serial") or "").strip() or "XXXXXX"
    return {
        "os": int(os_numero) if include_os else None,
        "modelo": info.get("modelo") or "Apple MacBook",
        "serial": serial if serial != "N/A" else "XXXXXX",
        "tipoEquipamento": equipment_type,
        "cpu": cpu_short(info.get("cpu")),
        "gpu": gpu_short(info.get("gpu")),
        "ram": ram_short(info.get("ram")),
        "ramMods": ram_short(info.get("ram")),
        "disco": disk_short(info.get("disco")),
        "fichaCpu": info.get("cpu") or "N/A",
        "fichaGpu": info.get("gpu") or "N/A",
        "fichaRam": info.get("ram") or "N/A",
        "fichaDisco": info.get("disco") or "N/A",
        "modoManual": False,
        "bateria": info.get("bateria") or "N/A",
        "monitorTamanho": info.get("monitorTamanho") or "",
        "monitorEntradas": info.get("monitorEntradas") or "",
        "celularImei": info.get("imei") or "",
        "celularCiclos": info.get("ciclos") or "",
        "grade": (grade or "A").strip().upper(),
        "obs": obs or "",
    }


def validate_print_request(grade, obs):
    grade_text = (grade or "A").strip().upper()
    obs_text = (obs or "").strip()
    if grade_text == "B" and not obs_text:
        return "Observacoes sao obrigatorias para Grade B."
    if re.match(r"^(?:GRADE\s+)?C(?:\s*-\s*PINTURA\s*[123])?$", grade_text) and not obs_text:
        return "Observacoes sao obrigatorias para Grade C."
    return ""


class AppState:
    def __init__(self, core_dir, data_path):
        self.core_dir = pathlib.Path(core_dir)
        self.ui_dir = pathlib.Path(__file__).resolve().parent
        self.data_path = pathlib.Path(data_path)
        self.os_path = self.core_dir / "caij_os_counter.txt"
        self.server_config_path = self.core_dir / "caij_servidor_url.txt"
        self.history_path = self.core_dir / "caij_historico_notebooks.json"
        self.lock = threading.RLock()
        self.data = self.load_runtime_data()
        self.last_seen_confirmed = None
        self.pending_browser_event = None

    def load_runtime_data(self):
        try:
            return json.loads(self.data_path.read_text(encoding="utf-8-sig"))
        except Exception:
            return {"osNumero": self.read_os_number(), "info": {}}

    def save_runtime_data(self):
        self.data_path.write_text(json.dumps(self.data, ensure_ascii=False, indent=2), encoding="utf-8")

    def read_os_number(self):
        try:
            raw = self.os_path.read_text(encoding="utf-8-sig")
            num = int(re.sub(r"\D", "", raw) or "235")
            return max(num, 235)
        except Exception:
            return 235

    def set_os_number(self, value, manual=False):
        num = max(int(value), 1)
        self.os_path.write_text(str(num), encoding="utf-8")
        self.data["osNumero"] = num
        self.data["manualOsSet"] = bool(manual)
        self.save_runtime_data()
        return num

    def server_candidates(self):
        candidates = []
        try:
            candidates.append(self.server_config_path.read_text(encoding="utf-8-sig").strip())
        except Exception:
            pass
        if os.environ.get("CAIJ_SERVIDOR_URL"):
            candidates.append(os.environ["CAIJ_SERVIDOR_URL"])
        if os.environ.get("CAIJ_SERVIDOR_IP"):
            candidates.append(os.environ["CAIJ_SERVIDOR_IP"])
        candidates.extend((FALLBACK_SERVER_LOCAL, FALLBACK_SERVER, FALLBACK_SERVER_IP))
        normalized = []
        for item in candidates:
            if item and item.strip():
                value = normalize_server_url(item)
                if value not in normalized:
                    normalized.append(value)
        return normalized

    def server_url(self):
        candidates = self.server_candidates()
        return candidates[0] if candidates else FALLBACK_SERVER

    def request_server(self, path, method="GET", payload=None, timeout=12):
        data = None
        headers = {}
        if payload is not None:
            data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            headers["Content-Type"] = "application/json; charset=utf-8"
        last_error = None
        for base in self.server_candidates():
            parsed = urllib.parse.urlparse(base)
            try:
                socket.getaddrinfo(parsed.hostname, parsed.port or PORTA_SERVIDOR, type=socket.SOCK_STREAM)
            except socket.gaierror as exc:
                last_error = exc
                continue

            req = urllib.request.Request(base + path, data=data, headers=headers, method=method)
            try:
                with urllib.request.urlopen(req, timeout=timeout) as resp:
                    body = resp.read().decode("utf-8")
                    try:
                        self.server_config_path.write_text(base, encoding="utf-8")
                    except Exception:
                        pass
                    return json.loads(body) if body else {}
            except urllib.error.URLError as exc:
                last_error = exc
                if isinstance(exc.reason, (socket.gaierror, ConnectionRefusedError)):
                    continue
                raise
        if last_error:
            raise last_error
        raise ConnectionError("Servidor CAIJ nao encontrado.")

    def public_state(self):
        with self.lock:
            self.data["osNumero"] = self.read_os_number()
            return {
                "info": self.data.get("info", {}),
                "osNumero": self.data["osNumero"],
                "osFormatada": format_os(self.data["osNumero"]),
                "serverUrl": self.server_url(),
                "lastServerStatus": self.data.get("lastServerStatus", "nao verificado"),
                "lastOsSync": self.data.get("lastOsSync", ""),
                "pendingCreatedOs": int(self.data.get("pendingCreatedOs") or 0),
                "manualOsSet": bool(self.data.get("manualOsSet", False)),
                "equipmentType": self.data.get("equipmentType") or "Notebook",
            }

    def update_info(self, info, equipment_type=None):
        allowed = ("modelo", "serial", "cpu", "gpu", "ram", "disco", "bateria", "imei", "ciclos", "monitorTamanho", "monitorEntradas")
        with self.lock:
            current = self.data.setdefault("info", {})
            for key in allowed:
                if key in info:
                    current[key] = str(info.get(key) or "").strip()
            if equipment_type in ("Notebook", "Desktop", "Celular", "Monitor"):
                self.data["equipmentType"] = equipment_type
            self.save_runtime_data()
            return self.public_state()

    def sync_os(self):
        resp = self.request_server("/status-os", timeout=12)
        next_num = resp.get("proximoDisponivel")
        if next_num:
            with self.lock:
                self.set_os_number(int(next_num))
                self.data["lastServerStatus"] = "online"
                self.data["lastOsSync"] = time.strftime("%d/%m %H:%M")
                self.save_runtime_data()
        return self.public_state()

    def reserve_os(self):
        resp = self.request_server("/proxima-os", method="POST", payload={}, timeout=12)
        num = resp.get("osNumero")
        if num:
            return self.set_os_number(int(num))
        return self.read_os_number()

    def watch_os(self):
        resp = self.request_server("/status-os-local", timeout=5)
        confirmed = int(resp.get("ultimoConfirmado") or 0)
        next_num = int(resp.get("proximoDisponivel") or (confirmed + 1))
        with self.lock:
            previous = self.last_seen_confirmed
            is_new = previous is not None and confirmed > previous
            self.last_seen_confirmed = max(previous or 0, confirmed)
            pending_created = int(self.data.get("pendingCreatedOs") or 0)
            manual_os = bool(self.data.get("manualOsSet", False))
            if not pending_created and not manual_os and next_num > 0 and next_num != self.read_os_number():
                self.set_os_number(next_num)
            self.data["lastServerStatus"] = "online"
            self.data["lastOsSync"] = time.strftime("%d/%m %H:%M")
            self.save_runtime_data()
            event_data = {
                "ok": True,
                "event": is_new,
                "osCriadaNumero": confirmed,
                "osCriada": format_os(confirmed) if confirmed else "",
                "proximaOsNumero": next_num,
                "proximaOs": format_os(next_num),
                "state": self.public_state(),
            }
            if is_new:
                self.pending_browser_event = event_data
                self.show_native_os_alert(event_data)
            return event_data

    def consume_os_event(self):
        with self.lock:
            if self.pending_browser_event:
                event_data = self.pending_browser_event
                self.pending_browser_event = None
                return event_data
            return {"ok": True, "event": False, "state": self.public_state()}

    def show_native_os_alert(self, event_data):
        osascript = shutil.which("osascript")
        if not osascript:
            return
        created = str(event_data.get("osCriada") or "Nova OS")
        next_os = str(event_data.get("proximaOs") or "")
        message = "{} foi criada em outra estacao.\n\nProxima OS disponivel: {}".format(created, next_os)
        message = message.replace("\\", "\\\\").replace('"', '\\"')
        script = (
            'tell application "System Events"\n'
            'activate\n'
            'display dialog "{}" with title "InfoNotebook - Nova OS" '
            'buttons {{"Continuar com {}"}} default button 1 with icon note\n'
            'end tell'
        ).format(message, next_os.replace('"', '\\"'))
        try:
            subprocess.Popen(
                [osascript, "-e", script],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except Exception:
            pass

    def search_products(self, term):
        query = str(term or "").strip()
        if len(query) < 2:
            return {"ok": False, "message": "Digite pelo menos 2 caracteres.", "produtos": []}
        response = self.request_server(
            "/buscar-opcoes-altertag",
            method="POST",
            payload={"tipo": "produto", "termo": query, "modo": "catalogo"},
            timeout=25,
        )
        if str(response.get("status") or "").lower() != "ok":
            return {"ok": False, "message": response.get("mensagem") or "Nenhum produto encontrado.", "produtos": []}
        return {
            "ok": True,
            "message": response.get("mensagem") or "Produtos encontrados.",
            "fonte": response.get("fonte") or "Altertag",
            "produtos": response.get("produtos") or [],
        }

    def create_os(self, request_data):
        technician = str(request_data.get("tecnico") or "").strip()
        serial = str(request_data.get("serial") or "").strip()
        product = request_data.get("produto") or {}
        reference = str(request_data.get("referencia") or "GRADE T - TRIAGEM").strip()
        if not technician:
            return {"ok": False, "message": "Selecione o tecnico."}
        if not serial:
            return {"ok": False, "message": "Informe o serial."}
        if not product:
            return {"ok": False, "message": "Selecione um produto do Altertag."}

        payload = {
            "tecnico": technician,
            "serial": serial,
            "referencia": reference,
            "idProduto": int(product.get("idProduto") or 0),
            "produtoCodigo": str(product.get("codigo") or product.get("produtoCodigo") or ""),
            "produtoDescricao": str(product.get("descricao") or product.get("nome") or ""),
            "produtoValor": str(product.get("valor") or "0.00"),
            "servicos": request_data.get("servicos") or [],
            "tipoEquipamento": request_data.get("equipmentType") or self.data.get("equipmentType") or "Notebook",
            "observacao": str(request_data.get("observacao") or "").strip(),
        }
        response = self.request_server("/criar-os-altertag", method="POST", payload=payload, timeout=45)
        if str(response.get("status") or "").lower() != "ok":
            return {"ok": False, "message": response.get("mensagem") or "Falha ao criar OS."}

        created = int(response.get("osNumero") or 0)
        next_num = int(response.get("proximoDisponivel") or (created + 1))
        if created:
            self.set_os_number(created)
            self.last_seen_confirmed = max(self.last_seen_confirmed or 0, created)
        with self.lock:
            self.data["equipmentType"] = payload["tipoEquipamento"]
            self.data["pendingCreatedOs"] = created
            self.data["lastServerStatus"] = "online"
            self.data["lastOsSync"] = time.strftime("%d/%m %H:%M")
            self.save_runtime_data()
        return {
            "ok": True,
            "message": "OS {} criada com sucesso.".format(format_os(created)),
            "osCriada": format_os(created),
            "proximaOs": format_os(next_num),
            "response": response,
            "state": self.public_state(),
        }

    def add_log(self, status, message, grade, obs):
        entry = {
            "dataHora": time.strftime("%Y-%m-%d %H:%M:%S"),
            "os": format_os(self.read_os_number()),
            "osNumero": self.read_os_number(),
            "status": status,
            "acao": "impressao",
            "mensagem": message,
            "serial": self.data.get("info", {}).get("serial", ""),
            "modelo": self.data.get("info", {}).get("modelo", ""),
            "grade": grade,
            "observacoes": obs,
            "servidor": self.data.get("lastServerStatus", "nao verificado"),
            "osSincronizadaEm": self.data.get("lastOsSync", ""),
            "computador": socket.gethostname(),
            "usuario": os.environ.get("USER") or os.environ.get("USERNAME") or "",
        }
        log_dir = self.core_dir.parent.parent / "CAIJ-Registros"
        try:
            log_dir.mkdir(parents=True, exist_ok=True)
            log_path = log_dir / ("impressao-" + time.strftime("%Y-%m-%d") + ".log")
            with log_path.open("a", encoding="utf-8") as handle:
                handle.write(json.dumps(entry, ensure_ascii=False) + "\n")
        except Exception:
            pass

    def print_label(self, request_data):
        grade = (request_data.get("grade") or "A").strip()
        obs = (request_data.get("obs") or "").strip()
        include_os = bool(request_data.get("includeOs", True))
        error = validate_print_request(grade, obs)
        if error:
            return {"ok": False, "message": error}
        with self.lock:
            if request_data.get("info"):
                self.update_info(request_data["info"], request_data.get("equipmentType"))
            pending_created = int(self.data.get("pendingCreatedOs") or 0)
            manual_os = bool(self.data.get("manualOsSet", False))
            if include_os and not pending_created and not manual_os:
                try:
                    self.reserve_os()
                except Exception:
                    pass
            equipment_type = request_data.get("equipmentType") or self.data.get("equipmentType") or "Notebook"
            self.data["equipmentType"] = equipment_type
            payload = build_print_payload(self.data.get("info", {}), self.read_os_number(), grade, obs, include_os, equipment_type)
        try:
            server_response = self.request_server("/imprimir", method="POST", payload=payload, timeout=20)
            with self.lock:
                self.data["lastServerStatus"] = "online"
                self.save_runtime_data()
            self.add_log("ok", "Etiqueta enviada com sucesso", payload["grade"], payload["obs"])
            if include_os:
                with self.lock:
                    self.data["pendingCreatedOs"] = 0
                    self.data["manualOsSet"] = False
                    self.save_runtime_data()
                try:
                    self.sync_os()
                except Exception:
                    pass
            tracker = server_response.get("rastreador") if isinstance(server_response, dict) else None
            sync_warning = isinstance(tracker, dict) and str(tracker.get("status") or "").lower() == "warning"
            message = server_response.get("mensagem") if isinstance(server_response, dict) else ""
            return {
                "ok": True,
                "message": message or "Etiqueta enviada com sucesso.",
                "payload": payload,
                "tracker": tracker,
                "syncWarning": sync_warning,
                "state": self.public_state(),
            }
        except Exception as exc:
            with self.lock:
                self.data["lastServerStatus"] = "offline"
                self.save_runtime_data()
            self.add_log("erro", str(exc), payload["grade"], payload["obs"])
            return {"ok": False, "message": "Falha ao imprimir: {}".format(exc), "payload": payload, "state": self.public_state()}


def make_handler(app_state, stop_event):
    class Handler(BaseHTTPRequestHandler):
        server_version = "CAIJMacUI/1.0"

        def log_message(self, fmt, *args):
            return

        def send_json(self, status, data):
            raw = json.dumps(data, ensure_ascii=False).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(raw)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(raw)

        def read_json(self):
            length = int(self.headers.get("Content-Length") or "0")
            if not length:
                return {}
            return json.loads(self.rfile.read(length).decode("utf-8"))

        def do_GET(self):
            if self.path == "/" or self.path.startswith("/index.html"):
                return self.serve_file(app_state.ui_dir / "index.html")
            if self.path == "/style.css":
                return self.serve_file(app_state.ui_dir / "style.css")
            if self.path == "/app.js":
                return self.serve_file(app_state.ui_dir / "app.js")
            if self.path == "/portable.js":
                return self.serve_file(app_state.ui_dir / "portable.js")
            if self.path == "/runtime-loader.js":
                return self.serve_file(app_state.ui_dir / "runtime-loader.js")
            if self.path == "/caij-runtime.js":
                runtime_js = b"window.CAIJ_NATIVE_RUNTIME = null;\n"
                self.send_response(200)
                self.send_header("Content-Type", "application/javascript; charset=utf-8")
                self.send_header("Content-Length", str(len(runtime_js)))
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                self.wfile.write(runtime_js)
                return
            if self.path == "/logo.png":
                return self.serve_file(app_state.core_dir / "caij-logo.png")
            if self.path == "/api/state":
                return self.send_json(200, app_state.public_state())
            if self.path == "/api/os-watch":
                return self.send_json(200, app_state.consume_os_event())
            return self.send_json(404, {"ok": False, "message": "Nao encontrado"})

        def do_POST(self):
            try:
                if self.path == "/api/print":
                    return self.send_json(200, app_state.print_label(self.read_json()))
                if self.path == "/api/info":
                    request_data = self.read_json()
                    return self.send_json(200, app_state.update_info(request_data.get("info", {}), request_data.get("equipmentType")))
                if self.path == "/api/sync-os":
                    return self.send_json(200, app_state.sync_os())
                if self.path == "/api/products":
                    return self.send_json(200, app_state.search_products(self.read_json().get("term", "")))
                if self.path == "/api/create-os":
                    result = app_state.create_os(self.read_json())
                    return self.send_json(200 if result.get("ok") else 400, result)
                if self.path == "/api/set-os":
                    num = self.read_json().get("osNumero")
                    return self.send_json(200, {"osNumero": app_state.set_os_number(int(num), manual=True), "state": app_state.public_state()})
                if self.path == "/api/shutdown":
                    stop_event.set()
                    return self.send_json(200, {"ok": True})
                return self.send_json(404, {"ok": False, "message": "Nao encontrado"})
            except Exception as exc:
                return self.send_json(500, {"ok": False, "message": str(exc)})

        def serve_file(self, path):
            try:
                raw = pathlib.Path(path).read_bytes()
            except Exception:
                return self.send_json(404, {"ok": False, "message": "Arquivo nao encontrado"})
            content_type = mimetypes.guess_type(str(path))[0] or "application/octet-stream"
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(raw)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(raw)

    return Handler


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--core", required=True)
    parser.add_argument("--data", required=True)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=0)
    args = parser.parse_args()

    stop_event = threading.Event()
    app_state = AppState(args.core, args.data)

    def monitor_os():
        while not stop_event.is_set():
            try:
                app_state.watch_os()
            except Exception:
                pass
            stop_event.wait(4)

    monitor_thread = threading.Thread(target=monitor_os, name="caij-os-monitor", daemon=True)
    monitor_thread.start()
    httpd = ThreadingHTTPServer((args.host, args.port), make_handler(app_state, stop_event))
    url = "http://{}:{}/".format(httpd.server_address[0], httpd.server_address[1])
    print("Interface CAIJ aberta em {}".format(url), flush=True)
    webbrowser.open(url)

    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    try:
        while not stop_event.is_set():
            time.sleep(0.2)
    except KeyboardInterrupt:
        pass
    httpd.shutdown()
    httpd.server_close()


if __name__ == "__main__":
    main()
