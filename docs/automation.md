# Documentação de Automação — TF05

## Fluxo Completo de Deploy

```
build.sh → deploy.sh → health-monitor.sh
               ↓ (falha)
           rollback.sh
```

## Scripts Disponíveis

### `scripts/build.sh`
Build automatizado com validação completa.

**O que faz:**
1. Valida ambiente (Docker, docker-compose)
2. Verifica arquivos obrigatórios do projeto
3. Valida sintaxe do `docker-compose.yml`
4. Remove imagens antigas do projeto
5. Executa `docker-compose build --no-cache`
6. Valida imagens geradas

**Uso:**
```bash
./scripts/build.sh
```

**Saída:** Log salvo em `logs/build_TIMESTAMP.log`

---

### `scripts/deploy.sh`
Deploy com zero downtime e rollback automático.

**O que faz:**
1. Cria backup automático via `backup.sh`
2. Executa health check pré-deploy
3. Realiza deploy em ordem de dependência (db → redis → api → dashboard)
4. Aguarda API responder antes de atualizar dashboard
5. Executa verificação pós-deploy
6. Aciona rollback automático em caso de falha

**Uso:**
```bash
./scripts/deploy.sh
```

**Variáveis de ambiente:**
| Variável | Descrição |
|---|---|
| `DOCKER_REGISTRY` | URL do registry (opcional) |

---

### `scripts/rollback.sh`
Restaura o sistema para um backup anterior.

**O que faz:**
1. Para todos os serviços atuais
2. Restaura configurações do backup
3. Restaura banco de dados (dump SQL)
4. Carrega imagens Docker do backup
5. Reinicia todos os serviços
6. Verifica saúde pós-rollback

**Uso:**
```bash
# Rollback para backup específico
./scripts/rollback.sh backups/20260401_120000

# Rollback para o backup mais recente
./scripts/rollback.sh
```

---

### `scripts/backup.sh`
Backup completo antes de cada deploy.

**O que faz:**
1. Copia `config/` para o diretório de backup
2. Exporta dump do PostgreSQL via `pg_dump`
3. Salva imagens Docker em arquivos `.tar`
4. Copia logs da aplicação
5. Gera `manifest.json` com metadados
6. Remove backups antigos (mantém 7 mais recentes)

**Uso:**
```bash
./scripts/backup.sh                    # Backup com timestamp automático
./scripts/backup.sh backups/meu-backup # Backup em diretório específico
```

---

### `scripts/cleanup.sh`
Limpeza de recursos Docker e logs antigos.

**O que faz:**
1. Remove logs com mais de 7 dias
2. Remove imagens Docker dangling
3. Remove volumes órfãos
4. Remove containers parados
5. Remove redes não utilizadas
6. Limpa backups antigos (mantém 5 mais recentes)

**Uso:**
```bash
./scripts/cleanup.sh            # Limpeza padrão
./scripts/cleanup.sh --dry-run  # Simula sem remover nada
./scripts/cleanup.sh --full     # Inclui cache de build (> 48h)
```

---

### `scripts/health-monitor.sh`
Monitoramento manual de todos os serviços.

**Uso:**
```bash
./scripts/health-monitor.sh             # Verificação única
./scripts/health-monitor.sh --watch     # Modo contínuo (30s)
./scripts/health-monitor.sh --report    # Verificação + relatório salvo
./scripts/health-monitor.sh --check-all # Todos os checks + exit code
./scripts/health-monitor.sh --test-alerts  # Testa sistema de alertas
```

## Zero Downtime — Como Funciona

O deploy atualiza os serviços em sequência, respeitando dependências:

```
1. database  (atualiza, aguarda healthcheck)
      ↓
2. redis     (atualiza, aguarda healthcheck)
      ↓
3. api       (atualiza, aguarda resposta HTTP)
      ↓
4. dashboard (atualiza após API estar OK)
```

Durante cada atualização, o container anterior continua respondendo até o novo estar saudável, garantindo zero downtime.
