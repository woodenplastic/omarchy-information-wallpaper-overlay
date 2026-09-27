import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import ".." as Desk
import "../Model.js" as Model

// What the tiles need from the bar widget, for the lock screen: the widget's
// settings, the cache its fetch writes, herdr's agents, long tasks, the theme's run
// colors and Hyprland's look. It only reads; the bar widget keeps fetching
// while the screen is locked, and the cache follows along.
Item {
  id: root

  readonly property string moduleName: "woodenplastic.information-wallpaper-overlay"

  // ---- Settings, from the widget's entry in shell.json.

  property var settings: ({})

  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      root.shellConfigText = text()
      var next = Model.barEntry(root.shellConfigText, root.moduleName)
      if (next) root.settings = next
    }
  }

  // The whole file too, for the settings of plugins shown in tiles.
  property string shellConfigText: ""

  function option(name, fallback) {
    var value = settings[name]
    return value === undefined || value === null ? fallback : value
  }

  // Slots kept off the lock screen aren't here.
  readonly property var tiles: Model.lockTileList(option("tiles", []))
  readonly property var repos: Model.reposOf(tiles)
  readonly property real tileOpacity: Util.clamp(Number(option("opacity", 0.2)), 0, 1)
  readonly property bool animations: option("animations", true) === true

  // Set by the design: while the screen is lit.
  property bool animate: false
  // Set by the design: on the real lock screen or its full preview, not in
  // the explorer's thumbnails, which would each ask herdr and watch tasks.
  property bool live: false

  // ---- Data.

  readonly property string cachePath: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/information-wallpaper-overlay/data.json"

  property var results: []
  property string fetchedAt: ""
  readonly property string fetchError: ""
  readonly property bool fetching: false
  property real nowMs: Date.now()
  property var runsSeen: ({})

  readonly property var shownResults: repos.map(function(entry) { return Model.resultFor(root.results, entry) })
  readonly property bool anyLive: shownResults.some(function(r) { return root.liveRuns(r).length > 0 })

  function liveRuns(result) {
    return Model.liveRuns(result, root.runsSeen, root.nowMs)
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
      root.runsSeen = Model.trackRuns(root.results, root.runsSeen, Date.now())
    }
  }

  // ---- herdr's agents; the music tile finds the player itself.

  Desk.HerdrFeed {
    id: herdrFeed
    active: root.live && Model.hasKind(root.tiles, "herdr")
  }

  readonly property var herdr: herdrFeed

  Desk.TasksFeed {
    id: tasksWatcher
    active: root.live && Model.hasKind(root.tiles, "tasks")
    tools: Model.taskTools(root.tiles)
  }

  readonly property var tasksFeed: tasksWatcher
  readonly property var mediaService: null

  // ---- Windows and monitors, for workspace tiles on the lock screen.

  Desk.WorkspaceFeed {
    id: workspaceWatcher
    active: root.live && Model.hasKind(root.tiles, "workspace")
  }

  readonly property var workspaceFeed: workspaceWatcher

  // A workspace on the real lock screen runs at 60 fps: Hyprland draws
  // windows on hidden workspaces at misc:render_unfocused_fps (15 unless
  // set), so that's raised while it's shown and put back after
  // (scripts/unfocused-fps keeps the value it replaced).
  readonly property bool smoothWorkspaces: root.live && Model.hasKind(root.tiles, "workspace")

  function applySmoothWorkspaces() {
    Util.execArgv(["bash", root.pluginDir + "/scripts/unfocused-fps", root.smoothWorkspaces ? "raise" : "restore", "lock", "60"])
  }

  onSmoothWorkspacesChanged: applySmoothWorkspaces()
  Component.onCompleted: if (smoothWorkspaces) applySmoothWorkspaces()
  Component.onDestruction: if (smoothWorkspaces) Util.execArgv(["bash", root.pluginDir + "/scripts/unfocused-fps", "restore", "lock"])

  // ---- Installed plugins, for plugin tiles (see the bar widget): listed
  //      while live. The copies get a bar with the look's fallbacks, since
  //      the lock screen has no bar.

  readonly property string pluginDir: Qt.resolvedUrl("..").toString().replace(/^file:\/\//, "").replace(/\/$/, "")
  property var installedPlugins: []
  readonly property bool hidePluginControls: option("hidePluginControls", true) === true

  Process {
    running: root.live && Model.hasKind(root.tiles, "plugin")
    command: ["bash", root.pluginDir + "/scripts/plugins"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var list
        try { list = JSON.parse(text) } catch (e) { return }
        if (Array.isArray(list) && JSON.stringify(list) !== JSON.stringify(root.installedPlugins)) root.installedPlugins = list
      }
    }
  }

  function pluginInfo(id) {
    for (var i = 0; i < root.installedPlugins.length; i++) if (root.installedPlugins[i].id === id) return root.installedPlugins[i]
    return null
  }

  function pluginSettings(id) {
    return Model.barEntry(root.shellConfigText, id) || ({})
  }

  Desk.DeskBar {
    id: deskBarObject
  }

  readonly property var deskBar: deskBarObject

  // The fetch renames a new cache over the old one, which a file watch can
  // lose track of, so the tick reads it again too.
  property int ticks: 0

  Timer {
    running: true
    repeat: true
    interval: root.anyLive ? 1000 : 30000
    onTriggered: {
      root.nowMs = Date.now()
      if (!root.anyLive || ++root.ticks % 30 === 0) cacheFile.reload()
    }
  }

  // ---- Look.

  property var statusColors: ({ success: "", running: "", failure: "" })
  readonly property color successColor: statusColors.success || "#9ece6a"
  readonly property color runningColor: statusColors.running || "#e0af68"
  readonly property color failureColor: statusColors.failure || Color.urgent

  property int gapsIn: 5
  property int rounding: 0
  // Hyprland puts gaps_in around each window, so neighbors sit twice apart.
  readonly property int gap: gapsIn * 2

  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    printErrors: false
    onLoaded: root.statusColors = Model.statusColors(text())
  }

  Process {
    running: true
    command: ["bash", "-c", "for o in general:gaps_in decoration:rounding; do hyprctl -j getoption \"$o\"; done | jq -cs ."]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var look = Model.hyprLook(text)
        if (!look) return
        root.gapsIn = look.gapsIn
        root.rounding = look.rounding
      }
    }
  }
}
