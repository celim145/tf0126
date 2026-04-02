#!/bin/bash
# =============================================================
# TF05 - Script de Backup Automatizado
# Realiza backup de dados, configs e imagens Docker
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
BACKUP_DIR="${1:-backups/$TIMESTAMP}"
BACKUP_LOG="logs/backup_${TIMESTAMP}.log"
mkdir -p "$BACKUP_DIR"/{config,database,images,logs} logs

echo -e "${BOLD}╔══════════════════════════════════════╗"
echo -e "║   TF05 - Backup Automatizado         ║"
echo -e "╚══════════════════════════════════════╝${RESET}"
echo "  Destino: $BACKUP_DIR"
echo ""

# ── 1. Backup de configurações ────────────────────────────────
log_step "Backup de Configurações"

cp -r config/. "$BACKUP_DIR/config/" 2>/dev/null && log_success "config/ salvo" || log_warn "config/ não encontrado"
cp docker-compose.yml "$BACKUP_DIR/docker-compose.yml" 2>/dev/null && log_success "docker-compose.yml salvo" || true

# ── 2. Backup do banco de dados ───────────────────────────────
log_step "Backup do Banco de Dados"

if docker ps --format '{{.Names}}' | grep -q "tf05-database"; then
    log_info "Exportando banco de dados PostgreSQL..."
    docker exec tf05-database pg_dump -U monitor monitoring \
        > "$BACKUP_DIR/database/backup.sql" 2>>"$BACKUP_LOG"
    DUMP_SIZE=$(du -sh "$BACKUP_DIR/database/backup.sql" | cut -f1)
    log_success "Dump do banco: $DUMP_SIZE"
else
    log_warn "Container tf05-database não está rodando. Pulando backup do BD."
fi

# ── 3. Backup das imagens Docker ──────────────────────────────
log_step "Backup das Imagens Docker"

IMAGES=("tf05-dashboard" "tf05-api")
for img in "${IMAGES[@]}"; do
    if docker images --format '{{.Repository}}' | grep -q "^${img}$"; then
        log_info "Salvando imagem: $img"
        docker save "$img" > "$BACKUP_DIR/images/${img}.tar" 2>>"$BACKUP_LOG"
        IMG_SIZE=$(du -sh "$BACKUP_DIR/images/${img}.tar" | cut -f1)
        log_success "$img.tar ($IMG_SIZE)"
    else
        log_warn "Imagem $img não encontrada"
    fi
done

# ── 4. Backup de logs da aplicação ───────────────────────────
log_step "Backup de Logs"

if docker ps --format '{{.Names}}' | grep -q "tf05-api"; then
    docker cp tf05-api:/app/logs/. "$BACKUP_DIR/logs/" 2>/dev/null && log_success "Logs da API copiados" || log_warn "Sem logs para copiar"
fi

# ── 5. Metadados do backup ────────────────────────────────────
log_step "Gerando Metadados"

cat > "$BACKUP_DIR/manifest.json" <<EOF
{
  "backup_timestamp": "$TIMESTAMP",
  "backup_dir": "$BACKUP_DIR",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "docker_version": "$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo 'N/A')",
  "services": $(docker-compose ps --format json 2>/dev/null || echo '[]'),
  "contents": {
    "config": $([ -d "$BACKUP_DIR/config" ] && echo 'true' || echo 'false'),
    "database": $([ -f "$BACKUP_DIR/database/backup.sql" ] && echo 'true' || echo 'false'),
    "images": $(ls "$BACKUP_DIR/images/"*.tar 2>/dev/null | wc -l)
  }
}
EOF
log_success "manifest.json criado"

# ── 6. Limpeza de backups antigos (manter últimos 7) ─────────
log_step "Limpeza de Backups Antigos"

BACKUP_COUNT=$(ls -1d backups/*/ 2>/dev/null | wc -l)
if [ "$BACKUP_COUNT" -gt 7 ]; then
    TO_DELETE=$((BACKUP_COUNT - 7))
    log_info "Removendo $TO_DELETE backup(s) antigo(s)..."
    ls -1dt backups/*/ | tail -"$TO_DELETE" | xargs rm -rf
    log_success "$TO_DELETE backup(s) removido(s)"
else
    log_info "Total de backups: $BACKUP_COUNT (dentro do limite de 7)"
fi

# ── Tamanho total ─────────────────────────────────────────────
TOTAL_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗"
echo -e "║   ✓ BACKUP CONCLUÍDO                     ║"
echo -e "╠══════════════════════════════════════════╣"
echo -e "║  Diretório: $BACKUP_DIR"
echo -e "║  Tamanho:   $TOTAL_SIZE"
echo -e "║  Log:       $BACKUP_LOG"
echo -e "╚══════════════════════════════════════════╝${RESET}"

# Exporta o diretório para uso em outros scripts
echo "$BACKUP_DIR"
