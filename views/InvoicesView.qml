import QtQuick
import qs.Commons
import qs.Ui
import "../components"

// Invoices tab: pick a range + one client, generate. The helper writes
// the HTML invoice into stateDir/invoices and returns number + path; the
// file is opened with the system handler (no WebEngine in this runtime).
Item {
  id: root

  property var service: null
  property var dashboard: null

  property string from: ""
  property string to: ""
  property string currentPreset: "all"
  property string clientId: ""
  property var invoiceResult: null

  readonly property bool inputActive: rangeBar.fieldActive || clientDrop.popupOpen

  function generate() {
    if (!root.service || root.clientId === "") return
    root.service.lastError = ""
    root.service.makeInvoice(root.clientId, root.from, root.to, function(resp) {
      if (resp.ok)
        root.invoiceResult = resp
      else
        root.service.lastError = resp.error || "Invoice failed"
    })
  }

  Column {
    id: head
    anchors {
      top: parent.top
      left: parent.left
      right: parent.right
    }
    spacing: Style.space(10)

    Text {
      text: "Invoices"
      color: Color.foreground
      font.pixelSize: Style.font.title
      font.bold: true
    }

    Text {
      text: "Billable entries for one client over a date range, grouped by project, at the configured hourly rate."
      color: Color.muted
      font.pixelSize: Style.font.caption
      width: parent.width
      wrapMode: Text.Wrap
    }

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
      }
    }

    Row {
      spacing: Style.space(8)

      Dropdown {
        id: clientDrop
        label: "Client"
        showLabel: true
        width: Style.space(200)
        value: root.clientId
        options: root.service ? root.service.clientOptions() : []
        onChanged: function(value) {
          root.clientId = value
        }
      }

      Button {
        text: "Generate invoice"
        leftAlign: true
        focusable: true
        enabled: root.clientId !== ""
        onClicked: root.generate()
      }
    }

    Text {
      text: root.service ? root.service.lastError : ""
      color: Color.urgent
      font.pixelSize: Style.font.caption
      visible: root.service && root.service.lastError !== ""
    }
  }

  // ---- result card ------------------------------------------------------------
  Rectangle {
    id: resultCard
    anchors {
      top: head.bottom
      topMargin: Style.space(12)
      left: parent.left
      right: parent.right
    }
    height: visible ? resultColumn.implicitHeight + Style.space(24) : 0
    visible: root.invoiceResult !== null
    radius: Style.cornerRadius
    color: Qt.rgba(1, 1, 1, 0.03)
    border.width: 1
    border.color: Qt.darker(Color.foreground, 2.2)

    Column {
      id: resultColumn
      anchors.centerIn: parent
      width: parent.width - Style.space(32)
      spacing: Style.space(8)

      Text {
        text: "Invoice " + (root.invoiceResult ? root.invoiceResult.number : "") + " generated"
        color: Color.foreground
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Text {
        text: root.invoiceResult
          ? "Total " + Number(root.invoiceResult.total).toFixed(2)
            + (root.service && root.service.settings.currency ? " " + root.service.settings.currency : "")
          : ""
        color: Color.foreground
        font.pixelSize: Style.font.body
      }

      Text {
        text: root.invoiceResult ? root.invoiceResult.path : ""
        color: Color.muted
        font.pixelSize: Style.font.caption
        width: parent.width
        elide: Text.ElideMiddle
      }

      Row {
        spacing: Style.space(8)

        Button {
          text: "Open file"
          leftAlign: true
          focusable: true
          onClicked: {
            if (root.service && root.invoiceResult)
              root.service.openPath(root.invoiceResult.path)
          }
        }
      }
    }
  }
}
