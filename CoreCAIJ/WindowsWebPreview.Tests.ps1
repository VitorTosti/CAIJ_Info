$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$launcher = Get-Content -LiteralPath (Join-Path $root 'TestarInterfaceWindows.bat') -Raw
$preview = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'InfoNotebookWindowsPreview.ps1') -Raw
$html = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'mac-ui\index.html') -Raw
$app = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'mac-ui\app.js') -Raw
$style = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'mac-ui\style.css') -Raw
$portable = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'mac-ui\portable.js') -Raw

$checks = @(
    @($launcher, 'InfoNotebookWindowsPreview.ps1'),
    @($preview, "platform = 'windows'"),
    @($preview, "'--inprivate'"),
    @($preview, '--user-data-dir='),
    @($preview, 'Send-LocalUiFile'),
    @($preview, 'function Test-LocalClientDisconnect'),
    @($preview, 'http://127.0.0.1:$localBridgePort/'),
    @($preview, 'Win32_ComputerSystemProduct'),
    @($preview, 'function Get-WindowsBatterySummary'),
    @($preview, 'powercfg.exe'),
    @($preview, '/batteryreport /output $reportPath /xml'),
    @($html, 'id="platformName"'),
    @($app, 'isWindowsPreview'),
    @($app, 'Central de testes Windows'),
    @($app, 'Privacidade e segurança > Câmera ou Microfone'),
    @($app, 'normalizeStorage'),
    @($app, 'refreshOsVerification'),
    @($html, 'id="currentConfigCard"'),
    @($html, 'id="read3uTools"'),
    @($html, 'id="osVerification"'),
    @($html, 'class="hero-command-bar"'),
    @($html, 'id="openMenu"'),
    @($html, 'id="openLabels"'),
    @($html, 'id="homeView"'),
    @($html, 'id="labelsView"'),
    @($html, 'id="testsView"'),
    @($html, 'id="createOsView"'),
    @($html, 'id="createCurrentOs"'),
    @($html, 'class="thermal-label"'),
    @($html, 'id="labelPreviewModel"'),
    @($html, 'id="printOsInput"'),
    @($html, 'id="toggleLabelEditor"'),
    @($html, 'id="labelEditForm"'),
    @($html, 'aria-current="page"'),
    @($html, 'class="os-box hero-os"'),
    @($html, 'class="brand-copy hidden"'),
    @($html, 'class="equipment-summary"'),
    @($html, 'OS selecionada'),
    @($html, 'id="workflowTitle"'),
    @($html, 'id="refreshReading"'),
    @($html, 'id="copyDeviceInfo"'),
    @($html, 'id="sessionClock"'),
    @($html, 'id="workflowOverall"'),
    @($html, 'id="nextActionButton"'),
    @($html, 'id="operationalAlerts"'),
    @($html, 'id="reviewSerialDivergence"'),
    @($html, 'id="lastPrintValue"'),
    @($html, 'id="reprintLast"'),
    @($html, 'id="printHistoryList"'),
    @($html, 'id="printHistoryEmpty"'),
    @($html, 'id="printHistoryCount"'),
    @($html, 'id="printHistoryPanel"'),
    @($html, 'class="workflow-marker"'),
    @($app, 'function renderOperationalDashboard()'),
    @($app, 'function renderPrintHistory()'),
    @($app, 'function setButtonBusy(button, busy'),
    @($app, 'function runWorkflowAction(action)'),
    @($app, 'function refreshDeviceReading()'),
    @($app, 'function copyDeviceInfo()'),
    @($app, 'function updateSessionClock()'),
    @($app, 'function syncCompletedTestsToObservations(pending)'),
    @($html, 'id="finishTests"'),
    @($html, 'id="testsCompletion"'),
    @($html, 'class="tests-head-icon"'),
    @($html, 'class="test-icon"'),
    @($app, 'caij:last-print'),
    @($app, 'caij:print-history'),
    @($portable, 'automaticObservation'),
    @($portable, '/api/os-detail'),
    @($portable, '/api/read-3utools'),
    @($portable, 'manualOsSet'),
    @($portable, '!portableState.manualOsSet'),
    @($preview, 'Get-Windows3uToolsInfo'),
    @($preview, "-Arguments '-k SerialNumber'"),
    @($preview, 'BaseName -ieq "${currentSerial}_info"'),
    @($preview, 'ainda não foi atualizado no 3uTools'),
    @($preview, 'localBridgeUrl'),
    @($portable, 'equipmentType'),
    @($app, 'function showAppView(view)'),
    @($app, 'function populateLabelEditor()'),
    @($app, 'function updatePrintOsAvailability()'),
    @($app, 'function labelContextFromCreate(body)'),
    @($app, 'function import3uToolsDevice(button)'),
    @($app, 'awaitingDeviceImport'),
    @($app, 'const hadImportedDevice = Boolean(state.device3u)'),
    @($app, 'state.device3u = null'),
    @($app, 'function inferEquipmentType(product'),
    @($html, 'id="printCreatedOs"'),
    @($html, 'name="monitorTamanho"'),
    @($html, 'name="monitorEntradas"'),
    @($html, 'id="labelEquipmentType"'),
    @($html, 'id="read3uToolsLabel"'),
    @($html, 'name="imei"'),
    @($html, 'name="ciclos"'),
    @($portable, 'monitorTamanho: info.monitorTamanho'),
    @($portable, 'monitorEntradas: info.monitorEntradas'),
    @($portable, 'celularImei: info.imei'),
    @($portable, 'celularCiclos: info.ciclos'),
    @($style, '.label-workspace'),
    @($style, 'aspect-ratio: 8 / 5'),
    @($style, '--accent-cyan: #55c8ff'),
    @($style, '--accent-mint: #4cdda2'),
    @($style, '.workflow-step:nth-child(3)'),
    @($style, '.grade-fieldset .grade[data-grade="RMA"].active'),
    @($style, 'button.is-busy::before'),
    @($style, '@keyframes action-spin')
)

