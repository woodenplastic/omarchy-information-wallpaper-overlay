import QtQuick
import qs.Commons
import "Model.js" as Model

// Long tasks on the machine: builds, flashing, updates, copies. Running
// ones first, with their project, who started them, their jobs, CPU and
// time, and while there's room a second line: what it's doing now, its CPU
// over the last two minutes, and how far along it is next to how long it
// took last time. Then the last ones that ended, newest first, green or red
// when the shell hook saw how they ended, grey when it didn't.
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

  // Time left, roughly: "~3m", "<1m".
  function roughly(seconds) {
    if (seconds < 60) return "<1m"
    if (seconds < 3600) return "~" + Math.round(seconds / 60) + "m"
    return "~" + Model.span(seconds)
  }

  // "210 MB/s" for bytes a second.
  function rate(bytes) {
    var units = ["B/s", "kB/s", "MB/s", "GB/s"]
    var n = Math.max(0, Number(bytes) || 0), i = 0
    while (n >= 1000 && i < units.length - 1) { n /= 1000; i++ }
    return (n < 10 && i > 0 ? n.toFixed(1) : Math.round(n)) + " " + units[i]
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

  // ---- The tasks, as many as fit: the running ones first, then a second
  //      line for as many of them as there's room for, then the ended ones.
  Column {
    id: list
    visible: root.tasks.length > 0
    anchors.top: rule.bottom
    anchors.topMargin: root.statSize * 0.6
    width: parent.width

    readonly property real rowHeight: Math.round(root.bodySize * 1.75)
    readonly property real detailTop: Math.round(rowHeight * 0.92)
    readonly property real barHeight: Math.max(2, Math.round(root.bodySize * 0.14))
    readonly property real detailHeight: Math.round(root.smallSize * 1.9 + barHeight)
    readonly property real tallHeight: Math.round(detailTop + detailHeight + root.bodySize * 0.5)
    readonly property real room: root.area.height - y
    readonly property int runningShown: Math.max(0, Math.min(root.counts.running, Math.floor(room / rowHeight)))
    readonly property int tall: runningShown < root.counts.running ? 0
      : Math.min(runningShown, Math.floor((room - runningShown * rowHeight) / (tallHeight - rowHeight)))
    readonly property int shown: runningShown + Math.max(0, Math.min(root.tasks.length - runningShown,
      Math.floor((room - runningShown * rowHeight - tall * (tallHeight - rowHeight)) / rowHeight)))
    readonly property real sparkWidth: Math.round(Math.min(width * 0.2, root.bodySize * 7))
    readonly property real folderWidth: Math.min(width * 0.26, root.bodySize * 0.6 * 22)
    readonly property real timeWidth: Math.min(width * 0.36, root.bodySize * 0.6 * 30)

    Repeater {
      model: list.shown

      Item {
        id: row
        required property int index
        readonly property var task: root.tasks[index] || ({})
        readonly property bool running: task.state === "running"
        readonly property bool tall: running && index < list.tall
        readonly property real expected: task.expected || 0
        readonly property bool over: expected > 0 && task.elapsed > expected
        // A copy says how far into its input it is; that beats the last runs.
        readonly property real progress: typeof task.progress === "number" ? task.progress : -1
        readonly property bool measured: progress >= 0
        readonly property real fraction: measured ? progress
          : expected > 0 ? Math.min(1, task.elapsed / expected) : 0
        width: list.width
        height: tall ? list.tallHeight : list.rowHeight
        opacity: running ? 1 : 0.8

        Item {
          id: line
          width: parent.width
          height: list.rowHeight
        }

        StateBlock {
          id: block
          anchors.verticalCenter: line.verticalCenter
          taskState: row.task.state || "done"
        }
        Label {
          id: label
          anchors.left: block.right
          anchors.leftMargin: root.bodySize * 0.7
          anchors.verticalCenter: line.verticalCenter
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
          anchors.verticalCenter: line.verticalCenter
          text: [row.task.folder, row.task.by ? "by " + row.task.by : ""].filter(function(s) { return s }).join("  ·  ")
          color: row.task.folder ? Color.accent : root.dim
        }
        Label {
          id: time
          anchors.right: parent.right
          anchors.verticalCenter: line.verticalCenter
          width: list.timeWidth
          horizontalAlignment: Text.AlignRight
          color: root.dim
          text: row.running
            ? [row.task.jobs > 1 ? "×" + row.task.jobs : "", row.task.cpu > 0 ? row.task.cpu + "%" : "", Model.span(row.task.elapsed)].filter(function(s) { return s }).join("  ·  ")
            : root.stateWord(row.task.state) + " after " + Model.span(row.task.elapsed) + "  ·  " + (row.task.ago < 60 ? "just now" : row.task.ago < 86400 ? Model.span(row.task.ago).split(" ")[0] + " ago" : Math.floor(row.task.ago / 86400) + "d ago")
        }

        // ---- What it's doing, its CPU and how far along it is.
        Item {
          id: detail
          visible: row.tall
          x: label.x
          y: list.detailTop
          width: row.width - x
          height: list.detailHeight

          Label {
            anchors.left: parent.left
            anchors.right: eta.left
            anchors.rightMargin: root.bodySize
            anchors.verticalCenter: eta.verticalCenter
            font.pixelSize: root.smallSize
            color: root.dim
            text: row.task.step || ""
          }
          Label {
            id: eta
            anchors.right: spark.left
            anchors.rightMargin: root.bodySize * 0.8
            anchors.verticalCenter: spark.verticalCenter
            font.pixelSize: root.smallSize
            color: root.dim
            text: row.measured
              ? [Math.floor(row.progress * 100) + "%",
                 row.task.rate > 0 ? root.rate(row.task.rate) : "",
                 row.progress > 0.02 ? root.roughly(row.task.elapsed * (1 - row.progress) / row.progress) + " left" : ""].filter(function(s) { return s }).join("  ·  ")
              : row.expected <= 0 ? ""
              : row.over ? "over the usual " + Model.span(row.expected)
              : root.roughly(row.expected - row.task.elapsed) + " left"
          }

          // CPU over the last two minutes, newest on the right, as a share
          // of the machine; the square root keeps one busy core in sight
          // on a machine with many.
          Item {
            id: spark
            anchors.right: parent.right
            width: list.sparkWidth
            height: Math.round(root.smallSize * 1.4)
            readonly property var load: row.task.load || []
            readonly property real slot: width / 60

            Rectangle {
              anchors.bottom: parent.bottom
              width: parent.width
              height: 1
              color: root.faint
            }
            Repeater {
              model: spark.load

              Rectangle {
                required property int index
                required property var modelData
                anchors.bottom: parent.bottom
                x: spark.width - (spark.load.length - index) * spark.slot
                width: Math.max(1, spark.slot - (spark.slot >= 3 ? 1 : 0))
                height: modelData > 0 ? Math.max(1, spark.height * Math.sqrt(modelData / 100)) : 0
                color: root.stateColor("running")
                opacity: 0.75
              }
            }
          }

          // How far into its input a copy is, or else the time against the
          // last runs of the same task in the same folder; full, and dimmer,
          // once it's taking longer.
          Rectangle {
            visible: row.measured || row.expected > 0
            anchors.bottom: parent.bottom
            width: parent.width
            height: list.barHeight
            radius: root.rounded ? height / 2 : 0
            color: root.faint

            Rectangle {
              height: parent.height
              radius: parent.radius
              width: parent.width * row.fraction
              color: root.stateColor("running")
              opacity: row.over && !row.measured ? 0.45 : 0.9
              Behavior on width {
                enabled: root.animate
                NumberAnimation { duration: 2000 }
              }
            }
          }
        }
      }
    }
  }
}
