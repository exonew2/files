class TerminalDemo {
    constructor(container) {
        this.container = container;
        this.buffer = [];
        this.running = false;
        this.cancelled = false;
        this.scripts = {
            ollama: {
                prompt: 'aiuser@ash:~$ ',
                lines: [
                    { text: 'ollama run llama3.1', type: 'command', speed: 40 },
                    { text: '', type: 'output', speed: 1 },
                    { text: 'pulling manifest', type: 'output', speed: 30 },
                    { text: 'pulling 8a8e0c8a9e3a... 100% |████████████| 4.7 GB', type: 'output', speed: 20 },
                    { text: 'pulling 6b4b9e3c8a9e... 100% |████████████| 1.2 GB', type: 'output', speed: 20 },
                    { text: 'verifying sha256 digest', type: 'output', speed: 30 },
                    { text: 'writing manifest', type: 'output', speed: 30 },
                    { text: 'removing any unused layers', type: 'output', speed: 30 },
                    { text: 'success', type: 'success', speed: 40 },
                    { text: '', type: 'output', speed: 1 },
                    { text: '>>> Hello! How can I help you today?', type: 'output', speed: 40 },
                    { text: '>>> Write a Python function to search vectors', type: 'output', speed: 40 },
                    { text: '', type: 'output', speed: 1 },
                    { text: 'Here is a vector search function using Qdrant:', type: 'output', speed: 50 },
                    { text: '', type: 'output', speed: 1 },
                    { text: '  import qdrant_client', type: 'code', speed: 30 },
                    { text: '  from qdrant_client.models import Filter, FieldCondition, MatchValue', type: 'code', speed: 30 },
                    { text: '', type: 'output', speed: 1 },
                    { text: '  client = qdrant_client.QdrantClient("localhost", port=6333)', type: 'code', speed: 35 },
                    { text: '  result = client.search(', type: 'code', speed: 35 },
                    { text: '      collection_name="documents",', type: 'code', speed: 35 },
                    { text: '      query_vector=embedding,', type: 'code', speed: 35 },
                    { text: '      limit=10,', type: 'code', speed: 35 },
                    { text: '      score_threshold=0.5', type: 'code', speed: 35 },
                    { text: '  )', type: 'code', speed: 35 },
                    { text: '', type: 'output', speed: 1 },
                    { text: 'Result: 3 matches found in 12ms', type: 'success', speed: 50 },
                ]
            },
            lsfs: {
                prompt: 'aiuser@ash:~$ ',
                lines: [
                    { text: 'lsfs --search "python files about AI"', type: 'command', speed: 40 },
                    { text: '', type: 'output', speed: 1 },
                    { text: 'Routing query through local LLM (nomic-embed-text)...', type: 'info', speed: 30 },
                    { text: 'Semantic search in Qdrant collection: documents', type: 'info', speed: 30 },
                    { text: '', type: 'output', speed: 1 },
                    { text: 'Top 3 results:', type: 'output', speed: 40 },
                    { text: '', type: 'output', speed: 1 },
                    { text: '  [1] /home/aiuser/projects/vector_search.py', type: 'output', speed: 30 },
                    { text: '      AI Match: Semantic vector search implementation', type: 'dim', speed: 30 },
                    { text: '      Confidence: 0.94', type: 'dim', speed: 30 },
                    { text: '      Modified: 2025-01-14 14:32', type: 'dim', speed: 30 },
                    { text: '', type: 'output', speed: 1 },
                    { text: '  [2] /home/aiuser/projects/rag_pipeline.py', type: 'output', speed: 30 },
                    { text: '      AI Match: RAG pipeline with Ollama + Qdrant', type: 'dim', speed: 30 },
                    { text: '      Confidence: 0.87', type: 'dim', speed: 30 },
                    { text: '      Modified: 2025-01-13 09:15', type: 'dim', speed: 30 },
                    { text: '', type: 'output', speed: 1 },
                    { text: '  [3] /home/aiuser/projects/embedding_utils.py', type: 'output', speed: 30 },
                    { text: '      AI Match: Embedding generation utilities', type: 'dim', speed: 30 },
                    { text: '      Confidence: 0.76', type: 'dim', speed: 30 },
                    { text: '      Modified: 2025-01-12 16:48', type: 'dim', speed: 30 },
                    { text: '', type: 'output', speed: 1 },
                    { text: 'Found 3 results in 156ms (semantic) + 2ms (metadata filter)', type: 'success', speed: 50 },
                ]
            },
            snapper: {
                prompt: 'aiuser@ash:~$ ',
                lines: [
                    { text: 'snapper list', type: 'command', speed: 40 },
                    { text: '', type: 'output', speed: 1 },
                    { text: '  # | Type   | Pre # | Date                | User | Description', type: 'dim', speed: 20 },
                    { text: '  ──┼────────┼───────┼─────────────────────┼──────┼──────────────────────', type: 'dim', speed: 20 },
                    { text: '  0 | single |       | 2025-01-15 10:00   | root | current', type: 'output', speed: 30 },
                    { text: '  1 | pre    |       | 2025-01-15 09:55   | root | pacman -Syu pre', type: 'output', speed: 30 },
                    { text: '  2 | post   |     1 | 2025-01-15 09:56   | root | pacman -Syu post', type: 'output', speed: 30 },
                    { text: '  3 | pre    |       | 2025-01-15 08:00   | root | hourly', type: 'output', speed: 30 },
                    { text: '  4 | pre    |       | 2025-01-14 22:00   | root | daily', type: 'output', speed: 30 },
                    { text: '  5 | pre    |       | 2025-01-13 06:00   | root | daily', type: 'output', speed: 30 },
                    { text: '', type: 'output', speed: 1 },
                    { text: 'Rollback: sudo snapper undochange 2..0', type: 'info', speed: 50 },
                ]
            },
            status: {
                prompt: 'aiuser@ash:~$ ',
                lines: [
                    { text: 'ash --status', type: 'command', speed: 40 },
                    { text: '', type: 'output', speed: 1 },
                    { text: '  ash version     2025.01.15', type: 'output', speed: 30 },
                    { text: '  uptime          47 minutes', type: 'output', speed: 30 },
                    { text: '  desktop         GNOME 47 (Xorg)', type: 'output', speed: 30 },
                    { text: '  kernel          6.8.7-arch1-1', type: 'output', speed: 30 },
                    { text: '  memory          1.2 GB / 7.8 GB', type: 'output', speed: 30 },
                    { text: '  disk            6.5 GB / 49.2 GB', type: 'output', speed: 30 },
                    { text: '', type: 'output', speed: 1 },
                    { text: '  Services:', type: 'output', speed: 30 },
                    { text: '  ● ollama         active (running)  v0.5.4', type: 'success', speed: 30 },
                    { text: '  ● qdrant         active (running)  v1.10.0', type: 'success', speed: 30 },
                    { text: '  ● snapper        active (running)  timeline', type: 'success', speed: 30 },
                    { text: '  ● sshd           active (running)  port 22', type: 'success', speed: 30 },
                    { text: '  ● docker         active (running)  v26.0.0', type: 'success', speed: 30 },
                    { text: '', type: 'output', speed: 1 },
                    { text: '  Snapshots: 24 available (latest: 5 min ago)', type: 'info', speed: 40 },
                    { text: '  AI models: 3 installed (llama3.1, nomic-embed-text, codellama)', type: 'info', speed: 40 },
                ]
            }
        };
    }

    play(scriptName) {
        if (this.running) return;
        const script = this.scripts[scriptName];
        if (!script) return;

        this.running = true;
        this.cancelled = false;
        this.container.innerHTML = '';
        this.container.style.cssText = 'background: #1E1E1E; border-radius: 8px; padding: 20px; font-family: "JetBrains Mono", "Fira Code", monospace; font-size: 14px; line-height: 1.6; color: #D4D4D4; max-height: 60vh; overflow-y: auto; white-space: pre-wrap; word-break: break-all;';

        const promptEl = document.createElement('span');
        promptEl.style.color = '#4AF626';
        promptEl.textContent = script.prompt;
        this.container.appendChild(promptEl);

        this._typeLines(script.lines, 0, () => {
            this.running = false;
            const cursor = document.createElement('span');
            cursor.className = 'terminal-cursor';
            cursor.style.cssText = 'display: inline-block; width: 8px; height: 16px; background: #4AF626; animation: blink 1s step-end infinite; margin-left: 4px; vertical-align: text-bottom;';
            this.container.appendChild(cursor);
        });
    }

    _typeLines(lines, index, callback) {
        if (this.cancelled || index >= lines.length) {
            if (callback) callback();
            return;
        }

        const line = lines[index];
        const el = document.createElement('div');
        const colorMap = {
            command: '#4AF626',
            output: '#D4D4D4',
            success: '#4AF626',
            info: '#569CD6',
            dim: '#808080',
            code: '#CE9178'
        };
        el.style.color = colorMap[line.type] || '#D4D4D4';
        el.style.minHeight = '1.6em';

        if (line.type === 'command') {
            this._typeText(el, line.text, 0, line.speed || 40, () => {
                const newPrompt = document.createElement('div');
                newPrompt.style.color = '#4AF626';
                newPrompt.textContent = this.scripts[Object.keys(this.scripts).find(k => this.scripts[k].prompt === this.scripts[Object.keys(this.scripts)[0]].prompt)]?.prompt || 'aiuser@ash:~$ ';
                // Get the current script's prompt
                for (const key in this.scripts) {
                    const s = this.scripts[key];
                    if (s.lines === lines) {
                        newPrompt.textContent = s.prompt;
                        break;
                    }
                }
                newPrompt.textContent = 'aiuser@ash:~$ ';
                this.container.appendChild(el);
                setTimeout(() => this._typeLines(lines, index + 1, callback), 100);
            });
            return;
        }

        if (line.text === '') {
            el.innerHTML = '&nbsp;';
            this.container.appendChild(el);
            setTimeout(() => this._typeLines(lines, index + 1, callback), 50);
            return;
        }

        this._typeText(el, line.text, 0, line.speed || 30, () => {
            this.container.appendChild(el);
            this.container.scrollTop = this.container.scrollHeight;
            setTimeout(() => this._typeLines(lines, index + 1, callback), 80);
        });
    }

    _typeText(el, text, idx, speed, callback) {
        if (this.cancelled) { if (callback) callback(); return; }
        if (idx >= text.length) { if (callback) callback(); return; }

        el.textContent += text[idx];
        this.container.scrollTop = this.container.scrollHeight;
        setTimeout(() => this._typeText(el, text, idx + 1, speed, callback), speed);
    }

    stop() {
        this.cancelled = true;
        this.running = false;
    }
}

