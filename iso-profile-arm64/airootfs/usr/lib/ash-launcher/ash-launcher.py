#!/usr/bin/env python3
"""
ash-launcher.py — AI Application Launcher Daemon
Replaces wofi/rofi with AI-powered suggestions.
Tracks usage patterns and predicts intent.
"""

import json
import logging
import os
import platform
import signal
import sqlite3
import subprocess
import threading
import time
import urllib.request
import urllib.error
from collections import defaultdict, Counter
from pathlib import Path

LOG_DIR = os.path.expanduser("~/.local/share/ash-launcher")
DB_PATH = os.path.join(LOG_DIR, "launcher.db")
OLLAMA_URL = "http://localhost:11434/api"
MODEL = "phi3:mini"

os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler(os.path.join(LOG_DIR, "launcher.log"))
    ]
)
log = logging.getLogger("ash-launcher")

INTENT_MAP = {
    "write email": ["thunderbird", "geary", "evolution", "mailspring"],
    "write code": ["code", "code-oss", "jetbrains-idea", "vim", "nvim", "neovim", "emacs"],
    "fix bug": ["code", "code-oss", "jetbrains-idea", "jetbrains-webstorm", "kitty", "ghostty"],
    "browse web": ["firefox", "chromium", "google-chrome", "brave"],
    "read document": ["zathura", "evince", "okular", "libreoffice"],
    "listen music": ["spotify", "vlc", "mpv", "strawberry"],
    "chat": ["discord", "telegram-desktop", "slack", "element"],
    "terminal": ["kitty", "alacritty", "foot", "ghostty", "wezterm"],
    "files": ["nautilus", "thunar", "dolphin", "yazi"],
    "design": ["gimp", "inkscape", "blender", "krita"],
    "docker": ["docker", "podman", "lens", "distrobox"],
    "database": ["dbeaver", "tableplus", "sqlitebrowser", "mysql-workbench"],
    "game": ["steam", "lutris", "heroic-games-launcher", "gamescope"],
}

def get_db():
    conn = sqlite3.connect(DB_PATH, timeout=5)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("""CREATE TABLE IF NOT EXISTS app_usage (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        app_name TEXT NOT NULL,
        class_name TEXT NOT NULL,
        timestamp REAL NOT NULL,
        hour INTEGER NOT NULL,
        dow INTEGER NOT NULL,
        workspace INTEGER DEFAULT 1
    )""")
    conn.execute("""CREATE INDEX IF NOT EXISTS idx_usage_hour ON app_usage(hour)""")
    conn.execute("""CREATE INDEX IF NOT EXISTS idx_usage_app ON app_usage(app_name)""")
    conn.commit()
    return conn

def record_launch(app_name, class_name="", workspace=1):
    try:
        conn = get_db()
        conn.execute("""INSERT INTO app_usage (app_name, class_name, timestamp, hour, dow, workspace)
                        VALUES (?, ?, ?, ?, ?, ?)""",
                     (app_name, class_name, time.time(), time.localtime().tm_hour,
                      time.localtime().tm_wday, workspace))
        conn.commit()
        conn.close()
    except Exception as e:
        log.warning("Record launch failed: %s", e)

def get_time_based_predictions():
    hour = time.localtime().tm_hour
    dow = time.localtime().tm_wday
    try:
        conn = get_db()
        rows = conn.execute("""
            SELECT app_name, class_name, COUNT(*) as freq
            FROM app_usage
            WHERE hour BETWEEN ? AND ?
            ORDER BY freq DESC LIMIT 10
        """, (max(0, hour - 2), min(23, hour + 2))).fetchall()
        conn.close()
        return [{"app": r["app_name"], "class": r["class_name"], "freq": r["freq"]} for r in rows]
    except Exception as e:
        log.warning("Time predictions failed: %s", e)
        return []

def get_frequent_apps(limit=10):
    try:
        conn = get_db()
        rows = conn.execute("""
            SELECT app_name, class_name, COUNT(*) as freq
            FROM app_usage
            WHERE timestamp > ?
            GROUP BY app_name ORDER BY freq DESC LIMIT ?
        """, (time.time() - 604800, limit)).fetchall()
        conn.close()
        return [{"app": r["app_name"], "class": r["class_name"], "freq": r["freq"]} for r in rows]
    except Exception as e:
        log.warning("Frequent apps failed: %s", e)
        return []

