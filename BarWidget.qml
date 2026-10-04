import QtQuick
import qs.Commons
import qs.Ui
import "SceneModel.js" as SceneModel
import "Glyphs.js" as Glyphs

// Bar button: the clapperboard plus the active scene's name, or restore
// progress while a scene is coming back.
//   left click   open the Scenes picker
//   right click  save the current layout
BarWidget {
  id: root
  moduleName: "saidness.scenes"

  readonly property string pluginId: "saidness.scenes"
  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(root.pluginId) : null
  readonly property bool restoring: !!(service && service.restoring)
  readonly property bool showName: setting("showName", true) !== false
  readonly property string activeName: service ? service.activeName : ""

  readonly property string label: {
    if (root.restoring) {
      var total = root.service.restoreTotal
      return Glyphs.scene + "  " + (total > 0 ? root.service.restoreIndex + "/" + total : "…")
    }
    if (root.showName && root.activeName && !root.vertical) return Glyphs.scene + "  " + SceneModel.ellipsize(root.activeName, 18)
    return Glyphs.scene
  }

  readonly property string tooltip: {
    if (root.restoring) {
      var app = root.service.restoreApp
      return "Restoring " + root.service.restoreName + (app ? " · " + app : "")
    }
    return root.activeName ? "Scene: " + root.activeName : "Scenes"
  }

  function summon(payload) {
    var json = JSON.stringify(payload || {})
    if (root.bar && root.bar.shell && typeof root.bar.shell.toggle === "function" && !payload)
      root.bar.shell.toggle(root.pluginId, json)
    else if (root.bar && root.bar.shell && typeof root.bar.shell.summon === "function")
      root.bar.shell.summon(root.pluginId, json)
    else if (root.bar)
      root.bar.run("omarchy-shell shell toggle " + root.pluginId + " '" + json + "'")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.label
    tooltipText: root.tooltip
    active: root.restoring
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) root.summon({ mode: "save" })
      else root.summon(null)
    }
  }
}
