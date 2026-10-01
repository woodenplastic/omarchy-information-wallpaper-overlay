import QtQuick
import Quickshell.Io

// A watcher script for a tile (scripts/upkeep, projects, devices, board):
// it runs while `active` and prints one JSON object per line whenever it has
// news; the last one is `output`. It ends when its stdin closes, with the
// shell. A change of script or arguments restarts it; equal ones, which
// settings changes hand over too, leave it running.
Item {
  id: root
  visible: false

  property bool active: false
  // The script's file name in scripts/, and what it's given.
  property string script: ""
  property var args: []

  // Not `data`: that's where an Item keeps its children.
  property var output: null
  property bool loaded: false

  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")

  function restart() {
    var command = ["/usr/bin/python3", root.pluginDir + "/scripts/" + root.script].concat(root.args || [])
    if (root.active && proc.running && JSON.stringify(command) === JSON.stringify(proc.command)) return
    proc.running = false
    if (!root.active || !root.script) return
    proc.command = command
    Qt.callLater(function() { proc.running = root.active })
  }

  onActiveChanged: restart()
  onScriptChanged: restart()
  onArgsChanged: restart()
  Component.onCompleted: restart()

  Process {
    id: proc
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(line) {
        var data
        try { data = JSON.parse(line) } catch (e) { return }
        if (!data || typeof data !== "object") return
        root.output = data
        root.loaded = true
      }
    }
  }
}
