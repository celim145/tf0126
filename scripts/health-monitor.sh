#!/bin/bash
# =============================================================
# TF05 - Script de Monitoramento de Saúde
# Verificação de todos os serviços com relatórios e alertas
# =============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log_info()    { echo -e "${CYAN}[INFO]${RESET} $1"; }
log_success() { echo -e "${GREEN}[OK]${RESET}   $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET} $1"; }
log_error()   { echo -e "${RED}[FAIL]${RESET} $1"; }
log_step()    { echo -e "\n${BOLD}${CYAN}══ $1 ══${RESET}"; }

# ── Configuração de thresholds ────────────────────────────────
THRESHOLD_WARN_MS=1000
THRESHOLD_CRIT_MS=5000
THRESHOLD_WARN_UPTIME=95
THRESHOLD_CRIT_UPTIME=90

API_URL="http://localhost:5000"
DASHBOARD_URL="http://localhost:3000"
DB_CONTAINER="tf05-database"
REDIS_CONTAINER="tf05-redis"

FAILED_CHECKS=0
WARN_CHECKS=0

# ── Funções de check ──────────────────────────────────────────
check_http() {
    local name="$1" url="$2"
    local start end elapsed http_code

    start=$(date +%s%N)
    http_code=$(curl -sf -o /dev/null -w "%{http_code}" --max-time 10 "$url" 2>/dev/null || echo "000")
    end=$(date +%s%N)
    elapsed=$(( (end - start) / 1000000 ))

    if [ "$http_code" = "000" ]; then
        log_error "$name — CRÍTICO: sem resposta (timeout/recusa)"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 2
    elif [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
        if [ "$elapsed" -ge "$THRESHOLD_CRIT_MS" ]; then
            log_warn "$name — AVISO: HTTP $http_code mas lento (${elapsed}ms)"
            WARN_CHECKS=$((WARN_CHECKS + 1))
            return 1
        else
            log_success "$name — HTTP $http_code (${elapsed}ms)"
            return 0
        fi
    else
        log_error "$name — CRÍTICO: HTTP $http_code (${elapsed}ms)"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 2
    fi
}

check_container() {
    local name="$1" container="$2"
    local state

    state=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "not_found")

    case "$state" in
        "running")   log_success "$name — Container rodando"; return 0 ;;
        "not_found") log_error "$name — Container não encontrado"; FAILED_CHECKS=$((FAILED_CHECKS + 1)); return 2 ;;
        *)           log_error "$name — Container em estado: $state"; FAILED_CHECKS=$((FAILED_CHECKS + 1)); return 2 ;;
    esac
}

check_db_query() {
    local result
    result=$(docker exec "$DB_CONTAINER" psql -U monitor -d monitoring -t -c "SELECT 1" 2>/dev/null || echo "")
    if echo "$result" | grep -q "1"; then
        log_success "Database — Query SELECT 1 OK"
        return 0
    else
        log_error "Database — Falha na query de verificação"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 2
    fi
}

check_redis_ping() {
    local result
    result=$(docker exec "$REDIS_CONTAINER" redis-cli ping 2>/dev/null || echo "")
    if echo "$result" | grep -q "PONG"; then
        log_success "Redis — PONG recebido"
        return 0
    else
        log_error "Redis — Sem resposta ao PING"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 2
    fi
}

system_resources() {
    log_step "Recursos do Sistema"

    # CPU
    CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | tr -d '%us,' 2>/dev/null || echo "N/A")
    log_info "CPU Usage: ${CPU}%"

    # Memória
    MEM=$(free -h | awk 'NR==2{printf "%s/%s (%.0f%%)", $3,$2,$3/$2*100}' 2>/dev/null || echo "N/A")
    log_info "Memória: $MEM"

    # Disco
    DISK=$(df -h . | awk 'NR==2{printf "%s usado de %s (%s)", $3,$2,$5}' 2>/dev/null || echo "N/A")
    log_info "Disco: $DISK"

    # Docker
    CONTAINERS_RUNNING=$(docker ps -q | wc -l)
    log_info "Containers ativos: $CONTAINERS_RUNNING"
}

generate_report() {
    local REPORT_FILE="logs/health_report_$(date +%Y%m%d_%H%M%S).txt"
    mkdir -p logs

    {
        echo "============================================"
        echo " TF05 - Relatório de Saúde"
        echo " Gerado em: $(date '+%d/%m/%Y %H:%M:%S')"
        echo "============================================"
        echo ""
        echo "SERVIÇOS:"
        echo "  Dashboard:  $DASHBOARD_URL"
        echo "  API:        $API_URL"
        echo "  Database:   $DB_CONTAINER"
        echo "  Redis:      $REDIS_CONTAINER"
        echo ""
        echo "RESULTADO:"
        echo "  Checks com falha:  $FAILED_CHECKS"
        echo "  Checks com aviso:  $WARN_CHECKS"
        echo ""
        echo "RECURSOS DO SISTEMA:"
        free -h 2>/dev/null || echo "  N/A"
        echo ""
        df -h . 2>/dev/null || echo "  N/A"
        echo ""
        echo "CONTAINERS DOCKER:"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "  N/A"
    } > "$REPORT_FILE"

    echo ""
    log_success "Relatório salvo: $REPORT_FILE"
    cat "$REPORT_FILE"
}

