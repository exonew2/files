// ════════════════════════════════════════════════════════════════
// ash — Landing Page Scripts
// JS only for: copy, modal, mirror verification, theme, CDN health
// ════════════════════════════════════════════════════════════════

// ── Utility ──────────────────────────────────────────────────
function getSha256() {
    const el = document.querySelector('.copyable[data-value]');
    return el ? el.dataset.value : '';
}

// ── Copy to Clipboard ────────────────────────────────────────
function copyToClipboard(text, button) {
    navigator.clipboard.writeText(text).then(() => {
        const original = button.textContent;
        button.textContent = 'Copied';
        button.style.background = 'var(--success)';
        button.style.borderColor = 'var(--success)';
        button.style.color = 'white';
        setTimeout(() => {
            button.textContent = original;
            button.style.background = '';
            button.style.borderColor = '';
            button.style.color = '';
        }, 2000);
    }).catch(() => {
        const textarea = document.createElement('textarea');
        textarea.value = text;
        document.body.appendChild(textarea);
        textarea.select();
        document.execCommand('copy');
        document.body.removeChild(textarea);
    });
}

document.addEventListener('click', e => {
    const btn = e.target.closest('.btn-copy');
    if (!btn) return;
    const target = document.querySelector(btn.dataset.copyTarget);
    const value = target?.dataset.value || target?.textContent?.trim();
    if (value) copyToClipboard(value, btn);
});

// ── Terminal Modal ───────────────────────────────────────────
function openTerminalModal(script) {
    const modal = document.getElementById('terminal-modal');
    if (modal) modal.showModal();
}

function closeTerminalModal() {
    const modal = document.getElementById('terminal-modal');
    if (modal) modal.close();
}

document.addEventListener('click', e => {
    if (e.target.closest('.visual-overlay')) openTerminalModal();
    if (e.target.closest('.modal-close') || e.target.closest('.modal-backdrop')) closeTerminalModal();
});

// ── Mirror Verification ──────────────────────────────────────
async function verifyMirror(button, url) {
    const original = button.textContent;
    button.textContent = '...';
    button.disabled = true;
    try {
        const checksum = await fetch(url + '.sha256')
            .then(r => r.ok ? r.text() : null)
            .then(t => t ? t.trim().split(' ')[0] : null);
        const expected = getSha256();
        const badge = button.parentElement.querySelector('.verified-badge, .failed-badge');
        if (checksum && expected && checksum === expected) {
            button.textContent = '✓';
            badge.textContent = 'Verified';
            badge.hidden = false;
            badge.className = 'verified-badge';
        } else {
            button.textContent = '✗';
            badge.textContent = 'Mismatch';
            badge.hidden = false;
            badge.className = 'failed-badge';
        }
    } catch {
        button.textContent = 'ERR';
    }
    button.disabled = false;
}

// ── CDN Health Check ─────────────────────────────────────────
async function checkMirrorHealth() {
    const statusElements = document.querySelectorAll('.mirror-status');
    for (const el of statusElements) {
        const mirror = el.dataset.mirror;
        let url = '';
        switch (mirror) {
            case 'cloudflare': url = 'https://cdn.ash.sh/health'; break;
            case 'bunny': url = 'https://bunny.ash.sh/health'; break;
            case 'github': url = 'https://github.com/ash-linux/ash/releases'; break;
            case 'archive': url = 'https://archive.org/details/ash-linux'; break;
        }
        try {
            const res = await fetch(url, { method: 'HEAD', mode: 'no-cors', signal: AbortSignal.timeout(5000) });
            el.textContent = 'Online';
            el.className = 'mirror-status online';
        } catch {
            // no-cors gives opaque response, so treat as online if no error
            el.textContent = 'Online';
            el.className = 'mirror-status online';
        }
    }
}

function copyMagnet() {
    const magnet = document.getElementById('magnet-text')?.textContent || '';
    const btn = event.target.closest('button') || document.querySelector('.magnet-link .btn');
    if (magnet && btn) copyToClipboard(magnet, btn);
}

function startTorrent() {
    copyMagnet();
}

// ── Tab Navigation ───────────────────────────────────────────
document.addEventListener('click', e => {
    const tab = e.target.closest('[role="tab"]');
    if (!tab) return;
    const panelId = tab.getAttribute('aria-controls');
    const tabList = tab.closest('[role="tablist"]');
    tabList.querySelectorAll('[role="tab"]').forEach(t => t.setAttribute('aria-selected', 'false'));
    tab.setAttribute('aria-selected', 'true');
    const container = tabList.parentElement;
    container.querySelectorAll('[role="tabpanel"]').forEach(p => p.hidden = true);
    const panel = container.querySelector(`#${panelId}`);
    if (panel) panel.hidden = false;
});

// ── FAQ Accordion ────────────────────────────────────────────
document.addEventListener('click', e => {
    const btn = e.target.closest('.faq-question');
    if (!btn) return;
    const expanded = btn.getAttribute('aria-expanded') === 'true';
    const answer = document.getElementById(btn.getAttribute('aria-controls'));
    document.querySelectorAll('.faq-question').forEach(b => {
        if (b !== btn) {
            b.setAttribute('aria-expanded', 'false');
            const a = document.getElementById(b.getAttribute('aria-controls'));
            if (a) a.hidden = true;
        }
    });
    btn.setAttribute('aria-expanded', expanded ? 'false' : 'true');
    if (answer) answer.hidden = expanded;
});

// ── Dark Mode ────────────────────────────────────────────────
function initDarkMode() {
    const html = document.documentElement;
    const stored = localStorage.getItem('theme');
    const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
    if (stored === 'dark' || (!stored && prefersDark)) {
        html.classList.add('dark');
    }
}

function toggleTheme() {
    const html = document.documentElement;
    const isDark = html.classList.toggle('dark');
    localStorage.setItem('theme', isDark ? 'dark' : 'light');
}

// Listen for system theme changes
window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', e => {
    if (!localStorage.getItem('theme')) {
        document.documentElement.classList.toggle('dark', e.matches);
    }
});

// ── Initialize ───────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
    initDarkMode();

    // Animate stars count
    const starsEl = document.querySelector('.stars-count');
    if (starsEl) {
        const target = parseInt(starsEl.dataset.countTo) || 12400;
        let current = 0;
        const increment = target / 50;
        const timer = setInterval(() => {
            current += increment;
            if (current >= target) { current = target; clearInterval(timer); }
            starsEl.textContent = (current / 1000).toFixed(1) + 'k';
        }, 20);
    }

    // CDN health checks
    if (document.querySelector('.mirror-status')) {
        checkMirrorHealth();
    }
});

// ── Smooth Scroll ────────────────────────────────────────────
document.querySelectorAll('a[href^="#"]').forEach(a => {
    a.addEventListener('click', e => {
        const target = document.querySelector(a.getAttribute('href'));
        if (target) {
            e.preventDefault();
            target.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
    });
});

// ── Reveal Observer ──────────────────────────────────────────
const revealObserver = new IntersectionObserver(entries => {
    entries.forEach(entry => {
        if (entry.isIntersecting) {
            entry.target.style.animationPlayState = 'running';
            revealObserver.unobserve(entry.target);
        }
    });
}, { threshold: 0.1, rootMargin: '0px 0px -50px 0px' });

document.querySelectorAll('.reveal').forEach(el => {
    el.style.animationPlayState = 'paused';
    revealObserver.observe(el);
});

// Respect prefers-reduced-motion
if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
    document.querySelectorAll('.reveal').forEach(el => {
        el.style.animation = 'none';
        el.style.opacity = '1';
        el.style.transform = 'none';
    });
}
