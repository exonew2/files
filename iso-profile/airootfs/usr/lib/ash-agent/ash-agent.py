#!/usr/bin/env python3
"""
ash-agent.py — Ash AI Desktop Assistant Daemon
Monitors system health, provides AI-powered suggestions,
and exposes a D-Bus interface for desktop integration.
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
from pathlib import Path

CONFIG_PATH = "/usr/lib/ash-agent/ash-agent.yaml"
LOG_DIR = os.path.expanduser("~/.local/share/ash-agent")
DBUS_NAME = "org.ash.Agent"
DBUS_PATH = "/org/ash/Agent"

os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler(os.path.join(LOG_DIR, "agent.log"))
    ]
)
log = logging.getLogger("ash-agent")

CONFIG = {
    "ollama": {"endpoint": "http://localhost:11434", "model": "phi3:mini", "keep_alive": -1},
    "monitoring": {
        "cpu_alert_threshold": 90, "memory_alert_threshold": 85,
        "disk_alert_threshold": 90, "gpu_temp_alert_threshold": 85,
        "check_interval_seconds": 60
    },
    "notifications": {"backend": "swaync", "app_name": "Ash Agent", "urgency": "normal"},
}

def load_config():
    try:
        import yaml
        if os.path.exists(CONFIG_PATH):
            with open(CONFIG_PATH) as f:
                user_cfg = yaml.safe_load(f)
                if user_cfg:
                    _deep_merge(CONFIG, user_cfg)
    except ImportError:
        pass
    except Exception as e:
        log.warning("Config load failed: %s", e)

def _deep_merge(base, override):
    for k, v in override.items():
        if k in base and isinstance(base[k], dict) and isinstance(v, dict):
            _deep_merge(base[k], v)
        else:
            base[k] = v

def ollama_req(endpoint, method="POST", data=None, timeout=10):
    url = f"{CONFIG['ollama']['endpoint']}/api/{endpoint}"
    body = json.dumps(data).encode("utf-8") if data else None
    req = urllib.request.Request(url, data=body, method=method,
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except Exception as e:
        log.warning("Ollama %s failed: %s", endpoint, e)
        return None

def notify(title, body, urgency=None, timeout=5000):
    urgency = urgency or CONFIG["notifications"]["urgency"]
    try:
        subprocess.run(
            ["notify-send", "-a", CONFIG["notifications"]["app_name"],
             "-u", urgency, "-t", str(timeout), title, body],
            timeout=5, capture_output=True
        )
    except Exception as e:
        log.warning("notify-send failed: %s", e)

class AshAgent(dbus.service.Object):
    def __init__(self, bus, path):
        dbus.service.Object.__init__(self, bus, path)
        self._health = {}
        self._stop_event = threading.Event()
        self._monitor_thread = threading.Thread(target=self._monitor_loop, daemon=True)
        self._monitor_thread.start()
        log.info("Ash Agent started on D-Bus %s", DBUS_NAME)

    def _chat_ollama(self, query):
        model = CONFIG["ollama"]["model"]
        sysprompt = (
            "You are Ash Agent, an AI desktop assistant for Arch Linux. "
            "Provide concise, actionable responses. For system issues, suggest "
            "specific terminal commands. Keep responses under 200 words."
        )
        resp = ollama_req("chat", data={
            "model": model,
            "keep_alive": CONFIG["ollama"]["keep_alive"],
            "messages": [
                {"role": "system", "content": sysprompt},
                {"role": "user", "content": query}
            ],
            "stream": False
        })
        if resp and "message" in resp:
            return resp["message"]["content"].strip()
        fallback = ollama_req("generate", data={
            "model": model,
            "keep_alive": CONFIG["ollama"]["keep_alive"],
            "prompt": f"{sysprompt}\n\nUser: {query}",
            "stream": False
        })
        if fallback and "response" in fallback:
            return fallback["response"].strip()
        return "I'm having trouble reaching the local LLM. Is Ollama running?"

    def _get_health_data(self):
        health = {}
        try:
            import psutil
            health["cpu_percent"] = psutil.cpu_percent(interval=1)
            health["cpu_count"] = psutil.cpu_count()
            mem = psutil.virtual_memory()
            health["memory_percent"] = mem.percent
            health["memory_used_gb"] = round(mem.used / 1e9, 1)
            health["memory_total_gb"] = round(mem.total / 1e9, 1)
            disk = psutil.disk_usage("/")
            health["disk_percent"] = disk.percent
            health["disk_used_gb"] = round(disk.used / 1e9, 1)
            health["disk_total_gb"] = round(disk.total / 1e9, 1)
            health["load_avg"] = [round(x, 2) for x in psutil.getloadavg()]
            temps = psutil.sensors_temperatures()
            if temps:
                for name, entries in temps.items():
                    if entries:
                        health["gpu_temp"] = round(entries[0].current, 1)
                        break
            uptime_sec = time.time() - psutil.boot_time()
            health["uptime_hours"] = round(uptime_sec / 3600, 1)
        except ImportError:
            health["error"] = "psutil not available"
        except Exception as e:
            health["error"] = str(e)
        self._health = health
        return health

    def _monitor_loop(self):
        interval = CONFIG["monitoring"]["check_interval_seconds"]
        while not self._stop_event.wait(interval):
            try:
                health = self._get_health_data()
                alerts = []
                if health.get("cpu_percent", 0) >= CONFIG["monitoring"]["cpu_alert_threshold"]:
                    alerts.append(f"CPU at {health['cpu_percent']}%")
                if health.get("memory_percent", 0) >= CONFIG["monitoring"]["memory_alert_threshold"]:
                    alerts.append(f"Memory at {health['memory_percent']}%")
                if health.get("disk_percent", 0) >= CONFIG["monitoring"]["disk_alert_threshold"]:
                    alerts.append(f"Disk at {health['disk_percent']}%")
                if alerts:
                    alert_msg = " | ".join(alerts)
                    suggestion = self._chat_ollama(
                        f"System alert: {alert_msg}. Suggest a quick fix command."
                    )
                    notify("Ash Agent Alert", f"{alert_msg}\n\nSuggestion:\n{suggestion}",
                           urgency="critical", timeout=10000)
            except Exception as e:
                log.error("Monitor loop error: %s", e)

    @dbus.service.method(DBUS_NAME, in_signature='s', out_signature='s')
    def Chat(self, query):
        log.info("Chat query: %s", query[:100])
        try:
            response = self._chat_ollama(query)
            return response
        except Exception as e:
            log.error("Chat error: %s", e)
            return f"Error processing query: {e}"

    @dbus.service.method(DBUS_NAME, in_signature='', out_signature='s')
    def GetHealth(self):
        health = self._get_health_data()
        return json.dumps(health, indent=2)

    @dbus.service.method(DBUS_NAME, in_signature='s', out_signature='s')
    def SuggestFix(self, issue):
        prompt = f"I have this system issue: {issue}. Suggest specific terminal commands to fix it."
        return self._chat_ollama(prompt)

    @dbus.service.method(DBUS_NAME, in_signature='', out_signature='s')
    def GetActiveNotifications(self):
        return json.dumps([])

    def stop(self):
        self._stop_event.set()
        self._monitor_thread.join(timeout=5)

def main():
    load_config()

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()

    try:
        bus_name = dbus.service.BusName(DBUS_NAME, bus)
    except dbus.exceptions.NameExistsException:
        log.error("Another Ash Agent is already running on %s", DBUS_NAME)
        sys.exit(1)

    agent = AshAgent(bus, DBUS_PATH)
    loop = GLib.MainLoop()

    def sigterm_handler(_signum, _frame):
        log.info("Shutting down...")
        agent.stop()
        loop.quit()

    signal.signal(signal.SIGTERM, sigterm_handler)
    signal.signal(signal.SIGINT, sigterm_handler)

    log.info("Ash Agent daemon ready")
    loop.run()

if __name__ == "__main__":
    main()
