#!/usr/bin/env python3
import argparse
import json
import mimetypes
import os
import pathlib
import re
import socket
import threading
import time
import urllib.error
import urllib.request
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


PORTA_SERVIDOR = 9100
FALLBACK_SERVER = "http://192.168.15.127:9100"


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
        gen = model[:2] if len(model) >= 5 else model[:1]
        return "I{} {}".format(match.group(1), gen)
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


def build_print_payload(info, os_numero, grade, obs, include_os):
    serial = (info.get("serial") or "").strip() or "XXXXXX"
    return {
        "os": int(os_numero) if include_os else None,
        "modelo": info.get("modelo") or "Apple MacBook",
        "serial": serial if serial != "N/A" else "XXXXXX",
        "cpu": cpu_short(info.get("cpu")),
        "gpu": gpu_short(info.get("gpu")),
        "ram": ram_short(info.get("ram")),
        "ramMods": ram_short(info.get("ram")),
        "disco": disk_short(info.get("disco")),
        "modoManual": False,
        "bateria": info.get("bateria") or "N/A",
        "grade": (grade or "A").strip().upper(),
        "obs": obs or "",
    }


def validate_print_request(grade, obs):
    grade_text = (grade or "A").strip().upper()
    obs_text = (obs or "").strip()
    if grade_text == "B" and not obs_text:
        return "Observacoes sao obrigatorias para Grade B."
    if re.match(r"^C\s*-\s*PINTURA", grade_text) and not obs_text:
        return "Observacoes sao obrigatorias para Grade C - Pintura."
    if re.match(r"^T\s*-\s*TRIAGEM", grade_text) and not obs_text:
        return "Observacoes sao obrigatorias para Grade T - Triagem."
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

    def set_os_number(self, value):
        num = max(int(value), 1)
        self.os_path.write_text(str(num), encoding="utf-8")
        self.data["osNumero"] = num
        self.save_runtime_data()
        return num

    def server_url(self):
        candidates = []
        try:
            candidates.append(self.server_config_path.read_text(encoding="utf-8-sig").strip())
        except Exception:
            pass
        if os.environ.get("CAIJ_SERVIDOR_URL"):
            candidates.append(os.environ["CAIJ_SERVIDOR_URL"])
        if os.environ.get("CAIJ_SERVIDOR_IP"):
            candidates.append(os.environ["CAIJ_SERVIDOR_IP"])
        candidates.append(FALLBACK_SERVER)
        for item in candidates:
            if item and item.strip():
                return normalize_server_url(item)
        return FALLBACK_SERVER

    def request_server(self, path, method="GET", payload=None, timeout=12):
        base = self.server_url()
        data = None
        headers = {}
        if payload is not None:
            data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            headers["Content-Type"] = "application/json; charset=utf-8"
        req = urllib.request.Request(base + path, data=data, headers=headers, method=method)
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = resp.read().decode("utf-8")
            return json.loads(body) if body else {}

    def public_state(self):
        with self.lock:
            self.data["osNumero"] = self.read_os_number()
            return {
                "info": self.data.get("info", {}),
                "osNumero": self.data["osNumero"],
                "osFormatada": "C000{}".format(self.data["osNumero"]),
                "serverUrl": self.server_url(),
                "lastServerStatus": self.data.get("lastServerStatus", "nao verificado"),
                "lastOsSync": self.data.get("lastOsSync", ""),
            }

    def update_info(self, info):
        allowed = ("modelo", "serial", "cpu", "gpu", "ram", "disco", "bateria")
        with self.lock:
            current = self.data.setdefault("info", {})
            for key in allowed:
                if key in info:
                    current[key] = str(info.get(key) or "").strip()
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

    def add_log(self, status, message, grade, obs):
        entry = {
            "dataHora": time.strftime("%Y-%m-%d %H:%M:%S"),
            "os": "C000{}".format(self.read_os_number()),
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
                self.update_info(request_data["info"])
            if include_os:
                try:
                    self.reserve_os()
                except Exception:
                    pass
            payload = build_print_payload(self.data.get("info", {}), self.read_os_number(), grade, obs, include_os)
        try:
            self.request_server("/imprimir", method="POST", payload=payload, timeout=20)
            with self.lock:
                self.data["lastServerStatus"] = "online"
                self.save_runtime_data()
            self.add_log("ok", "Etiqueta enviada com sucesso", payload["grade"], payload["obs"])
            if include_os:
                try:
                    self.sync_os()
                except Exception:
                    pass
            return {"ok": True, "message": "Etiqueta enviada com sucesso.", "payload": payload, "state": self.public_state()}
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
            if self.path == "/logo.png":
                return self.serve_file(app_state.core_dir / "caij-logo.png")
            if self.path == "/api/state":
                return self.send_json(200, app_state.public_state())
            return self.send_json(404, {"ok": False, "message": "Nao encontrado"})

        def do_POST(self):
            try:
                if self.path == "/api/print":
                    return self.send_json(200, app_state.print_label(self.read_json()))
                if self.path == "/api/info":
                    return self.send_json(200, app_state.update_info(self.read_json().get("info", {})))
                if self.path == "/api/sync-os":
                    return self.send_json(200, app_state.sync_os())
                if self.path == "/api/set-os":
                    num = self.read_json().get("osNumero")
                    return self.send_json(200, {"osNumero": app_state.set_os_number(int(num)), "state": app_state.public_state()})
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
