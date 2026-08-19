import QtQuick
import qs.Commons
import qs.Ui
import "../components"

// Reports tab: one report per (range, group-by). The helper computes
// rows server-side; QML only renders them, so heavy intervals stay fast.
Item {
  id: root

  property var dashboard: null
  // Bound, not assigned: the panel loader injects the dashboard's service
  // after this view may already be loaded, so a one-shot assignment could
  // stay null forever.
  readonly property var service: root.dashboard ? root.dashboard.service : null

  property string from: ""
  property string to: ""
  property string currentPreset: "all"
  property string groupBy: "day"

  property var rows: []
  property int total: 0
  property int totalSeconds: 0
  property int billableSeconds: 0
  property int entryCount: 0
  property int offset: 0
  readonly property int limit: root.service ? root.service.pageSize : 15

  readonly property bool inputActive: rangeBar.fieldActive

  function load() {
    if (!root.service) return
    root.service.queryReport(
      { from: root.from, to: root.to, clientId: "", projectId: "", billable: null, search: "" },
      root.groupBy,
      root.offset,
      function(resp) {
        if (resp.ok) {
          root.rows = resp.rows
          root.total = resp.total
          root.totalSeconds = resp.totalSeconds
          root.billableSeconds = resp.billableSeconds
          root.entryCount = resp.entryCount
        } else {
          root.service.lastError = resp.error || "Report failed"
        }
      })
  }

  function prevPage() {
    root.offset = Math.max(0, root.offset - root.limit)
    root.load()
  }
  function nextPage() {
    root.offset = Math.min(Math.max(0, root.total - root.limit), root.offset + root.limit)
    root.load()
  }

  property string flash: ""

  Timer {
    id: flashTimer
    interval: 2000
    onTriggered: root.flash = ""
  }

  function doExport(kind) {
    if (!root.service) return
    root.service.exportRange(
      { from: root.from, to: root.to, clientId: "", projectId: "", billable: null, search: "" },
      kind,
      function(resp) {
        if (resp.ok) {
          var p = String(resp.path || "")
          var home = root.service.home
          if (home && p.indexOf(home) === 0) p = "~" + p.slice(home.length)
          root.flash = "Exported " + resp.count + " entries to " + p
          flashTimer.restart()
        } else {
          root.service.lastError = resp.error || "Export failed"
        }
      }
    )
  }

  Column {
    id: head
    anchors {
      top: parent.top
      left: parent.left
      right: parent.right
      topMargin: Style.space(16)
      leftMargin: Style.space(16)
      rightMargin: Style.space(16)
    }
    spacing: Style.space(10)

    Text {
      text: "Reports"
      color: Color.foreground
      font.pixelSize: Style.font.title
      font.bold: true
    }

    Text {
      text: "Time grouped by day, client, or project for the selected range — the hairline shows each group's share of the total; export the rows as CSV or HTML."
      color: Color.muted
      font.pixelSize: Style.font.caption
      width: parent.width
      wrapMode: Text.Wrap
    }

    // Row 1: range presets (left) + group-by (right). Reports is
    // preset-only: manual dates are picked in Entries / invoices, so the
    // picker row is hidden (showPickers: false) and the bar keeps its
    // natural width, leaving the right side free for the group-by.
    Item {
      id: filterRow
      width: parent.width
      height: Math.max(rangeBar.height, groupRow.implicitHeight)

      DateRangeBar {
        id: rangeBar
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        service: root.service
        from: root.from
        to: root.to
        currentPreset: root.currentPreset
        showPickers: false

        onChanged: function(f, t, preset) {
          root.from = f
          root.to = t
          root.currentPreset = preset
          root.offset = 0
          root.load()
        }
      }

      Row {
        id: groupRow
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        spacing: Style.space(8)

        Text {
          text: "Group by"
          color: Color.muted
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
        }

        Button {
          text: "Day"
          leftAlign: true
          focusable: true
          selected: root.groupBy === "day"
          onClicked: {
            root.groupBy = "day"
            root.offset = 0
            root.load()
          }
        }

        Button {
          text: "Client"
          leftAlign: true
          focusable: true
          selected: root.groupBy === "client"
          onClicked: {
            root.groupBy = "client"
            root.offset = 0
            root.load()
          }
        }

        Button {
          text: "Project"
          leftAlign: true
          focusable: true
          selected: root.groupBy === "project"
          onClicked: {
            root.groupBy = "project"
            root.offset = 0
            root.load()
          }
        }
      }
    }

    // Row 2: exports pinned to the far right of their own row.
    Item {
      id: actionBar
      width: parent.width
      height: exportRow.implicitHeight

      Row {
        id: exportRow
        anchors { right: parent.right; bottom: parent.bottom }
        spacing: Style.space(8)

        Button {
          text: "Export CSV"
          leftAlign: true
          focusable: true
          onClicked: root.doExport("csv")
        }

        Button {
          text: "Export HTML"
          leftAlign: true
          focusable: true
          onClicked: root.doExport("html")
        }
      }
    }
  }

  ListView {
    id: listView
    anchors {
      left: parent.left
      right: parent.right
      top: head.bottom
      topMargin: Style.space(10)
      bottom: pagerBar.top
      bottomMargin: Style.space(10)
      leftMargin: Style.space(16)
      rightMargin: Style.space(16)
    }
    model: root.rows
    spacing: 2
    clip: true

    delegate: ReportRow {
      width: listView.width
      service: root.service
      totalSeconds: root.totalSeconds
    }

    EmptyMessage {
      message: "No rows"
      visible: root.total === 0
    }
  }

  // ---- pager + status -----------------------------------------------------------
  // Pinned to the bottom of the table, above the totals bar: the shared
  // PaginationBar plus the flash/error status texts.
  Row {
    id: pagerBar
    anchors {
      left: parent.left
      right: parent.right
      bottom: totalsBar.top
      bottomMargin: Style.space(10)
      leftMargin: Style.space(16)
      rightMargin: Style.space(16)
    }
    spacing: Style.space(8)

    PaginationBar {
      id: pageBar
      total: root.total
      offset: root.offset
      limit: root.limit
      emptyText: "No rows"
      onPrevRequested: root.prevPage()
      onNextRequested: root.nextPage()
    }

    Text {
      text: root.flash
      color: Color.accent
      font.pixelSize: Style.font.caption
      anchors.verticalCenter: parent.verticalCenter
      visible: root.flash !== ""
    }

    Text {
      text: root.service ? root.service.lastError : ""
      color: Color.urgent
      font.pixelSize: Style.font.caption
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideRight
      visible: root.service && root.service.lastError !== ""
    }
  }

  Item {
    id: totalsBar
    anchors {
      left: parent.left
      right: parent.right
      bottom: parent.bottom
      leftMargin: Style.space(16)
      rightMargin: Style.space(16)
      bottomMargin: Style.space(16)
    }
    height: Style.space(20)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "Total " + (root.service ? root.service.fmtDur(root.totalSeconds) : "—")
        + " · billable " + (root.service ? root.service.fmtDur(root.billableSeconds) : "—")
        + " · " + root.entryCount + (root.entryCount === 1 ? " entry" : " entries")
      color: Color.muted
      font.pixelSize: Style.font.caption
    }
  }

  Timer {
    id: initialLoad
    interval: 0
    repeat: false
    running: root.service !== null
    onTriggered: root.load()
  }
}
