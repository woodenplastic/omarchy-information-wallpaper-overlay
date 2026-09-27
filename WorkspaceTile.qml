import QtQuick
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import "Model.js" as Model

// One workspace, live: its monitor's shape without the bar's strip, and
// each window at its place and size as a live capture, tiled ones under
// floating ones under fullscreen ones. Captures run only while the tile can
// be seen; Hyprland draws windows on hidden workspaces at
// misc:render_unfocused_fps, so that's their frame rate here.
Tile {
  id: root

  readonly property var feed: widget ? widget.workspaceFeed : null
  readonly property string target: String(entry.workspace || "")
  readonly property bool live: root.visible && !!widget && widget.desktopShown !== false && widget.live !== false

  // The workspace as Hyprland knows it, for its monitor and name.
  readonly property var workspace: {
    var list = Hyprland.workspaces ? Hyprland.workspaces.values : []
    for (var i = 0; i < list.length; i++) {
      if (String(list[i].id) === target || list[i].name === target) return list[i]
    }
    return null
  }

  readonly property var clients: {
    var list = feed ? feed.clients : []
    return list.filter(function(c) { return String(c.ws) === root.target || c.wsName === root.target })
  }

  readonly property var monitor: {
    var list = feed ? feed.monitors : []
    var name = workspace && workspace.monitor ? workspace.monitor.name : ""
    var id = clients.length > 0 ? clients[0].monitor : -1
    for (var i = 0; i < list.length; i++) if (list[i].name === name || list[i].id === id) return list[i]
    return list.length > 0 ? list[0] : null
  }

  // The monitor's usable area in logical pixels: window positions are
  // logical, monitor sizes physical, and the bar's reserved strip is left out.
  readonly property var usable: {
    if (!monitor) return null
    var rotated = monitor.transform % 2 === 1
    var scale = monitor.scale || 1
    var reserved = Array.isArray(monitor.reserved) ? monitor.reserved : [0, 0, 0, 0]
    return {
      left: monitor.x + (reserved[0] || 0),
      top: monitor.y + (reserved[1] || 0),
      width: Math.max(1, (rotated ? monitor.height : monitor.width) / scale - (reserved[0] || 0) - (reserved[2] || 0)),
      height: Math.max(1, (rotated ? monitor.width : monitor.height) / scale - (reserved[1] || 0) - (reserved[3] || 0))
    }
  }

  readonly property real factor: usable ? Math.min(stage.width / usable.width, stage.height / usable.height) : 1

  readonly property var windows: {
    if (!usable) return []
    var toplevels = {}
    var values = Hyprland.toplevels ? Hyprland.toplevels.values : []
    for (var t = 0; t < values.length; t++) toplevels[String(values[t].address).replace(/^0x/, "")] = values[t]
    function layer(c) { return c.fullscreen ? 2 : (c.floating ? 1 : 0) }
    var list = clients.slice().sort(function(a, b) { return layer(a) - layer(b) || b.focusHistoryID - a.focusHistoryID })
    var out = []
    for (var i = 0; i < list.length; i++) {
      var c = list[i]
      if (!c.at || !c.size) continue
      var x = Math.max(0, (c.at[0] - usable.left) * factor)
      var y = Math.max(0, (c.at[1] - usable.top) * factor)
      out.push({
        address: c.a,
        toplevel: toplevels[c.a] || null,
        label: c.cls || c.title || "",
        x: Math.round(x),
        y: Math.round(y),
        width: Math.max(1, Math.min(Math.round(c.size[0] * factor), Math.round(usable.width * factor - x))),
        height: Math.max(1, Math.min(Math.round(c.size[1] * factor), Math.round(usable.height * factor - y)))
      })
    }
    return out
  }

  glowY: pad + header.height + stage.height / 2

  component Label: Text {
    textFormat: Text.PlainText
    color: root.fg
    font.family: root.family
    font.pixelSize: root.bodySize
    elide: Text.ElideRight
    maximumLineCount: 1
  }

  Row {
    id: header
    spacing: root.statSize * 0.5

    Label {
      anchors.baseline: nameLabel.baseline
      text: ""
      color: Color.accent
      font.pixelSize: root.statSize
    }
    Label {
      id: nameLabel
      text: "Workspace " + (root.target.indexOf("special:") === 0 ? root.target.substring(8) : root.target)
      font.pixelSize: root.statSize
      font.bold: true
    }
    Label {
      anchors.baseline: nameLabel.baseline
      text: root.clients.length === 1 ? "1 window" : root.clients.length + " windows"
      color: root.dim
      font.pixelSize: root.smallSize
    }
  }

  // The monitor in miniature, at the top and centered across.
  Item {
    id: stageArea
    anchors.top: header.bottom
    anchors.topMargin: root.statSize * 0.6
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom

    Rectangle {
      id: stage
      readonly property real aspect: root.usable ? root.usable.width / root.usable.height : 16 / 10
      width: Math.min(stageArea.width, stageArea.height * aspect)
      height: width / aspect
      anchors.horizontalCenter: parent.horizontalCenter
      color: Util.alpha(Color.foreground, 0.04)
      border.width: 1
      border.color: root.faint
      radius: root.rounded ? Math.max(2, root.radius / 3) : 0
      clip: true

      Repeater {
        model: root.windows

        Rectangle {
          id: frame
          required property var modelData
          x: modelData.x
          y: modelData.y
          width: modelData.width
          height: modelData.height
          radius: root.rounded ? Math.max(2, root.radius / 4) : 0
          color: Util.alpha(Color.foreground, 0.08)
          border.width: 1
          border.color: Util.alpha(Color.accent, 0.35)
          clip: true

          ScreencopyView {
            id: capture
            anchors.fill: parent
            anchors.margins: 1
            captureSource: root.live && frame.modelData.toplevel && frame.modelData.toplevel.wayland ? frame.modelData.toplevel.wayland : null
            live: root.live
            paintCursor: false
            // The buffer near the size it's drawn at, whatever the window's.
            constraintSize: Qt.size(Math.max(1, width * 2), Math.max(1, height * 2))
            opacity: hasContent ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 150 } }
          }

          // The app's name until its first frame, or when it can't be captured.
          Label {
            visible: !capture.hasContent
            anchors.centerIn: parent
            width: parent.width - 8
            horizontalAlignment: Text.AlignHCenter
            text: frame.modelData.label
            color: root.dim
            font.pixelSize: Math.max(8, Math.min(root.smallSize, parent.height * 0.3))
          }
        }
      }

      Label {
        visible: root.windows.length === 0
        anchors.centerIn: parent
        text: !root.target ? "Pick a workspace in the settings"
          : root.feed && root.feed.monitors.length === 0 ? "Reading the workspace…"
          : "Nothing open here"
        color: root.dim
      }
    }
  }
}
