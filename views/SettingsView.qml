import QtQuick
import qs.Commons
import qs.Ui

// Settings tab: currency, hourly rate, and the invoice identity block.
// Local copies sync from the service on load; Save pushes one patch.
Item {
  id: root

  property var dashboard: null
  // Bound, not assigned: the panel loader injects the dashboard's service
  // after this view may already be loaded, so a one-shot assignment could
  // stay null forever.
  readonly property var service: root.dashboard ? root.dashboard.service : null
  property int focusCount: 0
  property bool dirty: false
  readonly property bool inputActive: focusCount > 0

  function syncFromSettings() {
    var s = root.service
    if (!s || !s.settings) return
    currencyF.text = s.settings.currency
    rateF.text = String(s.settings.hourlyRate)
    companyNameF.text = s.settings.invoice.companyName
    companyAddressF.text = s.settings.invoice.companyAddress
    taxRateF.text = String(s.settings.invoice.taxRate)
    prefixF.text = s.settings.invoice.numberPrefix
    nextNumberF.text = String(s.settings.invoice.nextNumber)
    footerF.text = s.settings.invoice.footer
    root.dirty = false
  }

  function markDirty() {
    root.dirty = true
  }

  function save() {
    var s = root.service
    if (!s) return
    var rate = parseFloat(rateF.text)
    if (!isFinite(rate) || rate < 0) {
      s.lastError = "Invalid hourly rate"
      return
    }
    var tax = parseFloat(taxRateF.text)
    if (!isFinite(tax) || tax < 0 || tax > 100) {
      s.lastError = "Invalid tax rate (0–100)"
      return
    }
    var next = parseInt(nextNumberF.text, 10)
    if (!isFinite(next) || next < 1) {
      s.lastError = "Invalid next invoice number"
      return
    }
    s.saveSettings({
      currency: currencyF.text.trim() || "EUR",
      hourlyRate: rate,
      invoice: {
        companyName: companyNameF.text.trim(),
        companyAddress: companyAddressF.text.trim(),
        taxRate: tax,
        numberPrefix: prefixF.text.trim(),
        nextNumber: next,
        footer: footerF.text.trim()
      }
    }, function(resp) {
      if (resp.ok)
        root.dirty = false
      else
        s.lastError = resp.error || "Save failed"
    })
  }

  Column {
    id: scrollHead
    anchors {
      top: parent.top
      left: parent.left
      right: parent.right
    }
    spacing: Style.space(10)

    Text {
      text: "Settings"
      color: Color.foreground
      font.pixelSize: Style.font.title
      font.bold: true
    }

    Row {
      spacing: Style.space(8)
      Text { text: "Currency"; color: Color.muted; font.pixelSize: Style.font.caption; width: Style.space(130); anchors.verticalCenter: parent.verticalCenter }
      TextField {
        id: currencyF
        width: Style.space(80)
        onActiveFocusChanged: root.focusCount = Math.max(0, root.focusCount + (activeFocus ? 1 : -1))
        onTextChanged: root.markDirty()
      }
    }

    Row {
      spacing: Style.space(8)
      Text { text: "Hourly rate"; color: Color.muted; font.pixelSize: Style.font.caption; width: Style.space(130); anchors.verticalCenter: parent.verticalCenter }
      TextField {
        id: rateF
        width: Style.space(110)
        placeholderText: "e.g. 85.00"
        onActiveFocusChanged: root.focusCount = Math.max(0, root.focusCount + (activeFocus ? 1 : -1))
        onTextChanged: root.markDirty()
      }
    }

    Row {
      spacing: Style.space(8)
      Text { text: "Company"; color: Color.muted; font.pixelSize: Style.font.caption; width: Style.space(130); anchors.verticalCenter: parent.verticalCenter }
      TextField {
        id: companyNameF
        width: parent.width - Style.space(138)
        onActiveFocusChanged: root.focusCount = Math.max(0, root.focusCount + (activeFocus ? 1 : -1))
        onTextChanged: root.markDirty()
      }
    }

    Row {
      spacing: Style.space(8)
      Text { text: "Address"; color: Color.muted; font.pixelSize: Style.font.caption; width: Style.space(130); anchors.verticalCenter: parent.verticalCenter }
      TextField {
        id: companyAddressF
        width: parent.width - Style.space(138)
        onActiveFocusChanged: root.focusCount = Math.max(0, root.focusCount + (activeFocus ? 1 : -1))
        onTextChanged: root.markDirty()
      }
    }

    Row {
      spacing: Style.space(8)
      Text { text: "Tax rate %"; color: Color.muted; font.pixelSize: Style.font.caption; width: Style.space(130); anchors.verticalCenter: parent.verticalCenter }
      TextField {
        id: taxRateF
        width: Style.space(80)
        placeholderText: "0"
        onActiveFocusChanged: root.focusCount = Math.max(0, root.focusCount + (activeFocus ? 1 : -1))
        onTextChanged: root.markDirty()
      }
    }

    Row {
      spacing: Style.space(8)
      Text { text: "No. prefix"; color: Color.muted; font.pixelSize: Style.font.caption; width: Style.space(130); anchors.verticalCenter: parent.verticalCenter }
      TextField {
        id: prefixF
        width: Style.space(110)
        onActiveFocusChanged: root.focusCount = Math.max(0, root.focusCount + (activeFocus ? 1 : -1))
        onTextChanged: root.markDirty()
      }
    }

    Row {
      spacing: Style.space(8)
      Text { text: "Next number"; color: Color.muted; font.pixelSize: Style.font.caption; width: Style.space(130); anchors.verticalCenter: parent.verticalCenter }
      TextField {
        id: nextNumberF
        width: Style.space(80)
        onActiveFocusChanged: root.focusCount = Math.max(0, root.focusCount + (activeFocus ? 1 : -1))
        onTextChanged: root.markDirty()
      }
    }

    Row {
      spacing: Style.space(8)
      Text { text: "Footer"; color: Color.muted; font.pixelSize: Style.font.caption; width: Style.space(130); anchors.verticalCenter: parent.verticalCenter }
      TextField {
        id: footerF
        width: parent.width - Style.space(138)
        placeholderText: "Printed on the invoice"
        onActiveFocusChanged: root.focusCount = Math.max(0, root.focusCount + (activeFocus ? 1 : -1))
        onTextChanged: root.markDirty()
      }
    }

    Row {
      spacing: Style.space(8)

      Button {
        text: "Save"
        leftAlign: true
        focusable: true
        onClicked: root.save()
      }

      Text {
        text: root.dirty ? "unsaved changes" : ""
        color: Color.accent
        font.pixelSize: Style.font.caption
        anchors.verticalCenter: parent.verticalCenter
        visible: root.dirty
      }

      Text {
        text: root.service ? root.service.lastError : ""
        color: Color.urgent
        font.pixelSize: Style.font.caption
        anchors.verticalCenter: parent.verticalCenter
        visible: root.service && root.service.lastError !== ""
      }
    }
  }

  Text {
    anchors {
      left: parent.left
      bottom: parent.bottom
    }
    text: "Data: " + (root.service ? root.service.statePath : "")
    color: Color.muted
    font.pixelSize: Style.font.caption
  }

  Connections {
    target: root.service
    function onSettingsChanged() {
      if (root && !root.dirty)
        root.syncFromSettings()
    }
  }
  Timer {
    id: syncTimer
    interval: 0
    repeat: false
    running: root.service !== null
    onTriggered: root.syncFromSettings()
  }
}
