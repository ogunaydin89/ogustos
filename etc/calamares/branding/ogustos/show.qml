import QtQuick 2.0;
import calamares.slideshow 1.0;

Presentation
{
    id: presentation

    Slide {
        Rectangle {
            anchors.fill: parent
            color: "#121316"

            Column {
                anchors.centerIn: parent
                spacing: 18

                Image {
                    anchors.horizontalCenter: parent.horizontalCenter
                    source: "ogustos-logo.svg"
                    width: 128
                    height: 128
                    fillMode: Image.PreserveAspectFit
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Installing ogustOS KDE..."
                    color: "#ECEFF4"
                    font.pixelSize: 24
                    font.bold: true
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Linux 7.3-ogustOS (Clang ThinLTO + BORE + BBRv3)  •  KDE Plasma 6 Wayland"
                    color: "#FCB514"
                    font.pixelSize: 15
                }
            }
        }
    }
}
