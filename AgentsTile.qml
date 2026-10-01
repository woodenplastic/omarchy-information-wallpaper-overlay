import QtQuick
import qs.Commons
import "Model.js" as Model

// herdr's coding agents: how many are working, waiting for you, done or
// idle, then each workspace with its agents, the state, what the agent is
// on (its terminal title), the folder and how long it's been so, and under
// it the long tasks running in its pane (from the tasks watcher). An agent
// waiting for you stands out; working ones pulse.
Tile {
  id: root

  readonly property var feed: widget ? widget.herdr : null
  readonly property bool ok: !!feed && feed.loaded && feed.error === "" && feed.agents.length > 0
  readonly property var counts: feed ? feed.counts : ({ working: 0, blocked: 0, done: 0, idle: 0 })

  // The running tasks by the herdr pane they run in.
  readonly property var tasksFeed: widget ? widget.tasksFeed : null
  readonly property var paneTasks: {
    var out = {}
    var tasks = tasksFeed && tasksFeed.tasks ? tasksFeed.tasks : []
    for (var i = 0; i < tasks.length; i++) {
      var t = tasks[i]
      if (t.state !== "running" || !t.pane) continue
      if (!out[t.pane]) out[t.pane] = []
      out[t.pane].push(t)
    }
    return out
  }
  readonly property int maxTaskLines: 2

  function taskLines(agent) {
    var list = agent ? root.paneTasks[agent.pane_id] : null
    return list ? Math.min(root.maxTaskLines, list.length) : 0
  }

  // What an agent's tasks add to its row: their lines, tucked under the
  // agent, and a little room after them.
  function tasksHeight(agent, taskHeight) {
    var n = root.taskLines(agent)
    return n > 0 ? Math.round((n + 0.2) * taskHeight) : 0
  }

  glowY: pad + header.height

  function stateColor(state) {
    if (!widget) return faint
    if (state === "blocked") return widget.failureColor
    if (state === "working") return widget.runningColor
    if (state === "done") return widget.successColor
    return Util.alpha(Color.foreground, 0.25)
  }

  function stateWord(state) {
    if (state === "blocked") return "waiting for you"
    return state
  }

  component Label: Text {
    textFormat: Text.PlainText
    color: root.fg
    font.family: root.family
    font.pixelSize: root.bodySize
    elide: Text.ElideRight
    maximumLineCount: 1
  }

  component StateDot: Rectangle {
    id: stateDot
    property string agentState: "idle"
    width: root.bodySize * 0.62
    height: width
    radius: root.rounded ? width / 2 : width * 0.18
    color: root.stateColor(agentState)

    SequentialAnimation on opacity {
      running: root.animate && (stateDot.agentState === "working" || stateDot.agentState === "blocked")
      loops: Animation.Infinite
      onRunningChanged: if (!running) stateDot.opacity = 1
      NumberAnimation { to: 0.3; duration: 800; easing.type: Easing.InOutSine }
      NumberAnimation { to: 1; duration: 800; easing.type: Easing.InOutSine }
    }
  }

  // ---- Title and the counts.
  Column {
    id: header
    width: parent.width
    spacing: root.statSize * 0.4

    Row {
      spacing: root.titleSize * 0.45

      Label {
        anchors.baseline: titleText.baseline
        text: ""
        color: Color.accent
        font.pixelSize: root.titleSize * 0.85
      }
      Label {
        id: titleText
        text: "Agents"
        font.pixelSize: root.titleSize
        font.bold: true
      }
      Label {
        anchors.baseline: titleText.baseline
        text: "herdr"
        color: root.dim
        font.pixelSize: root.statSize
      }
    }

    Flow {
      width: parent.width
      spacing: root.statSize * 0.9
      visible: root.ok

      Repeater {
        model: ["blocked", "working", "done", "idle"]

        Row {
          required property string modelData
          readonly property int count: root.counts[modelData] || 0
          visible: count > 0
          spacing: root.statSize * 0.35

          StateDot {
            anchors.verticalCenter: parent.verticalCenter
            agentState: parent.modelData
            width: root.statSize * 0.55
          }
          Label {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.count + " " + root.stateWord(parent.modelData)
            font.pixelSize: root.statSize
            color: parent.modelData === "blocked" ? root.stateColor("blocked") : root.fg
            font.bold: parent.modelData === "blocked"
          }
        }
      }
    }
  }

  Rectangle {
    id: rule
    anchors.top: header.bottom
    anchors.topMargin: root.statSize
    width: parent.width
    height: 1
    color: root.faint
  }

  // ---- Without agents: why.
  Label {
    visible: !root.ok
    anchors.top: rule.bottom
    anchors.topMargin: root.statSize
    width: parent.width
    wrapMode: Text.Wrap
    maximumLineCount: 3
    color: root.feed && root.feed.error ? root.stateColor("blocked") : root.dim
    text: !root.feed || !root.feed.loaded ? "Asking herdr…"
      : root.feed.error ? root.feed.error
      : "No agents running in herdr"
  }

  // ---- Workspaces and their agents, as many rows as fit.
  Column {
    id: list
    visible: root.ok
    anchors.top: rule.bottom
    anchors.topMargin: root.statSize * 0.6
    width: parent.width

    readonly property real rowHeight: Math.round(root.bodySize * 1.75)
    readonly property real taskHeight: Math.round(root.smallSize * 1.55)
    readonly property real room: root.area.height - y
    // As many rows as fit with their tasks under them: fewer rows are asked
    // for until the rows, their tasks and the count of the rest fit.
    readonly property var layout: {
      if (!root.ok) return { rows: [], hidden: 0 }
      var lay = null
      for (var n = Math.max(1, Math.floor(room / rowHeight)); n >= 1; n--) {
        lay = Model.herdrRows(root.feed.groups, n)
        var h = lay.hidden > 0 ? rowHeight : 0
        for (var i = 0; i < lay.rows.length; i++) h += rowHeight + root.tasksHeight(lay.rows[i].agent, taskHeight)
        if (h <= room) break
      }
      return lay
    }
    readonly property real sinceWidth: root.bodySize * 0.6 * 8
    readonly property real folderWidth: Math.min(width * 0.24, root.bodySize * 0.6 * 22)

    Repeater {
      model: list.layout.rows

      Item {
        id: row
        required property var modelData
        readonly property var agent: modelData.agent
        readonly property var group: modelData.group
        readonly property string agentState: agent ? Model.agentState(agent.agent_status) : ""
        readonly property var seen: agent && root.feed ? root.feed.seen[agent.pane_id] : null
        readonly property var tasks: agent ? root.paneTasks[agent.pane_id] || [] : []
        width: list.width
        height: list.rowHeight + root.tasksHeight(agent, list.taskHeight)

        Item {
          id: line
          width: parent.width
          height: list.rowHeight
        }

        // A workspace: its number and name.
        Row {
          visible: !row.agent
          anchors.verticalCenter: line.verticalCenter
          spacing: root.bodySize * 0.6

          Label {
            text: row.group.number > 0 ? String(row.group.number) : ""
            color: root.dim
            font.pixelSize: root.statSize
          }
          Label {
            text: row.group.label
            color: row.group.focused ? Color.accent : root.fg
            font.pixelSize: root.statSize
            font.bold: true
          }
        }

        // An agent: state, name, what it's on, folder, how long.
        StateDot {
          id: dot
          visible: !!row.agent
          x: root.statSize * 0.5
          anchors.verticalCenter: line.verticalCenter
          agentState: row.agentState
        }
        Label {
          id: agentName
          visible: !!row.agent
          anchors.left: dot.right
          anchors.leftMargin: root.bodySize * 0.7
          anchors.verticalCenter: line.verticalCenter
          width: root.bodySize * 0.6 * 9
          text: row.agent ? row.agent.agent : ""
          color: row.agentState === "blocked" ? root.stateColor("blocked") : Color.accent
        }
        Label {
          visible: !!row.agent
          anchors.left: agentName.right
          anchors.right: folder.left
          anchors.rightMargin: root.bodySize
          anchors.verticalCenter: line.verticalCenter
          text: !row.agent ? ""
            : row.agentState === "blocked" ? "waiting for you  ·  " + (row.agent.terminal_title_stripped || "")
            : row.agent.terminal_title_stripped || row.agentState
          color: row.agentState === "blocked" ? root.stateColor("blocked") : row.agentState === "idle" ? root.dim : root.fg
        }
        Label {
          id: folder
          visible: !!row.agent
          anchors.right: sinceLabel.left
          anchors.rightMargin: root.bodySize
          anchors.verticalCenter: line.verticalCenter
          width: list.folderWidth
          horizontalAlignment: Text.AlignRight
          text: row.agent ? Model.baseName(row.agent.foreground_cwd || row.agent.cwd) : ""
          color: root.dim
        }
        Label {
          id: sinceLabel
          visible: !!row.agent
          anchors.right: parent.right
          anchors.verticalCenter: line.verticalCenter
          width: list.sinceWidth
          horizontalAlignment: Text.AlignRight
          text: row.seen ? Model.since(row.seen.sinceMs, root.nowMs) : ""
          color: root.dim
        }

        // Its long tasks: what, what it's doing now, how long so far.
        Repeater {
          model: root.taskLines(row.agent)

          Item {
            required property int index
            readonly property var task: row.tasks[index] || ({})
            readonly property int more: index === root.maxTaskLines - 1 ? row.tasks.length - root.maxTaskLines : 0
            x: agentName.x
            y: Math.round(list.rowHeight * 0.85 + index * list.taskHeight)
            width: row.width - x
            height: list.taskHeight

            Rectangle {
              id: taskBlock
              anchors.verticalCenter: parent.verticalCenter
              width: root.smallSize * 0.55
              height: width
              radius: root.rounded ? width * 0.22 : 0
              color: root.stateColor("working")
            }
            Label {
              id: taskLabel
              anchors.left: taskBlock.right
              anchors.leftMargin: root.smallSize * 0.6
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(implicitWidth, parent.width * 0.45)
              font.pixelSize: root.smallSize
              text: parent.task.label || ""
            }
            Label {
              anchors.left: taskLabel.right
              anchors.leftMargin: root.smallSize * 0.8
              anchors.right: taskTime.left
              anchors.rightMargin: root.smallSize
              anchors.verticalCenter: parent.verticalCenter
              font.pixelSize: root.smallSize
              color: root.dim
              text: [parent.task.step || "", parent.more > 0 ? "+" + parent.more + " more" : ""].filter(function(s) { return s }).join("  ·  ")
            }
            Label {
              id: taskTime
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              font.pixelSize: root.smallSize
              color: root.dim
              text: Model.span(parent.task.elapsed)
            }
          }
        }
      }
    }

    Label {
      visible: list.layout.hidden > 0
      height: list.rowHeight
      verticalAlignment: Text.AlignVCenter
      text: "+" + list.layout.hidden + " more"
      color: root.dim
    }
  }
}
