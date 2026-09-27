import QtQuick
import "Model.js" as Model

// One tile, by its kind: a repo, herdr's agents, what's playing, or the
// long tasks on the machine, an installed plugin, or a workspace live. The
// desk and the lock screen both place their tiles through this.
Loader {
  id: root

  // The bar widget, or the lock screen's feed: settings, data and look.
  property var widget: null
  property var entry: ({})

  sourceComponent: entry.kind === "herdr" ? agentsTile
    : entry.kind === "music" ? musicTile
    : entry.kind === "tasks" ? tasksTile
    : entry.kind === "plugin" ? pluginTile
    : entry.kind === "workspace" ? workspaceTile
    : repoTile

  Component {
    id: repoTile
    RepoTile {
      widget: root.widget
      entry: root.entry
      result: root.widget ? Model.resultFor(root.widget.results, root.entry) : null
    }
  }

  Component {
    id: agentsTile
    AgentsTile {
      widget: root.widget
      entry: root.entry
    }
  }

  Component {
    id: workspaceTile
    WorkspaceTile {
      widget: root.widget
      entry: root.entry
    }
  }

  Component {
    id: pluginTile
    PluginTile {
      widget: root.widget
      entry: root.entry
    }
  }

  Component {
    id: tasksTile
    TasksTile {
      widget: root.widget
      entry: root.entry
    }
  }

  Component {
    id: musicTile
    MusicTile {
      widget: root.widget
      entry: root.entry
    }
  }
}
