import QtQuick
import qs.Commons
import qs.Ui
import "../components"

// Invoices tab: a paginated table of generated invoices (newest first,
// InvoiceRow), narrowed by the top Client filter (default "All"), plus a
// Generate invoice button pinned to the far right that opens a centered
// CardOverlay form (billing range + client — the same modal language as
// the other views' add/edit cards). Generation runs through the helper,
// which writes the HTML file and records the invoice in state, so the
// table refreshes through the usual state view. An empty table shows a
// centered EmptyMessage. Open on a row hands the file to the system
// handler (no WebEngine in this runtime).
Item {
  id: root

  property var dashboard: null
  // Bound, not assigned: the panel loader injects the dashboard's service
  // after this view may already be loaded, so a one-shot assignment could
  // stay null forever.
  readonly property var service: root.dashboard ? root.dashboard.service : null

  // The top Client picker: "" (the default, "All") shows every invoice;
  // a concrete client id narrows the table to that client's invoices.
  property string clientFilter: ""

  property int offset: 0
  readonly property int limit: root.service ? root.service.pageSize : 15

  // The filtered table list; the binding follows the service's invoices
  // array, so a generation (a state mutation) refreshes it.
  readonly property var filteredInvoices: {
    var s = root.service
    if (!s) return []
    if (root.clientFilter === "") return s.invoices
    var out = []
    var list = s.invoices
    for (var i = 0; i < list.length; i++)
      if (list[i].clientId === root.clientFilter) out.push(list[i])
    return out
  }
  readonly property int totalCount: root.filteredInvoices.length

  readonly property string emptyMessage:
    root.clientFilter === "" ? "No invoices" : "No invoices for this client"

  // ---- generate card ------------------------------------------------------
  // The form: an explicit billing range (defaults to today → today; the
  // helper demands from/to, so the defaults are always a concrete range)
  // and one client — no "All" option: an invoice is always for exactly
  // one client.
  property bool generateOpen: false
  property string genFrom: ""
  property string genTo: ""
  property string genClientId: ""

  // The window keyCatcher blocks while a dropdown or the open generate card
  // owns the keyboard (the card's range pickers are covered by
  // generateOpen).
  readonly property bool inputActive: clientDrop.popupOpen || genClientDrop.popupOpen
    || root.generateOpen

  property string flash: ""

  Timer {
    id: flashTimer
    interval: 2000
    onTriggered: root.flash = ""
  }

  function prevPage() { root.offset = Math.max(0, root.offset - root.limit) }
  function nextPage() {
    root.offset = Math.min(Math.max(0, root.totalCount - root.limit), root.offset + root.limit)
  }

  function openGenerate() {
    var s = root.service
    if (!s) return
    // Default range: today → today (a concrete range — the helper demands
    // from/to).
    var today = s.localDateStr(new Date())
    root.genFrom = today
    root.genTo = today
    // Default client: the table's filtered client when one is picked,
    // else the first client.
    root.genClientId = (root.clientFilter !== "" && s.clientName(root.clientFilter) !== "")
      ? root.clientFilter
      : (s.clients.length > 0 ? s.clients[0].id : "")
    genClientDrop.value = root.genClientId
    root.generateOpen = true
    Qt.callLater(function() { genFromPicker.triggerItem.forceActiveFocus() })
  }

  function closeGenerate() { root.generateOpen = false }

  function generate() {
    var s = root.service
    if (!s) return
    if (root.genClientId === "") {
      s.lastError = "Pick a client"
      return
    }
    if (root.genFrom === "" || root.genTo === "") {
      s.lastError = "Pick a billing range (from and to)"
      return
    }
    var from = root.genFrom
    var to = root.genTo
    var clientId = root.genClientId
    s.makeInvoice(clientId, from, to, function(resp) {
      if (resp.ok) {
        root.closeGenerate()
        // The new invoice is first in the list (the helper prepends):
        // follow it in the filter so the row is visible.
        root.clientFilter = clientId
        clientDrop.value = clientId
        root.offset = 0
        root.flash = "Invoice " + resp.number + " generated"
        flashTimer.restart()
      } else
        s.lastError = resp.error || "Invoice failed"
    })
  }

  function openInvoice(inv) {
    if (root.service && inv)
      root.service.openPath(inv.path)
  }

  // Window-level key gate: Esc closes the generate card, same dismissal
  // as clicking its scrim.
  function handleKey(event) {
    if (root.generateOpen && event.key === Qt.Key_Esc) {
      root.closeGenerate()
      return true
    }
    return false
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
      textFormat: Text.PlainText
      text: "Invoices"
      color: Color.foreground
      font.pixelSize: Style.font.title
      font.bold: true
    }

    Text {
      textFormat: Text.PlainText
      text: "Generated invoices, newest first — one client, one date range, one line per project at the configured hourly rate."
      color: Color.muted
      font.pixelSize: Style.font.caption
      width: parent.width
      wrapMode: Text.Wrap
    }

    // Top row: the Client picker is the table filter (default "All"); the
    // Generate button pins to the far right (shared bottom edge) and
    // opens the generate card.
    Item {
      id: filterBar
      width: parent.width
      height: clientDrop.implicitHeight

      Dropdown {
        id: clientDrop
        anchors { left: parent.left; top: parent.top }
        label: "Client"
        showLabel: true
        width: Style.space(170)
        value: root.clientFilter
        options: {
          var opts = [{ value: "", label: "All" }]
          if (root.service) opts = opts.concat(root.service.clientOptions())
          return opts
        }
        onChanged: function(value) {
          root.clientFilter = value
          root.offset = 0
        }
      }

      Button {
        id: generateButton
        text: "Generate invoice"
        leftAlign: true
        anchors { right: parent.right; bottom: parent.bottom }
        focusable: true
        onClicked: root.openGenerate()
      }
    }
  }

  // ---- table ----------------------------------------------------------------
  // QML-side pagination: the full invoices array stays in the service,
  // only the current page slice of the filtered list becomes the list
  // model.
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
    model: root.filteredInvoices.slice(root.offset, root.offset + root.limit)
    spacing: 2
    clip: true

    delegate: InvoiceRow {
      width: listView.width
      service: root.service
      onOpenRequested: root.openInvoice(modelData)
    }

    EmptyMessage {
      message: root.emptyMessage
      visible: root.totalCount === 0
    }
  }

  // ---- pager + status -----------------------------------------------------------
  // Pinned to the bottom of the table: the shared PaginationBar (page
  // navigation) with the flash/error status texts to its right.
  Row {
    id: pagerBar
    anchors {
      left: parent.left
      right: parent.right
      bottom: parent.bottom
      leftMargin: Style.space(16)
      rightMargin: Style.space(16)
      bottomMargin: Style.space(16)
    }
    spacing: Style.space(8)

    PaginationBar {
      id: pageBar
      total: root.totalCount
      offset: root.offset
      limit: root.limit
      emptyText: root.emptyMessage
      onPrevRequested: root.prevPage()
      onNextRequested: root.nextPage()
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
      elide: Text.ElideRight
      visible: root.service && root.service.lastError !== ""
    }
  }

  // ---- generate card overlay ------------------------------------------------------
  // Shared card-on-scrim modal (CardOverlay): same visual language and
  // dismissal semantics as the Clients/Projects add cards — scrim click or
  // Esc discards (Esc via the view's handleKey, routed by the dashboard's
  // key gate).
  CardOverlay {
    id: generateOverlay
    anchors.fill: parent
    visible: root.generateOpen
    cardWidth: Style.space(420)
    onScrimClicked: root.closeGenerate()

    Text {
      textFormat: Text.PlainText
      text: "Generate invoice"
      color: Color.foreground
      font.pixelSize: Style.font.title
      font.bold: true
    }

    Row {
      width: parent.width
      spacing: Style.space(12)

      DatePicker {
        id: genFromPicker
        label: "From"
        date: root.genFrom
        onChanged: function(d) { root.genFrom = d }
      }

      DatePicker {
        id: genToPicker
        label: "To"
        date: root.genTo
        onChanged: function(d) { root.genTo = d }
      }
    }

    Dropdown {
      id: genClientDrop
      label: "Client"
      showLabel: true
      width: parent.width
      value: root.genClientId
      options: root.service ? root.service.clientOptions() : []
      onChanged: function(value) {
        root.genClientId = value
      }
    }

    Row {
      spacing: Style.space(8)

      Button {
        text: "Generate"
        leftAlign: true
        focusable: true
        onClicked: root.generate()
      }

      Button {
        text: "Close"
        leftAlign: true
        focusable: true
        onClicked: root.closeGenerate()
      }
    }
  }
}
