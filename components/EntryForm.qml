import QtQuick
import qs.Commons
import qs.Ui
import "."

// Manual time entry: local date + start time + duration, plus the shared
// TaskForm for client/project/description/billable. `defaultsToToday()`
// fills today's date, the current time and 60 minutes the first time the
// form is shown empty. `valid` gates the caller's submit button.
Item {
  id: root
  width: parent ? parent.width : Style.spacing.dropdownWidth
  // Implicit size from the form column (same reason as TaskForm): the
  // entry edit card derives its height from implicitHeight.
  implicitWidth: formColumn.implicitWidth
  implicitHeight: formColumn.implicitHeight

  required property var service

  property string dateStr: ""
  property string timeStr: ""
  property int minutes: 60

  // TaskForm fields, mirrored so the caller can read everything in one place.
  property string clientId: ""
  property string projectId: ""
  property string description: ""
  property bool billable: true

  readonly property bool valid:
    /^\d{4}-\d{2}-\d{2}$/.test(root.dateStr) &&
    /^\d{2}:\d{2}$/.test(root.timeStr) &&
    root.minutes >= 1 &&
    root.clientId !== "" &&
    root.projectId !== ""

  readonly property var keyActiveItem:
    datePicker.triggerItem.activeFocus || datePicker.popupOpen ? datePicker.triggerItem
      : (timeField.activeFocus ? timeField
        : (minutesField.field.activeFocus ? minutesField.field : task.keyActiveItem))
  // Hosts inject the service after construction; fill today's values and
  // the task defaults then (defaultsToToday() guards against re-filling).
  onServiceChanged: { if (root.service) root.defaultsToToday() }


  Column {
    id: formColumn
    width: parent.width
    spacing: Style.space(8)

    Row {
      width: parent.width
      spacing: Style.space(6)

      DatePicker {
        id: datePicker
        date: root.dateStr
        onChanged: function(d) { root.dateStr = d }
      }

      TextField {
        id: timeField
        width: parent.width - Style.space(6) - datePicker.implicitWidth
        placeholderText: "HH:MM"
        text: root.timeStr
        onTextChanged: {
          if (text !== root.timeStr) root.timeStr = text
        }
      }
    }

    NumberField {
      id: minutesField
      label: "Minutes"
      from: 1
      to: 1440
      value: root.minutes
      fieldWidth: Math.max(90, parent.width - Style.space(100))
      onModified: function(v) { root.minutes = v }
    }

    TaskForm {
      id: task
      width: parent.width
      service: root.service
      clientId: root.clientId
      projectId: root.projectId
      description: root.description
      billable: root.billable
      onClientIdChanged: { root.clientId = clientId }
      onProjectIdChanged: { root.projectId = projectId }
      onDescriptionChanged: { root.description = description }
      onBillableChanged: { root.billable = billable }
    }
  }

  function defaultsToToday() {
    if (root.dateStr !== "" && root.clientId !== "") return
    var now = new Date()
    root.dateStr = root.service.localDateStr(now)
    root.timeStr = root.service.localTimeStr(now)
    root.minutes = 60
    task.applyDefaults()
  }
}
