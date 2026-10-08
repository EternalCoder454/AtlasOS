/*
    SPDX-FileCopyrightText: 2026 Telamon OS
    SPDX-License-Identifier: Apache-2.0

    One app playing sound: its name, mute, volume and the output device its
    stream goes to. `stream` is the row of plasma-pa's stream model, so
    assigning Volume, Muted or DeviceIndex on it changes the stream (a new
    DeviceIndex moves it to that output, and PulseAudio remembers the choice
    for the app).
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import org.kde.plasma.private.volume

ColumnLayout {
    id: item

    property var stream
    property var devices

    readonly property string appName: {
        const client = stream.Client;
        if (client && client.name && client.name !== "pipewire-media-session") {
            return client.name;
        }
        return stream.Name || i18n("Unnamed app");
    }
    // What it plays, when the app says (not "playback", "audio stream"...)
    readonly property string mediaName: {
        const name = stream.Properties ? stream.Properties["media.name"] : "";
        return name && !/playback|audio|stream|alsa|pulse|pipewire/i.test(name) ? name : "";
    }
    readonly property int percent: Math.round(stream.Volume / PulseAudio.NormalVolume * 100)

    spacing: Kirigami.Units.smallSpacing

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing * 2
        Kirigami.Icon {
            source: stream.IconName || "applications-multimedia-symbolic"
            implicitWidth: Kirigami.Units.iconSizes.smallMedium
            implicitHeight: implicitWidth
            Accessible.ignored: true
        }
        PC3.Label {
            Layout.fillWidth: true
            text: item.mediaName ? i18nc("app name · what it plays", "%1 · %2", item.appName, item.mediaName) : item.appName
            textFormat: Text.PlainText
            elide: Text.ElideRight
            font.weight: Font.DemiBold
        }
        PC3.Label {
            visible: stream.Corked === true
            text: i18n("Paused")
            opacity: 0.7
        }
    }

    ValueRow {
        Layout.fillWidth: true
        label: i18n("Volume of %1", item.appName)
        iconName: item.percent === 0 || stream.Muted ? "audio-volume-muted-symbolic" : "audio-volume-high-symbolic"
        canMute: true
        muted: stream.Muted
        from: PulseAudio.MinimalVolume
        to: Math.max(PulseAudio.NormalVolume, stream.Volume)
        stepSize: PulseAudio.NormalVolume / 100
        value: stream.Volume
        valueText: item.percent + " %"
        sliderEnabled: stream.VolumeWritable !== false
        onMoved: v => {
            stream.Volume = v;
            stream.Muted = v === 0;
        }
        onMuteToggled: stream.Muted = !stream.Muted
    }

    // Only when there is another output to choose
    RowLayout {
        Layout.fillWidth: true
        visible: item.devices && item.devices.count > 1
        spacing: Kirigami.Units.smallSpacing
        PC3.Label {
            text: i18n("Output")
            opacity: 0.7
        }
        PC3.ComboBox {
            id: picker
            Layout.fillWidth: true
            model: item.devices
            textRole: "Description"
            valueRole: "Index"
            Accessible.name: i18n("Output device of %1", item.appName)
            currentIndex: indexOfValue(stream.DeviceIndex)
            onActivated: stream.DeviceIndex = currentValue
            onCountChanged: currentIndex = Qt.binding(() => indexOfValue(stream.DeviceIndex))
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        Layout.preferredHeight: 1
        color: Qt.alpha(Kirigami.Theme.textColor, 0.1)
    }
}
