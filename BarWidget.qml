import QtQuick
import qs.Commons
import qs.Ui

// Bar badge: an icon and the shell's RSS. The tooltip names the heaviest
// helper; a click opens Panel.qml, which owns the data.
BarWidget {
  id: root
  moduleName: "nejcc.plugin-probe"

  readonly property var panelItem: panelLoader.item

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = button
    target.hostWidget = root
  }

  // Shape contract for shell summon/hide/toggle routing and popout switching
  // (Bar.findPanelWidget wants open/close/opened on the bar-widget root).
  readonly property bool opened: panelItem ? panelItem.opened === true : false
  readonly property bool popoutSwitchClosing: panelItem ? panelItem.popoutSwitchClosing === true : false

  function open() { if (panelItem) panelItem.open() }
  function close() { if (panelItem) panelItem.close() }
  function toggle() { if (panelItem) panelItem.toggle() }
  function closeForPopoutSwitch() { if (panelItem) panelItem.closeForPopoutSwitch() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    keepSpace: true
    text: root.panelItem && root.panelItem.label !== ""
      ? (root.vertical ? root.panelItem.icon : root.panelItem.icon + " " + root.panelItem.label)
      : (root.panelItem ? root.panelItem.icon : "")
    tooltipText: root.panelItem ? root.panelItem.tooltip : ""
    onPressed: function(b) {
      if (b === Qt.MiddleButton) { if (root.panelItem) root.panelItem.refresh() }
      else root.toggle()
    }
  }
}
