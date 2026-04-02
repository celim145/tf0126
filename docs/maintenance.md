# Documentação de Manutenção — TF05

## Rotinas de Manutenção

### Limpeza de Logs
```bash
# Remoção automática de logs > 7 dias + rotação de arquivos
./scripts/cleanup.sh
```
Logs mantidos: últimos 20 por tipo (`build_`, `deploy_`, `rollback_`, `backup_`).

### Otimização do Banco de Dados
Conecte ao container e execute:
```bash
docker exec -it tf05-database psql -U monitor -d monitoring
```
```sql
-- Analisar tabelas para atualizar estatísticas
ANALYZE metrics;
ANALYZE alerts;
ANALYZE health_history;

-- Recuperar espaço de registros deletados
VACUUM ANALYZE metrics;

-- Ver tamanho das tabelas
SELECT relname, pg_size_pretty(pg_total_relation_size(relid))
FROM pg_stat_user_tables ORDER BY pg_total_relation_size(relid) DESC;

-- Remover métricas com mais de 30 dias
DELETE FROM metrics WHERE created_at < NOW() - INTERVAL '30 days';
```

### Backup Manual
```bash
./scripts/backup.sh
# Backup salvo em: backups/YYYYMMDD_HHMMSS/
```

### Restore Manual
```bash
./scripts/rollback.sh backups/20260401_120000
```

### Monitoramento de Recursos
```bash
# Status em tempo real (atualiza a cada 30s)
./scripts/health-monitor.sh --watch

# Relatório completo salvo em arquivo
./scripts/health-monitor.sh --report
```

## Variáveis de Ambiente

| Variável | Descrição | Padrão |
|---|---|---|
| `DATABASE_URL` | URL de conexão PostgreSQL | `postgresql://monitor:monitor123@database:5432/monitoring` |
| `REDIS_URL` | URL de conexão Redis | `redis://redis:6379` |
| `SECRET_KEY` | Chave secreta da API | `tf05-secret-key-2026` |
| `ALERT_WEBHOOK_URL` | URL do webhook de alertas | vazio |
| `SMTP_SERVER` | Servidor SMTP | `smtp.gmail.com` |
| `SMTP_USER` | Usuário SMTP | vazio |
| `SMTP_PASS` | Senha SMTP | vazio |
| `ALERT_EMAIL_RECIPIENTS` | E-mails separados por vírgula | vazio |

## Troubleshooting

### API não inicia
```bash
docker logs tf05-api
# Verificar se o banco está pronto
docker exec tf05-database pg_isready -U monitor
```

### Dashboard sem dados
```bash
# Verificar se API está acessível
curl http://localhost:5000/health
# Verificar logs do nginx
docker logs tf05-dashboard
```

### Banco de dados não conecta
```bash
docker exec tf05-database psql -U monitor -d monitoring -c "SELECT 1"
# Recriar o container mantendo os dados
docker-compose up -d --force-recreate database
```

### Rollback em emergência
```bash
# Para tudo imediatamente
docker-compose down
# Lista backups disponíveis
ls -lht backups/
# Executa rollback
./scripts/rollback.sh backups/TIMESTAMP
```

## Agenda de Manutenção Sugerida

| Frequência | Tarefa |
|---|---|
| A cada deploy | `backup.sh` (automático) |
| Diário | `cleanup.sh` (via cron) |
| Semanal | `health-monitor.sh --report` |
| Mensal | `VACUUM ANALYZE` no banco |
| Mensal | Revisão de thresholds em `config/thresholds.yml` |

### Cron de exemplo
```cron
# Limpeza diária às 2h
0 2 * * * /caminho/TF05/scripts/cleanup.sh >> /var/log/tf05-cleanup.log 2>&1

# Health report semanal (domingo 8h)
0 8 * * 0 /caminho/TF05/scripts/health-monitor.sh --report >> /var/log/tf05-report.log 2>&1
```