let activeDemo = null;

function openTerminalModal(scriptName) {
    const modal = document.getElementById('terminal-modal');
    if (!modal) return;

    const terminalEl = document.getElementById('terminal-container');
    if (!terminalEl) return;

    if (activeDemo) activeDemo.stop();

    modal.showModal();
    terminalEl.innerHTML = '';

    const style = document.createElement('style');
    style.textContent = `
        @keyframes blink { 50% { opacity: 0; } }
        #terminal-container { background: #1E1E1E; }
    `;
    terminalEl.appendChild(style);

    activeDemo = new TerminalDemo(terminalEl);
    setTimeout(() => activeDemo.play(scriptName || 'ollama'), 300);
}

function closeTerminalModal() {
    const modal = document.getElementById('terminal-modal');
    if (modal) modal.close();
    if (activeDemo) activeDemo.stop();
}

document.addEventListener('click', e => {
    if (e.target.closest('.visual-overlay')) openTerminalModal('ollama');
    if (e.target.closest('.modal-close') || e.target.closest('.modal-backdrop')) closeTerminalModal();
    // Script selector buttons
    const scriptBtn = e.target.closest('[data-terminal-script]');
    if (scriptBtn) {
        e.preventDefault();
        openTerminalModal(scriptBtn.dataset.terminalScript);
    }
});

document.addEventListener('DOMContentLoaded', () => {
    document.addEventListener('keydown', e => {
        if (e.key === 'Escape') closeTerminalModal();
    });
});
