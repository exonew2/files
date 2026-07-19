#!/usr/bin/env python3
"""
ash-workspace.py — Smart Workspace Manager Daemon
Analyzes running applications, suggests layouts,
and remembers workspace habits via Qdrant vector DB.
"""

import dbus
import dbus.service
import dbus.mainloop.glib
import json
import logging
import os
import signal
import subprocess
import threading
import time
import urllib.request
import urllib.error
from gi.repository import GLib
from collections import defaultdict

LOG_DIR = os.path.expanduser("~/.local/share/ash-workspace")
DBUS_NAME = "org.ash.Workspace"
DBUS_PATH = "/org/ash/Workspace"
OLLAMA_URL = "http://localhost:11434/api"
QDRANT_URL = "http://localhost:6333/collections"
MODEL = "phi3:mini"
EMBED_MODEL = "nomic-embed-text:v1.5"
EMBED_DIM = 768
COLLECTION = "workspace_habits"

os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler(os.path.join(LOG_DIR, "workspace.log"))
    ]
)
log = logging.getLogger("ash-workspace")

APP_CATEGORIES = {
    "browser": ["firefox", "chromium", "google-chrome", "brave", "thorium", "qutebrowser", "librewolf"],
    "terminal": ["kitty", "alacritty", "foot", "wezterm", "ghostty", "konsole", "gnome-terminal", "xterm"],
    "editor": ["code", "code-oss", "vscodium", "jetbrains-idea", "jetbrains-webstorm",
               "jetbrains-pycharm", "neovim", "nvim", "emacs", "sublime_text"],
    "files": ["nautilus", "nemo", "thunar", "pcmanfm", "dolphin", "yazi"],
    "media": ["spotify", "vlc", "mpv", "rhythmbox", "audacity", "obs"],
    "chat": ["discord", "telegram-desktop", "slack", "signal-desktop", "element", "whatsapp-nativefier"],
    "devops": ["docker", "podman", "lens", "k9s", "vagrant", "terraform"],
    "documents": ["libreoffice", "onlyoffice", "evince", "zathura", "calibre", "okular"],
    "design": ["gimp", "inkscape", "blender", "krita", "figma-linux"],
}

DEFAULT_LAYOUT = {
    1: ["browser"],
    2: ["terminal", "devops"],
    3: ["editor"],
    4: ["chat"],
    5: ["files"],
    6: ["media"],
    7: ["documents"],
    8: ["design"],
}

