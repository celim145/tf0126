"""
TF05 - Healthcheck TCP e Personalizado
Verifica conectividade TCP (Redis, bancos, serviços custom)
"""

import time
import socket
import logging
from datetime import datetime

logger = logging.getLogger(__name__)


class TCPCheck:
    """
    Healthcheck TCP genérico.
    Tenta abrir uma conexão TCP na host:port especificada.
    Útil para Redis, Memcached, bancos sem driver, etc.
    """

    def __init__(self, host: str, port: int, timeout: int = 5,
                 warn_ms: int = 200, critical_ms: int = 1000):
        self.host = host
        self.port = port
        self.timeout = timeout
        self.warn_ms = warn_ms
        self.critical_ms = critical_ms

    def check(self) -> dict:
        """Tenta estabelecer conexão TCP"""
        result = {
            'type': 'tcp',
            'host': self.host,
            'port': self.port,
            'timestamp': datetime.now().isoformat(),
            'response_time': 0,
            'status': 'unknown',
            'detail': ''
        }

        start = time.perf_counter()
        try:
            sock = socket.create_connection((self.host, self.port), timeout=self.timeout)
            sock.close()
            elapsed_ms = int((time.perf_counter() - start) * 1000)
            result['response_time'] = elapsed_ms

            if elapsed_ms >= self.critical_ms:
                result['status'] = 'critical'
                result['detail'] = f"Conexão lenta: {elapsed_ms}ms"
            elif elapsed_ms >= self.warn_ms:
                result['status'] = 'warning'
                result['detail'] = f"Conexão acima do threshold: {elapsed_ms}ms"
            else:
                result['status'] = 'healthy'
                result['detail'] = f"TCP OK ({elapsed_ms}ms)"

        except socket.timeout:
            result['status'] = 'critical'
            result['response_time'] = self.timeout * 1000
            result['detail'] = f"Timeout TCP após {self.timeout}s"
        except ConnectionRefusedError:
            result['status'] = 'critical'
            result['response_time'] = int((time.perf_counter() - start) * 1000)
            result['detail'] = f"Conexão recusada em {self.host}:{self.port}"
        except Exception as e:
            result['status'] = 'critical'
            result['detail'] = f"Erro TCP: {str(e)[:100]}"

        return result


class CustomScriptCheck:
    """
    Healthcheck customizável baseado em função Python.
    Permite checks específicos de negócio.
    """

    def __init__(self, name: str, check_fn, timeout: int = 30):
        self.name = name
        self.check_fn = check_fn
        self.timeout = timeout

    def check(self) -> dict:
        """Executa função customizada de healthcheck"""
        result = {
            'type': 'custom',
            'name': self.name,
            'timestamp': datetime.now().isoformat(),
            'response_time': 0,
            'status': 'unknown',
            'detail': ''
        }

        start = time.perf_counter()
        try:
            status, detail = self.check_fn()
            elapsed_ms = int((time.perf_counter() - start) * 1000)
            result['response_time'] = elapsed_ms
            result['status'] = status
            result['detail'] = detail
        except Exception as e:
            result['status'] = 'critical'
            result['detail'] = f"Exceção no check customizado: {str(e)[:150]}"

        return result
