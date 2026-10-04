import QtQuick 2.12
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.components 1.0 as KirigamiComponents
import org.kde.kcmutils as KCM

Item {

    readonly property color borderGradientColor1: plasmoid.configuration.glowColor == 0 ? "#6252DD" : // AtlasOS violets
                                                plasmoid.configuration.glowColor == 1 ? "#a5fecb" :
                                                "#ff005d"
    readonly property color borderGradientColor2: plasmoid.configuration.glowColor == 0 ? "#9C8CF8" :
                                                plasmoid.configuration.glowColor == 1 ? "#20bdff" :
                                                "#ff005c"
    readonly property color borderGradientColor3: plasmoid.configuration.glowColor == 0 ? "#C3B8FF" :
                                                plasmoid.configuration.glowColor == 1 ? "#5433ff" :
                                                "#ff8b26"

    KirigamiComponents.AvatarButton {
        id: mainFaceIcon
        source: kuser.faceIconUrl
        anchors {
            fill: parent
            margins: 0
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: false
            onClicked: {
            KCM.KCMLauncher.openSystemSettings("kcm_users")
            root.toggle()
            }
        }
    }

    Rectangle {
        visible: plasmoid.configuration.enableGlow
        anchors.centerIn: mainFaceIcon
        width: parent.width - 4 // Subtract to prevent fringing
        height: width
        radius: width / 2
        
        gradient: Gradient {
            GradientStop { position: 0.0; color: borderGradientColor1 }
            GradientStop { position: 0.33; color: borderGradientColor2 }
            GradientStop { position: 1.0; color: borderGradientColor3 }
        }

        z:-1
        rotation: 270
        transformOrigin: Item.Center
    }
}