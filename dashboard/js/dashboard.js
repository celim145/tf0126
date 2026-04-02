/**
 * TF05 - Dashboard de Monitoramento
 * Controle principal da interface
 */

const API_BASE = 'http://localhost:5000';
const REFRESH_INTERVAL = 30; // segundos

let countdown = REFRESH_INTERVAL;
let refreshTimer = null;
let countdownTimer = null;

// ─── Dados simulados (fallback quando API não está disponível) ───
function generateMockData() {
    const services = ['frontend', 'api', 'database', 'redis'];
    const statuses = ['healthy', 'healthy', 'healthy', 'warning'];
    const now = new Date();

    return {
        timestamp: now.toISOString(),
        overall: 'healthy',
        services: services.map((name, i) => ({
            name,
            displayName: { frontend: 'Dashboard Frontend', api: 'Backend API', database: 'PostgreSQL DB', redis: 'Redis Cache' }[name],
            status: statuses[i],
            uptime: (99 + Math.random() * 0.9).toFixed(2),
            response_time: Math.floor(50 + Math.random() * 200),
            checks_ok: Math.floor(280 + Math.random() * 20),
            checks_failed: Math.floor(Math.random() * 3),
            last_check: new Date(now - Math.random() * 30000).toISOString(),
            type: { frontend: 'http', api: 'http', database: 'database', redis: 'tcp' }[name],
            extra: name === 'database' ? { connections: `${Math.floor(10 + Math.random() * 20)}/100` } : {}
        })),
        alerts: generateMockAlerts()
    };
}

function generateMockAlerts() {
    const now = Date.now();
    return [
        { id: 1, level: 'warning', title: 'Response time elevado — API', desc: 'Tempo de resposta acima de 1000ms nos últimos 5 minutos', time: new Date(now - 180000).toISOString() },
        { id: 2, level: 'info', title: 'Deploy realizado com sucesso', desc: 'Nova versão v1.3.2 implantada sem downtime', time: new Date(now - 3600000).toISOString() },
        { id: 3, level: 'resolved', title: 'Redis recuperado', desc: 'Serviço de cache voltou ao normal após reinicialização', time: new Date(now - 7200000).toISOString() },
        { id: 4, level: 'critical', title: 'Falha no healthcheck — Database', desc: 'Timeout após 30s — serviço reiniciado automaticamente', time: new Date(now - 86400000).toISOString() },
    ];
}

// ─── Utilitários ───
function formatTime(iso) {
    if (!iso) return '--';
    const d = new Date(iso);
    const diff = Math.floor((Date.now() - d.getTime()) / 1000);
    if (diff < 60) return `${diff}s atrás`;
    if (diff < 3600) return `${Math.floor(diff / 60)}m atrás`;
    if (diff < 86400) return `${Math.floor(diff / 3600)}h atrás`;
    return d.toLocaleDateString('pt-BR');
}

function statusIcon(status) {
    return { healthy: '✓', warning: '⚠', critical: '✕', unknown: '?' }[status] || '?';
}

function alertIcon(level) {
    return { critical: '🔴', warning: '🟡', info: '🔵', resolved: '🟢' }[level] || '⚪';
}

// ─── Fetch dados da API ───
async function fetchData() {
    try {
        const res = await fetch(`${API_BASE}/health/status`, { signal: AbortSignal.timeout(5000) });
        if (!res.ok) throw new Error('API error');
        return await res.json();
    } catch {
        return generateMockData();
    }
}

// ─── Atualiza UI ───
function updateOverallStatus(data) {
    const banner = document.getElementById('overall-status-banner');
    const text = document.getElementById('overall-status-text');
    const icon = document.getElementById('overall-icon');
    const labels = { healthy: 'Todos os sistemas operacionais', warning: 'Atenção — Degradação detectada', critical: 'Falha crítica detectada' };
    banner.className = `status-banner ${data.overall}`;
    text.textContent = labels[data.overall] || 'Status desconhecido';
    icon.textContent = { healthy: '●', warning: '◉', critical: '◈' }[data.overall] || '●';
    document.getElementById('last-check').textContent = formatTime(data.timestamp);
}

function updateKPIs(data) {
    const active = data.services.filter(s => s.status === 'healthy').length;
    const avgUptime = data.services.reduce((a, s) => a + parseFloat(s.uptime), 0) / data.services.length;
    const avgResp = Math.round(data.services.reduce((a, s) => a + s.response_time, 0) / data.services.length);
    const alertCount = data.alerts.filter(a => a.level !== 'resolved').length;

    document.getElementById('kpi-active').textContent = active;
    document.getElementById('kpi-total').textContent = data.services.length;
    document.getElementById('kpi-uptime').textContent = avgUptime.toFixed(1) + '%';
    document.getElementById('kpi-response').textContent = avgResp + 'ms';
    document.getElementById('kpi-alerts').textContent = alertCount;
}

