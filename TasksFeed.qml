import QtQuick
import Quickshell.Io
import "Model.js" as Model

// Long tasks for the tasks tile, from scripts/tasks: it runs while `active`
// and sends the list every two seconds. A new list of tools restarts it.
Item {
  id: root
  visible: false

  property bool active: false
  property var tools: []

  property var tasks: []
  property bool loaded: false
  readonly property var counts: Model.taskCounts(tasks)

  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")

  // Settings changes hand over equal lists too; those leave the watcher, and
  // the history it keeps, alone.
  function restart() {
    var command = ["/usr/bin/python3", root.pluginDir + "/scripts/tasks"].concat(root.tools)
    if (root.active && proc.running && JSON.stringify(command) === JSON.stringify(proc.command)) return
    proc.running = false
    if (!root.active) return
    proc.command = command
    Qt.callLater(function() { proc.running = root.active })
  }

  onActiveChanged: restart()
  onToolsChanged: restart()
  Component.onCompleted: restart()

  Process {
    id: proc
    // Open stdin: the watcher ends when it closes, with the shell.
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(line) {
        var data
        try { data = JSON.parse(line) } catch (e) { return }
        if (!data || !Array.isArray(data.tasks)) return
        root.tasks = data.tasks
        root.loaded = true
      }
    }
  }
}
