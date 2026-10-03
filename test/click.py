#!/usr/bin/env python3
"""Clicks the middle of the game window once, or holds keys (X11 XTest, no packages needed).
The "click to start" screen after loading has no Lua or command line way around it
(GameLoadingState only checks Mouse.isButtonDown), so run.sh clicks it. Driving has no Lua
way either (CarController reads the real keyboard), so the test asks run.sh to hold W / S.
Usage: click.py <game pid>                    click, puts the pointer back where it was
       click.py <game pid> keys <key> <ms> ...  hold each key for ms, one after the other"""
import ctypes
import ctypes.util
import sys
import time

pid = int(sys.argv[1])
keys = []
if len(sys.argv) > 2 and sys.argv[2] == "keys":
    rest = sys.argv[3:]
    keys = [(rest[i], int(rest[i + 1])) for i in range(0, len(rest) - 1, 2)]


# never click while the desktop is locked: the click would land on the lock screen
def screen_locked():
    import subprocess
    try:
        out = subprocess.run(["gdbus", "call", "--session", "--dest", "org.gnome.ScreenSaver",
                              "--object-path", "/org/gnome/ScreenSaver",
                              "--method", "org.gnome.ScreenSaver.GetActive"],
                             capture_output=True, text=True, timeout=5).stdout
    except Exception:
        return True  # can't tell: don't click
    return "true" in out


if screen_locked():
    sys.exit("screen locked (or lock state unknown), not clicking: unlock it, the run waits")
x11 = ctypes.cdll.LoadLibrary(ctypes.util.find_library("X11"))
xtst = ctypes.cdll.LoadLibrary(ctypes.util.find_library("Xtst"))

Window = ctypes.c_ulong
x11.XOpenDisplay.restype = ctypes.c_void_p
x11.XDefaultRootWindow.restype = Window
x11.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
x11.XInternAtom.restype = ctypes.c_ulong
x11.XInternAtom.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
x11.XQueryTree.argtypes = [ctypes.c_void_p, Window, ctypes.POINTER(Window), ctypes.POINTER(Window),
                           ctypes.POINTER(ctypes.POINTER(Window)), ctypes.POINTER(ctypes.c_uint)]
x11.XGetWindowProperty.argtypes = [ctypes.c_void_p, Window, ctypes.c_ulong, ctypes.c_long, ctypes.c_long,
                                   ctypes.c_int, ctypes.c_ulong, ctypes.POINTER(ctypes.c_ulong),
                                   ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_ulong),
                                   ctypes.POINTER(ctypes.c_ulong), ctypes.POINTER(ctypes.c_void_p)]
x11.XGetGeometry.argtypes = [ctypes.c_void_p, Window, ctypes.POINTER(Window), ctypes.POINTER(ctypes.c_int),
                             ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_uint), ctypes.POINTER(ctypes.c_uint),
                             ctypes.POINTER(ctypes.c_uint), ctypes.POINTER(ctypes.c_uint)]
x11.XTranslateCoordinates.argtypes = [ctypes.c_void_p, Window, Window, ctypes.c_int, ctypes.c_int,
                                      ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int), ctypes.POINTER(Window)]
x11.XQueryPointer.argtypes = [ctypes.c_void_p, Window, ctypes.POINTER(Window), ctypes.POINTER(Window),
                              ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int),
                              ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_uint)]
x11.XFlush.argtypes = [ctypes.c_void_p]
x11.XRaiseWindow.argtypes = [ctypes.c_void_p, Window]
x11.XSetInputFocus.argtypes = [ctypes.c_void_p, Window, ctypes.c_int, ctypes.c_ulong]
x11.XFree.argtypes = [ctypes.c_void_p]
xtst.XTestFakeMotionEvent.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_ulong]
xtst.XTestFakeButtonEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]
xtst.XTestFakeKeyEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]
x11.XStringToKeysym.restype = ctypes.c_ulong
x11.XStringToKeysym.argtypes = [ctypes.c_char_p]
x11.XKeysymToKeycode.restype = ctypes.c_ubyte
x11.XKeysymToKeycode.argtypes = [ctypes.c_void_p, ctypes.c_ulong]

