const state = {
  info: {},
  equipmentType: "Notebook",
  grade: "A",
  view: "home",
  watchingOs: false,
  createOs: {
    technician: "",
    product: null,
  },
  device3u: null,
  awaitingDeviceImport: false,
  osDetail: null,
  tests: {
    camera: "pending",
    keyboard: "pending",
    audio: "pending",
    screen: "pending",
    trackpad: "pending",
  },
  activeTest: "",
  mediaStream: null,
  audioContext: null,
  audioFrame: 0,
  keyboardHandler: null,
  environment: {
    internetOnline: true,
    serverOnline: false,
  },
  lastPrint: readLastPrint(),
  printHistory: readPrintHistory(),
  operationalError: "",
  osCreatedInSession: false,
};

const fields = ["modelo", "serial", "cpu", "gpu", "ram", "disco", "bateria"];
const labelFields = [...fields, "imei", "ciclos", "monitorTamanho", "monitorEntradas"];
const labels = {
  modelo: "Modelo",
  serial: "Serial",
  cpu: "CPU",
  gpu: "GPU",
  ram: "RAM",
  disco: "Disco",
  bateria: "Bateria",
};

const testLabels = {
  camera: "Camera",
  keyboard: "Teclado",
  audio: "Som/Mic",
  screen: "Tela",
  trackpad: "Trackpad",
};

const nativeRuntime = window.CAIJ_NATIVE_RUNTIME || {};
const isWindowsPreview = String(nativeRuntime.platform || "").toLowerCase() === "windows";
const testsOnlyMode = new URLSearchParams(window.location.search).get("tests") === "1" ||
  (window.location.protocol === "file:" && !window.CAIJ_NATIVE_RUNTIME);
const defaultModelName = isWindowsPreview ? "Notebook Windows" : "Apple MacBook";
let statusTimer = 0;

function applyPlatformUi() {
  if (!isWindowsPreview) return;
  document.body.classList.add("windows-preview");
  document.title = "CAIJ InfoNotebook Windows - Previa";
  qs("platformName").textContent = "Windows";
  qs("brandKicker").classList.add("hidden");
  qs("serverLine").classList.add("hidden");
  qs("versionBadge").classList.add("hidden");
  qs("devicePanelTitle").textContent = "Informacoes do Windows";
  qs("testsTitle").textContent = "Central de testes Windows";
  qs("pointingDeviceTitle").textContent = "Mouse / Touchpad";
  qs("pointingDeviceDescription").textContent = "Validar movimento, cliques e rolagem.";
  testLabels.trackpad = "Mouse / Touchpad";
  document.querySelectorAll(".windows-only").forEach((element) => element.classList.remove("hidden"));
}

function qs(id) {
  return document.getElementById(id);
}

async function api(path, body) {
  if (window.CAIJ_PORTABLE_API) {
    return window.CAIJ_PORTABLE_API(path, body);
  }
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
  window.clearTimeout(statusTimer);
  el.className = `status-line ${type}`.trim();
  el.textContent = message;
  const isIdle = !String(message || "").trim() || String(message).trim().toLowerCase() === "pronto.";
  el.hidden = isIdle;
  if (!isIdle && type === "ok") {
    statusTimer = window.setTimeout(() => { el.hidden = true; }, 3200);
  }
  if (type === "warn") state.operationalError = String(message || "").trim();
  if (type === "ok") state.operationalError = "";
  renderOperationalDashboard();
}

function setButtonBusy(button, busy, busyLabel = "Processando...") {
  if (!button) return;
  if (busy) {
    button.dataset.idleLabel = button.textContent.trim();
    button.dataset.wasDisabled = String(button.disabled);
    button.textContent = busyLabel;
    button.disabled = true;
    button.classList.add("is-busy");
    button.setAttribute("aria-busy", "true");
    return;
  }
  button.textContent = button.dataset.idleLabel || button.textContent;
  button.disabled = button.dataset.wasDisabled === "true";
  button.classList.remove("is-busy");
  button.removeAttribute("aria-busy");
  delete button.dataset.idleLabel;
  delete button.dataset.wasDisabled;
}

function readLastPrint() {
  try {
    return JSON.parse(localStorage.getItem("caij:last-print") || "null");
  } catch (_) {
    return null;
  }
}

function readPrintHistory() {
  try {
    const saved = JSON.parse(localStorage.getItem("caij:print-history") || "null");
    if (Array.isArray(saved)) return saved.filter((entry) => entry && typeof entry === "object").slice(0, 8);
  } catch (_) {}
  const legacy = readLastPrint();
  return legacy ? [legacy] : [];
}

function saveLastPrint(data) {
  const entry = { ...data, printedAt: data.printedAt || new Date().toISOString() };
  state.lastPrint = entry;
  state.printHistory = [entry, ...(state.printHistory || [])].slice(0, 8);
  try {
    localStorage.setItem("caij:last-print", JSON.stringify(entry));
    localStorage.setItem("caij:print-history", JSON.stringify(state.printHistory));
  } catch (_) {}
  renderOperationalDashboard();
}

function renderPrintHistory() {
  const history = Array.isArray(state.printHistory) ? state.printHistory : [];
  const list = qs("printHistoryList");
  const empty = qs("printHistoryEmpty");
  if (!list || !empty) return;
  qs("printHistoryPanel").classList.toggle("is-empty", history.length === 0);
  qs("printHistoryCount").textContent = `${history.length} ${history.length === 1 ? "impressão" : "impressões"}`;
  empty.classList.toggle("hidden", history.length > 0);
  list.classList.toggle("hidden", history.length === 0);
  list.innerHTML = history.map((entry, index) => `
    <li class="print-history-item">
      <span class="print-history-order">${String(index + 1).padStart(2, "0")}</span>
      <div class="print-history-main">
        <strong>${escapeHtml(entry.modelo || "Equipamento não informado")}</strong>
        <span>${escapeHtml(entry.serial || "Serial não informado")}</span>
      </div>
      <div class="print-history-tags">
        <span class="history-os">${escapeHtml(entry.os || "Sem OS")}</span>
        <span>${escapeHtml(entry.grade ? `Grade ${entry.grade}` : "Grade não informada")}</span>
        <span>${escapeHtml(entry.tipo || "Equipamento")}</span>
      </div>
      <time>${escapeHtml(entry.horario || "Horário não informado")}</time>
    </li>
  `).join("");
}

function hasUsefulValue(value) {
  const text = String(value || "").trim();
  return Boolean(text && !/^(?:N\/?A|NA|NÃO IDENTIFICAD[AO]|NAO IDENTIFICAD[AO])$/i.test(text));
}

function hasSerialDivergence() {
  if (!state.osDetail) return false;
  const serialOs = normalizeSerial(state.osDetail.serial);
  const serialMachine = normalizeSerial(state.info.serial);
  return Boolean(serialOs && serialOs !== "-" && serialMachine && serialMachine !== "N/A" && serialOs !== serialMachine);
}

function setWorkflowStep(id, statusId, text, stateClass) {
  const step = qs(id);
  if (!step) return;
  const previousState = step.dataset.workflowState || "";
  const nextState = stateClass || "";
  step.classList.remove("complete", "warning", "failed");
  if (stateClass) step.classList.add(stateClass);
  step.dataset.workflowState = nextState;
  if (previousState && previousState !== nextState && nextState === "complete") {
    step.classList.remove("just-completed");
    void step.offsetWidth;
    step.classList.add("just-completed");
  } else if (nextState !== "complete") step.classList.remove("just-completed");
  qs(statusId).textContent = text;
}

