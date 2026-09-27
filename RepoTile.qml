import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons
import "Model.js" as Model

// One repo on the desk: a borderless panel in the theme's background. On a soft
// accent glow: the year of commits as a heatmap, the owner's avatar in the
// accent color beside the name, the numbers, the Actions runs, and the
// latest commits. Everything scales with the tile.
Rectangle {
  id: root

  property var widget: null
  property var entry: ({ repo: "", branch: "" })
  property var result: null

  readonly property bool ok: !!result && result.ok === true
  readonly property real nowMs: widget ? widget.nowMs : Date.now()
  readonly property bool animate: !!widget && widget.animate

  readonly property color fg: Color.foreground
  readonly property color dim: Util.alpha(Color.foreground, 0.55)
  readonly property color faint: Util.alpha(Color.foreground, 0.12)
  readonly property string family: Style.font.family
  readonly property bool rounded: !!widget && widget.rounding > 0

  color: Util.alpha(Color.background, widget ? widget.tileOpacity : 0.2)
  radius: widget ? widget.rounding : 0
  clip: true

  // ---- Scale: the heatmap's cell pitch sets every other size.
  readonly property real pad: Math.max(Style.space(16), Math.min(width, height) * 0.05)
  readonly property real innerWidth: width - 2 * pad
  readonly property real innerHeight: height - 2 * pad
  readonly property real minPitch: 8
  readonly property real fitPitch: Math.min(26, (innerWidth * 0.95) / 55.5, innerHeight * 0.34 / 9)
  readonly property real pitch: Math.max(minPitch, fitPitch)
  readonly property int weeks: fitPitch >= minPitch ? 53 : Math.max(8, Math.floor((innerWidth - smallSize * 2.6) / minPitch))

  readonly property real smallSize: Math.max(Style.font.caption, pitch * 0.6)
  readonly property real bodySize: Math.max(Style.font.body, pitch * 0.72)
  readonly property real statSize: Math.max(Style.font.subtitle, pitch * 0.85)
  readonly property real titleSize: Math.max(Style.font.heading, pitch * 1.3)

  function stateColor(state) {
    if (!widget) return faint
    if (state === "success") return widget.successColor
    if (state === "failure") return widget.failureColor
    if (state === "running") return widget.runningColor
    return Util.alpha(Color.foreground, 0.25)
  }

  function stateWord(state, run) {
    if (state === "running") return run && run.status === "queued" ? "queued" : "running"
    if (state === "success") return "passed"
    if (state === "failure") return "failed"
    if (state === "cancelled") return "cancelled"
    return run && run.conclusion ? run.conclusion.replace(/_/g, " ") : ""
  }

  readonly property string ageText: {
    if (!widget) return ""
    if (widget.fetching) return "updating…"
    if (!widget.fetchedAt) return ""
    var age = Model.relativeTime(widget.fetchedAt, nowMs)
    return age === "now" ? "updated just now" : "updated " + age + " ago"
  }

  component Label: Text {
    textFormat: Text.PlainText
    color: root.fg
    font.family: root.family
    font.pixelSize: root.bodySize
    elide: Text.ElideRight
    maximumLineCount: 1
  }

  component Dot: Label {
    text: "·"
    color: root.dim
    font.pixelSize: root.statSize
  }

  component Stat: Row {
    property string glyph: ""
    property string value: ""
    property string word: ""
    property color tint: Color.accent
    spacing: root.statSize * 0.35
    Label { text: parent.glyph; color: parent.tint; font.pixelSize: root.statSize; anchors.verticalCenter: parent.verticalCenter }
    Label { text: parent.value + (parent.word ? " " + parent.word : ""); font.pixelSize: root.statSize; anchors.verticalCenter: parent.verticalCenter }
  }

  // ---- Glow: the accent, faint, around the heatmap.
  Shape {
    anchors.fill: parent
    visible: root.ok
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeWidth: -1
      startX: 0; startY: 0
      fillGradient: RadialGradient {
        centerX: root.width / 2
        centerY: stack.y + root.pad + heatmap.height * 0.6
        centerRadius: Math.max(root.width, root.height) * 0.62
        focalX: centerX
        focalY: centerY
        GradientStop { position: 0; color: Util.alpha(Color.accent, 0.2) }
        GradientStop { position: 0.45; color: Util.alpha(Color.accent, 0.07) }
        GradientStop { position: 1; color: Util.alpha(Color.accent, 0) }
      }
      PathLine { x: root.width; y: 0 }
      PathLine { x: root.width; y: root.height }
      PathLine { x: 0; y: root.height }
      PathLine { x: 0; y: 0 }
    }
  }

  Item {
    id: inner
    anchors.fill: parent
    anchors.margins: root.pad

    // ---- Without data: loading, or what went wrong.
    Column {
      visible: !root.ok
      anchors.centerIn: parent
      width: parent.width
      spacing: root.bodySize * 0.6

      Label {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: root.entry.repo
        font.pixelSize: root.titleSize
        font.bold: true
      }
      Label {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        maximumLineCount: 3
        color: root.result ? root.widget.failureColor : root.dim
        text: root.result ? (root.result.error || "")
          : root.widget && root.widget.fetchError ? root.widget.fetchError
          : "Loading…"
      }
    }

    Column {
      id: stack
      visible: root.ok
      // Pinned to the top: the heatmap and the repo stay put whatever the
      // list below them shows.
      anchors.horizontalCenter: parent.horizontalCenter
      y: 0
      width: heatmap.implicitWidth
      spacing: root.pitch * 1.1

      readonly property real textX: heatmap.gridX
      readonly property real textWidth: heatmap.gridWidth

      Heatmap {
        id: heatmap
        days: root.ok ? root.result.days : ({})
        nowMs: root.nowMs
        weeks: root.weeks
        pitch: root.pitch
        animate: root.animate
        rounded: root.rounded
        fontSize: root.smallSize
        dim: root.dim
        note: root.ageText
        width: implicitWidth
        height: implicitHeight
      }

      // ---- Who: avatar, name, description, numbers, year in numbers.
      Item {
        id: identity
        x: stack.textX
        width: stack.textWidth
        height: Math.max(avatarFrame.height, info.implicitHeight)

        readonly property var year: root.ok ? Model.yearStats(root.result.days, root.nowMs) : ({ total: 0, streak: 0, peak: 0, peakLabel: "" })

        Rectangle {
          id: avatarFrame
          visible: avatar.status === Image.Ready
          width: visible ? Math.round(info.implicitHeight * 0.92) : 0
          height: width
          color: "transparent"
          border.width: Math.max(2, Math.round(width * 0.05))
          border.color: Color.accent
          radius: root.rounded ? width * 0.18 : 0

          Image {
            id: avatar
            anchors.fill: parent
            anchors.margins: parent.border.width * 2
            source: root.ok && root.result.avatar ? Util.fileUrl(root.result.avatar) : ""
            sourceSize.width: 160
            sourceSize.height: 160
            fillMode: Image.PreserveAspectCrop
            smooth: true
            visible: false
          }

          MultiEffect {
            source: avatar
            anchors.fill: avatar
            // Dark photos would stay dark; lifted first, they come out in
            // the accent like a duotone.
            brightness: 0.35
            contrast: 0.35
            colorization: 1
            colorizationColor: Color.accent
          }
        }

        Column {
          id: info
          anchors.left: avatarFrame.right
          anchors.leftMargin: avatarFrame.visible ? root.pitch * 0.9 : 0
          anchors.right: parent.right
          spacing: root.statSize * 0.25

          Row {
            id: titleRow
            width: parent.width
            spacing: root.titleSize * 0.5

            Label {
              visible: root.ok && root.result.private
              text: ""
              color: Color.accent
              font.pixelSize: root.titleSize * 0.8
              anchors.baseline: title.baseline
            }
            Label {
              id: title
              readonly property string fullName: root.ok ? root.result.repo : root.entry.repo
              text: fullName.substring(fullName.indexOf("/") + 1)
              font.pixelSize: root.titleSize
              font.bold: true
              width: Math.min(implicitWidth, titleRow.width * 0.55)
            }
            Rectangle {
              id: branchChip
              visible: root.ok
              anchors.verticalCenter: title.verticalCenter
              color: Util.alpha(Color.accent, 0.14)
              radius: root.rounded ? height / 2 : 0
              width: branchLabel.implicitWidth + root.smallSize
              height: branchLabel.implicitHeight + root.smallSize * 0.3
              Label {
                id: branchLabel
                anchors.centerIn: parent
                text: root.ok ? " " + root.result.branch : ""
                color: Color.accent
                font.pixelSize: root.smallSize
              }
            }
            Label {
              anchors.baseline: title.baseline
              text: root.ok ? root.result.description : ""
              color: root.dim
              font.pixelSize: root.statSize
              width: Math.max(0, titleRow.width - title.width - branchChip.width - titleRow.spacing * 3 - (root.ok && root.result.private ? root.titleSize : 0))
            }
          }

          Flow {
            width: parent.width
            spacing: root.statSize * 0.55

            Stat { glyph: ""; value: root.ok ? Model.compactNumber(root.result.stars) : ""; word: "stars" }
            Dot {}
            Stat { glyph: ""; value: root.ok ? Model.compactNumber(root.result.forks) : ""; word: "forks" }
            Dot {}
            Stat { glyph: ""; value: root.ok ? Model.compactNumber(root.result.watchers) : ""; word: "watching" }
            Dot {}
            Stat { glyph: ""; value: root.ok ? Model.compactNumber(root.result.prs) : ""; word: "PRs" }
            Dot {}
            Stat { glyph: ""; value: root.ok ? Model.compactNumber(root.result.issues) : ""; word: "issues" }
            Dot { visible: root.ok && root.result.release !== "" }
            Stat { visible: root.ok && root.result.release !== ""; glyph: ""; value: root.ok ? root.result.release : "" }
          }

          Label {
            width: parent.width
            color: root.dim
            font.pixelSize: root.statSize
            text: root.ok ? [
              Model.withCommas(root.result.totalCommits) + " commits",
              Model.withCommas(identity.year.total) + " in the last year",
              identity.year.streak > 0 ? identity.year.streak + "-day streak" : "",
              identity.year.peak > 0 ? "peak " + identity.year.peak + " on " + identity.year.peakLabel : ""
            ].filter(function(s) { return s }).join("  ·  ") : ""
          }

          // Actions: the last runs, oldest left, and the newest in words.
          Row {
            id: ciRow
            width: parent.width
            spacing: root.statSize * 0.6
            readonly property var runs: root.ok ? root.result.runs.slice(0, 12).reverse() : []
            readonly property var latest: runs.length > 0 ? runs[runs.length - 1] : null
            readonly property string latestState: Model.runState(latest)

            Row {
              id: runBlocks
              anchors.verticalCenter: parent.verticalCenter
              spacing: Math.max(2, root.statSize * 0.2)
              visible: ciRow.runs.length > 0

              Repeater {
                model: ciRow.runs
                Rectangle {
                  required property var modelData
                  readonly property string state: Model.runState(modelData)
                  width: root.statSize * 0.7
                  height: width
                  radius: root.rounded ? width * 0.22 : 0
                  color: root.stateColor(state)

                  SequentialAnimation on opacity {
                    running: root.animate && state === "running"
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.35; duration: 800; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 800; easing.type: Easing.InOutSine }
                  }
                }
              }
            }

            Label {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - (runBlocks.visible ? runBlocks.width + parent.spacing : 0)
              font.pixelSize: root.statSize
              color: ciRow.latest ? root.stateColor(ciRow.latestState) : root.dim
              text: ciRow.latest
                ? [ciRow.latest.name, root.stateWord(ciRow.latestState, ciRow.latest), Model.duration(ciRow.latest, root.nowMs), Model.relativeTime(ciRow.latest.started, root.nowMs) + " ago"].filter(function(s) { return s }).join("  ·  ")
                : "no workflow runs"
            }
          }
        }
      }

      Rectangle {
        x: stack.textX
        width: stack.textWidth
        height: 1
        color: root.faint
      }

      // ---- While a workflow runs (and a minute after): its jobs and steps.
      WorkflowView {
        id: workflow
        visible: runs.length > 0
        x: stack.textX
        width: stack.textWidth
        height: visible ? implicitHeight : 0
        runs: root.widget && root.ok ? root.widget.liveRuns(root.result) : []
        nowMs: root.nowMs
        animate: root.animate
        fontSize: root.bodySize
        titleSize: root.statSize
        smallSize: root.smallSize
        dim: root.dim
        successColor: root.widget ? root.widget.successColor : "#9ece6a"
        runningColor: root.widget ? root.widget.runningColor : "#e0af68"
        failureColor: root.widget ? root.widget.failureColor : Color.urgent
        room: commits.room
      }

      // ---- Otherwise the latest commits: as many as the tile has room for,
      //      up to sixteen.
      Column {
        id: commits
        visible: !workflow.visible
        x: stack.textX
        width: stack.textWidth

        readonly property real rowHeight: Math.round(root.bodySize * 1.75)
        readonly property var list: root.ok ? root.result.commits : []
        // Column skips hidden items' spacing, so the room is the same with
        // either the commits or the workflow showing.
        readonly property real room: inner.height - heatmap.height - identity.height - 1 - stack.spacing * 3
        readonly property int shown: Math.max(0, Math.min(list.length, 16, Math.floor(room / rowHeight)))
        readonly property real shaWidth: root.bodySize * 0.6 * 8.5
        readonly property real timeWidth: root.bodySize * 0.6 * 15

        Repeater {
          model: commits.shown

          Item {
            required property int index
            readonly property var commit: commits.list[index]
            width: commits.width
            height: commits.rowHeight

            Label {
              id: sha
              width: commits.shaWidth
              anchors.verticalCenter: parent.verticalCenter
              text: commit.sha
              color: Color.accent
            }
            Label {
              id: author
              anchors.left: sha.right
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(implicitWidth, commits.width * 0.2)
              text: commit.author
            }
            Label {
              anchors.left: author.right
              anchors.leftMargin: root.bodySize
              anchors.right: time.left
              anchors.rightMargin: root.bodySize * 1.5
              anchors.verticalCenter: parent.verticalCenter
              text: commit.message
              color: root.dim
            }
            Label {
              id: time
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: commits.timeWidth
              horizontalAlignment: Text.AlignRight
              text: Model.commitTime(commit.date, root.nowMs)
              color: root.dim
            }
          }
        }
      }
    }
  }
}
