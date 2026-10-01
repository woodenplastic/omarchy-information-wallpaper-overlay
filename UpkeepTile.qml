import QtQuick
import qs.Commons

// How the machine is doing, from scripts/upkeep: whether it needs a reboot,
// pending updates, failed units, the last snapshot and free space. One row
// each, red or yellow when it needs a look; where there's room, a row says
// more under it (the packages, the units), the red ones first.
Tile {
  id: root

  readonly property var feed: widget ? widget.upkeepFeed : null
  readonly property var info: feed && feed.loaded ? feed.output : null
  readonly property var items: info && Array.isArray(info.items) ? info.items : []
  readonly property var counts: {
    var c = { bad: 0, warn: 0, ok: 0 }
    for (var i = 0; i < items.length; i++) if (c[items[i].state] !== undefined) c[items[i].state] += 1
    return c
  }

  glowY: pad + header.height

  function stateColor(state) {
    if (!widget) return faint
    if (state === "bad") return widget.failureColor
    if (state === "warn") return widget.runningColor
    if (state === "ok") return widget.successColor
    return Util.alpha(Color.foreground, 0.25)
  }

  function countWord(state, n) {
    if (state === "bad") return n + " to fix"
    if (state === "warn") return n + " to look at"
    return n + " fine"
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
    property string itemState: "unknown"
    width: root.bodySize * 0.7
    height: width
    radius: root.rounded ? width * 0.22 : 0
    color: root.stateColor(itemState)
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
        text: ""
        color: Color.accent
        font.pixelSize: root.titleSize * 0.85
      }
      Label {
        id: titleText
        text: "Upkeep"
        font.pixelSize: root.titleSize
        font.bold: true
      }
    }

    Flow {
      width: parent.width
      spacing: root.statSize * 0.9
      visible: root.items.length > 0

      Repeater {
        model: ["bad", "warn", "ok"]

        Row {
          required property string modelData
          readonly property int count: root.counts[modelData]
          visible: count > 0
          spacing: root.statSize * 0.35

          StateBlock {
            anchors.verticalCenter: parent.verticalCenter
            itemState: parent.modelData
            width: root.statSize * 0.55
          }
          Label {
            anchors.verticalCenter: parent.verticalCenter
            text: root.countWord(parent.modelData, parent.count)
            font.pixelSize: root.statSize
            color: parent.modelData === "bad" ? root.stateColor("bad") : root.fg
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
    visible: root.items.length === 0
    anchors.top: rule.bottom
    anchors.topMargin: root.statSize
    width: parent.width
    color: root.dim
    text: "Looking…"
  }

  // ---- The rows, then the lines under them as room allows.
  Column {
    id: list
    visible: root.items.length > 0
    anchors.top: rule.bottom
    anchors.topMargin: root.statSize * 0.6
    width: parent.width

    readonly property real rowHeight: Math.round(root.bodySize * 1.75)
    readonly property real lineHeight: Math.round(root.smallSize * 1.45)
    readonly property real room: root.area.height - y
    readonly property int shown: Math.max(0, Math.min(root.items.length, Math.floor(room / rowHeight)))
    // Lines each row gets: the red rows first, then the yellow, then the
    // rest, in their order, while there's room; a row cut short ends on
    // "and N more".
    readonly property var lineCounts: {
      var out = []
      for (var i = 0; i < root.items.length; i++) out.push(0)
      var left = room - shown * rowHeight
      var order = ["bad", "warn", "ok", "unknown"]
      for (var o = 0; o < order.length; o++) {
        for (var j = 0; j < shown; j++) {
          var lines = root.items[j].lines || []
          if (root.items[j].state !== order[o] || lines.length === 0) continue
          var n = Math.min(lines.length, Math.floor((left - gap) / lineHeight))
          // A lone "and N more" says nothing.
          if (n <= 0 || (n === 1 && lines.length > 1)) continue
          out[j] = n
          left -= gap + n * lineHeight
        }
      }
      return out
    }
    // Under a row's lines, before the next row.
    readonly property real gap: Math.round(root.bodySize * 0.3)
    readonly property real indent: root.bodySize * 0.7 + root.bodySize * 0.7

    Repeater {
      model: list.shown

      Column {
        id: row
        required property int index
        readonly property var item: root.items[index] || ({})
        readonly property var lines: item.lines || []
        readonly property int lineCount: list.lineCounts[index] || 0
        width: list.width

        Item {
          width: parent.width
          height: list.rowHeight

          StateBlock {
            id: block
            anchors.verticalCenter: parent.verticalCenter
            itemState: row.item.state || "unknown"
          }
          Label {
            id: title
            anchors.left: block.right
            anchors.leftMargin: root.bodySize * 0.7
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, parent.width * 0.55)
            text: row.item.title || ""
            color: row.item.state === "bad" ? root.stateColor("bad") : root.fg
            font.bold: row.item.state === "bad" || row.item.state === "warn"
          }
          Label {
            anchors.left: title.right
            anchors.leftMargin: root.bodySize * 0.9
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            text: row.item.detail || ""
            color: root.dim
          }
        }

        Repeater {
          model: row.lineCount

          Label {
            required property int index
            readonly property bool cut: index === row.lineCount - 1 && row.lines.length > row.lineCount
            x: list.indent
            width: list.width - list.indent
            height: list.lineHeight
            verticalAlignment: Text.AlignVCenter
            font.pixelSize: root.smallSize
            color: root.dim
            text: cut ? "and " + (row.lines.length - index) + " more" : row.lines[index]
          }
        }

        Item {
          visible: row.lineCount > 0
          width: 1
          height: list.gap
        }
      }
    }
  }
}
