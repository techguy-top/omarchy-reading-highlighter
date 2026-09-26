pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

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
    if (!active || !isFinite(p.x) || !isFinite(p.y)) return
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
  onActiveChanged: { points = []; previousPosition = null; error = "" }
  IpcHandler {
    target: "reading-highlighter"
    function toggle(): void { highlighterState.toggleActive() }
    function off(): void { highlighterState.active = false }
    function color(name: string): void { highlighterState.chooseColor(name) }
    function status(): string { return JSON.stringify({active:highlighterState.active, color:highlighterState.colorName, points:highlighterState.points.length, error:highlighterState.error}) }
  }
  Process {
    id: pointer
    command: ["python3", Qt.resolvedUrl("pointer.py").toString().replace("file://", "")]
    running: highlighterState.active
    stdout: SplitParser {
      onRead: data => { try { highlighterState.sample(JSON.parse(data)) } catch (e) { console.warn("Highlighter sample:", e) } }
    }
    onExited: (code, status) => {
      if (highlighterState.active) { highlighterState.active = false; highlighterState.error = "Pointer connection stopped. Try turning it on again." }
    }
  }
  Timer {
    interval: 33
    repeat: true
    running: highlighterState.active
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
      visible: highlighterState.active && highlighterState.points.length > 0
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
        }
        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          var m = highlighterState.monitors.find(m => m.name === overlay.screen.name)
          if (!m) return
          var pts = highlighterState.points.filter(p => p.screen === m.name)
          ctx.strokeStyle = highlighterState.ink
          ctx.fillStyle = highlighterState.ink
          ctx.lineWidth = 18
          ctx.lineCap = "round"
          // Lighten compositing avoids darker blobs where strokes overlap.
          ctx.globalCompositeOperation = "lighten"
          for (var i = 0; i < pts.length; ++i) {
            var p = pts[i]
            ctx.globalAlpha = Math.max(0, 1 - (highlighterState.now - p.t) / 3000)
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