display = x11.XOpenDisplay(None)
if not display:
    sys.exit("no X display")
root = x11.XDefaultRootWindow(display)
NET_WM_PID = x11.XInternAtom(display, b"_NET_WM_PID", 1)


def window_pid(w):
    actual_type, fmt = ctypes.c_ulong(), ctypes.c_int()
    count, after, data = ctypes.c_ulong(), ctypes.c_ulong(), ctypes.c_void_p()
    if x11.XGetWindowProperty(display, w, NET_WM_PID, 0, 1, 0, 0, ctypes.byref(actual_type), ctypes.byref(fmt),
                              ctypes.byref(count), ctypes.byref(after), ctypes.byref(data)) != 0 or not data.value:
        return None
    value = ctypes.cast(data, ctypes.POINTER(ctypes.c_ulong))[0] if count.value else None
    x11.XFree(data)
    return value


def find(w):
    if window_pid(w) == pid:
        width, height = ctypes.c_uint(), ctypes.c_uint()
        r, gx, gy, border, depth = Window(), ctypes.c_int(), ctypes.c_int(), ctypes.c_uint(), ctypes.c_uint()
        x11.XGetGeometry(display, w, ctypes.byref(r), ctypes.byref(gx), ctypes.byref(gy),
                         ctypes.byref(width), ctypes.byref(height), ctypes.byref(border), ctypes.byref(depth))
        if width.value > 200 and height.value > 200:
            return w, width.value, height.value
    r, parent, children, n = Window(), Window(), ctypes.POINTER(Window)(), ctypes.c_uint()
    if not x11.XQueryTree(display, w, ctypes.byref(r), ctypes.byref(parent), ctypes.byref(children), ctypes.byref(n)):
        return None
    found = None
    for i in range(n.value):
        found = find(children[i])
        if found:
            break
    if children:
        x11.XFree(children)
    return found


found = find(root)
if not found:
    sys.exit("game window not found for pid %d" % pid)
win, width, height = found
x, y, child = ctypes.c_int(), ctypes.c_int(), Window()
x11.XTranslateCoordinates(display, win, root, width // 2, height // 2, ctypes.byref(x), ctypes.byref(y), ctypes.byref(child))

r, c = Window(), Window()
oldx, oldy, wx, wy, mask = ctypes.c_int(), ctypes.c_int(), ctypes.c_int(), ctypes.c_int(), ctypes.c_uint()
x11.XQueryPointer(display, root, ctypes.byref(r), ctypes.byref(c), ctypes.byref(oldx), ctypes.byref(oldy),
                  ctypes.byref(wx), ctypes.byref(wy), ctypes.byref(mask))

x11.XRaiseWindow(display, win)
x11.XSetInputFocus(display, win, 1, 0)
x11.XFlush(display)

if keys:
    time.sleep(0.2)
    # "none" is a pause between keys
    for name, ms in keys:
        code = 0
        if name != "none":
            code = x11.XKeysymToKeycode(display, x11.XStringToKeysym(name.encode()))
            if not code:
                sys.exit("unknown key " + name)
        if name != "none":
            xtst.XTestFakeKeyEvent(display, code, 1, 0)
            x11.XFlush(display)
        time.sleep(ms / 1000.0)
        if name != "none":
            xtst.XTestFakeKeyEvent(display, code, 0, 0)
            x11.XFlush(display)
    print("held " + ", ".join("%s %d ms" % k for k in keys))
    sys.exit(0)

xtst.XTestFakeMotionEvent(display, -1, x.value, y.value, 0)
x11.XFlush(display)
time.sleep(0.2)
xtst.XTestFakeButtonEvent(display, 1, 1, 0)
x11.XFlush(display)
time.sleep(0.15)
xtst.XTestFakeButtonEvent(display, 1, 0, 0)
xtst.XTestFakeMotionEvent(display, -1, oldx.value, oldy.value, 0)
x11.XFlush(display)
print("clicked game window at %d,%d" % (x.value, y.value))
