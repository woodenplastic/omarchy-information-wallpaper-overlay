.pragma library

var MAX_TILES = 6
// What a slot can show.
var KINDS = ["github", "herdr", "music", "tasks", "plugin", "workspace", "upkeep", "projects", "devices", "board"]
// The kinds that can stay off the desk while there's nothing to show.
var QUIET_KINDS = ["github", "herdr", "tasks", "workspace", "upkeep", "projects", "devices", "board"]
var ACTIVITY_DAYS = 28

// ---- Pulse: everything on the desk that breathes or sparkles follows one
//      clock (pulseMs in Overlay and LockFeed), ticking PULSE_HZ times a
//      second while the desk animates. A Qt Quick window draws all of itself
//      again for any change, so a dot pulsing at 60 fps cost as much as
//      animating the whole full-screen desk, a third of a core on a small
//      machine; stepped a few times a second it costs a few percent.
var PULSE_HZ = 5
var PULSE_MS = 2000

// The opacity of a dot breathing down to `low` and back, at clock time `ms`.
function breathe(ms, low) {
  var phase = 0.5 - 0.5 * Math.cos(2 * Math.PI * (ms % PULSE_MS) / PULSE_MS)
  return 1 - (1 - low) * phase
}

var SPARK_RISE_MS = 650
var SPARK_FADE_MS = 1700

// A heatmap spark's opacity `age` ms after it lit: up quickly, out slowly.
function sparkOpacity(age) {
  if (!(age >= 0) || age >= SPARK_RISE_MS + SPARK_FADE_MS) return 0
  if (age < SPARK_RISE_MS) return 0.95 * Math.sin(age / SPARK_RISE_MS * Math.PI / 2)
  return 0.95 * Math.cos((age - SPARK_RISE_MS) / SPARK_FADE_MS * Math.PI / 2)
}

