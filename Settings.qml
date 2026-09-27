import QtQuick
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Settings popup under the bar icon: six slots, each picked from a dropdown
// (a repo with an optional branch, herdr's agents, tasks, what's playing, or
// nothing), where they land on the desk, and how the tiles look.
Panel {
  id: root
  moduleName: "woodenplastic.information-wallpaper-overlay"
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
    if (root.widget) {
      root.widget.refreshRepoChoices()
      root.widget.refreshLockDesign()
      root.widget.refreshShellHook()
      root.widget.refreshPlugins()
    }
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
    var list = root.widget ? root.widget.slots : Model.slotList([])
    root.drafts = list.map(function(e) { return { kind: e.kind, repo: e.repo || "", branch: e.branch || "", tools: (e.tools || []).join(", "), plugin: e.plugin || "", workspace: e.workspace || "", hideOnLock: e.hideOnLock === true } })
  }

  function saveDrafts() {
    if (!root.widget) return
    var list = root.drafts.map(function(d) {
      var slot = d.kind === "github" ? { kind: "github", repo: Model.normalizeRepo(d.repo) || d.repo.trim(), branch: Model.normalizeBranch(d.branch) }
        : d.kind === "tasks" ? { kind: "tasks", tools: Model.toolList(d.tools) }
        : d.kind === "plugin" ? { kind: "plugin", plugin: d.plugin }
        : d.kind === "workspace" ? { kind: "workspace", workspace: d.workspace }
        : { kind: d.kind }
      if (d.kind !== "empty" && d.hideOnLock) slot.hideOnLock = true
      return slot
    })
    if (JSON.stringify(Model.slotList(list)) !== JSON.stringify(root.widget.slots)) root.widget.setSetting("tiles", list)
    // Fields edit the rows in place; a new list lets the preview follow.
    root.drafts = root.drafts.slice()
  }

  function setKind(index, kind) {
    if (!root.drafts[index] || root.drafts[index].kind === kind) return
    var next = root.drafts.slice()
    // A live workspace starts off the lock screen: anyone there would see
    // its windows.
    next[index] = { kind: kind, repo: "", branch: "", tools: "", plugin: "", workspace: "",
      hideOnLock: kind === "workspace" ? true : root.drafts[index].hideOnLock === true }
    root.drafts = next
    root.saveDrafts()
    if (kind === "github") Qt.callLater(function() {
      var row = rows.itemAt(index)
      if (row) row.focusRepo()
    })
  }

  // Keeps a slot off the lock screen, or puts it back.
  function toggleLock(index) {
    if (!root.drafts[index]) return
    root.drafts[index].hideOnLock = !root.drafts[index].hideOnLock
    root.saveDrafts()
  }

  function pickRepo(index, repo) {
    if (!root.drafts[index]) return
    root.drafts[index].repo = repo
    root.saveDrafts()
    var row = rows.itemAt(index)
    if (row) row.showPicked(repo)
    keyCatcher.forceActiveFocus()
  }

  // Repos in another slot, which the suggestions leave out.
  function takenRepos(exceptIndex) {
    var out = []
    for (var i = 0; i < root.drafts.length; i++) {
      if (i === exceptIndex || root.drafts[i].kind !== "github") continue
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

  // The filled slots, as the desk places them.
  readonly property var filled: {
    var out = []
    for (var i = 0; i < root.drafts.length; i++) {
      var d = root.drafts[i]
      if (d.kind !== "empty" && (d.kind !== "github" || Model.normalizeRepo(d.repo)) && (d.kind !== "plugin" || d.plugin) && (d.kind !== "workspace" || d.workspace)) out.push({ slot: i, kind: d.kind })
    }
    return out
  }

  // The plugins a plugin slot can show; a name two plugins share gets its id.
  // Those that opted out of tiles are left out, unless a slot has one.
  readonly property var pluginOptions: {
    var list = (root.widget ? root.widget.installedPlugins : []).filter(function(p) {
      return p.optOut === null || p.optOut === undefined || root.drafts.some(function(d) { return d.kind === "plugin" && d.plugin === p.id })
    })
    return list.map(function(p) {
      var shared = list.some(function(q) { return q !== p && q.name === p.name })
      return { value: p.id, label: shared ? p.name + " (" + p.id + ")" : p.name }
    })
  }

  // Workspaces a workspace slot can show: 1 to 10, and any other Hyprland
  // has now (named or special ones).
  readonly property var workspaceOptions: {
    var out = []
    for (var n = 1; n <= 10; n++) out.push({ value: String(n), label: "Workspace " + n })
    var list = Hyprland.workspaces ? Hyprland.workspaces.values : []
    for (var i = 0; i < list.length; i++) {
      var ws = list[i]
      var value = ws.id >= 1 && ws.id <= 10 ? String(ws.id) : ws.name
      if (out.some(function(o) { return o.value === value })) continue
      out.push({ value: value, label: value.indexOf("special:") === 0 ? "Special: " + value.substring(8) : "Workspace " + value })
    }
    return out
  }

  function setWorkspace(index, value) {
    if (!root.drafts[index]) return
    root.drafts[index].workspace = value
    root.saveDrafts()
  }

  function setPlugin(index, id) {
    if (!root.drafts[index]) return
    root.drafts[index].plugin = id
    root.saveDrafts()
  }

  // Dropdowns open keep the keys from the panel, like fields with focus.
  property int openDropdowns: 0

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
      blocked: root.focusedFields > 0 || root.openDropdowns > 0
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
            text: "\uf009  Information Wallpaper Overlay"
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
          text: "SLOTS"
          foreground: Color.popups.text
        }

        // ---- Where the filled slots land on the desk: empty ones are
        //      skipped, and with three the first is the large one.
        Item {
          id: preview
          width: parent.width
          height: Math.round(width * 0.24)
          readonly property var rects: Model.tileRects(root.filled.length, width, height, Style.space(4))

          Rectangle {
            visible: root.filled.length === 0
            anchors.fill: parent
            radius: Style.cornerRadius
            color: Util.alpha(Color.popups.text, 0.04)
            border.width: Math.max(1, Style.normalBorderWidth)
            border.color: Util.alpha(Color.popups.text, 0.12)

            Text {
              anchors.centerIn: parent
              width: parent.width - Style.space(24)
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.Wrap
              textFormat: Text.PlainText
              text: "The desk is empty. Pick what a slot shows below."
              color: root.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          Repeater {
            model: root.filled.length

            Rectangle {
              required property int index
              readonly property var rect: preview.rects[index] || { x: 0, y: 0, w: 0, h: 0 }
              readonly property var slot: root.filled[index] || { slot: 0, kind: "empty" }
              x: Math.round(rect.x)
              y: Math.round(rect.y)
              width: Math.round(rect.w)
              height: Math.round(rect.h)
              radius: Style.cornerRadius
              color: Util.alpha(Color.accent, 0.12)
              border.width: Math.max(1, Style.normalBorderWidth)
              border.color: Util.alpha(Color.accent, 0.4)

              Row {
                anchors.centerIn: parent
                spacing: Style.space(5)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: String(parent.parent.slot.slot + 1)
                  color: root.dim
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: Model.kindGlyph(parent.parent.slot.kind)
                  color: Color.accent
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }
              }
            }
          }
        }

        // ---- The six slots: what each shows, and what that needs.
        Column {
          width: parent.width
          spacing: Style.space(8)

          Repeater {
            id: rows
            model: root.drafts.length

            Column {
              id: row
              required property int index
              readonly property var draft: root.drafts[index] || ({ kind: "empty" })
              readonly property string kind: draft.kind
              readonly property var result: kind === "github" ? root.resultFor(draft) : null
              width: parent.width
              spacing: Style.space(3)

              function focusRepo() { repoField.forceActiveFocus() }
              function showPicked(repo) { repoField.text = repo }

              // Suggestions while the repo field has the keyboard.
              property string typed: draft.repo || ""
              property int highlight: -1
              readonly property var suggestions: repoField.activeFocus && root.widget
                ? Model.filterChoices(root.widget.repoChoices, typed, root.takenRepos(index), 6)
                : []
              onSuggestionsChanged: if (highlight >= suggestions.length) highlight = suggestions.length - 1

              Row {
                width: parent.width
                spacing: Style.space(6)

                Text {
                  id: slotNumber
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.font.body * 1.4
                  horizontalAlignment: Text.AlignHCenter
                  textFormat: Text.PlainText
                  text: String(row.index + 1)
                  color: row.kind === "empty" ? root.dim : Color.accent
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                }

                Dropdown {
                  id: kindPicker
                  width: Math.round((parent.width - slotNumber.width - parent.spacing * 2) * 0.4)
                  showLabel: false
                  options: Model.KIND_OPTIONS
                  value: row.kind
                  onChanged: function(value) { root.setKind(row.index, value) }
                  onPopupOpenChanged: root.openDropdowns = Math.max(0, root.openDropdowns + (popupOpen ? 1 : -1))
                }

                // What the kind needs: a repo, more tools to watch, or a note.
                Item {
                  id: detail
                  width: parent.width - slotNumber.width - kindPicker.width - lockButton.width - parent.spacing * 3
                  height: kindPicker.height

                  TextField {
                    id: repoField
                    visible: row.kind === "github"
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    placeholderText: "owner/repo or GitHub URL"
                    text: row.draft.repo || ""
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
                    visible: row.kind === "tasks"
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    placeholderText: "Also watch: e.g. just, ./build.sh"
                    text: row.draft.tools || ""
                    foreground: Color.popups.text
                    onTextEdited: root.drafts[row.index].tools = text
                    onActiveFocusChanged: root.focusedFields += activeFocus ? 1 : -1
                    onEditingFinished: root.saveDrafts()
                    onAccepted: keyCatcher.forceActiveFocus()
                    Keys.onEscapePressed: keyCatcher.forceActiveFocus()
                  }

                  Dropdown {
                    visible: row.kind === "plugin"
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    showLabel: false
                    options: [{ value: "", label: root.pluginOptions.length > 0 ? "Pick a plugin" : "Listing plugins…" }].concat(root.pluginOptions)
                    value: row.draft.plugin || ""
                    onChanged: function(value) { if (value) root.setPlugin(row.index, value) }
                    onPopupOpenChanged: root.openDropdowns = Math.max(0, root.openDropdowns + (popupOpen ? 1 : -1))
                  }

                  Dropdown {
                    visible: row.kind === "workspace"
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    showLabel: false
                    options: [{ value: "", label: "Pick a workspace" }].concat(root.workspaceOptions)
                    value: row.draft.workspace || ""
                    onChanged: function(value) { if (value) root.setWorkspace(row.index, value) }
                    onPopupOpenChanged: root.openDropdowns = Math.max(0, root.openDropdowns + (popupOpen ? 1 : -1))
                  }

                  Text {
                    visible: row.kind !== "github" && row.kind !== "tasks" && row.kind !== "plugin" && row.kind !== "workspace"
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    leftPadding: Style.spacing.controlPaddingX
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    text: row.kind === "herdr" ? "Agents in every herdr workspace"
                      : row.kind === "music" ? "What the bar's media widget plays"
                      : "Skipped; the other tiles share the desk"
                    color: root.dim
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }

                // On the lock screen or not: kept off, the tile leaves the
                // others the room there.
                PanelActionButton {
                  id: lockButton
                  anchors.verticalCenter: parent.verticalCenter
                  opacity: row.kind === "empty" ? 0 : 1
                  enabled: row.kind !== "empty"
                  iconText: row.draft.hideOnLock ? "\uf023" : "\uf09c"
                  tooltipText: row.draft.hideOnLock ? "Kept off the lock screen" : "Shown on the lock screen"
                  foreground: row.draft.hideOnLock ? Color.accent : root.dim
                  onClicked: root.toggleLock(row.index)
                }
              }

              // ---- A repo's branch, under the repo.
              TextField {
                id: branchField
                visible: row.kind === "github"
                x: detail.x
                width: detail.width
                placeholderText: row.result && row.result.ok ? "branch: " + row.result.defaultBranch : "branch (default)"
                text: row.draft.branch || ""
                foreground: Color.popups.text
                onTextEdited: root.drafts[row.index].branch = text
                onActiveFocusChanged: root.focusedFields += activeFocus ? 1 : -1
                onEditingFinished: root.saveDrafts()
                onAccepted: keyCatcher.forceActiveFocus()
                Keys.onEscapePressed: keyCatcher.forceActiveFocus()
              }

              // ---- Suggestions: own and organization repos matching the text.
              Rectangle {
                visible: row.kind === "github" && (row.suggestions.length > 0 || (repoField.activeFocus && root.widget && root.widget.listingRepos && root.widget.repoChoices.length === 0))
                x: detail.x
                width: detail.width
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
                visible: row.kind === "github" && text !== ""
                x: detail.x
                width: detail.width
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

        Toggle {
          visible: root.drafts.some(function(d) { return d.kind === "plugin" })
          width: parent.width
          label: "Hide plugin controls"
          description: "Plugin tiles leave out the menus' buttons, dropdowns, switches and fields; the desk takes no clicks anyway."
          checked: !!root.widget && root.widget.hidePluginControls
          foreground: Color.popups.text
          onClicked: if (root.widget) root.widget.setSetting("hidePluginControls", !root.widget.hidePluginControls)
        }

        Toggle {
          visible: root.drafts.some(function(d) { return d.kind === "tasks" }) && !!root.widget && root.widget.shellHook !== ""
          width: parent.width
          label: "Pass or fail for terminal commands"
          description: "For the tasks tile: adds a line to ~/.bashrc, so new terminals note how commands that ran 5 seconds or longer ended. Tasks agents start show as done."
          checked: !!root.widget && root.widget.shellHook === "on"
          foreground: Color.popups.text
          onClicked: if (root.widget) root.widget.setShellHook(root.widget.shellHook !== "on")
        }

        PanelSeparator { width: parent.width }

        PanelSectionHeader {
          text: "LOOK"
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
            id: opacitySlider
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - opacityLabel.width - opacityValue.width - parent.spacing * 2
            bar: root.bar
            minimum: 0
            maximum: 1
            step: 0.05
            value: root.widget ? root.widget.tileOpacity : 0.2
            // The tiles follow the drag here; a desk shown by another monitor's
            // instance follows the saved value, written whenever the drag pauses.
            onMoved: function(value) {
              if (!root.widget) return
              root.widget.previewOpacity = Math.round(value * 100) / 100
              opacitySave.restart()
            }
            onReleased: function(value) {
              if (!root.widget) return
              opacitySave.stop()
              root.widget.setSetting("opacity", Math.round(value * 100) / 100)
              root.widget.previewOpacity = NaN
            }

            Timer {
              id: opacitySave
              interval: 150
              onTriggered: if (root.widget && !isNaN(root.widget.previewOpacity)) root.widget.setSetting("opacity", root.widget.previewOpacity)
            }
          }

          Text {
            id: opacityValue
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: Math.round(opacitySlider.liveValue * 100) + "%"
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
          description: "Heatmap cells twinkle, today's cell breathes and working agents pulse, while no windows cover the desk."
          checked: !!root.widget && root.widget.animations
          foreground: Color.popups.text
          onClicked: if (root.widget) root.widget.setSetting("animations", !root.widget.animations)
        }

        // ---- Lock screen, through the Lock Screen Explorer plugin.
        readonly property string lockDesign: root.widget ? root.widget.lockDesign : ""

        PanelSeparator { width: parent.width; visible: column.lockDesign !== "" }

        PanelSectionHeader {
          visible: column.lockDesign !== ""
          text: "LOCK SCREEN"
          foreground: Color.popups.text
        }

        Toggle {
          width: parent.width
          visible: column.lockDesign === "on" || column.lockDesign === "off"
          label: "On the lock screen"
          description: "The tiles as a Lock Screen Explorer design, with the clock and password in the middle."
          checked: column.lockDesign === "on"
          enabled: !!root.widget && !root.widget.lockDesignBusy
          foreground: Color.popups.text
          onClicked: if (root.widget) root.widget.setLockDesign(column.lockDesign !== "on")
        }

        Text {
          visible: column.lockDesign === "missing" || column.lockDesign === "taken" || (!!root.widget && root.widget.lockDesignError !== "")
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          color: root.widget && root.widget.lockDesignError ? Color.urgent : root.dim
          text: root.widget && root.widget.lockDesignError ? root.widget.lockDesignError
            : column.lockDesign === "taken" ? "A lock design called InformationWallpaperOverlay already exists and isn't this plugin's, so it's left alone. Rename or remove it in Lock Screen Explorer to use this one."
            : "Install the Lock Screen Explorer plugin to show the tiles on the lock screen too."
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
            var parts = root.widget.repos.length > 0 ? ["Signed in through the gh CLI"] : []
            parts.push("tiles on the first monitor")
            if (root.widget.fetching) parts.push("updating…")
            else if (root.widget.fetchedAt) parts.push("updated " + Model.relativeTime(root.widget.fetchedAt, root.widget.nowMs))
            return parts.join("  ·  ")
          }
        }
      }
    }
  }
}
