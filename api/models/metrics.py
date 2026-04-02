"""
TF05 - Model de Métricas
Armazena e recupera dados de monitoramento (em memória + PostgreSQL)
"""

import os
import json
import logging
from datetime import datetime
from collections import defaultdict, deque

logger = logging.getLogger(__name__)


class MetricsStore:
    """
    Armazena métricas dos serviços.
    Usa deque em memória para acesso rápido e tenta persistir no PostgreSQL.
    """

    def __init__(self, max_history=500):
        self.history = defaultdict(lambda: deque(maxlen=max_history))
        self.counters = defaultdict(lambda: {'ok': 0, 'failed': 0})
        self._try_init_db()

    def _try_init_db(self):
        """Tenta conectar ao banco (silencioso em caso de falha)"""
        self._db_available = False
        try:
            import psycopg2
            url = os.getenv('DATABASE_URL', '')
            if url:
                self._conn_str = url
                self._db_available = True
                logger.info("Banco de dados disponível para persistência de métricas")
        except Exception as e:
            logger.warning(f"Banco de dados não disponível: {e}")

    def store(self, service: str, result: dict):
        """Armazena resultado de um healthcheck"""
        result['timestamp'] = result.get('timestamp', datetime.now().isoformat())

        # Atualiza contadores
        if result.get('status') == 'healthy':
            self.counters[service]['ok'] += 1
        else:
            self.counters[service]['failed'] += 1

        # Calcula uptime acumulado
        total = self.counters[service]['ok'] + self.counters[service]['failed']
        result['checks_ok'] = self.counters[service]['ok']
        result['checks_failed'] = self.counters[service]['failed']
        result['uptime'] = round(self.counters[service]['ok'] / total * 100, 2) if total > 0 else 0

        self.history[service].append(result.copy())
        self._persist(service, result)

    def _persist(self, service: str, result: dict):
        """Tenta salvar no PostgreSQL"""
        if not self._db_available:
            return
        try:
            import psycopg2
            with psycopg2.connect(self._conn_str) as conn:
                with conn.cursor() as cur:
                    cur.execute("""
                        INSERT INTO metrics (service, status, response_time, uptime, detail, created_at)
                        VALUES (%s, %s, %s, %s, %s, %s)
                    """, (
                        service,
                        result.get('status'),
                        result.get('response_time', 0),
                        result.get('uptime', 0),
                        result.get('detail', ''),
                        result.get('timestamp')
                    ))
        except Exception as e:
            logger.debug(f"Erro ao persistir métrica: {e}")

    def get_all_latest(self) -> dict:
        """Retorna o último resultado de cada serviço"""
        latest = {}
        for service, hist in self.history.items():
            if hist:
                latest[service] = hist[-1]
        return latest

    def get_history(self, service: str, limit: int = 100) -> list:
        """Retorna histórico de um serviço"""
        hist = list(self.history.get(service, []))
        return hist[-limit:]
