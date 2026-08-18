import QtQuick
import qs.Commons
import qs.Ui

// The in-view modal: a centered card on a dimmed scrim — the same visual
// language and dismissal contract as the window-level ConfirmDialog. Used
// by the Entries edit card and the Timer manual-entry modal.
//
// The host binds `visible`, closes on `scrimClicked` (or Esc via its own
// handleKey), and drops content in via the default property — it lands in
// the card's content column. Card height follows content; the host sets
// the width (`cardWidth`).
Rectangle {
  id: root

  property int cardWidth: Style.space(420)

  // A click on the scrim (not the card): the host treats it as dismissal.
  signal scrimClicked

  default property alias content: cardColumn.children

  color: Util.alpha(Color.background, 0.7)
  z: 10

  MouseArea {
    anchors.fill: parent
    onClicked: root.scrimClicked()
  }

  BorderSurface {
    id: card
    width: root.cardWidth
    height: cardColumn.implicitHeight + card.contentTopInset + card.contentBottomInset
    radius: Style.cornerRadius
    color: Color.background
    borderSpec: Border.flat(Color.accent, Style.normalBorderWidth)
    padding: Style.space(18)
    anchors.centerIn: parent

    // Swallows clicks on the card so they never reach the scrim.
    MouseArea { anchors.fill: parent }

    Column {
      id: cardColumn
      anchors {
        top: parent.top
        left: parent.left
        right: parent.right
      }
      anchors.topMargin: card.contentTopInset
      anchors.leftMargin: card.contentLeftInset
      anchors.rightMargin: card.contentRightInset
      spacing: Style.space(10)
    }
  }
}
