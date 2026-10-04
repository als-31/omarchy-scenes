import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Scenes service: one instance per shell, shared by the overlay and every
// bar widget. It owns the scene list, the restore in flight, and the rolling
// session snapshot. All real work happens in bin/scenes; this side keeps the
// UI fed and talks to it.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  readonly property string pluginId: (manifest && manifest.id) || "saidness.scenes"
  readonly property string cli: String(Qt.resolvedUrl("bin/scenes")).replace(/^file:\/\//, "")
  readonly property string home: Quickshell.env("HOME")
  readonly property string glyph: "󰿎"

  property var scenes: []
  property var previous: null
  property var active: null
  property bool loaded: false

  // Live capture of the current desktop, shown while naming a new scene.
  property var current: null
  property bool capturing: false

  // Restore progress.
  property bool restoring: false
  property string restoreName: ""
  property string restoreSlug: ""
  property int restoreTotal: 0
  property int restoreIndex: 0
  property string restoreApp: ""
  property var lastResult: null

  readonly property string activeName: active && active.name ? String(active.name) : ""
  readonly property string activeSlug: active && active.slug ? String(active.slug) : ""

  signal listChanged()

  function refresh() {
    if (listProc.running) {
      listProc.pending = true
      return
    }
    listProc.running = true
  }

  function applyList(raw) {
    var data = null
    try { data = JSON.parse(String(raw || "{}")) } catch (e) { data = null }
    if (!data) return
    root.scenes = data.scenes && typeof data.scenes.length === "number" ? data.scenes : []
    root.previous = data.previous || null
    root.active = data.active || null
    root.loaded = true
    root.listChanged()
  }

  function capture() {
    if (captureProc.running) return
    root.capturing = true
    captureProc.running = true
  }

  // Run the CLI once; callback(exitCode, stdout, stderr).
  function run(args, callback) {
    var proc = runner.createObject(root, { command: [root.cli].concat(args), callback: callback || null })
    if (!proc) return false
    proc.running = true
    return true
  }

  function notify(title, body) {
    Quickshell.execDetached(["omarchy-notification-send", "-g", root.glyph, title, body || ""])
  }

  function firstLine(text) {
    var lines = String(text || "").trim().split("\n")
    return String(lines[lines.length - 1] || "").replace(/^scenes:\s*/, "")
  }

  function save(name, overwrite) {
    var clean = String(name || "").trim()
    if (!clean) return
    var args = ["save", clean]
    if (overwrite) args.push("--force")
    run(args, function(code, out, err) {
      if (code === 0) {
        var count = (String(out).match(/\((\d+) windows?\)/) || [])[1]
        root.notify("Scene saved", clean + (count ? " · " + count + " windows" : ""))
      } else {
        root.notify("Couldn't save scene", root.firstLine(err))
      }
      root.refresh()
    })
  }

  function remove(slug) {
    run(["delete", String(slug)], function(code, out, err) {
      if (code !== 0) root.notify("Couldn't delete scene", root.firstLine(err))
      root.refresh()
    })
  }

  function rename(slug, name) {
    var clean = String(name || "").trim()
    if (!clean) return
    run(["rename", String(slug), clean], function(code, out, err) {
      if (code !== 0) root.notify("Couldn't rename scene", root.firstLine(err))
      root.refresh()
    })
  }

  function restore(slug) {
    if (root.restoring) {
      root.notify("Scenes", "Still restoring " + root.restoreName + "…")
      return
    }
    var target = String(slug || "")
    if (!target) return
    var scene = target === "previous" ? root.previous : root.findScene(target)
    root.restoreSlug = target
    root.restoreName = scene && scene.name ? String(scene.name) : target
    root.restoreTotal = scene && scene.windows && typeof scene.windows.length === "number" ? scene.windows.length : 0
    root.restoreIndex = 0
    root.restoreApp = ""
    root.restoring = true
    restoreProc.command = [root.cli, "restore", target, "--jsonl", "--notify"]
    restoreProc.running = true
  }

  function findScene(slug) {
    for (var i = 0; i < root.scenes.length; i++) if (root.scenes[i].slug === slug) return root.scenes[i]
    return null
  }

  function handleRestoreEvent(line) {
    var event = null
    try { event = JSON.parse(String(line || "")) } catch (e) { return }
    if (!event || !event.event) return
    if (event.event === "start") {
      root.restoreName = String(event.name || root.restoreName)
      root.restoreTotal = Number(event.total) || 0
    } else if (event.event === "window") {
      root.restoreIndex = Number(event.index) || root.restoreIndex
      root.restoreApp = String(event.app || "")
    } else if (event.event === "done") {
      root.lastResult = event
    }
  }

  function autosave() {
    if (autosaveProc.running || root.restoring) return
    autosaveProc.running = true
  }

  Component {
    id: runner
    Process {
      id: proc
      property var callback: null
      stdout: StdioCollector { id: runOut; waitForEnd: true }
      stderr: StdioCollector { id: runErr; waitForEnd: true }
      onExited: function(exitCode) {
        var out = String(runOut.text || "")
        var err = String(runErr.text || "")
        var done = proc.callback
        Qt.callLater(function() {
          if (typeof done === "function") done(exitCode, out, err)
          proc.destroy()
        })
      }
    }
  }

  Process {
    id: listProc
    property bool pending: false
    command: [root.cli, "list", "--json"]
    stdout: StdioCollector { id: listOut; waitForEnd: true }
    onExited: {
      root.applyList(listOut.text)
      if (listProc.pending) {
        listProc.pending = false
        Qt.callLater(root.refresh)
      }
    }
  }

  Process {
    id: captureProc
    command: [root.cli, "capture"]
    stdout: StdioCollector { id: captureOut; waitForEnd: true }
    onExited: {
      var data = null
      try { data = JSON.parse(String(captureOut.text || "")) } catch (e) { data = null }
      root.current = data
      root.capturing = false
    }
  }

  Process {
    id: restoreProc
    stdout: SplitParser {
      onRead: function(line) { root.handleRestoreEvent(line) }
    }
    stderr: StdioCollector { id: restoreErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0 && !root.lastResult) root.notify("Couldn't restore scene", root.firstLine(restoreErr.text))
      root.restoring = false
      root.restoreApp = ""
      root.refresh()
      autosaveTimer.restart()
    }
    onRunningChanged: if (running) root.lastResult = null
  }

  Process {
    id: autosaveProc
    command: [root.cli, "autosave"]
    onExited: if (root.previous === null) root.refresh()
  }

  // Window churn settles before we snapshot it; a busy minute costs one save.
  Timer {
    id: autosaveTimer
    interval: 20000
    repeat: false
    onTriggered: root.autosave()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || !event.name || root.restoring) return
      var name = String(event.name)
      if (name === "openwindow" || name === "closewindow" || name === "movewindowv2" || name === "changefloatingmode")
        autosaveTimer.restart()
    }
  }

  // The first snapshot of a new login sets the previous one aside, so take it
  // early, before the new session's windows pile up.
  Timer {
    id: startupTimer
    interval: 4000
    repeat: false
    onTriggered: root.autosave()
  }

  Component.onCompleted: {
    root.refresh()
    startupTimer.start()
  }
}
