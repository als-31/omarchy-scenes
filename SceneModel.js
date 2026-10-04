.pragma library

// Pure helpers for the Scenes UI. Everything here works on the JSON the
// `scenes` CLI prints, so it stays testable outside the shell.

function plural(n, word) {
  return n + " " + word + (n === 1 ? "" : "s")
}

// Arrays that cross a QML property boundary can arrive as Qt sequence types
// that are not real JS arrays. Anything with a numeric length is a list here.
function isList(value) {
  return value !== null && value !== undefined && typeof value === "object" && typeof value.length === "number"
}

function monitorCount(scene) {
  return scene && isList(scene.monitors) ? scene.monitors.length : 0
}

function windowsOf(scene) {
  return scene && isList(scene.windows) ? scene.windows : []
}

function isSpecial(name) {
  return String(name || "").indexOf("special:") === 0
}

function workspaceLabel(name) {
  var value = String(name || "")
  if (isSpecial(value)) return value.slice("special:".length) || "special"
  return value
}

function workspaceCount(scene) {
  var seen = ({})
  var count = 0
  var windows = windowsOf(scene)
  for (var i = 0; i < windows.length; i++) {
    var key = windows[i].workspace ? String(windows[i].workspace.name) : ""
    if (!seen[key]) { seen[key] = true; count++ }
  }
  return count
}

function summary(scene) {
  var windows = windowsOf(scene).length
  var workspaces = workspaceCount(scene)
  return plural(windows, "window") + " · " + plural(workspaces, "workspace")
}

function parseTime(iso) {
  var t = Date.parse(String(iso || ""))
  return isFinite(t) ? t : 0
}

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

function relativeTime(iso, nowMs) {
  var t = parseTime(iso)
  if (!t) return ""
  var diff = Math.max(0, (nowMs || Date.now()) - t) / 1000
  if (diff < 45) return "just now"
  if (diff < 90) return "a minute ago"
  if (diff < 3600) return Math.round(diff / 60) + " min ago"
  if (diff < 5400) return "an hour ago"
  if (diff < 86400) return Math.round(diff / 3600) + " hours ago"
  if (diff < 172800) return "yesterday"
  if (diff < 604800) return Math.round(diff / 86400) + " days ago"
  var d = new Date(t)
  var now = new Date(nowMs || Date.now())
  var label = d.getDate() + " " + MONTHS[d.getMonth()]
  return d.getFullYear() === now.getFullYear() ? label : label + " " + d.getFullYear()
}

function homeRelative(path, home) {
  var value = String(path || "")
  if (home && value === home) return "~"
  if (home && value.indexOf(home + "/") === 0) return "~" + value.slice(home.length)
  return value
}

function basename(path) {
  var parts = String(path || "").split("/")
  for (var i = parts.length - 1; i >= 0; i--) if (parts[i]) return parts[i]
  return ""
}

