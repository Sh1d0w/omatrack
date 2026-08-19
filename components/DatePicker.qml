import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Read-only date field for range filters: a Dropdown-style trigger showing
// YYYY-MM-DD (a muted placeholder when empty) that opens a month-grid
// calendar popup below. One month at a time, Monday-first weeks, 42 cells
// so the popup height is constant. Click a day to pick it; the footer
// offers Today and Clear.
//
// The host owns the value: this component only displays `date` and emits
// `changed(dateStr)` — the host writes the new value back through its own
// binding, so the host->picker binding never breaks.
//
// Keyboard: Enter/Space/Down opens the popup from the trigger. While open,
// Left/Right move the cursor a day, Up/Down a week, Enter selects, Esc (or
// a press outside) closes. `popupOpen` lets the host view keep the window's
// key catcher blocked while the picker owns the keyboard.
Item {
  id: root

  property string date: ""            // "YYYY-MM-DD" or "" (no bound)
  property string label: ""           // optional caption label above the trigger
  property string placeholder: "YYYY-MM-DD"

  readonly property bool popupOpen: popup.opened
  // The trigger control, exposed so hosts can fold "picker trigger focused
  // or popup open" into their key-gating (keyActiveItem / inputActive).
  readonly property Item triggerItem: trigger


  signal changed(string date)

  function open() { if (!popup.opened) popup.open() }
  function close() { popup.close() }
  function toggle() { popup.opened ? popup.close() : popup.open() }

  // ---- month grid (local calendar, 42 cells, Monday-first) -----------------
  property int viewYear: 0
  property int viewMonth: 1           // 1-12
  property int cursor: -1             // 0..41 index into gridModel, -1 = none
  property var gridModel: []

  readonly property int cell: Style.space(26)

  readonly property var monthNames: [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December"
  ]

  function pad2(n) { return n < 10 ? "0" + n : String(n) }
  function dayStr(y, m, d) { return y + "-" + pad2(m) + "-" + pad2(d) }
  function todayStr() {
    var n = new Date()
    return dayStr(n.getFullYear(), n.getMonth() + 1, n.getDate())
  }
  function daysInMonth(y, m) { return new Date(y, m, 0).getDate() }   // m: 1-12
  function lead(y, m) { return (new Date(y, m - 1, 1).getDay() + 6) % 7 }
  function indexOfDay(day) { return lead(viewYear, viewMonth) + day - 1 }

  function parseDate(s) {
    if (typeof s !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(s)) return null
    var y = parseInt(s.substring(0, 4), 10)
    var m = parseInt(s.substring(5, 7), 10)
    var d = parseInt(s.substring(8, 10), 10)
    var dt = new Date(y, m - 1, d)
    if (dt.getFullYear() !== y || dt.getMonth() !== m - 1 || dt.getDate() !== d)
      return null
    return dt
  }

  // Rebuild the 42 cell descriptors for the visible month. Called on open
  // and on every view change (the delegates bind plain values, so a fresh
  // model is what repaints the grid). Each cell carries its own grid
  // index: the Repeater context `index` is not reachable from the
  // delegate's event handlers once the delegate declares required
  // properties, so the handlers read it from the model data instead.
  function rebuildGrid() {
    if (viewYear <= 0) return
    var l = lead(viewYear, viewMonth)
    var today = todayStr()
    var out = []
    for (var i = 0; i < 42; i++) {
      var d = new Date(viewYear, viewMonth - 1, 1 - l + i)
      var s = dayStr(d.getFullYear(), d.getMonth() + 1, d.getDate())
      out.push({
        i: i,
        y: d.getFullYear(),
        m: d.getMonth() + 1,
        day: d.getDate(),
        str: s,
        inMonth: d.getFullYear() === viewYear && d.getMonth() + 1 === viewMonth,
        isToday: s === today
      })
    }
    gridModel = out
  }

  // ---- selection --------------------------------------------------------------
  function pickCell(i) {
    if (i < 0 || i >= gridModel.length) return
    var c = gridModel[i]
    popup.close()
    root.changed(c.str)
  }
  function pickCursor() { root.pickCell(root.cursor) }
  function pickToday() {
    popup.close()
    root.changed(todayStr())
  }
  function clearDate() {
    popup.close()
    root.changed("")
  }

  function shiftMonth(delta) {
    var m = viewMonth + delta
    if (m < 1) { m = 12; viewYear-- }
    else if (m > 12) { m = 1; viewYear++ }
    viewMonth = m
    if (cursor >= 0 && cursor < gridModel.length)
      cursor = indexOfDay(Math.min(gridModel[cursor].day, daysInMonth(viewYear, viewMonth)))
  }

  function moveCursor(delta) {
    if (cursor < 0) cursor = 0
    var next = Math.max(0, Math.min(41, cursor + delta))
    if (next === cursor) return
    var c = gridModel[next]
    if (c.y !== viewYear || c.m !== viewMonth) {
      // The cursor wandered into a spillover cell: follow it into that
      // month so the highlight stays under the cursor.
      viewYear = c.y
      viewMonth = c.m
      cursor = indexOfDay(c.day)
    } else {
      cursor = next
    }
  }

  Component.onCompleted: rebuildGrid()
  onViewYearChanged: rebuildGrid()
  onViewMonthChanged: rebuildGrid()

  implicitWidth: Style.space(110)
  implicitHeight: root.label !== ""
    ? labelText.implicitHeight + Style.spacing.labelGap + Style.spacing.controlHeight
    : Style.spacing.controlHeight

  Column {
    id: col
    width: parent.width
    spacing: Style.spacing.labelGap

    Text {
      id: labelText
      visible: root.label !== ""
      text: root.label
      color: Qt.darker(Color.foreground, 1.4)
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    BorderSurface {
      id: trigger
      width: parent.width
      height: Style.spacing.controlHeight
      radius: Style.cornerRadius

      readonly property bool _hot: triggerHover.hovered || trigger.activeFocus
      color: Style.controlFill(trigger.activeFocus, trigger._hot, Color.foreground, Color.accent)
      borderSpec: Border.controlSpec(
        trigger.activeFocus ? "focus" : (trigger._hot ? "hover-cursor" : "normal"),
        Color.foreground, Color.accent)
      activeFocusOnTab: true

      HoverHandler { id: triggerHover }

      Text {
        anchors.left: parent.left
        anchors.right: chevron.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.spacing.controlPaddingX
        anchors.rightMargin: Style.spacing.md
        text: root.date !== "" ? root.date : root.placeholder
        color: root.date !== "" ? Color.foreground : Qt.darker(Color.foreground, 2.0)
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        id: chevron
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: Style.spacing.controlGap
        text: "󰅀"
        color: Qt.darker(Color.foreground, 1.2)
        font.pixelSize: Style.font.body
      }

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
            || event.key === Qt.Key_Space || event.key === Qt.Key_Down) {
          popup.opened ? popup.close() : popup.open()
          event.accepted = true
        }
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          trigger.forceActiveFocus()
          popup.opened ? popup.close() : popup.open()
        }
      }

      Popup {
        id: popup
        x: 0
        y: trigger.height + Style.spacing.xxs
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape
          | Popup.CloseOnPressOutside
          | Popup.CloseOnPressOutsideRoot
        padding: Style.spacing.xxl

        background: BorderSurface {
          color: Color.popups.background
          borderSpec: Border.localOrSurfaceSpec("popups", "border",
            Color.popups.border, Color.popups.border, Style.normalBorderWidth)
          radius: Style.cornerRadius
        }

        onOpened: {
          var base = root.parseDate(root.date)
          if (base) {
            root.viewYear = base.getFullYear()
            root.viewMonth = base.getMonth() + 1
            root.cursor = root.indexOfDay(base.getDate())
          } else {
            var n = new Date()
            root.viewYear = n.getFullYear()
            root.viewMonth = n.getMonth() + 1
            root.cursor = root.indexOfDay(n.getDate())
          }
          cal.forceActiveFocus()
        }

        contentItem: Column {
          id: cal
          focus: true
          spacing: Style.spacing.md

          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              popup.close()
              event.accepted = true
            } else if (event.key === Qt.Key_Left) {
              root.moveCursor(-1); event.accepted = true
            } else if (event.key === Qt.Key_Right) {
              root.moveCursor(1); event.accepted = true
            } else if (event.key === Qt.Key_Up) {
              root.moveCursor(-7); event.accepted = true
            } else if (event.key === Qt.Key_Down) {
              root.moveCursor(7); event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.pickCursor(); event.accepted = true
            }
          }

          // Month navigation
          Row {
            width: 7 * root.cell
            spacing: 0

            Button {
              text: "◀"
              width: root.cell
              height: root.cell
              fontSize: Style.font.caption
              horizontalPadding: 0
              verticalPadding: 0
              focusable: false
              onClicked: root.shiftMonth(-1)
            }

            Text {
              width: 7 * root.cell - 2 * root.cell
              height: parent.height
              text: root.monthNames[root.viewMonth - 1] + " " + root.viewYear
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              color: Color.foreground
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Button {
              text: "▶"
              width: root.cell
              height: root.cell
              fontSize: Style.font.caption
              horizontalPadding: 0
              verticalPadding: 0
              focusable: false
              onClicked: root.shiftMonth(1)
            }
          }

          // Weekday header (Monday-first)
          Row {
            width: 7 * root.cell

            Repeater {
              model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
              Text {
                required property string modelData
                width: root.cell
                text: modelData
                horizontalAlignment: Text.AlignHCenter
                color: Qt.darker(Color.foreground, 1.8)
                font.pixelSize: Style.font.caption
              }
            }
          }

          // Day grid: 42 cells, stable height across months.
          Grid {
            id: dayGrid
            columns: 7
            width: 7 * root.cell

            Repeater {
              model: root.gridModel
              delegate: Rectangle {
                id: dayCell
                required property var modelData
                width: root.cell
                height: root.cell
                radius: Style.cornerRadius

                readonly property bool _isCursor: root.cursor === modelData.i
                readonly property bool _hot: _isCursor || cellHover.hovered
                readonly property bool _isSelected: root.date !== "" && modelData.str === root.date

                color: _isSelected ? Style.selectedAccentFill
                     : _hot ? Style.hoverFillFor(Color.foreground, Color.accent)
                     : "transparent"
                border.color: modelData.isToday && !_isSelected ? Util.alpha(Color.accent, 0.9) : "transparent"
                border.width: modelData.isToday && !_isSelected ? 1 : 0

                Text {
                  anchors.centerIn: parent
                  text: modelData.day
                  color: !modelData.inMonth ? Qt.darker(Color.foreground, 2.6)
                       : _isSelected ? Color.accent
                       : Color.foreground
                  font.pixelSize: Style.font.bodySmall
                  font.bold: _isSelected
                }

                HoverHandler {
                  id: cellHover
                  onHoveredChanged: { if (hovered) root.cursor = modelData.i }
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.pickCell(modelData.i)
                }
              }
            }
          }

          // Footer shortcuts
          Row {
            width: 7 * root.cell
            spacing: Style.spacing.xs

            Button {
              text: "Today"
              fontSize: Style.font.caption
              leftAlign: true
              focusable: false
              onClicked: root.pickToday()
            }

            Item { width: 1 }

            Button {
              text: "Clear"
              fontSize: Style.font.caption
              leftAlign: true
              focusable: false
              onClicked: root.clearDate()
            }
          }
        }
      }
    }
  }
}
