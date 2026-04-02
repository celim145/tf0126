"""
TF05 - API de Métricas e Healthchecks
Flask application principal
"""

import os
import json
import logging
from datetime import datetime
from flask import Flask, jsonify, request
from flask_cors import CORS
from apscheduler.schedulers.background import BackgroundScheduler

from healthchecks.http_check import HTTPCheck
from healthchecks.db_check import DatabaseCheck
from healthchecks.custom_check import TCPCheck
from models.metrics import MetricsStore
from models.alerts import AlertManager

# ── Config ──────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[
        logging.FileHandler('logs/api.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)

metrics = MetricsStore()
alerts = AlertManager()

# ── Healthchecks registrados ─────────────────────────────────────
SERVICES = [
    {
        'name': 'frontend',
        'displayName': 'Dashboard Frontend',
        'checker': HTTPCheck('http://dashboard:80/health', timeout=10, expected_status=200),
        'type': 'http',
        'interval': 30
    },
    {
        'name': 'api',
        'displayName': 'Backend API',
        'checker': HTTPCheck('http://localhost:5000/ping', timeout=5, expected_status=200),
        'type': 'http',
        'interval': 15
    },
    {
        'name': 'database',
        'displayName': 'PostgreSQL DB',
        'checker': DatabaseCheck(os.getenv('DATABASE_URL', 'postgresql://monitor:monitor123@database:5432/monitoring')),
        'type': 'database',
        'interval': 60
    },
    {
        'name': 'redis',
        'displayName': 'Redis Cache',
        'checker': TCPCheck(host='redis', port=6379, timeout=5),
        'type': 'tcp',
        'interval': 30
    }
]


def run_checks():
    """Executa todos os healthchecks e armazena resultados"""
    for svc in SERVICES:
        result = svc['checker'].check()
        result['service'] = svc['name']
        result['displayName'] = svc['displayName']
        result['type'] = svc['type']
        metrics.store(svc['name'], result)

        # Alertas automáticos por threshold
        if result['status'] == 'critical':
            alerts.add(svc['name'], 'critical', f"Serviço {svc['displayName']} em estado crítico", result.get('detail', ''))
        elif result['status'] == 'warning':
            alerts.add(svc['name'], 'warning', f"Degradação em {svc['displayName']}", result.get('detail', ''))
        elif result['status'] == 'healthy':
            alerts.resolve(svc['name'])

        logger.info(f"[CHECK] {svc['name']}: {result['status']} ({result.get('response_time', 0)}ms)")


# ── Rotas ────────────────────────────────────────────────────────
@app.route('/ping')
def ping():
    return jsonify({'status': 'ok', 'timestamp': datetime.now().isoformat()})


@app.route('/health')
def health():
    return jsonify({'status': 'healthy', 'service': 'tf05-api', 'timestamp': datetime.now().isoformat()})


@app.route('/health/status')
def health_status():
    """Status completo de todos os serviços"""
    all_metrics = metrics.get_all_latest()
    overall = 'healthy'
    if any(m.get('status') == 'critical' for m in all_metrics.values()):
        overall = 'critical'
    elif any(m.get('status') == 'warning' for m in all_metrics.values()):
        overall = 'warning'

    services_list = []
    for svc in SERVICES:
        m = all_metrics.get(svc['name'], {})
        services_list.append({
            'name': svc['name'],
            'displayName': svc['displayName'],
            'type': svc['type'],
            'status': m.get('status', 'unknown'),
            'uptime': m.get('uptime', 0),
            'response_time': m.get('response_time', 0),
            'checks_ok': m.get('checks_ok', 0),
            'checks_failed': m.get('checks_failed', 0),
            'last_check': m.get('timestamp', None),
        })

    return jsonify({
        'timestamp': datetime.now().isoformat(),
        'overall': overall,
        'services': services_list,
        'alerts': alerts.get_recent(20)
    })


@app.route('/metrics')
def get_metrics():
    """Métricas brutas de todos os serviços"""
    return jsonify(metrics.get_all_latest())


@app.route('/metrics/<service>')
def get_service_metrics(service):
    """Histórico de um serviço específico"""
    history = metrics.get_history(service, limit=100)
    return jsonify({'service': service, 'history': history})


@app.route('/alerts')
def get_alerts():
    level = request.args.get('level')
    limit = int(request.args.get('limit', 50))
    return jsonify(alerts.get_recent(limit, level=level))


@app.route('/alerts', methods=['POST'])
def create_alert():
    data = request.json
    alerts.add(data.get('service', 'manual'), data.get('level', 'info'), data.get('title'), data.get('description', ''))
    return jsonify({'created': True}), 201


@app.route('/healthchecks/run', methods=['POST'])
def trigger_check():
    """Dispara checks manualmente"""
    run_checks()
    return jsonify({'triggered': True, 'timestamp': datetime.now().isoformat()})


# ── Scheduler ────────────────────────────────────────────────────
def start_scheduler():
    scheduler = BackgroundScheduler()
    scheduler.add_job(run_checks, 'interval', seconds=15, id='healthchecks')
    scheduler.start()
    logger.info("Scheduler de healthchecks iniciado (intervalo: 15s)")
    return scheduler


if __name__ == '__main__':
    logger.info("Iniciando TF05 API de Monitoramento...")
    run_checks()  # Check inicial
    scheduler = start_scheduler()
    try:
        app.run(host='0.0.0.0', port=5000, debug=False)
    finally:
        scheduler.shutdown()
