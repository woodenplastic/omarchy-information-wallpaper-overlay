import QtQuick
import qs.Commons

// A KiCad board, from scripts/board: a 3D render made again after each
// save, then views of it from six sides, shown in turn while the desk
// can be seen; how its DRC and its schematic's ERC came out, its size, copper
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
          text: !root.board ? "" : root.board.busy === "views" ? "rendering the views…" : root.board.busy + "…"
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

    // The board from six sides, once there are views of it as it is now:
    // each stays a while, then fades out, easing back a touch, and the next
    // fades in, settling from a touch larger. One after the other, never
    // both at once: two half-faded boards at different angles show through
    // each other and the wallpaper, and that flickered. They change while
    // the desk can be seen with animations on and hold otherwise; the first
    // looks from where the still does. Two layers take turns, the next
    // loaded off the main thread before the change starts; it runs on the
    // render thread, and between changes nothing is drawn.
    Item {
      id: views
      readonly property int count: root.board && root.board.views ? root.board.viewCount || 0 : 0
      readonly property string folder: count > 0 ? "file://" + root.board.views + "/" : ""
      readonly property string version: count > 0 ? String(root.board.viewsVersion) : ""
      readonly property int holdMs: 6000
      readonly property int outMs: 350
      readonly property int inMs: 650
      // The view in front and its layer; null until the first has loaded,
      // and the still shows till then.
      property int current: 0
      property Image front: null

      anchors.fill: parent
      visible: front !== null

      readonly property string key: folder + version
      onKeyChanged: restart()
      Component.onCompleted: restart()

      function url(i) {
        return folder + i + ".webp?v=" + version
      }

      function restart() {
        fade.stop()
        front = null
        current = 0
        for (var layer of [one, two]) {
          layer.wanted = false
          layer.opacity = 0
          layer.scale = 1
        }
        two.source = ""
        load(one, 0)
      }

      function load(layer, view) {
        layer.view = view
        layer.wanted = !!folder
        layer.source = folder ? url(view) : ""
        // The same view again is there already.
        arrived(layer)
      }

      function next() {
        if (fade.running || count < 2 || !front) return
        load(front === one ? two : one, (current + 1) % count)
      }

      function arrived(layer) {
        if (!layer.wanted || layer.status !== Image.Ready) return
        layer.wanted = false
        current = layer.view
        if (!front) {
          layer.z = 1
          layer.opacity = 1
          front = layer
          return
        }
        front.z = 0
        layer.z = 1
        fade.incoming = layer
        fade.outgoing = front
        front = layer
        fade.restart()
      }

      Timer {
        interval: views.holdMs
        repeat: true
        running: !!views.front && views.count > 1 && root.animate
        onTriggered: views.next()
      }

      SequentialAnimation {
        id: fade
        property Item incoming: null
        property Item outgoing: null
        ParallelAnimation {
          OpacityAnimator { target: fade.outgoing; from: 1; to: 0; duration: views.outMs; easing.type: Easing.InQuad }
          ScaleAnimator { target: fade.outgoing; from: 1; to: 0.98; duration: views.outMs; easing.type: Easing.InQuad }
        }
        ParallelAnimation {
          OpacityAnimator { target: fade.incoming; from: 0; to: 1; duration: views.inMs; easing.type: Easing.OutQuad }
          ScaleAnimator { target: fade.incoming; from: 1.02; to: 1; duration: views.inMs; easing.type: Easing.OutCubic }
        }
      }

      component Layer: Image {
        id: layer
        property int view: 0
        property bool wanted: false
        anchors.fill: parent
        opacity: 0
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: false
        smooth: true
        mipmap: true
        onStatusChanged: views.arrived(layer)
      }

      Layer { id: one }
      Layer { id: two }
    }

    Image {
      id: render
      anchors.fill: parent
      visible: root.hasImage && !views.visible
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
