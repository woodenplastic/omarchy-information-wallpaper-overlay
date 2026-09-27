import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Settings popup under the bar icon: up to four repos with an optional
// branch each, and how the tiles look.
Panel {
  id: root
  moduleName: "woodenplastic.github-desk"
  manageIpc: false

  property var anchorItem: null
  // The bar knows the widget in its slot, not this nested panel, so the
  // popout coordinator and panel switching go by the widget.
  property var hostWidget: null
  readonly property var widget: hostWidget

  // Rows being edited; saved as they are left. Rebuilt on each open.
  property var drafts: []
  property int focusedFields: 0

  function open() {
    loadDrafts()
    root.focusedFields = 0
    if (root.widget) root.widget.refreshRepoChoices()
    root.controller.show()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  function loadDrafts() {
    var list = root.widget ? root.widget.repos : []
    root.drafts = list.map(function(e) { return { repo: e.repo, branch: e.branch } })
    if (root.drafts.length === 0) root.drafts = [{ repo: "", branch: "" }]
  }

  function saveDrafts() {
    if (!root.widget) return
    var list = []
    for (var i = 0; i < root.drafts.length; i++) {
      var repo = Model.normalizeRepo(root.drafts[i].repo)
      if (repo) list.push({ repo: repo, branch: Model.normalizeBranch(root.drafts[i].branch) })
    }
    var current = root.widget.repos
    if (JSON.stringify(current) !== JSON.stringify(list)) root.widget.setSetting("repos", list)
  }

  function addRow() {
    if (root.drafts.length >= Model.MAX_REPOS) return
    root.drafts = root.drafts.concat([{ repo: "", branch: "" }])
    Qt.callLater(function() {
      var row = rows.itemAt(root.drafts.length - 1)
      if (row) row.focusRepo()
    })
  }

  function removeRow(index) {
    var next = root.drafts.slice()
    next.splice(index, 1)
    root.drafts = next
    saveDrafts()
  }

  function pickRepo(index, repo) {
    if (!root.drafts[index]) return
    root.drafts[index].repo = repo
    root.saveDrafts()
    var row = rows.itemAt(index)
    if (row) row.showPicked(repo)
    keyCatcher.forceActiveFocus()
  }

  // Repos on the desk or in another row, which the suggestions leave out.
  function takenRepos(exceptIndex) {
    var out = []
    for (var i = 0; i < root.drafts.length; i++) {
      if (i === exceptIndex) continue
      var repo = Model.normalizeRepo(root.drafts[i].repo)
      if (repo) out.push(repo)
    }
    return out
  }

  function resultFor(draft) {
    var repo = Model.normalizeRepo(draft.repo)
    if (!repo || !root.widget) return null
    return Model.resultFor(root.widget.results, { repo: repo, branch: Model.normalizeBranch(draft.branch) })
  }

  readonly property color dim: Util.alpha(Color.popups.text, 0.55)

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(470))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.focusedFields > 0
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        Item {
          width: parent.width
          height: Math.max(title.implicitHeight, refreshButton.height)

          Text {
            id: title
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "  GitHub Desk"
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
          }

          PanelActionButton {
            id: refreshButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            iconText: ""
            tooltipText: "Refresh now"
            foreground: Color.popups.text
            enabled: !!root.widget && root.widget.repos.length > 0 && !root.widget.fetching
            onClicked: root.widget.fetch()
          }
        }

        PanelSectionHeader {
          text: "REPOSITORIES"
          foreground: Color.popups.text
        }

        Column {
          width: parent.width
          spacing: Style.space(8)

          Repeater {
            id: rows
            model: root.drafts.length

            Column {
              id: row
              required property int index
              readonly property var result: root.resultFor(root.drafts[index] || {})
              width: parent.width
              spacing: Style.space(3)

              function focusRepo() { repoField.forceActiveFocus() }
              function showPicked(repo) { repoField.text = repo }

              // Suggestions while the repo field has the keyboard.
              property string typed: (root.drafts[index] || {}).repo || ""
              property int highlight: -1
              readonly property var suggestions: repoField.activeFocus && root.widget
                ? Model.filterChoices(root.widget.repoChoices, typed, root.takenRepos(index), 6)
                : []
              onSuggestionsChanged: if (highlight >= suggestions.length) highlight = suggestions.length - 1

              Row {
                width: parent.width
                spacing: Style.space(6)

                TextField {
                  id: repoField
                  width: (parent.width - removeButton.width - parent.spacing * 2) * 0.62
                  placeholderText: "owner/repo or GitHub URL"
                  text: (root.drafts[row.index] || {}).repo || ""
                  foreground: Color.popups.text
                  onTextEdited: {
                    root.drafts[row.index].repo = text
                    row.typed = text
                    row.highlight = -1
                  }
                  onActiveFocusChanged: {
                    root.focusedFields += activeFocus ? 1 : -1
                    row.highlight = -1
                  }
                  onEditingFinished: root.saveDrafts()
                  onAccepted: {
                    if (row.highlight >= 0 && row.suggestions[row.highlight]) root.pickRepo(row.index, row.suggestions[row.highlight].repo)
                    else keyCatcher.forceActiveFocus()
                  }
                  Keys.onEscapePressed: keyCatcher.forceActiveFocus()
                  Keys.onDownPressed: row.highlight = Math.min(row.suggestions.length - 1, row.highlight + 1)
                  Keys.onUpPressed: row.highlight = Math.max(-1, row.highlight - 1)
                }

                TextField {
                  id: branchField
                  width: (parent.width - removeButton.width - parent.spacing * 2) * 0.38
                  placeholderText: row.result && row.result.ok ? row.result.defaultBranch : "default branch"
                  text: (root.drafts[row.index] || {}).branch || ""
                  foreground: Color.popups.text
                  onTextEdited: root.drafts[row.index].branch = text
                  onActiveFocusChanged: root.focusedFields += activeFocus ? 1 : -1
                  onEditingFinished: root.saveDrafts()
                  onAccepted: keyCatcher.forceActiveFocus()
                  Keys.onEscapePressed: keyCatcher.forceActiveFocus()
                }

                PanelActionButton {
                  id: removeButton
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: ""
                  tooltipText: "Remove"
                  foreground: Color.popups.text
                  onClicked: root.removeRow(row.index)
                }
              }

              // ---- Suggestions: own and organization repos matching the text.
              Rectangle {
                visible: row.suggestions.length > 0 || (repoField.activeFocus && root.widget && root.widget.listingRepos && root.widget.repoChoices.length === 0)
                width: repoField.width
                height: suggestionColumn.implicitHeight + Style.space(4)
                color: Util.alpha(Color.popups.text, 0.04)
                border.width: Math.max(1, Style.normalBorderWidth)
                border.color: Style.normalBorderFor(Color.popups.text, Color.accent)
                radius: Style.cornerRadius

                Column {
                  id: suggestionColumn
                  x: Style.space(2)
                  y: Style.space(2)
                  width: parent.width - Style.space(4)

                  Text {
                    visible: row.suggestions.length === 0
                    leftPadding: Style.spacing.controlPaddingX
                    height: Style.spacing.popupRowHeight
                    verticalAlignment: Text.AlignVCenter
                    textFormat: Text.PlainText
                    text: "Listing your repos…"
                    color: root.dim
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                  }

                  Repeater {
                    model: row.suggestions

                    Rectangle {
                      id: suggestion
                      required property var modelData
                      required property int index
                      readonly property bool hot: pickArea.containsMouse || row.highlight === index
                      width: suggestionColumn.width
                      height: Style.spacing.popupRowHeight
                      radius: Style.cornerRadius
                      color: hot ? Style.hoverFillFor(Color.popups.text, Color.accent) : "transparent"

                      Row {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: Style.spacing.controlPaddingX
                        anchors.rightMargin: Style.spacing.controlPaddingX
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(6)

                        Text {
                          textFormat: Text.PlainText
                          text: suggestion.modelData.private ? "\uf023" : (suggestion.modelData.org ? "\uf0c0" : "\uf401")
                          color: suggestion.hot ? Color.accent : root.dim
                          font.family: Style.font.family
                          font.pixelSize: Style.font.body
                          width: Style.font.body * 1.3
                        }
                        Text {
                          id: ownerText
                          textFormat: Text.PlainText
                          text: suggestion.modelData.owner + "/"
                          color: root.dim
                          font.family: Style.font.family
                          font.pixelSize: Style.font.body
                        }
                        Text {
                          textFormat: Text.PlainText
                          text: String(suggestion.modelData.repo).substring(String(suggestion.modelData.repo).indexOf("/") + 1)
                          color: suggestion.hot ? Color.accent : Color.popups.text
                          font.family: Style.font.family
                          font.pixelSize: Style.font.body
                          elide: Text.ElideRight
                          width: Math.min(implicitWidth, suggestionColumn.width - ownerText.width - Style.font.body * 1.3 - Style.space(12) - Style.spacing.controlPaddingX * 2)
                        }
                      }

                      MouseArea {
                        id: pickArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.pickRepo(row.index, suggestion.modelData.repo)
                      }
                    }
                  }
                }
              }

              Text {
                readonly property string typed: (root.drafts[row.index] || {}).repo || ""
                readonly property bool invalid: typed.trim() !== "" && Model.normalizeRepo(typed) === ""
                visible: text !== ""
                width: parent.width
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                color: invalid || (row.result && !row.result.ok) ? Color.urgent : root.dim
                text: invalid ? "Not a GitHub repo: use owner/repo or its URL"
                  : row.result && !row.result.ok ? row.result.error
                  : row.result && row.result.private ? "Private repo"
                  : ""
              }
            }
          }
        }

        Button {
          visible: root.drafts.length < Model.MAX_REPOS
          text: "Add repository"
          iconText: ""
          foreground: Color.popups.text
          bordered: true
          onClicked: root.addRow()
        }

        PanelSeparator { width: parent.width }

        PanelSectionHeader {
          text: "TILES"
          foreground: Color.popups.text
        }

        Row {
          width: parent.width
          spacing: Style.space(12)

          Text {
            id: opacityLabel
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "Opacity"
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
          }

          PanelSlider {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - opacityLabel.width - opacityValue.width - parent.spacing * 2
            bar: root.bar
            minimum: 0
            maximum: 1
            step: 0.05
            value: root.widget ? root.widget.tileOpacity : 0.2
            onReleased: function(value) { if (root.widget) root.widget.setSetting("opacity", Math.round(value * 100) / 100) }
          }

          Text {
            id: opacityValue
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: Math.round((root.widget ? root.widget.tileOpacity : 0.2) * 100) + "%"
            color: root.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
        }

        Toggle {
          width: parent.width
          label: "Show in the tray"
          description: "The icon sits behind the tray's arrow. Off puts it on the bar."
          checked: !!root.widget && root.widget.inTray
          foreground: Color.popups.text
          onClicked: if (root.widget) root.widget.setSetting("inTray", !root.widget.inTray)
        }

        Toggle {
          width: parent.width
          label: "Animations"
          description: "Cells with commits twinkle and today's cell breathes, while no windows cover the desk."
          checked: !!root.widget && root.widget.animations
          foreground: Color.popups.text
          onClicked: if (root.widget) root.widget.setSetting("animations", !root.widget.animations)
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          color: root.widget && root.widget.fetchError ? Color.urgent : root.dim
          text: {
            if (!root.widget) return ""
            if (root.widget.fetchError) return root.widget.fetchError
            var parts = ["Signed in through the gh CLI", "tiles on the first monitor"]
            if (root.widget.fetching) parts.push("updating…")
            else if (root.widget.fetchedAt) parts.push("updated " + Model.relativeTime(root.widget.fetchedAt, root.widget.nowMs))
            return parts.join("  ·  ")
          }
        }
      }
    }
  }
}
