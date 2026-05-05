#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'; BLU='\033[0;34m'; MAG='\033[0;35m'; DIM='\033[2m'; RST='\033[0m'

step() { echo -e "${YLW}▶ $*${RST}"; }
info() { echo -e "${BLU}  i  $*${RST}"; }
ok() { echo -e "${GRN}  ok  $*${RST}"; }
pause() { echo -e "${YLW}Press ENTER to continue${RST}"; read -r; }
run_cmd() { echo -e "${DIM}$ ${MAG}$*${RST}"; eval "$@"; }

if ! command -v docker >/dev/null 2>&1; then
  echo -e "${RED}docker not found${RST}"; exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

compose_cmd="docker compose"
if ! docker compose version >/dev/null 2>&1; then
  if command -v docker-compose >/dev/null 2>&1; then
    compose_cmd="docker-compose"
  else
    echo -e "${RED}docker compose not found${RST}"; exit 1
  fi
fi

cleanup() {
  $compose_cmd down -v >/dev/null 2>&1 || true
}
trap cleanup EXIT

clear
echo -e "${BLU}Docker Step 6.3 - Compose${RST}"
info "Goal: multi-container app, shared network, service lifecycle"
pause

step "Bring stack up"
run_cmd "$compose_cmd up -d"
pause

step "Show services"
run_cmd "$compose_cmd ps"
run_cmd "docker network ls | grep demo-compose-net"
pause

step "Verify web service"
run_cmd "curl -s http://127.0.0.1:8081 | sed -n '1,8p'"
pause

step "Call api from inside web container"
run_cmd "docker exec demo-web wget -qO- http://demo-api:5678"

ok "Step 6.3 complete"
info "Cleanup will run automatically via compose down -v"
