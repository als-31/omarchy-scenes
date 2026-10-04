import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "SceneModel.js" as SceneModel
import "Glyphs.js" as Glyphs
import "components"

// The Scenes picker. Keyboard first: type to filter, Enter restores, and a
// handful of chords manage scenes. Every color and size comes from the
// shell's theme tokens (the [menu] surface), so it looks native everywhere.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  property var service: null

  property bool opened: false
  // "list" browses scenes; "save" and "rename" turn the header into a name field.
  property string mode: "list"
  property string filterText: ""
  property string inputText: ""
  property string renameSlug: ""
  property int selectedIndex: 0
  property bool cursorActive: true
  property var rows: []
  property real now: Date.now()

  // Pending confirmation: "delete", "overwrite" or "replace".
  property string confirmKind: ""
  property string confirmSlug: ""
  property string confirmName: ""

  readonly property string home: Quickshell.env("HOME")
  readonly property var scenes: service ? service.scenes : []
  readonly property var selectedRow: rows.length > 0 && selectedIndex >= 0 && selectedIndex < rows.length ? rows[selectedIndex] : null
  readonly property var previewScene: {
    if (root.mode === "save") return root.service ? root.service.current : null
    var row = root.selectedRow
    if (!row || !root.service) return null
    if (row.kind === "save") return root.service.current
    if (row.kind === "previous") return root.service.previous
    return root.sceneFor(row.slug)
  }
  readonly property string suggestion: root.service
    ? SceneModel.suggestName(root.service.current, root.scenes, root.home) : "Scene"

  // Theme: the clipboard, emoji picker and menu all share the [menu] surface.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color accent: Color.accent
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(38), Style.font.heading + Style.spacing.controlPaddingY * 2)
  property int footerHeight: Style.font.caption + Style.space(14)
  property int rowHeight: Math.max(Style.space(54), Style.font.title + Style.font.caption + Style.space(24))
  property int cardWidth: Math.min(Style.space(980), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(620), panel.height - Style.gapsOut * 2)
  readonly property color divider: Util.alpha(root.border, 0.22)

  // ------------------------------------------------------------ lifecycle

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }

    root.opened = true
    root.now = Date.now()
    root.filterText = ""
    root.inputText = ""
    root.confirmKind = ""
    root.mode = "list"
    root.selectedIndex = 0
    root.cursorActive = true
    pointerGate.reset()
    if (root.service) {
      root.service.refresh()
      root.service.capture()
    }
    root.rebuildRows()
    if (payload.mode === "save") root.startSave()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    root.confirmKind = ""
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide((root.manifest && root.manifest.id) || "saidness.scenes")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  // `omarchy-shell shell call saidness.scenes refresh` (the CLI pings this
  // after it changes anything) keeps the bar and picker in step.
  function refresh(arg) {
    if (root.service) root.service.refresh()
    return "ok"
  }

  Connections {
    target: root.service
    function onListChanged() { if (root.opened) root.rebuildRows() }
  }

  // ----------------------------------------------------------------- rows

  function sceneFor(slug) {
    for (var i = 0; i < root.scenes.length; i++) if (root.scenes[i].slug === slug) return root.scenes[i]
    return null
  }

  // Scenes and the previous session, most recent first, then the save action.
  function rebuildRows() {
    var keep = root.selectedRow ? root.selectedRow.kind + ":" + root.selectedRow.slug : ""
    var entries = []
    for (var i = 0; i < root.scenes.length; i++) {
      var scene = root.scenes[i]
      if (SceneModel.matches(scene, root.filterText))
        entries.push({ kind: "scene", slug: scene.slug, name: scene.name || scene.slug, time: SceneModel.parseTime(scene.updatedAt) })
    }
    var previous = root.service ? root.service.previous : null
    if (previous && SceneModel.matches(previous, root.filterText))
      entries.push({ kind: "previous", slug: "previous", name: "Previous session", time: SceneModel.parseTime(previous.updatedAt) })
    entries.sort(function(a, b) { return b.time - a.time })
    if (!root.filterText) entries.push({ kind: "save", slug: "", name: "Save current layout", time: 0 })

    root.rows = entries
    var index = -1
    for (var j = 0; j < entries.length && keep; j++)
      if (entries[j].kind + ":" + entries[j].slug === keep) index = j
    root.selectedIndex = index >= 0 ? index : Math.min(Math.max(0, root.selectedIndex), Math.max(0, entries.length - 1))
    Qt.callLater(function() {
      if (root.rows.length > 0) list.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function select(delta) {
    if (root.rows.length === 0) return
    pointerGate.reset()
    root.cursorActive = true
    root.selectedIndex = (root.selectedIndex + delta + root.rows.length) % root.rows.length
    list.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function selectAbsolute(index) {
    if (root.rows.length === 0) return
    pointerGate.reset()
    root.cursorActive = true
    root.selectedIndex = Math.max(0, Math.min(index, root.rows.length - 1))
    list.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function setFilter(text) {
    root.filterText = text
    root.selectedIndex = 0
    root.rebuildRows()
  }

  // -------------------------------------------------------------- actions

  function activate(index) {
    var row = index >= 0 && index < root.rows.length ? root.rows[index] : null
    if (!row || !root.service) return
    if (row.kind === "save") {
      root.startSave()
      return
    }
    root.service.restore(row.slug)
    root.dismiss()
  }

  function startSave() {
    root.mode = "save"
    root.inputText = ""
    if (root.service && !root.service.current) root.service.capture()
  }

  function startRename() {
    var row = root.selectedRow
    if (!row || row.kind !== "scene") return
    root.mode = "rename"
    root.renameSlug = row.slug
    root.inputText = row.name
  }

  function cancelInput() {
    root.mode = "list"
    root.inputText = ""
  }

  function submitInput() {
    if (!root.service) return
    if (root.mode === "save") {
      var name = root.inputText.trim() || root.suggestion
      if (SceneModel.nameTaken(root.scenes, name)) {
        root.ask("replace", "", name)
        return
      }
      root.service.save(name, false)
      root.dismiss()
    } else if (root.mode === "rename") {
      var renamed = root.inputText.trim()
      if (renamed && renamed !== (root.sceneFor(root.renameSlug) || {}).name) root.service.rename(root.renameSlug, renamed)
      root.cancelInput()
    }
  }

  function ask(kind, slug, name) {
    root.confirmKind = kind
    root.confirmSlug = slug
    root.confirmName = name
    confirm.selectedIndex = 1
  }

  function requestDelete() {
    var row = root.selectedRow
    if (row && row.kind === "scene") root.ask("delete", row.slug, row.name)
  }

  function requestOverwrite() {
    var row = root.selectedRow
    if (row && row.kind === "scene") root.ask("overwrite", row.slug, row.name)
  }

  function confirmed() {
    var kind = root.confirmKind
    root.confirmKind = ""
    if (!root.service) return
    if (kind === "delete") {
      root.service.remove(root.confirmSlug)
    } else if (kind === "overwrite") {
      root.service.save(root.confirmName, true)
    } else if (kind === "replace") {
      root.service.save(root.confirmName, true)
      root.dismiss()
      return
    }
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function canceled() {
    root.confirmKind = ""
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  readonly property string confirmMessage: {
    if (root.confirmKind === "delete") return "Delete the scene “" + root.confirmName + "”?"
    if (root.confirmKind === "overwrite") return "Replace “" + root.confirmName + "” with the windows open right now?"
    if (root.confirmKind === "replace") return "A scene called “" + root.confirmName + "” already exists. Replace it?"
    return ""
  }

  readonly property string confirmLabel: root.confirmKind === "delete" ? "Delete" : "Replace"

  // ------------------------------------------------------------- keyboard

  function isTyping(event) {
    return event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127
      && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
  }

  function handleKey(event) {
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0

    if (root.mode !== "list") {
      if (event.key === Qt.Key_Escape) root.cancelInput()
      else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.submitInput()
      else if (Util.editsFilter(event, root.inputText)) root.inputText = Util.editedFilter(event, root.inputText)
      else if (event.key === Qt.Key_Tab && root.mode === "save" && !root.inputText) root.inputText = root.suggestion
      else if (root.isTyping(event)) root.inputText += event.text
      else return false
      return true
    }

    if (event.key === Qt.Key_Escape) {
      if (root.filterText) root.setFilter("")
      else root.dismiss()
    } else if (ctrl && event.key === Qt.Key_S) {
      root.startSave()
    } else if ((ctrl && event.key === Qt.Key_R) || event.key === Qt.Key_F2) {
      root.startRename()
    } else if (ctrl && event.key === Qt.Key_O) {
      root.requestOverwrite()
    } else if (event.key === Qt.Key_Delete) {
      root.requestDelete()
    } else if (Util.editsFilter(event, root.filterText)) {
      root.setFilter(Util.editedFilter(event, root.filterText))
    } else if (event.key === Qt.Key_Up || (ctrl && event.key === Qt.Key_P) || (ctrl && event.key === Qt.Key_K)) {
      root.select(-1)
    } else if (event.key === Qt.Key_Down || (ctrl && event.key === Qt.Key_N) || (ctrl && event.key === Qt.Key_J)) {
      root.select(1)
    } else if (event.key === Qt.Key_PageUp) {
      root.select(-5)
    } else if (event.key === Qt.Key_PageDown) {
      root.select(5)
    } else if (event.key === Qt.Key_Home) {
      root.selectAbsolute(0)
    } else if (event.key === Qt.Key_End) {
      root.selectAbsolute(root.rows.length - 1)
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.activate(root.selectedIndex)
    } else if (root.isTyping(event)) {
      root.setFilter(root.filterText + event.text)
    } else {
      return false
    }
    return true
  }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  // Relative times ("5 min ago") stay honest while the picker is open.
  Timer {
    interval: 30000
    repeat: true
    running: root.opened
    onTriggered: root.now = Date.now()
  }

  // ------------------------------------------------------------------ view

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-scenes"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: keyCatcher.forceActiveFocus() }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        z: root.confirmKind ? 20 : 0

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.confirmKind) {
            if (confirm.handleKey(event)) event.accepted = true
            return
          }
          if (root.handleKey(event)) event.accepted = true
        }

        ConfirmDialog {
          id: confirm
          anchors.fill: parent
          opened: root.confirmKind !== ""
          z: 10
          message: root.confirmMessage
          confirmText: root.confirmLabel
          background: root.background
          foreground: root.foreground
          scrim: root.scrim
          selectedBackground: root.selectedBackground
          selectedText: root.selectedText
          fontFamily: root.fontFamily
          cornerRadius: root.cornerRadius
          onCanceled: root.canceled()
          onConfirmed: root.confirmed()
        }
      }

      Item {
        id: content
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        // --------------------------------------------------------- header
        Item {
          id: header
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: root.headerHeight

          Text {
            id: headerGlyph
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.mode === "save" ? Glyphs.save : (root.mode === "rename" ? Glyphs.rename : Glyphs.scene)
            color: root.selectedText
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
          }

          Rectangle {
            id: modeChip
            visible: root.mode !== "list"
            anchors.left: headerGlyph.right
            anchors.leftMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            width: visible ? modeLabel.implicitWidth + Style.space(14) : 0
            height: modeLabel.implicitHeight + Style.space(6)
            radius: Math.min(root.cornerRadius, Style.space(4))
            color: Util.alpha(root.accent, 0.16)

            Text {
              id: modeLabel
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: root.mode === "save" ? "Save as" : "Rename"
              color: root.selectedText
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          Text {
            id: headerText
            textFormat: Text.PlainText
            anchors.left: modeChip.visible ? modeChip.right : headerGlyph.right
            anchors.leftMargin: Style.space(10)
            anchors.right: headerStatus.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            readonly property string value: root.mode === "list" ? root.filterText : root.inputText
            readonly property string placeholder: root.mode === "list" ? "Search scenes…"
              : (root.mode === "save" ? root.suggestion : "New name")
            text: value || placeholder
            color: root.foreground
            opacity: value ? 1 : 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight

            // A caret makes the name fields read as fields.
            Rectangle {
              visible: root.mode !== "list" && root.opened
              x: headerText.value ? Math.min(headerText.contentWidth, headerText.width) + 2 : 0
              anchors.verticalCenter: parent.verticalCenter
              width: Math.max(1, Style.space(2))
              height: Style.font.heading + Style.space(2)
              color: root.selectedText

              SequentialAnimation on opacity {
                running: root.mode !== "list" && root.opened
                loops: Animation.Infinite
                NumberAnimation { to: 0; duration: 530; easing.type: Easing.InOutQuad }
                NumberAnimation { to: 1; duration: 530; easing.type: Easing.InOutQuad }
              }
            }
          }

          Text {
            id: headerStatus
            textFormat: Text.PlainText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: {
              var s = root.service
              if (s && s.restoring) return Glyphs.sync + "  Restoring " + s.restoreName + "  " + s.restoreIndex + "/" + s.restoreTotal
              if (root.mode === "save") return root.service && root.service.current ? SceneModel.summary(root.service.current) : "Looking at your desktop…"
              if (root.mode === "rename") return "Enter to rename"
              var count = root.scenes.length
              return count === 0 ? "No scenes yet" : SceneModel.plural(count, "scene")
            }
            color: root.service && root.service.restoring ? root.selectedText : root.foreground
            opacity: root.service && root.service.restoring ? 1 : 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
        }

        Rectangle {
          id: headerRule
          anchors.top: header.bottom
          anchors.topMargin: Style.space(10)
          anchors.left: parent.left
          anchors.right: parent.right
          height: 1
          color: root.divider
        }

        // ----------------------------------------------------------- body
        Item {
          id: body
          anchors.top: headerRule.bottom
          anchors.topMargin: Style.space(12)
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: footerRule.top
          anchors.bottomMargin: Style.space(12)

          // Scene list.
          Item {
            id: listPane
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: Math.round(parent.width * 0.4)
            opacity: root.mode === "rename" ? 0.35 : 1

            Behavior on opacity { NumberAnimation { duration: 140 } }

            ListView {
              id: list
              anchors.fill: parent
              anchors.rightMargin: root.contentMargin
              model: root.rows
              clip: true
              spacing: Style.space(4)
              boundsBehavior: Flickable.StopAtBounds
              interactive: root.mode === "list"
              visible: root.mode !== "save"

              delegate: Rectangle {
                id: row

                required property int index
                required property var modelData
                readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex
                readonly property var scene: modelData.kind === "scene" ? root.sceneFor(modelData.slug)
                  : (modelData.kind === "previous" ? (root.service ? root.service.previous : null) : (root.service ? root.service.current : null))
                readonly property bool isActive: modelData.kind === "scene" && root.service && root.service.activeSlug === modelData.slug
                readonly property color ink: hasCursor ? root.selectedText : root.foreground

                width: ListView.view.width
                height: root.rowHeight
                radius: root.cornerRadius
                color: hasCursor ? root.selectedBackground : "transparent"

                Text {
                  id: rowGlyph
                  textFormat: Text.PlainText
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(18)
                  horizontalAlignment: Text.AlignHCenter
                  text: row.modelData.kind === "save" ? Glyphs.save : (row.modelData.kind === "previous" ? Glyphs.history : Glyphs.scene)
                  color: row.modelData.kind === "save" || row.isActive ? root.selectedText : row.ink
                  opacity: row.hasCursor || row.modelData.kind === "save" || row.isActive ? 1 : 0.55
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.icon
                }

                Column {
                  anchors.left: rowGlyph.right
                  anchors.leftMargin: Style.space(12)
                  anchors.right: appStack.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(3)

                  Row {
                    width: parent.width
                    spacing: Style.space(8)

                    Text {
                      id: rowName
                      textFormat: Text.PlainText
                      width: Math.min(implicitWidth, parent.width - (activeTag.visible ? activeTag.width + parent.spacing : 0))
                      text: row.modelData.name
                      color: row.ink
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.title
                      elide: Text.ElideRight
                    }

                    Rectangle {
                      id: activeTag
                      visible: row.isActive
                      anchors.verticalCenter: rowName.verticalCenter
                      width: activeLabel.implicitWidth + Style.space(10)
                      height: activeLabel.implicitHeight + Style.space(2)
                      radius: height / 2
                      color: Util.alpha(root.accent, 0.18)

                      Text {
                        id: activeLabel
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: "active"
                        color: root.selectedText
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }
                  }

                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: {
                      var kind = row.modelData.kind
                      if (kind === "save") {
                        if (!row.scene) return "Snapshot every window you have open"
                        return SceneModel.summary(row.scene) + " open now"
                      }
                      var when = row.scene ? SceneModel.relativeTime(row.scene.updatedAt, root.now) : ""
                      var text = row.scene ? SceneModel.summary(row.scene) : ""
                      if (kind === "previous") return "From your last login" + (when ? " · " + when : "")
                      return text + (when ? " · " + when : "")
                    }
                    color: root.foreground
                    opacity: 0.55
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                Row {
                  id: appStack
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(4)
                  visible: row.modelData.kind !== "save"
                  opacity: row.hasCursor ? 1 : 0.7

                  Repeater {
                    model: row.modelData.kind !== "save" && row.scene ? SceneModel.apps(row.scene, 4) : []
                    delegate: AppIcon {
                      required property var modelData
                      size: Style.font.icon
                      icon: modelData.icon
                      kind: modelData.kind
                      foreground: row.ink
                      fontFamily: root.fontFamily
                    }
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  enabled: root.mode === "list"
                  onPositionChanged: function(mouse) {
                    if (!pointerGate.moved(row, mouse)) return
                    root.cursorActive = true
                    root.selectedIndex = row.index
                  }
                  onClicked: {
                    root.selectedIndex = row.index
                    root.activate(row.index)
                  }
                }
              }
            }

            // What a scene remembers: shown while naming one, and to anyone
            // who has not saved a scene yet.
            Column {
              id: explainer
              readonly property bool firstRun: root.mode === "list" && !root.filterText && root.rows.length === 1
                && root.rows[0].kind === "save"
              visible: root.mode === "save" || firstRun
              y: root.mode === "save" ? Style.space(6) : root.rowHeight + Style.space(26)
              x: Style.space(12)
              width: listPane.width - root.contentMargin - Style.space(24)
              spacing: Style.space(14)

              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: "A scene remembers"
                color: root.selectedText
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
              }

              Repeater {
                model: [
                  [Glyphs.app, "Every window, on its workspace and monitor, tiled or floating where it was"],
                  [Glyphs.terminal, "Terminals reopen in their folder and rerun nvim, lazygit, claude and friends"],
                  [Glyphs.web, "Web apps and PWAs come back at their address"],
                  [Glyphs.restore, "Windows that are already open get moved into place, never duplicated"]
                ]

                delegate: Row {
                  required property var modelData
                  width: explainer.width
                  spacing: Style.space(12)

                  Text {
                    id: bulletGlyph
                    textFormat: Text.PlainText
                    width: Style.space(18)
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData[0]
                    color: root.selectedText
                    opacity: 0.85
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.icon
                  }

                  Text {
                    textFormat: Text.PlainText
                    width: parent.width - bulletGlyph.width - parent.spacing
                    text: modelData[1]
                    color: root.foreground
                    opacity: 0.72
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    wrapMode: Text.Wrap
                    lineHeight: 1.15
                  }
                }
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                topPadding: Style.space(4)
                text: root.mode === "save"
                  ? "Press Enter to save. Bring it back any time from this picker."
                  : "Your desktop before each login is kept too, as “Previous session”."
                color: root.foreground
                opacity: 0.45
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.Wrap
              }
            }

            Column {
              anchors.centerIn: parent
              anchors.horizontalCenterOffset: -root.contentMargin / 2
              spacing: Style.space(8)
              visible: root.rows.length === 0

              Text {
                textFormat: Text.PlainText
                width: listPane.width - root.contentMargin
                horizontalAlignment: Text.AlignHCenter
                text: Glyphs.search
                color: root.selectedText
                opacity: 0.8
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }

              Text {
                textFormat: Text.PlainText
                width: listPane.width - root.contentMargin
                horizontalAlignment: Text.AlignHCenter
                text: "No scenes match “" + root.filterText + "”"
                color: root.foreground
                opacity: 0.7
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.Wrap
              }
            }
          }

          Rectangle {
            id: paneDivider
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: listPane.right
            width: 1
            color: root.divider
          }

          // Preview of the selected scene.
          Flickable {
            id: previewPane
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: paneDivider.right
            anchors.leftMargin: root.contentMargin
            anchors.right: parent.right
            contentWidth: width
            contentHeight: previewColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            readonly property var scene: root.previewScene
            readonly property string kind: root.mode === "save" ? "save" : (root.selectedRow ? root.selectedRow.kind : "")

            Column {
              id: previewColumn
              width: previewPane.width
              spacing: Style.space(14)

              Column {
                width: parent.width
                spacing: Style.space(4)

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: {
                    if (previewPane.kind === "save") return root.mode === "save" ? (root.inputText.trim() || root.suggestion) : "Current desktop"
                    if (root.mode === "rename") return root.inputText.trim() || "New name"
                    return root.selectedRow ? root.selectedRow.name : ""
                  }
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  font.bold: true
                  elide: Text.ElideRight
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: {
                    var scene = previewPane.scene
                    if (!scene) return previewPane.kind === "save" ? "Looking at your desktop…" : ""
                    var parts = [SceneModel.summary(scene)]
                    if (previewPane.kind === "save") parts.push("as it is right now")
                    else if (previewPane.kind === "previous") parts.push("saved " + SceneModel.relativeTime(scene.updatedAt, root.now) + ", before you last logged in")
                    else parts.push("saved " + SceneModel.relativeTime(scene.updatedAt, root.now))
                    return parts.join(" · ")
                  }
                  color: root.foreground
                  opacity: 0.55
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }
              }

              ScenePreview {
                width: parent.width
                visible: !!previewPane.scene
                scene: previewPane.scene
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                tileHeight: Style.space(SceneModel.workspaceCount(previewPane.scene) > 6 ? 72 : 92)
              }

              Rectangle {
                width: parent.width
                height: 1
                color: root.divider
                visible: !!previewPane.scene
              }

              Column {
                width: parent.width
                spacing: Style.space(2)
                visible: !!previewPane.scene

                Repeater {
                  model: previewPane.scene ? previewPane.scene.windows : []

                  delegate: Item {
                    id: winRow
                    required property var modelData
                    width: previewColumn.width
                    height: Math.max(Style.space(26), Style.font.body + Style.space(12))

                    AppIcon {
                      id: winIcon
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      size: Style.font.icon
                      icon: winRow.modelData.icon || ""
                      kind: winRow.modelData.kind || "app"
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                    }

                    Text {
                      id: winApp
                      textFormat: Text.PlainText
                      anchors.left: winIcon.right
                      anchors.leftMargin: Style.space(10)
                      anchors.verticalCenter: parent.verticalCenter
                      width: Math.min(implicitWidth, parent.width * 0.4)
                      text: winRow.modelData.app || winRow.modelData.class
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                    }

                    Text {
                      textFormat: Text.PlainText
                      anchors.left: winApp.right
                      anchors.leftMargin: Style.space(10)
                      anchors.right: winWorkspace.left
                      anchors.rightMargin: Style.space(10)
                      anchors.verticalCenter: parent.verticalCenter
                      text: SceneModel.windowDetail(winRow.modelData, root.home)
                      color: winRow.modelData.kind === "unknown" ? Color.urgent : root.foreground
                      opacity: 0.5
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideMiddle
                    }

                    Rectangle {
                      id: winWorkspace
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      width: Math.max(height, wsLabel.implicitWidth + Style.space(10))
                      height: wsLabel.implicitHeight + Style.space(4)
                      radius: Math.min(root.cornerRadius, Style.space(4))
                      color: Util.alpha(root.foreground, 0.06)

                      Text {
                        id: wsLabel
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: SceneModel.workspaceLabel(winRow.modelData.workspace ? winRow.modelData.workspace.name : "")
                          + (winRow.modelData.floating ? " ·  float" : "")
                        color: root.foreground
                        opacity: 0.7
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }
                  }
                }
              }
            }
          }
        }

        // --------------------------------------------------------- footer
        Rectangle {
          id: footerRule
          anchors.bottom: footer.top
          anchors.bottomMargin: Style.space(10)
          anchors.left: parent.left
          anchors.right: parent.right
          height: 1
          color: root.divider
        }

        Row {
          id: footer
          anchors.bottom: parent.bottom
          anchors.left: parent.left
          height: root.footerHeight
          spacing: Style.space(18)

          readonly property var hints: {
            if (root.mode === "save") return [["Enter", "Save"], ["Tab", "Use suggestion"], ["Esc", "Cancel"]]
            if (root.mode === "rename") return [["Enter", "Rename"], ["Esc", "Cancel"]]
            var kind = root.selectedRow ? root.selectedRow.kind : ""
            var out = []
            if (kind === "save") out.push(["Enter", "Save current layout"])
            else if (kind) out.push(["Enter", "Restore"])
            if (kind !== "save") out.push(["Ctrl S", "Save current"])
            if (kind === "scene") out = out.concat([["Ctrl R", "Rename"], ["Ctrl O", "Update"], ["Del", "Delete"]])
            out.push(["Esc", root.filterText ? "Clear" : "Close"])
            return out
          }

          Repeater {
            model: footer.hints
            delegate: KeyHint {
              required property var modelData
              anchors.verticalCenter: parent.verticalCenter
              keys: modelData[0]
              label: modelData[1]
              foreground: root.foreground
              fontFamily: root.fontFamily
            }
          }
        }
      }
    }
  }
}
