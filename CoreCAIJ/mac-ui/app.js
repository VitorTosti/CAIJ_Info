const state = {
  info: {},
  grade: "A",
  paint: "1",
};

const fields = ["modelo", "serial", "cpu", "gpu", "ram", "disco", "bateria"];
const labels = {
  modelo: "Modelo",
  serial: "Serial",
  cpu: "CPU",
  gpu: "GPU",
  ram: "RAM",
  disco: "Disco",
  bateria: "Bateria",
};

function qs(id) {
  return document.getElementById(id);
}

async function api(path, body) {
  const options = body ? {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=utf-8" },
    body: JSON.stringify(body),
  } : {};
  const response = await fetch(path, options);
  const data = await response.json();
  if (!response.ok || data.ok === false) {
    throw new Error(data.message || "Falha na operacao");
  }
  return data;
}

function setStatus(message, type = "") {
  const el = qs("statusLine");
  el.className = `status-line ${type}`.trim();
  el.textContent = message;
}

function gradeValue() {
  if (state.grade === "C") return `C - PINTURA ${state.paint}`;
  return state.grade;
}

function renderDevice() {
  const read = qs("deviceRead");
  read.innerHTML = fields.map((key, index) => `
    <div class="device-item" style="animation-delay:${index * 35}ms">
      <span>${labels[key]}</span>
      <strong>${escapeHtml(state.info[key] || "N/A")}</strong>
    </div>
  `).join("");

  const form = qs("editForm");
  fields.forEach((key) => {
    const input = form.elements[key];
    if (input) input.value = state.info[key] || "";
  });
  renderPreview();
}

function renderPreview() {
  qs("previewModel").textContent = state.info.modelo || "Apple MacBook";
  qs("previewSpecs").textContent = [
    state.info.cpu || "CPU",
    state.info.ram || "RAM",
    state.info.disco || "Disco",
  ].join(" | ");
  qs("previewGrade").textContent = `Grade ${gradeValue()}`;
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function applyState(data) {
  state.info = data.info || state.info || {};
  qs("osNumber").textContent = data.osFormatada || `C000${data.osNumero || 235}`;
  qs("serverLine").textContent = `Servidor: ${data.serverUrl || "nao configurado"} | ${data.lastServerStatus || "nao verificado"}`;
  renderDevice();
}

async function loadState() {
  try {
    const data = await api("/api/state");
    applyState(data);
    setStatus("Pronto.");
  } catch (err) {
    setStatus(err.message, "warn");
  }
}

function wireControls() {
  document.querySelectorAll(".grade").forEach((button) => {
    button.addEventListener("click", () => {
      state.grade = button.dataset.grade;
      document.querySelectorAll(".grade").forEach((b) => b.classList.toggle("active", b === button));
      qs("paintRow").classList.toggle("hidden", state.grade !== "C");
      renderPreview();
    });
  });

  document.querySelectorAll(".paint").forEach((button) => {
    button.addEventListener("click", () => {
      state.paint = button.dataset.paint;
      document.querySelectorAll(".paint").forEach((b) => b.classList.toggle("active", b === button));
      renderPreview();
    });
  });

  qs("editToggle").addEventListener("click", () => {
    qs("deviceRead").classList.toggle("hidden");
    qs("editForm").classList.toggle("hidden");
  });

  qs("editForm").addEventListener("submit", async (event) => {
    event.preventDefault();
    const formData = new FormData(event.currentTarget);
    const info = {};
    fields.forEach((key) => info[key] = formData.get(key) || "");
    setStatus("Salvando dados...", "busy");
    try {
      const data = await api("/api/info", { info });
      applyState(data);
      qs("deviceRead").classList.remove("hidden");
      qs("editForm").classList.add("hidden");
      setStatus("Dados atualizados.", "ok");
    } catch (err) {
      setStatus(err.message, "warn");
    }
  });

  qs("syncOs").addEventListener("click", async () => {
    setStatus("Sincronizando OS com o servidor...", "busy");
    try {
      const data = await api("/api/sync-os", {});
      applyState(data);
      setStatus("OS sincronizada.", "ok");
    } catch (err) {
      setStatus(err.message, "warn");
    }
  });

  qs("printBtn").addEventListener("click", async () => {
    const body = {
      grade: gradeValue(),
      obs: qs("obs").value.trim(),
      includeOs: qs("includeOs").checked,
      info: state.info,
    };
    setStatus("Enviando etiqueta para impressao...", "busy");
    try {
      const data = await api("/api/print", body);
      if (data.state) applyState(data.state);
      setStatus(data.message || "Etiqueta enviada.", "ok");
    } catch (err) {
      setStatus(err.message, "warn");
    }
  });
}

wireControls();
loadState();