function renderOperationalDashboard() {
  if (!qs("workflowOverall")) return;
  const infoCount = fields.filter((key) => hasUsefulValue(state.info[key])).length;
  const testValues = Object.values(state.tests);
  const testsDone = testValues.filter((value) => value !== "pending").length;
  const testsFailed = testValues.filter((value) => value === "failed").length;
  const osNumber = osNumberFromInput();
  const osLabel = osNumber ? `C${String(osNumber).padStart(6, "0")}` : "Não selecionada";
  if (qs("createCurrentOs")) qs("createCurrentOs").textContent = osLabel;
  const osVerified = Boolean(state.osDetail && state.osDetail.online && !hasSerialDivergence());
  const osReady = isWindowsPreview ? osVerified : state.osCreatedInSession;
  const obsRequired = state.grade === "B" || state.grade === "C";
  const labelReady = hasUsefulValue(state.info.modelo) && hasUsefulValue(state.info.serial) && (!obsRequired || qs("obs").value.trim());
  const readComplete = infoCount === fields.length;
  const testsComplete = testsDone === testValues.length && testsFailed === 0;

  qs("equipmentSummaryText").textContent = `${infoCount} de ${fields.length} informações identificadas`;
  setWorkflowStep("workflowRead", "workflowReadStatus", `${infoCount} de ${fields.length} identificadas`, readComplete ? "complete" : "warning");
  setWorkflowStep("workflowTests", "workflowTestsStatus", testsFailed ? `${testsFailed} com falha` : `${testsDone} de ${testValues.length} realizados`, testsFailed ? "failed" : testsComplete ? "complete" : "warning");
  setWorkflowStep("workflowOs", "workflowOsStatus", osReady ? `${osLabel} conferida` : osLabel, osReady ? "complete" : "warning");
  setWorkflowStep("workflowLabel", "workflowLabelStatus", labelReady ? "Pronta para revisar" : "Informações pendentes", labelReady ? "complete" : "warning");

  const completed = [readComplete, testsComplete, osReady, labelReady].filter(Boolean).length;
  const pendingSteps = 4 - completed;
  qs("workflowOverall").textContent = `${completed} de 4 etapas`;
  qs("workflowOverall").title = pendingSteps ? `${pendingSteps} ${pendingSteps === 1 ? "etapa pendente" : "etapas pendentes"}` : "Fluxo pronto para finalizar";

  let next = { action: "labels", title: "Preparar etiqueta", description: "Confira a prévia antes de imprimir.", button: "Abrir etiquetas" };
  if (!readComplete) next = { action: "edit", title: "Completar informações", description: `${fields.length - infoCount} campos ainda precisam de revisão.`, button: "Revisar dados" };
  else if (!testsComplete) next = { action: "tests", title: testsFailed ? "Revisar testes" : "Executar testes", description: testsFailed ? "Há teste marcado com falha." : `${testValues.length - testsDone} testes ainda estão pendentes.`, button: "Abrir testes" };
  else if (!osReady) next = { action: "create-os", title: "Cadastrar OS", description: `${osLabel} ainda precisa ser conferida no AlterTag.`, button: "Cadastrar OS" };
  qs("nextActionTitle").textContent = next.title;
  qs("nextActionDescription").textContent = next.description;
  qs("nextActionButton").textContent = next.button;
  qs("nextActionButton").dataset.workflowAction = next.action;

  const alerts = [];
  const serialDivergent = hasSerialDivergence();
  if (!state.environment.internetOnline) alerts.push("Notebook sem conexão com a internet.");
  if (!state.environment.serverOnline) alerts.push("Servidor CAIJ indisponível.");
  if (serialDivergent) alerts.push(`Equipamento: ${state.info.serial || "não informado"} • OS: ${state.osDetail.serial || "não informada"}`);
  if (testsFailed) alerts.push(`${testsFailed} teste${testsFailed > 1 ? "s" : ""} marcado${testsFailed > 1 ? "s" : ""} com falha.`);
  if (state.operationalError) alerts.push(state.operationalError);
  const uniqueAlerts = [...new Set(alerts)];
  qs("operationalAlerts").classList.toggle("hidden", uniqueAlerts.length === 0);
  qs("operationalAlertTitle").textContent = serialDivergent ? "Serial divergente" : "Revisão necessária";
  qs("reviewSerialDivergence").classList.toggle("hidden", !serialDivergent);
  qs("operationalAlertsList").innerHTML = uniqueAlerts.map((alert) => `<li>${escapeHtml(alert)}</li>`).join("");

  const last = state.lastPrint;
  qs("lastPrintValue").textContent = last ? (last.os || "Sem OS") : "Nenhuma nesta sessão";
  qs("lastPrintMeta").textContent = last ? `${last.modelo || "Equipamento"} • ${last.horario || ""}` : "A impressão mais recente aparecerá aqui.";
  qs("reprintLast").classList.toggle("hidden", !last);
  renderPrintHistory();
}

function runWorkflowAction(action) {
  if (action === "edit") {
    showAppView("home");
    qs("deviceRead").classList.add("hidden");
    qs("editForm").classList.remove("hidden");
    qs("editForm").querySelector("input")?.focus();
    return;
  }
  if (action === "tests") return qs("openTests").click();
  if (action === "create-os") return qs("openCreateOs").click();
  if (action === "labels") return qs("openLabels").click();
}

function gradeValue() {
  if (state.grade === "T") return "T - TRIAGEM";
  return state.grade;
}

function normalizeStorage(value) {
  const text = String(value || "").trim();
  const match = text.match(/([0-9]+(?:[.,][0-9]+)?)\s*(TB|GB)/i);
  if (!match) return text || "N/A";
  const unit = match[2].toUpperCase();
  const amount = Number(match[1].replace(",", "."));
  let marketed = amount;
  if (unit === "GB") {
    const sizes = [32, 64, 128, 256, 512, 1024, 2048];
    marketed = sizes.reduce((best, size) => Math.abs(size - amount) < Math.abs(best - amount) ? size : best, sizes[0]);
  }
  const capacity = marketed >= 1024 && unit === "GB" ? `${marketed / 1024}TB` : `${marketed}${unit}`;
  const kind = /HDD/i.test(text) ? "HDD" : /SSD|NVME|M\.2/i.test(text) ? "SSD" : "";
  return `${capacity}${kind ? ` ${kind}` : ""}`;
}

function compactCpu(value) {
  const text = String(value || "").trim().toUpperCase();
  const intel = text.match(/\bI([3579])[-\s]?(\d{4,5})[A-Z0-9]*\b/);
  if (intel) {
    const model = intel[2];
    const firstTwo = Number(model.slice(0, 2));
    const generation = model.length >= 5 || (firstTwo >= 10 && firstTwo <= 14) ? firstTwo : Number(model[0]);
    return `I${intel[1]} ${generation}TH`;
  }
  const ryzen = text.match(/\bRYZEN\s+([3579])\s+(\d{4})/);
  if (ryzen) return `RYZEN ${ryzen[1]} ${ryzen[2]}`;
  return text.replace(/\b(INTEL|AMD|CORE|PROCESSOR|CPU)\b/g, "").replace(/\s+/g, " ").trim();
}

function compactRam(value) {
  const match = String(value || "").match(/(\d+(?:[.,]\d+)?)\s*GB/i);
  return match ? `${match[1]}GB RAM` : String(value || "").trim().toUpperCase();
}

