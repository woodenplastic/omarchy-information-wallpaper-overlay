import QtQuick
import qs.Commons

// The bar a borrowed plugin (PluginTile) is given: the real bar's colors,
// fonts, sizes and shell services, so the plugin looks and works as on the
// bar, but none of its popup coordination or tooltips. Its menu never
// becomes the bar's open popout, and never closes the real ones.
QtObject {
  id: root

  property var real: null

  readonly property var shell: real ? real.shell : null
  readonly property color foreground: real ? real.foreground : Color.foreground
  readonly property color barForeground: real ? real.barForeground : Color.foreground
  readonly property color background: real && real.background !== undefined ? real.background : Color.background
  readonly property color urgent: real && real.urgent !== undefined ? real.urgent : Color.urgent
  readonly property string fontFamily: real ? real.fontFamily : Style.font.family
  readonly property var iconFont: pick("iconFont", undefined)
  readonly property int barSize: pick("barSize", Style.bar.sizeHorizontal)
  readonly property int sizeHorizontal: pick("sizeHorizontal", Style.bar.sizeHorizontal)
  readonly property real iconCanvas: pick("iconCanvas", Style.bar.iconCanvas)
  readonly property real iconSlot: pick("iconSlot", Style.bar.iconCanvas)
  readonly property real statusSlot: pick("statusSlot", Style.bar.iconCanvas)
  readonly property bool vertical: false
  readonly property string position: pick("position", "top")
  readonly property real x: 0
  readonly property bool foregroundAnimationEnabled: false

  readonly property var clickTargets: []
  readonly property string activePopout: ""

  // The real bar's value, where it has one.
  function pick(name, fallback) {
    var value = real ? real[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function run() { return real && typeof real.run === "function" ? real.run.apply(real, arguments) : undefined }
  function requestPopout(key) {}
  function releasePopout(key) {}
  function switchPanelFrom(widget, direction) { return false }
  function moduleWidgets(id) { return [] }
  function targetBelongsToWindow(target, window) { return false }
  function showTooltip() {}
  function hideTooltip() {}
}
