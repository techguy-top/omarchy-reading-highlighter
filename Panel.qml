import QtQuick
import QtQuick.Dialogs as Dialogs
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import qs.Ui as Ui
import "."

Ui.Panel {
  id: root
  moduleName: "diky.reading-highlighter"
  ipcTarget: "diky.reading-highlighter"
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
  Dialogs.FolderDialog {
    id: folderDialog
    title: strings.t("chooseFolder")
    currentFolder: "file://" + TrailState.destination.substring(0, TrailState.destination.lastIndexOf("/"))
    onAccepted: {
      var folder = decodeURIComponent(String(selectedFolder).replace(/^file:\/\//, ""))
      fileField.text = folder.replace(/\/$/, "") + "/Reading Highlights.md"
      TrailState.saveSettings(fileField.text, appField.value, autoField.checked)
      root.open()
    }
    onRejected: root.open()
  }
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: TrailState.captureBusy ? "󰈙" : "󰇥"
    tooltipText: strings.t("tooltip")
    foreground: TrailState.active || TrailState.captureBusy ? TrailState.ink : root.barForeground
    onPressed: b => { if (b === Qt.RightButton) TrailState.toggleActive(); else root.toggle() }
  }
  KeyboardPanel {
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: 390
    contentHeight: fittedContentHeight(column.implicitHeight)
    Flickable {
      anchors.fill: parent
      contentHeight: column.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      Column {
        id: column
        width: parent.width
        spacing: 12
        PlainText { text: strings.t("title"); font.pixelSize: 20; font.bold: true }
        Row {
          spacing: 12
          ToggleSwitch { checked: TrailState.active; accent: TrailState.ink; onToggled: TrailState.toggleActive() }
          PlainText { text: strings.t("trail"); font.pixelSize: 16; anchors.verticalCenter: parent.verticalCenter }
        }
        Row {
          spacing: 8
          Repeater {
            model: ["Orange", "Green", "Red"]
            Button {
              required property string modelData
              text: strings.t(modelData)
              selected: TrailState.colorName === modelData
              bordered: true
              foreground: modelData === "Orange" ? "#ffab40" : modelData === "Green" ? "#59e36b" : "#ff6262"
              onClicked: TrailState.chooseColor(modelData)
            }
          }
        }
        PlainText { text: strings.t("capture"); font.pixelSize: 17; font.bold: true }
        PlainText { width: parent.width; text: strings.t("help"); opacity: 0.85 }
        PlainText { text: strings.t("file") }
        TextField {
          id: fileField
          width: parent.width
          text: TrailState.destination
          placeholderText: "~/Documents/Reading Highlights.md"
          enabled: !TrailState.captureBusy
        }
        Row {
          spacing: 8
          Button {
            text: strings.t("chooseFolder"); bordered: true
            enabled: TrailState.backendReady && !TrailState.captureBusy
            onClicked: { root.close(); Qt.callLater(function() { folderDialog.open() }) }
          }
          Button {
            text: strings.t("openFolder"); bordered: true
            enabled: TrailState.backendReady && !TrailState.captureBusy
            onClicked: TrailState.openFolder()
          }
        }
        PlainText { width: parent.width; text: strings.t("fileHelp"); opacity: 0.7; font.pixelSize: 12 }
        PlainText { width: parent.width; text: strings.t("actualDestination", "Currently saving to:\n%1").arg(TrailState.destination); font.pixelSize: 12; wrapMode: Text.WrapAnywhere }
        Dropdown {
          id: appField
          width: parent.width
          label: strings.t("app")
          value: TrailState.selectedApp
          options: TrailState.appOptions.map(o => ({value:o.value, label:o.value === "" ? strings.t("app.default") : root.safeLabel(o.label)}))
          enabled: !TrailState.captureBusy
          onChanged: value => { appField.value = value }
        }
        Row {
          spacing: 10
          ToggleSwitch { id: autoField; checked: TrailState.autoOpen; onToggled: checked = !checked }
          PlainText { text: strings.t("autoOpen"); anchors.verticalCenter: parent.verticalCenter }
        }
        Row {
          spacing: 8
          Button {
            text: strings.t("apply"); bordered: true
            enabled: TrailState.backendReady && !TrailState.captureBusy
            onClicked: TrailState.saveSettings(fileField.text, appField.value, autoField.checked)
          }
          Button { text: strings.t("open"); bordered: true; enabled: TrailState.backendReady && !TrailState.captureBusy; onClicked: TrailState.openNotes() }
        }
        PlainText {
          width: parent.width
          text: TrailState.preparing ? strings.t("preparing") : TrailState.capturing ? strings.t("capturing") : TrailState.processing ? strings.t("processing") : TrailState.saved ? strings.t("saved") : strings.t("ready")
          color: TrailState.saved ? "#59e36b" : Color.foreground
        }
        Button { visible: TrailState.preparing || TrailState.capturing; text: strings.t("cancel"); onClicked: TrailState.cancelCapture() }
        PlainText { visible: TrailState.settingsState === "saved"; text: strings.t("settingsSaved"); opacity: 0.7 }
        PlainText { visible: TrailState.lastPreview !== ""; width: parent.width; text: TrailState.lastPreview; maximumLineCount: 4; elide: Text.ElideRight }
        PlainText { visible: TrailState.error !== ""; text: TrailState.error; width: parent.width; color: "#ff6262" }
        PlainText { width: parent.width; text: strings.t("limitation"); opacity: 0.65; font.pixelSize: 12 }
      }
    }
  }
  // Dropdown's labels are Omarchy-owned Text elements. Neutralize markup at that boundary.
  function safeLabel(value) { return String(value).replace(/&/g, "＆").replace(/</g, "＜").replace(/>/g, "＞") }
}
