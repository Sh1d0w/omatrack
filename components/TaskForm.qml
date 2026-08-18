import QtQuick
import qs.Commons
import qs.Ui

// New-task fields shared by the bar popup and the dashboard Timer tab:
// client, project (scoped to the selected client), description, billable.
//
// Owns its four values; the host reads them back directly. `valid` is the
// start gate: client, project and a non-blank description are all required.
// `applyDefaults()` seeds last-client/last-project/last-description/
// last-billable exactly once (until the user edits anything, which sets
// `userTouched`). `keyActiveItem` tells the host which control currently
// owns the keys, if any.
Item {
  id: root
  width: parent ? parent.width : Style.spacing.dropdownWidth
  // Implicit size from the form column: hosts lay the form out in a
  // Column or size the panel/card by content, so a bare Item here
  // collapses to height 0 and the fields get clipped (popup card) or
  // overlapped (timer tab, entry edit card).
  implicitWidth: formColumn.implicitWidth
  implicitHeight: formColumn.implicitHeight

  property var service: null
  property string clientId: ""
  property string projectId: ""
  property string description: ""
  property bool billable: true
  property bool userTouched: false

  // Start gate: client, project and a non-blank description are required.
  readonly property bool valid:
    clientId !== "" && projectId !== "" && description.trim() !== ""

  // True while applyDefaults() is writing, so the handlers below don't
  // mistake programmatic seeding for user edits.
  property bool _applyingDefaults: false

  readonly property var keyActiveItem:
    descriptionField.activeFocus ? descriptionField
      : (clientDrop.popupOpen ? clientDrop : (projectDrop.popupOpen ? projectDrop : null))

  // The host may inject the service after the form is constructed (a
  // Loader's onLoaded runs after onCompleted), so seed the last-used
  // defaults here; explicit applyDefaults() calls from hosts only
  // re-seed (e.g. the popup on open).
  onServiceChanged: root.applyDefaults()

  Column {
    id: formColumn
    width: parent.width
    spacing: Style.space(8)

    Dropdown {
      id: clientDrop
      label: "Client"
      showLabel: true
      width: parent.width
      value: root.clientId
      options: root.service ? root.service.clientOptions() : []
      onChanged: function(v) {
        root.clientId = v
        if (!root._applyingDefaults) root.userTouched = true
        root.reselectProject()
      }
    }

    Dropdown {
      id: projectDrop
      label: "Project"
      showLabel: true
      width: parent.width
      value: root.projectId
      options: (root.service && root.clientId !== "")
        ? root.service.projectOptions(root.clientId)
        : []
      onChanged: function(v) {
        root.projectId = v
        if (!root._applyingDefaults) root.userTouched = true
      }
    }

    TextField {
      id: descriptionField
      width: parent.width
      placeholderText: "Task description (required)"
      text: root.description
      onTextChanged: {
        if (text !== root.description) root.description = text
        if (!root._applyingDefaults) root.userTouched = true
      }
    }

    Toggle {
      label: "Billable"
      description: "Counted in billable totals and invoices"
      width: parent.width
      checked: root.billable
      onClicked: {
        root.billable = !root.billable
        if (!root._applyingDefaults) root.userTouched = true
      }
    }
  }

  // Keep the selected project if it belongs to the (new) client; else the
  // last-used project if it does; else the client's first project; else "".
  function reselectProjectFor(c) {
    var opts = root.service ? root.service.projectOptions(c) : []
    if (opts.length === 0) { root.projectId = ""; return }
    for (var i = 0; i < opts.length; i++)
      if (opts[i].value === root.projectId) return
    var lu = root.service ? root.service.lastUsed : null
    if (lu && lu.clientId === c) {
      for (var j = 0; j < opts.length; j++)
        if (opts[j].value === String(lu.projectId)) { root.projectId = String(lu.projectId); return }
    }
    root.projectId = opts[0].value
  }

  function reselectProject() { root.reselectProjectFor(root.clientId) }

  // Single implementation of the last-used defaults; called by the popup on
  // open, the Timer tab on show, and EntryForm when empty.
  function applyDefaults() {
    if (root.userTouched || !root.service) return
    var s = root.service
    var lu = s.lastUsed
    root._applyingDefaults = true
    root.clientId = (lu && lu.clientId) || (s.clients.length > 0 ? s.clients[0].id : "")
    root.reselectProjectFor(root.clientId)
    root.description = (lu && lu.description) || ""
    root.billable = (lu && typeof lu.billable === "boolean") ? lu.billable : true
    root._applyingDefaults = false
  }
}
