import QtQuick 1.1

// One ship. Skin "blocks" = raw 8-bit: a row of flat squares.
// Other skins (e.g. drawn warships) can be added here later without touching the game logic.
Item {
    id: root
    property variant s: null           // { x, y, len, h }
    property int pitch: 40
    property int gap: 2
    property color color: "#E7FFCD"
    property bool burnt: false          // sunk: red cells with a black core
    property string skin: "blocks"
    property int len: s ? s.len : 0
    property bool h: s ? s.h : true

    x: s ? s.x * pitch : 0
    y: s ? s.y * pitch : 0
    width: (h ? len : 1) * pitch - gap
    height: (h ? 1 : len) * pitch - gap

    Repeater {
        model: root.skin == "blocks" ? root.len : 0
        Rectangle {
            x: root.h ? index * root.pitch : 0
            y: root.h ? 0 : index * root.pitch
            width: root.pitch - root.gap
            height: root.pitch - root.gap
            color: root.burnt ? "#ff7a6a" : root.color
            smooth: false
            Rectangle {
                visible: root.burnt
                anchors.centerIn: parent
                width: Math.round(parent.width / 3); height: width
                color: "#0c120a"
            }
        }
    }
}
