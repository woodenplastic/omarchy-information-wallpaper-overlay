import QtQuick
import QtQuick.Shapes
import qs.Commons

// The frame the agents and music tiles share with the repo tiles: the
// theme's background at the tiles' opacity, Hyprland's rounding, a soft
// accent glow, and type that scales with the tile. What a tile puts in it
// goes inside the padding.
Rectangle {
  id: root

  property var widget: null
  property var entry: ({})

  // Where the glow centers.
  property real glowX: width / 2
  property real glowY: height / 2

  default property alias content: inner.data
  readonly property Item area: inner

  // Whether the desk this tile is on can be seen; a desk per display.
  property bool shown: true
  readonly property real nowMs: widget ? widget.nowMs : Date.now()
  readonly property bool animate: !!widget && widget.animate && shown
  // The desk's pulse clock (Model.breathe).
  readonly property real pulseMs: widget && widget.pulseMs !== undefined ? widget.pulseMs : 0

  readonly property color fg: Color.foreground
  readonly property color dim: Util.alpha(Color.foreground, 0.55)
  readonly property color faint: Util.alpha(Color.foreground, 0.12)
  readonly property string family: Style.font.family
  readonly property bool rounded: !!widget && widget.rounding > 0

  color: Util.alpha(Color.background, widget ? widget.tileOpacity : 0.2)
  radius: widget ? widget.rounding : 0
  clip: true

  // ---- Scale: the body size follows the tile, about as large as a repo
  //      tile's of the same size.
  readonly property real pad: Math.max(Style.space(16), Math.min(width, height) * 0.05)
  readonly property real unit: Util.clamp(Math.min(width / 88, height / 48), Style.font.body, 19)

  readonly property real smallSize: Math.max(Style.font.caption, unit * 0.83)
  readonly property real bodySize: unit
  readonly property real statSize: Math.max(Style.font.subtitle, unit * 1.18)
  readonly property real titleSize: Math.max(Style.font.heading, unit * 1.8)

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeWidth: -1
      startX: 0; startY: 0
      fillGradient: RadialGradient {
        centerX: root.glowX
        centerY: root.glowY
        centerRadius: Math.max(root.width, root.height) * 0.62
        focalX: centerX
        focalY: centerY
        GradientStop { position: 0; color: Util.alpha(Color.accent, 0.2) }
        GradientStop { position: 0.45; color: Util.alpha(Color.accent, 0.07) }
        GradientStop { position: 1; color: Util.alpha(Color.accent, 0) }
      }
      PathLine { x: root.width; y: 0 }
      PathLine { x: root.width; y: root.height }
      PathLine { x: 0; y: root.height }
      PathLine { x: 0; y: 0 }
    }
  }

  Item {
    id: inner
    anchors.fill: parent
    anchors.margins: root.pad
  }
}
