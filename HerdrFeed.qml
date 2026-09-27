import QtQuick
import Quickshell.Io
import "Model.js" as Model

// herdr's agents and workspaces for the agents tile, asked every two seconds
// while `active`. `herdr agent list` and `workspace list` answer from the
// running server's socket in a few milliseconds.
Item {
  id: root
  visible: false

  property bool active: false

  property var agents: []
  property var workspaces: []
  // pane id -> { state, sinceMs }, see Model.trackAgents.
  property var seen: ({})
  property string error: ""
  property bool loaded: false

  readonly property var groups: Model.herdrGroups(agents, workspaces)
  readonly property var counts: Model.herdrCounts(agents)

  Process {
    id: proc
    command: ["bash", "-c", "command -v herdr >/dev/null || { echo 'herdr not found; see https://herdr.dev' >&2; exit 127; }; herdr agent list && herdr workspace list"]
    stdout: StdioCollector { id: out; waitForEnd: true }
    stderr: StdioCollector { id: err; waitForEnd: true }
    onExited: function(exitCode) { root.read(exitCode, String(out.text || ""), String(err.text || "")) }
  }

  function read(exitCode, text, errText) {
    var agents = null, workspaces = null
    var lines = text.split("\n")
    for (var i = 0; i < lines.length; i++) {
      var data
      try { data = JSON.parse(lines[i]) } catch (e) { continue }
      var result = data && data.result ? data.result : {}
      if (result.type === "agent_list") agents = result.agents || []
      else if (result.type === "workspace_list") workspaces = result.workspaces || []
    }
    if (exitCode !== 0 || !agents) {
      root.error = errText.trim().split("\n")[0] || "herdr isn't running"
      root.agents = []
      root.workspaces = []
    } else {
      root.error = ""
      root.seen = Model.trackAgents(agents, root.seen, Date.now(), !root.loaded)
      root.agents = agents
      root.workspaces = workspaces || []
    }
    root.loaded = true
  }

  Timer {
    running: root.active
    repeat: true
    triggeredOnStart: true
    interval: 2000
    onTriggered: if (!proc.running) proc.running = true
  }
}
