import QtQuick
import qs.Commons
import qs.Ui
import "SceneModel.js" as SceneModel
import "Glyphs.js" as Glyphs

// Bar button: the clapperboard opens the picker, while the active scene's
// name restores that scene. Restore progress replaces the name while a scene
// is coming back. Right-clicking either button saves the current layout.
BarWidget {
  id: root
  moduleName: "saidness.scenes"

  readonly property string pluginId: "saidness.scenes"
  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(root.pluginId) : null
  readonly property bool restoring: !!(service && service.restoring)
  readonly property bool showName: setting("showName", true) !== false
  readonly property string activeName: service ? service.activeName : ""

  readonly property string statusText: {
    if (root.restoring) {
      var total = root.service.restoreTotal
      return total > 0 ? root.service.restoreIndex + "/" + total : "…"
    }
    return SceneModel.ellipsize(root.activeName, 18)
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

  implicitWidth: iconButton.implicitWidth + (sceneButton.visible ? sceneButton.implicitWidth : 0)
  implicitHeight: Math.max(iconButton.implicitHeight, sceneButton.implicitHeight)

  Row {
    anchors.fill: parent
    spacing: 0

    WidgetButton {
      id: iconButton
      bar: root.bar
      text: Glyphs.scene
      tooltipText: "Manage Scenes"
      active: root.restoring

      onPressed: function(mouseButton) {
        if (mouseButton === Qt.RightButton)
          root.summon({ mode: "save" })
        else
          root.summon(null)
      }
    }

    WidgetButton {
      id: sceneButton
      visible: root.restoring || (root.showName && !!root.activeName && !root.vertical)
      bar: root.bar
      text: root.statusText
      tooltipText: root.restoring ? root.tooltip : "Restore " + root.activeName
      active: root.restoring

      onPressed: function(mouseButton) {
        if (mouseButton === Qt.RightButton)
          root.summon({ mode: "save" })
        else if (root.restoring)
          root.summon(null)
        else if (root.service && root.service.activeSlug)
          root.service.restore(root.service.activeSlug)
        else
          root.summon(null)
      }
    }
  }
}
