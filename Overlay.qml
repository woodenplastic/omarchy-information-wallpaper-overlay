import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Information Wallpaper Overlay: the bar icon with the CI status dot, the
// settings popup, and the tiles on the desktop (Desk.qml): GitHub repos,
// herdr's agents, what's playing and the long tasks on the machine.
//
// The bar has one instance of this widget per monitor. The one on the first
// monitor fetches (scripts/fetch through the gh CLI) and draws the desk; the
// fetch lands in a cache file that every instance watches, so each bar's dot
// agrees and the desk shows the last data right after a shell restart.
BarWidget {
  id: root
  moduleName: "woodenplastic.information-wallpaper-overlay"

  // ---- Settings. shell.json is the source: the widget reads its own entry
  //      from the file, since the shell's hand-over can lag behind changes
  //      made outside it. A change from the popup applies at once, then goes
  //      to the file.

  property var fileSettings: null
  readonly property var effectiveSettings: fileSettings || settings || ({})

  FileView {
    id: shellConfigFile
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.readShellConfig(text())
  }

  // Plugin tiles leave out the menus' buttons, dropdowns and fields.
  readonly property bool hidePluginControls: option("hidePluginControls", true) === true

  // The whole file too, for the settings of plugins shown in tiles.
  property string shellConfigText: ""

  function readShellConfig(text) {
    root.shellConfigText = text
    var next = Model.barEntry(text, root.moduleName)
    if (next && JSON.stringify(next) !== JSON.stringify(root.fileSettings)) root.fileSettings = next
  }

  function option(name, fallback) {
    var value = effectiveSettings[name]
    return value === undefined || value === null ? fallback : value
  }

  // The six slots as set in the popup, and the filled ones, which the desk shows.
  readonly property var slots: Model.slotList(option("tiles", []))
  readonly property var tiles: Model.tileList(option("tiles", []))
  readonly property var repos: Model.reposOf(tiles)
  // Set while the settings slider is dragged, so the tiles follow it before
  // the value is saved; NaN otherwise.
  property real previewOpacity: NaN
  readonly property real tileOpacity: Util.clamp(Number(isNaN(previewOpacity) ? option("opacity", 0.2) : previewOpacity), 0, 1)
  readonly property bool animations: option("animations", true) === true
  // The icon behind the tray's arrow instead of on the bar.
  readonly property bool inTray: option("inTray", true) === true
  readonly property var specs: repos.map(Model.specOf)

  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")

  function setSetting(key, value) {
    var entry = {}
    for (var k in root.effectiveSettings) entry[k] = root.effectiveSettings[k]
    entry[key] = value
    root.fileSettings = entry
    Util.execArgv([root.pluginDir + "/scripts/config", "set", key, JSON.stringify(value)])
  }

  // ---- Which instance leads: the one on the first monitor.

  // The attached window isn't there yet while the bar builds its widgets
  // and doesn't notify when it arrives, so the screen is looked up until found.
  property string widgetScreenName: ""
  readonly property var primaryScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
  readonly property bool isPrimary: widgetScreenName !== "" && !!primaryScreen && widgetScreenName === primaryScreen.name

  function resolveScreen() {
    var window = root.QsWindow.window
    root.widgetScreenName = window && window.screen ? String(window.screen.name || "") : ""
    return root.widgetScreenName !== ""
  }

  Timer {
    id: screenLookup
    interval: 250
    repeat: true
    running: true
    onTriggered: if (root.resolveScreen()) stop()
  }

  Connections {
    target: Quickshell
    function onScreensChanged() {
      root.widgetScreenName = ""
      screenLookup.restart()
    }
  }

  // ---- Data.

  readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/information-wallpaper-overlay"
  readonly property string cachePath: cacheDir + "/data.json"

  property var results: []
  property string fetchedAt: ""
  property string fetchError: ""
  readonly property bool fetching: fetchProc.running

  // Ticks relative times ("5m") and the running-run durations along.
  property real nowMs: Date.now()

  readonly property var shownResults: repos.map(function(entry) { return Model.resultFor(root.results, entry) })
  readonly property bool anyRunning: shownResults.some(function(r) { return Model.isRunning(r) })
  // The last fetch couldn't reach GitHub (see scripts/fetch).
  readonly property bool offline: shownResults.some(function(r) { return !!r && r.offline === true })
  readonly property string ciState: Model.overallState(shownResults)

  function fetch() {
    if (!root.isPrimary || root.specs.length === 0) return
    if (fetchProc.running) {
      fetchProc.again = true
      return
    }
    fetchProc.command = ["bash", root.pluginDir + "/scripts/fetch", root.cachePath].concat(root.specs)
    fetchProc.running = true
  }

  Process {
    id: fetchProc
    property bool again: false
    stderr: StdioCollector {
      id: fetchStderr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.fetchError = exitCode === 0 ? "" : (String(fetchStderr.text || "").trim() || "Fetching failed")
      cacheFile.reload()
      if (again) {
        again = false
        Qt.callLater(root.fetch)
      }
    }
  }

  FileView {
    id: cacheFile
    path: root.cachePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var data
      try { data = JSON.parse(text()) } catch (e) { return }
      if (!data || !Array.isArray(data.results)) return
      root.results = data.results
      root.fetchedAt = String(data.fetched || "")
      root.trackRuns()
    }
  }

  // ---- Live workflow view. A tile shows the runs going on in place of its
  //      commits, and a run that ended keeps showing its result for a minute
  //      after the desk sees it end. Only runs seen running count, so a
  //      restart doesn't bring back ones that are long over.

  property var runsSeen: ({})

  function trackRuns() {
    root.runsSeen = Model.trackRuns(root.results, root.runsSeen, Date.now())
  }

  function liveRuns(result) {
    return Model.liveRuns(result, root.runsSeen, root.nowMs)
  }

  readonly property bool anyLive: shownResults.some(function(r) { return root.liveRuns(r).length > 0 })

  // ---- herdr's agents, for an agents tile.

  HerdrFeed {
    id: herdrFeed
    active: root.isPrimary && Model.hasKind(root.tiles, "herdr")
  }

  readonly property var herdr: herdrFeed

  // ---- Long tasks, for a tasks tile (scripts/tasks), and the shell hook
  //      that tells whether terminal commands passed (scripts/shell-hook):
  //      "on", "off", "" until asked. Asked again when the popup opens.

  TasksFeed {
    id: tasksWatcher
    active: root.isPrimary && Model.hasKind(root.tiles, "tasks")
    tools: Model.taskTools(root.tiles)
  }

  readonly property var tasksFeed: tasksWatcher

  property string shellHook: ""

  function refreshShellHook() {
    if (shellHookProc.running) return
    shellHookProc.command = ["bash", root.pluginDir + "/scripts/shell-hook", "status"]
    shellHookProc.running = true
  }

  function setShellHook(on) {
    if (shellHookProc.running) return
    shellHookProc.command = ["bash", root.pluginDir + "/scripts/shell-hook", on ? "on" : "off"]
    shellHookProc.running = true
  }

  Process {
    id: shellHookProc
    stdout: StdioCollector { id: shellHookOut; waitForEnd: true }
    onExited: {
      if (command[2] === "status") root.shellHook = String(shellHookOut.text || "").trim()
      else Qt.callLater(root.refreshShellHook)
    }
  }

  // ---- Windows and monitors, for workspace tiles.

  WorkspaceFeed {
    id: workspaceWatcher
    active: root.isPrimary && Model.hasKind(root.tiles, "workspace")
  }

  readonly property var workspaceFeed: workspaceWatcher

  // A workspace on the visible desk runs at 60 fps: Hyprland draws windows
  // on hidden workspaces at misc:render_unfocused_fps (15 unless set), so
  // that's raised while one is in view and put back once none is
  // (scripts/unfocused-fps, which the lock screen shares).
  readonly property bool smoothWorkspaces: root.isPrimary && root.desktopShown && Model.hasKind(root.tiles, "workspace")

  function applySmoothWorkspaces() {
    Util.execArgv(["bash", root.pluginDir + "/scripts/unfocused-fps", root.smoothWorkspaces ? "raise" : "restore", "desk", "60"])
  }

  onSmoothWorkspacesChanged: applySmoothWorkspaces()
  Component.onDestruction: if (root.isPrimary) Util.execArgv(["bash", root.pluginDir + "/scripts/unfocused-fps", "restore", "desk"])

  // ---- Installed plugins, for plugin tiles (PluginTile, scripts/plugins):
  //      listed at the start and when the popup opens.

  property var installedPlugins: []
  // Listed once: before that, a plugin tile can't tell a missing plugin.
  property bool pluginsListed: false

  function refreshPlugins() {
    if (pluginsProc.running) return
    pluginsProc.command = ["bash", root.pluginDir + "/scripts/plugins"]
    pluginsProc.running = true
  }

  Process {
    id: pluginsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var list
        try { list = JSON.parse(text) } catch (e) { return }
        if (Array.isArray(list) && JSON.stringify(list) !== JSON.stringify(root.installedPlugins)) root.installedPlugins = list
        root.pluginsListed = true
      }
    }
  }

  function pluginInfo(id) {
    for (var i = 0; i < root.installedPlugins.length; i++) if (root.installedPlugins[i].id === id) return root.installedPlugins[i]
    return null
  }

  // A plugin's own entry on the bar in shell.json, as it gets it there.
  function pluginSettings(id) {
    return Model.barEntry(root.shellConfigText, id) || ({})
  }

  // The bar plugins in tiles get: the real one's look, none of its popups.
  DeskBar {
    id: deskBarObject
    real: root.bar
  }

  readonly property var deskBar: deskBarObject

  // ---- What's playing, for a music tile: the shell's media service, so the
  //      tile shows the player the bar's media widget shows.

  readonly property var mediaService: root.bar && root.bar.shell && typeof root.bar.shell.firstPartyServiceFor === "function"
    ? root.bar.shell.firstPartyServiceFor("omarchy.media") : null

  // ---- The repos the gh login can pick from (own and organizations'), for
  //      the settings popup's suggestions. Listed again when the popup opens
  //      and the list is older than ten minutes.

  readonly property string choicesPath: cacheDir + "/repos.json"
  property var repoChoices: []
  property real choicesFetchedMs: 0
  readonly property bool listingRepos: choicesProc.running

  function refreshRepoChoices() {
    if (choicesProc.running || Date.now() - root.choicesFetchedMs < 600000) return
    choicesProc.command = ["bash", root.pluginDir + "/scripts/repos", root.choicesPath]
    choicesProc.running = true
  }

  Process {
    id: choicesProc
    onExited: choicesFile.reload()
  }

  FileView {
    id: choicesFile
    path: root.choicesPath
    printErrors: false
    onLoaded: {
      var data
      try { data = JSON.parse(text()) } catch (e) { return }
      if (!data || !Array.isArray(data.repos)) return
      root.repoChoices = data.repos
      var t = Date.parse(data.fetched)
      root.choicesFetchedMs = isFinite(t) ? t : 0
    }
  }

  // ---- On the lock screen, as a Lock Screen Explorer design
  //      (scripts/lock-design): "on", "off", "missing" without the explorer,
  //      "" until asked. Asked again when the popup opens.

  property string lockDesign: ""
  property string lockDesignError: ""
  readonly property bool lockDesignBusy: lockDesignProc.running

  function refreshLockDesign() {
    if (lockDesignProc.running) return
    lockDesignProc.command = ["bash", root.pluginDir + "/scripts/lock-design", "status"]
    lockDesignProc.running = true
  }

  function setLockDesign(on) {
    if (lockDesignProc.running) return
    root.lockDesignError = ""
    lockDesignProc.command = ["bash", root.pluginDir + "/scripts/lock-design", on ? "on" : "off"]
    lockDesignProc.running = true
  }

  Process {
    id: lockDesignProc
    stdout: StdioCollector { id: lockDesignOut; waitForEnd: true }
    stderr: StdioCollector { id: lockDesignErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (command[2] === "status") {
        root.lockDesign = String(lockDesignOut.text || "").trim()
        return
      }
      if (exitCode !== 0) root.lockDesignError = String(lockDesignErr.text || "").trim() || "Couldn't change the lock screen"
      Qt.callLater(root.refreshLockDesign)
    }
  }

  // Every 5 minutes, every 30 seconds while a workflow runs, every minute
  // while GitHub can't be reached (as early in a boot, before the network).
  Timer {
    running: root.isPrimary && root.specs.length > 0
    repeat: true
    interval: root.anyRunning ? 30000 : root.offline ? 60000 : 300000
    onTriggered: root.fetch()
  }

  // Changed repos fetch right away, once the edits settle.
  Timer {
    id: refetchSoon
    interval: 400
    onTriggered: root.fetch()
  }

  onSpecsChanged: refetchSoon.restart()
  onIsPrimaryChanged: if (isPrimary) {
    refetchSoon.restart()
    // Letting go at the start too clears claims a crashed shell left; a
    // desk that shows a workspace raises it through smoothWorkspaces.
    if (!smoothWorkspaces) applySmoothWorkspaces()
  }

  // The fetch replaces the cache by renaming a new file over it, which a
  // file watch can lose track of, so the tick reads it again too. That's how
  // the instances on other monitors follow along.
  property int reloadTicks: 0

  // Every second while a live view counts up its durations.
  Timer {
    running: true
    repeat: true
    interval: root.anyLive ? 1000 : 30000
    onTriggered: {
      root.nowMs = Date.now()
      if (!fetchProc.running && (!root.anyLive || ++reloadTicks % 30 === 0)) cacheFile.reload()
    }
  }

  // ---- Theme and Hyprland look. Color follows theme switches on its own;
  //      the run colors and the window geometry are read along with it.

  readonly property string themeColorsPath: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"

  property var statusColors: ({ success: "", running: "", failure: "" })
  readonly property color successColor: statusColors.success || "#9ece6a"
  readonly property color runningColor: statusColors.running || "#e0af68"
  readonly property color failureColor: statusColors.failure || Color.urgent

  property int gapsIn: 5
  property int rounding: 0

  FileView {
    id: themeColorsFile
    path: root.themeColorsPath
    printErrors: false
    onLoaded: root.statusColors = Model.statusColors(text())
  }

  Process {
    id: hyprOptions
    command: ["bash", "-c", "for o in general:gaps_in decoration:rounding; do hyprctl -j getoption \"$o\"; done | jq -cs ."]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.readHyprOptions(text)
    }
  }

  function readHyprOptions(raw) {
    var look = Model.hyprLook(raw)
    if (!look) return
    root.gapsIn = look.gapsIn
    root.rounding = look.rounding
  }

  function refreshLook() {
    themeColorsFile.reload()
    if (!hyprOptions.running) hyprOptions.running = true
  }

  // A theme switch reaches Color over IPC after its files are in place, and
  // reloads Hyprland's config; either way the look is read again.
  Timer {
    id: lookSoon
    interval: 300
    onTriggered: root.refreshLook()
  }

  Connections {
    target: Color
    function onAccentChanged() { lookSoon.restart() }
    function onBackgroundChanged() { lookSoon.restart() }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "configreloaded") lookSoon.restart()
      if (/^(openwindow|closewindow|movewindow|workspace|moveworkspace|focusedmon)/.test(event.name)) windowsSoon.restart()
    }
  }

  // Quickshell learns which windows are on which workspace only from the
  // events it sees, so after a shell restart it takes a covered desk for an
  // empty one. Asked at the start and after window events, so the desk knows
  // when windows cover it (for the animations, plugin tiles and 60 fps).
  Timer {
    id: windowsSoon
    interval: 150
    onTriggered: {
      Hyprland.refreshWorkspaces()
      Hyprland.refreshToplevels()
    }
  }

  Component.onCompleted: {
    windowsSoon.restart()
    refreshLook()
    refreshPlugins()
    refetchSoon.restart()
  }

  // Sparks and breathing run only while the desk can be seen: no windows on
  // the first monitor's workspace.
  readonly property var deskMonitor: primaryScreen ? Hyprland.monitorFor(primaryScreen) : null
  readonly property bool desktopShown: !!deskMonitor && !!deskMonitor.activeWorkspace
    && deskMonitor.activeWorkspace.toplevels.values.length === 0
  readonly property bool animate: animations && desktopShown

  // ---- Desk: the tiles on the first monitor's desktop.

  Loader {
    active: root.isPrimary && root.tiles.length > 0
    source: Qt.resolvedUrl("Desk.qml")
    onLoaded: item.widget = root
  }

  // ---- Settings popup, with the shape the bar routes panels by.

  readonly property bool opened: settingsLoader.item ? settingsLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: settingsLoader.item ? settingsLoader.item.popoutSwitchClosing === true : false

  function open() { if (settingsLoader.item) settingsLoader.item.open() }
  function close() { if (settingsLoader.item) settingsLoader.item.close() }
  function toggle() { if (settingsLoader.item) settingsLoader.item.toggle() }
  function closeForPopoutSwitch() { if (settingsLoader.item) settingsLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = settingsLoader.item
    if (!target) return
    target.bar = root.bar
    target.anchorItem = root.anchorAtPoint ? pointAnchor : button
    target.hostWidget = root
  }

  onBarChanged: injectPanel()
  onAnchorAtPointChanged: injectPanel()

  // ---- In the tray. The helper (scripts/tray-icon) puts a tray icon up and,
  //      when it's clicked, calls toggleAt with the cursor position; the
  //      popup opens under a 1px anchor there. The icon carries the CI dot,
  //      drawn in the theme's colors sent over its stdin.

  property bool anchorAtPoint: false
  readonly property var barWindow: root.QsWindow.window

  Item {
    id: pointAnchor
    parent: root.barWindow ? root.barWindow.contentItem : root
    width: 1
    height: 1
  }

  function toggleAtPoint(x, y) {
    if (root.opened) {
      root.close()
      return
    }
    var screen = root.barWindow ? root.barWindow.screen : null
    pointAnchor.x = x - (screen ? screen.x : 0)
    pointAnchor.y = y - (screen ? screen.y : 0)
    root.anchorAtPoint = true
    root.injectPanel()
    root.open()
  }

  function toggleHere() {
    if (root.opened) {
      root.close()
      return
    }
    root.anchorAtPoint = false
    root.injectPanel()
    root.open()
  }

  function screenContains(item, x, y) {
    var window = item && item.QsWindow ? item.QsWindow.window : null
    var screen = window ? window.screen : null
    return !!screen && x >= screen.x && x < screen.x + screen.width && y >= screen.y && y < screen.y + screen.height
  }

  // The bar on the monitor under the point opens it; there's a widget per
  // monitor, and the first monitor's owns the IPC target.
  function routeToggleAt(x, y) {
    var widgets = root.bar && typeof root.bar.moduleWidgets === "function" ? root.bar.moduleWidgets(root.moduleName) : [root]
    for (var i = 0; i < widgets.length; i++) {
      if (widgets[i] && widgets[i].toggleAtPoint && root.screenContains(widgets[i], x, y)) {
        widgets[i].toggleAtPoint(x, y)
        return
      }
    }
    root.toggleAtPoint(x, y)
  }

  IpcHandler {
    enabled: root.isPrimary
    target: root.moduleName

    function toggle(): void { root.toggleHere() }
    function toggleAt(x: string, y: string): void { root.routeToggleAt(Number(x), Number(y)) }
    function refresh(): void { root.fetch() }
  }

  function hexOf(c) {
    function part(v) { var h = Math.round(Util.clamp(v, 0, 1) * 255).toString(16); return h.length < 2 ? "0" + h : h }
    return "#" + part(c.r) + part(c.g) + part(c.b)
  }

  readonly property color markColor: root.bar ? root.bar.barForeground : Color.foreground
  readonly property string trayIconLine: "icon " + (root.ciState || "none") + " " + hexOf(root.markColor) + " " + hexOf(root.dotColor) + "\n"
  readonly property string trayTooltipLine: "tooltip " + root.statusText.replace(/\n/g, " ") + "\n"

  function sendTray() {
    if (!trayProc.running) return
    trayProc.write(root.trayIconLine)
    trayProc.write(root.trayTooltipLine)
  }

  onTrayIconLineChanged: sendTray()
  onTrayTooltipLineChanged: sendTray()

  Process {
    id: trayProc
    running: root.isPrimary && root.inTray
    stdinEnabled: true
    command: ["/usr/bin/python3", root.pluginDir + "/scripts/tray-icon"]
    onStarted: root.sendTray()
  }

  Loader {
    id: settingsLoader
    active: true
    source: Qt.resolvedUrl("Settings.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // ---- The bar icon.

  // In the tray, the bar keeps the widget (it draws the desk) at no width.
  implicitWidth: root.inTray ? 0 : button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property color dotColor: ciState === "failure" ? failureColor
    : ciState === "running" ? runningColor
    : successColor

  readonly property string ciText: {
    if (root.ciState === "failure") return "a workflow failed"
    if (root.ciState === "running") return "workflows running"
    if (root.ciState === "success") return "all workflows passing"
    return ""
  }

  readonly property int agentsWaiting: herdrFeed.active ? herdrFeed.counts.blocked : 0
  readonly property int tasksFailed: tasksWatcher.active ? tasksWatcher.counts.failure : 0

  readonly property string statusText: {
    if (root.tiles.length === 0) return "no tiles yet"
    var parts = [
      root.ciText,
      root.agentsWaiting === 0 ? "" : root.agentsWaiting === 1 ? "an agent is waiting" : root.agentsWaiting + " agents waiting",
      root.tasksFailed === 0 ? "" : root.tasksFailed === 1 ? "a task failed" : root.tasksFailed + " tasks failed"
    ]
    parts = parts.filter(function(s) { return s })
    if (parts.length > 0) return parts.join(", ")
    return root.tiles.length === 1 ? "1 tile" : root.tiles.length + " tiles"
  }

  BarIconButton {
    id: button
    visible: !root.inTray
    anchors.fill: parent
    bar: root.bar
    text: "\uf009"
    tooltipText: root.opened ? "" : "Information Wallpaper Overlay: " + root.statusText
    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.fetch()
      else root.toggleHere()
    }

    Rectangle {
      id: dot
      visible: root.ciState !== ""
      width: Math.max(4, Math.round(Style.bar.iconCanvas * 0.36))
      height: width
      radius: width / 2
      color: root.dotColor
      border.width: Math.max(1, Math.round(width * 0.2))
      border.color: root.bar && root.bar.background !== undefined ? root.bar.background : Color.background
      x: Math.round(parent.width / 2 + Style.bar.iconCanvas / 2 - width * 0.7)
      y: Math.round(parent.height / 2 + Style.bar.iconCanvas / 2 - height * 0.7)

      SequentialAnimation on opacity {
        running: root.ciState === "running"
        loops: Animation.Infinite
        onRunningChanged: if (!running) dot.opacity = 1
        NumberAnimation { to: 0.3; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
      }
    }
  }
}
