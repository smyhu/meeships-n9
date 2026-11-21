import QtQuick 1.1

// 10 x 10 sea. marks[i]: 0 water, 1 miss, 2 hit, 3 water next to a sunk ship.
Rectangle {
    id: b
    property int pitch: 40
    property int gap: 2
    property int pad: 4
    property variant marks: []
    property variant ships: []        // afloat ships to show (own fleet / revealed enemy)
    property variant sunk: []         // sunk ships
    property int aim: -1              // cell being fired at (blinks)
    property bool aimOn: true
    property variant ghost: null      // setup: ship that does not fit here (red)
    property string skin: "blocks"
    property bool active: true
    signal tapped(int i)

    width: pitch * 10 - gap + 2 * pad
    height: width
    color: "#0c120a"
    border.width: 2
    border.color: "#5f7f45"

    function hitsOf(m) {
        var out = []
        if (!m) return out
        for (var i = 0; i < m.length; i++) if (m[i] == 2) out.push(i)
        return out
    }
    property variant _hits: hitsOf(marks)

    Item {
        x: b.pad; y: b.pad
        width: b.pitch * 10; height: width
        Repeater {
            model: 100
            Rectangle {
                property int mk: b.marks.length == 100 ? b.marks[index] : 0
                x: (index % 10) * b.pitch
                y: Math.floor(index / 10) * b.pitch
                width: b.pitch - b.gap; height: width
                color: "#162513"
                smooth: false
                Rectangle {
                    visible: parent.mk == 1 || parent.mk == 3
                    anchors.centerIn: parent
                    width: parent.mk == 1 ? Math.round(b.pitch / 4) : Math.round(b.pitch / 8)
                    height: width
                    color: parent.mk == 1 ? "#9cc575" : "#3d5c2e"
                }
            }
        }
        Repeater {
            model: b.ships
            ShipBlock { s: modelData; pitch: b.pitch; gap: b.gap; skin: b.skin }
        }
        Repeater {
            model: b._hits
            Rectangle {
                x: (modelData % 10) * b.pitch
                y: Math.floor(modelData / 10) * b.pitch
                width: b.pitch - b.gap; height: width
                color: "#ff7a6a"
            }
        }
        Repeater {
            model: b.sunk
            ShipBlock { s: modelData; pitch: b.pitch; gap: b.gap; burnt: true; skin: b.skin }
        }
        ShipBlock {
            s: b.ghost; visible: b.ghost != null; pitch: b.pitch; gap: b.gap
            color: "#ff7a6a"; opacity: 0.7; skin: b.skin
        }
        Rectangle {
            visible: b.aim >= 0 && b.aimOn
            x: (b.aim % 10) * b.pitch - 2
            y: Math.floor(b.aim / 10) * b.pitch - 2
            width: b.pitch - b.gap + 4; height: width
            color: "transparent"
            border.width: Math.max(2, Math.round(b.pitch / 10)); border.color: "#f0d860"
        }
    }
    MouseArea {
        anchors.fill: parent
        enabled: b.active
        onClicked: {
            var cx = Math.floor((mouse.x - b.pad) / b.pitch), cy = Math.floor((mouse.y - b.pad) / b.pitch)
            if (cx >= 0 && cy >= 0 && cx < 10 && cy < 10) b.tapped(cy * 10 + cx)
        }
    }
}
