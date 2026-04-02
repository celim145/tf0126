# Documentação de Healthchecks — TF05

## Tipos de Verificação

### 1. HTTP Check (`http_check.py`)
Verifica endpoints HTTP/HTTPS. Mede:
- Status code da resposta
- Conteúdo esperado no body
- Tempo de resposta (ms)

**Parâmetros:**
| Parâmetro | Descrição | Padrão |
|---|---|---|
| `url` | URL do endpoint | obrigatório |
| `timeout` | Tempo máximo de espera (s) | 10 |
| `expected_status` | HTTP status esperado | 200 |
| `expected_body` | Texto esperado no body | None |
| `headers` | Headers adicionais | {} |
| `warn_ms` | Threshold de aviso (ms) | 1000 |
| `critical_ms` | Threshold crítico (ms) | 5000 |

**Exemplo de uso:**
```python
from healthchecks.http_check import HTTPCheck

check = HTTPCheck(
    url="http://api:5000/health",
    timeout=5,
    expected_status=200,
    warn_ms=500
)
result = check.check()
# result = {'status': 'healthy', 'response_time': 85, ...}
```

---

### 2. Database Check (`db_check.py`)
Verifica conectividade e performance do PostgreSQL. Mede:
- Latência de conexão
- Tempo de execução de query

**Parâmetros:**
| Parâmetro | Descrição | Padrão |
|---|---|---|
| `connection_string` | URL de conexão PostgreSQL | obrigatório |
| `query` | Query de verificação | `SELECT 1` |
| `timeout` | Timeout de conexão (s) | 30 |
| `warn_ms` | Threshold de aviso (ms) | 500 |
| `critical_ms` | Threshold crítico (ms) | 2000 |

**Exemplo de uso:**
```python
from healthchecks.db_check import DatabaseCheck

check = DatabaseCheck(
    connection_string="postgresql://user:pass@db:5432/app",
    query="SELECT COUNT(*) FROM metrics"
)
result = check.check()
```

---

### 3. TCP Check (`custom_check.py`)
Verifica conectividade TCP genérica. Útil para Redis, Memcached, etc. Mede:
- Tempo para estabelecer conexão TCP

**Parâmetros:**
| Parâmetro | Descrição | Padrão |
|---|---|---|
| `host` | Hostname ou IP | obrigatório |
| `port` | Porta TCP | obrigatório |
| `timeout` | Timeout (s) | 5 |
| `warn_ms` | Threshold de aviso (ms) | 200 |
| `critical_ms` | Threshold crítico (ms) | 1000 |

**Exemplo de uso:**
```python
from healthchecks.custom_check import TCPCheck

check = TCPCheck(host="redis", port=6379, timeout=3)
result = check.check()
```

---

## Classificação de Status

| Status | Critério |
|---|---|
| `healthy` | Resposta OK dentro dos thresholds |
| `warning` | Resposta OK mas acima do threshold de aviso |
| `critical` | Sem resposta, erro ou acima do threshold crítico |
| `unknown` | Check ainda não executado |

## Configuração via YAML

Todos os checks são configuráveis via `config/healthchecks.yml`:

```yaml
healthchecks:
  meu-servico:
    type: http         # http | database | tcp
    url: http://...
    interval: 30s
    timeout: 10s
    retries: 3
```

## Histórico e Retenção

- Histórico mantido em memória (últimas 500 amostras por serviço)
- Persistência no PostgreSQL quando disponível
- Retenção no banco: 7 dias (configurável em `config/healthchecks.yml`)
- Uptime calculado cumulativamente desde o início do serviço
