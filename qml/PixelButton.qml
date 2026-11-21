import QtQuick 1.1

// Raw 8-bit button: flat frame, pixel text, inverts while pressed.
Item {
    id: root
    property alias text: label.text
    property int pixelSize: 4
    property color color: "#E7FFCD"
    property color fill: "#0c120a"
    property bool enabled: true
    signal clicked

    width: 400
    height: label.height + 28
    opacity: enabled ? 1 : 0.35

    Rectangle {
        anchors.fill: parent
        color: mouse.pressed ? root.color : root.fill
        border.width: 4
        border.color: root.color
        smooth: false
    }
    PixelText {
        id: label
        anchors.centerIn: parent
        pixelSize: root.pixelSize
        align: 1
        color: mouse.pressed ? root.fill : root.color
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: root.enabled
        onClicked: root.clicked()
    }
}
