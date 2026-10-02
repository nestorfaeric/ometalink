#!/usr/bin/env python3
"""Minimal HFP Audio Gateway probe: answers the SLC handshake with service=1
and logs whether the headset keeps the RFCOMM link up."""
import os, socket, sys, time
import dbus, dbus.service, dbus.mainloop.glib
from gi.repository import GLib

HFP_AG = "0000111f-0000-1000-8000-00805f9b34fb"
SERVICE = int(sys.argv[1]) if len(sys.argv) > 1 else 1
T0 = time.time()

def log(*a):
    print(f"{time.time()-T0:7.3f}", *a, flush=True)

class Profile(dbus.service.Object):
    @dbus.service.method("org.bluez.Profile1", in_signature="", out_signature="")
    def Release(self): log("Release")

    @dbus.service.method("org.bluez.Profile1", in_signature="oha{sv}", out_signature="")
    def NewConnection(self, path, fd, props):
        fd = fd.take()
        log("NewConnection", path, dict(props))
        sock = socket.socket(fileno=fd)
        sock.setblocking(False)
        buf = b""
        def send(s):
            log(">>", s)
            sock.send(b"\r\n" + s.encode() + b"\r\n")
        def on_data(*_):
            nonlocal buf
            try:
                data = sock.recv(1024)
            except BlockingIOError:
                return True
            if not data:
                log("LINK CLOSED by peer")
                return False
            buf += data
            while b"\r" in buf:
                line, buf = buf.split(b"\r", 1)
                cmd = line.strip().decode(errors="replace")
                if not cmd: continue
                log("<<", cmd)
                if cmd.startswith("AT+BRSF="): send("+BRSF: 512"); send("OK")
                elif cmd == "AT+CIND=?":
                    send('+CIND: ("service",(0-1)),("call",(0,1)),("callsetup",(0-3)),("callheld",(0-2)),("signal",(0-5)),("roam",(0,1)),("battchg",(0-5))'); send("OK")
                elif cmd == "AT+CIND?": send(f"+CIND: {SERVICE},0,0,0,{5 if SERVICE else 0},0,5"); send("OK")
                elif cmd == "AT+CHLD=?": send("+CHLD: (0,1,2,3)"); send("OK")
                elif cmd.startswith("AT+XAPL="): send("+XAPL=iPhone,2"); send("OK")
                elif cmd.startswith("AT+IPHONEACCEV") or cmd.startswith("AT+BIEV") or cmd.startswith("AT+XEVENT"):
                    log("  ^^^ battery/accessory event"); send("OK")
                elif cmd.startswith("AT+BIND=?"): send("+BIND: (1,2)"); send("OK")
                elif cmd.startswith("AT+BIND?"): send("+BIND: 1,1"); send("+BIND: 2,1"); send("OK")
                else: send("OK")
            return True
        GLib.io_add_watch(sock.fileno(), GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR, on_data)
        self._sock = sock

    @dbus.service.method("org.bluez.Profile1", in_signature="o", out_signature="")
    def RequestDisconnection(self, path): log("RequestDisconnection", path)

dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
bus = dbus.SystemBus()
prof = Profile(bus, "/ometalink/probe")
mgr = dbus.Interface(bus.get_object("org.bluez", "/org/bluez"), "org.bluez.ProfileManager1")
mgr.RegisterProfile("/ometalink/probe", HFP_AG, {"Name": "OmetaLink probe", "Role": "server", "Channel": dbus.UInt16(13), "Features": dbus.UInt16(0x200)})
log("registered HFP AG probe, service =", SERVICE)
GLib.timeout_add_seconds(int(os.environ.get("PROBE_SECS", "25")), lambda: (log("timeout"), loop.quit()))
loop = GLib.MainLoop()
loop.run()
