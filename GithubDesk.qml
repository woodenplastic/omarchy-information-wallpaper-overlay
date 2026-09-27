import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// GitHub Desk: the bar icon with the CI status dot, the settings popup, and
// the repo tiles on the desktop (Desk.qml).
//
// The bar has one instance of this widget per monitor. The one on the first
// monitor fetches (scripts/fetch through the gh CLI) and draws the desk; the
// fetch lands in a cache file that every instance watches, so each bar's dot
// agrees and the desk shows the last data right after a shell restart.
BarWidget {
  id: root
  moduleName: "woodenplastic.github-desk"

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

  function readShellConfig(text) {
    var config
    try { config = JSON.parse(text) } catch (e) { return }
    var layout = config && config.bar && config.bar.layout ? config.bar.layout : {}
    for (var section in layout) {
      var entries = Array.isArray(layout[section]) ? layout[section] : []
      for (var i = 0; i < entries.length; i++) {
        var entry = entries[i]
        if (!entry || entry.id !== root.moduleName) continue
        var next = {}
        for (var k in entry) if (k !== "id") next[k] = entry[k]
        if (JSON.stringify(next) !== JSON.stringify(root.fileSettings)) root.fileSettings = next
        return
      }
    }
  }

  function option(name, fallback) {
    var value = effectiveSettings[name]
    return value === undefined || value === null ? fallback : value
  }

  readonly property var repos: Model.repoList(option("repos", []))
  readonly property real tileOpacity: Util.clamp(Number(option("opacity", 0.2)), 0, 1)
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

  readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/omarchy-github-desk"
  readonly property string cachePath: cacheDir + "/data.json"

  property var results: []
  property string fetchedAt: ""
  property string fetchError: ""
  readonly property bool fetching: fetchProc.running

  // Ticks relative times ("5m") and the running-run durations along.
  property real nowMs: Date.now()

  readonly property var shownResults: repos.map(function(entry) { return Model.resultFor(root.results, entry) })
  readonly property bool anyRunning: shownResults.some(function(r) { return Model.isRunning(r) })
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

  readonly property int holdMs: 60000
  // run id -> { running: true } while running, { endedMs } once seen ending.
  property var runsSeen: ({})

  function trackRuns() {
    var next = {}
    for (var i = 0; i < root.results.length; i++) {
      var runs = root.results[i] && root.results[i].runs ? root.results[i].runs : []
      for (var j = 0; j < runs.length; j++) {
        var run = runs[j]
        var before = root.runsSeen[run.id]
        if (run.status !== "completed") next[run.id] = { running: true }
        else if (before && before.running) next[run.id] = { endedMs: Date.now() }
        else if (before && before.endedMs) next[run.id] = before
      }
    }
    root.runsSeen = next
  }

  function liveRuns(result) {
    var runs = result && result.ok && result.runs ? result.runs : []
    var out = []
    for (var i = 0; i < runs.length; i++) {
      var seen = root.runsSeen[runs[i].id]
      if (runs[i].status !== "completed" || (seen && seen.endedMs && root.nowMs - seen.endedMs < root.holdMs)) out.push(runs[i])
    }
    return out
  }

  readonly property bool anyLive: shownResults.some(function(r) { return root.liveRuns(r).length > 0 })

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

  // Every 5 minutes, every 30 seconds while a workflow runs.
  Timer {
    running: root.isPrimary && root.specs.length > 0
    repeat: true
    interval: root.anyRunning ? 30000 : 300000
    onTriggered: root.fetch()
  }

  // Changed repos fetch right away, once the edits settle.
  Timer {
    id: refetchSoon
    interval: 400
    onTriggered: root.fetch()
  }

  onSpecsChanged: refetchSoon.restart()
  onIsPrimaryChanged: if (isPrimary) refetchSoon.restart()

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

  function firstNumber(option, fallback) {
    if (!option) return fallback
    if (option.int !== undefined) return Number(option.int)
    var n = parseInt(String(option.css || option.custom || "").trim().split(/\s+/)[0], 10)
    return isFinite(n) ? n : fallback
  }

  function readHyprOptions(raw) {
    var list
    try { list = JSON.parse(raw) } catch (e) { return }
    var byName = {}
    for (var i = 0; i < list.length; i++) if (list[i] && list[i].option) byName[list[i].option] = list[i]
    root.gapsIn = firstNumber(byName["general:gaps_in"], 5)
    root.rounding = firstNumber(byName["decoration:rounding"], 0)
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
    }
  }

  Component.onCompleted: {
    refreshLook()
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
    active: root.isPrimary && root.repos.length > 0
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

  readonly property string statusText: {
    if (root.repos.length === 0) return "no repos yet"
    if (root.ciState === "failure") return "a workflow failed"
    if (root.ciState === "running") return "workflows running"
    if (root.ciState === "success") return "all workflows passing"
    return root.repos.length === 1 ? "1 repo" : root.repos.length + " repos"
  }

  BarIconButton {
    id: button
    visible: !root.inTray
    anchors.fill: parent
    bar: root.bar
    text: ""
    tooltipText: root.opened ? "" : "GitHub Desk: " + root.statusText
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
