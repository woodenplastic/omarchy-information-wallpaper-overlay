import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons
import "Model.js" as Model

// One repo on the desk: a borderless panel in the theme's background. On a soft
// accent glow: the year of commits as a heatmap, the owner's avatar in the
// accent color beside the name, the numbers, the Actions runs, why the
// latest one failed, the open pull requests, and the latest commits.
// Everything scales with the tile.
Rectangle {
  id: root

  property var widget: null
  property var entry: ({ repo: "", branch: "" })
  property var result: null
  readonly property bool ok: !!result && result.ok === true
  // Whether the desk this tile is on can be seen; a desk per display.
  property bool shown: true
  readonly property real nowMs: widget ? widget.nowMs : Date.now()
  readonly property bool animate: !!widget && widget.animate && shown

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

  // A pull request's checks, in the runs' words.
  function checksState(state) {
    if (state === "SUCCESS") return "success"
    if (state === "FAILURE" || state === "ERROR") return "failure"
    if (state === "PENDING" || state === "EXPECTED") return "running"
    return "neutral"
  }

  function pullWords(pull) {
    var checks = checksState(pull.checks)
    return [
      pull.conflicts ? "conflicts" : "",
      checks === "success" ? "passing" : checks === "failure" ? "failing" : checks === "running" ? "checks running" : "",
      pull.review === "APPROVED" ? "approved" : pull.review === "CHANGES_REQUESTED" ? "changes requested" : pull.review === "REVIEW_REQUIRED" ? "needs review" : "",
      Model.relativeTime(pull.updated, root.nowMs)
    ].filter(function(s) { return s }).join("  ·  ")
  }

  readonly property string ageText: {
    if (!widget) return ""
    if (widget.fetching) return "updating…"
    // A stale result is the last one GitHub gave, kept through a failed fetch.
    var at = (result && result.fetched) || widget.fetchedAt
    if (!at) return ""
    var age = Model.relativeTime(at, nowMs)
    var updated = age === "now" ? "updated just now" : "updated " + age + " ago"
    if (result && result.stale) return (result.offline ? "offline" : "couldn't update") + " · " + updated
    return updated
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
        // No network is no fault of the repo's.
        color: root.result && !root.result.offline ? root.widget.failureColor : root.dim
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
      // Below the rule: the failure, the pull requests and the commits (or
      // the live workflow) share it. Column skips hidden items' spacing.
      readonly property real room: inner.height - heatmap.height - identity.height - 1 - spacing * 3

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
          // As tall as the lines beside it would be unwrapped, and at most
          // a quarter of the width: sized from what wraps beside it, a
          // narrow tile's wrapping grew the avatar, which narrowed and
          // wrapped the lines more, until it filled the tile.
          width: visible ? Math.round(Math.min(stack.textWidth * 0.25, (titleRow.height + yearLine.height * 3 + info.spacing * 3) * 0.92)) : 0
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

          // The numbers with their words, wrapped to two lines at most;
          // narrower, they go without the words and dots.
          TextMetrics {
            id: statsMeasure
            font.family: root.family
            font.pixelSize: root.statSize
            text: root.ok ? [
              Model.compactNumber(root.result.stars) + " stars", Model.compactNumber(root.result.forks) + " forks",
              Model.compactNumber(root.result.watchers) + " watching", Model.compactNumber(root.result.prs) + " PRs",
              Model.compactNumber(root.result.issues) + " issues", root.result.release
            ].join(" · ") : ""
          }

          Flow {
            id: stats
            // Each number's glyph and its gap besides the words.
            readonly property bool compact: statsMeasure.advanceWidth + 6 * root.statSize * 1.4 > width * 2
            width: parent.width
            spacing: root.statSize * (stats.compact ? 0.9 : 0.55)

            Stat { glyph: ""; value: root.ok ? Model.compactNumber(root.result.stars) : ""; word: stats.compact ? "" : "stars" }
            Dot { visible: !stats.compact }
            Stat { glyph: ""; value: root.ok ? Model.compactNumber(root.result.forks) : ""; word: stats.compact ? "" : "forks" }
            Dot { visible: !stats.compact }
            Stat { glyph: ""; value: root.ok ? Model.compactNumber(root.result.watchers) : ""; word: stats.compact ? "" : "watching" }
            Dot { visible: !stats.compact }
            Stat { glyph: ""; value: root.ok ? Model.compactNumber(root.result.prs) : ""; word: stats.compact ? "" : "PRs" }
            Dot { visible: !stats.compact }
            Stat { glyph: ""; value: root.ok ? Model.compactNumber(root.result.issues) : ""; word: stats.compact ? "" : "issues" }
            Dot { visible: !stats.compact && root.ok && root.result.release !== "" }
            Stat { visible: root.ok && root.result.release !== ""; glyph: ""; value: root.ok ? root.result.release : "" }
          }

          Label {
            id: yearLine
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

      // ---- Why the latest run failed: the job and step, and the last
      //      lines before the error. Not while a run is shown live.
      Rectangle {
        id: failure
        readonly property var why: root.ok ? root.result.failure : null
        readonly property real headerHeight: Math.round(root.bodySize * 1.6)
        readonly property real lineHeight: Math.round(root.smallSize * 1.45)
        readonly property real inset: Math.round(root.smallSize * 0.7)
        readonly property var lines: why && why.lines ? why.lines : []
        // At most a bit under half the room; the commits get the rest.
        readonly property int linesShown: Math.max(0, Math.min(lines.length, Math.floor((stack.room * 0.45 - headerHeight - inset * 2) / lineHeight)))
        // When not all fit, the ones that name the trouble come first, then
        // the latest; in their order either way.
        readonly property var picked: {
          var n = linesShown, out = []
          var telling = /error|fail|fatal|cannot|can't|not found|undefined|expected|denied|✕|×|✗/i
          for (var i = lines.length - 1; i >= 0 && out.length < n; i--) if (telling.test(lines[i])) out.push(i)
          for (var j = lines.length - 1; j >= 0 && out.length < n; j--) if (out.indexOf(j) === -1) out.push(j)
          return out.sort(function(a, b) { return a - b }).map(function(k) { return lines[k] })
        }
        visible: !!why && !workflow.visible && stack.room >= headerHeight + commits.rowHeight * 2
        x: stack.textX
        width: stack.textWidth
        height: visible ? headerHeight + (linesShown > 0 ? linesShown * lineHeight + inset * 2 : 0) : 0
        radius: root.rounded ? root.smallSize * 0.5 : 0
        color: root.widget ? Util.alpha(root.widget.failureColor, 0.08) : "transparent"

        Label {
          id: failureTitle
          x: failure.inset
          width: parent.width - failure.inset * 2
          height: failure.headerHeight
          verticalAlignment: Text.AlignVCenter
          color: root.stateColor("failure")
          text: !failure.why ? ""
            : " " + (failure.why.workflow || "Workflow") + " failed"
              + (failure.why.job ? " in " + failure.why.job + (failure.why.step ? " › " + failure.why.step : "") : "")
              + (failure.why.jobs > 1 ? "  (+" + (failure.why.jobs - 1) + (failure.why.jobs === 2 ? " job)" : " jobs)") : "")
        }

        Column {
          x: failure.inset
          y: failure.headerHeight + failure.inset * 0.4
          width: parent.width - failure.inset * 2

          Repeater {
            model: failure.linesShown

            Label {
              required property int index
              width: parent.width
              height: failure.lineHeight
              verticalAlignment: Text.AlignVCenter
              font.pixelSize: root.smallSize
              color: root.dim
              text: failure.picked[index] || ""
            }
          }
        }
      }

      // ---- The newest open pull requests, as fit: checks, review, age.
      Column {
        id: pulls
        readonly property var list: root.ok && root.result.pulls ? root.result.pulls : []
        readonly property real headerHeight: Math.round(root.smallSize * 1.7)
        readonly property real room: stack.room - (failure.visible ? failure.height + stack.spacing : 0)
        readonly property int shown: Math.max(0, Math.min(list.length, 3, Math.floor((room * 0.6 - headerHeight) / commits.rowHeight)))
        visible: shown > 0
        x: stack.textX
        width: stack.textWidth
        readonly property real wordsWidth: Math.min(width * 0.45, root.bodySize * 0.6 * 47)

        Label {
          width: pulls.width
          height: pulls.headerHeight
          verticalAlignment: Text.AlignVCenter
          font.pixelSize: root.smallSize
          color: root.dim
          text: !root.ok ? "" : " Pull requests  ·  " + root.result.prs + " open"
            + (root.result.prs > pulls.shown ? ", newest " + pulls.shown + " shown" : "")
        }

        Repeater {
          model: pulls.shown

          Item {
            id: pullRow
            required property int index
            readonly property var pull: pulls.list[index]
            readonly property string checks: root.checksState(pull.checks)
            width: pulls.width
            height: commits.rowHeight
            opacity: pull.draft ? 0.55 : 1

            Rectangle {
              id: checksBlock
              anchors.verticalCenter: parent.verticalCenter
              width: root.statSize * 0.6
              height: width
              radius: root.rounded ? width * 0.22 : 0
              color: root.stateColor(pullRow.checks)

              SequentialAnimation on opacity {
                running: root.animate && pullRow.checks === "running"
                loops: Animation.Infinite
                onRunningChanged: if (!running) checksBlock.opacity = 1
                NumberAnimation { to: 0.35; duration: 800; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 800; easing.type: Easing.InOutSine }
              }
            }
            Label {
              id: pullNumber
              anchors.left: checksBlock.right
              anchors.leftMargin: root.bodySize * 0.6
              anchors.verticalCenter: parent.verticalCenter
              text: "#" + pullRow.pull.number
              color: Color.accent
            }
            Label {
              id: pullTitle
              anchors.left: pullNumber.right
              anchors.leftMargin: root.bodySize * 0.6
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(implicitWidth, pullRow.width - checksBlock.width - pullNumber.width - pulls.wordsWidth - pullAuthor.implicitWidth - root.bodySize * 4)
              text: (pullRow.pull.draft ? "Draft: " : "") + pullRow.pull.title
            }
            Label {
              id: pullAuthor
              anchors.left: pullTitle.right
              anchors.leftMargin: root.bodySize * 0.8
              anchors.right: pullWords.left
              anchors.rightMargin: root.bodySize
              anchors.verticalCenter: parent.verticalCenter
              text: pullRow.pull.author
              color: root.dim
            }
            Label {
              id: pullWords
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: pulls.wordsWidth
              horizontalAlignment: Text.AlignRight
              color: pullRow.pull.conflicts || pullRow.pull.review === "CHANGES_REQUESTED" ? root.stateColor("failure") : root.dim
              text: root.pullWords(pullRow.pull)
            }
          }
        }
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
        // What the failure and the pull requests leave; the same with
        // either the commits or the workflow showing.
        readonly property real room: pulls.room - (pulls.visible ? pulls.height + stack.spacing : 0)
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
