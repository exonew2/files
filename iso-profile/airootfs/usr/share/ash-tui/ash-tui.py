#!/usr/bin/env python3
"""ash-tui — Terminal Dashboard for ash-iso"""

import os
import subprocess
import json
import shutil
import time
from datetime import datetime

try:
    from textual.app import App, ComposeResult
    from textual.containers import Horizontal, Vertical, Grid, Container
    from textual.widgets import Header, Footer, Static, Label, Button, ListView, ListItem, TabbedContent, TabPane, RichLog
    from textual.reactive import reactive
    from textual.binding import Binding
    from textual import log
except ImportError:
    print("ash-tui requires python-textual. Install with: pip install textual")
    print("Falling back to simple dashboard mode...")
    import sys
    sys.exit(1)


def run_cmd(cmd):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
        return r.stdout.strip() or r.stderr.strip()
    except Exception as e:
        return str(e)


class SystemMonitor(Static):
    """Live system monitor panel"""

    def on_mount(self):
        self.set_interval(3, self.refresh_stats)
        self.refresh_stats()

    def refresh_stats(self):
        cpu = run_cmd(["bash", "-c", "top -bn1 | head -5 | grep '%Cpu' | awk '{print $2}'"])
        mem = run_cmd(["bash", "-c", "free -h | awk '/^Mem:/ {print $3 \"/\" $2}'"])
        disk = run_cmd(["bash", "-c", "df -h / | awk 'NR==2 {print $3 \"/\" $2 \" (\" $5 \")\"}'"])
        uptime = run_cmd(["bash", "-c", "uptime -p | sed 's/up //'"])
        load = run_cmd(["cat", "/proc/loadavg"]).split()[:3]
        load_str = " ".join(load)
        gpu = run_cmd(["bash", "-c", "nvidia-smi --query-gpu=name,temperature.gpu --format=csv,noheader 2>/dev/null || echo 'No GPU'"])
        net = run_cmd(["bash", "-c", "ip -br addr | grep -v lo | head -3 | awk '{print $1, $3}' | tr '\n' ' | ' || echo 'N/A'"])

        self.update(
            f"""[bold cyan]System Monitor[/]
[bold]CPU:[/] {cpu}%
[bold]Memory:[/] {mem}
[bold]Disk:[/] {disk}
[bold]Uptime:[/] {uptime}
[bold]Load:[/] {load_str}
[bold]GPU:[/] {gpu.split(',')[0] if ',' in gpu else gpu}
[bold]Network:[/]
  {net}

[dim]Last updated: {datetime.now().strftime('%H:%M:%S')}[/]
"""
        )


class AIStackPanel(Static):
    """AI stack health monitor"""

    def on_mount(self):
        self.set_interval(5, self.refresh_ai)
        self.refresh_ai()

    def refresh_ai(self):
        ollama = run_cmd(["bash", "-c", "ollama list 2>/dev/null | tail -n +2 | head -5 || echo 'Not running'"])
        qdrant = run_cmd(["bash", "-c", "curl -s http://localhost:6333/health 2>/dev/null | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get(\"status\",\"unknown\"))' 2>/dev/null || echo 'Not responding'"])
        models = run_cmd(["bash", "-c", "ollama list 2>/dev/null | awk 'NR>1 {print $1}' | tr '\n' ', ' || echo 'None'"])

        status = "[green]OK[/]" if "running" in ollama.lower() or "Not" not in ollama else "[red]Not running[/]"
        qstatus = "[green]OK[/]" if "ok" in qdrant.lower() else "[red]Not responding[/]"

        self.update(
            f"""[bold magenta]AI Stack Health[/]
[bold]Ollama:[/] {status}
[bold]Models:[/] {models if models != 'None' else 'None loaded'}
[bold]Qdrant:[/] {qstatus}

[dim]Last updated: {datetime.now().strftime('%H:%M:%S')}[/]
"""
        )


