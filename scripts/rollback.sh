#!/bin/bash
# =============================================================
# TF05 - Script de Rollback
# Restaura o sistema para o estado de um backup específico
# =============================================================
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log_info()    { echo -e "${CYAN}[INFO]${RESET} $1"; }
log_success() { echo -e "${GREEN}[OK]${RESET}   $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET} $1"; }
log_error()   { echo -e "${RED}[ERR]${RESET}  $1"; }
log_step()    { echo -e "\n${BOLD}${CYAN}══ $1 ══${RESET}"; }

BACKUP_DIR="${1:-}"
ROLLBACK_LOG="logs/rollback_$(date +%Y%m%d_%H%M%S).log"
mkdir -p logs

echo -e "${RED}${BOLD}╔══════════════════════════════════════╗"
echo -e "║   TF05 - ROLLBACK ACIONADO           ║"
echo -e "╚══════════════════════════════════════╝${RESET}"
echo ""

# ── Validar backup ────────────────────────────────────────────
if [ -z "$BACKUP_DIR" ]; then
    log_info "Nenhum backup especificado. Buscando o mais recente..."
    BACKUP_DIR=$(ls -1dt backups/*/ 2>/dev/null | head -1)
    if [ -z "$BACKUP_DIR" ]; then
        log_error "Nenhum backup encontrado em ./backups/"
        exit 1
    fi
fi

if [ ! -d "$BACKUP_DIR" ]; then
    log_error "Diretório de backup não encontrado: $BACKUP_DIR"
    exit 1
fi

log_info "Usando backup: $BACKUP_DIR"

# ── 1. Parar serviços ─────────────────────────────────────────
log_step "Parando Serviços Atuais"
docker-compose down --timeout 30 2>&1 | tee -a "$ROLLBACK_LOG" || true
log_success "Serviços parados"

# ── 2. Restaurar configurações ────────────────────────────────
log_step "Restaurando Configurações"

if [ -d "$BACKUP_DIR/config" ]; then
    cp -r "$BACKUP_DIR/config/." ./config/
    log_success "Configurações restauradas"
else
    log_warn "Nenhuma configuração no backup"
fi

if [ -f "$BACKUP_DIR/docker-compose.yml" ]; then
    cp "$BACKUP_DIR/docker-compose.yml" ./docker-compose.yml
    log_success "docker-compose.yml restaurado"
fi

# ── 3. Restaurar banco de dados ───────────────────────────────
log_step "Restaurando Banco de Dados"

DB_BACKUP="$BACKUP_DIR/database/backup.sql"
if [ -f "$DB_BACKUP" ]; then
    log_info "Restaurando banco de dados..."
    docker-compose up -d database 2>&1 | tee -a "$ROLLBACK_LOG"
    sleep 10
    docker exec tf05-database psql -U monitor -d monitoring < "$DB_BACKUP" 2>&1 | tee -a "$ROLLBACK_LOG"
    log_success "Banco de dados restaurado"
else
    log_warn "Backup do banco não encontrado em $DB_BACKUP"
fi

# ── 4. Restaurar imagens Docker ───────────────────────────────
log_step "Restaurando Imagens Docker"

IMAGES_DIR="$BACKUP_DIR/images"
if [ -d "$IMAGES_DIR" ]; then
    for tar_file in "$IMAGES_DIR"/*.tar; do
        if [ -f "$tar_file" ]; then
            log_info "Carregando imagem: $tar_file"
            docker load < "$tar_file" 2>&1 | tee -a "$ROLLBACK_LOG"
            log_success "Imagem carregada: $(basename "$tar_file" .tar)"
        fi
    done
else
    log_warn "Sem imagens salvas no backup. Usando imagens atuais do registry."
fi

# ── 5. Subir serviços ─────────────────────────────────────────
log_step "Reiniciando Serviços"

docker-compose up -d 2>&1 | tee -a "$ROLLBACK_LOG"
log_info "Aguardando serviços inicializarem..."
sleep 20

# ── 6. Verificar saúde pós-rollback ──────────────────────────
log_step "Verificando Saúde Pós-Rollback"

RETRIES=0
HEALTHY=false
while [ $RETRIES -lt 10 ]; do
    if curl -sf http://localhost:5000/health &>/dev/null; then
        HEALTHY=true
        break
    fi
    RETRIES=$((RETRIES + 1))
    sleep 5
done

if [ "$HEALTHY" = true ]; then
    echo ""
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗"
    echo -e "║   ✓ ROLLBACK CONCLUÍDO COM SUCESSO       ║"
    echo -e "╠══════════════════════════════════════════╣"
    echo -e "║  Backup usado: $BACKUP_DIR"
    echo -e "║  Log:  $ROLLBACK_LOG"
    echo -e "╚══════════════════════════════════════════╝${RESET}"
else
    log_error "Sistema não respondeu após rollback."
    log_error "Intervenção manual necessária."
    log_error "Log completo: $ROLLBACK_LOG"
    exit 1
fi
