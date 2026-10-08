/*
    SPDX-FileCopyrightText: 2026 Telamon OS
    SPDX-License-Identifier: Apache-2.0

    What Quick Settings knows about sound: the default output, the output
    devices and the apps playing, from plasma-pa. Nothing is drawn here.
*/

import QtQuick
import org.kde.kitemmodels as KItemModels
import org.kde.plasma.private.volume

Item {
    id: self
    visible: false

    // Server.defaultSink, not PreferredDevice.sink: that one is only updated
    // when the default changes, so it is empty if first asked for later
    readonly property var sink: Server.defaultSink
    readonly property bool ready: Context.state === Context.State.Ready
    readonly property bool hasSink: ready && sink !== null && sink !== undefined && sink.name !== "auto_null"
    readonly property bool muted: hasSink && sink.muted
    readonly property int percent: hasSink ? Math.round(sink.volume / PulseAudio.NormalVolume * 100) : 0
    readonly property string deviceName: hasSink ? (sink.description || sink.name) : ""
    readonly property string iconName: hasSink ? AudioIcon.forVolume(percent, sink.muted, "") + "-symbolic" : "audio-volume-muted-symbolic"
    readonly property alias sinks: sinks
    readonly property alias apps: apps

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

    function setVolume(volume) {
        if (hasSink) {
            sink.volume = volume;
            sink.muted = volume === 0;
        }
    }
    function toggleMute() {
        if (hasSink) {
            sink.muted = !sink.muted;
        }
    }
    function sinkAt(row) {
        return sinks.data(sinks.index(row, 0), sinks.KItemModels.KRoleNames.role("PulseObject"));
    }
    // Make the output in this row of `sinks` the default
    function useOutput(row) {
        const target = sinkAt(row);
        if (target) {
            target.default = true;
        }
    }
}
