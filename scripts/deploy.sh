#!/bin/bash
# =============================================================
# TF05 - Script de Deploy com Zero Downtime
# Backup → Health check → Deploy → Verificação → Rollback automático
# =============================================================
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log_info()    { echo -e "${CYAN}[INFO]${RESET} $1"; }
log_success() { echo -e "${GREEN}[OK]${RESET}   $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET} $1"; }
log_error()   { echo -e "${RED}[ERR]${RESET}  $1"; }
log_step()    { echo -e "\n${BOLD}${CYAN}══ $1 ══${RESET}"; }

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="backups/$TIMESTAMP"
DEPLOY_LOG="logs/deploy_${TIMESTAMP}.log"
mkdir -p logs

echo -e "${BOLD}╔══════════════════════════════════════╗"
echo -e "║   TF05 - Deploy Automatizado         ║"
echo -e "╚══════════════════════════════════════╝${RESET}"
echo "  Timestamp: $TIMESTAMP"
echo ""

# ── 1. Backup obrigatório antes do deploy ────────────────────
log_step "Backup Pré-Deploy"
log_info "Criando backup em: $BACKUP_DIR"
./scripts/backup.sh "$BACKUP_DIR"
log_success "Backup criado: $BACKUP_DIR"

# ── 2. Health check pré-deploy ───────────────────────────────
log_step "Health Check Pré-Deploy"
log_info "Verificando estado atual dos serviços..."

if ./scripts/health-monitor.sh --check-all --quiet; then
    log_success "Serviços em estado saudável antes do deploy"
else
    log_warn "Serviços com problemas detectados. Continuando deploy..."
fi

# ── 3. Pull de novas imagens (se houver registry) ────────────
log_step "Preparando Novas Imagens"

if [ -n "$DOCKER_REGISTRY" ]; then
    log_info "Baixando imagens do registry: $DOCKER_REGISTRY"
    docker-compose pull 2>&1 | tee -a "$DEPLOY_LOG" || log_warn "Pull falhou, usando imagens locais"
else
    log_info "Usando imagens locais (sem registry configurado)"
fi

# ── 4. Deploy com zero downtime ───────────────────────────────
log_step "Executando Deploy"

deploy_service() {
    local service=$1
    log_info "Atualizando serviço: $service"

    # Recria o container com nova imagem, mantendo outros ativos
    if docker-compose up -d --no-deps "$service" 2>&1 | tee -a "$DEPLOY_LOG"; then
        log_success "$service atualizado"
    else
        log_error "Falha ao atualizar $service"
        return 1
    fi
}

# Deploy em ordem de dependência
deploy_service database
sleep 5
deploy_service redis
sleep 3
deploy_service api
sleep 10

# Verifica saúde da API antes de atualizar o dashboard
log_info "Aguardando API estar pronta..."
RETRIES=0
MAX_RETRIES=12
API_OK=false

while [ $RETRIES -lt $MAX_RETRIES ]; do
    if curl -sf http://localhost:5000/health &>/dev/null; then
        API_OK=true
        break
    fi
    RETRIES=$((RETRIES + 1))
    log_info "Aguardando API... ($RETRIES/$MAX_RETRIES)"
    sleep 5
done

if [ "$API_OK" = true ]; then
    log_success "API respondendo, continuando deploy..."
    deploy_service dashboard
else
    log_error "API não respondeu em tempo hábil. Acionando rollback..."
    ./scripts/rollback.sh "$BACKUP_DIR"
    exit 1
fi

# ── 5. Verificação pós-deploy ─────────────────────────────────
log_step "Verificação Pós-Deploy"

sleep 10
log_info "Executando verificação final dos serviços..."

HEALTH_OK=true
SERVICES=("tf05-dashboard:3000" "tf05-api:5000")

for svc_port in "${SERVICES[@]}"; do
    IFS=':' read -r svc port <<< "$svc_port"
    if curl -sf "http://localhost:$port/health" &>/dev/null || \
       curl -sf "http://localhost:$port" &>/dev/null; then
        log_success "$svc respondendo na porta $port"
    else
        log_error "$svc NÃO está respondendo na porta $port"
        HEALTH_OK=false
    fi
done

# ── 6. Rollback automático se necessário ─────────────────────
if [ "$HEALTH_OK" = false ]; then
    log_error "Deploy falhou na verificação pós-deploy!"
    log_warn "Acionando rollback automático para: $BACKUP_DIR"
    ./scripts/rollback.sh "$BACKUP_DIR"
    exit 1
fi

# ── 7. Relatório de sucesso ───────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗"
echo -e "║   ✓ DEPLOY CONCLUÍDO COM SUCESSO         ║"
echo -e "╠══════════════════════════════════════════╣"
echo -e "║  Backup:    $BACKUP_DIR"
echo -e "║  Log:       $DEPLOY_LOG"
echo -e "║  Dashboard: http://localhost:3000"
echo -e "║  API:       http://localhost:5000"
echo -e "╚══════════════════════════════════════════╝${RESET}"
