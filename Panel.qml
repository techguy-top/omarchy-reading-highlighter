import QtQuick
import qs.Commons
import qs.Ui
import "."

Panel {
  id: root
  moduleName: "diky.reading-highlighter"
  ipcTarget: "diky.reading-highlighter"
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰇥"
    tooltipText: "Reading Highlighter — " + (TrailState.active ? "On" : "Off") + ""
    foreground: TrailState.active ? TrailState.ink : root.barForeground
    onPressed: b => { if (b === Qt.RightButton) TrailState.toggleActive(); else root.toggle() }
  }
  PopupCard {
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: 310
    contentHeight: fittedContentHeight(column.implicitHeight)
    Column {
      id: column
      width: parent.width
      spacing: 16
      Text { text: "Reading Highlighter"; color: Color.foreground; font.pixelSize: 20; font.bold: true }
      Row {
        spacing: 16
        ToggleSwitch { checked: TrailState.active; accent: TrailState.ink; onToggled: TrailState.toggleActive() }
        Text { text: TrailState.active ? "On" : "Off"; color: Color.foreground; font.pixelSize: 17; anchors.verticalCenter: parent.verticalCenter }
      }
      Row {
        spacing: 8
        Repeater {
          model: ["Orange", "Green", "Red"]
          Button {
            required property string modelData
            text: modelData
            selected: TrailState.colorName === modelData
            bordered: true
            foreground: modelData === "Orange" ? "#ffab40" : modelData === "Green" ? "#59e36b" : "#ff6262"
            onClicked: TrailState.chooseColor(modelData)
          }
        }
      }
      Text {
        width: parent.width
        text: "Move your pointer to highlight.\nAbout 1 inch • fades in 3 seconds\n\nOptional shortcut: Super + Shift + H\nSee README for setup\nRight-click the bar icon: on / off"
        color: Color.foreground
        opacity: 0.8
        font.pixelSize: 13
        wrapMode: Text.WordWrap
      }
      Text { visible: TrailState.error !== ""; text: TrailState.error; width: parent.width; wrapMode: Text.WordWrap; color: "#ff6262" }
    }
  }
}