// "owner/repo" from what people paste: a GitHub URL, an SSH remote or the
// name itself. "" when it isn't one.
function normalizeRepo(text) {
  var s = String(text || "").trim()
  s = s.replace(/^git@github\.com:/i, "")
  s = s.replace(/^(https?:\/\/)?(www\.)?github\.com\//i, "")
  s = s.replace(/\.git$/i, "").replace(/\/+$/, "")
  var parts = s.split("/")
  if (parts.length < 2) return ""
  var name = parts[0] + "/" + parts[1]
  return /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(name) ? name : ""
}

function normalizeBranch(text) {
  return String(text || "").trim().replace(/^refs\/heads\//, "")
}

// The six slots as saved: { kind: "github", repo, branch }, { kind: "herdr" },
// { kind: "music" }, { kind: "tasks", tools }, { kind: "plugin", plugin },
// { kind: "workspace", workspace }, { kind: "upkeep" }, { kind: "projects",
// folder }, { kind: "devices" }, { kind: "board", path } or { kind: "empty" };
// any filled one can carry hideOnLock: true, to stay off the lock screen,
// and one of QUIET_KINDS quiet: true, to stay off the desk while it has
// nothing to show. A repo
// slot keeps what was typed even before it's a repo, so the slot stays one.
// A bare repo string or an entry without a kind is a repo; a shorter list
// fills the first slots. Any kind can fill any number of slots.
function slotList(value) {
  // Settings can reach the widget as a Qt list, which isn't a JS Array.
  var list = value && typeof value.length === "number" ? Array.prototype.slice.call(value) : []
  var out = []
  for (var i = 0; i < list.length && out.length < MAX_TILES; i++) {
    var entry = list[i]
    if (typeof entry === "string") entry = { repo: entry }
    var kind = entry && typeof entry === "object" ? entry.kind || "github" : "empty"
    if (KINDS.indexOf(kind) === -1) kind = "empty"
    var slot = kind === "github" ? { kind: kind, repo: normalizeRepo(entry.repo) || String(entry.repo || "").trim(), branch: normalizeBranch(entry.branch) }
      : kind === "tasks" ? { kind: kind, tools: toolList(entry.tools) }
      : kind === "plugin" ? { kind: kind, plugin: String(entry.plugin || "").trim() }
      : kind === "workspace" ? { kind: kind, workspace: String(entry.workspace || "").trim() }
      : kind === "projects" ? { kind: kind, folder: String(entry.folder || "").trim() }
      : kind === "board" ? { kind: kind, path: String(entry.path || "").trim() }
      : { kind: kind }
    if (kind !== "empty" && entry.hideOnLock === true) slot.hideOnLock = true
    if (QUIET_KINDS.indexOf(kind) !== -1 && entry.quiet === true) slot.quiet = true
    out.push(slot)
  }
  while (out.length < MAX_TILES) out.push({ kind: "empty" })
  return out
}

// The tiles on the desk: the filled slots in order, repos and plugins only
// once one is set.
function tileList(value) {
  return slotList(value).filter(function(t) {
    return t.kind !== "empty" && (t.kind !== "github" || normalizeRepo(t.repo) !== "") && (t.kind !== "plugin" || t.plugin !== "")
      && (t.kind !== "workspace" || t.workspace !== "") && (t.kind !== "board" || t.path !== "")
  })
}

// The tiles on the lock screen: those not kept off it.
function lockTileList(value) {
  return tileList(value).filter(function(t) { return t.hideOnLock !== true })
}

// What each slot's dropdown offers.
var KIND_OPTIONS = [
  { value: "empty", label: "Empty" },
  { value: "github", label: "GitHub repository" },
  { value: "herdr", label: "herdr agents" },
  { value: "tasks", label: "Tasks" },
  { value: "music", label: "Now playing" },
  { value: "plugin", label: "Installed plugin" },
  { value: "workspace", label: "Workspace (live)" },
  { value: "upkeep", label: "Omarchy" },
  { value: "projects", label: "Local repos" },
  { value: "devices", label: "USB devices" },
  { value: "board", label: "KiCad board" }
]

// Extra programs for the tasks tile to watch, from a list or what's typed:
// names only, split on commas and spaces.
function toolList(value) {
  var list = typeof value === "string" ? value.split(/[\s,]+/)
    : value && typeof value.length === "number" ? Array.prototype.slice.call(value) : []
  var out = []
  for (var i = 0; i < list.length; i++) {
    var name = String(list[i] || "").trim()
    if (/^[A-Za-z0-9_.+-]+$/.test(name) && out.indexOf(name) === -1) out.push(name)
  }
  return out
}

// What the tasks tiles watch besides the known tools: all their lists
// together, since they share one watcher.
function taskTools(tiles) {
  var out = []
  for (var i = 0; i < tiles.length; i++) {
    if (tiles[i].kind !== "tasks") continue
    var tools = tiles[i].tools || []
    for (var j = 0; j < tools.length; j++) if (out.indexOf(tools[j]) === -1) out.push(tools[j])
  }
  return out
}

// What one watcher for several slots of a kind is given: each slot's folder
// (projects) or path (board) as typed, once.
function slotArgs(tiles, kind, key) {
  var out = []
  for (var i = 0; i < tiles.length; i++) {
    if (tiles[i].kind !== kind) continue
    var value = String(tiles[i][key] || "")
    if (out.indexOf(value) === -1) out.push(value)
  }
  return out
}

// Whether a tile has something to show, for slots set to stay off the desk
// otherwise. `feeds` has what the tiles read: results and liveRuns (repos),
// herdrCounts, tasks, upkeep, projects, devices, boards, clients.
var QUIET_TASK_HOLD_S = 300
var BOARD_FRESH_S = 1800

function tileHasNews(entry, feeds) {
  if (QUIET_KINDS.indexOf(entry.kind) === -1 || entry.quiet !== true) return true
  if (entry.kind === "github") {
    var result = resultFor(feeds.results || [], entry)
    return !!result && (feeds.liveRuns(result).length > 0 || overallState([result]) === "failure")
  }
  if (entry.kind === "herdr") {
    var c = feeds.herdrCounts || {}
    return (c.working || 0) + (c.blocked || 0) > 0
  }
  if (entry.kind === "tasks") {
    return (feeds.tasks || []).some(function(t) { return t.state === "running" || t.ago < QUIET_TASK_HOLD_S })
  }
  if (entry.kind === "workspace") {
    return (feeds.clients || []).some(function(c) { return String(c.ws) === entry.workspace || c.wsName === entry.workspace })
  }
  if (entry.kind === "upkeep") return !!feeds.upkeep && feeds.upkeep.attention === true
  if (entry.kind === "devices") return !!feeds.devices && feeds.devices.attention === true
  if (entry.kind === "projects") {
    var folders = feeds.projects && feeds.projects.folders || {}
    return !!folders[entry.folder || ""] && folders[entry.folder || ""].attention === true
  }
  if (entry.kind === "board") {
    // The watcher only speaks when something changes, so "saved lately"
    // is worked out here, where time passes.
    var b = (feeds.boards && feeds.boards.boards || {})[entry.path]
    if (!b) return false
    var drc = b.drc || {}, erc = b.erc || {}
    return !!b.error || drc.errors > 0 || drc.unconnected > 0 || erc.errors > 0
      || (b.saved > 0 && Date.now() / 1000 - b.saved < BOARD_FRESH_S)
  }
  return true
}

// A quiet slot that had news stays a minute more, so the desk doesn't
// rearrange between two builds. `held` maps a slot's key to when it last had
// news; returns the tiles to show and the map to keep.
var QUIET_HOLD_MS = 60000

function tileKey(entry) {
  return JSON.stringify(entry)
}

function shownTiles(tiles, feeds, held, nowMs) {
  var shown = [], next = {}
  for (var i = 0; i < tiles.length; i++) {
    var key = tileKey(tiles[i])
    if (tileHasNews(tiles[i], feeds)) next[key] = nowMs
    else if (held[key] !== undefined && nowMs - held[key] < QUIET_HOLD_MS) next[key] = held[key]
    if (next[key] !== undefined || tiles[i].quiet !== true) shown.push(tiles[i])
  }
  return { tiles: shown, held: next }
}

// The GitHub tiles among them, which the fetch covers.
function reposOf(tiles) {
  return tiles.filter(function(t) { return t.kind === "github" })
}

function hasKind(tiles, kind) {
  return tiles.some(function(t) { return t.kind === kind })
}

// The argument the fetch script takes for a repo.
function specOf(entry) {
  return entry.branch ? entry.repo + ":" + entry.branch : entry.repo
}

function resultFor(results, entry) {
  var spec = specOf(entry)
  for (var i = 0; i < results.length; i++) {
    if (results[i] && results[i].query === spec) return results[i]
  }
  return null
}

// Tile rectangles for n tiles in a w x h area, `gap` apart: one fills it,
// two split it along its long side, three put one large tile beside two
// stacked ones, four make a 2x2 grid, five put one tall tile beside a 2x2
// grid, six make a 3x2 grid. On a portrait screen the splits turn.
function tileRects(n, w, h, gap) {
  var portrait = h > w
  var W = portrait ? h : w
  var H = portrait ? w : h
  var half = (W - gap) / 2
  var halfH = (H - gap) / 2
  var rects = []
  if (n <= 0) return rects
  if (n === 1) rects = [{ x: 0, y: 0, w: W, h: H }]
  else if (n === 2) rects = [{ x: 0, y: 0, w: half, h: H }, { x: half + gap, y: 0, w: half, h: H }]
  else if (n === 3) rects = [
    { x: 0, y: 0, w: half, h: H },
    { x: half + gap, y: 0, w: half, h: halfH },
    { x: half + gap, y: halfH + gap, w: half, h: halfH }
  ]
  else if (n === 4) rects = [
    { x: 0, y: 0, w: half, h: halfH },
    { x: half + gap, y: 0, w: half, h: halfH },
    { x: 0, y: halfH + gap, w: half, h: halfH },
    { x: half + gap, y: halfH + gap, w: half, h: halfH }
  ]
  else {
    var third = (W - 2 * gap) / 3
    var col = function(i) { return i * (third + gap) }
    rects = n === 5 ? [{ x: 0, y: 0, w: third, h: H }] : [{ x: 0, y: 0, w: third, h: halfH }, { x: 0, y: halfH + gap, w: third, h: halfH }]
    for (var c = 1; c <= 2; c++) {
      rects.push({ x: col(c), y: 0, w: third, h: halfH })
      rects.push({ x: col(c), y: halfH + gap, w: third, h: halfH })
    }
  }
  if (!portrait) return rects
  return rects.map(function(r) { return { x: r.y, y: r.x, w: r.h, h: r.w } })
}

function startOfDay(ms) {
  var d = new Date(ms)
  d.setHours(0, 0, 0, 0)
  return d.getTime()
}

// Commits per local day, oldest first, ending today.
function activityBuckets(dates, nowMs) {
  var buckets = []
  for (var i = 0; i < ACTIVITY_DAYS; i++) buckets.push(0)
  var today = startOfDay(nowMs)
  var list = Array.isArray(dates) ? dates : []
  for (var j = 0; j < list.length; j++) {
    var t = Date.parse(list[j])
    if (!isFinite(t)) continue
    var days = Math.round((today - startOfDay(t)) / 86400000)
    if (days >= 0 && days < ACTIVITY_DAYS) buckets[ACTIVITY_DAYS - 1 - days] += 1
  }
  return buckets
}

function relativeTime(iso, nowMs) {
  var t = Date.parse(iso)
  if (!isFinite(t)) return ""
  var s = Math.max(0, Math.round((nowMs - t) / 1000))
  if (s < 60) return "now"
  var m = Math.round(s / 60)
  if (m < 60) return m + "m"
  var h = Math.round(m / 60)
  if (h < 24) return h + "h"
  var d = Math.round(h / 24)
  if (d < 30) return d + "d"
  var mo = Math.round(d / 30)
  if (mo < 12) return mo + "mo"
  return Math.round(d / 365) + "y"
}

function duration(run, nowMs) {
  var start = Date.parse(run.started)
  var end = run.status === "completed" ? Date.parse(run.updated) : nowMs
  if (!isFinite(start) || !isFinite(end)) return ""
  var s = Math.max(0, Math.round((end - start) / 1000))
  if (s < 60) return s + "s"
  var m = Math.floor(s / 60)
  if (m < 60) return m + "m " + (s % 60) + "s"
  return Math.floor(m / 60) + "h " + (m % 60) + "m"
}

// success | failure | running | cancelled | neutral
function runState(run) {
  if (!run) return "neutral"
  if (run.status !== "completed") return "running"
  var c = run.conclusion
  if (c === "success") return "success"
  if (c === "failure" || c === "timed_out" || c === "startup_failure") return "failure"
  if (c === "cancelled") return "cancelled"
  return "neutral"
}

function isRunning(result) {
  var runs = result && result.runs ? result.runs : []
  for (var i = 0; i < runs.length; i++) if (runState(runs[i]) === "running") return true
  return false
}

// The newest run of each workflow; an older failure stays visible until that
// workflow passes again, whatever other workflows ran since.
function latestPerWorkflow(runs) {
  var seen = {}
  var out = []
  for (var i = 0; i < runs.length; i++) {
    var name = runs[i].name
    if (seen[name]) continue
    seen[name] = true
    out.push(runs[i])
  }
  return out
}

// State of all repos together for the bar dot: running wins, then failure,
// then success; "" without runs.
function overallState(results) {
  var running = false, failure = false, success = false
  for (var i = 0; i < results.length; i++) {
    var r = results[i]
    if (!r || !r.ok) continue
    var latest = latestPerWorkflow(r.runs || [])
    for (var j = 0; j < latest.length; j++) {
      var state = runState(latest[j])
      if (state === "running") running = true
      else if (state === "failure") failure = true
      else if (state === "success") success = true
    }
  }
  if (running) return "running"
  if (failure) return "failure"
  if (success) return "success"
  return ""
}

function compactNumber(n) {
  n = Number(n) || 0
  if (n >= 1000000) return (n / 1000000).toFixed(n >= 10000000 ? 0 : 1) + "M"
  if (n >= 1000) return (n / 1000).toFixed(n >= 10000 ? 0 : 1) + "k"
  return String(n)
}

// "#AARRGGBB"-style Hyprland colors ("ff7aa2f7 0deg", "rgba(...)") to a
// "#RRGGBB" string plus alpha; null when unreadable.
function hyprColor(value) {
  var s = String(value || "").trim().split(/\s+/)[0]
  var hex = s.match(/^(?:0x)?([0-9a-fA-F]{8})$/)
  if (hex) return { color: "#" + hex[1].substr(2), alpha: parseInt(hex[1].substr(0, 2), 16) / 255 }
  var rgba = s.match(/^rgba\(([0-9a-fA-F]{8})\)$/)
  if (rgba) return { color: "#" + rgba[1].substr(0, 6), alpha: parseInt(rgba[1].substr(6, 2), 16) / 255 }
  var rgb = s.match(/^rgb\(([0-9a-fA-F]{6})\)$/)
  if (rgb) return { color: "#" + rgb[1], alpha: 1 }
  return null
}

// green / yellow / red of the theme's colors.toml, with the ANSI slots as
// fallback.
function statusColors(raw) {
  var found = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
    if (m) found[m[1]] = m[2]
  }
  return {
    success: found.green || found.color2 || "",
    running: found.yellow || found.color3 || "",
    failure: found.red || found.color1 || ""
  }
}

// The widget's entry on the bar in shell.json, without its id; null when the
// text isn't JSON or the widget isn't on the bar.
function barEntry(configText, id) {
  var config
  try { config = JSON.parse(configText) } catch (e) { return null }
  var layout = config && config.bar && config.bar.layout ? config.bar.layout : {}
  for (var section in layout) {
    var entries = Array.isArray(layout[section]) ? layout[section] : []
    for (var i = 0; i < entries.length; i++) {
      var entry = entries[i]
      if (!entry || entry.id !== id) continue
      var out = {}
      for (var k in entry) if (k !== "id") out[k] = entry[k]
      return out
    }
  }
  return null
}

// gaps_in and rounding from `hyprctl -j getoption` for each, as one JSON array.
function hyprLook(raw) {
  var list
  try { list = JSON.parse(raw) } catch (e) { return null }
  var byName = {}
  for (var i = 0; i < list.length; i++) if (list[i] && list[i].option) byName[list[i].option] = list[i]
  function firstNumber(option, fallback) {
    if (!option) return fallback
    if (option.int !== undefined) return Number(option.int)
    var n = parseInt(String(option.css || option.custom || "").trim().split(/\s+/)[0], 10)
    return isFinite(n) ? n : fallback
  }
  return { gapsIn: firstNumber(byName["general:gaps_in"], 5), rounding: firstNumber(byName["decoration:rounding"], 0) }
}

// How long a run that ended stays in the live view.
var LIVE_HOLD_MS = 60000

// The runs seen running, from the last `seen` and new results: run id ->
// { running: true } while running, { endedMs } once seen ending. Only runs
// seen running count, so a restart doesn't bring back ones long over.
function trackRuns(results, seen, nowMs) {
  var next = {}
  for (var i = 0; i < results.length; i++) {
    var runs = results[i] && results[i].runs ? results[i].runs : []
    for (var j = 0; j < runs.length; j++) {
      var run = runs[j]
      var before = seen[run.id]
      if (run.status !== "completed") next[run.id] = { running: true }
      else if (before && before.running) next[run.id] = { endedMs: nowMs }
      else if (before && before.endedMs) next[run.id] = before
    }
  }
  return next
}

// A repo's runs for the live view: the running ones, and those that ended
// less than LIVE_HOLD_MS ago. A stale result's runs aren't live: what they
// did since, GitHub couldn't say.
function liveRuns(result, seen, nowMs) {
  var runs = result && result.ok && !result.stale && result.runs ? result.runs : []
  var out = []
  for (var i = 0; i < runs.length; i++) {
    var s = seen[runs[i].id]
    if (runs[i].status !== "completed" || (s && s.endedMs && nowMs - s.endedMs < LIVE_HOLD_MS)) out.push(runs[i])
  }
  return out
}

// Repos to suggest for what's typed: matches on owner/name, names starting
// with the text first, leaving out repos already on the desk. With nothing
// typed, the most recently pushed ones.
function filterChoices(choices, text, taken, limit) {
  var q = String(text || "").trim().toLowerCase()
    .replace(/^(https?:\/\/)?(www\.)?github\.com\//, "")
  var skip = {}
  for (var t = 0; t < taken.length; t++) skip[String(taken[t]).toLowerCase()] = true
  var starts = [], contains = []
  for (var i = 0; i < choices.length; i++) {
    var c = choices[i]
    var full = String(c.repo || "").toLowerCase()
    if (!full || skip[full]) continue
    if (!q) { starts.push(c); continue }
    if (full === q) continue
    var name = full.substring(full.indexOf("/") + 1)
    if (name.indexOf(q) === 0 || full.indexOf(q) === 0) starts.push(c)
    else if (full.indexOf(q) !== -1) contains.push(c)
  }
  return starts.concat(contains).slice(0, limit)
}

// ---- Year heatmap.

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

function dayKey(d) {
  var m = d.getMonth() + 1, day = d.getDate()
  return d.getFullYear() + "-" + (m < 10 ? "0" : "") + m + "-" + (day < 10 ? "0" : "") + day
}

// Levels 1-4 by quartile of the days with commits, like GitHub's graph.
function levelThresholds(counts) {
  var nonzero = counts.filter(function(c) { return c > 0 }).sort(function(a, b) { return a - b })
  if (nonzero.length === 0) return [1, 1, 1]
  function q(p) { return nonzero[Math.min(nonzero.length - 1, Math.floor(p * nonzero.length))] }
  return [q(0.25), q(0.5), q(0.75)]
}

function levelOf(count, thresholds) {
  if (count <= 0) return 0
  if (count <= thresholds[0]) return 1
  if (count <= thresholds[1]) return 2
  if (count <= thresholds[2]) return 3
  return 4
}

// `weeks` columns of Sunday-to-Saturday days, the last one holding today:
// { cells: [{ key, count, level, col, row, today, future }], months: [{ col, name }] }.
function heatmap(days, nowMs, weeks) {
  var map = days || {}
  var today = new Date(nowMs)
  today.setHours(12, 0, 0, 0)
  var start = new Date(today.getTime())
  start.setDate(start.getDate() - today.getDay() - (weeks - 1) * 7)
  var todayKey = dayKey(today)

  var cells = []
  var counts = []
  var months = []
  var lastMonth = -1
  for (var col = 0; col < weeks; col++) {
    for (var row = 0; row < 7; row++) {
      var d = new Date(start.getTime())
      d.setDate(start.getDate() + col * 7 + row)
      var key = dayKey(d)
      var future = key > todayKey
      var count = future ? 0 : (Number(map[key]) || 0)
      if (row === 0 && d.getMonth() !== lastMonth) {
        // A month label needs room: a sliver of a month at the left edge
        // gives way to the next one, and labels keep three weeks apart.
        var label = { col: col, name: MONTHS[d.getMonth()] }
        if (months.length === 1 && months[0].col === 0 && col < 3) months[0] = label
        else if (months.length === 0 || col - months[months.length - 1].col >= 3) months.push(label)
        lastMonth = d.getMonth()
      }
      cells.push({ key: key, count: count, col: col, row: row, today: key === todayKey, future: future })
      counts.push(count)
    }
  }
  var thresholds = levelThresholds(counts)
  for (var i = 0; i < cells.length; i++) cells[i].level = levelOf(cells[i].count, thresholds)
  return { cells: cells, months: months }
}

// Last year's total, the current streak (today may still be empty) and the
// busiest day.
function yearStats(days, nowMs) {
  var map = days || {}
  var total = 0, peak = 0, peakKey = ""
  for (var k in map) {
    var n = Number(map[k]) || 0
    total += n
    if (n > peak) { peak = n; peakKey = k }
  }
  var d = new Date(nowMs)
  d.setHours(12, 0, 0, 0)
  if (!(Number(map[dayKey(d)]) > 0)) d.setDate(d.getDate() - 1)
  var streak = 0
  while (Number(map[dayKey(d)]) > 0 && streak < 400) {
    streak++
    d.setDate(d.getDate() - 1)
  }
  return { total: total, streak: streak, peak: peak, peakLabel: peakKey ? shortDate(peakKey) : "" }
}

// "May 20" from "2026-05-20".
function shortDate(key) {
  var parts = String(key).split("-")
  return MONTHS[Number(parts[1]) - 1] + " " + Number(parts[2])
}

function withCommas(n) {
  return String(Math.round(Number(n) || 0)).replace(/\B(?=(\d{3})+(?!\d))/g, ",")
}

function pad2(n) { return (n < 10 ? "0" : "") + n }

// "today 15:39", "yesterday 09:12", "Sep 20", "Sep 20 2025".
function commitTime(iso, nowMs) {
  var t = Date.parse(iso)
  if (!isFinite(t)) return ""
  var d = new Date(t)
  var now = new Date(nowMs)
  var time = pad2(d.getHours()) + ":" + pad2(d.getMinutes())
  var dayMs = 86400000
  var startToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
  if (t >= startToday) return "today " + time
  if (t >= startToday - dayMs) return "yesterday " + time
  var label = MONTHS[d.getMonth()] + " " + d.getDate()
  return d.getFullYear() === now.getFullYear() ? label : label + " " + d.getFullYear()
}

// ---- Live workflow view.

// A job's or step's state: running | waiting | success | failure |
// cancelled | skipped | neutral.
function stepState(item) {
  if (!item) return "neutral"
  if (item.status === "in_progress") return "running"
  if (item.status !== "completed") return "waiting"
  var c = item.conclusion
  if (c === "success") return "success"
  if (c === "failure" || c === "timed_out" || c === "startup_failure") return "failure"
  if (c === "cancelled") return "cancelled"
  if (c === "skipped") return "skipped"
  return "neutral"
}

function elapsed(started, completed, nowMs) {
  var start = Date.parse(started)
  if (!isFinite(start)) return ""
  var end = completed ? Date.parse(completed) : nowMs
  if (!isFinite(end)) end = nowMs
  var s = Math.max(0, Math.round((end - start) / 1000))
  if (s < 60) return s + "s"
  var m = Math.floor(s / 60)
  if (m < 60) return m + "m " + (s % 60) + "s"
  return Math.floor(m / 60) + "h " + (m % 60) + "m"
}

// The rows of one run's live view, fitted to `maxRows`: the run, each job,
// and the steps of the jobs running (or failed, once the run is over).
// Finished steps fold into one row and the waiting ones into another when
// there isn't room for all of them.
function workflowRows(run, nowMs, maxRows) {
  var rows = []
  var jobs = run && run.jobs ? run.jobs : []
  var runOver = run && run.status === "completed"
  for (var i = 0; i < jobs.length; i++) {
    var job = jobs[i]
    var state = stepState(job)
    rows.push({ kind: "job", name: job.name, state: state,
                time: state === "waiting" ? "" : elapsed(job.started, job.completed, nowMs) })
    if (state === "running" || (runOver && state === "failure")) {
      var steps = job.steps || []
      for (var j = 0; j < steps.length; j++) {
        var st = stepState(steps[j])
        rows.push({ kind: "step", name: steps[j].name, state: st, job: i,
                    time: st === "waiting" || st === "skipped" ? "" : elapsed(steps[j].started, steps[j].completed, nowMs) })
      }
    }
  }
  if (rows.length <= maxRows) return rows

  // Runs of steps in one state fold into a single row: done ones (keeping
  // the last, next to the current step), skipped ones, then waiting ones.
  function fold(list, state, label, keepLast) {
    var out = []
    var k = 0
    while (k < list.length) {
      var r = list[k]
      if (r.kind !== "step" || r.folded || r.state !== state) { out.push(r); k++; continue }
      var group = []
      while (k < list.length && list[k].kind === "step" && !list[k].folded && list[k].job === r.job && list[k].state === state) group.push(list[k++])
      var folded = keepLast ? group.length - 1 : group.length
      if (folded >= 2) {
        out.push({ kind: "step", name: folded + " " + label, state: state, time: "", folded: true, job: r.job })
        if (keepLast) out.push(group[group.length - 1])
      } else out = out.concat(group)
    }
    return out
  }
  rows = fold(rows, "success", "steps done", true)
  if (rows.length > maxRows) rows = fold(rows, "skipped", "steps skipped", false)
  if (rows.length > maxRows) rows = fold(rows, "waiting", "more steps", false)

  // Still too long: steps give way from the end, the running and failed
  // ones last, so every job keeps its row.
  var keep = ["running", "failure"]
  for (var pass = 0; pass < 2 && rows.length > maxRows; pass++) {
    for (var x = rows.length - 1; x >= 0 && rows.length > maxRows; x--) {
      if (rows[x].kind === "step" && (pass === 1 || keep.indexOf(rows[x].state) === -1)) rows.splice(x, 1)
    }
  }
  return rows.slice(0, maxRows)
}

// ---- herdr

// Agents grouped by workspace, in herdr's workspace order:
// [{ id, label, number, focused, agents }]. Agents of a workspace herdr
// didn't list come last, under their workspace id.
function herdrGroups(agents, workspaces) {
  var byWorkspace = {}
  var order = []
  for (var i = 0; i < agents.length; i++) {
    var id = agents[i].workspace_id
    if (!byWorkspace[id]) {
      byWorkspace[id] = []
      order.push(id)
    }
    byWorkspace[id].push(agents[i])
  }
  var sorted = workspaces.slice().sort(function(a, b) { return (a.number || 0) - (b.number || 0) })
  var out = []
  for (var j = 0; j < sorted.length; j++) {
    var ws = sorted[j]
    if (!byWorkspace[ws.workspace_id]) continue
    out.push({ id: ws.workspace_id, label: ws.label || ws.workspace_id, number: ws.number || 0, focused: ws.focused === true, agents: byWorkspace[ws.workspace_id] })
    delete byWorkspace[ws.workspace_id]
  }
  for (var k = 0; k < order.length; k++) {
    if (byWorkspace[order[k]]) out.push({ id: order[k], label: order[k], number: 0, focused: false, agents: byWorkspace[order[k]] })
  }
  return out
}

// working | blocked | done | idle, for a status herdr reports.
function agentState(status) {
  return status === "working" || status === "blocked" || status === "done" ? status : "idle"
}

function herdrCounts(agents) {
  var counts = { working: 0, blocked: 0, done: 0, idle: 0 }
  for (var i = 0; i < agents.length; i++) counts[agentState(agents[i].agent_status)] += 1
  return counts
}

// Rows for the agents tile, at most maxRows: a header for each workspace,
// then its agents. When they don't all fit, the idle agents go first, then
// the rest is cut. `hidden` counts the agents left out.
function herdrRows(groups, maxRows) {
  function build(keep) {
    var rows = []
    for (var i = 0; i < groups.length; i++) {
      var list = groups[i].agents.filter(keep)
      if (list.length === 0) continue
      rows.push({ group: groups[i], agent: null })
      for (var j = 0; j < list.length; j++) rows.push({ group: groups[i], agent: list[j] })
    }
    return rows
  }
  function agentsIn(rows) { return rows.filter(function(r) { return r.agent }).length }
  var rows = build(function() { return true })
  var total = agentsIn(rows)
  if (rows.length > maxRows) {
    // One row stays free for the count of what's left out.
    var room = Math.max(0, maxRows - 1)
    rows = build(function(a) { return agentState(a.agent_status) !== "idle" })
    if (rows.length > room) rows = rows.slice(0, room)
    while (rows.length > 0 && !rows[rows.length - 1].agent) rows.pop()
  }
  return { rows: rows, hidden: total - agentsIn(rows) }
}

// Since when each agent is in its state, from the last `seen`: pane id ->
// { state, sinceMs }. On the first read the start isn't known, so sinceMs
// is 0 and no time shows until the state changes.
function trackAgents(agents, seen, nowMs, first) {
  var next = {}
  for (var i = 0; i < agents.length; i++) {
    var id = agents[i].pane_id
    var state = agentState(agents[i].agent_status)
    var before = seen[id]
    if (before && before.state === state) next[id] = before
    else next[id] = { state: state, sinceMs: first ? 0 : nowMs }
  }
  return next
}

// "5s", "12m", "1h 5m" since a time; "" without one.
function since(ms, nowMs) {
  if (!ms) return ""
  var s = Math.max(0, Math.round((nowMs - ms) / 1000))
  if (s < 60) return s + "s"
  var m = Math.floor(s / 60)
  if (m < 60) return m + "m"
  return Math.floor(m / 60) + "h " + (m % 60) + "m"
}

function baseName(path) {
  var parts = String(path || "").replace(/\/+$/, "").split("/")
  return parts[parts.length - 1] || ""
}

// "3:07" for a number of seconds.
function clockTime(seconds) {
  var s = Math.max(0, Math.floor(Number(seconds) || 0))
  var h = Math.floor(s / 3600)
  var m = Math.floor((s % 3600) / 60)
  return (h > 0 ? h + ":" + pad2(m) : m) + ":" + pad2(s % 60)
}

// ---- Now playing

// Browsers hand the player a small cover (Chrome: 256px), so a sharp one is
// looked up on the iTunes catalogue by artist and title.

// Lowercase words only, for comparing names.
function coverWords(text) {
  return String(text || "").toLowerCase()
    .replace(/[\(\[][^\)\]]*[\)\]]/g, " ")
    .replace(/\b(feat|ft)\.?\s.*$/, " ")
    .replace(/[^a-z0-9\u00c0-\u024f]+/g, " ")
    .trim()
}

