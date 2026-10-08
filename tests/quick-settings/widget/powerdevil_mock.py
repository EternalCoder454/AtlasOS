#!/usr/bin/python3
# Session bus: PowerDevil as the Plasma widgets see it: org.kde.ScreenBrightness (two displays; writes go to
# /tmp/brightness.log) and org.kde.Solid.PowerManagement (remaining battery time, power profiles; /tmp/profile.log).
import dbus, dbus.service, dbus.mainloop.glib
from gi.repository import GLib
dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
name = dbus.service.BusName("org.kde.ScreenBrightness", bus)
import os
state = {} if os.environ.get("MOCK_SCENE") == "desktop" else {"display0": [70, 100, "Built-in display", True], "display1": [40, 100, "Dell U2723QE", False]}
class Display(dbus.service.Object):
    def __init__(self, key):
        self.key = key
        super().__init__(bus, "/org/kde/ScreenBrightness/" + key)
    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="ss", out_signature="v")
    def Get(self, iface, prop): return self.GetAll(iface)[prop]
    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="s", out_signature="a{sv}")
    def GetAll(self, iface):
        b, m, l, i = state[self.key]
        return {"Brightness": dbus.Int32(b), "MaxBrightness": dbus.Int32(m), "Label": l, "IsInternal": dbus.Boolean(i)}
    @dbus.service.method("org.kde.ScreenBrightness.Display", in_signature="iu", out_signature="")
    def SetBrightness(self, v, flags):
        open("/tmp/brightness.log", "a").write("%s=%d\n" % (self.key, v))
        state[self.key][0] = int(v)
        self.BrightnessChanged(int(v), "", "")
    @dbus.service.method("org.kde.ScreenBrightness.Display", in_signature="ius", out_signature="")
    def SetBrightnessWithContext(self, v, flags, ctx): self.SetBrightness(v, flags)
    @dbus.service.signal("org.kde.ScreenBrightness.Display", signature="iss")
    def BrightnessChanged(self, v, a, b): pass
    @dbus.service.signal("org.kde.ScreenBrightness.Display", signature="ii")
    def BrightnessRangeChanged(self, m, v): pass
class Root(dbus.service.Object):
    def __init__(self):
        super().__init__(bus, "/org/kde/ScreenBrightness")
    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="ss", out_signature="v")
    def Get(self, iface, prop): return self.GetAll(iface)[prop]
    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="s", out_signature="a{sv}")
    def GetAll(self, iface): return {"DisplaysDBusNames": dbus.Array(list(state), signature="s")}
    @dbus.service.signal("org.kde.ScreenBrightness", signature="s")
    def DisplayAdded(self, n): pass
    @dbus.service.signal("org.kde.ScreenBrightness", signature="s")
    def DisplayRemoved(self, n): pass
d = [Display(k) for k in state]
Root()
pm_name = dbus.service.BusName("org.kde.Solid.PowerManagement", bus)
class PM(dbus.service.Object):
    def __init__(self): super().__init__(bus, "/org/kde/Solid/PowerManagement")
    I = "org.kde.Solid.PowerManagement"
    @dbus.service.method(I, out_signature="t")
    def batteryRemainingTime(self): return dbus.UInt64(11500000)
    @dbus.service.method(I, out_signature="t")
    def smoothedBatteryRemainingTime(self): return dbus.UInt64(11500000)
    @dbus.service.method(I, out_signature="i")
    def chargeStopThreshold(self): return dbus.Int32(100)
class Profiles(dbus.service.Object):
    I = "org.kde.Solid.PowerManagement.Actions.PowerProfile"
    cur = "balanced"
    def __init__(self): super().__init__(bus, "/org/kde/Solid/PowerManagement/Actions/PowerProfile")
    @dbus.service.method(I, out_signature="as")
    def profileChoices(self): return dbus.Array(["power-saver", "balanced", "performance"], signature="s")
    @dbus.service.method(I, out_signature="s")
    def configuredProfile(self): return "balanced"
    @dbus.service.method(I, out_signature="s")
    def currentProfile(self): return self.cur
    @dbus.service.method(I, out_signature="s")
    def performanceInhibitedReason(self): return ""
    @dbus.service.method(I, out_signature="s")
    def performanceDegradedReason(self): return ""
    @dbus.service.method(I, out_signature="aa{sv}")
    def profileHolds(self): return dbus.Array([], signature="a{sv}")
    @dbus.service.method(I, in_signature="s")
    def setProfile(self, p):
        open("/tmp/profile.log", "a").write(p + "\n")
        Profiles.cur = str(p)
        self.currentProfileChanged(str(p))
    @dbus.service.signal(I, signature="s")
    def currentProfileChanged(self, p): pass
PM(); Profiles()
GLib.MainLoop().run()
