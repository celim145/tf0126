/**
 * TF05 - Charts
 * Gráficos de monitoramento com Chart.js
 */

let responseTimeChart = null;
let uptimeChart = null;

function generateTimeLabels(hours = 24, interval = 2) {
    const labels = [];
    const now = new Date();
    for (let i = hours; i >= 0; i -= interval) {
        const d = new Date(now - i * 3600000);
        labels.push(d.getHours().toString().padStart(2, '0') + 'h');
    }
    return labels;
}

function generateResponseData(base, variance, points = 13) {
    return Array.from({ length: points }, () =>
        Math.max(20, Math.floor(base + (Math.random() - 0.5) * variance))
    );
}

function initCharts() {
    const labels = generateTimeLabels();
    const chartDefaults = {
        responsive: true,
        maintainAspectRatio: true,
        plugins: { legend: { display: false } },
        scales: {
            x: {
                grid: { color: 'rgba(30,48,72,.5)', drawBorder: false },
                ticks: { color: '#4a6080', font: { family: "'Space Mono', monospace", size: 10 } }
            },
            y: {
                grid: { color: 'rgba(30,48,72,.5)', drawBorder: false },
                ticks: { color: '#4a6080', font: { family: "'Space Mono', monospace", size: 10 } }
            }
        }
    };

    // ── Response Time Chart ──
    const rtCtx = document.getElementById('responseTimeChart').getContext('2d');
    responseTimeChart = new Chart(rtCtx, {
        type: 'line',
        data: {
            labels,
            datasets: [
                {
                    label: 'Frontend',
                    data: generateResponseData(120, 80),
                    borderColor: '#00e5ff', backgroundColor: 'rgba(0,229,255,.08)',
                    tension: 0.4, fill: true, pointRadius: 3, pointHoverRadius: 5, borderWidth: 2
                },
                {
                    label: 'API',
                    data: generateResponseData(85, 60),
                    borderColor: '#00ff88', backgroundColor: 'rgba(0,255,136,.05)',
                    tension: 0.4, fill: false, pointRadius: 3, pointHoverRadius: 5, borderWidth: 2
                },
                {
                    label: 'Database',
                    data: generateResponseData(40, 30),
                    borderColor: '#ffcc00', backgroundColor: 'rgba(255,204,0,.05)',
                    tension: 0.4, fill: false, pointRadius: 3, pointHoverRadius: 5, borderWidth: 2
                }
            ]
        },
        options: {
            ...chartDefaults,
            plugins: { legend: { display: false } },
            scales: {
                ...chartDefaults.scales,
                y: {
                    ...chartDefaults.scales.y,
                    title: { display: true, text: 'ms', color: '#4a6080', font: { size: 10 } }
                }
            }
        }
    });

    // ── Uptime Chart ──
    const upCtx = document.getElementById('uptimeChart').getContext('2d');
    uptimeChart = new Chart(upCtx, {
        type: 'doughnut',
        data: {
            labels: ['Frontend', 'API', 'Database', 'Redis'],
            datasets: [{
                data: [99.9, 99.8, 100, 98.5],
                backgroundColor: ['rgba(0,229,255,.8)', 'rgba(0,255,136,.8)', 'rgba(255,204,0,.8)', 'rgba(124,58,237,.8)'],
                borderColor: '#0a0e13',
                borderWidth: 3,
                hoverOffset: 8
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            cutout: '65%',
            plugins: {
                legend: {
                    display: true, position: 'bottom',
                    labels: {
                        color: '#4a6080', boxWidth: 10, padding: 12,
                        font: { family: "'Space Mono', monospace", size: 10 }
                    }
                },
                tooltip: {
                    callbacks: {
                        label: ctx => ` ${ctx.label}: ${ctx.parsed}%`
                    }
                }
            }
        }
    });
}

// Chamado pelo dashboard.js a cada refresh
window.updateCharts = function(data) {
    if (!responseTimeChart) return;

    // Adiciona um ponto novo no gráfico de response time
    const services = data.services;
    const now = new Date();
    const label = now.getHours().toString().padStart(2, '0') + ':' + now.getMinutes().toString().padStart(2, '0');

    if (responseTimeChart.data.labels.length > 25) {
        responseTimeChart.data.labels.shift();
        responseTimeChart.data.datasets.forEach(ds => ds.data.shift());
    }

    const frontend = services.find(s => s.name === 'frontend');
    const api = services.find(s => s.name === 'api');
    const db = services.find(s => s.name === 'database');

    responseTimeChart.data.datasets[0].data.push(frontend?.response_time || 0);
    responseTimeChart.data.datasets[1].data.push(api?.response_time || 0);
    responseTimeChart.data.datasets[2].data.push(db?.response_time || 0);
    responseTimeChart.update('none');

    // Atualiza uptime doughnut
    if (uptimeChart) {
        uptimeChart.data.datasets[0].data = services.map(s => parseFloat(s.uptime));
        uptimeChart.data.labels = services.map(s => s.displayName || s.name);
        uptimeChart.update('none');
    }
};

document.addEventListener('DOMContentLoaded', initCharts);
