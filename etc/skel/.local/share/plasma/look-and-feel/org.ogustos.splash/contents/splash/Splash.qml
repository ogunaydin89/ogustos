import QtQuick

Rectangle {
    id: root
    color: "#94042B"
    property int stage

    Image {
        id: logo
        anchors.centerIn: parent
        width: 256
        height: 256
        source: "images/logo.png"
        smooth: true
        opacity: 0
        NumberAnimation on opacity { from: 0; to: 1; duration: 800; running: true }
    }
}
