import QtQuick
import qs.Commons

// A KiCad board, from scripts/board: a 3D render made again after each
// save, how its DRC and its schematic's ERC came out, its size, copper
// layers and footprints, and when it was saved. While kicad-cli works on
// it, that pulses; the last render stays until the new one is there.
Tile {
  id: root

  readonly property var feed: widget ? widget.boardFeed : null
  readonly property var board: feed && feed.output && feed.output.boards && entry.path ? feed.output.boards[entry.path] || null : null
  readonly property bool hasImage: !!board && !!board.image

  glowY: pad + header.height + (art.height / 2)

  // A check's state: errors red, warnings yellow, passed green.
  function checkState(counts) {
    if (!counts) return ""
    if (counts.errors > 0 || counts.unconnected > 0) return "failure"
    if (counts.warnings > 0) return "warning"
    return "success"
  }

  function checkColor(state) {
    if (!widget) return faint
    if (state === "failure") return widget.failureColor
    if (state === "warning" || state === "busy") return widget.runningColor
    if (state === "success") return widget.successColor
    return Util.alpha(Color.foreground, 0.25)
  }

  function checkWords(counts) {
    if (!counts) return "…"
    var parts = []
    if (counts.errors > 0) parts.push(counts.errors + (counts.errors === 1 ? " error" : " errors"))
    if (counts.unconnected > 0) parts.push(counts.unconnected + " unconnected")
    if (counts.warnings > 0) parts.push(counts.warnings + (counts.warnings === 1 ? " warning" : " warnings"))
    return parts.length > 0 ? parts.join(", ") : "passed"
  }

  function ago(seconds) {
    if (seconds < 60) return "just now"
    if (seconds < 3600) return Math.floor(seconds / 60) + "m ago"
    if (seconds < 86400) return Math.floor(seconds / 3600) + "h ago"
    return Math.floor(seconds / 86400) + "d ago"
  }

  readonly property string factsText: {
    if (!board) return ""
    var parts = []
    if (board.width > 0 && board.height > 0) parts.push(board.width + " × " + board.height + " mm")
    if (board.layers > 0) parts.push(board.layers + " layers")
    if (board.footprints > 0) parts.push(board.footprints + " footprints")
    if (board.drc && board.drc.parity > 0) parts.push(board.drc.parity + " schematic differences")
    if (board.saved > 0) parts.push("saved " + ago(root.nowMs / 1000 - board.saved))
    return parts.join("  ·  ")
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
    property string checkState: ""
    property bool pulse: false
    width: root.statSize * 0.55
    height: width
    radius: root.rounded ? width * 0.22 : 0
    color: root.checkColor(checkState)

    SequentialAnimation on opacity {
      running: root.animate && block.pulse
      loops: Animation.Infinite
      onRunningChanged: if (!running) block.opacity = 1
      NumberAnimation { to: 0.35; duration: 800; easing.type: Easing.InOutSine }
      NumberAnimation { to: 1; duration: 800; easing.type: Easing.InOutSine }
    }
  }

  // ---- The board's name, then its checks.
  Column {
    id: header
    width: parent.width
    spacing: root.statSize * 0.4

    Row {
      width: parent.width
      spacing: root.titleSize * 0.45

      Label {
        id: glyph
        anchors.baseline: titleText.baseline
        text: ""
        color: Color.accent
        font.pixelSize: root.titleSize * 0.85
      }
      Label {
        id: titleText
        width: Math.min(implicitWidth, parent.width - glyph.width - parent.spacing)
        text: root.board ? root.board.name : "Board"
        font.pixelSize: root.titleSize
        font.bold: true
      }
    }

    Flow {
      width: parent.width
      spacing: root.statSize * 0.9
      // A board that can't be read has no checks to show.
      visible: !!root.board && (!!root.board.drc || !!root.board.erc || root.board.busy !== "" || !root.board.error)

      Repeater {
        model: [
          { name: "DRC", counts: root.board ? root.board.drc : null },
          { name: "ERC", counts: root.board ? root.board.erc : null }
        ]

        Row {
          required property var modelData
          // An ERC only shows for a board with a schematic to check.
          visible: modelData.name === "DRC" || !!modelData.counts
          spacing: root.statSize * 0.35

          StateBlock {
            anchors.verticalCenter: parent.verticalCenter
            checkState: root.checkState(parent.modelData.counts)
          }
          Label {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.modelData.name + " " + root.checkWords(parent.modelData.counts)
            font.pixelSize: root.statSize
            color: root.checkState(parent.modelData.counts) === "failure" ? root.checkColor("failure") : root.fg
          }
        }
      }

      // kicad-cli at work on it.
      Row {
        visible: !!root.board && root.board.busy !== ""
        spacing: root.statSize * 0.35

        StateBlock {
          anchors.verticalCenter: parent.verticalCenter
          checkState: "busy"
          pulse: true
        }
        Label {
          anchors.verticalCenter: parent.verticalCenter
          text: root.board ? root.board.busy + "…" : ""
          font.pixelSize: root.statSize
          color: root.dim
        }
      }
    }
  }

  // ---- The render, as large as fits between the checks and the facts.
  Item {
    id: art
    anchors.top: header.bottom
    anchors.topMargin: root.statSize * 0.6
    anchors.bottom: footer.top
    anchors.bottomMargin: root.statSize * 0.4
    width: parent.width

    Image {
      id: render
      anchors.fill: parent
      visible: root.hasImage
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      cache: false
      // The last render stays up while the next one loads.
      retainWhileLoading: true
      smooth: true
      mipmap: true
      sourceSize.width: Math.ceil(width * 1.5)
      source: root.hasImage ? "file://" + root.board.image + "?v=" + root.board.version : ""
    }

    // No render yet: why, or that it's being made.
    Label {
      visible: !root.hasImage
      anchors.centerIn: parent
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      maximumLineCount: 3
      color: root.board && root.board.error ? root.checkColor("failure") : root.dim
      text: !root.entry.path ? "Pick a board in the settings"
        : !root.feed || !root.feed.loaded ? "Loading…"
        : !root.board ? "Loading…"
        : root.board.error ? root.board.error
        : root.board.busy === "rendering" ? "Rendering…"
        : "No render yet"
    }
  }

  // ---- Size, layers, footprints and when it was saved; an error over a
  //      render that stays.
  Column {
    id: footer
    anchors.bottom: parent.bottom
    width: parent.width
    spacing: root.bodySize * 0.3

    Label {
      width: parent.width
      visible: root.hasImage && !!root.board.error
      text: root.board ? root.board.error : ""
      color: root.checkColor("failure")
    }
    Label {
      width: parent.width
      visible: text !== ""
      text: root.factsText
      color: root.dim
    }
  }
}
