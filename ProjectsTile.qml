import QtQuick
import qs.Commons

// The git repos in a folder (scripts/projects): what's left uncommitted or
// unpushed. The repos that need attention first, the most recently touched
// first, each with its branch, its changed and untracked files, the commits
// its upstream doesn't have and it doesn't have yet, and how long ago it was
// touched; then the clean ones, dimmed, counted when they don't fit.
Tile {
  id: root

  readonly property var feed: widget ? widget.projectsFeed : null
  readonly property string folderKey: entry && entry.folder ? entry.folder : ""
  readonly property var folder: feed && feed.output && feed.output.folders ? feed.output.folders[folderKey] || null : null
  readonly property var repos: folder ? folder.repos || [] : []
  readonly property var counts: folder ? folder.counts : ({ total: 0, attention: 0, changed: 0, ahead: 0, clean: 0 })
  readonly property int stuck: repos.filter(function(r) { return r.conflicts > 0 || (r.state !== "" && r.state !== "detached") }).length

  glowY: pad + header.height

  // A repo's color: red mid-rebase or with conflicts, yellow with changes,
  // the accent with only unpushed commits, green when clean.
  function repoState(repo) {
    if (repo.conflicts > 0 || (repo.state !== "" && repo.state !== "detached")) return "stuck"
    if (repo.changed > 0 || repo.untracked > 0) return "changed"
    if (repo.ahead > 0) return "ahead"
    return "clean"
  }

  function stateColor(state) {
    if (!widget) return faint
    if (state === "stuck") return widget.failureColor
    if (state === "changed") return widget.runningColor
    if (state === "ahead") return Color.accent
    return widget.successColor
  }

  // "now", "12m", "5h", "3d", "4mo", "2y" since a time in epoch seconds.
  function ago(seconds) {
    var s = Math.max(0, root.nowMs / 1000 - seconds)
    if (!seconds) return ""
    if (s < 60) return "now"
    if (s < 3600) return Math.floor(s / 60) + "m"
    if (s < 86400) return Math.floor(s / 3600) + "h"
    if (s < 60 * 86400) return Math.floor(s / 86400) + "d"
    if (s < 365 * 86400) return Math.floor(s / (30 * 86400)) + "mo"
    return Math.floor(s / (365 * 86400)) + "y"
  }

  // "5 changed · 2 new · ↑3 ↓1"
  function details(repo) {
    return [
      repo.conflicts > 0 ? repo.conflicts + " conflicted" : "",
      repo.changed > 0 ? repo.changed + " changed" : "",
      repo.untracked > 0 ? repo.untracked + " new" : "",
      repo.ahead > 0 || repo.behind > 0 ? [repo.ahead > 0 ? "↑" + repo.ahead : "", repo.behind > 0 ? "↓" + repo.behind : ""].filter(function(s) { return s }).join(" ") : "",
      repo.stash > 0 ? repo.stash + " stashed" : ""
    ].filter(function(s) { return s }).join("  ·  ")
  }

  // The branch, or what the repo is in the middle of.
  function where(repo) {
    if (repo.state === "detached") return "detached"
    if (repo.state !== "") return repo.state + (repo.branch ? " " + repo.branch : "")
    return repo.branch + (repo.upstream ? "" : "  ·  not pushed yet")
  }

  component Label: Text {
    textFormat: Text.PlainText
    color: root.fg
    font.family: root.family
    font.pixelSize: root.bodySize
    elide: Text.ElideRight
    maximumLineCount: 1
  }

  component StateBlock: Rectangle {
    property string repoState: "clean"
    width: root.bodySize * 0.7
    height: width
    radius: root.rounded ? width * 0.22 : 0
    color: root.stateColor(repoState)
  }

  // ---- Title, the folder and the counts.
  Column {
    id: header
    width: parent.width
    spacing: root.statSize * 0.4

    Row {
      width: parent.width
      spacing: root.titleSize * 0.45

      Label {
        id: glyph
        anchors.baseline: titleText.baseline
        text: ""
        color: Color.accent
        font.pixelSize: root.titleSize * 0.85
      }
      Label {
        id: titleText
        text: "Repos"
        font.pixelSize: root.titleSize
        font.bold: true
      }
      Label {
        anchors.baseline: titleText.baseline
        width: Math.max(0, parent.width - glyph.width - titleText.width - parent.spacing * 2)
        text: root.folder ? root.folder.path.replace(/^\/home\/[^/]+/, "~") : root.folderKey || "~/Projects"
        color: root.dim
        font.pixelSize: root.statSize
      }
    }

    Flow {
      width: parent.width
      spacing: root.statSize * 0.9
      visible: root.repos.length > 0

      Repeater {
        model: [
          { state: "stuck", count: root.stuck, word: "stuck" },
          { state: "changed", count: root.counts.changed, word: "with changes" },
          { state: "ahead", count: root.counts.ahead, word: "unpushed" },
          { state: "clean", count: root.counts.clean, word: "clean" }
        ]

        Row {
          required property var modelData
          visible: modelData.count > 0
          spacing: root.statSize * 0.35

          StateBlock {
            anchors.verticalCenter: parent.verticalCenter
            repoState: parent.modelData.state
            width: root.statSize * 0.55
          }
          Label {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.modelData.count + " " + parent.modelData.word
            font.pixelSize: root.statSize
            color: parent.modelData.state === "stuck" ? root.stateColor("stuck") : root.fg
          }
        }
      }
    }
  }

  Rectangle {
    id: rule
    anchors.top: header.bottom
    anchors.topMargin: root.statSize
    width: parent.width
    height: 1
    color: root.faint
  }

  Label {
    visible: root.repos.length === 0
    anchors.top: rule.bottom
    anchors.topMargin: root.statSize
    width: parent.width
    wrapMode: Text.Wrap
    maximumLineCount: 3
    color: root.dim
    text: !root.feed || !root.feed.loaded || !root.folder ? "Looking for repos…"
      : root.folder.error ? root.folder.error
      : "No git repos in " + root.folder.path.replace(/^\/home\/[^/]+/, "~")
  }

  // ---- The repos, as many as fit; the clean ones that don't are counted.
  Column {
    id: list
    visible: root.repos.length > 0
    anchors.top: rule.bottom
    anchors.topMargin: root.statSize * 0.6
    width: parent.width

    readonly property real rowHeight: Math.round(root.bodySize * 1.75)
    readonly property int fit: Math.max(0, Math.floor((root.area.height - y) / rowHeight))
    // With more than fit, the last row says how many are left out.
    readonly property int shown: root.repos.length <= fit ? root.repos.length : Math.max(0, fit - 1)
    readonly property int hiddenCount: root.repos.length - shown
    readonly property real detailWidth: Math.min(width * 0.5, root.bodySize * 0.6 * 40)
    readonly property real ageWidth: root.bodySize * 0.6 * 5

    Repeater {
      model: list.shown

      Item {
        id: row
        required property int index
        readonly property var repo: root.repos[index] || ({})
        readonly property string repoState: root.repoState(repo)
        width: list.width
        height: list.rowHeight
        opacity: repo.attention ? 1 : 0.6

        StateBlock {
          id: block
          anchors.verticalCenter: parent.verticalCenter
          repoState: row.repoState
        }
        Label {
          id: name
          anchors.left: block.right
          anchors.leftMargin: root.bodySize * 0.7
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, row.width - block.width - detail.width - age.width - root.bodySize * 7)
          text: row.repo.name || ""
          font.bold: !!row.repo.attention
        }
        Label {
          anchors.left: name.right
          anchors.leftMargin: root.bodySize * 0.8
          anchors.right: detail.left
          anchors.rightMargin: root.bodySize
          anchors.verticalCenter: parent.verticalCenter
          text: root.where(row.repo)
          color: row.repoState === "stuck" ? root.stateColor("stuck") : row.repo.state === "detached" ? root.dim : Color.accent
        }
        Label {
          id: detail
          anchors.right: age.left
          anchors.rightMargin: text ? root.bodySize : 0
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, list.detailWidth)
          horizontalAlignment: Text.AlignRight
          color: root.dim
          text: root.details(row.repo)
        }
        // How long since it was touched, in a column of its own.
        Label {
          id: age
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: list.ageWidth
          horizontalAlignment: Text.AlignRight
          color: root.dim
          text: root.ago(row.repo.touched)
        }
      }
    }

    Label {
      visible: list.hiddenCount > 0
      height: list.rowHeight
      verticalAlignment: Text.AlignVCenter
      width: list.width
      color: root.dim
      text: {
        var hidden = root.repos.slice(list.shown)
        var clean = hidden.filter(function(r) { return !r.attention }).length
        return clean === hidden.length ? "+" + clean + " clean" : "+" + hidden.length + " more, " + clean + " of them clean"
      }
    }
  }
}
