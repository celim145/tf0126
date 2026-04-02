#!/bin/bash
# =============================================================
# TF05 - Script de Limpeza de Recursos
# Remove logs antigos, imagens dangling, volumes órfãos e backups excessivos
# =============================================================
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log_info()    { echo -e "${CYAN}[INFO]${RESET} $1"; }
log_success() { echo -e "${GREEN}[OK]${RESET}   $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET} $1"; }
log_step()    { echo -e "\n${BOLD}${CYAN}══ $1 ══${RESET}"; }

DRY_RUN=false
[ "$1" = "--dry-run" ] && DRY_RUN=true

echo -e "${BOLD}╔══════════════════════════════════════╗"
echo -e "║   TF05 - Limpeza de Recursos         ║"
echo -e "╚══════════════════════════════════════╝${RESET}"
[ "$DRY_RUN" = true ] && echo -e "  ${YELLOW}MODO DRY-RUN (sem alterações reais)${RESET}"
echo ""

FREED=0

# ── 1. Logs antigos (> 7 dias) ────────────────────────────────
log_step "Limpeza de Logs Antigos"

LOG_DIRS=("logs" "api/logs")
for dir in "${LOG_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        OLD_LOGS=$(find "$dir" -name "*.log" -mtime +7 2>/dev/null | wc -l)
        if [ "$OLD_LOGS" -gt 0 ]; then
            if [ "$DRY_RUN" = false ]; then
                find "$dir" -name "*.log" -mtime +7 -delete
            fi
            log_success "Logs > 7 dias removidos: $OLD_LOGS arquivo(s) em $dir"
        else
            log_info "Nenhum log antigo em $dir"
        fi
    fi
done

# Rotação: manter apenas os 20 logs mais recentes por prefixo
for prefix in build deploy rollback backup; do
    LOG_FILES=$(ls -1t logs/${prefix}_*.log 2>/dev/null | tail -n +21 | wc -l)
    if [ "$LOG_FILES" -gt 0 ]; then
        [ "$DRY_RUN" = false ] && ls -1t logs/${prefix}_*.log | tail -n +21 | xargs rm -f
        log_success "Logs excedentes de '$prefix' removidos: $LOG_FILES"
    fi
done

# ── 2. Imagens Docker dangling ────────────────────────────────
log_step "Limpeza de Imagens Docker"

DANGLING=$(docker images -f "dangling=true" -q | wc -l)
if [ "$DANGLING" -gt 0 ]; then
    DANGLING_SIZE=$(docker images -f "dangling=true" --format "{{.Size}}" | head -1)
    if [ "$DRY_RUN" = false ]; then
        docker image prune -f >> /dev/null 2>&1
    fi
    log_success "Imagens dangling removidas: $DANGLING (≈ $DANGLING_SIZE cada)"
else
    log_info "Sem imagens dangling"
fi

# Imagens antigas do projeto (não a tag mais recente)
for img in tf05-dashboard tf05-api; do
    OLD_IMGS=$(docker images "$img" --format "{{.ID}}" | tail -n +2 | wc -l)
    if [ "$OLD_IMGS" -gt 0 ]; then
        [ "$DRY_RUN" = false ] && docker images "$img" --format "{{.ID}}" | tail -n +2 | xargs -r docker rmi -f 2>/dev/null || true
        log_success "Versões antigas de $img removidas: $OLD_IMGS"
    fi
done

# ── 3. Volumes órfãos ─────────────────────────────────────────
log_step "Limpeza de Volumes"

ORPHAN_VOLS=$(docker volume ls -qf dangling=true | wc -l)
if [ "$ORPHAN_VOLS" -gt 0 ]; then
    if [ "$DRY_RUN" = false ]; then
        docker volume prune -f >> /dev/null 2>&1
    fi
    log_success "Volumes órfãos removidos: $ORPHAN_VOLS"
else
    log_info "Sem volumes órfãos"
fi

# ── 4. Containers parados ─────────────────────────────────────
log_step "Limpeza de Containers Parados"

STOPPED=$(docker ps -aq --filter "status=exited" --filter "status=dead" | wc -l)
if [ "$STOPPED" -gt 0 ]; then
    [ "$DRY_RUN" = false ] && docker container prune -f >> /dev/null 2>&1
    log_success "Containers parados removidos: $STOPPED"
else
    log_info "Sem containers parados"
fi

# ── 5. Redes Docker não utilizadas ───────────────────────────
log_step "Limpeza de Redes"

if [ "$DRY_RUN" = false ]; then
    REMOVED_NETS=$(docker network prune -f 2>&1 | grep -c "Deleted" || true)
    [ "$REMOVED_NETS" -gt 0 ] && log_success "Redes removidas: $REMOVED_NETS" || log_info "Sem redes para remover"
else
    log_info "Dry-run: verificação de redes pulada"
fi

# ── 6. Backups antigos (manter últimos 5) ────────────────────
log_step "Limpeza de Backups"

if [ -d "backups" ]; then
    BACKUP_COUNT=$(ls -1d backups/*/ 2>/dev/null | wc -l)
    if [ "$BACKUP_COUNT" -gt 5 ]; then
        TO_DEL=$((BACKUP_COUNT - 5))
        if [ "$DRY_RUN" = false ]; then
            ls -1dt backups/*/ | tail -"$TO_DEL" | xargs rm -rf
        fi
        log_success "Backups antigos removidos: $TO_DEL (mantidos: 5 mais recentes)"
    else
        log_info "Total de backups: $BACKUP_COUNT (dentro do limite)"
    fi
fi

# ── 7. Cache de build do Docker ───────────────────────────────
log_step "Cache de Build"

if [ "$1" = "--full" ] || [ "$2" = "--full" ]; then
    if [ "$DRY_RUN" = false ]; then
        CACHE_FREED=$(docker builder prune -f --filter "until=48h" 2>&1 | grep "Total reclaimed" | grep -oE '[0-9.]+[KMGB]+' || echo "0B")
        log_success "Cache de build > 48h removido: $CACHE_FREED"
    else
        log_info "Dry-run: cache de build não removido"
    fi
else
    log_info "Use --full para limpar também o cache de build"
fi

# ── Relatório ─────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗"
echo -e "║   ✓ LIMPEZA CONCLUÍDA                    ║"
echo -e "╠══════════════════════════════════════════╣"
echo -e "║  Use --dry-run para simular sem apagar"
echo -e "║  Use --full para limpar cache de build"
echo -e "╚══════════════════════════════════════════╝${RESET}"
