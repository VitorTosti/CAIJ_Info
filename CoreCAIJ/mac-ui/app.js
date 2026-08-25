const state = {
  info: {},
  grade: "A",
  paint: "1",
  watchingOs: false,
  createOs: {
    technician: "",
    product: null,
  },
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
  if (state.grade === "T") return "T - TRIAGEM";
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

function showOsAlert(data) {
  qs("alertCreatedOs").textContent = data.osCriada || "Nova OS";
  qs("alertNextOs").textContent = data.proximaOs || qs("osNumber").textContent;
  qs("osAlert").classList.remove("hidden");
  qs("dismissOsAlert").focus();
}

function closeOsAlert() {
  qs("osAlert").classList.add("hidden");
}

function productLabel(product) {
  const code = product.codigo || product.produtoCodigo || "SEM CODIGO";
  const description = product.descricao || product.nome || product.texto || "Produto";
  return `${code} | ${description}`;
}

function updateCreateOsState() {
  const other = qs("otherTechnician").value.trim();
  const technician = state.createOs.technician === "Outro" ? other : state.createOs.technician;
  const ready = Boolean(technician && state.createOs.product && qs("createSerial").value.trim());
  qs("submitCreateOs").disabled = !ready;
  qs("createOsStatus").textContent = state.createOs.product
    ? `Selecionado: ${productLabel(state.createOs.product)}`
    : "Selecione o tecnico e o produto.";
}

function openCreateOs() {
  state.createOs.technician = "";
  state.createOs.product = null;
  qs("technicianGrid").querySelectorAll("button").forEach((button) => button.classList.remove("active"));
  qs("otherTechnician").value = "";
  qs("otherTechnician").classList.add("hidden");
  qs("productSearch").value = state.info.modelo || "";
  qs("createSerial").value = state.info.serial || "";
  qs("createObservation").value = "";
  qs("productResults").innerHTML = "<p>Pesquise e selecione um produto.</p>";
  updateCreateOsState();
  qs("createOsDialog").showModal();
}

function closeCreateOs() {
  qs("createOsDialog").close();
}

function renderProductResults(products) {
  const container = qs("productResults");
  if (!products.length) {
    container.innerHTML = "<p>Nenhum produto encontrado.</p>";
    return;
  }
  container.innerHTML = products.map((product, index) => `
    <button type="button" data-product-index="${index}">
      <strong>${escapeHtml(product.codigo || product.produtoCodigo || "--")}</strong>
      <span>${escapeHtml(product.descricao || product.nome || product.texto || "Produto")}</span>
    </button>
  `).join("");
  container.querySelectorAll("button").forEach((button) => {
    button.addEventListener("click", () => {
      state.createOs.product = products[Number(button.dataset.productIndex)];
      container.querySelectorAll("button").forEach((item) => item.classList.toggle("active", item === button));
      updateCreateOsState();
    });
  });
}

async function watchOs() {
  if (state.watchingOs) return;
  state.watchingOs = true;
  try {
    const data = await api("/api/os-watch");
    if (data.state && data.event) {
      applyState(data.state);
      showOsAlert(data);
      setStatus(`${data.osCriada} criada. Sistema atualizado para ${data.proximaOs}.`, "ok");
    }
  } catch (_) {
    // A perda momentanea do servidor nao deve interromper o trabalho na etiqueta.
  } finally {
    state.watchingOs = false;
  }
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

  qs("openCreateOs").addEventListener("click", openCreateOs);
  qs("closeCreateOs").addEventListener("click", closeCreateOs);
  qs("cancelCreateOs").addEventListener("click", closeCreateOs);
  qs("createOsDialog").addEventListener("click", (event) => {
    if (event.target === qs("createOsDialog")) closeCreateOs();
  });

  qs("technicianGrid").querySelectorAll("button").forEach((button) => {
    button.addEventListener("click", () => {
      state.createOs.technician = button.dataset.technician;
      qs("technicianGrid").querySelectorAll("button").forEach((item) => item.classList.toggle("active", item === button));
      qs("otherTechnician").classList.toggle("hidden", state.createOs.technician !== "Outro");
      if (state.createOs.technician === "Outro") qs("otherTechnician").focus();
      updateCreateOsState();
    });
  });
  qs("otherTechnician").addEventListener("input", updateCreateOsState);
  qs("createSerial").addEventListener("input", updateCreateOsState);

  qs("searchProducts").addEventListener("click", async () => {
    const term = qs("productSearch").value.trim();
    qs("productResults").innerHTML = "<p>Buscando produtos...</p>";
    try {
      const data = await api("/api/products", { term });
      renderProductResults(data.produtos || []);
    } catch (err) {
      qs("productResults").innerHTML = `<p>${escapeHtml(err.message)}</p>`;
    }
  });
  qs("productSearch").addEventListener("keydown", (event) => {
    if (event.key === "Enter") {
      event.preventDefault();
      qs("searchProducts").click();
    }
  });

  qs("createOsForm").addEventListener("submit", async (event) => {
    event.preventDefault();
    const technician = state.createOs.technician === "Outro"
      ? qs("otherTechnician").value.trim()
      : state.createOs.technician;
    const body = {
      tecnico: technician,
      serial: qs("createSerial").value.trim(),
      referencia: qs("createReference").value,
      observacao: qs("createObservation").value.trim(),
      produto: state.createOs.product,
      servicos: [],
    };
    qs("submitCreateOs").disabled = true;
    qs("createOsStatus").textContent = "Criando OS no Altertag...";
    try {
      const data = await api("/api/create-os", body);
      if (data.state) applyState(data.state);
      closeCreateOs();
      setStatus(`${data.osCriada} criada com sucesso.`, "ok");
    } catch (err) {
      updateCreateOsState();
      qs("createOsStatus").textContent = err.message;
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

  qs("dismissOsAlert").addEventListener("click", closeOsAlert);
  qs("osAlert").addEventListener("click", (event) => {
    if (event.target === qs("osAlert")) closeOsAlert();
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && !qs("createOsDialog").open) closeOsAlert();
  });
}

wireControls();
loadState().then(watchOs);
setInterval(watchOs, 4000);
