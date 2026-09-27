import QtQuick
import qs.Commons
import "Model.js" as Model

// An installed shell plugin on the desk. A plugin with a DeskTile.qml draws
// itself in the tile (see the README's "For plugin authors"). Any other
// plugin built on the shell's Panel and KeyboardPanel lends its menu: the
// tile makes its own copy of the plugin's bar widget, tells it its menu is
// open (so it gathers its data) while the desk can be seen, keeps that
// menu's window from ever showing, and moves what the menu holds into the
// tile, scaled to fit. The plugin's own code does all of it; the tile only
// looks, since the desk takes no clicks.
Tile {
  id: root

  readonly property var info: widget ? widget.pluginInfo(entry.plugin) : null
  // The plugin works while the tile can be seen: the desk in view, or the
  // real lock screen (not the Lock Screen Explorer's thumbnails, where no
  // copy is made at all).
  readonly property bool live: root.visible && !!widget && widget.desktopShown !== false && widget.live !== false
  readonly property bool allowed: !!widget && widget.live !== false

  property var instance: null
  // The plugin's Panel (whose controller opens the menu) and its menu.
  property var panel: null
  property var menu: null
  property var moved: []
  property string failure: ""
  // The menu's whole height, scrolled parts included.
  property real fullHeight: 0
  property string builtFor: ""

  // Buttons, dropdowns and fields of a borrowed menu stay out (Model.isControl).
  readonly property bool hideControls: !widget || widget.hidePluginControls !== false

  readonly property string buildKey: info && allowed ? info.id + "|" + info.dir + "|" + info.deskTile + "|" + hideControls : ""
  onBuildKeyChanged: Qt.callLater(build)
  Component.onCompleted: Qt.callLater(build)
  Component.onDestruction: teardown()

  onLiveChanged: applyLive()
  onAnimateChanged: applyLive()

  function applyLive() {
    if (panel && menu) panel.controller.open = live
    if (instance && info && info.deskTile) {
      if (instance.live !== undefined) instance.live = live
      if (instance.animate !== undefined) instance.animate = root.animate
    }
  }

  function teardown() {
    for (var i = 0; i < moved.length; i++) if (moved[i]) moved[i].destroy()
    moved = []
    if (instance) instance.destroy()
    instance = null
    panel = null
    menu = null
  }

  function build() {
    if (buildKey === builtFor) return
    teardown()
    builtFor = buildKey
    failure = ""
    if (!info) return
    // The plugin said it has nothing for a tile.
    if (info.optOut !== null && info.optOut !== undefined) {
      failure = info.optOut || (info.name + " doesn't show in a tile")
      return
    }
    if (info.deskTile) buildDeskTile()
    else buildBorrowed()
    applyLive()
  }

  // ---- A plugin's own DeskTile.qml, in the tile's padding.
  function buildDeskTile() {
    var component = Qt.createComponent("file://" + info.dir + "/DeskTile.qml")
    if (component.status !== Component.Ready) {
      failure = "DeskTile.qml didn't load: " + component.errorString().trim().split("\n")[0]
      return
    }
    instance = component.createObject(stage)
    if (!instance) {
      failure = "DeskTile.qml couldn't be created"
      return
    }
    instance.anchors.fill = stage
    // Shown, never used: no clicks, keys or focus (it's on the lock screen too).
    instance.enabled = false
    // What the tile offers, where the DeskTile asks for it.
    if (instance.bar !== undefined) instance.bar = widget.deskBar
    if (instance.settings !== undefined) instance.settings = widget.pluginSettings(info.id)
  }

  // ---- Any other plugin: its menu, borrowed.
  function buildBorrowed() {
    var component = Qt.createComponent("file://" + info.dir + "/" + info.barWidget)
    if (component.status !== Component.Ready) {
      failure = "The plugin didn't load: " + component.errorString().trim().split("\n")[0]
      return
    }
    instance = component.createObject(hiddenHost, { bar: widget.deskBar, moduleName: info.id, settings: widget.pluginSettings(info.id) })
    if (!instance) {
      failure = "The plugin couldn't be created"
      return
    }
    silence(instance, 0)
    // The Panel is the widget itself, or loaded inside it (a BarWidget with
    // a Loader for Panel.qml, like Weather).
    panel = findPanel(instance, 0)
    menu = panel ? findMenu(panel, 0) : null
    if (!menu) {
      failure = "This plugin has no menu the tile can show"
      return
    }
    // Before it's ever open: the window stays unmapped, so it never shows
    // and never takes the keyboard, and it opens no catchers on other screens.
    menu.visible = false
    for (var i = 0; i < menu.data.length; i++) {
      if (String(menu.data[i]).indexOf("Variants") === 0) menu.data[i].model = []
    }
    var items = []
    for (var j = 0; j < menu.contentItem.length; j++) items.push(menu.contentItem[j])
    for (var k = 0; k < items.length; k++) items[k].parent = holder
    moved = items
    fullHeight = 0
    Qt.callLater(measure)
  }

  // ---- The whole height: a popup is capped at the screen and scrolls the
  //      rest, but the tile shows all of it. Measured now and then rather
  //      than bound, since what fills the holder follows its height.

  function naturalHeight(item, depth) {
    if (!item || depth > 8 || item.visible === false) return 0
    var h = Math.max(item.implicitHeight || 0, item.childrenRect ? item.childrenRect.height : 0)
    // A Flickable or list: all it scrolls through.
    if (typeof item.contentHeight === "number" && item.contentY !== undefined && item.contentHeight > item.height)
      h = Math.max(h, item.contentHeight + (item.topMargin || 0) + (item.bottomMargin || 0))
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) h = Math.max(h, (kids[i].y || 0) + naturalHeight(kids[i], depth + 1))
    return h
  }

  // Hides the controls in what the menu holds; run with each measure, since
  // a plugin makes more as its data comes in.
  function hideControlsIn(item, depth) {
    if (!item || depth > 12) return
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) {
      if (!kids[i].visible) continue
      if (Model.isControl(kids[i])) kids[i].visible = false
      else hideControlsIn(kids[i], depth + 1)
    }
  }

  function measure() {
    if (hideControls) for (var j = 0; j < moved.length; j++) {
      if (!moved[j]) continue
      if (Model.isControl(moved[j])) moved[j].visible = false
      else hideControlsIn(moved[j], 0)
    }
    var h = 0
    for (var i = 0; i < moved.length; i++) if (moved[i]) h = Math.max(h, (moved[i].y || 0) + naturalHeight(moved[i], 0))
    // What fills the holder measures as the holder, so this settles; it
    // must never add anything to what it measured, or the scale would creep.
    if (Math.abs(h - fullHeight) > 2) fullHeight = h
  }

  Timer {
    running: !!root.menu && root.live
    repeat: true
    triggeredOnStart: true
    interval: 1000
    onTriggered: root.measure()
  }

  // What an object holds: its children and resources, and a Loader's item.
  function partsOf(object) {
    var out = []
    var list = object.data || []
    for (var i = 0; i < list.length; i++) out.push(list[i])
    if (object.item && out.indexOf(object.item) === -1) out.push(object.item)
    return out
  }

  // The shell's Panel: it has the controller that opens the menu.
  function findPanel(object, depth) {
    if (!object || depth > 4) return null
    if (object.controller && object.controller.open !== undefined && typeof object.controller.show === "function") return object
    var parts = partsOf(object)
    for (var i = 0; i < parts.length; i++) {
      var found = findPanel(parts[i], depth + 1)
      if (found) return found
    }
    return null
  }

  // The menu: the shell's KeyboardPanel, by what only it has.
  function findMenu(object, depth) {
    if (!object || depth > 3) return null
    if (typeof object.fittedContentWidth === "function" && object.contentItem !== undefined && object.focusPrimed !== undefined) return object
    var parts = partsOf(object)
    for (var i = 0; i < parts.length; i++) {
      var found = findMenu(parts[i], depth + 1)
      if (found) return found
    }
    return null
  }

  // The real widget keeps the plugin's IPC; the copy's handlers go quiet.
  function silence(object, depth) {
    if (!object || depth > 4) return
    if (String(object).indexOf("IpcHandler") === 0) object.enabled = false
    var parts = partsOf(object)
    for (var i = 0; i < parts.length; i++) silence(parts[i], depth + 1)
  }

  component Label: Text {
    textFormat: Text.PlainText
    color: root.fg
    font.family: root.family
    font.pixelSize: root.bodySize
    elide: Text.ElideRight
    maximumLineCount: 1
  }

  // Where the copy lives: never shown.
  Item {
    id: hiddenHost
    visible: false
    width: 0
    height: 0
  }

  Row {
    id: header
    spacing: root.statSize * 0.5

    Label {
      anchors.baseline: nameLabel.baseline
      text: ""
      color: Color.accent
      font.pixelSize: root.statSize
    }
    Label {
      id: nameLabel
      text: root.info ? root.info.name : (root.entry.plugin || "Plugin")
      color: root.dim
      font.pixelSize: root.smallSize
      font.letterSpacing: root.smallSize * 0.12
      font.capitalization: Font.AllUppercase
    }
  }

  Item {
    id: stage
    anchors.top: header.bottom
    anchors.topMargin: root.statSize * 0.6
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    clip: true

    // The menu's content at the width the plugin laid it out for and its
    // whole height (see naturalHeight), scaled so all of it fits the tile,
    // at the top and centered across.
    Item {
      id: holder
      visible: !!root.menu
      // Shown, never used: a menu brings its clickable rows and key handling
      // (ending processes, switching networks), and on the lock screen
      // anyone could reach them, or it could take the keyboard from the
      // password field. Disabled, nothing in it gets a click, a key or focus.
      enabled: false
      width: root.menu ? root.menu.contentWidth : 0
      height: root.menu ? Math.max(root.menu.contentHeight, root.fullHeight) : 0
      transformOrigin: Item.TopLeft
      // A little room under the last row, which measuring can come up short on.
      readonly property real room: Style.space(8)
      scale: width > 0 && height > 0 && stage.width > 0 && stage.height > room ? Math.min(stage.width / width, (stage.height - room) / height, 2.5) : 1
      x: (stage.width - width * scale) / 2
      y: 0
    }
  }

  Label {
    visible: text !== ""
    anchors.centerIn: stage
    width: stage.width
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.Wrap
    maximumLineCount: 4
    // The plugin's own word that it has nothing to show is no failure.
    color: root.failure && !(root.info && root.info.optOut !== null && root.info.optOut !== undefined)
      ? (widget ? widget.failureColor : Color.urgent) : root.dim
    text: !root.entry.plugin ? "Pick a plugin in the settings"
      : !root.info ? "Plugin not installed: " + root.entry.plugin
      : root.failure
  }
}