// Short "what is this window" text: the directory and program for a
// terminal, the site for a web app, nothing for an ordinary app.
function windowDetail(win, home) {
  if (!win) return ""
  if (win.kind === "terminal") {
    var dir = homeRelative(win.cwd, home)
    var cmd = isList(win.command) && win.command.length > 0 ? basename(win.command[0]) : ""
    return cmd ? dir + " · " + cmd : dir
  }
  if (win.kind === "webapp" && win.url) return String(win.url).replace(/^https?:\/\//, "").replace(/\/$/, "")
  if (win.kind === "unknown") return "can't be relaunched"
  return ""
}

// One entry per workspace, numbered workspaces first, then named, then
// special ones. Each carries its windows and the logical size of the monitor
// it was on, so previews keep the screen's shape.
function workspaces(scene) {
  var monitors = scene && isList(scene.monitors) ? scene.monitors : []
  var monitorByName = ({})
  for (var m = 0; m < monitors.length; m++) monitorByName[monitors[m].name] = monitors[m]
  var fallback = monitors.length > 0 ? monitors[0] : { width: 1920, height: 1080 }

  var groups = ({})
  var order = []
  var windows = windowsOf(scene)
  for (var i = 0; i < windows.length; i++) {
    var win = windows[i]
    var name = win.workspace ? String(win.workspace.name) : "?"
    if (!groups[name]) {
      var monitor = monitorByName[win.monitor] || fallback
      groups[name] = {
        name: name,
        label: workspaceLabel(name),
        id: win.workspace ? Number(win.workspace.id) : 0,
        special: isSpecial(name),
        monitor: win.monitor || "",
        width: Math.max(1, Number(monitor.width) || 1920),
        height: Math.max(1, Number(monitor.height) || 1080),
        focused: !!(scene.focus && scene.focus.workspace === name),
        windows: []
      }
      order.push(name)
    }
    groups[name].windows.push(win)
  }

  var list = order.map(function(key) { return groups[key] })
  list.sort(function(a, b) {
    var rank = function(w) { return w.special ? 2 : (w.id > 0 ? 0 : 1) }
    if (rank(a) !== rank(b)) return rank(a) - rank(b)
    if (a.id !== b.id) return a.id - b.id
    return a.name < b.name ? -1 : 1
  })
  return list
}

// Distinct apps in a scene, most windows first, for compact icon stacks.
function apps(scene, limit) {
  var counts = ({})
  var first = ({})
  var order = []
  var windows = windowsOf(scene)
  for (var i = 0; i < windows.length; i++) {
    var key = windows[i].desktopId || windows[i].class
    if (!counts[key]) { counts[key] = 0; first[key] = windows[i]; order.push(key) }
    counts[key]++
  }
  order.sort(function(a, b) { return counts[b] - counts[a] })
  var out = []
  for (var j = 0; j < order.length && (!limit || j < limit); j++)
    out.push({ app: first[order[j]].app || first[order[j]].class, icon: first[order[j]].icon || "", kind: first[order[j]].kind || "app", count: counts[order[j]] })
  return out
}

function matches(scene, filter) {
  var query = String(filter || "").toLowerCase().trim()
  if (!query) return true
  var haystack = String(scene.name || "").toLowerCase()
  var windows = windowsOf(scene)
  for (var i = 0; i < windows.length; i++) {
    haystack += " " + String(windows[i].app || "").toLowerCase()
    haystack += " " + String(windows[i].class || "").toLowerCase()
    if (windows[i].cwd) haystack += " " + String(windows[i].cwd).toLowerCase()
  }
  var words = query.split(/\s+/)
  for (var w = 0; w < words.length; w++) if (haystack.indexOf(words[w]) === -1) return false
  return true
}

function slugify(name) {
  var slug = String(name || "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "")
  if (!slug) slug = "scene"
  if (slug === "settings" || slug === "previous") slug += "-scene"
  return slug
}

function nameTaken(scenes, name) {
  var slug = slugify(name)
  for (var i = 0; i < scenes.length; i++) if (scenes[i].slug === slug) return scenes[i]
  return null
}

function capitalize(text) {
  var value = String(text || "")
  return value ? value.charAt(0).toUpperCase() + value.slice(1) : value
}

// A sensible default name for the current desktop: the project most of its
// terminals are in, else the app on the focused workspace.
function suggestName(capture, scenes, home) {
  var windows = windowsOf(capture)
  var counts = ({})
  var best = ""
  for (var i = 0; i < windows.length; i++) {
    var win = windows[i]
    if (win.kind !== "terminal" || !win.cwd || win.cwd === home || win.cwd === "/") continue
    var dir = basename(win.cwd)
    if (!dir) continue
    counts[dir] = (counts[dir] || 0) + 1
    if (!best || counts[dir] > counts[best]) best = dir
  }
  if (!best && capture && capture.focus) {
    for (var j = 0; j < windows.length; j++) {
      if (windows[j].workspace && windows[j].workspace.name === capture.focus.workspace) { best = windows[j].app || ""; break }
    }
  }
  var base = best || "Scene"
  var candidate = base
  var n = 2
  while (nameTaken(scenes || [], candidate)) candidate = base + " " + n++
  return candidate
}

function ellipsize(text, max) {
  var value = String(text || "")
  return value.length > max ? value.slice(0, Math.max(1, max - 1)) + "…" : value
}
