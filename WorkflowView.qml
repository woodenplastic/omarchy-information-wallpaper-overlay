import QtQuick
import qs.Commons
import "Model.js" as Model

// The runs going on in a repo, in place of its commits: the run, then each
// job, and the steps of the job that's running, with their times counting
// up. Several runs take turns every eight seconds.
Item {
  id: root

  property var runs: []
  property real nowMs: Date.now()
  property bool animate: true
  // The desk's pulse clock (Model.breathe).
  property real pulseMs: 0
  property real fontSize: Style.font.body
  property real titleSize: Style.font.subtitle
  property real smallSize: Style.font.caption
  property color foreground: Color.foreground
  property color dim: Util.alpha(Color.foreground, 0.55)
  property color successColor: "#9ece6a"
  property color runningColor: "#e0af68"
  property color failureColor: Color.urgent
  // Height the view may take.
  property real room: 200

  property int turn: 0
  readonly property var run: runs.length > 0 ? runs[turn % runs.length] : null
  readonly property string runState: Model.runState(run)
  readonly property real rowHeight: Math.round(fontSize * 1.75)
  readonly property int maxRows: Math.max(1, Math.floor((room - header.height - fontSize) / rowHeight))
  readonly property var rows: run ? Model.workflowRows(run, nowMs, maxRows) : []

  implicitHeight: header.height + fontSize * 0.6 + rows.length * rowHeight + (run && !run.jobs ? rowHeight : 0)

  Timer {
    interval: 8000
    repeat: true
    running: root.runs.length > 1
    onTriggered: root.turn = (root.turn + 1) % root.runs.length
  }

  onRunsChanged: if (turn >= runs.length) turn = 0

  function stateColor(state) {
    if (state === "success") return root.successColor
    if (state === "failure") return root.failureColor
    if (state === "running") return root.runningColor
    return root.dim
  }

  function glyph(state) {
    if (state === "success") return ""
    if (state === "failure") return ""
    if (state === "running") return ""
    if (state === "cancelled") return ""
    if (state === "skipped") return ""
    return ""
  }

  function word(state) {
    if (state === "running") return "running"
    if (state === "success") return "passed"
    if (state === "failure") return "failed"
    if (state === "cancelled") return "cancelled"
    if (state === "skipped") return "skipped"
    if (state === "waiting") return "waiting"
    return ""
  }

  component Label: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: Style.font.family
    font.pixelSize: root.fontSize
    elide: Text.ElideRight
    maximumLineCount: 1
  }

  // A dot that pulses while its job or step runs.
  component StateGlyph: Label {
    property string state: ""
    text: root.glyph(state)
    color: root.stateColor(state)
    horizontalAlignment: Text.AlignHCenter
    opacity: root.animate && state === "running" ? Model.breathe(root.pulseMs, 0.3) : 1
  }

  // ---- The run: name and number, its commit, state and time.
  Column {
    id: header
    width: parent.width
    spacing: root.fontSize * 0.2

    Item {
      width: parent.width
      height: runName.implicitHeight

      Row {
        spacing: root.fontSize * 0.6
        width: parent.width - runTime.width - root.fontSize

        StateGlyph {
          state: root.runState === "neutral" ? "cancelled" : root.runState
          font.pixelSize: root.titleSize
          anchors.baseline: runName.baseline
        }
        Label {
          id: runName
          text: root.run ? root.run.name : ""
          font.pixelSize: root.titleSize
          font.bold: true
          width: Math.min(implicitWidth, parent.width * 0.6)
        }
        Label {
          anchors.baseline: runName.baseline
          text: root.run ? "#" + root.run.number : ""
          color: root.dim
        }
        Label {
          anchors.baseline: runName.baseline
          visible: root.runs.length > 1
          text: (root.turn % Math.max(1, root.runs.length) + 1) + "/" + root.runs.length
          color: root.dim
          font.pixelSize: root.smallSize
        }
      }

      Label {
        id: runTime
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        color: root.stateColor(root.runState)
        font.pixelSize: root.titleSize
        text: root.run
          ? root.word(root.runState === "running" && root.run.status !== "in_progress" ? "waiting" : root.runState)
            + "  ·  " + Model.elapsed(root.run.started, root.run.status === "completed" ? root.run.updated : null, root.nowMs)
          : ""
      }
    }

    Label {
      width: parent.width
      color: root.dim
      text: root.run ? [root.run.title, root.run.event].filter(function(s) { return s && s !== root.run.name }).join("  ·  ") : ""
    }
  }

  // ---- Jobs, and the steps of the running one.
  Column {
    y: header.height + root.fontSize * 0.6
    width: parent.width

    Label {
      visible: !!root.run && !root.run.jobs
      height: root.rowHeight
      verticalAlignment: Text.AlignVCenter
      color: root.dim
      text: "Waiting for jobs…"
    }

    Repeater {
      model: root.rows

      Item {
        required property var modelData
        readonly property bool step: modelData.kind === "step"
        width: parent.width
        height: root.rowHeight

        StateGlyph {
          id: rowGlyph
          x: parent.step ? root.fontSize * 2 : 0
          width: root.fontSize * 1.4
          anchors.verticalCenter: parent.verticalCenter
          state: modelData.state
          font.pixelSize: parent.step ? root.smallSize : root.fontSize
        }
        Label {
          anchors.left: rowGlyph.right
          anchors.leftMargin: root.fontSize * 0.5
          anchors.right: rowTime.left
          anchors.rightMargin: root.fontSize
          anchors.verticalCenter: parent.verticalCenter
          text: modelData.name
          color: parent.step && modelData.state !== "running" ? root.dim : root.foreground
          font.bold: !parent.step
          font.italic: modelData.folded === true
        }
        Label {
          id: rowTime
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          color: modelData.state === "running" || modelData.state === "failure" ? root.stateColor(modelData.state) : root.dim
          text: parent.step
            ? modelData.time
            : [root.word(modelData.state), modelData.time].filter(function(s) { return s }).join("  ·  ")
        }
      }
    }
  }
}
