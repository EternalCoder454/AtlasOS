/*
    SPDX-FileCopyrightText: 2026 Telamon OS
    SPDX-License-Identifier: Apache-2.0

    Sound: the output's volume and mute on top; folded, the output device
    and the apps playing sound, each with its own volume, mute and output
    device (moving its stream, as Plasma's volume widget does with a drag).
    The models are plasma-pa's.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import org.kde.kitemmodels as KItemModels
import org.kde.plasma.private.volume

Card {
    id: card

    readonly property var sink: Server.defaultSink
    readonly property bool ready: Context.state === Context.State.Ready
    readonly property bool hasSink: ready && sink !== null && sink !== undefined && sink.name !== "auto_null"
    readonly property int percent: hasSink ? Math.round(sink.volume / PulseAudio.NormalVolume * 100) : 0

    iconName: hasSink ? AudioIcon.forVolume(percent, sink.muted, "") + "-symbolic" : "audio-volume-muted-symbolic"
    title: i18n("Sound")
    subtitle: {
        if (!ready) {
            return i18n("Sound service not running");
        }
        if (!hasSink) {
            return i18n("No output device");
        }
        const name = sink.description || sink.name;
        return apps.count > 0 ? i18np("%2 · %1 app playing", "%2 · %1 apps playing", apps.count, name) : name;
    }
    settingsLabel: i18n("Open Sound settings")
    hasDetails: hasSink

    // Output devices, without the dummy one and plasma-pa's virtual ones
    SinkModel { id: sinkModel }
    PulseObjectFilterModel {
        id: sinks
        sourceModel: sinkModel
        filterOutInactiveDevices: true
        filterVirtualDevices: true
    }
    // Apps playing sound: non-virtual streams, without libcanberra's event sounds
    SinkInputModel { id: inputModel }
    PulseObjectFilterModel {
        id: apps
        sourceModel: inputModel
        filters: [
            { role: "VirtualStream", value: false },
            { role: "Client", value: client => !client || client.name !== "libcanberra" }
        ]
    }

    function sinkAt(row) {
        return sinks.data(sinks.index(row, 0), sinks.KItemModels.KRoleNames.role("PulseObject"));
    }

    ValueRow {
        Layout.fillWidth: true
        visible: card.hasSink
        label: card.hasSink ? i18n("Volume of %1", card.sink.description || card.sink.name) : i18n("Volume")
        iconName: card.iconName
        canMute: true
        muted: card.hasSink && card.sink.muted
        from: PulseAudio.MinimalVolume
        to: card.hasSink ? Math.max(PulseAudio.NormalVolume, card.sink.volume) : PulseAudio.NormalVolume
        stepSize: PulseAudio.NormalVolume / 100
        value: card.hasSink ? card.sink.volume : 0
        valueText: card.percent + " %"
        onMoved: v => {
            card.sink.volume = v;
            card.sink.muted = v === 0;
        }
        onMuteToggled: card.sink.muted = !card.sink.muted
    }

    details: [
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PC3.Label {
                text: i18n("Output device")
                font: Kirigami.Theme.smallFont
                opacity: 0.7
            }
            PC3.ComboBox {
                id: outputPicker
                Layout.fillWidth: true
                model: sinks
                textRole: "Description"
                valueRole: "Index"
                enabled: count > 0
                Accessible.name: i18n("Output device")
                currentIndex: card.hasSink ? indexOfValue(card.sink.index) : -1
                onActivated: index => {
                    const target = card.sinkAt(index);
                    if (target) {
                        target.default = true;
                    }
                }
                // The sink list changes after the box is built
                onCountChanged: currentIndex = Qt.binding(() => card.hasSink ? indexOfValue(card.sink.index) : -1)
            }

            PC3.Label {
                Layout.topMargin: Kirigami.Units.smallSpacing
                text: i18n("Apps")
                font: Kirigami.Theme.smallFont
                opacity: 0.7
            }
            PC3.Label {
                Layout.fillWidth: true
                visible: apps.count === 0
                text: i18n("No app is playing sound.")
                wrapMode: Text.Wrap
            }

            Repeater {
                model: apps
                delegate: AppStream {
                    required property var model
                    stream: model
                    devices: sinks
                    Layout.fillWidth: true
                }
            }
        }
    ]
}
