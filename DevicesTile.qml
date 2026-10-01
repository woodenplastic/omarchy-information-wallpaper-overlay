import QtQuick
import qs.Commons

// USB devices, from scripts/devices: dev boards and debug probes first,
// each with its serial port, the program that has it open, and how long
// it's been plugged in; one that was unplugged stays a moment, greyed. Then
// the other devices, dim and short. It never shows what a board prints:
// opening its port would reset it (see the script).
Tile {
  id: root

  readonly property var feed: widget ? widget.devicesFeed : null
  readonly property var info: feed && feed.output ? feed.output : ({ boards: [], others: [] })
  readonly property var boards: info.boards || []
  readonly property var others: info.others || []

  readonly property var counts: {
    var c = { busy: 0, ready: 0, gone: 0 }
    for (var i = 0; i < boards.length; i++) c[root.boardState(boards[i])] += 1
    return c
  }

  glowY: pad + header.height

  // busy (a program has its port open), ready or gone.
  function boardState(board) {
    if (board.gone) return "gone"
    var ports = board.ports || []
    for (var i = 0; i < ports.length; i++) if ((ports[i].users || []).length > 0) return "busy"
    return "ready"
  }

  function stateColor(state) {
    if (!widget) return faint
    if (state === "busy") return widget.runningColor
    if (state === "ready") return widget.successColor
    return Util.alpha(Color.foreground, 0.25)
  }

  function stateWord(state) {
    return state === "busy" ? "in use" : state === "ready" ? "ready" : "unplugged"
  }

  // "40s", "5m", "2h 10m", "3d" since a time in seconds.
  function ago(seconds) {
    var s = Math.max(0, Math.round(root.nowMs / 1000 - seconds))
    if (s < 60) return s + "s"
    var m = Math.floor(s / 60)
    if (m < 60) return m + "m"
    var h = Math.floor(m / 60)
    if (h < 24) return h + "h " + (m % 60) + "m"
    return Math.floor(h / 24) + "d"
  }

  function glyph(kind) {
    return kind === "keyboard" ? "" : kind === "mouse" ? "" : kind === "storage" ? ""
      : kind === "audio" ? "" : kind === "camera" ? "" : kind === "wireless" ? ""
      : kind === "printer" ? "" : kind === "serial" ? "" : kind === "input" ? ""
      : ""
  }

  // What a board's second line says: who has its port, or what it is.
  function detailOf(board) {
    var ports = board.ports || []
    var users = []
    for (var i = 0; i < ports.length; i++) {
      var u = ports[i].users || []
      for (var j = 0; j < u.length; j++) if (users.indexOf(u[j]) === -1) users.push(u[j])
    }
    var parts = [
      board.gone ? "unplugged " + root.ago(board.gone) + " ago"
        : users.length > 0 ? "in use by " + users.join(", ")
        : board.kind === "bootloader" ? "waiting in its bootloader"
        : ports.length > 0 ? "port free" : "no serial port",
      board.kind === "probe" ? "debug probe" : "",
      board.model && board.model !== board.name ? board.model : "",
      board.gone ? "" : "plugged in " + root.ago(board.since) + " ago"
    ]
    return parts.filter(function(s) { return s }).join("  ·  ")
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
    property string boardState: "ready"
    width: root.bodySize * 0.7
    height: width
    radius: root.rounded ? width * 0.22 : 0
    color: root.stateColor(boardState)

    SequentialAnimation on opacity {
      running: root.animate && block.boardState === "busy"
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
        text: ""
        color: Color.accent
        font.pixelSize: root.titleSize * 0.85
      }
      Label {
        id: titleText
        text: "Devices"
        font.pixelSize: root.titleSize
        font.bold: true
      }
      Label {
        anchors.baseline: titleText.baseline
        text: "USB"
        color: root.dim
        font.pixelSize: root.statSize
      }
    }

    Flow {
      width: parent.width
      spacing: root.statSize * 0.9
      visible: !!root.feed && root.feed.loaded

      Repeater {
        model: ["busy", "ready", "gone"]

        Row {
          required property string modelData
          readonly property int count: root.counts[modelData]
          visible: count > 0
          spacing: root.statSize * 0.35

          StateBlock {
            anchors.verticalCenter: parent.verticalCenter
            boardState: parent.modelData
            width: root.statSize * 0.55
          }
          Label {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.count + " " + root.stateWord(parent.modelData)
            font.pixelSize: root.statSize
          }
        }
      }

      Label {
        visible: root.others.length > 0
        text: root.others.length + (root.others.length === 1 ? " other device" : " other devices")
        font.pixelSize: root.statSize
        color: root.dim
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

  // ---- The boards, then the other devices, as many as fit: the boards
  //      get a second line while there's room for all of them to have one.
  Column {
    id: list
    anchors.top: rule.bottom
    anchors.topMargin: root.statSize * 0.6
    width: parent.width

    readonly property real rowHeight: Math.round(root.bodySize * 1.75)
    readonly property real detailTop: Math.round(rowHeight * 0.92)
    readonly property real tallHeight: Math.round(detailTop + root.smallSize * 1.4 + root.bodySize * 0.45)
    readonly property real otherHeight: Math.round(root.smallSize * 1.6)
    readonly property real room: root.area.height - y

    // No boards: a line that says so, in their place.
    readonly property int boardCount: Math.max(1, root.boards.length)
    readonly property bool tall: root.boards.length > 0 && root.boards.length * tallHeight <= room
    readonly property real boardHeight: tall ? tallHeight : rowHeight
    readonly property int boardsShown: Math.min(boardCount, Math.floor(room / boardHeight))
    readonly property real othersRoom: room - boardsShown * boardHeight - otherHeight * 1.5
    readonly property int othersFit: Math.max(0, Math.floor(othersRoom / otherHeight))
    // When they don't all fit, the last line counts the rest.
    readonly property int othersShown: othersFit >= root.others.length ? root.others.length : Math.max(0, othersFit - 1)

    Label {
      visible: !root.feed || !root.feed.loaded || root.boards.length === 0
      width: parent.width
      height: list.rowHeight
      verticalAlignment: Text.AlignVCenter
      color: root.dim
      text: !root.feed || !root.feed.loaded ? "Looking at USB…" : "No dev board plugged in"
    }

    Repeater {
      model: root.boards.length > 0 ? list.boardsShown : 0

      Item {
        id: row
        required property int index
        readonly property var board: root.boards[index] || ({})
        readonly property string boardState: root.boardState(board)
        width: list.width
        height: list.boardHeight
        opacity: boardState === "gone" ? 0.6 : 1

        Item {
          id: line
          width: parent.width
          height: list.rowHeight
        }

        StateBlock {
          id: block
          anchors.verticalCenter: line.verticalCenter
          boardState: row.boardState
        }
        Label {
          id: name
          anchors.left: block.right
          anchors.leftMargin: root.bodySize * 0.7
          anchors.right: ports.left
          anchors.rightMargin: root.bodySize
          anchors.verticalCenter: line.verticalCenter
          text: row.board.name || ""
          color: row.boardState === "gone" ? root.dim : root.fg
          font.bold: row.boardState !== "gone"
        }
        Label {
          id: ports
          anchors.right: parent.right
          anchors.verticalCenter: line.verticalCenter
          width: Math.min(implicitWidth, list.width * 0.4)
          horizontalAlignment: Text.AlignRight
          color: row.boardState === "busy" ? root.stateColor("busy") : Color.accent
          text: (row.board.ports || []).map(function(p) { return p.dev }).join("  ")
        }

        Label {
          visible: list.tall
          x: name.x
          y: list.detailTop
          width: row.width - x
          font.pixelSize: root.smallSize
          color: root.dim
          text: root.detailOf(row.board)
        }
      }
    }

    // ---- Everything else on USB.
    Label {
      visible: list.othersShown > 0 || (list.othersFit > 0 && root.others.length > 0)
      width: parent.width
      height: list.otherHeight * 1.5
      verticalAlignment: Text.AlignBottom
      bottomPadding: root.smallSize * 0.3
      font.pixelSize: root.smallSize
      color: root.dim
      text: "Other devices"
    }

    Repeater {
      model: list.othersShown

      Item {
        id: other
        required property int index
        readonly property var device: root.others[index] || ({})
        width: list.width
        height: list.otherHeight

        Label {
          id: icon
          anchors.verticalCenter: parent.verticalCenter
          width: root.bodySize * 0.7
          horizontalAlignment: Text.AlignHCenter
          font.pixelSize: root.smallSize
          color: root.dim
          text: root.glyph(other.device.kind)
        }
        Label {
          anchors.left: icon.right
          anchors.leftMargin: root.bodySize * 0.7
          anchors.right: kind.left
          anchors.rightMargin: root.bodySize
          anchors.verticalCenter: parent.verticalCenter
          font.pixelSize: root.smallSize
          color: root.dim
          text: other.device.name || ""
        }
        Label {
          id: kind
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          font.pixelSize: root.smallSize
          color: Util.alpha(Color.foreground, 0.4)
          text: other.device.kind === "device" ? "" : other.device.kind || ""
        }
      }
    }

    Label {
      visible: list.othersShown < root.others.length && list.othersFit > 0
      width: parent.width
      height: list.otherHeight
      verticalAlignment: Text.AlignVCenter
      leftPadding: root.bodySize * 1.4
      font.pixelSize: root.smallSize
      color: Util.alpha(Color.foreground, 0.4)
      text: "+" + (root.others.length - list.othersShown) + " more"
    }
  }
}
