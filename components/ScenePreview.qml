import QtQuick
import qs.Commons
import "../SceneModel.js" as SceneModel

// Miniature of a scene: one screen-shaped tile per workspace, each window
// drawn where it sat, with its app icon. Colors come from the active theme.
Item {
  id: root

  property var scene: null
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.menuFamily
  property real tileHeight: Style.space(92)
  property real spacing: Style.space(14)
  readonly property int tileRadius: Math.min(Style.cornerRadius, Style.space(8))
  readonly property var groups: SceneModel.workspaces(root.scene)
  readonly property bool multiMonitor: SceneModel.monitorCount(root.scene) > 1

  implicitHeight: flow.implicitHeight

  Flow {
    id: flow
    width: root.width
    spacing: root.spacing

    Repeater {
      model: root.groups

      delegate: Column {
        id: tile

        required property var modelData
        readonly property real aspect: modelData.width / modelData.height
        readonly property real screenWidth: Math.min(root.width, root.tileHeight * aspect)
        readonly property real screenHeight: screenWidth / aspect

        spacing: Style.space(5)

        Row {
          spacing: Style.space(5)

          Text {
            textFormat: Text.PlainText
            text: tile.modelData.label
            color: tile.modelData.focused ? root.accent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Text {
            textFormat: Text.PlainText
            visible: root.multiMonitor && tile.modelData.monitor !== ""
            text: tile.modelData.monitor
            color: root.foreground
            opacity: 0.45
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Rectangle {
          id: screen
          width: tile.screenWidth
          height: tile.screenHeight
          radius: root.tileRadius
          color: Util.alpha(root.foreground, 0.035)
          border.width: 1
          border.color: Util.alpha(tile.modelData.focused ? root.accent : root.foreground, tile.modelData.focused ? 0.6 : 0.16)
          clip: true

          Repeater {
            model: tile.modelData.windows

            delegate: Rectangle {
              id: win

              required property var modelData
              readonly property real sx: screen.width / tile.modelData.width
              readonly property real sy: screen.height / tile.modelData.height
              readonly property real rawX: (modelData.at ? modelData.at[0] : 0) * sx
              readonly property real rawY: (modelData.at ? modelData.at[1] : 0) * sy
              readonly property real rawW: (modelData.size ? modelData.size[0] : tile.modelData.width) * sx
              readonly property real rawH: (modelData.size ? modelData.size[1] : tile.modelData.height) * sy

              x: Math.max(1, Math.min(rawX, screen.width - 4)) + 1
              y: Math.max(1, Math.min(rawY, screen.height - 4)) + 1
              width: Math.max(3, Math.min(rawW, screen.width - x - 1) - 2)
              height: Math.max(3, Math.min(rawH, screen.height - y - 1) - 2)
              z: modelData.fullscreen ? 3 : (modelData.floating ? 2 : 1)
              radius: Math.max(1, root.tileRadius / 2)
              color: Util.alpha(root.accent, modelData.floating ? 0.26 : 0.13)
              border.width: 1
              border.color: Util.alpha(root.accent, modelData.floating ? 0.85 : 0.5)

              AppIcon {
                anchors.centerIn: parent
                visible: win.width >= 12 && win.height >= 12
                size: Math.max(8, Math.min(22, Math.min(win.width, win.height) * 0.5))
                icon: win.modelData.icon || ""
                kind: win.modelData.kind || "app"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }
            }
          }
        }
      }
    }
  }
}
