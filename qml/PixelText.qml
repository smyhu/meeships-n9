import QtQuick 1.1
import "pixelfont.js" as PF

// Chunky 8-bit text drawn from square pixels (pixelfont.js). Shared by the MeeGames.
// API: text, pixelSize (size of one font pixel), color, align (0 left, 1 centre, 2 right).
Item {
    id: root
    property string text: ""
    property int pixelSize: 4
    property color color: "#E7FFCD"
    property int align: 0

    property variant _cells: PF.layout(text, align)

    width: PF.columns(text) * pixelSize
    height: PF.rows(text) * pixelSize

    Repeater {
        model: root._cells.length
        Rectangle {
            property int c: root._cells[index]
            x: Math.floor(c / 1024) * root.pixelSize
            y: (c % 1024) * root.pixelSize
            width: root.pixelSize
            height: root.pixelSize
            color: root.color
            smooth: false
        }
    }
}
