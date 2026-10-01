import QtQuick
import "Model.js" as Model

// One tile, by its kind: a repo, herdr's agents, what's playing, the long
// tasks on the machine, an installed plugin, a workspace live, the
// machine's upkeep, local repos, USB devices or a KiCad board. The
// desk and the lock screen both place their tiles through this.
Loader {
  id: root

  // The bar widget, or the lock screen's feed: settings, data and look.
  property var widget: null
  property var entry: ({})
  // Whether the desk it's on can be seen (Desk.qml).
  property bool shown: true

  sourceComponent: entry.kind === "herdr" ? agentsTile
    : entry.kind === "music" ? musicTile
    : entry.kind === "tasks" ? tasksTile
    : entry.kind === "plugin" ? pluginTile
    : entry.kind === "workspace" ? workspaceTile
    : entry.kind === "upkeep" ? upkeepTile
    : entry.kind === "projects" ? projectsTile
    : entry.kind === "devices" ? devicesTile
    : entry.kind === "board" ? boardTile
    : repoTile

  Component {
    id: repoTile
    RepoTile {
      widget: root.widget
      entry: root.entry
      shown: root.shown
      result: root.widget ? Model.resultFor(root.widget.results, root.entry) : null
    }
  }

  Component {
    id: agentsTile
    AgentsTile {
      widget: root.widget
      entry: root.entry
      shown: root.shown
    }
  }

  Component {
    id: workspaceTile
    WorkspaceTile {
      widget: root.widget
      entry: root.entry
      shown: root.shown
    }
  }

  Component {
    id: pluginTile
    PluginTile {
      widget: root.widget
      entry: root.entry
      shown: root.shown
    }
  }

  Component {
    id: tasksTile
    TasksTile {
      widget: root.widget
      entry: root.entry
      shown: root.shown
    }
  }

  Component {
    id: musicTile
    MusicTile {
      widget: root.widget
      entry: root.entry
      shown: root.shown
    }
  }

  Component {
    id: upkeepTile
    UpkeepTile {
      widget: root.widget
      entry: root.entry
      shown: root.shown
    }
  }

  Component {
    id: projectsTile
    ProjectsTile {
      widget: root.widget
      entry: root.entry
      shown: root.shown
    }
  }

  Component {
    id: devicesTile
    DevicesTile {
      widget: root.widget
      entry: root.entry
      shown: root.shown
    }
  }

  Component {
    id: boardTile
    BoardTile {
      widget: root.widget
      entry: root.entry
      shown: root.shown
    }
  }
}
