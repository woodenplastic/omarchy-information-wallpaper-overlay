import QtQuick
import QtQuick.Shapes
import qs.Commons
import "Model.js" as Model

// The Omarchy tile: how the machine is doing, from scripts/upkeep: whether it needs a reboot,
// pending updates, failed units, the last snapshot and free space. A ring
// with an arc per check, in the color of how it's doing, and the verdict
// beside it; then a card per check with its number (uptime, updates
// waiting, failed units, the snapshot's age, free space) and a bar where
// one says more; then, as room allows, the failed units and the packages
// waiting. On a small tile the lists go first, then the cards' small print.
Tile {
  id: root

  readonly property var feed: widget ? widget.upkeepFeed : null
  readonly property var info: feed && feed.loaded ? feed.output : null
  readonly property var items: info && Array.isArray(info.items) ? info.items : []
  readonly property var badItems: items.filter(function(i) { return i.state === "bad" })
  readonly property var warnItems: items.filter(function(i) { return i.state === "warn" })
  readonly property string overall: badItems.length > 0 ? "bad" : warnItems.length > 0 ? "warn" : items.length > 0 ? "ok" : "unknown"

  readonly property var updates: info && info.updates ? info.updates : ({ repo: [], aur: [], omarchy: "" })
  readonly property int updateCount: (updates.repo || []).length + (updates.aur || []).length
  readonly property var units: info && Array.isArray(info.units) ? info.units : []

  glowX: pad + ring.width / 2
  glowY: pad + hero.y + hero.height / 2

  function stateColor(state) {
    if (!widget) return faint
    if (state === "bad") return widget.failureColor
    if (state === "warn") return widget.runningColor
    if (state === "ok") return widget.successColor
    return Util.alpha(Color.foreground, 0.25)
  }

  // "12m", "5h", "13d".
  function age(seconds) {
    var s = Math.max(0, Number(seconds) || 0)
    if (s < 3600) return Math.max(1, Math.round(s / 60)) + "m"
    if (s < 172800) return Math.round(s / 3600) + "h"
    return Math.round(s / 86400) + "d"
  }

  function size(bytes) {
    var g = (Number(bytes) || 0) / 1073741824
    return g >= 1024 ? (g / 1024).toFixed(1) + "T" : Math.round(g) + "G"
  }

  // "4.29.9 → 4.30.0": the package release only when that's what changed.
  function versions(p) {
    var a = String(p.old || ""), b = String(p["new"] || "")
    var sa = a.replace(/-\d+(\.\d+)?$/, ""), sb = b.replace(/-\d+(\.\d+)?$/, "")
    return sa === sb ? a + " → " + b : sa + " → " + sb
  }

  // What the ring says, big, and under it what else is going on.
  readonly property string verdict: {
    if (items.length === 0) return "Looking…"
    if (badItems.length === 1) return badItems[0].title
    if (badItems.length > 1) return badItems.length + " things need you"
    if (warnItems.length > 0) return "Nothing urgent"
    return "All good"
  }

  readonly property string verdictMore: {
    var rest = items.filter(function(i) { return i.state === "warn" || (i.state === "bad" && root.badItems.length === 1 && i !== root.badItems[0]) || (i.state === "bad" && root.badItems.length > 1) })
    var words = rest.map(function(i) {
      if (i.key === "updates") return root.updateCount + (root.updateCount === 1 ? " update" : " updates") + " waiting"
      if (i.key === "snapshot") return "last snapshot " + i.title.replace(/^Snapshot /, "")
      return i.title.charAt(0).toLowerCase() + i.title.substring(1)
    })
    if (words.length > 0) return words.join("  ·  ")
    return items.length > 0 ? "nothing waiting, nothing failed" : ""
  }

  // A card per check: what it is, its number, the small print, and a bar
  // (0–1, or -1 for none) with an optional second share for the updates.
  function card(item) {
    var c = { key: item.key, cardState: item.state, label: "", value: "–", note: item.detail || "", bar: -1, split: -1 }
    var nowS = root.nowMs / 1000
    if (item.key === "reboot") {
      var r = info.reboot || {}
      c.label = "Reboot"
      c.value = item.state === "bad" ? "Due" : item.state === "warn" ? "Soon" : root.age(r.up)
      c.note = item.state === "ok" ? "up  ·  " + String(r.running || "").split("-")[0] : item.detail
    } else if (item.key === "updates") {
      c.label = "Updates"
      if (item.state === "unknown") {
        c.value = "…"
        c.note = "checking…"
      } else {
        c.value = String(root.updateCount)
        var parts = []
        if ((updates.repo || []).length > 0) parts.push(updates.repo.length + " repo")
        if ((updates.aur || []).length > 0) parts.push(updates.aur.length + " AUR")
        if (updates.omarchy) parts.unshift("Omarchy " + updates.omarchy)
        c.note = parts.length > 0 ? parts.join("  ·  ") : "up to date"
        c.split = root.updateCount > 0 ? (updates.repo || []).length / root.updateCount : -1
      }
    } else if (item.key === "units") {
      c.label = "Failed units"
      c.value = String(root.units.length)
      c.note = root.units.length === 0 ? "system and yours" : root.units[0].unit + (root.units.length > 1 ? "  +" + (root.units.length - 1) : "")
    } else if (item.key === "snapshot") {
      var at = info.snapshot && info.snapshot.at
      c.label = "Snapshot"
      c.value = at ? root.age(nowS - at) : "–"
      c.note = at ? item.detail : "can't tell"
      // A month without one fills the bar.
      c.bar = at ? Math.min(1, (nowS - at) / (30 * 86400)) : -1
    } else if (item.key.indexOf("disk:") === 0) {
      var mount = item.key.substring(5)
      var disk = (info.disks || []).filter(function(d) { return d.mount === mount })[0]
      c.label = "Free on " + mount
      c.value = disk ? Math.round(disk.share * 100) + "%" : "–"
      c.note = disk ? root.size(disk.free) + " of " + root.size(disk.total) : item.detail
      // The bar is what's used.
      c.bar = disk ? 1 - disk.share : -1
    } else {
      c.label = item.title
      c.value = ""
    }
    return c
  }

  readonly property var allCards: info ? items.map(card) : []
  // On a tile too small for them all, the cards that need a look come
  // first and the rest are left to the ring.
  readonly property var cards: {
    var list = allCards
    if (list.length <= grid.fitCards) return list
    var rank = { bad: 0, warn: 1, unknown: 2, ok: 3 }
    var order = list.map(function(c, i) { return { c: c, i: i } })
    order.sort(function(a, b) { return rank[a.c.cardState] - rank[b.c.cardState] || a.i - b.i })
    return order.slice(0, grid.fitCards).map(function(o) { return o.c })
  }

  component Label: Text {
    textFormat: Text.PlainText
    color: root.fg
    font.family: root.family
    font.pixelSize: root.bodySize
    elide: Text.ElideRight
    maximumLineCount: 1
  }

  // A thin bar, filled to `fill` (0–1) in `tint`; with `split` the fill's
  // first part is solid and the rest lighter (repo and AUR updates).
  component Bar: Rectangle {
    id: bar
    property real fill: 0
    property real split: -1
    property color tint: Color.accent
    height: Math.max(3, Math.round(root.bodySize * 0.24))
    radius: root.rounded ? height / 2 : 0
    color: root.faint

    Rectangle {
      width: parent.width * Math.max(0, Math.min(1, bar.fill))
      height: parent.height
      radius: parent.radius
      color: bar.tint
      opacity: bar.split >= 0 ? 0.45 : 0.9
    }
    Rectangle {
      visible: bar.split >= 0
      width: parent.width * Math.max(0, Math.min(1, bar.split))
      height: parent.height
      radius: parent.radius
      color: bar.tint
    }
  }

  // ---- Title.
  Row {
    id: header
    spacing: root.titleSize * 0.45

    // Omarchy's logo, from its own font, as on the bar's menu button.
    Label {
      anchors.baseline: titleText.baseline
      text: "\ue900"
      color: Color.accent
      font.family: "omarchy"
      font.pixelSize: root.titleSize * 0.85
    }
    Label {
      id: titleText
      text: "Omarchy"
      font.pixelSize: root.titleSize
      font.bold: true
    }
  }

  // ---- The ring and the verdict.
  Item {
    id: hero
    anchors.top: header.bottom
    anchors.topMargin: root.statSize * 0.9
    width: parent.width
    height: ring.height

    // An arc per check, a small gap between them, starting at the top.
    Item {
      id: ring
      width: Math.round(Math.max(root.statSize * 2.6, Math.min(root.titleSize * 5, root.area.height * 0.17)))
      height: width

      readonly property real stroke: Math.max(3, width * 0.09)
      readonly property real radius: (width - stroke) / 2
      readonly property int count: Math.max(1, root.items.length)
      readonly property real gapDeg: root.items.length > 1 ? 9 : 0
      readonly property real sweep: 360 / count - gapDeg

      // The arcs grow in when the data comes, if animations are on.
      property real grown: 0
      Component.onCompleted: grown = root.items.length > 0 ? 1 : 0
      Connections {
        target: root
        function onItemsChanged() { if (ring.grown === 0 && root.items.length > 0) ring.grown = 1 }
      }
      Behavior on grown {
        enabled: root.animate
        NumberAnimation { duration: 900; easing.type: Easing.OutCubic }
      }

      // The track under the arcs.
      Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          strokeColor: root.faint
          strokeWidth: ring.stroke
          fillColor: "transparent"
          PathAngleArc {
            centerX: ring.width / 2
            centerY: ring.height / 2
            radiusX: ring.radius
            radiusY: ring.radius
            startAngle: 0
            sweepAngle: 360
          }
        }
      }

      Repeater {
        model: root.items.length

        Shape {
          id: arc
          required property int index
          readonly property string arcState: root.items[index] ? root.items[index].state : "unknown"
          anchors.fill: parent
          preferredRendererType: Shape.CurveRenderer

          ShapePath {
            strokeColor: root.stateColor(arc.arcState)
            strokeWidth: ring.stroke
            fillColor: "transparent"
            capStyle: root.rounded ? ShapePath.RoundCap : ShapePath.FlatCap
            PathAngleArc {
              centerX: ring.width / 2
              centerY: ring.height / 2
              radiusX: ring.radius
              radiusY: ring.radius
              // Round caps reach past the arc's ends; the gap allows for them.
              startAngle: -90 + arc.index * (ring.sweep + ring.gapDeg) + ring.gapDeg / 2
              sweepAngle: Math.max(0.1, ring.sweep * ring.grown)
            }
          }

          opacity: root.animate && arcState === "bad" ? Model.breathe(root.pulseMs, 0.35) : 1
        }
      }

      Label {
        anchors.centerIn: parent
        // A check, or how many need you.
        text: root.overall === "bad" ? String(root.badItems.length) : root.overall === "unknown" ? "" : ""
        color: root.stateColor(root.overall === "unknown" ? "unknown" : root.overall === "bad" ? "bad" : root.overall === "warn" ? "warn" : "ok")
        font.pixelSize: ring.width * (root.overall === "bad" ? 0.42 : 0.34)
        font.bold: true
      }
    }

    Column {
      anchors.left: ring.right
      anchors.leftMargin: root.statSize * 1.1
      anchors.right: parent.right
      anchors.verticalCenter: ring.verticalCenter
      spacing: root.smallSize * 0.35

      Label {
        width: parent.width
        text: root.verdict
        font.pixelSize: Math.round(root.titleSize * 1.15)
        font.bold: true
        color: root.overall === "bad" ? root.stateColor("bad") : root.fg
      }
      Label {
        width: parent.width
        visible: text !== ""
        text: root.verdictMore
        color: root.dim
      }
    }
  }

  // ---- A card per check.
  Item {
    id: grid
    anchors.top: hero.bottom
    anchors.topMargin: root.statSize * 1.1
    width: parent.width
    height: rows * cardHeight + Math.max(0, rows - 1) * gap
    visible: root.cards.length > 0

    readonly property real gap: Math.round(root.bodySize * 0.8)
    // As many to a row as fit, the rows as even as they can be: five make
    // three and two, not four and one.
    readonly property int fit: Math.max(1, Math.min(root.allCards.length, Math.floor((width + gap) / (root.bodySize * 9 + gap))))
    readonly property int rows: Math.max(1, Math.ceil(root.cards.length / fit))
    readonly property int cols: Math.max(1, Math.ceil(root.cards.length / rows))
    readonly property real cardWidth: (width - (cols - 1) * gap) / cols
    readonly property real padding: Math.round(root.bodySize * 0.8)
    // The number grows on a roomy tile.
    readonly property real valueSize: Math.round(Math.max(root.titleSize * 1.25, Math.min(root.titleSize * 2, root.area.height * 0.055)))
    readonly property real fullHeight: Math.round(padding * 2 + root.smallSize * 1.5 + valueSize * 1.25 + root.smallSize * 1.5 + root.bodySize * 0.9)
    readonly property real shortHeight: Math.round(padding * 2 + root.smallSize * 1.5 + valueSize * 1.25)
    // The small print goes before anything else is cut.
    readonly property real room: root.area.height - y
    // How many cards fit at all, short, in the rows there's room for.
    readonly property int fitCards: Math.max(fit, fit * Math.floor((room + gap) / (shortHeight + gap)))
    readonly property bool full: rows * fullHeight + (rows - 1) * gap <= room
    readonly property real cardHeight: full ? fullHeight : shortHeight

    Repeater {
      model: root.cards.length

      Rectangle {
        id: cardBox
        required property int index
        readonly property var c: root.cards[index] || ({})
        readonly property bool attention: c.cardState === "bad" || c.cardState === "warn"
        x: (index % grid.cols) * (grid.cardWidth + grid.gap)
        y: Math.floor(index / grid.cols) * (grid.cardHeight + grid.gap)
        width: grid.cardWidth
        height: grid.cardHeight
        radius: root.rounded ? Math.min(root.radius, root.bodySize * 0.6) : 0
        color: Util.alpha(attention ? root.stateColor(c.cardState) : Color.foreground, attention ? 0.1 : 0.045)
        border.width: 1
        border.color: Util.alpha(attention ? root.stateColor(c.cardState) : Color.foreground, attention ? 0.35 : 0.07)

        // How it's doing, as a mark in the corner.
        Rectangle {
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: grid.padding
          width: Math.round(root.smallSize * 0.6)
          height: width
          radius: root.rounded ? width / 2 : 0
          color: root.stateColor(cardBox.c.cardState)
        }

        Column {
          anchors.fill: parent
          anchors.margins: grid.padding
          spacing: 0

          Label {
            width: parent.width - root.smallSize
            height: root.smallSize * 1.5
            verticalAlignment: Text.AlignVCenter
            text: String(cardBox.c.label || "").toUpperCase()
            font.pixelSize: root.smallSize
            font.letterSpacing: root.smallSize * 0.08
            color: root.dim
          }
          Label {
            width: parent.width
            height: grid.valueSize * 1.25
            verticalAlignment: Text.AlignVCenter
            text: cardBox.c.value || ""
            font.pixelSize: grid.valueSize
            font.bold: true
            color: cardBox.c.cardState === "bad" ? root.stateColor("bad") : cardBox.c.cardState === "warn" ? root.stateColor("warn") : root.fg
          }
          Label {
            visible: grid.full
            width: parent.width
            height: root.smallSize * 1.5
            verticalAlignment: Text.AlignVCenter
            text: cardBox.c.note || ""
            font.pixelSize: root.smallSize
            color: root.dim
          }
          Item {
            visible: grid.full
            width: parent.width
            height: root.bodySize * 0.9

            Bar {
              visible: cardBox.c.bar >= 0 || cardBox.c.split >= 0
              anchors.bottom: parent.bottom
              width: parent.width
              fill: cardBox.c.split >= 0 ? 1 : cardBox.c.bar
              split: cardBox.c.split
              tint: cardBox.c.key === "updates" ? Color.accent : root.stateColor(cardBox.c.cardState)
            }
          }
        }
      }
    }
  }

  // ---- As room allows: the failed units, then the packages waiting.
  Column {
    id: lists
    anchors.top: grid.bottom
    anchors.topMargin: root.statSize * 1.1
    width: parent.width
    spacing: root.bodySize * 0.9

    readonly property real lineHeight: Math.round(root.bodySize * 1.6)
    readonly property real headHeight: Math.round(root.smallSize * 2)
    readonly property real room: root.area.height - y
    // Units first: they're what's broken.
    readonly property int unitLines: root.units.length === 0 ? 0 : Math.max(0, Math.min(root.units.length, Math.floor((room - headHeight) / lineHeight)))
    readonly property real unitsHeight: unitLines > 0 ? headHeight + unitLines * lineHeight + spacing : 0
    readonly property var packages: (root.updates.omarchy ? [{ name: "omarchy", old: "", "new": root.updates.omarchy, omarchy: true }] : [])
      .concat((root.updates.repo || []).map(function(p) { return { name: p.name, old: p.old, "new": p["new"] } }))
      .concat((root.updates.aur || []).map(function(p) { return { name: p.name, old: p.old, "new": p["new"], aur: true } }))
    // Two columns when the tile is wide.
    readonly property int columns: width > root.bodySize * 70 ? 2 : 1
    readonly property int packageRows: packages.length === 0 ? 0 : Math.max(0, Math.min(Math.ceil(packages.length / columns), Math.floor((room - unitsHeight - headHeight) / lineHeight)))
    // A last row of "and N more" when they don't all fit.
    readonly property int packageSlots: {
      var n = Math.min(packages.length, packageRows * columns)
      // A lone "and N more" says nothing.
      return n === 1 && packages.length > 1 ? 0 : n
    }

    component Head: Item {
      property string text: ""
      property string aside: ""
      property color tint: root.dim
      width: lists.width
      height: lists.headHeight

      Label {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: parent.text.toUpperCase()
        font.pixelSize: root.smallSize
        font.letterSpacing: root.smallSize * 0.08
        color: parent.tint
      }
      Label {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: parent.aside
        font.pixelSize: root.smallSize
        color: root.dim
      }
      Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: root.faint
      }
    }

    Column {
      visible: lists.unitLines > 0
      width: parent.width

      Head {
        text: "Failed units"
        tint: root.stateColor("bad")
      }
      Repeater {
        model: lists.unitLines

        Item {
          required property int index
          readonly property var unit: root.units[index] || ({})
          width: lists.width
          height: lists.lineHeight

          Label {
            id: unitName
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, parent.width * 0.5)
            text: parent.unit.unit + (parent.unit.user ? "  (yours)" : "")
            color: root.stateColor("bad")
          }
          Label {
            anchors.left: unitName.right
            anchors.leftMargin: root.bodySize
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: parent.unit.description || ""
            color: root.dim
          }
        }
      }
    }

    Column {
      visible: lists.packageSlots > 0
      width: parent.width

      Head {
        text: "Waiting to update"
        aside: root.updates.checked ? "checked " + (root.nowMs / 1000 - root.updates.checked < 90 ? "just now" : root.age(root.nowMs / 1000 - root.updates.checked) + " ago") : ""
      }
      Grid {
        width: parent.width
        columns: lists.columns
        columnSpacing: root.bodySize * 2

        Repeater {
          model: lists.packageSlots

          Item {
            id: pkg
            required property int index
            readonly property var p: lists.packages[index] || ({})
            // The last slot says what's left when they don't all fit.
            readonly property bool more: index === lists.packageSlots - 1 && lists.packages.length > lists.packageSlots
            width: (lists.width - (lists.columns - 1) * root.bodySize * 2) / lists.columns
            height: lists.lineHeight

            Label {
              visible: pkg.more
              anchors.verticalCenter: parent.verticalCenter
              text: "and " + (lists.packages.length - pkg.index) + " more"
              color: root.dim
            }
            Label {
              id: pkgName
              visible: !pkg.more
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(implicitWidth, parent.width * 0.5)
              text: pkg.p.name || ""
              color: pkg.p.omarchy ? Color.accent : root.fg
              font.bold: !!pkg.p.omarchy
            }
            Rectangle {
              id: aurTag
              visible: !pkg.more && !!pkg.p.aur
              anchors.left: pkgName.right
              anchors.leftMargin: root.bodySize * 0.5
              anchors.verticalCenter: parent.verticalCenter
              width: aurText.implicitWidth + root.smallSize * 0.8
              height: root.smallSize * 1.35
              radius: root.rounded ? height * 0.3 : 0
              color: "transparent"
              border.width: 1
              border.color: Util.alpha(Color.foreground, 0.2)

              Label {
                id: aurText
                anchors.centerIn: parent
                text: "AUR"
                font.pixelSize: root.smallSize * 0.8
                color: root.dim
              }
            }
            Label {
              visible: !pkg.more
              anchors.left: aurTag.visible ? aurTag.right : pkgName.right
              anchors.leftMargin: root.bodySize * 0.8
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              horizontalAlignment: Text.AlignRight
              text: pkg.p.omarchy ? "new version " + pkg.p["new"] : root.versions(pkg.p)
              color: root.dim
              font.pixelSize: root.smallSize
            }
          }
        }
      }
    }
  }
}