class QuickActions(Static):
    """Quick action buttons"""

    def compose(self):
        yield Button("Update System", id="update", variant="primary")
        yield Button("Health Check", id="health", variant="default")
        yield Button("Launch Ollama", id="ollama", variant="success")
        yield Button("Terminal", id="terminal", variant="warning")
        yield Button("Process Tree", id="process", variant="default")
        yield Button("Logs", id="logs", variant="default")

    def on_button_pressed(self, event: Button.Pressed) -> None:
        actions = {
            "update": ["bash", "-c", "kitty -e bash -c 'paru -Syu || pacman -Syu'"],
            "health": ["bash", "-c", "kitty -e ash-doctor check"],
            "ollama": ["bash", "-c", "kitty -e bash -c 'ollama list && echo && read -p \"Press enter to continue...\"'"],
            "terminal": ["kitty"],
            "process": ["bash", "-c", "kitty -e htop"],
            "logs": ["bash", "-c", "kitty -e journalctl -f"],
        }
        cmd = actions.get(event.button.id, ["true"])
        subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


class LogViewer(RichLog):
    """System log viewer"""

    def on_mount(self):
        self.set_interval(10, self.refresh_logs)
        self.refresh_logs()
        self.title = "Recent Logs"

    def refresh_logs(self):
        logs = run_cmd(["bash", "-c", "journalctl -n 20 --no-pager --output=short 2>/dev/null || echo 'No logs'"])

        self.clear()
        self.write("[bold yellow]Recent System Logs[/]")
        self.write("")
        for line in logs.split("\n")[:20]:
            if line.strip():
                self.write(line)


class PackageManager(Static):
    """Package manager frontend"""

    def on_mount(self):
        self.refresh_packages()

    def refresh_packages(self):
        updates = run_cmd(["bash", "-c", "pacman -Qu 2>/dev/null | wc -l || echo 0"])
        total = run_cmd(["bash", "-c", "pacman -Q 2>/dev/null | wc -l || echo 0"])
        aur = run_cmd(["bash", "-c", "pacman -Qm 2>/dev/null | wc -l || echo 0"])

        self.update(
            f"""[bold green]Package Manager[/]
[bold]Total packages:[/] {total}
[bold]AUR packages:[/] {aur}
[bold]Available updates:[/] {updates}

[dim]Run 'ash-doctor check' for package integrity[/]
"""
        )


class AshTUI(App):
    """ash Terminal Dashboard"""

    TITLE = "ash TUI — Terminal Dashboard"
    CSS = """
    Screen {
        background: #1e1e2e;
    }

    Header {
        background: #181825;
        color: #cdd6f4;
    }

    Footer {
        background: #181825;
        color: #cdd6f4;
    }

    Vertical {
        height: 100%;
    }

    Grid {
        grid-size: 2 2;
        grid-gutter: 1;
        padding: 1;
        height: 1fr;
    }

    Static {
        padding: 1;
        border: solid #45475a;
        background: #1e1e2e;
        color: #cdd6f4;
    }

    .panel {
        padding: 1;
        border: solid #45475a;
        background: #1e1e2e;
        height: 100%;
    }

    Button {
        margin: 0 1;
        min-width: 12;
    }

    #quick-actions {
        padding: 1;
        border: solid #45475a;
        background: #1e1e2e;
    }

    #quick-actions Button {
        margin: 1 1;
    }

    RichLog {
        padding: 1;
        border: solid #45475a;
        background: #1e1e2e;
        height: 100%;
    }
    """

    BINDINGS = [
        Binding("q", "quit", "Quit"),
        Binding("r", "refresh", "Refresh"),
        Binding("t", "terminal", "Terminal"),
        Binding("h", "health", "Health Check"),
    ]

    def compose(self):
        yield Header(show_clock=True)
        with Vertical():
            yield SystemMonitor("[bold cyan]System Monitor[/]\nLoading...")
            with TabbedContent():
                with TabPane("AI Stack", id="ai"):
                    yield AIStackPanel()
                with TabPane("Logs", id="logs"):
                    yield LogViewer()
                with TabPane("Packages", id="pkgs"):
                    yield PackageManager()
        with Horizontal(id="quick-actions"):
            yield QuickActions()
        yield Footer()

    def action_refresh(self):
        for child in self.query(SystemMonitor):
            child.refresh_stats()
        for child in self.query(AIStackPanel):
            child.refresh_ai()
        for child in self.query(LogViewer):
            child.refresh_logs()

    def action_terminal(self):
        subprocess.Popen(["kitty"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def action_health(self):
        subprocess.Popen(["kitty", "-e", "ash-doctor", "check"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main():
    try:
        app = AshTUI()
        app.run()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