function compactGpu(value) {
  return String(value || "")
    .toUpperCase()
    .replace(/\bNVIDIA\b|\bGEFORCE\b|\bLAPTOP GPU\b|\bGRAPHICS\b|\s*\((?:DEDICADA|INTEGRADA)\)/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

function currentConfigSummary() {
  if (state.awaitingDeviceImport) return "Aguardando a leitura do novo aparelho conectado.";
  if (state.device3u) {
    const data = state.device3u;
    return [
      data.imei ? `IMEI: ${data.imei}` : "",
      data.armazenamento ? `ARMAZ: ${data.armazenamento}` : "",
      data.ram ? `RAM: ${data.ram}` : "",
      data.bateria ? `BATERIA: ${data.bateria}` : "",
      Number(data.ciclos) > 0 ? `CICLOS: ${data.ciclos}` : "",
    ].filter(Boolean).join(" | ");
  }
  const items = [
    compactCpu(state.info.cpu),
    normalizeStorage(state.info.disco),
    compactRam(state.info.ram),
    compactGpu(state.info.gpu),
  ].filter((item) => item && !/^(N\/?A|NA)$/.test(item));
  return items.length ? `CONFIG: ${items.join(" | ")}` : "CONFIG: dados ainda não identificados.";
}

function renderCurrentConfig() {
  if (!isWindowsPreview) return;
  qs("currentConfigValue").textContent = currentConfigSummary();
  qs("configCpu").value = state.info.cpu || "";
  qs("configDisk").value = normalizeStorage(state.info.disco);
  qs("configRam").value = state.info.ram || "";
  qs("configGpu").value = state.info.gpu || "";
}

function normalizeSerial(value) {
  return String(value || "").replace(/\s+/g, "").toUpperCase();
}

function renderOsVerification(detail = state.osDetail) {
  if (!isWindowsPreview) return renderOperationalDashboard();
  const panel = qs("osVerification");
  panel.classList.remove("loading", "synced", "divergent");
  if (!detail) {
    qs("osVerificationStatus").textContent = "Aguardando consulta";
    renderOperationalDashboard();
    return;
  }
  const serialOs = normalizeSerial(detail.serial);
  const serialMachine = normalizeSerial(state.info.serial);
  const divergent = Boolean(serialOs && serialOs !== "-" && serialMachine && serialMachine !== "N/A" && serialOs !== serialMachine);
  qs("verifyOs").textContent = detail.osCodigo || "—";
  qs("verifyProduct").textContent = detail.produto || "Produto não informado";
  qs("verifyTechnician").textContent = detail.tecnico || "—";
  qs("verifySerial").textContent = detail.serial || "—";
  qs("osVerificationStatus").textContent = divergent ? "Serial divergente" : detail.online ? "OS conferida" : (detail.message || "Não localizada");
  if (divergent) panel.classList.add("divergent");
  else if (detail.online) panel.classList.add("synced");
  renderOperationalDashboard();
}

async function refreshOsVerification() {
  if (!isWindowsPreview) return;
  const osNumero = osNumberFromInput();
  if (!osNumero) return renderOsVerification(null);
  const panel = qs("osVerification");
  panel.classList.add("loading");
  qs("osVerificationStatus").textContent = "Consultando Altertag...";
  try {
    const data = await api("/api/os-detail", { osNumero });
    state.osDetail = data.detail || null;
    renderOsVerification();
  } catch (error) {
    state.osDetail = { osCodigo: `C${String(osNumero).padStart(6, "0")}`, message: error.message };
    renderOsVerification();
  }
}

function renderDevice() {
  const read = qs("deviceRead");
  if (isWindowsPreview) {
    const windowsFields = ["modelo", "serial", "cpu", "disco", "gpu", "ram", "bateria"];
    const spanTwo = new Set(["modelo", "cpu", "gpu"]);
    read.className = "device-specs-wrap";
    read.innerHTML = `
      <div class="device-specs">
        ${windowsFields.map((key, index) => `
          <article class="device-spec spec-${key} ${spanTwo.has(key) ? "wide" : ""} ${key === "bateria" ? "full" : ""}" style="animation-delay:${index * 28}ms">
            <span>${labels[key]}</span>
            <strong>${escapeHtml(state.info[key] || "N/A")}</strong>
          </article>
        `).join("")}
      </div>
    `;
  } else {
    read.className = "device-table-wrap";
  read.innerHTML = `
    <table class="device-table">
      <thead>
        <tr><th>Informacao</th><th>Valor detectado</th></tr>
      </thead>
      <tbody>
        ${fields.map((key, index) => `
          <tr style="animation-delay:${index * 28}ms">
            <th scope="row">${labels[key]}</th>
            <td>${escapeHtml(state.info[key] || "N/A")}</td>
          </tr>
        `).join("")}
      </tbody>
    </table>
  `;
  }

  const form = qs("editForm");
  fields.forEach((key) => {
    const input = form.elements[key];
    if (input) input.value = state.info[key] || "";
  });
  renderPreview();
}

function renderPreview() {
  qs("labelPreviewModel").textContent = state.info.modelo || defaultModelName;
  qs("labelPreviewSerial").textContent = state.info.serial || "N/A";
  qs("labelPreviewCpu").textContent = compactCpu(state.info.cpu) || "N/A";
  qs("labelPreviewRam").textContent = compactRam(state.info.ram) || "N/A";
  qs("labelPreviewDisk").textContent = normalizeStorage(state.info.disco) || "N/A";
  qs("labelPreviewGpu").textContent = compactGpu(state.info.gpu) || "N/A";
  qs("labelPreviewBattery").textContent = state.info.bateria || "N/A";
  const previewRows = [...document.querySelectorAll(".thermal-config-list dl > div")];
  const previewTitle = document.querySelector(".thermal-section-title");
  const type = ["Notebook", "Desktop", "Celular", "Monitor"].includes(state.equipmentType) ? state.equipmentType : "Notebook";
  const valuesByType = {
    Notebook: [["CPU", compactCpu(state.info.cpu) || "N/A"], ["RAM", compactRam(state.info.ram) || "N/A"], ["DISCO", normalizeStorage(state.info.disco) || "N/A"], ["GPU", compactGpu(state.info.gpu) || "N/A"], ["BAT", state.info.bateria || "N/A"]],
    Desktop: [["CPU", compactCpu(state.info.cpu) || "N/A"], ["RAM", compactRam(state.info.ram) || "N/A"], ["DISCO", normalizeStorage(state.info.disco) || "N/A"], ["GPU", compactGpu(state.info.gpu) || "N/A"]],
    Celular: [["IMEI", state.info.imei || state.device3u?.imei || "N/A"], ["ARMAZ.", normalizeStorage(state.info.disco) || "N/A"], ["RAM", compactRam(state.info.ram) || "N/A"], ["BATERIA", batteryWithoutCycles(state.info.bateria) || "N/A"], ["CICLOS", state.info.ciclos || state.device3u?.ciclos || "N/A"]],
    Monitor: [["POLEGADAS", state.info.monitorTamanho || monitorSizeFromDescription(state.info.modelo) || "N/A"], ["ENTRADAS", state.info.monitorEntradas || "N/A"]],
  };
  const values = valuesByType[type];
  if (previewTitle) previewTitle.textContent = type === "Notebook" ? "CONFIGURACAO" : type.toUpperCase();
  previewRows.forEach((row, index) => {
    row.classList.toggle("hidden", index >= values.length);
    if (values[index]) {
      row.querySelector("dt").textContent = values[index][0];
      row.querySelector("dd").textContent = values[index][1];
    }
  });
  qs("labelEquipmentType").value = type;
  if (qs("labelPageType")) qs("labelPageType").textContent = type;
  document.querySelectorAll(".label-data-field, .label-type-action").forEach((field) => {
    const allowed = String(field.dataset.labelTypes || "").split(/\s+/);
    field.classList.toggle("hidden", !allowed.includes(type));
  });
  qs("labelPreviewGrade").textContent = `GRADE ${gradeValue()}`;
  const formattedOs = `C${String(osNumberFromInput() || 235).padStart(6, "0")}`;
  if (qs("previewMetaGrade")) qs("previewMetaGrade").textContent = `Grade ${gradeValue()}`;
  if (qs("previewMetaOs")) qs("previewMetaOs").textContent = qs("includeOs").checked ? `OS ${formattedOs}` : "OS não incluída";
  qs("labelPreviewOs").textContent = qs("includeOs").checked ? `OS ${formattedOs}` : "OS NAO INCLUIDA";
  qs("labelPreviewDate").textContent = new Date().toLocaleDateString("pt-BR", {
    day: "2-digit",
    month: "2-digit",
    year: "2-digit",
  });
}

function syncPrintOsInput() {
  const input = qs("printOsInput");
  if (document.activeElement !== input) input.value = qs("osInput").value;
}

function populateLabelEditor() {
  const form = qs("labelEditForm");
  labelFields.forEach((key) => {
    const input = form.elements.namedItem(key);
    if (input) input.value = state.info[key] || "";
  });
}

function setLabelEditorOpen(open) {
  qs("labelEditForm").classList.toggle("hidden", !open);
  qs("toggleLabelEditor").textContent = open ? "Editando dados" : "Editar dados da etiqueta";
  qs("toggleLabelEditor").classList.toggle("active", open);
  if (open) {
    populateLabelEditor();
    qs("labelEditForm").elements.namedItem("modelo")?.focus();
  }
}

function updatePrintOsAvailability() {
  const includeOs = qs("includeOs").checked;
  qs("printOsInput").disabled = !includeOs;
  qs("printOsInput").closest("label").classList.toggle("disabled", !includeOs);
  renderPreview();
}

function showAppView(view) {
  const views = {
    home: "homeView",
    labels: "labelsView",
    tests: "testsView",
    createOs: "createOsView",
  };
  state.view = views[view] ? view : "home";
  Object.entries(views).forEach(([name, id]) => {
    qs(id).classList.toggle("hidden", name !== state.view);
  });
  setNavigationAction(state.view);
  if (state.view === "labels") {
    syncPrintOsInput();
    populateLabelEditor();
    renderPreview();
  }
  if (state.view === "tests") renderTests();
  window.scrollTo({ top: 0, behavior: "smooth" });
}

function setNavigationAction(action = state.view) {
  const targetId = { home: "openMenu", labels: "openLabels", tests: "openTests", createOs: "openCreateOs" }[action];
  ["openMenu", "openLabels", "openTests", "openCreateOs"].forEach((id) => {
    const active = id === targetId;
    qs(id).classList.toggle("active", active);
    setAttribute(qs(id), "aria-current", active ? "page" : "");
  });
}

function setAttribute(element, name, value) {
  if (value) element.setAttribute(name, value);
  else element.removeAttribute(name);
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
  state.equipmentType = data.equipmentType || state.equipmentType || "Notebook";
  if (isWindowsPreview && state.info.disco) state.info.disco = normalizeStorage(state.info.disco);
  const osFormatted = data.osFormatada || `C${String(data.osNumero || 235).padStart(6, "0")}`;
  if (document.activeElement !== qs("osInput")) qs("osInput").value = osFormatted;
  syncPrintOsInput();
  if (Number(data.pendingCreatedOs || 0) === Number(data.osNumero || 0) && Number(data.osNumero || 0) > 0) {
    state.osCreatedInSession = true;
  }
  qs("serverLine").textContent = `Servidor: ${data.serverUrl || "nao configurado"} | ${data.lastServerStatus || "nao verificado"}`;
  setEnvironmentStatus(data);
  renderDevice();
  renderCurrentConfig();
  renderOperationalDashboard();
}

function setEnvironmentStatus(data) {
  const runtime = window.CAIJ_NATIVE_RUNTIME || {};
  const internetOnline = runtime.internetStatus !== "offline" && navigator.onLine !== false;
  const serverOnline = String(data.lastServerStatus || "").toLowerCase() === "online";
  state.environment = { internetOnline, serverOnline };
  const internet = qs("internetBadge");
  const server = qs("serverBadge");
  internet.classList.toggle("online", internetOnline);
  internet.classList.toggle("offline", !internetOnline);
  internet.lastChild.textContent = internetOnline ? " Internet online" : " Sem internet";
  server.classList.toggle("online", serverOnline);
  server.classList.toggle("offline", !serverOnline);
  server.lastChild.textContent = serverOnline ? " Servidor online" : " Servidor aguardando";
  qs("versionBadge").textContent = runtime.version ? `v${runtime.version}` : "Versao local";
  renderOperationalDashboard();
}

function osNumberFromInput() {
  const digits = String(qs("osInput").value || "").replace(/\D/g, "");
  return Number(digits || 0);
}

async function persistEditedOs() {
  const osNumero = osNumberFromInput();
  if (!osNumero) throw new Error("Informe um numero de OS valido.");
  const data = await api("/api/set-os", { osNumero });
  if (data.state) applyState(data.state);
  return osNumero;
}

function showOsAlert(data, localCreation = false) {
  qs("alertCreatedOs").textContent = data.osCriada || "Nova OS";
  qs("alertNextOs").textContent = data.proximaOs || qs("osInput").value;
  qs("osAlertTitle").textContent = localCreation ? "OS criada com sucesso" : "Nova OS detectada";
  qs("alertCopySuffix").textContent = localCreation
    ? "Esta é a ordem vinculada ao atendimento e preparada para a etiqueta."
    : "Esta ordem foi criada em outra estação.";
  qs("printCreatedOs").classList.toggle("hidden", !localCreation);
  qs("dismissOsAlert").textContent = localCreation ? "Voltar ao menu" : "Entendido";
  qs("osAlert").classList.remove("hidden");
  (localCreation ? qs("printCreatedOs") : qs("dismissOsAlert")).focus();
}

function closeOsAlert() {
  qs("osAlert").classList.add("hidden");
}

function closeTestsPanel() {
  stopActiveTest();
  if (testsOnlyMode) {
    document.title = "CAIJ_TESTES_CONCLUIDOS";
    qs("closeTests").textContent = "Retornando...";
    qs("closeTests").disabled = true;
    return;
  }
  showAppView("home");
}

function testsOverall() {
  const values = Object.values(state.tests);
  return values.includes("failed") ? "FALHOU" : values.includes("pending") ? "PENDENTE" : "OK";
}

function testsReport() {
  const overall = testsOverall();
  const statusLabel = { passed: "OK", failed: "FALHOU", pending: "PENDENTE" };
  const details = Object.entries(state.tests)
    .map(([key, value]) => `${testLabels[key]}: ${statusLabel[value]}`)
    .join(" | ");
  return `TESTES: ${overall} | ${details}`;
}

function testsLabelSummary() {
  return `TESTES: ${testsOverall()}`;
}

function removeTestsReport(target) {
  target.value = target.value
    .split(/\r?\n/)
    .filter((line) => !/^TESTES(?: (?:MAC|WINDOWS))?:/i.test(line.trim()))
    .join("\n")
    .trim();
  target.dispatchEvent(new Event("input", { bubbles: true }));
}

function syncCompletedTestsToObservations(pending) {
  const targets = [qs("obs"), qs("createObservation")].filter(Boolean);
  if (pending > 0) {
    targets.forEach(removeTestsReport);
    qs("finishTests").classList.add("hidden");
    qs("testsActionStatus").textContent = "";
    return;
  }
  const report = testsLabelSummary();
  targets.forEach((target) => appendTestsReport(target, report));
  try { localStorage.setItem("caij:mac-tests-observation", report); } catch (_) {}
  qs("finishTests").classList.remove("hidden");
  qs("testsActionStatus").textContent = "Resultado incluído automaticamente nas observações.";
}

function renderTests() {
  const values = Object.values(state.tests);
  const passed = values.filter((value) => value === "passed").length;
  const failed = values.filter((value) => value === "failed").length;
  const pending = values.length - passed - failed;
  const completion = Math.round(((passed + failed) / values.length) * 100);
  qs("testsPassed").textContent = passed;
  qs("testsFailed").textContent = failed;
  qs("testsPending").textContent = pending;
  qs("testsCompletion").textContent = `${completion}%`;
  qs("testsProgress").style.width = `${completion}%`;
  qs("testsReport").textContent = testsReport();
  qs("testList").querySelectorAll(".test-row").forEach((row) => {
    const status = state.tests[row.dataset.test];
    const previousStatus = row.dataset.renderedStatus || "";
    row.classList.remove("passed", "failed");
    if (status !== "pending") row.classList.add(status);
    row.dataset.renderedStatus = status;
    if (previousStatus && previousStatus !== status) {
      row.classList.remove("status-changed");
      void row.offsetWidth;
      row.classList.add("status-changed");
    }
    row.querySelector(".test-state").textContent = status === "passed" ? "Passou" : status === "failed" ? "Falhou" : "Pendente";
    row.querySelectorAll("button[data-action]").forEach((button) => {
      const selected = (button.dataset.action === "pass" && status === "passed") || (button.dataset.action === "fail" && status === "failed");
      button.classList.toggle("selected", selected);
      if (button.dataset.action === "pass" || button.dataset.action === "fail") button.setAttribute("aria-pressed", String(selected));
    });
  });
  syncCompletedTestsToObservations(pending);
  renderOperationalDashboard();
}

function stopActiveTest() {
  if (state.mediaStream) {
    state.mediaStream.getTracks().forEach((track) => track.stop());
    state.mediaStream = null;
  }
  if (state.audioFrame) cancelAnimationFrame(state.audioFrame);
  state.audioFrame = 0;
  if (state.audioContext) state.audioContext.close().catch(() => {});
  state.audioContext = null;
  if (state.keyboardHandler) document.removeEventListener("keydown", state.keyboardHandler, true);
  state.keyboardHandler = null;
  state.activeTest = "";
  qs("testWorkspace").classList.add("hidden");
  qs("activeTestBody").innerHTML = "";
}

function requestUserMedia(constraints) {
  if (!window.isSecureContext) {
    return Promise.reject(new Error("A câmera e o microfone exigem que o InfoNotebook seja aberto pela interface local segura."));
  }
  if (navigator.mediaDevices && typeof navigator.mediaDevices.getUserMedia === "function") {
    return navigator.mediaDevices.getUserMedia(constraints);
  }
  const legacy = navigator.getUserMedia || navigator.webkitGetUserMedia;
  if (legacy) {
    return new Promise((resolve, reject) => legacy.call(navigator, constraints, resolve, reject));
  }
  return Promise.reject(new Error("Camera e microfone precisam ser abertos pelo teste local seguro do InfoNotebook."));
}

function testError(message) {
  const permissionHelp = isWindowsPreview
    ? "Confira em Configurações do Windows > Privacidade e segurança > Câmera ou Microfone."
    : "Confira a permissão em Ajustes do Sistema > Privacidade e Segurança.";
  qs("activeTestBody").innerHTML = `<div class="test-permission-error"><strong>Não foi possível iniciar.</strong><span>${escapeHtml(message)}</span><small>${escapeHtml(permissionHelp)}</small></div>`;
}

async function openCameraTest() {
  qs("activeTestBody").innerHTML = '<div class="camera-stage"><video id="cameraPreview" autoplay muted playsinline></video><span>Imagem ao vivo</span></div>';
  try {
    state.mediaStream = await requestUserMedia({ video: true, audio: false });
    qs("cameraPreview").srcObject = state.mediaStream;
  } catch (err) {
    testError(err.message || "Camera indisponivel.");
  }
}

function normalizeKeyboardEvent(event) {
  const physicalKeys = {
    Escape: "ESC",
    Quote: "'",
    Slash: "/",
    IntlRo: "/",
    NumpadDivide: "/",
    Semicolon: ";",
    Comma: ",",
    Period: ".",
    Minus: "-",
    Equal: "=",
    BracketLeft: "[",
    BracketRight: "]",
    Backquote: "BACKQUOTE",
    Backslash: "BACKSLASH",
    IntlBackslash: "BACKSLASH",
    Backspace: "BACKSPACE",
    Tab: "TAB",
    Enter: "ENTER",
    CapsLock: "CAPSLOCK",
    ShiftLeft: "SHIFT",
    ShiftRight: "SHIFT",
    ControlLeft: "CONTROL",
    ControlRight: "CONTROL",
    AltLeft: "ALT",
    AltRight: "ALT",
    MetaLeft: isWindowsPreview ? "WINDOWS" : "META",
    MetaRight: isWindowsPreview ? "WINDOWS" : "META",
    ContextMenu: "MENU",
    PrintScreen: "PRINTSCREEN",
    ScrollLock: "SCROLLLOCK",
    Pause: "PAUSE",
    Insert: "INSERT",
    Delete: "DELETE",
    Home: "HOME",
    End: "END",
    PageUp: "PAGEUP",
    PageDown: "PAGEDOWN",
    Space: "SPACE",
  };
  if (/^F(?:[1-9]|1[0-2])$/.test(event.code)) return event.code;
  if (physicalKeys[event.code]) return physicalKeys[event.code];
  const aliases = { " ": "SPACE", ESCAPE: "ESC", CMD: "META", OS: "META", DEAD: "'" };
  return aliases[String(event.key || "").toUpperCase()] || String(event.key || "").toUpperCase();
}

function openKeyboardTest() {
  const macKeyboardRows = [
    ["ESC","F1","F2","F3","F4","F5","F6","F7","F8","F9","F10","F11","F12"],
    ["BACKQUOTE","1","2","3","4","5","6","7","8","9","0","-","=","BACKSPACE"],
    ["TAB","Q","W","E","R","T","Y","U","I","O","P","[","]","BACKSLASH"],
    ["CAPSLOCK","A","S","D","F","G","H","J","K","L",";","'","ENTER"],
    ["SHIFT","Z","X","C","V","B","N","M",",",".","/","CONTROL","ALT","META","SPACE","ARROWLEFT","ARROWUP","ARROWDOWN","ARROWRIGHT"],
  ];
  const windowsKeyboardRows = [
    ["ESC","F1","F2","F3","F4","F5","F6","F7","F8","F9","F10","F11","F12","PRINTSCREEN","SCROLLLOCK","PAUSE"],
    ["BACKQUOTE","1","2","3","4","5","6","7","8","9","0","-","=","BACKSPACE","INSERT","HOME","PAGEUP"],
    ["TAB","Q","W","E","R","T","Y","U","I","O","P","[","]","BACKSLASH","DELETE","END","PAGEDOWN"],
    ["CAPSLOCK","A","S","D","F","G","H","J","K","L",";","'","ENTER"],
    ["SHIFT","Z","X","C","V","B","N","M",",",".","/","SHIFT"],
    ["CONTROL","WINDOWS","ALT","SPACE","MENU","ARROWLEFT","ARROWUP","ARROWDOWN","ARROWRIGHT"],
  ];
  const keyboardRows = isWindowsPreview ? windowsKeyboardRows : macKeyboardRows;
  const keyNames = { SPACE: "ESPAÇO", WINDOWS: "WIN", PRINTSCREEN: "PRT SC", SCROLLLOCK: "SCR LK", PAGEUP: "PG UP", PAGEDOWN: "PG DN", META: "COMMAND", BACKQUOTE: "`", BACKSLASH: "\\", ARROWLEFT: "←", ARROWUP: "↑", ARROWDOWN: "↓", ARROWRIGHT: "→" };
  qs("activeTestBody").innerHTML = `<div class="keyboard-progress"><span>Teclas reconhecidas</span><strong id="keyboardCount">0</strong></div><div class="keyboard-map ${isWindowsPreview ? "windows-keyboard" : "mac-keyboard"}">${keyboardRows.map((row) => `<div class="keyboard-row">${row.map((key) => `<kbd data-key="${key}">${keyNames[key] || key}</kbd>`).join("")}</div>`).join("")}</div>`;
  const pressed = new Set();
  state.keyboardHandler = (event) => {
    event.preventDefault();
    event.stopPropagation();
    event.stopImmediatePropagation();
    const key = normalizeKeyboardEvent(event);
    const elements = [...qs("activeTestBody").querySelectorAll("kbd[data-key]")]
      .filter((item) => item.dataset.key === key);
    if (elements.length) {
      elements.forEach((element) => element.classList.add("pressed"));
      pressed.add(key);
      qs("keyboardCount").textContent = pressed.size;
    }
  };
  document.addEventListener("keydown", state.keyboardHandler, true);
}

function playTestTone() {
  const AudioContextClass = window.AudioContext || window.webkitAudioContext;
  if (!AudioContextClass) return testError("Audio Web nao suportado neste navegador.");
  const context = new AudioContextClass();
  const oscillator = context.createOscillator();
  const gain = context.createGain();
  oscillator.frequency.setValueAtTime(440, context.currentTime);
  gain.gain.setValueAtTime(0.12, context.currentTime);
  oscillator.connect(gain).connect(context.destination);
  oscillator.start();
  oscillator.stop(context.currentTime + 1.2);
  oscillator.addEventListener("ended", () => context.close());
}

async function startMicrophoneMeter() {
  try {
    if (state.mediaStream) state.mediaStream.getTracks().forEach((track) => track.stop());
    const AudioContextClass = window.AudioContext || window.webkitAudioContext;
    state.mediaStream = await requestUserMedia({ audio: true, video: false });
    state.audioContext = new AudioContextClass();
    const source = state.audioContext.createMediaStreamSource(state.mediaStream);
    const analyser = state.audioContext.createAnalyser();
    analyser.fftSize = 256;
    source.connect(analyser);
    const data = new Uint8Array(analyser.frequencyBinCount);
    const meter = qs("micMeterFill");
    const tick = () => {
      analyser.getByteFrequencyData(data);
      const level = data.reduce((sum, value) => sum + value, 0) / data.length;
      meter.style.width = `${Math.min(100, level * 1.8)}%`;
      state.audioFrame = requestAnimationFrame(tick);
    };
    tick();
    qs("micStatus").textContent = "Microfone ativo — fale para movimentar o medidor.";
  } catch (err) {
    testError(err.message || "Microfone indisponivel.");
  }
}

function openAudioTest() {
  qs("activeTestBody").innerHTML = '<div class="audio-stage"><div class="audio-controls"><button type="button" id="playTone">Reproduzir som</button><button type="button" id="startMic">Ativar microfone</button></div><div class="mic-meter"><span id="micMeterFill"></span></div><p id="micStatus">Reproduza o som e depois ative o microfone.</p></div>';
  qs("playTone").addEventListener("click", playTestTone);
  qs("startMic").addEventListener("click", startMicrophoneMeter);
}

function setScreenTestColor(color) {
  qs("screenTestDialog").style.background = color;
  qs("screenTestDialog").classList.toggle("light-screen", color === "#ffffff");
}

function openScreenTest() {
  const dialog = qs("screenTestDialog");
  setScreenTestColor("#ffffff");
  try { dialog.showModal(); } catch (_) { dialog.setAttribute("open", ""); }
  const requestFull = dialog.requestFullscreen || dialog.webkitRequestFullscreen;
  if (requestFull) Promise.resolve(requestFull.call(dialog)).catch(() => {});
}

function openTrackpadTest() {
  qs("activeTestBody").innerHTML = '<div class="trackpad-stats"><span>Movimento <strong id="trackMoves">0</strong></span><span>Cliques <strong id="trackClicks">0</strong></span><span>Rolagem <strong id="trackScrolls">0</strong></span></div><div class="trackpad-zone" id="trackpadZone"><i id="trackPointer"></i><strong>Mova, clique e role aqui</strong></div>';
  const zone = qs("trackpadZone");
  const pointer = qs("trackPointer");
  let moves = 0;
  let clicks = 0;
  let scrolls = 0;
  zone.addEventListener("pointermove", (event) => {
    const bounds = zone.getBoundingClientRect();
    pointer.style.left = `${event.clientX - bounds.left}px`;
    pointer.style.top = `${event.clientY - bounds.top}px`;
    qs("trackMoves").textContent = ++moves;
  });
  zone.addEventListener("click", () => { qs("trackClicks").textContent = ++clicks; });
  zone.addEventListener("wheel", (event) => { event.preventDefault(); qs("trackScrolls").textContent = ++scrolls; }, { passive: false });
}

async function openTest(test) {
  stopActiveTest();
  state.activeTest = test;
  qs("testWorkspace").classList.remove("hidden");
  qs("activeTestTitle").textContent = testLabels[test];
  const helps = {
    camera: "Autorize a camera e confira nitidez, enquadramento e estabilidade.",
    keyboard: isWindowsPreview
      ? "Pressione todas as teclas. Em alguns notebooks, use Fn + F1, Fn + F2 etc. para testar as teclas de função."
      : "Pressione as teclas. No Mac, use Fn + F1, Fn + F2 etc. para testar as teclas de função.",
    audio: "Confirme a saida dos alto-falantes e observe o nivel do microfone.",
    screen: "Alterne entre as cinco cores e procure pixels presos, manchas ou vazamento de luz.",
    trackpad: isWindowsPreview
      ? "Mova o mouse ou use toda a superfície do touchpad, clique e faça rolagem."
      : "Use toda a superfície do trackpad, clique e faça rolagem.",
  };
  qs("activeTestHelp").textContent = helps[test];
  if (test === "camera") await openCameraTest();
  if (test === "keyboard") openKeyboardTest();
  if (test === "audio") openAudioTest();
  if (test === "screen") openScreenTest();
  if (test === "trackpad") openTrackpadTest();
  qs("testWorkspace").scrollIntoView({ behavior: "smooth", block: "nearest" });
}

function closeScreenTest() {
  const dialog = qs("screenTestDialog");
  if (document.fullscreenElement && document.exitFullscreen) document.exitFullscreen().catch(() => {});
  if (dialog.open) dialog.close();
}

function appendTestsReport(target, report = testsReport()) {
  const clean = target.value.split(/\r?\n/).filter((line) => !/^TESTES(?: (?:MAC|WINDOWS))?:/i.test(line.trim())).join("\n").trim();
  target.value = [clean, report].filter(Boolean).join("\n");
  target.dispatchEvent(new Event("input", { bubbles: true }));
}

async function copyTestsReport() {
  const report = testsReport();
  await copyText(report);
  qs("testsActionStatus").textContent = "Resumo completo copiado.";
  setStatus("Resumo dos testes copiado.", "ok");
}

async function copyText(text) {
  try {
    await navigator.clipboard.writeText(text);
  } catch (_) {
    const field = document.createElement("textarea");
    field.value = text;
    document.body.appendChild(field);
    field.select();
    document.execCommand("copy");
    field.remove();
  }
}

function productLabel(product) {
  const code = product.codigo || product.produtoCodigo || "SEM CODIGO";
  const description = product.descricao || product.nome || product.texto || "Produto";
  return `${code} | ${description}`;
}

function productDescription(product) {
  return String(product?.descricao || product?.nome || product?.texto || "").trim();
}

function inferEquipmentType(product, device3u = state.device3u) {
  if (device3u) return "Celular";
  const description = productDescription(product);
  if (/\b(MONITOR|DISPLAY|TELA)\b/i.test(description)) return "Monitor";
  if (/^\s*(?:CPU|DESKTOP|MINI\s*DESKTOP)\b|\b(MINI\s*PC|OPTIPLEX|PRODESK|ELITEDESK)\b/i.test(description)) return "Desktop";
  if (/\b(IPHONE|IPAD|SMARTPHONE|CELULAR|TABLET)\b/i.test(description)) return "Celular";
  return "Notebook";
}

function monitorSizeFromDescription(description) {
  const match = String(description || "").match(/\b(\d{2}(?:[.,]\d)?)\s*(?:POL(?:EGADAS?)?|\")/i);
  return match ? `${match[1].replace(",", ".")}"` : "";
}

function batteryWithoutCycles(value) {
  return String(value || "")
    .replace(/\s*\|?\s*\d+\s*ciclos?.*$/i, "")
    .trim();
}

async function import3uToolsDevice(button) {
  const idleText = button.textContent;
  state.device3u = null;
  state.awaitingDeviceImport = true;
  renderCurrentConfig();
  button.disabled = true;
  button.textContent = "Lendo aparelho...";
  try {
    const data = await api("/api/read-3utools", {});
    state.device3u = data.device;
    state.awaitingDeviceImport = false;
    const mobileInfo = {
      modelo: data.device.modelo || "iPhone",
      serial: data.device.serial || "N/A",
      cpu: "N/A",
      gpu: "N/A",
      ram: data.device.ram || "N/A",
      disco: data.device.armazenamento || "N/A",
      bateria: data.device.bateria || "N/A",
      imei: data.device.imei || "N/A",
      ciclos: Number(data.device.ciclos) > 0 ? String(data.device.ciclos) : "N/A",
    };
    applyState(await api("/api/info", { info: mobileInfo, equipmentType: "Celular" }));
    return data.device;
  } finally {
    button.disabled = false;
    button.textContent = idleText;
  }
}

function labelContextFromCreate(body) {
  const equipmentType = inferEquipmentType(body.produto, body.device3u);
  const description = productDescription(body.produto);
  const info = { ...state.info, serial: body.serial };
  if (equipmentType === "Monitor") {
    Object.assign(info, {
      modelo: description || "Monitor",
      cpu: "",
      gpu: "",
      ram: "",
      disco: "",
      bateria: "",
      monitorTamanho: state.info.monitorTamanho || monitorSizeFromDescription(description),
      monitorEntradas: state.info.monitorEntradas || "",
    });
  } else if (equipmentType === "Desktop") {
    info.modelo = description || info.modelo || "Desktop";
    info.bateria = "";
  } else if (equipmentType === "Celular" && body.device3u) {
    info.modelo = body.device3u.modelo || description || info.modelo;
  }
  return { info, equipmentType };
}

function applyGradeFromReference(reference) {
  const normalized = String(reference || "").toUpperCase();
  state.grade = normalized.includes("TRIAGEM") ? "T"
    : normalized === "RMA" ? "RMA"
      : (normalized.match(/GRADE\s+([ABC])/)?.[1] || "A");
  document.querySelectorAll(".grade").forEach((button) => {
    button.classList.toggle("active", button.dataset.grade === state.grade);
  });
}

function productCode(product) {
  return String(product.codigo || product.produtoCodigo || "").trim().toUpperCase();
}

function sortProductsWithTFirst(products) {
  return [...products].sort((left, right) => {
    const leftCode = productCode(left);
    const rightCode = productCode(right);
    const leftIsT = /^T\d/.test(leftCode);
    const rightIsT = /^T\d/.test(rightCode);
    if (leftIsT !== rightIsT) return leftIsT ? -1 : 1;
    return leftCode.localeCompare(rightCode, "pt-BR", { numeric: true, sensitivity: "base" });
  });
}

function updateCreateOsState() {
  const other = qs("otherTechnician").value.trim();
  const technician = state.createOs.technician === "Outro" ? other : state.createOs.technician;
  const ready = Boolean(technician && state.createOs.product && qs("createSerial").value.trim());
  qs("submitCreateOs").disabled = !ready;
  qs("createOsStatus").textContent = state.createOs.product
    ? `Selecionado: ${productLabel(state.createOs.product)}`
    : "Selecione o técnico e o produto.";
}

function openCreateOs() {
  const hadImportedDevice = Boolean(state.device3u);
  state.createOs.technician = "";
  state.createOs.product = null;
  state.device3u = null;
  state.awaitingDeviceImport = hadImportedDevice;
  qs("technicianGrid").querySelectorAll("button").forEach((button) => button.classList.remove("active"));
  qs("otherTechnician").value = "";
  qs("otherTechnician").classList.add("hidden");
  qs("productSearch").value = hadImportedDevice ? "" : (state.info.modelo || "");
  qs("createSerial").value = hadImportedDevice ? "" : (state.info.serial || "");
  qs("createObservation").value = Object.values(state.tests).every((value) => value !== "pending") ? testsLabelSummary() : "";
  qs("productResults").innerHTML = "<p>Pesquise e selecione um produto.</p>";
  const currentOs = osNumberFromInput();
  qs("createCurrentOs").textContent = currentOs ? `C${String(currentOs).padStart(6, "0")}` : "Não selecionada";
  renderCurrentConfig();
  updateCreateOsState();
  showAppView("createOs");
}

function closeCreateOs() {
  showAppView("home");
}

function renderProductResults(products) {
  const container = qs("productResults");
  if (!products.length) {
    container.innerHTML = "<p>Nenhum produto encontrado.</p>";
    return;
  }
  const orderedProducts = sortProductsWithTFirst(products);
  container.innerHTML = orderedProducts.map((product, index) => `
    <button type="button" data-product-index="${index}">
      <strong>${escapeHtml(product.codigo || product.produtoCodigo || "--")}</strong>
      <span>${escapeHtml(product.descricao || product.nome || product.texto || "Produto")}</span>
    </button>
  `).join("");
  container.querySelectorAll("button").forEach((button) => {
    button.addEventListener("click", () => {
      state.createOs.product = orderedProducts[Number(button.dataset.productIndex)];
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

function deviceInfoText() {
  return fields
    .map((key) => `${labels[key]}: ${state.info[key] || "N/A"}`)
    .join("\n");
}

function updateSessionClock() {
  const now = new Date();
  qs("sessionClock").dateTime = now.toISOString();
  qs("sessionClock").querySelector("b").textContent = now.toLocaleTimeString("pt-BR", {
    hour: "2-digit",
    minute: "2-digit",
  });
  qs("sessionClock").title = now.toLocaleDateString("pt-BR", {
    weekday: "long",
    day: "2-digit",
    month: "long",
  });
}

async function refreshDeviceReading() {
  const button = qs("refreshReading");
  button.disabled = true;
  setStatus("Atualizando a leitura da máquina...", "busy");
  await loadState();
  if (isWindowsPreview) await refreshOsVerification();
  button.disabled = false;
}

async function copyDeviceInfo() {
  await copyText(deviceInfoText());
  setStatus("Ficha técnica copiada.", "ok");
}

function wireControls() {
  document.querySelectorAll(".grade").forEach((button) => {
    button.addEventListener("click", () => {
      state.grade = button.dataset.grade;
      document.querySelectorAll(".grade").forEach((b) => b.classList.toggle("active", b === button));
      renderPreview();
      renderOperationalDashboard();
    });
  });

  qs("editToggle").addEventListener("click", () => {
    qs("deviceRead").classList.toggle("hidden");
    qs("editForm").classList.toggle("hidden");
  });
  qs("refreshReading").addEventListener("click", refreshDeviceReading);
  qs("copyDeviceInfo").addEventListener("click", copyDeviceInfo);

  qs("openTests").addEventListener("click", () => {
    showAppView("tests");
  });
  qs("closeTests").addEventListener("click", closeTestsPanel);
  qs("closeActiveTest").addEventListener("click", stopActiveTest);
  qs("testList").addEventListener("click", (event) => {
    const button = event.target.closest("button[data-action]");
    if (!button) return;
    const test = button.closest(".test-row").dataset.test;
    const action = button.dataset.action;
    if (action === "open") return openTest(test);
    state.tests[test] = action === "pass" ? "passed" : action === "fail" ? "failed" : "pending";
    renderTests();
  });
  qs("resetTests").addEventListener("click", () => {
    Object.keys(state.tests).forEach((key) => state.tests[key] = "pending");
    stopActiveTest();
    renderTests();
  });
  qs("copyTestsReport").addEventListener("click", copyTestsReport);
  qs("finishTests").addEventListener("click", async () => {
    if (Object.values(state.tests).some((value) => value === "pending")) return;
    if (testsOnlyMode) {
      const report = testsLabelSummary();
      await copyText(report);
      try { localStorage.setItem("caij:mac-tests-observation", report); } catch (_) {}
    }
    closeTestsPanel();
    setStatus("Testes finalizados e observações atualizadas.", "ok");
  });
  qs("screenColorButtons").addEventListener("click", (event) => {
    const button = event.target.closest("button[data-color]");
    if (button) setScreenTestColor(button.dataset.color);
  });
  qs("closeScreenTest").addEventListener("click", closeScreenTest);

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
      await refreshOsVerification();
      setStatus("OS sincronizada.", "ok");
    } catch (err) {
      setStatus(err.message, "warn");
    }
  });

  qs("osInput").addEventListener("focus", (event) => event.currentTarget.select());
  qs("osInput").addEventListener("change", async () => {
    try {
      await persistEditedOs();
      await refreshOsVerification();
      setStatus("OS da etiqueta alterada.", "ok");
    } catch (err) {
      setStatus(err.message, "warn");
    }
  });
  qs("printOsInput").addEventListener("focus", (event) => event.currentTarget.select());
  qs("printOsInput").addEventListener("change", async (event) => {
    const digits = String(event.currentTarget.value || "").replace(/\D/g, "");
    if (!digits) {
      syncPrintOsInput();
      return setStatus("Informe um número de OS válido.", "warn");
    }
    const formatted = `C${String(Number(digits)).padStart(6, "0")}`;
    event.currentTarget.value = formatted;
    qs("osInput").value = formatted;
    try {
      await persistEditedOs();
      await refreshOsVerification();
      renderPreview();
      setStatus("OS da etiqueta alterada.", "ok");
    } catch (err) {
      setStatus(err.message, "warn");
    }
  });

  qs("openMenu").addEventListener("click", () => {
    stopActiveTest();
    showAppView("home");
  });
  qs("openLabels").addEventListener("click", async () => {
    showAppView("labels");
    await refreshOsVerification();
  });
  qs("reviewSerialDivergence").addEventListener("click", async () => {
    showAppView("labels");
    setStatus("Confira a serial do equipamento e a serial vinculada à OS.", "busy");
    await refreshOsVerification();
  });
  qs("workflowRead").parentElement.addEventListener("click", (event) => {
    const target = event.target.closest("[data-workflow-action]");
    if (target) runWorkflowAction(target.dataset.workflowAction);
  });
  qs("nextActionButton").addEventListener("click", (event) => runWorkflowAction(event.currentTarget.dataset.workflowAction));
  qs("reprintLast").addEventListener("click", () => {
    showAppView("labels");
    setStatus("Confira a etiqueta antes de reimprimir.", "busy");
  });
  qs("includeOs").addEventListener("change", updatePrintOsAvailability);
  qs("labelEquipmentType").addEventListener("change", async (event) => {
    const equipmentType = event.currentTarget.value;
    state.equipmentType = equipmentType;
    renderPreview();
    try {
      const data = await api("/api/info", { info: state.info, equipmentType });
      applyState(data);
      setStatus(`Etiqueta adaptada para ${event.currentTarget.selectedOptions[0].textContent}.`, "ok");
    } catch (err) {
      setStatus(err.message, "warn");
    }
  });
  qs("read3uToolsLabel").addEventListener("click", async (event) => {
    try {
      const device = await import3uToolsDevice(event.currentTarget);
      populateLabelEditor();
      renderPreview();
      setStatus(`${device.modelo || "Aparelho"} importado do 3uTools.`, "ok");
    } catch (err) {
      setStatus(err.message, "warn");
    }
  });
  qs("toggleLabelEditor").addEventListener("click", () => {
    setLabelEditorOpen(qs("labelEditForm").classList.contains("hidden"));
  });
  qs("cancelLabelEditor").addEventListener("click", () => setLabelEditorOpen(false));
  qs("labelEditForm").addEventListener("submit", async (event) => {
    event.preventDefault();
    const formData = new FormData(event.currentTarget);
    const info = {};
    labelFields.forEach((key) => info[key] = String(formData.get(key) || "").trim());
    setStatus("Aplicando dados manuais na etiqueta...", "busy");
    try {
      const data = await api("/api/info", { info, equipmentType: qs("labelEquipmentType").value });
      applyState(data);
      renderPreview();
      setLabelEditorOpen(false);
      setStatus("Dados manuais aplicados na prévia.", "ok");
    } catch (err) {
      setStatus(err.message, "warn");
    }
  });
  qs("obs").addEventListener("input", renderOperationalDashboard);
  qs("openCreateOs").addEventListener("click", openCreateOs);
  qs("closeCreateOs").addEventListener("click", closeCreateOs);
  qs("cancelCreateOs").addEventListener("click", closeCreateOs);

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

  if (isWindowsPreview) {
    qs("refreshOsVerification").addEventListener("click", refreshOsVerification);
    qs("toggleConfigEditor").addEventListener("click", () => {
      qs("configInlineEditor").classList.toggle("hidden");
    });
    qs("applyConfigEditor").addEventListener("click", async () => {
      const info = {
        ...state.info,
        cpu: qs("configCpu").value.trim(),
        disco: normalizeStorage(qs("configDisk").value),
        ram: qs("configRam").value.trim(),
        gpu: qs("configGpu").value.trim(),
      };
      const data = await api("/api/info", { info });
      applyState(data);
      qs("configInlineEditor").classList.add("hidden");
      setStatus("Configuração atualizada para o cadastro da OS.", "ok");
    });
    qs("read3uTools").addEventListener("click", async () => {
      const button = qs("read3uTools");
      qs("createOsStatus").textContent = "Consultando o 3uTools deste computador...";
      try {
        const device = await import3uToolsDevice(button);
        qs("createSerial").value = device.serial || "";
        qs("productSearch").value = device.modelo || "iPhone";
        renderCurrentConfig();
        updateCreateOsState();
        qs("createOsStatus").textContent = `${device.modelo} lido. Buscando o produto correspondente...`;
        qs("searchProducts").click();
      } catch (error) {
        qs("createOsStatus").textContent = error.message;
      }
    });
  }

  qs("createOsForm").addEventListener("submit", async (event) => {
    event.preventDefault();
    const createButton = qs("submitCreateOs");
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
      info: state.info,
      equipmentType: state.equipmentType,
      device3u: state.device3u,
    };
    const labelContext = labelContextFromCreate(body);
    body.info = labelContext.info;
    body.equipmentType = labelContext.equipmentType;
    setButtonBusy(createButton, true, "Criando OS...");
    qs("createOsStatus").textContent = "Criando OS no Altertag...";
    try {
      const data = await api("/api/create-os", body);
      state.osCreatedInSession = true;
      const preparedState = await api("/api/info", labelContext);
      applyState(preparedState || data.state || {});
      applyGradeFromReference(body.referencia);
      if (data.observacao) qs("obs").value = data.observacao;
      closeCreateOs();
      await refreshOsVerification();
      showOsAlert(data, true);
      setStatus(`${data.osCriada} criada com sucesso.`, "ok");
    } catch (err) {
      updateCreateOsState();
      qs("createOsStatus").textContent = err.message;
    } finally {
      setButtonBusy(createButton, false);
    }
  });

  qs("printBtn").addEventListener("click", async () => {
    const printButton = qs("printBtn");
    const printedOs = osNumberFromInput();
    const body = {
      grade: gradeValue(),
      obs: qs("obs").value.trim(),
      includeOs: qs("includeOs").checked,
      info: state.info,
      equipmentType: state.equipmentType,
    };
    setButtonBusy(printButton, true, "Imprimindo etiqueta...");
    setStatus("Imprimindo etiqueta...", "busy");
    try {
      if (body.includeOs) {
        await persistEditedOs();
      }
      const data = await api("/api/print", body);
      saveLastPrint({
        os: body.includeOs ? `C${String(printedOs).padStart(6, "0")}` : "Sem OS",
        modelo: state.info.modelo || defaultModelName,
        serial: state.info.serial || "",
        grade: gradeValue(),
        tipo: state.equipmentType,
        horario: new Date().toLocaleString("pt-BR", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" }),
      });
      if (data.state) applyState(data.state);
      showAppView("home");
      setStatus(data.message || "Etiqueta enviada.", data.syncWarning ? "warn" : "ok");
    } catch (err) {
      setStatus(err.message, "warn");
    } finally {
      setButtonBusy(printButton, false);
    }
  });
  qs("fullscreenBtn").addEventListener("click", async () => {
    try {
      if (document.fullscreenElement) {
        await document.exitFullscreen();
        qs("fullscreenBtn").textContent = "Tela cheia";
      } else {
        await document.documentElement.requestFullscreen();
        qs("fullscreenBtn").textContent = "Sair da tela cheia";
      }
    } catch (_) {
      setStatus(isWindowsPreview ? "Use F11 para alternar a tela cheia." : "Use Control + Command + F para alternar a tela cheia.", "warn");
    }
  });

  qs("dismissOsAlert").addEventListener("click", closeOsAlert);
  qs("printCreatedOs").addEventListener("click", async () => {
    closeOsAlert();
    showAppView("labels");
    await refreshOsVerification();
    setStatus("OS criada. Confira a prévia e imprima a etiqueta.", "ok");
  });
  qs("osAlert").addEventListener("click", (event) => {
    if (event.target === qs("osAlert")) closeOsAlert();
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") closeOsAlert();
  });
}

applyPlatformUi();
wireControls();
renderTests();
updatePrintOsAvailability();
updateSessionClock();
setInterval(updateSessionClock, 30000);
if (window.location.protocol === "file:") qs("brandLogo").src = "../caij-logo.png";
if (testsOnlyMode) {
  document.body.classList.add("tests-only");
  qs("closeTests").textContent = "Voltar ao InfoNotebook";
  showAppView("tests");
} else {
  loadState().then(async () => {
    if (isWindowsPreview) await refreshOsVerification();
    await watchOs();
  });
  setInterval(watchOs, 4000);
}