function updateServicesGrid(services) {
    const grid = document.getElementById('services-grid');
    grid.innerHTML = services.map(s => `
        <div class="service-card ${s.status}">
            <div class="service-header">
                <div class="service-name">${s.displayName}</div>
                <span class="service-badge badge-${s.status}">${s.status.toUpperCase()}</span>
            </div>
            <div class="service-metrics">
                <div class="metric-item">
                    <div class="metric-label">UPTIME</div>
                    <div class="metric-value">${s.uptime}%</div>
                </div>
                <div class="metric-item">
                    <div class="metric-label">RESPONSE TIME</div>
                    <div class="metric-value">${s.response_time}ms</div>
                </div>
                <div class="metric-item">
                    <div class="metric-label">CHECKS OK</div>
                    <div class="metric-value">${s.checks_ok}</div>
                </div>
                <div class="metric-item">
                    <div class="metric-label">CHECKS FALHOS</div>
                    <div class="metric-value">${s.checks_failed}</div>
                </div>
            </div>
            <div class="service-footer">
                Tipo: <strong>${s.type.toUpperCase()}</strong> &nbsp;|&nbsp;
                Último check: <strong>${formatTime(s.last_check)}</strong>
            </div>
        </div>
    `).join('');
}

function updateAlerts(alerts) {
    const list = document.getElementById('alerts-list');
    if (!alerts.length) {
        list.innerHTML = '<div class="no-alerts">✓ Nenhum alerta ativo</div>';
        return;
    }
    list.innerHTML = alerts.map(a => `
        <div class="alert-item ${a.level}">
            <div class="alert-icon">${alertIcon(a.level)}</div>
            <div class="alert-content">
                <div class="alert-title">${a.title}</div>
                <div class="alert-desc">${a.desc}</div>
            </div>
            <div class="alert-time">${formatTime(a.time)}</div>
        </div>
    `).join('');
}

function updateMetricsTable(services) {
    const tbody = document.getElementById('metrics-tbody');
    tbody.innerHTML = services.map(s => `
        <tr>
            <td>${s.displayName}</td>
            <td><span class="dot dot-${s.status}"></span>${s.status}</td>
            <td>${s.response_time}ms</td>
            <td>${s.uptime}%</td>
            <td>${s.checks_ok}</td>
            <td>${s.checks_failed}</td>
            <td>${formatTime(s.last_check)}</td>
        </tr>
    `).join('');
}

// ─── Atualização completa ───
async function refresh() {
    const data = await fetchData();
    updateOverallStatus(data);
    updateKPIs(data);
    updateServicesGrid(data.services);
    updateAlerts(data.alerts);
    updateMetricsTable(data.services);

    // Repassa dados para charts.js
    if (window.updateCharts) window.updateCharts(data);
}

// ─── Relógio ───
function startClock() {
    setInterval(() => {
        const now = new Date();
        document.getElementById('system-time').textContent =
            now.toLocaleTimeString('pt-BR');
    }, 1000);
}

// ─── Countdown ───
function startCountdown() {
    clearInterval(countdownTimer);
    countdown = REFRESH_INTERVAL;
    countdownTimer = setInterval(() => {
        countdown--;
        document.getElementById('countdown').textContent = countdown;
        if (countdown <= 0) {
            refresh();
            countdown = REFRESH_INTERVAL;
        }
    }, 1000);
}

// ─── Navegação ───
function initNav() {
    document.querySelectorAll('.nav-item').forEach(item => {
        item.addEventListener('click', e => {
            e.preventDefault();
            document.querySelectorAll('.nav-item').forEach(i => i.classList.remove('active'));
            document.querySelectorAll('.section').forEach(s => s.classList.remove('active'));
            item.classList.add('active');
            document.getElementById(`section-${item.dataset.section}`).classList.add('active');
        });
    });

    document.getElementById('btn-refresh').addEventListener('click', () => {
        refresh();
        startCountdown();
    });

    document.getElementById('btn-clear-alerts').addEventListener('click', () => {
        document.getElementById('alerts-list').innerHTML = '<div class="no-alerts">✓ Alertas limpos</div>';
    });
}

// ─── Init ───
document.addEventListener('DOMContentLoaded', () => {
    startClock();
    initNav();
    refresh();
    startCountdown();
});
