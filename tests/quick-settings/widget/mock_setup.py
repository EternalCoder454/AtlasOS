#!/usr/bin/python3
# Populates the dbusmock services on the private system bus. scene: laptop | desktop
import sys, dbus
scene = sys.argv[1] if len(sys.argv) > 1 else "laptop"
bus = dbus.SystemBus()
def mock(name, path, iface="org.freedesktop.DBus.Mock"):
    return dbus.Interface(bus.get_object(name, path), iface)

# --- UPower: a laptop battery (not on the desktop scene)
if scene == "laptop":
    up = mock("org.freedesktop.UPower", "/org/freedesktop/UPower")
    up.AddAC("mock_AC", "Mock AC")
    up.AddDischargingBattery("mock_BAT", "Mock Battery", 87.0, 11500)

# --- power-profiles-daemon: default balanced (all three profiles)
# nothing to do: the template starts with the three profiles

# --- NetworkManager
nm = mock("org.freedesktop.NetworkManager", "/org/freedesktop/NetworkManager")
if scene == "desktop":
    # a desktop with a cable: no Wi-Fi adapter, no Bluetooth, no battery
    eth = nm.AddEthernetDevice("mock_eth0", "eth0", 100)
else:
    wifi = nm.AddWiFiDevice("mock_wlan0", "wlan0", 100)
    aps = [
        ("Telamon Home", "AA:BB:CC:00:00:01", 80, 0x100),   # WPA-PSK
        ("Cafe Guest", "AA:BB:CC:00:00:02", 55, 0),         # open
        ("Neighbour 5G", "AA:BB:CC:00:00:03", 30, 0x100),
        ("Office Corp", "AA:BB:CC:00:00:04", 65, 0x200),    # 802.1X
    ]
    ap0 = None
    for i, (ssid, hw, strength, sec) in enumerate(aps):
        p = nm.AddAccessPoint(wifi, "AP%d" % i, ssid, hw, 2, 2412 + 5 * i, 54000, strength, sec)
        ap0 = ap0 or p
        # NM derives the security type from the AP's Wpa/Rsn flags, not from the mock's single "security" number
        rsn = {0x100: 0x188, 0x200: 0x288}.get(sec, 0)
        nm.SetProperty(p, "org.freedesktop.NetworkManager.AccessPoint", "RsnFlags", dbus.UInt32(rsn))
        nm.SetProperty(p, "org.freedesktop.NetworkManager.AccessPoint", "Flags", dbus.UInt32(1 if sec else 0))
    conn = nm.AddWiFiConnection(wifi, "TelamonHome", "Telamon Home", "wpa-psk")
    ac = nm.AddActiveConnection([wifi], conn, ap0, "TelamonHome", 2)
    nm.SetDeviceActive(wifi, ac)

# --- BlueZ: an adapter and two paired devices (none on the desktop scene)
if scene != "desktop":
    bz = mock("org.bluez", "/org/bluez", "org.bluez.Mock")
    bz.AddAdapter("hci0", "telamon-pc")
    # the template has no ProfileManager1, which BluezQt's manager wants before it counts as operational
    obj = dbus.Interface(bus.get_object("org.bluez", "/org/bluez"), "org.freedesktop.DBus.Mock")
    obj.AddMethods("org.bluez.ProfileManager1", [("RegisterProfile", "osa{sv}", "", "pass"), ("UnregisterProfile", "o", "", "pass")])
    obj.AddProperty("org.bluez.ProfileManager1", "Mock", dbus.String("x"))
    bz.AddDevice("hci0", "11:22:33:44:55:66", "WH-1000XM5")
    bz.AddDevice("hci0", "11:22:33:44:55:77", "MX Keys")
    bz.PairDevice("hci0", "11:22:33:44:55:66")
    bz.PairDevice("hci0", "11:22:33:44:55:77")
print("mocks ready", scene)
