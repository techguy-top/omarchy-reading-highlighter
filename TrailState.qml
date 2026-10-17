pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons as Commons

Scope {
  id: highlighterState
  property bool active: false
  property string colorName: "Orange"
  readonly property color ink: colorName === "Green" ? "#59e36b" : colorName === "Red" ? "#ff6262" : "#ffab40"
  property var monitors: []
  property var points: []
  property real now: Date.now()
  property string error: ""
  property var previousPosition: null
  property bool backendReady: false
  property bool preparing: false
  property bool capturing: false
  property bool processing: false
  property bool released: false
  property bool simpleHold: false
  property string captureMonitor: ""
  property var capturePoints: []
  property string destination: ""
  property string selectedApp: ""
  property bool autoOpen: false
  property var appOptions: []
  property string lastPreview: ""
  property bool saved: false
  property string settingsState: ""
  readonly property bool captureBusy: preparing || capturing || processing
  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
  function send(message) { backend.write(JSON.stringify(message) + "\n") }
  function saveSettings(file, app, openAfter) {
    error = ""; settingsState = ""
    send({action:"settings", file:file, app:app, autoOpen:openAfter})
  }
  function openFolder() { error = ""; send({action:"folder"}) }
  function openNotes() { error = ""; send({action:"open"}) }
  function beginHoldCapture() {
    if (!active || captureBusy || !backendReady) return
    simpleHold = true
    beginCapture()
  }
  function endHoldCapture() {
    if (!simpleHold) return
    simpleHold = false
    if (capturePoints.length < 2) cancelCapture()
    else finishCapture()
  }
  function beginCapture() {
    if (captureBusy || !backendReady) return
    captureMonitor = ""; preparing = true; released = false; saved = false; error = ""
    capturePoints = []; points = []; previousPosition = null
    prepareTimer.start()
  }
  function finishCapture() {
    if (preparing) { released = true; return }
    if (!capturing) return
    capturing = false; processing = true
    send({action:"finish", points:capturePoints})
  }
  function cancelCapture() {
    if (!preparing && !capturing) return
    prepareTimer.stop(); preparing = false; capturing = false; released = false
    capturePoints = []; send({action:"cancel"})
  }
  function backendMessage(data) {
    var p = JSON.parse(data)
    if (p.event === "settings") {
      destination = p.settings.file; selectedApp = p.settings.app; autoOpen = p.settings.autoOpen
      appOptions = [{value:"", label:strings.t("app.default")}].concat(p.apps)
      settingsState = backendReady ? "saved" : ""; backendReady = true
    } else if (p.event === "ready") {
      if (captureMonitor !== "" && captureMonitor !== p.monitor) { cancelCapture(); error = "Keep each capture on the monitor where you started."; return }
      captureMonitor = p.monitor; capturing = true; preparing = false
      if (released) finishCapture()
    } else if (p.event === "saved") {
      processing = false; saved = true; lastPreview = p.preview; capturePoints = []
    } else if (p.event === "error" || p.event === "openError") {
      preparing = false; capturing = false; processing = false
      error = p.message; settingsState = ""; capturePoints = []
    }
  }
  Timer { id: prepareTimer; interval: 100; onTriggered: highlighterState.send({action:"start"}) }
  Timer { interval: 120000; running: highlighterState.capturing; onTriggered: highlighterState.finishCapture() }
  Process {
    id: backend
    command: ["python3", "-B", Qt.resolvedUrl("capture.py").toString().replace("file://", "")]
    running: true
    stdinEnabled: true
    stdout: SplitParser { onRead: data => { try { highlighterState.backendMessage(data) } catch (e) { console.warn("Highlighter capture:", e) } } }
    onExited: (code, status) => {
      highlighterState.backendReady = false
      highlighterState.preparing = false; highlighterState.capturing = false; highlighterState.processing = false
      highlighterState.error = "Capture helper stopped. Reload the plugin to retry."
    }
  }
  function toggleActive() { active = !active }
  function chooseColor(name) {
    if (["Orange", "Green", "Red"].indexOf(name) >= 0) colorName = name
  }
  function monitorAt(x, y) {
    for (var m of monitors) {
      var rotated = m.transform % 2 === 1
      var w = (rotated ? m.height : m.width) / m.scale
      var h = (rotated ? m.width : m.height) / m.scale
      if (x >= m.x && x < m.x + w && y >= m.y && y < m.y + h) return m
    }
    return null
  }
  function sample(p) {
    if (p.monitors) { monitors = p.monitors; return }
    if ((!active && !capturing && !preparing) || !isFinite(p.x) || !isFinite(p.y)) return
    if ((capturing || preparing) && capturePoints.length < 4000) {
      var cm = monitorAt(p.x, p.y)
      if (cm && captureMonitor === "") captureMonitor = cm.name
      if (!cm || cm.name !== captureMonitor) { cancelCapture(); error = "Keep each capture on the monitor where you started."; return }
      var cp = capturePoints.length ? capturePoints[capturePoints.length - 1] : null
      if (!cp || Math.hypot(p.x - cp.x, p.y - cp.y) >= 2) capturePoints = capturePoints.concat([{x:p.x, y:p.y, screen:cm.name}])
      if (capturePoints.length >= 4000) finishCapture()
    }
    if (!active) return
    var m = monitorAt(p.x, p.y)
    if (!m) return
    if (previousPosition && previousPosition.x === p.x && previousPosition.y === p.y) return
    previousPosition = {x:p.x, y:p.y}
    var next = points.slice()
    var last = next.length ? next[next.length - 1] : null
    if (last && last.x === p.x && last.y === p.y) return
    var distance = last ? Math.hypot(p.x - last.x, p.y - last.y) : 0
    var physical = m.transform % 2 === 1 ? m.physicalHeight : m.physicalWidth
    var pixels = m.transform % 2 === 1 ? m.height : m.width
    var inch = physical > 0 ? pixels / m.scale * 25.4 / physical : 96
    if (last && (last.screen !== m.name || distance > inch * 2)) next = []
    next.push({x:p.x, y:p.y, t:Date.now(), screen:m.name})
    var length = 0
    for (var i = next.length - 1; i > 0; --i) {
      var a = next[i], b = next[i - 1]
      var d = Math.hypot(a.x-b.x, a.y-b.y)
      if (length + d > inch) {
        var fraction = (inch - length) / d
        next[i-1] = {x:a.x+(b.x-a.x)*fraction, y:a.y+(b.y-a.y)*fraction, t:b.t, screen:b.screen}
        next = next.slice(i-1)
        break
      }
      length += d
    }
    points = next
  }
  onActiveChanged: { points = []; previousPosition = null; error = ""; if (!active && simpleHold) { cancelCapture(); simpleHold = false } }
  IpcHandler {
    target: "reading-highlighter"
    function toggle(): void { highlighterState.toggleActive() }
    function off(): void { highlighterState.active = false }
    function color(name: string): void { highlighterState.chooseColor(name) }
    function captureHoldStart(): void { highlighterState.beginHoldCapture() }
    function captureHoldStop(): void { highlighterState.endHoldCapture() }
    function captureStart(): void { highlighterState.beginCapture() }
    function captureStop(): void { highlighterState.finishCapture() }
    function captureCancel(): void { highlighterState.cancelCapture() }
    function openFolderIfActive(): bool {
      if (!highlighterState.active) return false
      highlighterState.openFolder()
      return true
    }
    function openNotesIfActive(): bool {
      if (!highlighterState.active) return false
      highlighterState.openNotes()
      return true
    }
    function openFolder(): void { highlighterState.openFolder() }
    function openNotes(): void { highlighterState.openNotes() }
    function status(): string { return JSON.stringify({active:highlighterState.active, color:highlighterState.colorName, points:highlighterState.points.length, error:highlighterState.error, backendReady:highlighterState.backendReady, preparing:highlighterState.preparing, capturing:highlighterState.capturing, processing:highlighterState.processing, saved:highlighterState.saved, simpleHold:highlighterState.simpleHold, file:highlighterState.destination, app:highlighterState.selectedApp, capturePoints:highlighterState.capturePoints.length}) }
  }
  Process {
    id: pointer
    command: ["python3", Qt.resolvedUrl("pointer.py").toString().replace("file://", "")]
    running: highlighterState.active || highlighterState.capturing || highlighterState.preparing
    stdout: SplitParser {
      onRead: data => { try { highlighterState.sample(JSON.parse(data)) } catch (e) { console.warn("Highlighter sample:", e) } }
    }
    onExited: (code, status) => {
      if (highlighterState.active || highlighterState.capturing || highlighterState.preparing) { highlighterState.cancelCapture(); highlighterState.active = false; highlighterState.error = "Pointer connection stopped. Try turning it on again." }
    }
  }
  Timer {
    interval: 33
    repeat: true
    running: highlighterState.active || highlighterState.capturing || highlighterState.preparing
    onTriggered: {
      highlighterState.now = Date.now()
      highlighterState.points = highlighterState.points.filter(p => highlighterState.now - p.t < 3000)
    }
  }
  Variants {
    model: Quickshell.screens
    PanelWindow {
      id: overlay
      required property var modelData
      screen: modelData
      visible: !highlighterState.preparing && ((highlighterState.active && highlighterState.points.length > 0) || highlighterState.capturing)
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "reading-highlighter"
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      color: "transparent"
      mask: Region {}
      Canvas {
        id: canvas
        anchors.fill: parent
        opacity: 0.34
        Connections {
          target: highlighterState
          function onNowChanged() { canvas.requestPaint() }
          function onInkChanged() { canvas.requestPaint() }
          function onCapturePointsChanged() { canvas.requestPaint() }
          function onCapturingChanged() { canvas.requestPaint() }
        }
        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          var m = highlighterState.monitors.find(m => m.name === overlay.screen.name)
          if (!m) return
          var pts = (highlighterState.capturing ? highlighterState.capturePoints : highlighterState.points).filter(p => p.screen === m.name)
          ctx.strokeStyle = highlighterState.ink
          ctx.fillStyle = highlighterState.ink
          ctx.lineWidth = 18
          ctx.lineCap = "round"
          // Lighten compositing avoids darker blobs where strokes overlap.
          ctx.globalCompositeOperation = "lighten"
          for (var i = 0; i < pts.length; ++i) {
            var p = pts[i]
            ctx.globalAlpha = highlighterState.capturing ? 1 : Math.max(0, 1 - (highlighterState.now - p.t) / 3000)
            ctx.beginPath()
            if (i === 0) {
              ctx.arc(p.x-m.x, p.y-m.y, 9, 0, Math.PI*2)
              ctx.fill()
            } else {
              ctx.moveTo(pts[i-1].x-m.x, pts[i-1].y-m.y)
              ctx.lineTo(p.x-m.x, p.y-m.y)
              ctx.stroke()
            }
          }
        }
      }
    }
  }
}
