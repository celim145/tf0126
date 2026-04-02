"""
TF05 - Model de Alertas
Gerencia alertas do sistema com suporte a webhook e email
"""

import os
import json
import logging
import smtplib
from datetime import datetime
from collections import deque
from email.mime.text import MIMEText

import requests

logger = logging.getLogger(__name__)


class AlertManager:
    """
    Gerencia alertas de monitoramento.
    Suporta notificações via webhook e SMTP.
    """

    def __init__(self, max_alerts=200):
        self._alerts = deque(maxlen=max_alerts)
        self._resolved = set()  # serviços com alertas resolvidos
        self._webhook_url = os.getenv('ALERT_WEBHOOK_URL', '')
        self._smtp = {
            'server': os.getenv('SMTP_SERVER', 'smtp.gmail.com'),
            'port': int(os.getenv('SMTP_PORT', 587)),
            'user': os.getenv('SMTP_USER', ''),
            'pass': os.getenv('SMTP_PASS', ''),
        }

    def add(self, service: str, level: str, title: str, description: str = ''):
        """Adiciona novo alerta"""
        alert = {
            'id': len(self._alerts) + 1,
            'service': service,
            'level': level,
            'title': title,
            'desc': description,
            'time': datetime.now().isoformat(),
            'resolved': False
        }
        self._alerts.appendleft(alert)
        logger.warning(f"[ALERT] [{level.upper()}] {title}")
        self._notify(alert)

    def resolve(self, service: str):
        """Marca alertas de um serviço como resolvidos"""
        resolved_count = 0
        for alert in self._alerts:
            if alert['service'] == service and not alert['resolved']:
                alert['resolved'] = True
                alert['level'] = 'resolved'
                resolved_count += 1
        if resolved_count:
            logger.info(f"[ALERT] Serviço {service}: {resolved_count} alerta(s) resolvido(s)")

    def get_recent(self, limit: int = 50, level: str = None) -> list:
        """Retorna alertas recentes"""
        alerts = list(self._alerts)
        if level:
            alerts = [a for a in alerts if a['level'] == level]
        return alerts[:limit]

    def _notify(self, alert: dict):
        """Dispara notificações externas"""
        if self._webhook_url:
            self._send_webhook(alert)
        if self._smtp['user']:
            self._send_email(alert)

    def _send_webhook(self, alert: dict):
        """Envia alerta para Slack/Discord webhook"""
        colors = {'critical': '#ff3b6b', 'warning': '#ffcc00', 'info': '#00e5ff'}
        payload = {
            'attachments': [{
                'color': colors.get(alert['level'], '#ccc'),
                'title': f"[{alert['level'].upper()}] {alert['title']}",
                'text': alert['desc'],
                'footer': f"TF05 Monitor | {alert['time']}",
                'fields': [{'title': 'Serviço', 'value': alert['service'], 'short': True}]
            }]
        }
        try:
            requests.post(self._webhook_url, json=payload, timeout=5)
            logger.info(f"Webhook enviado para {self._webhook_url}")
        except Exception as e:
            logger.error(f"Falha ao enviar webhook: {e}")

    def _send_email(self, alert: dict):
        """Envia alerta por SMTP"""
        recipients = os.getenv('ALERT_EMAIL_RECIPIENTS', '').split(',')
        if not recipients or not recipients[0]:
            return
        try:
            msg = MIMEText(
                f"Serviço: {alert['service']}\n"
                f"Nível: {alert['level'].upper()}\n"
                f"Mensagem: {alert['title']}\n"
                f"Detalhe: {alert['desc']}\n"
                f"Horário: {alert['time']}"
            )
            msg['Subject'] = f"[TF05 Monitor] {alert['level'].upper()}: {alert['title']}"
            msg['From'] = self._smtp['user']
            msg['To'] = ', '.join(recipients)
            with smtplib.SMTP(self._smtp['server'], self._smtp['port']) as smtp:
                smtp.starttls()
                smtp.login(self._smtp['user'], self._smtp['pass'])
                smtp.send_message(msg)
            logger.info(f"Email de alerta enviado para {recipients}")
        except Exception as e:
            logger.error(f"Falha ao enviar email: {e}")
