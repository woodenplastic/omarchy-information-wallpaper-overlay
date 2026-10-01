import QtQuick
import QtQuick.Effects
import qs.Commons
import "../../io.github.sirjul1337.lock-explorer/designs"
import ".." as Desk
import "../Model.js" as Model

// Information Wallpaper Overlay as a Lock Screen Explorer design: the tiles
// fill the screen as they do the desktop, and a card in the middle holds the
// clock, the CI status, agents waiting and the password field. scripts/lock-design puts it on.
// As a boot screen (a snapshot, see snapshotMode) nothing on it is live, so
// the tiles are empty panes and the card holds only the field.
DesignBase {
  id: lock
  inputItem: field.input

  LockFeed {
    id: feed
    animate: lock.animating && feed.animations
    live: lock.inputEnabled
  }

  Wallpaper { anchors.fill: parent; lock: lock; blur: 0.85; dim: 0.2 }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    onClicked: { lock.wakeRequested(); lock.forcePasswordFocus() }
    onPositionChanged: lock.wakeRequested()
  }

  // The tiles come in once they have something to show: the plugins listed,
  // then a moment for them to gather their data, so a fresh lock never
  // flashes "not installed" or empty tiles. Three seconds at most.
  property bool tilesShown: false

  Timer {
    running: feed.ready && !lock.tilesShown
    interval: 400
    onTriggered: lock.tilesShown = true
  }

  Timer {
    running: !lock.tilesShown
    interval: 3000
    onTriggered: lock.tilesShown = true
  }

  Item {
    id: area
    anchors.fill: parent
    opacity: lock.tilesShown || lock.snapshotMode ? 1 : 0

    Behavior on opacity {
      enabled: !lock.snapshotMode && feed.animations
      NumberAnimation { duration: 450; easing.type: Easing.OutCubic }
    }

    readonly property var rects: Model.tileRects(feed.tiles.length, width, height, feed.gap)

    Repeater {
      model: feed.tiles.length

      Item {
        required property int index
        readonly property var rect: area.rects[index] || { x: 0, y: 0, w: 0, h: 0 }

        x: Math.round(rect.x)
        y: Math.round(rect.y)
        width: Math.round(rect.w)
        height: Math.round(rect.h)

        Desk.TileView {
          anchors.fill: parent
          active: !lock.snapshotMode
          widget: feed
          entry: feed.tiles[index]
        }

        // A boot screen shows the same panes, empty: what's in them would
        // be days old by the time it's seen.
        Desk.Tile {
          anchors.fill: parent
          visible: lock.snapshotMode
          widget: feed
        }
      }
    }
  }

  // ---- The card: clock, date, CI status, password.

  readonly property string ciState: Model.overallState(feed.shownResults)
  readonly property color ciColor: ciState === "failure" ? feed.failureColor
    : ciState === "running" ? feed.runningColor
    : feed.successColor

  Rectangle {
    id: card
    anchors.centerIn: parent
    width: field.width + 64
    height: content.implicitHeight + 56
    radius: feed.rounding > 0 ? Math.max(feed.rounding, 8) + 8 : 0
    color: lock.withAlpha(Color.lock.background, 0.88)
    border.width: 1
    border.color: lock.withAlpha(Color.lock.text, 0.12)
    layer.enabled: true
    layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Qt.rgba(0, 0, 0, 0.5); shadowBlur: 1.0; shadowVerticalOffset: 10 }

    Column {
      id: content
      anchors.centerIn: parent
      spacing: 14

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        visible: !lock.snapshotMode
        text: lock.clock("HH:mm")
        color: Color.lock.text
        font.family: Style.font.family
        font.pixelSize: Math.round(Style.font.baseSize * 6)
        font.weight: Font.DemiBold
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        visible: !lock.snapshotMode
        text: lock.date("dddd, d MMMM")
        color: lock.withAlpha(Color.lock.text, 0.75)
        font.family: Style.font.family
        font.pixelSize: Style.font.heading
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: lock.ciState !== "" && !lock.snapshotMode
        spacing: 8

        Rectangle {
          id: ciDot
          anchors.verticalCenter: parent.verticalCenter
          width: Math.round(Style.font.body * 0.6)
          height: width
          radius: width / 2
          color: lock.ciColor

          SequentialAnimation on opacity {
            running: feed.animate && lock.ciState === "running"
            loops: Animation.Infinite
            onRunningChanged: if (!running) ciDot.opacity = 1
            NumberAnimation { to: 0.3; duration: 700; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: lock.ciState === "failure" ? "a workflow failed"
            : lock.ciState === "running" ? "workflows running"
            : "all workflows passing"
          color: lock.withAlpha(Color.lock.text, 0.75)
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
      }

      Row {
        readonly property int waiting: feed.herdr.active ? feed.herdr.counts.blocked : 0
        anchors.horizontalCenter: parent.horizontalCenter
        visible: waiting > 0 && !lock.snapshotMode
        spacing: 8

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Math.round(Style.font.body * 0.6)
          height: width
          radius: width / 2
          color: feed.failureColor
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: parent.waiting === 1 ? "an agent is waiting" : parent.waiting + " agents waiting"
          color: lock.withAlpha(Color.lock.text, 0.75)
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
      }

      Item { width: 1; height: 4 }

      PasswordField {
        id: field
        lock: lock
        anchors.horizontalCenter: parent.horizontalCenter
        width: 360
        height: 58
        radius: Style.cornerRadius
        showLockGlyph: false
        placeholder: lock.tr("Enter Password")
      }
    }
  }
}
