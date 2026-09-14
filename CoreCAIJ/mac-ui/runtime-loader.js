(function () {
  "use strict";
  const match = window.location.hash.match(/^#runtime=([A-Za-z0-9_-]+)$/);
  if (!match) return;
  try {
    let token = match[1].replace(/-/g, "+").replace(/_/g, "/");
    while (token.length % 4) token += "=";
    const binary = atob(token);
    const bytes = Uint8Array.from(binary, (char) => char.charCodeAt(0));
    const json = new TextDecoder("utf-8").decode(bytes);
    window.CAIJ_NATIVE_RUNTIME = JSON.parse(json);
    history.replaceState(null, "", window.location.pathname + window.location.search);
  } catch (_) {
    window.CAIJ_NATIVE_RUNTIME = null;
  }
})();
