import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Plugin probe's panel and data owner. BarWidget.qml shows `label` and
// `tooltip`; this file runs `bin/probe snapshot --json` and lists plugins
// with helper processes, heaviest first (the script already sorts them).
//
// Polls every 5 min, every 10 s while the panel is open. Each run is two
// /proc passes about a second apart.
Panel {
  id: root
  moduleName: "nejcc.plugin-probe"
  ipcTarget: "nejcc.plugin-probe"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property string helper: String(Qt.resolvedUrl("bin/probe")).replace(/^file:\/\//, "")
  readonly property string icon: "󰍛"

  property var snap: null
  property string error: ""

  readonly property var heavy: snap ? snap.plugins.filter(function(p) { return p.processes > 0 }) : []
  readonly property var topPlugin: heavy.length > 0 ? heavy[0] : null
  readonly property int insideOnly: snap ? snap.plugins.filter(function(p) { return p.processes === 0 && p.enabled === true }).length : 0
  readonly property string label: snap && snap.shell ? mb(snap.shell.rssKb) : ""
  readonly property string tooltip: !snap || !snap.shell ? error
    : "Shell " + mb(snap.shell.rssKb) + ", " + snap.shell.cpu + "% CPU"
      + (topPlugin ? "\nTop helper: " + topPlugin.id + " " + mb(topPlugin.rssKb) : "")

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function mb(kb) {
    var v = kb / 1024
    return (v >= 100 ? Math.round(v) : v.toFixed(1)) + " MB"
  }

  function refresh() {
    if (!proc.running) proc.running = true
  }

  function open() {
    root.controller.show()
    refresh()
  }

  function close() { root.controller.hide() }
  function toggle() { root.opened ? close() : open() }

  Component.onCompleted: refresh()

  Process {
    id: proc
    command: ["bash", root.helper, "snapshot", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          root.snap = JSON.parse(text)
          root.error = ""
        } catch (e) {
          root.error = "probe: no data"
        }
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text).trim() !== "") root.error = String(text).trim()
    }
  }

  Timer {
    interval: root.opened ? 10000 : 300000 // ponytail: a full scan costs ~0.5s CPU; read only the shell RSS when closed if 5 min is too stale
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(10)

        Row {
          spacing: Style.space(14)

          Text {
            textFormat: Text.PlainText
            text: root.icon
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              text: "Plugin probe"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              text: root.snap && root.snap.shell
                ? ("Shell " + root.mb(root.snap.shell.rssKb) + " · " + root.snap.shell.cpu + "% CPU").toUpperCase()
                : root.error
              color: root.fg
              opacity: 0.6
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
            }
          }
        }

        PanelSeparator { foreground: root.fg }

        CostRow { name: "PLUGIN"; procs: "PROCS"; rss: "RSS"; cpu: "CPU"; header: true }

        Repeater {
          model: root.heavy

          CostRow {
            required property var modelData
            name: modelData.id + (modelData.enabled === false ? " (off)" : "")
            procs: String(modelData.processes)
            rss: root.mb(modelData.rssKb)
            cpu: modelData.cpu + "%"
          }
        }

        CostRow {
          visible: root.snap !== null && root.snap.unattributed.processes > 0
          name: "other shell children"
          procs: root.snap ? String(root.snap.unattributed.processes) : ""
          rss: root.snap ? root.mb(root.snap.unattributed.rssKb) : ""
          cpu: root.snap ? root.snap.unattributed.cpu + "%" : ""
          dim: true
        }

        PanelSeparator { foreground: root.fg }

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: root.insideOnly + " enabled plugins run no helper process; their cost is inside the shell above. "
            + "To measure one, run in a terminal: probe ablate <id>"
          color: root.fg
          opacity: 0.6
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  component CostRow: Row {
    property string name: ""
    property string procs: ""
    property string rss: ""
    property string cpu: ""
    property bool header: false
    property bool dim: false

    width: column.width
    spacing: Style.space(8)
    opacity: header || dim ? 0.6 : 1

    Cell { text: parent.name; width: parent.width - Style.space(200) - parent.spacing * 3; elide: Text.ElideMiddle; horizontalAlignment: Text.AlignLeft }
    Cell { text: parent.procs; width: Style.space(50) }
    Cell { text: parent.rss; width: Style.space(80) }
    Cell { text: parent.cpu; width: Style.space(70) }
  }

  component Cell: Text {
    textFormat: Text.PlainText
    horizontalAlignment: Text.AlignRight
    color: root.fg
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
}
