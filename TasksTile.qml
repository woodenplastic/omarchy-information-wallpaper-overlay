import QtQuick
import qs.Commons
import "Model.js" as Model

// Long tasks on the machine: builds, flashing, updates, copies. Running
// ones first, with their project, who started them, their jobs, CPU and
// time; then the last ones that ended, newest first, green or red when the
// shell hook saw how they ended, grey when it didn't.
Tile {
  id: root

  readonly property var feed: widget ? widget.tasksFeed : null
  readonly property var tasks: feed ? feed.tasks : []
  readonly property var counts: Model.taskCounts(tasks)

  glowY: pad + header.height

  function stateColor(state) {
    if (!widget) return faint
    if (state === "failure") return widget.failureColor
    if (state === "running") return widget.runningColor
    if (state === "success") return widget.successColor
    return Util.alpha(Color.foreground, 0.25)
  }

  function stateWord(state) {
    if (state === "success") return "passed"
    if (state === "failure") return "failed"
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

  component StateBlock: Rectangle {
    id: block
    property string taskState: "done"
    width: root.bodySize * 0.7
    height: width
    radius: root.rounded ? width * 0.22 : 0
    color: root.stateColor(taskState)

    SequentialAnimation on opacity {
      running: root.animate && block.taskState === "running"
      loops: Animation.Infinite
      onRunningChanged: if (!running) block.opacity = 1
      NumberAnimation { to: 0.35; duration: 800; easing.type: Easing.InOutSine }
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
        text: ""
        color: Color.accent
        font.pixelSize: root.titleSize * 0.85
      }
      Label {
        id: titleText
        text: "Tasks"
        font.pixelSize: root.titleSize
        font.bold: true
      }
    }

    Flow {
      width: parent.width
      spacing: root.statSize * 0.9
      visible: root.tasks.length > 0

      Repeater {
        model: ["running", "failure", "success", "done"]

        Row {
          required property string modelData
          readonly property int count: root.counts[modelData] + (modelData === "done" ? root.counts.cancelled : 0)
          visible: count > 0
          spacing: root.statSize * 0.35

          StateBlock {
            anchors.verticalCenter: parent.verticalCenter
            taskState: parent.modelData
            width: root.statSize * 0.55
          }
          Label {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.count + " " + root.stateWord(parent.modelData)
            font.pixelSize: root.statSize
            color: parent.modelData === "failure" ? root.stateColor("failure") : root.fg
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

  Label {
    visible: root.tasks.length === 0
    anchors.top: rule.bottom
    anchors.topMargin: root.statSize
    width: parent.width
    wrapMode: Text.Wrap
    maximumLineCount: 3
    color: root.dim

  }

  // ---- The tasks, as many as fit.
  Column {
    id: list
    visible: root.tasks.length > 0
    anchors.top: rule.bottom
    anchors.topMargin: root.statSize * 0.6
    width: parent.width

    readonly property real rowHeight: Math.round(root.bodySize * 1.75)
    readonly property int shown: Math.max(0, Math.min(root.tasks.length, Math.floor((root.area.height - y) / rowHeight)))
    readonly property real folderWidth: Math.min(width * 0.26, root.bodySize * 0.6 * 22)
    readonly property real timeWidth: Math.min(width * 0.36, root.bodySize * 0.6 * 30)

    Repeater {
      model: list.shown

      Item {
        id: row
        required property int index
        readonly property var task: root.tasks[index] || ({})
        readonly property bool running: task.state === "running"
        width: list.width
        height: list.rowHeight
        opacity: running ? 1 : 0.8

        StateBlock {
          id: block
          anchors.verticalCenter: parent.verticalCenter
          taskState: row.task.state || "done"
        }
        Label {
          id: label
          anchors.left: block.right
          anchors.leftMargin: root.bodySize * 0.7
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, row.width - block.width - list.folderWidth - list.timeWidth - root.bodySize * 3)
          text: row.task.label || ""
          color: row.task.state === "failure" ? root.stateColor("failure") : root.fg
          font.bold: row.running
        }
        Label {
          anchors.left: label.right
          anchors.leftMargin: root.bodySize * 0.8
          anchors.right: time.left
          anchors.rightMargin: root.bodySize
          anchors.verticalCenter: parent.verticalCenter
          text: [row.task.folder, row.task.by ? "by " + row.task.by : ""].filter(function(s) { return s }).join("  ·  ")
          color: row.task.folder ? Color.accent : root.dim
        }
        Label {
          id: time
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: list.timeWidth
          horizontalAlignment: Text.AlignRight
          color: root.dim
          text: row.running
            ? [row.task.jobs > 1 ? "×" + row.task.jobs : "", row.task.cpu > 0 ? row.task.cpu + "%" : "", Model.span(row.task.elapsed)].filter(function(s) { return s }).join("  ·  ")
            : root.stateWord(row.task.state) + " after " + Model.span(row.task.elapsed) + "  ·  " + (row.task.ago < 60 ? "just now" : row.task.ago < 86400 ? Model.span(row.task.ago).split(" ")[0] + " ago" : Math.floor(row.task.ago / 86400) + "d ago")
        }
      }
    }
  }
}
