#!/bin/bash
# =============================================================
# TF05 - Script de Build Automatizado
# Executa validação de ambiente, testes e build das imagens
# =============================================================
set -e

# ── Cores ────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log_info()    { echo -e "${CYAN}[INFO]${RESET} $1"; }
log_success() { echo -e "${GREEN}[OK]${RESET}   $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET} $1"; }
log_error()   { echo -e "${RED}[ERR]${RESET}  $1"; }
log_step()    { echo -e "\n${BOLD}${CYAN}══ $1 ══${RESET}"; }

BUILD_START=$(date +%s)
BUILD_LOG="logs/build_$(date +%Y%m%d_%H%M%S).log"
mkdir -p logs

echo -e "${BOLD}╔══════════════════════════════════════╗"
echo -e "║   TF05 - Build Automatizado          ║"
echo -e "╚══════════════════════════════════════╝${RESET}"
echo ""

# ── 1. Validar ambiente ───────────────────────────────────────
log_step "Validando Ambiente"

check_cmd() {
    if ! command -v "$1" &>/dev/null; then
        log_error "$1 não encontrado. Instale e tente novamente."
        exit 1
    fi
    log_success "$1 disponível: $(command -v "$1")"
}

check_cmd docker
check_cmd docker-compose 2>/dev/null || check_cmd "docker compose"

# Verificar versão do Docker
DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null)
log_info "Docker versão: $DOCKER_VERSION"

# Verificar espaço em disco (mínimo 2GB)
DISK_FREE=$(df -BG . | awk 'NR==2{print $4}' | tr -d 'G')
if [ "${DISK_FREE:-0}" -lt 2 ]; then
    log_warn "Pouco espaço em disco: ${DISK_FREE}GB livre. Recomendado: 2GB+"
fi

log_success "Validação de ambiente concluída"

# ── 2. Validar arquivos obrigatórios ─────────────────────────
log_step "Verificando Arquivos do Projeto"

REQUIRED_FILES=(
    "docker-compose.yml"
    "dashboard/Dockerfile"
    "dashboard/index.html"
    "api/Dockerfile"
    "api/app.py"
    "database/init.sql"
)

for f in "${REQUIRED_FILES[@]}"; do
    if [ -f "$f" ]; then
        log_success "$f"
    else
        log_error "Arquivo obrigatório não encontrado: $f"
        exit 1
    fi
done

# ── 3. Verificar sintaxe do docker-compose ───────────────────
log_step "Validando docker-compose.yml"

if docker-compose config --quiet 2>/dev/null || docker compose config --quiet 2>/dev/null; then
    log_success "docker-compose.yml válido"
else
    log_error "Erro na sintaxe do docker-compose.yml"
    exit 1
fi

# ── 4. Limpeza pré-build ──────────────────────────────────────
log_step "Limpando Cache de Build"

log_info "Removendo imagens antigas do projeto..."
docker images | grep "tf05" | awk '{print $3}' | xargs -r docker rmi -f 2>/dev/null || true
log_success "Limpeza concluída"

# ── 5. Build das imagens ──────────────────────────────────────
log_step "Construindo Imagens Docker"

log_info "Iniciando build (--no-cache)..."
if docker-compose build --no-cache 2>&1 | tee -a "$BUILD_LOG"; then
    log_success "Build concluído com sucesso"
else
    log_error "Falha no build. Verifique: $BUILD_LOG"
    exit 1
fi

# ── 6. Validar imagens geradas ────────────────────────────────
log_step "Validando Imagens Geradas"

EXPECTED_IMAGES=("tf05-dashboard" "tf05-api")
for img in "${EXPECTED_IMAGES[@]}"; do
    if docker images | grep -q "$img"; then
        SIZE=$(docker images "$img" --format "{{.Size}}" 2>/dev/null | head -1)
        log_success "Imagem: $img ($SIZE)"
    else
        log_warn "Imagem não encontrada: $img"
    fi
done

# ── 7. Relatório final ────────────────────────────────────────
BUILD_END=$(date +%s)
DURATION=$((BUILD_END - BUILD_START))

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗"
echo -e "║   ✓ BUILD CONCLUÍDO COM SUCESSO          ║"
echo -e "╠══════════════════════════════════════════╣"
echo -e "║  Duração:  ${DURATION}s"
echo -e "║  Log:      $BUILD_LOG"
echo -e "║  Próximo:  ./scripts/deploy.sh"
echo -e "╚══════════════════════════════════════════╝${RESET}"