// A title and artist as browsers show them: "Artist - Title (Official Video)"
// from a channel called "ArtistVEVO" or "Artist - Topic".
function coverTrack(title, artist) {
  var t = String(title || "").replace(/\s*[\(\[][^\)\]]*(official|video|audio|lyric|visuali[sz]er|hd|4k|remaster|mv)[^\)\]]*[\)\]]/gi, "").trim()
  var a = String(artist || "").replace(/\s*-\s*Topic$/i, "").replace(/VEVO$/i, "").trim()
  var dash = t.indexOf(" - ")
  if (dash > 0 && (!a || coverLike(t.slice(0, dash), a))) {
    a = t.slice(0, dash).trim()
    t = t.slice(dash + 3).trim()
  }
  return { title: t, artist: a }
}

// One name within the other, ignoring case, spaces and punctuation.
function coverLike(a, b) {
  a = coverWords(a).replace(/ /g, "")
  b = coverWords(b).replace(/ /g, "")
  return !!a && !!b && (a.indexOf(b) !== -1 || b.indexOf(a) !== -1)
}

function coverQueryUrl(track) {
  if (!track.title) return ""
  return "https://itunes.apple.com/search?media=music&entity=song&limit=10&term="
    + encodeURIComponent((track.artist + " " + track.title).trim())
}

