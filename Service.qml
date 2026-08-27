import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Headless engine of the OmaTrack plugin.
//
// Owns the single serialized channel to `omatrack.py` (the only writer of
// the state file), the in-memory state view (clients/projects/settings/
// active — never the full entries list), the 1s tick that drives the
// running-timer display, and the `omatrack` IPC target. No UI here.
Item {
  id: root

  // ---- host injections (services get these minus `service`) ----------------
  property var shell: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null

  // ---- paths ----------------------------------------------------------------
  readonly property string home: Quickshell.env("HOME")
  readonly property string helperPath: Qt.resolvedUrl("omatrack.py").toString().replace("file://", "")
  readonly property string stateDir:
    (Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state"))
    + "/omarchy/omatrack"
  readonly property string statePath: stateDir + "/state.json"

  // ---- state view (set by applyView) ----------------------------------------
  property var settings: ({
    currency: "EUR",
    hourlyRate: 0,
    invoice: ({
      companyName: "", companyAddress: "", taxRate: 0,
      numberPrefix: "INV-", nextNumber: 1, footer: ""
    })
  })

  // Page size of every table view (fixed at 15).
  readonly property int pageSize: 15
  property var clients: []
  property var projects: []
  property var invoices: []
  property var active: null
  property var lastUsed: null
  property int daySeconds: 0
  property int dayBillableSeconds: 0
  property var dayByClient: ({})
  property int entryCount: 0
  property string lastError: ""
  readonly property bool running: active !== null
  readonly property bool paused:
    root.active !== null && root.active.paused === true

  // ---- live timer (C++ 1s tick; zero cost while idle) -----------------------
  SystemClock {
    id: clock
    precision: SystemClock.Seconds
    enabled: root.running
  }

  // Elapsed working time: wall clock since start, minus banked paused
  // seconds, minus the in-flight pause segment (algebraically constant
  // while paused, so the frozen display costs only the tick itself).
  readonly property int elapsedSeconds: root.active ? Math.max(0, Math.floor(
      clock.date.getTime() / 1000
      - Date.parse(root.active.start) / 1000
      - (Number(root.active.pausedSeconds) || 0)
      - (root.active.paused && root.active.pauseStart !== null
          ? Math.max(0, clock.date.getTime() / 1000 - Date.parse(root.active.pauseStart) / 1000)
          : 0)
  )) : 0
  readonly property string elapsedLabel: root.fmtHMS(root.elapsedSeconds)

  // ---- formatting --------------------------------------------------------------
  function pad2(n) { return n < 10 ? "0" + n : String(n) }
  function fmtHMS(sec) {
    sec = Math.max(0, Math.floor(Number(sec) || 0))
    return pad2(Math.floor(sec / 3600)) + ":" + pad2(Math.floor((sec % 3600) / 60)) + ":" + pad2(sec % 60)
  }
  function fmtHM(sec) {
    sec = Math.max(0, Math.floor(Number(sec) || 0))
    return Math.floor(sec / 3600) + ":" + pad2(Math.floor((sec % 3600) / 60))
  }
  // "1h 32m" / "45m" / "0m" — the suffixed sibling of fmtHM for places
  // where the H:MM shape reads as minutes:seconds (the reports table).
  function fmtDur(sec) {
    sec = Math.max(0, Math.floor(Number(sec) || 0))
    var h = Math.floor(sec / 3600)
    var m = Math.floor((sec % 3600) / 60)
    if (h > 0) return m > 0 ? h + "h " + m + "m" : h + "h"
    return m + "m"
  }

  // Local-calendar date parts, for manual-entry defaults and range presets.
  function localDateStr(d) {
    return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate())
  }
  function localTimeStr(d) { return pad2(d.getHours()) + ":" + pad2(d.getMinutes()) }


  // ---- name lookups + options ----------------------------------------------------
  function clientName(id) {
    var list = root.clients || []
    for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i].name
    return ""
  }
  function projectName(id) {
    var list = root.projects || []
    for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i].name
    return ""
  }
  function clientOptions() {
    var out = []
    var list = root.clients || []
    for (var i = 0; i < list.length; i++) out.push({ value: list[i].id, label: list[i].name })
    return out
  }
  function projectOptions(clientId) {
    var out = []
    var list = root.projects || []
    for (var i = 0; i < list.length; i++)
      if (list[i].clientId === clientId) out.push({ value: list[i].id, label: list[i].name })
    return out
  }
  function allProjectOptions() {
    var out = []
    var list = root.projects || []
    for (var i = 0; i < list.length; i++)
      out.push({ value: list[i].id, label: root.clientName(list[i].clientId) + " — " + list[i].name })
    return out
  }

  // ---- today by client (live) ----------------------------------------------
  // Today's logged seconds per client (the state view's dayByClient), with
  // the running timer's live elapsed folded into the active client — the
  // list grows with the 1s tick while a task runs, freezes while paused
  // (elapsedSeconds is constant), and shows the active client even before
  // its first stop. Sorted by seconds, descending.
  readonly property var clientDay: {
    var out = []
    var seen = {}
    var db = root.dayByClient || {}
    var keys = Object.keys(db)
    for (var i = 0; i < keys.length; i++) {
      seen[keys[i]] = true
      out.push({ clientId: keys[i], seconds: db[keys[i]] })
    }
    if (root.running && root.active && !seen[root.active.clientId])
      out.push({ clientId: root.active.clientId, seconds: 0 })
    for (var j = 0; j < out.length; j++) {
      var o = out[j]
      o.running = root.running && root.active && o.clientId === root.active.clientId
      if (o.running) o.seconds += root.elapsedSeconds
      o.name = root.clientName(o.clientId)
    }
    out.sort(function(a, b) { return b.seconds - a.seconds })
    return out
  }

  // ---- process channel (single serialized helper) ---------------------------------
  property var _queue: []
  property var _pending: null

  // StdioCollector.text is read-only and accumulates across runs, so each run
  // gets fresh collectors; QML garbage-collects the previous ones on reassign.
  Component { id: stdoutCollector; StdioCollector {} }
  Component { id: stderrCollector; StdioCollector {} }

  Process {
    id: helper
    running: false
    onExited: {
      var raw = helper.stdout ? helper.stdout.text : ""
      var err = helper.stderr ? helper.stderr.text : ""
      var resp = null
      try { resp = JSON.parse(raw) } catch (e) {
        resp = { ok: false, error: "helper: " + (err || raw || "no output") }
      }
      if (resp.ok !== true) root.lastError = String(resp.error || "unknown error")
      var pending = root._pending
      root._pending = null
      if (pending) pending(resp)
      root.runNextQueued()
    }
  }

  function run(args, done) {
    if (helper.running) root._queue.push([args, done])
    else root.startRun(args, done)
  }
  function startRun(args, done) {
    root._pending = done
    helper.stdout = stdoutCollector.createObject(helper)
    helper.stderr = stderrCollector.createObject(helper)
    helper.command = ["python3", root.helperPath].concat(args)
    helper.running = true
  }
  function runNextQueued() {
    if (!helper.running && root._queue.length > 0) {
      var next = root._queue.shift()
      root.startRun(next[0], next[1])
    }
  }

  // ---- state loading ---------------------------------------------------------------
  function applyInit() {
    root.run(["init"], function(resp) { if (resp.ok) root.applyView(resp) })
  }

  function reloadState() {
    root.run(["state"], function(resp) { if (resp.ok) root.applyView(resp) })
  }

  function applyView(resp) {
    var s = resp.state
    if (!s) return
    if (s.settings !== undefined) root.settings = s.settings
    if (s.clients !== undefined) root.clients = s.clients
    if (s.projects !== undefined) root.projects = s.projects
    if (s.invoices !== undefined) root.invoices = s.invoices
    if ("active" in s) root.active = s.active
    if ("lastUsed" in s) root.lastUsed = s.lastUsed
    if (s.daySeconds !== undefined) root.daySeconds = s.daySeconds
    if (s.dayBillableSeconds !== undefined) root.dayBillableSeconds = s.dayBillableSeconds
    if (s.dayByClient !== undefined) root.dayByClient = s.dayByClient
    if (s.entryCount !== undefined) root.entryCount = s.entryCount
    root.lastError = ""
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    printErrors: false
    onFileChanged: {
      if (helper.running) return
      if (stateFile.text() === "") root.applyInit()
      else root.reloadState()
    }
  }

  Component.onCompleted: root.applyInit()

  // ---- public API (argv builders; view applied on success; done always forwarded) --
  function withView(done) {
    return function(resp) { if (resp.ok) root.applyView(resp); if (done) done(resp) }
  }

  function startTask(clientId, projectId, description, billable, done) {
    root.run(
      ["start", "--client-id", String(clientId), "--project-id", String(projectId),
       "--description", String(description || ""), "--billable", billable ? "1" : "0"],
      root.withView(done)
    )
  }

  function stopTask(done) {
    root.run(["stop"], root.withView(done))
  }

  function pauseTask(done) {
    root.run(["pause"], root.withView(done))
  }

  function resumeTask(done) {
    root.run(["resume"], root.withView(done))
  }

  function pushFilterFlags(args, filter) {
    if (!filter) return
    if (filter.from) args.push("--from", String(filter.from))
    if (filter.to) args.push("--to", String(filter.to))
    if (filter.clientId) args.push("--client-id", String(filter.clientId))
    if (filter.projectId) args.push("--project-id", String(filter.projectId))
    if (filter.billable !== undefined && filter.billable !== null && filter.billable !== "")
      args.push("--billable", filter.billable ? "1" : "0")
    if (filter.search) args.push("--search", String(filter.search))
  }

  function queryEntries(filter, offset, done) {
    var args = ["entries", "--offset", String(offset || 0), "--limit", String(root.pageSize)]
    root.pushFilterFlags(args, filter)
    root.run(args, function(resp) { if (done) done(resp) })
  }

  function queryReport(filter, groupBy, offset, done) {
    var args = ["report", "--group-by", groupBy,
      "--offset", String(offset || 0), "--limit", String(root.pageSize)]
    root.pushFilterFlags(args, filter)
    root.run(args, function(resp) { if (done) done(resp) })
  }

  function addClient(name, done) {
    root.run(["client-add", "--name", String(name)], root.withView(done))
  }
  function updateClient(id, name, done) {
    root.run(["client-update", "--id", String(id), "--name", String(name)], root.withView(done))
  }
  function deleteClient(id, done) {
    root.run(["client-delete", "--id", String(id)], root.withView(done))
  }

  function addProject(clientId, name, done) {
    root.run(["project-add", "--client-id", String(clientId), "--name", String(name)], root.withView(done))
  }
  function updateProject(id, name, clientId, done) {
    var args = ["project-update", "--id", String(id)]
    if (name !== undefined && name !== null) args.push("--name", String(name))
    if (clientId !== undefined && clientId !== null) args.push("--client-id", String(clientId))
    root.run(args, root.withView(done))
  }
  function deleteProject(id, done) {
    root.run(["project-delete", "--id", String(id)], root.withView(done))
  }

  function addEntry(f, done) {
    root.run(
      ["entry-add", "--start", String(f.date), "--time", String(f.time),
       "--minutes", String(f.minutes), "--client-id", String(f.clientId),
       "--project-id", String(f.projectId), "--description", String(f.description || ""),
       "--billable", f.billable ? "1" : "0"],
      root.withView(done)
    )
  }

  function updateEntry(id, f, done) {
    var args = ["entry-update", "--id", String(id)]
    if (f.date) args.push("--start", String(f.date))
    if (f.time) args.push("--time", String(f.time))
    if (f.minutes !== undefined && f.minutes !== null) args.push("--minutes", String(f.minutes))
    if (f.clientId) args.push("--client-id", String(f.clientId))
    if (f.projectId) args.push("--project-id", String(f.projectId))
    if (f.description !== undefined && f.description !== null) args.push("--description", String(f.description))
    if (f.billable !== undefined && f.billable !== null) args.push("--billable", f.billable ? "1" : "0")
    root.run(args, root.withView(done))
  }

  function deleteEntry(id, done) {
    root.run(["entry-delete", "--id", String(id)], root.withView(done))
  }

  function saveSettings(patch, done) {
    root.run(["settings-set", "--json", JSON.stringify(patch)], root.withView(done))
  }

  function exportRange(filter, format, done) {
    // Exports go to the user's Downloads folder; the flash in
    // ReportsView reports the full path from the response.
    var out = root.home + "/Downloads/timesheet_"
      + (filter && filter.from ? filter.from : "all") + "_"
      + (filter && filter.to ? filter.to : "all")
      + "." + (format === "csv" ? "csv" : "html")
    var args = ["export", "--format", format, "--out", out]
    root.pushFilterFlags(args, filter)
    root.run(args, function(resp) { if (done) done(resp) })
  }

  function makeInvoice(clientId, from, to, done) {
    root.run(["invoice", "--client-id", String(clientId), "--from", String(from), "--to", String(to)],
      root.withView(done))
  }

  function openPath(path) {
    Quickshell.execDetached(["xdg-open", String(path)])
  }

  // ---- IPC target (the plugin's only IpcHandler) -----------------------------------
  // Synchronous calls: start/stop/pause/resume return optimistically; the
  // helper's actual result lands in `_ipcResult` for the next call and in
  // `status()` state.
  property string _ipcResult: ""

  IpcHandler {
    target: "omatrack"

    function ping(): string { return "ok" }

    function status(): string {
      var a = root.active
      return JSON.stringify({
        running: root.running,
        paused: root.paused,
        client: a ? root.clientName(a.clientId) : "",
        project: a ? root.projectName(a.projectId) : "",
        description: a ? a.description : "",
        billable: a ? a.billable === true : false,
        elapsedSeconds: root.elapsedSeconds,
        daySeconds: root.daySeconds,
        dayBillableSeconds: root.dayBillableSeconds,
        entryCount: root.entryCount,
        lastResult: root._ipcResult
      })
    }

    function start(): string {
      if (root.running) return root.paused ? "paused (resume first)" : "already running"
      var lu = root.lastUsed
      var c = (lu && lu.clientId) || (root.clients.length > 0 ? root.clients[0].id : "")
      var ps = c ? root.projectOptions(c) : []
      var p = (lu && lu.projectId && c === lu.clientId)
        ? lu.projectId
        : (ps.length > 0 ? ps[0].value : "")
      if (!c || !p) return "no client/project"
      var d = (lu && lu.description) || ""
      if (d.trim() === "") return "no description on file (start once from the UI)"
      root._ipcResult = ""
      root.startTask(c, p, d,
        (lu && typeof lu.billable === "boolean" ? lu.billable : true),
        function(resp) { root._ipcResult = resp.ok ? "started" : String(resp.error) })
      return "started"
    }

    function stop(): string {
      if (!root.running) return "not running"
      root._ipcResult = ""
      root.stopTask(function(resp) { root._ipcResult = resp.ok ? "stopped" : String(resp.error) })
      return "stopped"
    }

    function pause(): string {
      if (!root.running) return "not running"
      if (root.paused) return "already paused"
      root._ipcResult = ""
      root.pauseTask(function(resp) { root._ipcResult = resp.ok ? "paused" : String(resp.error) })
      return "paused"
    }

    function resume(): string {
      if (!root.running) return "not running"
      if (!root.paused) return "not paused"
      root._ipcResult = ""
      root.resumeTask(function(resp) { root._ipcResult = resp.ok ? "resumed" : String(resp.error) })
      return "resumed"
    }

    function toggle(): string {
      if (!root.running) return root.start()
      return root.paused ? root.resume() : root.pause()
    }
  }
}
