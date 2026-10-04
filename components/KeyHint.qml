import QtQuick
import qs.Commons

// A keycap followed by what it does, for the overlay's footer.
Row {
  id: root

  property string keys: ""
  property string label: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.menuFamily

  spacing: Style.space(6)

  Rectangle {
    anchors.verticalCenter: parent.verticalCenter
    width: Math.max(height, keyText.implicitWidth + Style.space(10))
    height: keyText.implicitHeight + Style.space(4)
    radius: Math.min(Style.cornerRadius, Style.space(4))
    color: Util.alpha(root.foreground, 0.07)
    border.width: Style.normalBorderWidth > 0 ? 1 : 0
    border.color: Util.alpha(root.foreground, 0.22)

    Text {
      id: keyText
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: root.keys
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Text {
    textFormat: Text.PlainText
    anchors.verticalCenter: parent.verticalCenter
    text: root.label
    color: root.foreground
    opacity: 0.62
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }
}
