import QtQuick
import qs.Commons
import qs.Ui
import "../components"

// Reports tab: one report per (range, group-by). The helper computes
// rows server-side; QML only renders them, so heavy intervals stay fast.
Item {
  id: root

  property var service: null
  property var dashboard: null

  property string from: ""
  property string to: ""
  property string currentPreset: "all"
  property string groupBy: "day"

  property var rows: []
  property int totalSeconds: 0
  property int billableSeconds: 0

  readonly property bool inputActive: rangeBar.fieldActive

  function load() {
    if (!root.service) return
    root.service.queryReport(
      { from: root.from, to: root.to, clientId: "", projectId: "", billable: null, search: "" },
      root.groupBy,
      function(resp) {
        if (resp.ok) {
          root.rows = resp.rows
          root.totalSeconds = resp.totalSeconds
          root.billableSeconds = resp.billableSeconds
        } else {
          root.service.lastError = resp.error || "Report failed"
        }
      })
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
          root.flash = "Exported " + resp.count + " entries to " + (kind === "csv" ? "CSV" : "HTML")
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
    }
    spacing: Style.space(10)

    DateRangeBar {
      id: rangeBar
      service: root.service
      from: root.from
      to: root.to
      currentPreset: root.currentPreset
      width: parent.width

      onChanged: function(f, t, preset) {
        root.from = f
        root.to = t
        root.currentPreset = preset
        root.load()
      }
    }

    Row {
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
          root.load()
        }
      }
      Item { width: 1 }

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

    Text {
      text: root.flash
      color: Color.accent
      font.pixelSize: Style.font.caption
      visible: root.flash !== ""
    }
  }

  ListView {
    id: listView
    anchors {
      left: parent.left
      right: parent.right
      top: head.bottom
      topMargin: Style.space(10)
      bottom: totalsBar.top
      bottomMargin: Style.space(10)
    }
    model: root.rows
    spacing: 2
    clip: true

    delegate: Row {
      width: ListView.view.width
      spacing: Style.space(8)

      Text {
        text: modelData.label
        color: Color.foreground
        font.pixelSize: Style.font.body
        width: parent.width - Style.space(220)
        elide: Text.ElideRight
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        text: root.service.fmtHM(modelData.seconds)
        color: Color.foreground
        font.bold: true
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        text: "billable " + root.service.fmtHM(modelData.billableSeconds)
        color: Color.muted
        font.pixelSize: Style.font.caption
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }

  Item {
    id: totalsBar
    anchors {
      left: parent.left
      right: parent.right
      bottom: parent.bottom
    }
    height: Style.space(20)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "Total " + (root.service ? root.service.fmtHM(root.totalSeconds) : "—")
        + " · billable " + (root.service ? root.service.fmtHM(root.billableSeconds) : "—")
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