// The 1000px cover of the result that is this track, or "" when none is.
function pickCover(results, track, size) {
  for (var i = 0; i < (results || []).length; i++) {
    var r = results[i]
    if (!r || !r.artworkUrl100) continue
    if (!coverLike(r.trackName, track.title)) continue
    if (track.artist && !coverLike(r.artistName, track.artist)) continue
    return String(r.artworkUrl100).replace(/\/\d+x\d+bb\./, "/" + size + "x" + size + "bb.")
  }
  return ""
}

// Videos aren't in the catalogue, so they're looked up on YouTube's search
// page instead, for the video with this title.
function youtubeQueryUrl(track) {
  if (!track.title) return ""
  return "https://www.youtube.com/results?search_query="
    + encodeURIComponent((track.artist + " " + track.title).trim())
}

// The id of the first result titled like this track, or "".
function pickYoutubeVideo(html, track) {
  var re = /"videoRenderer":\{"videoId":"([\w-]{11})"[\s\S]{0,2000}?"title":\{"runs":\[\{"text":"((?:[^"\\]|\\.)*)"/g
  var m
  while ((m = re.exec(String(html || "")))) {
    var title = m[2]
    try { title = JSON.parse('"' + title + '"') } catch (e) {}
    if (coverLike(title, track.title)) return m[1]
  }
  return ""
}

// ---- Plugin tiles

// Whether a borrowed menu's item is a control, which a tile that takes no
// clicks leaves out: the shell kit's and Qt's controls by type, and a
// plugin's own by how it's named (…Button, …Pill, …Dropdown).
var CONTROL_TYPES = [
  "Button", "PanelActionButton", "BarIconButton", "WidgetButton", "ButtonGroup",
  "Dropdown", "SearchableDropdown", "MultiSelect", "Toggle", "ToggleSwitch",
  "TextField", "NumberField", "PanelSlider", "TextInput", "TextEdit",
  "QQuickTextInput", "QQuickTextEdit", "QQuickButton", "QQuickRoundButton", "QQuickToolButton",
  "QQuickCheckBox", "QQuickSwitch", "QQuickComboBox", "QQuickSlider", "QQuickSpinBox", "QQuickTextField", "QQuickRadioButton"
]

function typeName(object) {
  return String(object).split("(")[0].replace(/_QML(TYPE)?_\d+$/, "")
}

function isControl(object) {
  var name = typeName(object)
  if (CONTROL_TYPES.indexOf(name) !== -1) return true
  return /(Button|Pill|Chip|Dropdown|Toggle|Switch|Slider|Field|Picker|Selector|Stepper)$/.test(name)
}

// ---- Tasks

// running | success | failure | cancelled | done, as the watcher reports.
function taskCounts(tasks) {
  var counts = { running: 0, success: 0, failure: 0, cancelled: 0, done: 0 }
  for (var i = 0; i < tasks.length; i++) if (counts[tasks[i].state] !== undefined) counts[tasks[i].state] += 1
  return counts
}

// "12s", "4m 12s", "1h 5m" for a number of seconds.
function span(seconds) {
  var s = Math.max(0, Math.round(Number(seconds) || 0))
  if (s < 60) return s + "s"
  var m = Math.floor(s / 60)
  if (m < 60) return m + "m " + (s % 60) + "s"
  return Math.floor(m / 60) + "h " + (m % 60) + "m"
}
