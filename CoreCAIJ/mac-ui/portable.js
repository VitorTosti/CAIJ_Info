(function () {
  "use strict";

  const runtime = window.CAIJ_NATIVE_RUNTIME;
  if (!runtime) return;
  const isWindows = String(runtime.platform || "").toLowerCase() === "windows";
  const defaultEquipmentType = runtime.equipmentType || "Notebook";
  const defaultModel = isWindows ? "Notebook Windows" : "Apple MacBook";

  const portableState = {
    info: runtime.info || {},
    osNumero: Number(runtime.osNumero || 235),
    serverUrl: runtime.serverUrl || "http://INFOCAIJ:9100",
    lastServerStatus: runtime.lastServerStatus || "nao verificado",
    lastOsSync: runtime.lastOsSync || "",
    pendingCreatedOs: 0,
    manualOsSet: false,
    equipmentType: defaultEquipmentType,
    device3u: null,
  };
  let lastSeenConfirmed = null;
  let activeServer = "";

  function formatOs(value) {
    return `C${String(Math.max(Number(value) || 0, 0)).padStart(6, "0")}`;
  }

  function publicState() {
    return {
      ...portableState,
      osFormatada: formatOs(portableState.osNumero),
    };
  }

  function normalizeServer(value) {
    let raw = String(value || "").trim().replace(/\/$/, "");
    if (!raw) return "";
    if (!/^https?:\/\//i.test(raw)) raw = `http://${raw}:9100`;
    return raw;
  }

  function serverCandidates() {
    return [...new Set([
      /^https?:$/i.test(window.location.protocol) ? window.location.origin : "",
      runtime.serverUrl,
      portableState.serverUrl,
      "http://INFOCAIJ.local:9100",
      "http://INFOCAIJ:9100",
      "http://192.168.15.11:9100",
    ].map(normalizeServer).filter(Boolean))];
  }

  async function fetchWithTimeout(url, options, timeout) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeout);
    try {
      return await fetch(url, { ...options, cache: "no-store", signal: controller.signal });
    } finally {
      clearTimeout(timer);
    }
  }

  async function central(path, body, timeout = 12000) {
    const options = body === undefined ? {} : {
      method: "POST",
      headers: { "Content-Type": "application/json; charset=utf-8" },
      body: JSON.stringify(body),
    };
    let lastError = null;
    const candidates = activeServer ? [activeServer, ...serverCandidates()] : serverCandidates();
    for (const base of [...new Set(candidates)]) {
      try {
        const response = await fetchWithTimeout(base + path, options, timeout);
        const data = await response.json();
        if (!response.ok || String(data.status || "ok").toLowerCase() === "erro") {
          throw new Error(data.mensagem || data.message || "Falha no servidor CAIJ");
        }
        activeServer = base;
        portableState.serverUrl = base;
        portableState.lastServerStatus = "online";
        return data;
      } catch (error) {
        lastError = error;
      }
    }
    portableState.lastServerStatus = "offline";
    throw new Error(`Servidor CAIJ indisponivel. ${lastError && lastError.message ? lastError.message : "Verifique a rede."}`);
  }

  function cpuShort(value) {
    const text = String(value || "").trim();
    const apple = text.match(/Apple\s+(M\d+[^\s(]*)/i);
    if (apple) return `Apple ${apple[1]}`;
    const intel = text.match(/i([3579]).*?(\d{4,5})/i);
    if (!intel) return text || "N/A";
    const model = intel[2];
    const firstTwo = Number(model.slice(0, 2));
    const generation = firstTwo >= 10 && firstTwo <= 19 ? firstTwo : Number(model[0]);
    const mod100 = generation % 100;
    const suffix = mod100 >= 11 && mod100 <= 13 ? "th" : ({ 1: "st", 2: "nd", 3: "rd" }[generation % 10] || "th");
    return `i${intel[1]} ${generation}${suffix}`;
  }

  function ramShort(value) {
    const text = String(value || "").trim();
    const match = text.match(/(\d+)\s*GB/i);
    if (!match) return text || "N/A";
    if (/Unificada/i.test(text)) return `${match[1]}GB Unificada`;
    const kind = text.match(/(LPDDR[345]|DDR[345])/i);
    return `${match[1]}GB${kind ? ` ${kind[1].toUpperCase()}` : ""}`;
  }

  function diskShort(value) {
    const text = String(value || "").trim();
    if (/1TB|\b(931|1000|1024)GB\b/i.test(text)) return "1TB SSD";
    if (/\b(476|480|494|500|512)GB\b/i.test(text)) return "512GB SSD";
    if (/\b(238|240|250|256)GB\b/i.test(text)) return "256GB SSD";
    if (/\b(119|120|128)GB\b/i.test(text)) return "128GB SSD";
    return text.slice(0, 18) || "N/A";
  }

  function gpuShort(value) {
    const text = String(value || "").trim();
    if (!text || /^(N\/?A|Nao identificada)$/i.test(text)) return null;
    const apple = text.match(/Apple\s+(M\d+[^\s(]*)/i);
    if (apple) return `Apple ${apple[1]}`;
    if (/Iris\s*Xe/i.test(text)) return "Intel Iris Xe";
    if (/UHD/i.test(text)) return "Intel UHD";
    return text.slice(0, 28);
  }

  function printPayload(info, grade, obs, includeOs) {
    const serial = String(info.serial || "").trim();
    return {
      os: includeOs ? portableState.osNumero : null,
      modelo: info.modelo || defaultModel,
      serial: serial && serial !== "N/A" ? serial : "XXXXXX",
      tipoEquipamento: portableState.equipmentType,
      cpu: cpuShort(info.cpu),
      gpu: gpuShort(info.gpu),
      ram: ramShort(info.ram),
      ramMods: ramShort(info.ram),
      disco: diskShort(info.disco),
      fichaCpu: info.cpu || "N/A",
      fichaGpu: info.gpu || "N/A",
      fichaRam: info.ram || "N/A",
      fichaDisco: info.disco || "N/A",
      modoManual: false,
      bateria: info.bateria || "N/A",
      monitorTamanho: info.monitorTamanho || "",
      monitorEntradas: info.monitorEntradas || "",
      celularImei: info.imei || portableState.device3u?.imei || "",
      celularCiclos: info.ciclos || portableState.device3u?.ciclos || "",
      grade: String(grade || "A").trim().toUpperCase(),
      obs: obs || "",
    };
  }

  function configSummary(info, device3u) {
    if (device3u) {
      return [
        device3u.imei ? `IMEI: ${device3u.imei}` : "",
        device3u.armazenamento ? `ARMAZ: ${device3u.armazenamento}` : "",
        device3u.ram ? `RAM: ${device3u.ram}` : "",
        device3u.bateria ? `BATERIA: ${device3u.bateria}` : "",
        Number(device3u.ciclos) > 0 ? `CICLOS: ${device3u.ciclos}` : "",
      ].filter(Boolean).join(" | ");
    }
    const gpu = gpuShort(info.gpu);
    return `CONFIG: ${[cpuShort(info.cpu).toUpperCase(), diskShort(info.disco).toUpperCase(), `${ramShort(info.ram).toUpperCase()} RAM`, gpu ? gpu.toUpperCase() : ""].filter(Boolean).join(" | ")}`;
  }

  function automaticObservation(text, technician, info, device3u, equipmentType) {
    const now = new Date();
    const date = now.toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit", year: "2-digit" });
    const time = now.toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" });
    const displayName = String(technician || "").trim().toLowerCase().replace(/(^|\s)\p{L}/gu, (letter) => letter.toUpperCase());
    const type = String(equipmentType || portableState.equipmentType || "Notebook");
    const configuration = /^Monitor$/i.test(type) ? "" : configSummary(info || {}, device3u);
    const lines = [String(text || "").trim(), configuration].filter(Boolean);
    return `${date} - ${time}${displayName ? ` - ${displayName}` : ""}: ${lines.join("\n")}`;
  }

  function normalizeOsDetail(order, osNumber) {
    const products = Array.isArray(order?.produtos) ? order.produtos : [];
    const product = String(order?.equipamento || order?.produtoResumo || products.map((item) => item.descricao || item.nome || "").filter(Boolean).join(" | ") || "Produto não informado").trim();
    return {
      osCodigo: formatOs(osNumber),
      produto: product,
      tecnico: String(order?.tecnico || "-").trim(),
      serial: String(order?.garantia || order?.serial || "-").trim(),
      statusOs: String(order?.statusOs || "").trim(),
      online: Boolean(order),
      message: order ? "" : "OS não localizada no Altertag",
    };
  }

  async function portableApi(path, body) {
    if (path === "/api/state") return publicState();
    if (path === "/api/info") {
      portableState.info = { ...portableState.info, ...(body.info || {}) };
      if (body.equipmentType) portableState.equipmentType = body.equipmentType;
      return publicState();
    }
    if (path === "/api/set-os") {
      portableState.osNumero = Math.max(Number(body.osNumero) || 1, 1);
      portableState.manualOsSet = isWindows;
      return { ok: true, osNumero: portableState.osNumero, state: publicState() };
    }
    if (path === "/api/native-command") {
      if (!runtime.sessionId) throw new Error("Sessao local do Mac nao identificada.");
      const data = await central("/mac/comando", { session: runtime.sessionId, command: body.command }, 5000);
      return { ok: true, message: data.mensagem || "Comando enviado." };
    }
    if (path === "/api/read-3utools") {
      if (!isWindows || !runtime.localBridgeUrl) throw new Error("Leitor local do 3uTools não está disponível.");
      const response = await fetchWithTimeout(`${runtime.localBridgeUrl}/3utools`, { method: "POST" }, 25000);
      const data = await response.json();
      if (!response.ok || data.ok === false) throw new Error(data.message || "Não foi possível ler o 3uTools.");
      portableState.device3u = data.device || null;
      return data;
    }
    if (path === "/api/sync-os") {
      const data = await central("/status-os", undefined, 15000);
      portableState.osNumero = Number(data.proximoDisponivel || portableState.osNumero);
      portableState.manualOsSet = false;
      portableState.lastOsSync = new Date().toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" });
      return publicState();
    }
    if (path === "/api/os-watch") {
      const data = await central("/status-os-local", undefined, 5000);
      const confirmed = Number(data.ultimoConfirmado || 0);
      const next = Number(data.proximoDisponivel || confirmed + 1);
      const event = lastSeenConfirmed !== null && confirmed > lastSeenConfirmed;
      lastSeenConfirmed = Math.max(lastSeenConfirmed || 0, confirmed);
      if (!portableState.pendingCreatedOs && !portableState.manualOsSet && next > 0) portableState.osNumero = next;
      return {
        ok: true,
        event,
        osCriada: confirmed ? formatOs(confirmed) : "",
        proximaOs: formatOs(next),
        state: publicState(),
      };
    }
    if (path === "/api/os-detail") {
      const osNumber = Number(body.osNumero || portableState.osNumero || 0);
      if (!osNumber) throw new Error("Informe uma OS válida.");
      const data = await central(`/os-detalhe?osNumero=${osNumber}&produtos=1`, undefined, 8000);
      return { ok: true, detail: normalizeOsDetail(data.ordem, osNumber) };
    }
    if (path === "/api/products") {
      const term = String(body.term || "").trim();
      if (term.length < 2) throw new Error("Digite pelo menos 2 caracteres.");
      const data = await central("/buscar-opcoes-altertag", { tipo: "produto", termo: term, modo: "catalogo" }, 25000);
      return { ok: true, produtos: data.produtos || [], fonte: data.fonte || "Altertag", message: data.mensagem || "Produtos encontrados." };
    }
    if (path === "/api/create-os") {
      const product = body.produto || {};
      const device3u = body.device3u || null;
      const equipmentType = device3u ? "Celular" : (body.equipmentType || portableState.equipmentType);
      const observation = automaticObservation(body.observacao, body.tecnico, body.info || portableState.info, device3u, equipmentType);
      const payload = {
        tecnico: body.tecnico,
        serial: body.serial,
        referencia: body.referencia || "GRADE T - TRIAGEM",
        idProduto: Number(product.idProduto || 0),
        produtoCodigo: String(product.codigo || product.produtoCodigo || ""),
        produtoDescricao: String(product.descricao || product.nome || ""),
        produtoValor: String(product.valor || "0.00"),
        servicos: body.servicos || [],
        tipoEquipamento: equipmentType,
        observacao: observation,
      };
      const data = await central("/criar-os-altertag", payload, 45000);
      const created = Number(data.osNumero || 0);
      portableState.info = { ...portableState.info, ...(body.info || {}) };
      portableState.equipmentType = equipmentType;
      portableState.osNumero = created || portableState.osNumero;
      portableState.pendingCreatedOs = created;
      portableState.manualOsSet = false;
      lastSeenConfirmed = Math.max(lastSeenConfirmed || 0, created);
      return { ok: true, osCriada: formatOs(created), proximaOs: formatOs(data.proximoDisponivel || created + 1), observacao: observation, state: publicState(), response: data };
    }
    if (path === "/api/print") {
      const grade = String(body.grade || "A").toUpperCase();
      const obs = String(body.obs || "").trim();
      if ((grade === "B" || grade === "C") && !obs) throw new Error(`Observacoes sao obrigatorias para Grade ${grade}.`);
      portableState.info = { ...portableState.info, ...(body.info || {}) };
      if (body.equipmentType) portableState.equipmentType = body.equipmentType;
      if (body.includeOs && !portableState.pendingCreatedOs && !portableState.manualOsSet) {
        try {
          const reserved = await central("/proxima-os", {}, 12000);
          if (reserved.osNumero) portableState.osNumero = Number(reserved.osNumero);
        } catch (_) {}
      }
      const payload = printPayload(portableState.info, grade, obs, Boolean(body.includeOs));
      const data = await central("/imprimir", payload, 22000);
      portableState.pendingCreatedOs = 0;
      portableState.manualOsSet = false;
      if (body.includeOs) {
        try {
          const synced = await central("/status-os", undefined, 12000);
          portableState.osNumero = Number(synced.proximoDisponivel || portableState.osNumero + 1);
        } catch (_) {}
      }
      const tracker = data.rastreador || null;
      return {
        ok: true,
        message: data.mensagem || "Etiqueta enviada com sucesso.",
        payload,
        tracker,
        syncWarning: String(tracker?.status || "").toLowerCase() === "warning",
        state: publicState(),
      };
    }
    throw new Error("Acao nao disponivel no modo portatil.");
  }

  window.CAIJ_PORTABLE_API = portableApi;
  window.CAIJ_PORTABLE_STATE = publicState;
})();