def qdrant_req(method, path, data=None, timeout=3):
    url = f"{QDRANT_URL}/{path.lstrip('/')}"
    body = json.dumps(data).encode("utf-8") if data else None
    req = urllib.request.Request(url, data=body, method=method,
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return {}
        return None
    except Exception as e:
        log.warning("Qdrant %s %s: %s", method, path, e)
        return None

def ensure_collection():
    existing = qdrant_req("GET", COLLECTION)
    if existing is None or "result" not in existing:
        log.info("Creating Qdrant collection '%s' (dim=%d)", COLLECTION, EMBED_DIM)
        qdrant_req("PUT", COLLECTION, {
            "name": COLLECTION,
            "vectors": {"size": EMBED_DIM, "distance": "Cosine"},
            "optimizers_config": {"default_segment_number": 2, "memmap_threshold_kb": 20000}
        }, timeout=5)

def get_embedding(text):
    payload = json.dumps({
        "model": EMBED_MODEL, "prompt": text[:2048], "keep_alive": -1
    }).encode("utf-8")
    try:
        req = urllib.request.Request(
            f"{OLLAMA_URL}/embeddings", data=payload,
            headers={"Content-Type": "application/json"}, method="POST"
        )
        with urllib.request.urlopen(req, timeout=5) as resp:
            return json.loads(resp.read()).get("embedding")
    except Exception as e:
        log.warning("Embedding failed: %s", e)
        return None

def get_ollama_response(prompt):
    payload = json.dumps({
        "model": MODEL, "prompt": prompt, "keep_alive": -1,
        "stream": False
    }).encode("utf-8")
    try:
        req = urllib.request.Request(
            f"{OLLAMA_URL}/generate", data=payload,
            headers={"Content-Type": "application/json"}, method="POST"
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read())
            return data.get("response", "").strip()
    except Exception as e:
        log.warning("Ollama response failed: %s", e)
        return ""

def get_hyprctl_clients():
    try:
        result = subprocess.run(
            ["hyprctl", "clients", "-j"],
            capture_output=True, text=True, timeout=5
        )
        return json.loads(result.stdout) if result.stdout else []
    except Exception as e:
        log.warning("hyprctl clients failed: %s", e)
        return []

def categorize_app(class_name):
    cls = class_name.lower()
    for category, apps in APP_CATEGORIES.items():
        for app in apps:
            if app in cls or cls in app:
                return category
    return "other"

class WorkspaceManager(dbus.service.Object):
    def __init__(self, bus, path):
        dbus.service.Object.__init__(self, bus, path)
        self._stop_event = threading.Event()
        ensure_collection()
        log.info("Workspace Manager started on D-Bus %s", DBUS_NAME)

    @dbus.service.method(DBUS_NAME, in_signature='', out_signature='s')
    def Organize(self):
        try:
            result = self._organize_windows()
            return json.dumps(result)
        except Exception as e:
            log.error("Organize failed: %s", e)
            return json.dumps({"error": str(e)})

    def _organize_windows(self):
        clients = get_hyprctl_clients()
        if not clients:
            return {"status": "no_clients", "moved": 0}

        window_map = defaultdict(list)
        for c in clients:
            cls = c.get("class", "")
            wid = c.get("address", "")
            cat = categorize_app(cls)
            ws = c.get("workspace", {}).get("id", 1)
            window_map[cat].append({"class": cls, "address": wid, "workspace": ws})

        layout = self._suggest_layout(window_map)
        moved = 0
        for cat, target_ws in layout.items():
            if cat not in window_map:
                continue
            for win in window_map[cat]:
                cur_ws = win["workspace"]
                if cur_ws != target_ws:
                    addr = win["address"]
                    try:
                        subprocess.run(
                            ["hyprctl", "dispatch", "movetoworkspace",
                             str(target_ws), f"address:{addr}"],
                            capture_output=True, timeout=3
                        )
                        moved += 1
                    except Exception as e:
                        log.warning("Move failed for %s: %s", addr, e)

        self._record_layout(window_map, layout)
        return {"status": "organized", "moved": moved, "layout": layout}

    def _suggest_layout(self, window_map):
        time_of_day = "morning" if 6 <= time.localtime().tm_hour < 12 else \
                      "afternoon" if 12 <= time.localtime().tm_hour < 18 else \
                      "evening"

        layout = DEFAULT_LAYOUT.copy()
        category_count = defaultdict(int)
        for cat, wins in window_map.items():
            category_count[cat] = len(wins)

        ai_prompt = (
            f"Current time: {time_of_day}. Active app categories: {dict(category_count)}. "
            f"Suggest a workspace layout (1-8) for these categories. "
            f"Return JSON like: {{\"browser\": 1, \"terminal\": 2, ...}}"
        )
        ai_suggestion = get_ollama_response(ai_prompt)
        if ai_suggestion:
            try:
                parsed = json.loads(ai_suggestion)
                if isinstance(parsed, dict):
                    for cat, ws in parsed.items():
                        if cat in APP_CATEGORIES and isinstance(ws, (int, float)):
                            layout[int(ws)] = [cat]
            except (json.JSONDecodeError, ValueError):
                pass

        next_ws = 1
        for cat in list(window_map.keys()):
            if cat not in {v for vals in layout.values() for v in vals}:
                while next_ws in layout and next_ws <= 8:
                    next_ws += 1
                if next_ws <= 8:
                    layout[next_ws] = [cat]
                    next_ws += 1

        return {cat: ws for ws, cats in layout.items() for cat in cats if cat in window_map}

    def _record_layout(self, window_map, layout):
        try:
            embedding_text = json.dumps({
                "categories": {k: len(v) for k, v in window_map.items()},
                "layout": layout,
                "hour": time.localtime().tm_hour,
                "dow": time.localtime().tm_wday
            })
            emb = get_embedding(embedding_text)
            if emb:
                point_id = int(time.time() * 1000) % (2**63)
                qdrant_req("PUT", f"{COLLECTION}/points", {
                    "points": [{
                        "id": point_id, "vector": emb,
                        "payload": {
                            "layout": layout,
                            "categories": dict(window_map),
                            "timestamp": time.time(),
                            "hour": time.localtime().tm_hour,
                            "dow": time.localtime().tm_wday
                        }
                    }]
                }, timeout=3)
        except Exception as e:
            log.warning("Record layout failed: %s", e)

    @dbus.service.method(DBUS_NAME, in_signature='', out_signature='s')
    def GetLayout(self):
        clients = get_hyprctl_clients()
        cats = defaultdict(list)
        for c in clients:
            cls = c.get("class", "")
            cats[categorize_app(cls)].append(cls)
        return json.dumps(dict(cats), indent=2)

    @dbus.service.method(DBUS_NAME, in_signature='', out_signature='s')
    def SuggestNextWorkspace(self):
        try:
            clients = get_hyprctl_clients()
            current_apps = [c.get("class", "") for c in clients]
            prompt = (
                f"Current running applications: {current_apps}. "
                f"Suggest what workspace/task the user might want to switch to next. "
                f"Be concise."
            )
            suggestion = get_ollama_response(prompt)
            return suggestion or "Try switching to a terminal or browser."
        except Exception as e:
            return f"Error: {e}"

    @dbus.service.method(DBUS_NAME, in_signature='', out_signature='s')
    def GetHabits(self):
        try:
            result = qdrant_req("POST", f"{COLLECTION}/points/scroll",
                                {"limit": 20, "with_payload": True}, timeout=5)
            points = result.get("result", {}).get("points", [])
            habits = []
            for p in points:
                payload = p.get("payload", {})
                habits.append({
                    "hour": payload.get("hour"),
                    "dow": payload.get("dow"),
                    "layout": payload.get("layout"),
                    "time": payload.get("timestamp")
                })
            return json.dumps(habits, indent=2)
        except Exception as e:
            return json.dumps({"error": str(e)})

    def stop(self):
        self._stop_event.set()

def main():
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()

    try:
        bus_name = dbus.service.BusName(DBUS_NAME, bus)
    except dbus.exceptions.NameExistsException:
        log.error("Another Workspace Manager is already running on %s", DBUS_NAME)
        sys.exit(1)

    wm = WorkspaceManager(bus, DBUS_PATH)
    loop = GLib.MainLoop()

    def sigterm_handler(_signum, _frame):
        log.info("Shutting down...")
        wm.stop()
        loop.quit()

    signal.signal(signal.SIGTERM, sigterm_handler)
    signal.signal(signal.SIGINT, sigterm_handler)

    log.info("Workspace Manager daemon ready")
    loop.run()

if __name__ == "__main__":
    main()
