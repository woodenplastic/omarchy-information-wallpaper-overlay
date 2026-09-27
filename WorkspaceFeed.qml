import QtQuick
import Quickshell.Hyprland
import Quickshell.Io

// Windows and monitors for the workspace tiles, from `hyprctl clients` and
// `hyprctl monitors` (Quickshell's cached copies don't notify on moves and
// resizes). Read every second while `active`, and at once when Hyprland
// reports a window opening, closing or moving.
Item {
  id: root
  visible: false

  property bool active: false

  // [{ a (address without 0x), ws, wsName, at, size, floating, fullscreen,
  //    focusHistoryID, monitor, cls, title }]
  property var clients: []
  // [{ id, name, x, y, width, height, scale, transform, reserved }]
  property var monitors: []

  function refresh() {
    if (!root.active || proc.running) return
    proc.running = true
  }

  Process {
    id: proc
    command: ["bash", "-c", "c=$(hyprctl clients -j 2>/dev/null) || exit 0; m=$(hyprctl monitors -j 2>/dev/null) || exit 0; "
      + "jq -cn --argjson c \"$c\" --argjson m \"$m\" '{clients: [$c[] | select(.mapped != false and .hidden != true) | "
      + "{a: (.address | ltrimstr(\"0x\")), ws: .workspace.id, wsName: .workspace.name, at, size, floating, fullscreen: ((.fullscreen // 0) != 0), focusHistoryID, monitor, cls: .class, title}], "
      + "monitors: [$m[] | {id, name, x, y, width, height, scale, transform, reserved}]}'"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var data
        try { data = JSON.parse(text) } catch (e) { return }
        if (!data || !Array.isArray(data.clients)) return
        if (JSON.stringify(data.clients) !== JSON.stringify(root.clients)) root.clients = data.clients
        if (JSON.stringify(data.monitors) !== JSON.stringify(root.monitors)) root.monitors = data.monitors
      }
    }
  }

  Timer {
    running: root.active
    repeat: true
    triggeredOnStart: true
    interval: 1000
    onTriggered: root.refresh()
  }

  // Window events refresh soon, after Hyprland has settled the layout.
  Timer {
    id: soon
    interval: 120
    onTriggered: root.refresh()
  }

  Connections {
    target: Hyprland
    enabled: root.active
    function onRawEvent(event) {
      if (/^(openwindow|closewindow|movewindow|movewindowv2|changefloatingmode|fullscreen|resizewindow|workspace|moveworkspace)/.test(event.name)) soon.restart()
    }
  }
}
