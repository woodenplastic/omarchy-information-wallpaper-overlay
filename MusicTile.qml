import QtQuick
import Quickshell.Services.Mpris
import qs.Commons
import "Model.js" as Model

// What's playing: the cover, title, artist and album, the player, and how
// far into the track it is. The player is the one the shell's media widget
// shows; without the shell's media service (on the lock screen), the one
// playing, else the first with a track.
Tile {
  id: root

  readonly property var service: widget ? widget.mediaService : null
  readonly property var player: service ? service.activePlayer : fallbackPlayer
  readonly property var fallbackPlayer: {
    var list = Mpris.players ? Mpris.players.values : []
    var withTrack = null
    for (var i = 0; i < list.length; i++) {
      if (list[i].isPlaying) return list[i]
      if (!withTrack && list[i].trackTitle) withTrack = list[i]
    }
    return withTrack
  }

  readonly property bool ok: !!player && !!(player.trackTitle || player.trackArtist)
  readonly property bool playing: ok && player.isPlaying
  readonly property real length: ok && player.lengthSupported ? player.length : 0
  readonly property real position: ok && player.positionSupported ? player.position : 0

  // The cover beside the text in a wide tile, above it in a tall one.
  readonly property bool stacked: area.height > area.width * 0.9
  readonly property real coverSize: stacked
    ? Math.min(area.width * 0.8, area.height * 0.5)
    : Math.min(area.height * 0.86, area.width * 0.4)

  glowX: pad + cover.x + cover.width / 2
  glowY: pad + cover.y + cover.height / 2

  // ---- A sharp cover, looked up by artist and title (see Model.coverTrack):
  // players in a browser only get a thumbnail.

  readonly property var coverTrack: ok ? Model.coverTrack(player.trackTitle, player.trackArtist) : ({ title: "", artist: "" })
  readonly property string coverKey: coverTrack.title ? coverTrack.artist + "\n" + coverTrack.title : ""
  property var coverCache: ({})
  property string sharpArt: ""

  onCoverKeyChanged: lookUpCover()
  Component.onCompleted: lookUpCover()

  function lookUpCover() {
    var key = coverKey
    if (!key) { sharpArt = ""; return }
    if (coverCache[key] !== undefined) { sharpArt = coverCache[key]; return }
    sharpArt = ""
    var track = coverTrack
    var done = function(found) {
      root.coverCache[key] = found
      if (root.coverKey === key) root.sharpArt = found
    }
    // The catalogue first, then YouTube for videos.
    fetchText(Model.coverQueryUrl(track), function(text) {
      var found = ""
      try { found = Model.pickCover(JSON.parse(text).results, track, 1000) } catch (e) {}
      if (found) return done(found)
      fetchText(Model.youtubeQueryUrl(track), function(html) {
        var id = Model.pickYoutubeVideo(html, track)
        done(id ? "https://i.ytimg.com/vi/" + id + "/maxresdefault.jpg" : "")
      })
    })
  }

  // Calls back with the body of a successful GET, while the tile still exists
  // (the desk is rebuilt as the shell starts).
  function fetchText(url, callback) {
    var xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE || !root) return
      if (xhr.status === 200) callback(xhr.responseText)
    }
    xhr.open("GET", url)
    xhr.send()
  }

  // The player reports its position when asked, so it's asked each second.
  Timer {
    running: root.playing && root.visible && root.player.positionSupported
    repeat: true
    interval: 1000
    onTriggered: root.player.positionChanged()
  }

  component Label: Text {
    textFormat: Text.PlainText
    color: root.fg
    font.family: root.family
    font.pixelSize: root.bodySize
    elide: Text.ElideRight
    maximumLineCount: 1
  }

  // ---- The cover, or a note in its place.
  Rectangle {
    id: cover
    width: root.coverSize
    height: width
    x: root.stacked ? (root.area.width - width) / 2 : 0
    y: root.stacked ? (root.area.height - width - info.implicitHeight - root.statSize * 1.5) / 2 : (root.area.height - height) / 2
    color: Util.alpha(Color.accent, 0.1)
    border.width: Math.max(2, Math.round(width * 0.012))
    border.color: Util.alpha(Color.accent, art.status === Image.Ready || sharp.status === Image.Ready ? 0.6 : 0.3)
    radius: root.rounded ? Math.max(root.radius, width * 0.04) : 0
    clip: true

    Image {
      id: art
      anchors.fill: parent
      anchors.margins: parent.border.width
      source: root.ok && root.player.trackArtUrl ? root.player.trackArtUrl : ""
      sourceSize.width: 600
      sourceSize.height: 600
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      smooth: true
      opacity: root.playing ? 1 : 0.55
      Behavior on opacity { NumberAnimation { duration: 300 } }
    }

    // Over the player's cover once loaded, so a change of track never blanks it.
    Image {
      id: sharp
      anchors.fill: art
      source: root.sharpArt
      sourceSize.width: 1000
      sourceSize.height: 1000
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      smooth: true
      mipmap: true
      opacity: status === Image.Ready ? art.opacity : 0
      // Not every video has a full-size thumbnail; the 480px one always exists.
      onStatusChanged: if (status === Image.Error && root.sharpArt.indexOf("/maxresdefault.") !== -1)
        root.sharpArt = root.sharpArt.replace("/maxresdefault.", "/hqdefault.")
      Behavior on opacity { NumberAnimation { duration: 300 } }
    }

    Label {
      visible: art.status !== Image.Ready && sharp.status !== Image.Ready
      anchors.centerIn: parent
      text: ""
      color: Util.alpha(Color.accent, 0.7)
      font.pixelSize: parent.width * 0.32
    }
  }

  // ---- Title, artist, album, and the time.
  Column {
    id: info
    x: root.stacked ? 0 : cover.width + root.titleSize
    y: root.stacked ? cover.y + cover.height + root.statSize * 1.5 : (root.area.height - implicitHeight) / 2
    width: root.stacked ? root.area.width : root.area.width - x
    spacing: root.statSize * 0.35

    readonly property int align: root.stacked ? Text.AlignHCenter : Text.AlignLeft

    Label {
      width: parent.width
      horizontalAlignment: info.align
      text: !root.ok ? "" : [
        root.player.identity || root.player.desktopEntry || "",
        root.playing ? "playing" : "paused"
      ].filter(function(s) { return s }).join("  ·  ").toUpperCase()
      color: root.playing ? Color.accent : root.dim
      font.pixelSize: root.smallSize
      font.letterSpacing: root.smallSize * 0.12
    }
    Label {
      width: parent.width
      horizontalAlignment: info.align
      text: root.ok ? (root.player.trackTitle || "") : "Nothing playing"
      color: root.ok ? root.fg : root.dim
      font.pixelSize: root.titleSize
      font.bold: root.ok
      wrapMode: Text.Wrap
      maximumLineCount: 2
    }
    Label {
      width: parent.width
      horizontalAlignment: info.align
      visible: root.ok && text !== ""
      text: root.ok ? (root.player.trackArtist || "") : ""
      font.pixelSize: root.statSize
    }
    Label {
      width: parent.width
      horizontalAlignment: info.align
      visible: root.ok && text !== ""
      text: root.ok ? (root.player.trackAlbum || "") : ""
      color: root.dim
      font.pixelSize: root.statSize
    }

    Item { width: 1; height: root.statSize * 0.6; visible: bar.visible }

    // How far into the track.
    Rectangle {
      id: bar
      visible: root.length > 0
      width: parent.width
      height: Math.max(3, Math.round(root.bodySize * 0.3))
      radius: root.rounded ? height / 2 : 0
      color: root.faint

      Rectangle {
        width: parent.width * Util.clamp(root.position / Math.max(1, root.length), 0, 1)
        height: parent.height
        radius: parent.radius
        color: root.playing ? Color.accent : root.dim
      }
    }

    Item {
      visible: bar.visible
      width: parent.width
      height: positionLabel.implicitHeight

      Label {
        id: positionLabel
        text: Model.clockTime(root.position)
        color: root.dim
        font.pixelSize: root.smallSize
      }
      Label {
        anchors.right: parent.right
        text: Model.clockTime(root.length)
        color: root.dim
        font.pixelSize: root.smallSize
      }
    }
  }
}