def get_recent_apps(limit=5):
    try:
        conn = get_db()
        rows = conn.execute("""
            SELECT DISTINCT app_name, class_name
            FROM app_usage
            WHERE timestamp > ?
            ORDER BY timestamp DESC LIMIT ?
        """, (time.time() - 3600, limit)).fetchall()
        conn.close()
        return [{"app": r["app_name"], "class": r["class_name"]} for r in rows]
    except Exception as e:
        return []

def resolve_intent(query):
    query_lower = query.lower().strip()
    for intent, apps in INTENT_MAP.items():
        if intent in query_lower:
            return apps
    prompt = (
        f"User wants to: {query}\n"
        f"Suggest a desktop application to open. Return ONLY the app's binary name "
        f"(e.g., 'firefox', 'code', 'kitty')."
    )
    try:
        data = json.dumps({
            "model": MODEL, "prompt": prompt,
            "keep_alive": -1, "stream": False
        }).encode("utf-8")
        req = urllib.request.Request(f"{OLLAMA_URL}/generate", data=data,
                                     headers={"Content-Type": "application/json"},
                                     method="POST")
        with urllib.request.urlopen(req, timeout=8) as resp:
            result = json.loads(resp.read())
            app = result.get("response", "").strip().lower()
            if app:
                return [app]
    except Exception as e:
        log.warning("Intent resolve failed: %s", e)
    return []

def get_desktop_entries():
    entries = {}
    for dir_path in ["/usr/share/applications", os.path.expanduser("~/.local/share/applications")]:
        if not os.path.isdir(dir_path):
            continue
        for f in os.listdir(dir_path):
            if not f.endswith(".desktop"):
                continue
            path = os.path.join(dir_path, f)
            try:
                with open(path, "r", errors="replace") as fh:
                    content = fh.read()
                name = ""
                exec_cmd = ""
                for line in content.splitlines():
                    if line.startswith("Name=") and not name:
                        name = line.split("=", 1)[1].strip()
                    if line.startswith("Exec=") and not exec_cmd:
                        exec_cmd = line.split("=", 1)[1].strip()
                if name and exec_cmd:
                    entries[f.replace(".desktop", "")] = {
                        "name": name, "exec": exec_cmd, "path": path
                    }
            except Exception:
                pass
    return entries

class AshLauncher:
    def __init__(self):
        desktop_entries = get_desktop_entries()
        self._desktop = desktop_entries
        log.info("Ash Launcher ready — %d desktop entries loaded", len(desktop_entries))

    def get_launcher_suggestions(self, query=""):
        time_based = get_time_based_predictions()
        frequent = get_frequent_apps()
        recent = get_recent_apps()

        suggestions = []

        if query:
            intent_apps = resolve_intent(query)
            for app_bin in intent_apps:
                for entry_id, entry in self._desktop.items():
                    if app_bin in entry_id or app_bin in entry["exec"].lower():
                        suggestions.append({
                            "source": "intent", "app": entry_id,
                            "name": entry["name"], "exec": entry["exec"]
                        })
                        break
                else:
                    suggestions.append({
                        "source": "intent", "app": app_bin,
                        "name": app_bin.title(), "exec": app_bin
                    })

        seen = set()
        for group in [recent, time_based, frequent]:
            for item in group:
                app = item.get("app", "")
                if app in seen:
                    continue
                seen.add(app)
                for entry_id, entry in self._desktop.items():
                    if app == entry_id or app.lower() in entry["exec"].lower():
                        suggestions.append({
                            "source": item.get("source", "history"),
                            "app": entry_id, "name": entry["name"],
                            "exec": entry["exec"]
                        })
                        break
                else:
                    suggestions.append({
                        "source": "history", "app": app,
                        "name": app.title(), "exec": app
                    })

        return suggestions[:20]

    def launch(self, exec_cmd):
        try:
            subprocess.Popen(
                ["hyprctl", "dispatch", "exec", exec_cmd],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
            return True
        except Exception as e:
            log.warning("Launch failed for '%s': %s", exec_cmd, e)
            return False

launcher = AshLauncher()

def main_loop():
    while True:
        time.sleep(300)

def signal_handler(signum, frame):
    log.info("Shutting down...")
    sys.exit(0)

if __name__ == "__main__":
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)
    log.info("Ash Launcher daemon ready")
    main_loop()
