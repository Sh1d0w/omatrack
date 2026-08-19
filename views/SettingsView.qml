import QtQuick
import qs.Commons
import qs.Ui
import "../components"

// Settings tab: billing defaults (currency, hourly rate) and the invoice
// identity block, grouped into four sections — Billing, Company,
// Tax & numbering, Footer. Each field is a LabeledField (body-size label
// above, input, helper line below) on an equal-width grid, so inputs in
// a row are the same size. Local copies sync from the service on load;
// Save pushes one patch. The section stack scrolls when the window is
// short; the save row and the data path stay pinned at the bottom.
Item {
  id: root

  property var dashboard: null
  // Bound, not assigned: the panel loader injects the dashboard's service
  // after this view may already be loaded, so a one-shot assignment could
  // stay null forever.
  readonly property var service: root.dashboard ? root.dashboard.service : null
  property bool dirty: false

  // The window's Esc-to-close is blocked while any field owns the
  // keyboard (the dashboard's key catcher reads this).
  readonly property bool inputActive:
    currencyF.focused || rateF.focused
    || companyNameF.focused || companyAddressF.focused
    || taxRateF.focused || prefixF.focused || nextNumberF.focused
    || footerF.focused

  property string flash: ""
  Timer {
    id: flashTimer
    interval: 2000
    onTriggered: root.flash = ""
  }

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
      if (resp.ok) {
        root.dirty = false
        root.flash = "Settings saved"
        flashTimer.restart()
      } else
        s.lastError = resp.error || "Save failed"
    })
  }

  // ---- header ----------------------------------------------------------
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
      textFormat: Text.PlainText
      text: "Settings"
      color: Color.foreground
      font.pixelSize: Style.font.title
      font.bold: true
    }

    Text {
      textFormat: Text.PlainText
      width: parent.width
      wrapMode: Text.Wrap
      text: "Billing defaults and the identity printed on invoices. Changes apply from the next generated invoice."
      color: Color.muted
      font.pixelSize: Style.font.caption
    }
  }

  // ---- section stack ------------------------------------------------------
  // Scrolls when the window is short; while it fits, the flickable is
  // inert so fields behave like a plain layout.
  Flickable {
    id: scroller
    anchors {
      left: parent.left
      right: parent.right
      top: head.bottom
      bottom: bottomBar.top
      topMargin: Style.space(4)
      bottomMargin: Style.space(4)
      leftMargin: Style.space(16)
      rightMargin: Style.space(16)
    }
    clip: true
    contentWidth: width
    contentHeight: form.implicitHeight
    interactive: form.implicitHeight > scroller.height
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: form
      width: Math.min(scroller.width, Style.space(720))
      spacing: Style.space(14)

      // ---- Billing ------------------------------------------------------
      Column {
        width: parent.width
        spacing: Style.space(8)

        PanelSeparator { width: parent.width }
        PanelSectionHeader { text: "Billing"; fontSize: Style.font.subtitle }

        Row {
          width: parent.width
          spacing: Style.space(12)

          LabeledField {
            id: currencyF
            width: (parent.width - Style.space(12)) / 2
            label: "Currency"
            placeholderText: "EUR"
            helper: "Code shown with money in reports, exports, and invoices (e.g. EUR, USD)."
            onTextChanged: root.markDirty()
          }

          LabeledField {
            id: rateF
            width: (parent.width - Style.space(12)) / 2
            label: "Hourly rate"
            placeholderText: "85.00"
            helper: "Price per hour used for invoice line amounts and the Price column in exports."
            onTextChanged: root.markDirty()
          }
        }
      }

      // ---- Company --------------------------------------------------------
      Column {
        width: parent.width
        spacing: Style.space(8)

        PanelSeparator { width: parent.width }
        PanelSectionHeader { text: "Company"; fontSize: Style.font.subtitle }

        Row {
          width: parent.width
          spacing: Style.space(12)

          LabeledField {
            id: companyNameF
            width: (parent.width - Style.space(12)) / 2
            label: "Company name"
            placeholderText: "Acme Ltd."
            helper: "Printed in the header of every invoice."
            onTextChanged: root.markDirty()
          }

          LabeledField {
            id: companyAddressF
            width: (parent.width - Style.space(12)) / 2
            label: "Address"
            placeholderText: "Street, 12345 City"
            helper: "Printed under the company name on every invoice."
            onTextChanged: root.markDirty()
          }
        }
      }

      // ---- Tax & numbering -------------------------------------------------
      Column {
        width: parent.width
        spacing: Style.space(8)

        PanelSeparator { width: parent.width }
        PanelSectionHeader { text: "Tax & numbering"; fontSize: Style.font.subtitle }

        Row {
          width: parent.width
          spacing: Style.space(12)

          LabeledField {
            id: taxRateF
            width: (parent.width - 2 * Style.space(12)) / 3
            label: "Tax rate %"
            placeholderText: "19"
            helper: "VAT applied to the invoice subtotal (0 for none)."
            onTextChanged: root.markDirty()
          }

          LabeledField {
            id: prefixF
            width: (parent.width - 2 * Style.space(12)) / 3
            label: "No. prefix"
            placeholderText: "INV-"
            helper: "Invoice numbers read prefix + number, e.g. INV- → INV-0001."
            onTextChanged: root.markDirty()
          }

          LabeledField {
            id: nextNumberF
            width: (parent.width - 2 * Style.space(12)) / 3
            label: "Next number"
            helper: "Number of the next invoice; advances automatically when one is generated."
            onTextChanged: root.markDirty()
          }
        }
      }

      // ---- Footer ---------------------------------------------------------
      Column {
        width: parent.width
        spacing: Style.space(8)

        PanelSeparator { width: parent.width }
        PanelSectionHeader { text: "Footer"; fontSize: Style.font.subtitle }

        LabeledField {
          id: footerF
          width: parent.width
          label: "Footer text"
          placeholderText: "Thank you for your business!"
          helper: "Optional line printed at the bottom of every invoice."
          onTextChanged: root.markDirty()
        }
      }
    }
  }

  // ---- bottom bar: save + status + data path, always visible --------------
  Column {
    id: bottomBar
    anchors {
      left: parent.left
      right: parent.right
      bottom: parent.bottom
      leftMargin: Style.space(16)
      rightMargin: Style.space(16)
      bottomMargin: Style.space(14)
    }
    spacing: Style.space(8)

    Row {
      spacing: Style.space(10)

      Button {
        text: "Save"
        leftAlign: true
        focusable: true
        onClicked: root.save()
      }

      Text {
        textFormat: Text.PlainText
        text: root.dirty ? "unsaved changes" : ""
        color: Color.accent
        font.pixelSize: Style.font.caption
        anchors.verticalCenter: parent.verticalCenter
        visible: root.dirty
      }

      Text {
        textFormat: Text.PlainText
        text: root.flash
        color: Color.accent
        font.pixelSize: Style.font.caption
        anchors.verticalCenter: parent.verticalCenter
        visible: root.flash !== ""
      }

      Text {
        textFormat: Text.PlainText
        text: root.service ? root.service.lastError : ""
        color: Color.urgent
        font.pixelSize: Style.font.caption
        anchors.verticalCenter: parent.verticalCenter
        visible: root.service && root.service.lastError !== ""
      }
    }

    Text {
      textFormat: Text.PlainText
      text: "Data: " + (root.service ? root.service.statePath : "")
      color: Color.muted
      font.pixelSize: Style.font.caption
      width: parent.width
      elide: Text.ElideRight
    }
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
