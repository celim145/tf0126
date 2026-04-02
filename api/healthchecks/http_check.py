"""
TF05 - Healthcheck HTTP
Verifica endpoints HTTP/HTTPS com métricas de performance
"""

import time
import logging
from datetime import datetime

import requests

logger = logging.getLogger(__name__)

# Thresholds padrão (ms)
THRESHOLD_WARNING = 1000
THRESHOLD_CRITICAL = 5000


class HTTPCheck:
    """
    Healthcheck para endpoints HTTP/HTTPS.
    Verifica: status code, body, tempo de resposta.
    """

    def __init__(self, url: str, timeout: int = 10, expected_status: int = 200,
                 expected_body: str = None, headers: dict = None,
                 warn_ms: int = THRESHOLD_WARNING, critical_ms: int = THRESHOLD_CRITICAL):
        self.url = url
        self.timeout = timeout
        self.expected_status = expected_status
        self.expected_body = expected_body
        self.headers = headers or {}
        self.warn_ms = warn_ms
        self.critical_ms = critical_ms

    def check(self) -> dict:
        """Executa o healthcheck e retorna resultado padronizado"""
        start = time.perf_counter()
        result = {
            'type': 'http',
            'url': self.url,
            'timestamp': datetime.now().isoformat(),
            'response_time': 0,
            'status': 'unknown',
            'detail': ''
        }

        try:
            resp = requests.get(
                self.url,
                timeout=self.timeout,
                headers=self.headers,
                allow_redirects=True
            )
            elapsed_ms = int((time.perf_counter() - start) * 1000)
            result['response_time'] = elapsed_ms
            result['http_status'] = resp.status_code

            # Verifica status code
            if resp.status_code != self.expected_status:
                result['status'] = 'critical'
                result['detail'] = f"HTTP {resp.status_code} (esperado {self.expected_status})"
                return result

            # Verifica body esperado
            if self.expected_body and self.expected_body not in resp.text:
                result['status'] = 'warning'
                result['detail'] = f"Body inesperado: '{resp.text[:100]}'"
                return result

            # Avalia tempo de resposta
            if elapsed_ms >= self.critical_ms:
                result['status'] = 'critical'
                result['detail'] = f"Response time crítico: {elapsed_ms}ms"
            elif elapsed_ms >= self.warn_ms:
                result['status'] = 'warning'
                result['detail'] = f"Response time lento: {elapsed_ms}ms"
            else:
                result['status'] = 'healthy'
                result['detail'] = f"OK ({elapsed_ms}ms)"

        except requests.exceptions.Timeout:
            result['status'] = 'critical'
            result['response_time'] = self.timeout * 1000
            result['detail'] = f"Timeout após {self.timeout}s"
        except requests.exceptions.ConnectionError as e:
            result['status'] = 'critical'
            result['response_time'] = int((time.perf_counter() - start) * 1000)
            result['detail'] = f"Conexão recusada: {str(e)[:100]}"
        except Exception as e:
            result['status'] = 'critical'
            result['detail'] = f"Erro inesperado: {str(e)[:100]}"

        return result
