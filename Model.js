.pragma library

var MAX_REPOS = 4
var ACTIVITY_DAYS = 28

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

// The configured repos as [{ repo, branch }], valid ones only, at most four.
function repoList(value) {
  // Settings can reach the widget as a Qt list, which isn't a JS Array.
  var list = value && typeof value.length === "number" ? Array.prototype.slice.call(value) : []
  var out = []
  for (var i = 0; i < list.length && out.length < MAX_REPOS; i++) {
    var entry = list[i]
    if (typeof entry === "string") entry = { repo: entry }
    if (!entry || typeof entry !== "object") continue
    var repo = normalizeRepo(entry.repo)
    if (!repo) continue
    out.push({ repo: repo, branch: normalizeBranch(entry.branch) })
  }
  return out
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

// Tile rectangles for n repos in a w x h area, `gap` apart: one fills it,
// two split it along its long side, three put one large tile beside two
// stacked ones, four make a 2x2 grid. On a portrait screen the splits turn.
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
  else rects = [
    { x: 0, y: 0, w: half, h: halfH },
    { x: half + gap, y: 0, w: half, h: halfH },
    { x: 0, y: halfH + gap, w: half, h: halfH },
    { x: half + gap, y: halfH + gap, w: half, h: halfH }
  ]
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
