"""
TF05 - Healthcheck de Banco de Dados
Verifica conectividade e performance do PostgreSQL
"""

import time
import logging
from datetime import datetime

logger = logging.getLogger(__name__)

THRESHOLD_WARNING = 500   # ms
THRESHOLD_CRITICAL = 2000 # ms


class DatabaseCheck:
    """
    Healthcheck para PostgreSQL.
    Executa query de verificação e mede latência.
    """

    def __init__(self, connection_string: str, query: str = 'SELECT 1',
                 timeout: int = 30, warn_ms: int = THRESHOLD_WARNING,
                 critical_ms: int = THRESHOLD_CRITICAL):
        self.connection_string = connection_string
        self.query = query
        self.timeout = timeout
        self.warn_ms = warn_ms
        self.critical_ms = critical_ms

    def check(self) -> dict:
        """Executa verificação de banco de dados"""
        result = {
            'type': 'database',
            'timestamp': datetime.now().isoformat(),
            'response_time': 0,
            'status': 'unknown',
            'detail': ''
        }

        start = time.perf_counter()
        try:
            import psycopg2
            import psycopg2.extras

            conn = psycopg2.connect(self.connection_string, connect_timeout=self.timeout)
            with conn.cursor() as cur:
                cur.execute(self.query)
                row = cur.fetchone()
                conn.close()

            elapsed_ms = int((time.perf_counter() - start) * 1000)
            result['response_time'] = elapsed_ms
            result['query_result'] = str(row)

            if elapsed_ms >= self.critical_ms:
                result['status'] = 'critical'
                result['detail'] = f"Query lenta: {elapsed_ms}ms"
            elif elapsed_ms >= self.warn_ms:
                result['status'] = 'warning'
                result['detail'] = f"Query acima do threshold: {elapsed_ms}ms"
            else:
                result['status'] = 'healthy'
                result['detail'] = f"Conectado. Query OK ({elapsed_ms}ms)"

        except ImportError:
            result['status'] = 'critical'
            result['detail'] = "Driver psycopg2 não instalado"
        except Exception as e:
            elapsed_ms = int((time.perf_counter() - start) * 1000)
            result['response_time'] = elapsed_ms
            result['status'] = 'critical'
            result['detail'] = f"Erro de conexão: {str(e)[:150]}"

        return result
