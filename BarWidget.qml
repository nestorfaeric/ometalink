import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.nestorfaeric.ometalink"

  readonly property string binDir: String(Qt.resolvedUrl("bin")).replace(/^file:\/\//, "")
  readonly property string address: String(setting("address", ""))
  readonly property int pollSeconds: Math.max(5, Number(setting("pollSeconds", 15)))
  readonly property bool hideWhenDisconnected: setting("hideWhenDisconnected", false) === true

  readonly property string glassesGlyph: String.fromCodePoint(0xF02AA)
  readonly property string glassesOffGlyph: String.fromCodePoint(0xF00B2)

  property var state: ({ found: false, connected: false })
  property bool popupOpen: false
  property bool busy: false

  readonly property bool opened: popupOpen
  readonly property bool connected: state.connected === true
  readonly property string deviceName: state.name ? state.name : "Ray-Ban Meta"
  readonly property string codecLabel: state.codec ? String(state.codec).toUpperCase() : "—"
  readonly property string batteryLabel: state.battery === null || state.battery === undefined ? "Not reported" : state.battery + "%"
  readonly property string volumeLabel: state.volume === null || state.volume === undefined
    ? "—" : (state.muted ? "Muted" : state.volume + "%")

  readonly property string statusText: {
    if (!state.found) return "No glasses paired"
    if (busy) return "Working…"
    if (!connected) return "Disconnected"
    return (state.playing ? "Playing" : "Connected") + " · " + codecLabel
  }

  visible: !(hideWhenDisconnected && !connected)
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh() {
    if (!statusProc.running) statusProc.running = true
    else refreshAgain.restart()
  }

  function run(args) {
    busy = true
    ctlProc.command = [root.binDir + "/ometalink-ctl"].concat(args).concat(root.address !== "" ? [root.address] : [])
    ctlProc.running = true
  }

  function open() { popupOpen = true; refresh() }
  function close() { popupOpen = false }
  function closeForPopoutSwitch() { close() }
  function togglePanel() { popupOpen ? close() : open() }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(root, direction)
    return false
  }

  Component.onCompleted: refresh()

  Process {
    id: statusProc
    command: [root.binDir + "/ometalink-status"].concat(root.address !== "" ? [root.address] : [])
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.state = JSON.parse(this.text) } catch (e) {}
      }
    }
  }

  Process {
    id: ctlProc
    onExited: {
      root.busy = false
      root.refresh()
    }
  }

  // BlueZ property changes (connect, disconnect, transport state) and
  // PipeWire sink events (volume, mute) trigger a debounced refresh, so the
  // poll timer only acts as a safety net.
  Process {
    running: true
    command: ["dbus-monitor", "--system", "type='signal',sender='org.bluez'"]
    stdout: SplitParser { onRead: refreshSoon.restart() }
  }

  Process {
    running: true
    command: ["pactl", "subscribe"]
    stdout: SplitParser {
      onRead: function(line) {
        if (line.indexOf("sink") !== -1 || line.indexOf("card") !== -1) refreshSoon.restart()
      }
    }
  }

  Timer { id: refreshSoon; interval: 400; onTriggered: root.refresh() }
  Timer { id: refreshAgain; interval: 300; onTriggered: root.refresh() }
  Timer { interval: root.pollSeconds * 1000; running: true; repeat: true; onTriggered: root.refresh() }

  IpcHandler {
    target: "io.github.nestorfaeric.ometalink"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function refresh(): void { root.refresh() }
    function connect(): void { root.run(["connect"]) }
    function disconnect(): void { root.run(["disconnect"]) }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.connected ? root.glassesGlyph : root.glassesOffGlyph
    active: root.connected && root.state.playing === true
    tooltipText: root.deviceName + " · " + root.statusText
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) root.run(["toggle"])
      else root.togglePanel()
    }
    onWheelMoved: function(delta) {
      if (root.connected) root.run(["volume", delta > 0 ? "+5" : "-5"])
    }
  }

  component InfoRow: Item {
    property string label: ""
    property string value: ""
    property bool dim: false
    width: parent ? parent.width : 0
    implicitHeight: valueText.implicitHeight

    Text {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: parent.label
      textFormat: Text.PlainText
      color: Qt.darker(root.bar.foreground, 1.4)
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
    }

    Text {
      id: valueText
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: parent.value
      textFormat: Text.PlainText
      color: root.bar.foreground
      opacity: parent.dim ? 0.55 : 1
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
      font.bold: !parent.dim
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.popupOpen
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onActivateRequested: root.run(["toggle"])
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refresh()
      }

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.space(14)

        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

          Text {
            id: heroIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: button.text
            textFormat: Text.PlainText
            color: root.bar.foreground
            opacity: root.connected ? 1 : 0.5
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              width: parent.width
              text: root.deviceName
              textFormat: Text.PlainText
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              text: root.statusText.toUpperCase()
              textFormat: Text.PlainText
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
            }
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        PanelSectionHeader {
          text: "AUDIO"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        Column {
          width: parent.width
          spacing: Style.space(8)

          InfoRow { label: "Profile"; value: root.connected && root.state.profile ? String(root.state.profile).toUpperCase() : "—"; dim: !root.connected }
          InfoRow { label: "Codec"; value: root.connected ? root.codecLabel : "—"; dim: !root.connected }
          InfoRow { label: "Playback"; value: root.connected ? (root.state.playing ? "Playing" : "Idle") : "—"; dim: !root.connected }
          InfoRow { label: "Volume"; value: root.connected ? root.volumeLabel : "—"; dim: !root.connected }
          InfoRow { label: "Battery"; value: root.batteryLabel; dim: root.state.battery === null || root.state.battery === undefined }
        }

        PanelSeparator { foreground: root.bar.foreground }

        PanelSectionHeader {
          text: "NOT AVAILABLE ON LINUX"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        Column {
          width: parent.width
          spacing: Style.space(8)

          InfoRow { label: "Microphone"; value: "Meta AI app only"; dim: true }
          InfoRow { label: "Camera"; value: "Meta AI app only"; dim: true }
        }

        PanelSeparator { foreground: root.bar.foreground }

        Row {
          spacing: Style.spacing.md

          Button {
            text: root.connected ? "Disconnect" : "Connect"
            enabled: root.state.found === true && !root.busy
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            bordered: true
            onClicked: root.run([root.connected ? "disconnect" : "connect"])
          }

          Button {
            text: "Use as output"
            visible: root.connected
            enabled: !root.busy
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            bordered: true
            onClicked: root.run(["output"])
          }
        }
      }
    }
  }
}
