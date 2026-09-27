import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "Model.js" as Model

// The tiles on the first monitor's desktop: a layer between the
// wallpaper and the windows, filling the area the bar leaves free, with
// Hyprland's gap between tiles and its rounding. Clicks pass through.
PanelWindow {
  id: root

  property var widget: null

  screen: widget ? widget.primaryScreen : null
  visible: !!widget
  color: "transparent"

  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Normal
  exclusiveZone: 0

  WlrLayershell.layer: WlrLayer.Bottom
  WlrLayershell.namespace: "information-wallpaper-overlay"
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  // No input region: the desk never takes a click or the pointer.
  mask: Region {}

  // Hyprland puts gaps_in around each window, so neighbors sit twice apart.
  readonly property int gap: widget ? widget.gapsIn * 2 : 10
  readonly property var rects: widget ? Model.tileRects(widget.tiles.length, area.width, area.height, gap) : []

  Item {
    id: area
    anchors.fill: parent
    // Drawn only while it can be seen: covered by windows, nothing here is
    // painted, and tiles that follow their visibility (plugin copies, live
    // workspaces, the music clock) rest. Otherwise every clock tick or new
    // sample would repaint the whole desk behind the windows.
    visible: !root.widget || root.widget.desktopShown

    Repeater {
      model: root.widget ? root.widget.tiles.length : 0

      TileView {
        required property int index
        readonly property var rect: root.rects[index] || { x: 0, y: 0, w: 0, h: 0 }

        x: Math.round(rect.x)
        y: Math.round(rect.y)
        width: Math.round(rect.w)
        height: Math.round(rect.h)

        widget: root.widget
        entry: root.widget.tiles[index]
      }
    }
  }
}
