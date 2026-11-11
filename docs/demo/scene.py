#!/usr/bin/env python3
"""Plays the demo's scene in the stage's Rex window and captures it.

scene.py <stage folder>: sizes the window, limits its sidebar to "This Mac"
(the stage's server), then types into the shop's shell with the rex CLI and
clicks sidebar rows with cua-driver, while a thread saves the window ten
times a second into <stage>/frames.
"""
import json
import os
import subprocess
import sys
import threading
import time

W = sys.argv[1]
ENV = dict(os.environ)
for line in open(f"{W}/env.sh"):
    if line.startswith("export "):
        for pair in __import__("shlex").split(line[len("export "):]):
            k, _, v = pair.partition("=")
            ENV[k] = v
for k in ("REX_SESSION", "REX_BLOCK", "REX_CLIENT", "REX_HOME"):
    ENV.pop(k, None)
PID = int(open(f"{W}/app.pid").read())
FPS = 10


def rex(*args, check=True):
    r = subprocess.run(["rex", "--autostart=false", *args], env=ENV, capture_output=True, text=True)
    if check and r.returncode:
        raise SystemExit(f"rex {' '.join(args)}: {r.stderr.strip()}")
    return r.stdout


def cua(tool, args):
    r = subprocess.run(["cua-driver", "call", tool, json.dumps(args)], capture_output=True, text=True)
    try:
        return json.loads(r.stdout)
    except ValueError:
        return {}


def windows():
    return [x for x in cua("list_windows", {"pid": PID}).get("windows", []) if x.get("is_on_screen")]


def press(window_id, role, name, must=True):
    step = {"click": {"role": role, "name": name}}
    if not must:
        step["timeout_ms"] = 2000
    r = cua("run_steps", {"pid": PID, "window_id": window_id, "steps": [step]})
    if must and not r.get("ok"):
        raise SystemExit(f"couldn't press {name}: {json.dumps(r)[:300]}")


def show(window_id, name):
    """Clicks an agent's tab in the sidebar. Its terminal was sized before the app showed it, so the
    tab takes it over, as a click on the notice does."""
    press(window_id, "radiobutton", name)
    press(window_id, "button", "Take over", must=False)


def capture(window_id, stop):
    i, start = 0, time.time()
    while not stop.is_set():
        subprocess.run(["screencapture", "-x", "-o", "-l", str(window_id), f"{W}/frames/{i:05d}.png"])
        i += 1
        time.sleep(max(0.0, start + i / FPS - time.time()))


def type_line(session, block, text, each=0.012):
    for ch in text:
        rex("send", "-s", session, "-b", block, ch)
        time.sleep(each)
    time.sleep(0.5)
    rex("send-key", "-s", session, "-b", block, "enter")


def agent_block(name):
    """The block of the herdr-core tab that shows the agent called name."""
    hc = subprocess.run(["hc", "ls", "--json"], env=ENV, capture_output=True, text=True).stdout
    address = next(t["address"] for t in json.loads(hc)["terminals"] if t.get("name") == name)
    for s in json.loads(rex("ls", "--json")).get("sessions", []):
        if s.get("label") == "herdr-core":
            for b in json.loads(rex("block", "ls", "-s", s["session_id"], "--json")).get("blocks", []):
                if b.get("label") == f"hc:{address}":
                    return s["session_id"], b["block_id"]
    raise SystemExit(f"no tab for {name}")


def main():
    shop = json.load(open(f"{W}/shop.json"))
    session, block = shop["session_id"], shop["initial_windows"][0]["block_ids"][0]
    main_window = max(windows(), key=lambda x: (bool(x.get("title")), x["bounds"]["width"]))
    wid = main_window["window_id"]
    b = main_window["bounds"]
    cua("set_window_frame", {"pid": PID, "window_id": wid, "x": b["x"] + 20, "y": b["y"] + 60, "width": 1300, "height": 760})
    # Only the stage's server in the sidebar: the app also knows your hosts.
    press(wid, "button", "Filter Hosts")
    menu = min(windows(), key=lambda x: x["bounds"]["width"])
    press(menu["window_id"], "button", "This Mac")
    rex("-C", client(), "do", "session.select", f"session_id={session}")
    time.sleep(4)  # the "Go to Session" notice fades

    stop = threading.Event()
    t = threading.Thread(target=capture, args=(wid, stop))
    t.start()
    try:
        time.sleep(1.5)
        type_line(session, block, 'hc run --bg --name fix-auth -- claude "Fix the login redirect loop"')
        time.sleep(1.0)
        type_line(session, block, 'hc run --bg --name retries -- claude "Add retries to the webhook client"')
        time.sleep(1.0)
        type_line(session, block, 'hc run --bg --name docs -- claude "Update the docs for the new API"')
        time.sleep(7.5)  # retries stops to ask; fix-auth finishes
        show(wid, "retries")
        time.sleep(3.0)
        answer("retries")
        time.sleep(5.5)  # retries finishes
        show(wid, "fix-auth")
        time.sleep(3.5)
        show(wid, "docs")
        time.sleep(4.0)
    finally:
        stop.set()
        t.join()


def client():
    for line in rex("client", "ls").splitlines():
        if " app " in line:
            return line.split()[-1]
    raise SystemExit("the stage's Rex app isn't connected")


def answer(name):
    s, b = agent_block(name)
    rex("send", "-s", s, "-b", b, "1")


if __name__ == "__main__":
    main()
