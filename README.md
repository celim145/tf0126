# TF05 - Sistema de Monitoramento e Automação

## Aluno
- **Nome:** Marcelo Luis dos Santos Raimundo
- **RA:** 6324637
- **Curso:** Análise e Desenvolvimento de Sistemas — 5 semstre

---

## Funcionalidades

- **Healthchecks inteligentes** — HTTP, TCP e Database com métricas de performance
- **Dashboard de monitoramento** em tempo real com gráficos (Chart.js)
- **Sistema de alertas** via webhook e email com thresholds configuráveis
- **Automação completa de deploy** com zero downtime
- **Rollback automático** em caso de falha pós-deploy
- **Scripts de manutenção** — limpeza, backup, relatórios e monitoramento
- **Backup automatizado** antes de cada deploy (com retenção de 7 cópias)
- **Histórico de saúde** persistido em PostgreSQL

---

## Arquitetura

```
┌─────────────┐    ┌─────────────┐    ┌──────────────┐    ┌───────┐
│  Dashboard  │───▶│   API Flask  │───▶│  PostgreSQL  │    │ Redis │
│  (Nginx:80) │    │  (Python:5000│    │  (5432)      │    │(6379) │
└─────────────┘    └─────────────┘    └──────────────┘    └───────┘
       │                  │
       └──────────────────┴── Rede Docker: monitoring
```

---

## Como Executar

### Pré-requisitos
- Docker >= 20.x
- Docker Compose >= 2.x
- Bash >= 4.x
- curl (para health checks)

### Execução Rápida

```bash
# 1. Clonar repositório
git clone https://github.com/celim145/tf0126.git
cd tf0126

# 2. Build automatizado
chmod +x scripts/*.sh
./scripts/build.sh

# 3. Deploy automatizado
./scripts/deploy.sh

# 4. Acessar dashboard
open http://localhost:3000
```

### Subir apenas com Docker Compose
```bash
docker-compose up -d
```

---

## Scripts Disponíveis

| Script | Descrição |
|--------|-----------|
| `./scripts/build.sh` | Build com validação de ambiente e imagens |
| `./scripts/deploy.sh` | Deploy zero-downtime com backup e rollback automático |
| `./scripts/rollback.sh [backup_dir]` | Rollback para versão anterior |
| `./scripts/backup.sh [dest_dir]` | Backup de configs, banco e imagens Docker |
| `./scripts/cleanup.sh [--dry-run] [--full]` | Limpeza de recursos antigos |
| `./scripts/health-monitor.sh [--watch\|--report\|--check-all]` | Monitoramento de saúde |

---

## Endpoints

| Endpoint | Descrição |
|----------|-----------|
| `http://localhost:3000` | Dashboard de monitoramento |
| `http://localhost:5000/health` | Health da API |
| `http://localhost:5000/health/status` | Status completo de todos os serviços |
| `http://localhost:5000/metrics` | Métricas brutas |
| `http://localhost:5000/alerts` | Alertas recentes |

---

## Configuração

| Arquivo | Descrição |
|---------|-----------|
| `config/healthchecks.yml` | Define serviços, intervalos e tipos de check |
| `config/alerts.yml` | Canais de notificação (email, webhook, log) |
| `config/thresholds.yml` | Limites de response time, uptime, CPU, disco, etc. |

### Variáveis de Ambiente (`.env`)
```env
ALERT_WEBHOOK_URL=https://hooks.slack.com/services/xxx
SMTP_USER=alerts@example.com
SMTP_PASS=sua-senha-app
ALERT_EMAIL_RECIPIENTS=admin@example.com,devops@example.com
```

---

## Monitoramento Manual

```bash
# Verificação única de todos os serviços
./scripts/health-monitor.sh

# Modo watch (atualiza a cada 30s)
./scripts/health-monitor.sh --watch

# Relatório completo salvo em arquivo
./scripts/health-monitor.sh --report

# Testar sistema de alertas
./scripts/health-monitor.sh --test-alerts
```

---

## Estrutura do Projeto

```
TF05/
├── README.md
├── docker-compose.yml
├── dashboard/
│   ├── Dockerfile
│   ├── index.html
│   ├── js/
│   │   ├── dashboard.js
│   │   └── charts.js
│   └── css/
│       └── dashboard.css
├── api/
│   ├── Dockerfile
│   ├── app.py
│   ├── requirements.txt
│   ├── models/
│   │   ├── metrics.py
│   │   └── alerts.py
│   └── healthchecks/
│       ├── http_check.py
│       ├── db_check.py
│       └── custom_check.py
├── database/
│   ├── init.sql
│   └── migrations/
├── scripts/
│   ├── build.sh
│   ├── deploy.sh
│   ├── rollback.sh
│   ├── backup.sh
│   ├── cleanup.sh
│   └── health-monitor.sh
├── config/
│   ├── healthchecks.yml
│   ├── alerts.yml
│   └── thresholds.yml
└── docs/
    ├── automation.md
    ├── healthchecks.md
    └── maintenance.md
```

---

## Critérios Atendidos

### Healthchecks (0,8 pt)
- [x] HTTP, TCP e Database implementados (`api/healthchecks/`)
- [x] Configuração via YAML (`config/healthchecks.yml`)
- [x] Métricas de performance (response_time, uptime, checks_ok/failed)
- [x] Histórico de saúde (PostgreSQL + deque em memória)
- [x] Alertas por threshold (webhook + email + log)

### Automação (0,8 pt)
- [x] Script de build completo (`scripts/build.sh`)
- [x] Deploy automatizado com zero downtime (`scripts/deploy.sh`)
- [x] Rollback funcional (`scripts/rollback.sh`)
- [x] Backup automático (`scripts/backup.sh`)
- [x] Limpeza de recursos (`scripts/cleanup.sh`)

### Qualidade Técnica (0,4 pt)
- [x] Dashboard funcional com gráficos em tempo real
- [x] Scripts documentados com comentários e logs coloridos
- [x] Configuração flexível via arquivos YAML e variáveis de ambiente

---

> **Disciplina:** Implementação de Software — UniFAAT  
> **Professor:** Alexandre Tavares  
> **Semestre:** 2026.1