if ($html.Contains('id="printHero"')) {
    throw 'O topo nao deve repetir o botao de imprimir etiqueta.'
}
if (-not ($preview -match 'Test-LocalClientDisconnect[\s\S]*System\.IO\.IOException[\s\S]*System\.Net\.Sockets\.SocketException[\s\S]*System\.ObjectDisposedException')) {
    throw 'O servidor local deve reconhecer desconexoes normais do navegador.'
}
if (-not ($preview -match 'Send-LocalBytesResponse[\s\S]*catch\s*\{[\s\S]*Test-LocalClientDisconnect[\s\S]*while \(-not \$edgeProcess\.HasExited\)[\s\S]*catch\s*\{[\s\S]*Test-LocalClientDisconnect')) {
    throw 'Uma conexao cancelada pelo Edge nao deve encerrar a interface local.'
}
if ($html -match 'id="testsDialog"|id="createOsDialog"') {
    throw 'Testes e Cadastrar OS devem ser paginas, nao pop-ups.'
}
if (-not ($app -match 'home:\s*"homeView"[\s\S]*labels:\s*"labelsView"[\s\S]*tests:\s*"testsView"[\s\S]*createOs:\s*"createOsView"')) {
    throw 'A navegacao principal deve controlar as quatro paginas internas.'
}
if (-not ($html -match 'create-os-head-actions[\s\S]*OS ATUAL[\s\S]*id="createCurrentOs"')) {
    throw 'A pagina Cadastrar OS deve destacar a OS atual no cabecalho.'
}
if (-not ($app -match 'osNumberFromInput\(\)[\s\S]*createCurrentOs[\s\S]*showAppView\("createOs"\)')) {
    throw 'A OS atual deve ser sincronizada ao abrir a pagina Cadastrar OS.'
}
if ($html.Contains('id="heroModel"') -or $app.Contains('qs("heroModel")')) {
    throw 'O topo nao deve repetir o modelo exibido nas informacoes da maquina.'
}
if ($html -match 'Adicionar a observa') {
    throw 'Os testes concluidos devem atualizar as observacoes automaticamente.'
}
if (-not ($html -match 'id="workflowRead"[\s\S]*id="workflowTests"[\s\S]*id="workflowOs"[\s\S]*id="workflowLabel"')) {
    throw 'O Menu deve resumir leitura, testes, OS e etiqueta na ordem operacional.'
}
if (-not ($app -match 'internetOnline[\s\S]*serverOnline[\s\S]*hasSerialDivergence')) {
    throw 'O Menu deve concentrar somente alertas operacionais relevantes.'
}
if (-not ($html -match '<section class="topbar">[\s\S]*?class="hero-command-bar"')) {
    throw 'A navegacao deve ficar dentro da barra superior.'
}
if (-not ($style -match '\.topbar\s*\{[\s\S]*?position:\s*sticky;[\s\S]*?top:\s*0;[\s\S]*?z-index:\s*100;')) {
    throw 'A navegacao superior deve permanecer visivel durante a rolagem.'
}
if (-not ($style -match '\.topbar,\s*\.windows-preview \.topbar\s*\{[\s\S]*?background:\s*#0d111b;')) {
    throw 'A barra superior deve usar uma unica superficie solida, sem divergencia no fundo.'
}
if (-not ($style -match '\.home-workspace\s*\{\s*align-items:\s*start;\s*\}')) {
    throw 'Os paineis do Menu nao devem ser esticados e criar espaco vazio.'
}
if (-not ($html -match '<section class="hero-strip">[\s\S]*?class="equipment-summary"[\s\S]*?class="os-box hero-os"')) {
    throw 'A OS selecionada deve ficar na mesma faixa do equipamento conectado.'
}
if ($html -match 'hero-action-index|hero-action-copy') {
    throw 'A navegacao superior deve usar somente rotulos curtos.'
}
$homeIndex = $html.IndexOf('id="homeView"')
$labelsIndex = $html.IndexOf('id="labelsView"')
$printIndex = $html.IndexOf('class="panel print-panel"')
if ($homeIndex -lt 0 -or $labelsIndex -le $homeIndex -or $printIndex -le $labelsIndex) {
    throw 'A impressao deve ficar somente na pagina Etiquetas, depois da pagina inicial.'
}
if (-not ($app.Contains('window.scrollTo({ top: 0, behavior: "smooth" })'))) {
    throw 'A aba Menu deve retornar para a pagina principal.'
}
if (-not ($html -match 'id="statusLine" hidden')) {
    throw 'A linha de status nao deve ficar visivel na interface principal.'
}
if (-not ($html -match 'id="labelEditForm"[\s\S]*name="modelo"[\s\S]*name="serial"[\s\S]*name="cpu"[\s\S]*name="ram"[\s\S]*name="disco"[\s\S]*name="gpu"[\s\S]*name="bateria"')) {
    throw 'A pagina Etiquetas deve permitir editar manualmente todos os dados impressos.'
}
if (-not ($app -match 'printOsInput[\s\S]*persistEditedOs\(\)[\s\S]*refreshOsVerification\(\)')) {
    throw 'A OS alterada na pagina Etiquetas deve ser persistida e conferida.'
}
if (-not ($app -match 'printBtn[\s\S]*api\("/api/print", body\)[\s\S]*showAppView\("home"\)')) {
    throw 'Depois de uma impressao confirmada, a interface deve voltar ao Menu.'
}
if (-not ($app -match 'submitCreateOs[\s\S]*setButtonBusy\(createButton, true, "Criando OS\.\.\."\)[\s\S]*api\("/api/create-os"[\s\S]*finally[\s\S]*setButtonBusy\(createButton, false\)')) {
    throw 'O botao Criar OS deve mostrar o andamento e bloquear cliques duplicados.'
}
if (-not ($app -match 'printBtn[\s\S]*setButtonBusy\(printButton, true, "Imprimindo etiqueta\.\.\."\)[\s\S]*api\("/api/print", body\)[\s\S]*finally[\s\S]*setButtonBusy\(printButton, false\)')) {
    throw 'O botao Imprimir etiqueta deve mostrar o andamento e bloquear cliques duplicados.'
}
$printHandlerStart = $app.IndexOf('qs("printBtn").addEventListener')
$printHandlerEnd = $app.IndexOf('qs("fullscreenBtn").addEventListener', $printHandlerStart)
$printHandlerText = $app.Substring($printHandlerStart, $printHandlerEnd - $printHandlerStart)
if ($printHandlerText -match 'refreshOsVerification') {
    throw 'A impressao nao deve aguardar uma segunda consulta remota da OS antes de chegar ao spooler.'
}
if (-not ($printHandlerText -match 'persistEditedOs\(\)[\s\S]*api\("/api/print", body\)')) {
    throw 'A impressao rapida ainda deve persistir a OS selecionada antes do envio.'
}
if (-not ($html -match 'class="alert-created"[\s\S]*id="alertCreatedOs"[\s\S]*class="alert-next"[\s\S]*id="alertNextOs"')) {
    throw 'O pop-up deve destacar primeiro a OS criada e deixar a proxima OS como informacao secundaria.'
}
if (-not ($html -match 'id="homeView"[\s\S]*class="panel print-history-panel"[\s\S]*id="printHistoryList"')) {
    throw 'O historico das etiquetas deve aparecer no final da pagina Menu.'
}
if (-not ($app -match 'readPrintHistory[\s\S]*caij:print-history[\s\S]*slice\(0, 8\)')) {
    throw 'O historico deve preservar localmente somente as oito impressoes mais recentes.'
}
if (-not ($app -match 'printHistoryPanel[\s\S]*classList\.toggle\("is-empty", history\.length === 0\)')) {
    throw 'O historico vazio deve permanecer compacto no Menu.'
}
if (-not ($app -match 'workflowOverall"\)\.textContent = `\$\{completed\} de 4 etapas`')) {
    throw 'O andamento deve apresentar a contagem de etapas por extenso.'
}
if (-not ($app -match 'reviewSerialDivergence[\s\S]*showAppView\("labels"\)[\s\S]*refreshOsVerification')) {
    throw 'A divergencia de serial deve oferecer uma acao segura para conferir os dados.'
}
if (-not ($app -match 'testsCompletion"\)\.textContent = `\$\{completion\}%`[\s\S]*aria-pressed')) {
    throw 'A Central de Testes deve mostrar progresso geral e selecao acessivel dos resultados.'
}
if (-not ($style -match '\.tests-page \.test-row\.passed[\s\S]*\.tests-page \.test-row\.failed[\s\S]*\.test-actions button\[data-action="pass"\]\.selected')) {
    throw 'A Central de Testes deve diferenciar visualmente estados pendente, aprovado e reprovado.'
}
if (-not ($preview -match '\$lenovoPreflightPath\s*=\s*Join-Path \$PSScriptRoot ''PrepararLenovo\.ps1''')) {
    throw 'A interface Windows deve preservar o verificador da tecla de interrogacao Lenovo.'
}
if (-not ($preview -match 'SystemManufacturer[\s\S]*Scancode Map[\s\S]*Start-Process powershell\.exe[\s\S]*ExitCode -ne 0')) {
    throw 'O pre-check Lenovo deve detectar a correcao, executar o utilitario quando necessario e bloquear falhas.'
}
$preflightIndex = $preview.IndexOf('$lenovoPreflightPath')
$edgeLaunchIndex = $preview.IndexOf('$edgeProcess = Start-Process')
if ($preflightIndex -lt 0 -or $edgeLaunchIndex -le $preflightIndex) {
    throw 'O pre-check Lenovo deve terminar antes de a interface ser aberta.'
}
if (-not ($html -match 'class="verification-os"[\s\S]*class="verification-product"[\s\S]*class="verification-technician"[\s\S]*class="verification-serial"')) {
    throw 'O resumo da conferencia deve identificar os campos para um layout sem cortes.'
}
if (-not ($style -match '\.os-verification-grid strong\s*\{[\s\S]*?overflow-wrap:\s*anywhere;[\s\S]*?white-space:\s*normal;')) {
    throw 'As informacoes da conferencia devem quebrar linha em vez de serem cortadas.'
}
if (-not ($app -match 'api\("/api/create-os"[\s\S]*api\("/api/info", labelContext\)[\s\S]*showOsAlert\(data, true\)')) {
    throw 'A OS criada deve preparar os dados da etiqueta antes de exibir a confirmacao.'
}
if (-not ($app -match 'printCreatedOs[\s\S]*showAppView\("labels"\)[\s\S]*refreshOsVerification')) {
    throw 'A confirmacao da OS deve abrir diretamente a etiqueta preenchida.'
}
if (-not ($portable -match 'tipoEquipamento:\s*equipmentType')) {
    throw 'O tipo inferido no cadastro deve chegar ao payload da OS.'
}
if (-not ($portable.Contains('const configuration = /^Monitor$/i.test(type) ? ""'))) {
    throw 'Monitor nao deve receber configuracao automatica de notebook na observacao.'
}
if (-not ($app.Contains('el.hidden = isIdle'))) {
    throw 'O estado Pronto deve ficar oculto sem remover alertas operacionais.'
}
if (-not ($app.Contains('"bateria"'))) {
    throw 'O cartao de bateria deve completar o alinhamento das informacoes do notebook.'
}
if ($html -match 'Leitura autom.tica conclu.da') {
    throw 'O selo de leitura automatica concluida nao deve aparecer na interface.'
}
if (-not ($app -match 'windowsFields\s*=\s*\["modelo",\s*"serial",\s*"cpu",\s*"disco",\s*"gpu",\s*"ram",\s*"bateria"\]')) {
    throw 'No Windows, Disco deve preencher a coluna ao lado da CPU.'
}
if (-not ($app -match 'key === "bateria" \? "full"')) {
    throw 'No Windows, Bateria deve fechar toda a base da grade.'
}
if (-not ($app.Contains('isWindowsPreview ? windowsKeyboardRows : macKeyboardRows'))) {
    throw 'O mapa de teclado deve separar teclas Windows e Mac.'
}
if (-not ($app.Contains('return `TESTES: ${overall} | ${details}`'))) {
    throw 'O resumo dos testes nao deve ficar rotulado como teste do Mac.'
}

foreach ($check in $checks) {
    if (-not $check[0].Contains($check[1])) { throw "Trecho esperado nao encontrado: $($check[1])" }
}
if ($preview.Contains('unsafely-treat-insecure-origin-as-secure')) {
    throw 'A previa nao deve exibir o aviso de sinalizador inseguro do Edge.'
}
if ($preview -match 'EstimatedChargeRemaining') {
    throw 'A interface nova nao deve apresentar carga atual como se fosse saude da bateria.'
}
if ($preview -match 'saÃ|SaÃ') {
    throw 'A leitura da bateria nao pode conter texto UTF-8 corrompido.'
}
if (-not ($preview.Contains("[char]0x00FA"))) {
    throw 'O texto de saude da bateria deve ser seguro no Windows PowerShell 5.'
}
if (-not ($preview.Contains("*[local-name()='DesignCapacity']")) -or
    -not ($preview.Contains("*[local-name()='FullChargeCapacity']")) -or
    -not ($preview.Contains('100 * $fullTotal / $designTotal'))) {
    throw 'A saude da bateria deve comparar capacidade maxima atual com capacidade de projeto.'
}

Write-Output 'OK: Windows web preview tests'
