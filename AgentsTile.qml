import QtQuick
import qs.Commons
import "Model.js" as Model

// herdr's coding agents: how many are working, waiting for you, done or
// idle, then each workspace with its agents, the state, what the agent is
// on (its terminal title), the folder and how long it's been so. An agent
// waiting for you stands out; working ones pulse.
Tile {
  id: root

  readonly property var feed: widget ? widget.herdr : null
  readonly property bool ok: !!feed && feed.loaded && feed.error === "" && feed.agents.length > 0
  readonly property var counts: feed ? feed.counts : ({ working: 0, blocked: 0, done: 0, idle: 0 })

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
    readonly property real room: root.area.height - y
    readonly property var layout: root.ok ? Model.herdrRows(root.feed.groups, Math.max(1, Math.floor(room / rowHeight))) : { rows: [], hidden: 0 }
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
        width: list.width
        height: list.rowHeight

        // A workspace: its number and name.
        Row {
          visible: !row.agent
          anchors.verticalCenter: parent.verticalCenter
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
          anchors.verticalCenter: parent.verticalCenter
          agentState: row.agentState
        }
        Label {
          id: agentName
          visible: !!row.agent
          anchors.left: dot.right
          anchors.leftMargin: root.bodySize * 0.7
          anchors.verticalCenter: parent.verticalCenter
          width: root.bodySize * 0.6 * 9
          text: row.agent ? row.agent.agent : ""
          color: row.agentState === "blocked" ? root.stateColor("blocked") : Color.accent
        }
        Label {
          visible: !!row.agent
          anchors.left: agentName.right
          anchors.right: folder.left
          anchors.rightMargin: root.bodySize
          anchors.verticalCenter: parent.verticalCenter
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
          anchors.verticalCenter: parent.verticalCenter
          width: list.folderWidth
          horizontalAlignment: Text.AlignRight
          text: row.agent ? Model.baseName(row.agent.foreground_cwd || row.agent.cwd) : ""
          color: root.dim
        }
        Label {
          id: sinceLabel
          visible: !!row.agent
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: list.sinceWidth
          horizontalAlignment: Text.AlignRight
          text: row.seen ? Model.since(row.seen.sinceMs, root.nowMs) : ""
          color: root.dim
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
