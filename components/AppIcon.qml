import QtQuick
import Quickshell
import qs.Commons
import "../Glyphs.js" as Glyphs

// An app's themed icon, falling back to a glyph for its kind when the icon
// theme has nothing (or the window came from a plain command).
Item {
  id: root

  property string icon: ""
  property string kind: "app"
  property real size: Style.font.icon
  property color foreground: Color.foreground
  property string fontFamily: Style.font.menuFamily

  readonly property string source: {
    var value = String(root.icon || "")
    if (!value) return ""
    if (value.charAt(0) === "/") return "file://" + value
    return Quickshell.iconPath(value, true) || ""
  }

  width: size
  height: size
  implicitWidth: size
  implicitHeight: size

  Image {
    id: image
    anchors.fill: parent
    source: root.source
    sourceSize: Qt.size(Math.ceil(root.size * 2), Math.ceil(root.size * 2))
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    smooth: true
    mipmap: true
    visible: status === Image.Ready
  }

  Text {
    anchors.centerIn: parent
    visible: image.status !== Image.Ready
    text: Glyphs.forKind(root.kind)
    color: root.foreground
    opacity: 0.75
    font.family: root.fontFamily
    font.pixelSize: Math.max(6, Math.round(root.size * 0.86))
    renderType: Text.NativeRendering
  }
}