run_all_checks() {
    echo -e "${BOLD}╔══════════════════════════════════════╗"
    echo -e "║   TF05 - Health Monitor              ║"
    echo -e "╚══════════════════════════════════════╝${RESET}"
    echo "  $(date '+%d/%m/%Y %H:%M:%S')"

    log_step "Verificações HTTP"
    check_http "Dashboard" "$DASHBOARD_URL"
    check_http "API Health" "$API_URL/health"
    check_http "API Metrics" "$API_URL/metrics"

    log_step "Verificações de Containers"
    check_container "Dashboard Container" "tf05-dashboard"
    check_container "API Container" "tf05-api"
    check_container "Database Container" "$DB_CONTAINER"
    check_container "Redis Container" "$REDIS_CONTAINER"

    log_step "Verificações de Serviços Internos"
    check_db_query
    check_redis_ping
}

# ── Modo watch ────────────────────────────────────────────────
watch_mode() {
    log_info "Modo watch ativado (Ctrl+C para sair)..."
    while true; do
        clear
        FAILED_CHECKS=0; WARN_CHECKS=0
        run_all_checks

        TOTAL=$((FAILED_CHECKS + WARN_CHECKS))
        echo ""
        if [ "$FAILED_CHECKS" -gt 0 ]; then
            echo -e "${RED}${BOLD}SISTEMA COM FALHAS: $FAILED_CHECKS crítico(s), $WARN_CHECKS aviso(s)${RESET}"
        elif [ "$WARN_CHECKS" -gt 0 ]; then
            echo -e "${YELLOW}${BOLD}ATENÇÃO: $WARN_CHECKS aviso(s) detectado(s)${RESET}"
        else
            echo -e "${GREEN}${BOLD}✓ TODOS OS SERVIÇOS SAUDÁVEIS${RESET}"
        fi

        echo -e "\n${CYAN}Próxima verificação em 30s...${RESET}"
        sleep 30
    done
}

test_alerts() {
    log_step "Testando Sistema de Alertas"
    log_info "Disparando alerta de teste via API..."
    curl -sf -X POST "$API_URL/alerts" \
        -H "Content-Type: application/json" \
        -d '{"service":"test","level":"info","title":"Teste de Alerta","description":"Alerta disparado via health-monitor.sh --test-alerts"}' \
        && log_success "Alerta de teste enviado" \
        || log_error "Falha ao enviar alerta de teste (API offline?)"
}

# ── Parser de argumentos ──────────────────────────────────────
case "${1:-}" in
    --watch)         watch_mode ;;
    --report)        run_all_checks; generate_report ;;
    --test-alerts)   test_alerts ;;
    --check-all)
        run_all_checks
        system_resources
        echo ""
        if [ "$FAILED_CHECKS" -gt 0 ]; then
            [ "${2}" != "--quiet" ] && echo -e "${RED}${BOLD}FALHAS: $FAILED_CHECKS${RESET}"
            exit 1
        elif [ "$WARN_CHECKS" -gt 0 ]; then
            [ "${2}" != "--quiet" ] && echo -e "${YELLOW}${BOLD}AVISOS: $WARN_CHECKS${RESET}"
            exit 0
        else
            [ "${2}" != "--quiet" ] && echo -e "${GREEN}${BOLD}✓ TODOS OS SERVIÇOS SAUDÁVEIS${RESET}"
            exit 0
        fi
        ;;
    --pre-deploy)
        log_step "Health Check Pré-Deploy"
        run_all_checks
        [ "$FAILED_CHECKS" -gt 0 ] && exit 1 || exit 0
        ;;
    --quiet)
        FAILED_CHECKS=0; WARN_CHECKS=0
        run_all_checks > /dev/null 2>&1
        [ "$FAILED_CHECKS" -gt 0 ] && exit 1 || exit 0
        ;;
    *)
        run_all_checks
        system_resources
        echo ""
        if [ "$FAILED_CHECKS" -gt 0 ]; then
            echo -e "${RED}${BOLD}Resultado: $FAILED_CHECKS crítico(s), $WARN_CHECKS aviso(s)${RESET}"
            exit 1
        else
            echo -e "${GREEN}${BOLD}✓ Todos os serviços OK${RESET}"
        fi
        ;;
esac
