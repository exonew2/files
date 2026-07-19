// ════════════════════════════════════════════════════════════════
// ash — Landing Page Scripts
// Clinical Clean: 4 CSS-only animations, 0 JS animation bytes
// JS only for: copy buttons, modal, mirror verification, torrent
// ════════════════════════════════════════════════════════════════

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
        // Fallback for non-secure contexts
        const textarea = document.createElement('textarea');
        textarea.value = text;
        document.body.appendChild(textarea);
        textarea.select();
        document.execCommand('copy');
        document.body.removeChild(textarea);
        copyToClipboard(text, button); // Retry with feedback
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
function openTerminalModal() {
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

// ── Mirror Verification (Download Page) ──────────────────────
async function verifyMirror(button, url) {
    const original = button.textContent;
    button.textContent = '...';
    button.disabled = true;
    
    try {
        const res = await fetch(url, { method: 'HEAD', mode: 'cors' });
        const checksum = res.headers.get('x-sha256') || 
            await fetch(url + '.sha256').then(r => r.text()).then(t => t.trim().split(' ')[0]).catch(() => null);
        
        const expected = 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2';
        const badge = button.parentElement.querySelector('.verified-badge, .failed-badge');
        
        if (checksum && checksum === expected) {
            button.textContent = 'OK';
            badge.textContent = 'Verified';
            badge.hidden = false;
            badge.className = 'verified-badge';
        } else {
            button.textContent = 'FAIL';
            badge.textContent = 'Mismatch';
            badge.hidden = false;
            badge.className = 'failed-badge';
        }
    } catch {
        button.textContent = 'ERR';
    }
    button.disabled = false;
}

function copyMagnet() {
    const magnet = document.getElementById('magnet-text')?.textContent || 'magnet:?xt=urn:btih:...';
    copyToClipboard(magnet, event.target.closest('button'));
}

function startTorrent() {
    // WebTorrent implementation would go here
    alert('WebTorrent streaming would start here. The magnet link is copied to clipboard.');
    copyMagnet();
}

// ── Tab Navigation (Hypervisor Guides) ───────────────────────
document.addEventListener('click', e => {
    const tab = e.target.closest('[role="tab"]');
    if (!tab) return;
    
    const panelId = tab.getAttribute('aria-controls');
    const tabList = tab.closest('[role="tablist"]');
    
    // Update tabs
    tabList.querySelectorAll('[role="tab"]').forEach(t => {
        t.setAttribute('aria-selected', 'false');
    });
    tab.setAttribute('aria-selected', 'true');
    
    // Update panels
    const container = tabList.parentElement;
    container.querySelectorAll('[role="tabpanel"]').forEach(p => {
        p.hidden = true;
    });
    const panel = container.querySelector(`#${panelId}`);
    if (panel) panel.hidden = false;
});

// ── FAQ Accordion ────────────────────────────────────────────
document.addEventListener('click', e => {
    const btn = e.target.closest('.faq-question');
    if (!btn) return;
    
    const expanded = btn.getAttribute('aria-expanded') === 'true';
    const answer = document.getElementById(btn.getAttribute('aria-controls'));
    
    // Close all others
    document.querySelectorAll('.faq-question').forEach(b => {
        if (b !== btn) {
            b.setAttribute('aria-expanded', 'false');
            const a = document.getElementById(b.getAttribute('aria-controls'));
            if (a) a.hidden = true;
        }
    });
    
    // Toggle this
    btn.setAttribute('aria-expanded', expanded ? 'false' : 'true');
    if (answer) answer.hidden = expanded;
});

// ── Dark Mode Toggle (if needed) ─────────────────────────────
function initDarkMode() {
    const html = document.documentElement;
    const stored = localStorage.getItem('theme');
    const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
    
    if (stored === 'dark' || (!stored && prefersDark)) {
        html.classList.add('dark');
    }
}

// Initialize
document.addEventListener('DOMContentLoaded', () => {
    initDarkMode();
    
    // Animate trust row stars count
    const starsEl = document.querySelector('.stars-count');
    if (starsEl) {
        const target = parseInt(starsEl.dataset.stars);
        let current = 0;
        const increment = target / 50;
        const timer = setInterval(() => {
            current += increment;
            if (current >= target) {
                current = target;
                clearInterval(timer);
            }
            starsEl.textContent = (current / 1000).toFixed(1) + 'k';
        }, 20);
    }
});

// ── Smooth Scroll for Anchor Links ───────────────────────────
document.querySelectorAll('a[href^="#"]').forEach(a => {
    a.addEventListener('click', e => {
        const target = document.querySelector(a.getAttribute('href'));
        if (target) {
            e.preventDefault();
            target.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
    });
});

// ── IntersectionObserver for Reveal Animations (CSS-driven) ──
// The .reveal class animations are CSS-only with animation-delay
// This observer just ensures they fire when scrolled into view
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
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
if (reducedMotion.matches) {
    document.querySelectorAll('.reveal').forEach(el => {
        el.style.animation = 'none';
        el.style.opacity = '1';
        el.style.transform = 'none';
    });
}