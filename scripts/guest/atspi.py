#!/usr/bin/python3
"""Drives a Qt/Kirigami app through accessibility (AT-SPI), inside the guest.
Copied in and run by scripts/vmlive.py's "ui" step.

    atspi.py on                        turn accessibility on for the session (Qt follows it)
    atspi.py dump APP                  the app's accessible tree: role, name, text
    atspi.py press APP NAME [SECONDS]  press the first showing control named NAME (waits for it;
                                       one scrolled out of view is focused first, which
                                       scrolls it in, and pressed anyway if it is the only match);
                                       "ROLE:NAME" (button:Go back) also matches the role,
                                       and "NAME#2" presses the second match (a dialog's twin)
    atspi.py wait APP TEXT [SECONDS]   wait until TEXT appears anywhere in the app
    atspi.py set APP NAME VALUE        set the value of the showing control named NAME
                                       (a spin box or slider, through its Value interface)

APP matches the start of the application's accessible name, case-insensitively.
"""

import re
import subprocess
import sys
import time

import gi

gi.require_version("Atspi", "2.0")
from gi.repository import Atspi  # noqa: E402


def app(name: str):
    desktop = Atspi.get_desktop(0)
    for i in range(desktop.get_child_count()):
        a = desktop.get_child_at_index(i)
        if a is not None and (a.get_name() or "").lower().startswith(name.lower()):
            return a
    return None


def walk(node, depth=0):
    yield node, depth
    try:
        n = node.get_child_count()
    except Exception:
        return
    for i in range(n):
        c = node.get_child_at_index(i)
        if c is not None:
            yield from walk(c, depth + 1)


def text_of(node) -> str:
    try:
        t = node.get_text_iface()
        if t is not None:
            return t.get_text(0, -1) or ""
    except Exception:
        pass
    return ""


def showing(node) -> bool:
    try:
        return node.get_state_set().contains(Atspi.StateType.SHOWING)
    except Exception:
        return False


def press(node) -> bool:
    try:
        action = node.get_action_iface()
    except Exception:
        return False
    if action is None or action.get_n_actions() == 0:
        return False
    # Qt lists SetFocus first on list items and Toggle first on checkable
    # ones; Press is the click.
    names = [action.get_action_name(i).lower() for i in range(action.get_n_actions())]
    pick = next((names.index(n) for n in ("press", "click", "toggle") if n in names), 0)
    action.do_action(pick)
    return True


def need_app(name: str, seconds: float = 30):
    deadline = time.time() + seconds
    while (a := app(name)) is None:
        if time.time() > deadline:
            sys.exit(f"no accessible application named {name!r}")
        time.sleep(1)
    return a


def main() -> None:
    cmd = sys.argv[1]
    if cmd == "on":
        subprocess.run(["busctl", "--user", "set-property", "org.a11y.Bus", "/org/a11y/bus",
                        "org.a11y.Status", "IsEnabled", "b", "true"], check=True)
        print("accessibility on")
        return
    a = need_app(sys.argv[2])
    if cmd == "dump":
        for node, depth in walk(a):
            if not showing(node) and depth > 1:
                continue
            name, text = node.get_name() or "", text_of(node)
            line = f"{'  ' * depth}{node.get_role_name()}: {name}"
            if text and text != name:
                line += f" | {text}"
            print(line[:300])
    elif cmd == "press":
        target, seconds = sys.argv[3], float(sys.argv[4]) if len(sys.argv) > 4 else 30
        m = re.fullmatch(r"(?:([a-z ]+):)?(.+?)(?:#(\d+))?", target)
        role, name, nth = m.group(1) or "", m.group(2), int(m.group(3) or 1)
        deadline = time.time() + seconds
        focused = False
        while True:
            matches = [node for node, _ in walk(need_app(sys.argv[2]))
                       if (node.get_name() or "") == name and (not role or node.get_role_name() == role)]
            shown = [node for node in matches if showing(node)]
            node = shown[nth - 1] if len(shown) >= nth else None
            if node is None and matches and not focused:
                # Qt reports a control scrolled out of view as neither showing nor
                # visible. Focusing it makes the page scroll it into view.
                focused = True
                for c in matches:
                    try:
                        c.get_component_iface().grab_focus()
                    except Exception:
                        pass
                time.sleep(1)
                continue
            if node is None and len(matches) == 1 and nth == 1:
                node = matches[0]  # unambiguous, even if still out of view
            # Read the role first: pressing can destroy the control (a card's own button).
            if node is not None and (kind := node.get_role_name()) and press(node):
                print(f"pressed {target!r} ({kind})")
                return
            if time.time() > deadline:
                sys.exit(f"no showing control named {target!r}")
            time.sleep(1)
    elif cmd == "wait":
        target, seconds = sys.argv[3], float(sys.argv[4]) if len(sys.argv) > 4 else 60
        deadline = time.time() + seconds
        while True:
            for node, _ in walk(need_app(sys.argv[2])):
                if target in (node.get_name() or "") or target in text_of(node):
                    print(f"found {target!r}")
                    return
            if time.time() > deadline:
                sys.exit(f"{target!r} never appeared")
            time.sleep(2)
    elif cmd == "set":
        if len(sys.argv) < 5:
            sys.exit(__doc__)
        name, value = sys.argv[3], float(sys.argv[4])
        for node, _ in walk(a):
            if (node.get_name() or "") == name and showing(node):
                v = node.get_value_iface()
                if v is not None and v.set_current_value(value):
                    print(f"set {name!r} to {v.get_current_value():g}")
                    return
        sys.exit(f"no showing control named {name!r} that takes a value")
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
