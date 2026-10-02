import QtQuick
import QtQuick.Effects
import qs.Commons
import "Model.js" as Model

// A year of commits per day, GitHub style: a column per week, Sunday on top,
// month names above, Mon/Wed/Fri beside, a Less-More legend below. Cells with
// commits twinkle now and then and today's cell breathes, while `animate`.
Item {
  id: root

  property var days: ({})
  property real nowMs: Date.now()
  property int weeks: 53
  property real pitch: 16
  property bool animate: true
  // The desk's pulse clock (Model.breathe): today breathes and the sparks
  // light and fade on its ticks, never at the display's frame rate.
  property real pulseMs: 0
  property bool rounded: false
  property real fontSize: Style.font.caption
  property color accent: Color.accent
  property color foreground: Color.foreground
  property color dim: Util.alpha(Color.foreground, 0.5)
  // Shown at the left end of the legend row.
  property string note: ""

  readonly property real cell: Math.max(3, Math.round(pitch * 0.8))
  readonly property real radius: rounded ? Math.max(1, cell * 0.22) : 0
  readonly property real labelWidth: fontSize * 2.6
  readonly property real monthHeight: fontSize * 1.8
  readonly property real gridX: labelWidth
  readonly property real gridY: monthHeight
  readonly property real gridWidth: weeks * pitch - (pitch - cell)
  readonly property real gridHeight: 7 * pitch - (pitch - cell)
  readonly property var map: Model.heatmap(days, nowMs, weeks)
  readonly property var active: map.cells.filter(function(c) { return c.count > 0 })
  readonly property var todayCell: {
    for (var i = map.cells.length - 1; i >= 0; i--) if (map.cells[i].today) return map.cells[i]
    return null
  }

  implicitWidth: gridX + gridWidth
  implicitHeight: gridY + gridHeight + fontSize * 2.4

  function levelColor(level) {
    if (level <= 0) return Util.alpha(root.foreground, 0.1)
    return Util.alpha(root.accent, [0, 0.3, 0.52, 0.76, 1][level])
  }

  component DimText: Text {
    textFormat: Text.PlainText
    color: root.dim
    font.family: Style.font.family
    font.pixelSize: root.fontSize
  }

  Repeater {
    model: root.map.months
    DimText {
      required property var modelData
      x: root.gridX + modelData.col * root.pitch
      y: 0
      text: modelData.name
    }
  }

  Repeater {
    model: [{ row: 1, name: "Mon" }, { row: 3, name: "Wed" }, { row: 5, name: "Fri" }]
    DimText {
      required property var modelData
      x: 0
      y: root.gridY + modelData.row * root.pitch + (root.cell - height) / 2
      text: modelData.name
    }
  }

  Repeater {
    model: root.map.cells
    Rectangle {
      required property var modelData
      visible: !modelData.future
      x: root.gridX + modelData.col * root.pitch
      y: root.gridY + modelData.row * root.pitch
      width: root.cell
      height: root.cell
      radius: root.radius
      color: root.levelColor(modelData.level)
    }
  }

  // ---- Today: an accent frame that breathes.
  Item {
    id: today
    visible: !!root.todayCell
    readonly property real inset: Math.max(1.5, root.cell * 0.14)
    x: root.gridX + (root.todayCell ? root.todayCell.col : 0) * root.pitch - inset
    y: root.gridY + (root.todayCell ? root.todayCell.row : 0) * root.pitch - inset
    width: root.cell + inset * 2
    height: width

    Rectangle {
      id: todayFrame
      anchors.fill: parent
      color: "transparent"
      radius: root.rounded ? root.radius + today.inset : 0
      border.width: Math.max(1, Math.round(today.inset * 0.9))
      border.color: root.accent
      layer.enabled: true
      layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: root.accent
        shadowBlur: 0.8
        shadowHorizontalOffset: 0
        shadowVerticalOffset: 0
      }
    }

    opacity: root.animate ? Model.breathe(root.pulseMs, 0.35) : 1
  }

  // ---- Sparks: a few cells with commits light up and fade, one at a time,
  //      a new one about every half second.
  property real lastSpark: 0

  onPulseMsChanged: {
    if (!root.animate || root.active.length === 0 || root.pulseMs - root.lastSpark < 500) return
    for (var i = 0; i < sparks.count; i++) {
      var spark = sparks.itemAt(i)
      if (spark && !spark.busy) {
        spark.fire(root.active[Math.floor(Math.random() * root.active.length)])
        root.lastSpark = root.pulseMs
        return
      }
    }
  }

  Repeater {
    id: sparks
    model: 6

    Item {
      id: spark
      property real litAt: -1e9
      readonly property real age: root.pulseMs - litAt
      readonly property bool busy: age < Model.SPARK_RISE_MS + Model.SPARK_FADE_MS
      x: 0
      y: 0
      width: root.cell
      height: root.cell
      visible: root.animate && busy
      opacity: visible ? Model.sparkOpacity(age) : 0

      function fire(c) {
        spark.x = root.gridX + c.col * root.pitch
        spark.y = root.gridY + c.row * root.pitch
        spark.litAt = root.pulseMs
      }

      Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Qt.lighter(root.accent, 1.35)
        layer.enabled: true
        layer.effect: MultiEffect {
          shadowEnabled: true
          shadowColor: root.accent
          shadowBlur: 1
          shadowHorizontalOffset: 0
          shadowVerticalOffset: 0
        }
      }

    }
  }

  // ---- Legend.
  DimText {
    anchors.left: parent.left
    anchors.leftMargin: root.gridX
    y: root.gridY + root.gridHeight + root.fontSize * 0.9
    width: Math.max(0, legend.x - root.gridX - root.fontSize)
    elide: Text.ElideRight
    text: root.note
  }

  Row {
    id: legend
    anchors.right: parent.right
    y: root.gridY + root.gridHeight + root.fontSize * 0.9
    spacing: Math.max(2, root.pitch - root.cell)

    DimText { text: "Less"; anchors.verticalCenter: parent.verticalCenter; rightPadding: root.fontSize * 0.3 }
    Repeater {
      model: 5
      Rectangle {
        required property int index
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(root.cell, root.fontSize)
        height: width
        radius: root.rounded ? width * 0.22 : 0
        color: root.levelColor(index)
      }
    }
    DimText { text: "More"; anchors.verticalCenter: parent.verticalCenter; leftPadding: root.fontSize * 0.3 }
  }
}
