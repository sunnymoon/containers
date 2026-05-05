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

cleanup() {
  docker rm -f step6-nginx >/dev/null 2>&1 || true
}
trap cleanup EXIT

clear
echo -e "${BLU}Docker Step 6.2 - Run${RST}"
info "Goal: show lifecycle, port mapping, exec, inspect"
pause

step "Run nginx with host port mapping"
run_cmd "docker run -d --name step6-nginx -p 8080:80 -v $SCRIPT_DIR/nginx.conf:/etc/nginx/nginx.conf:ro nginx:alpine"
pause

step "Inspect running containers"
run_cmd "docker ps"
run_cmd "curl -s http://127.0.0.1:8080"
pause

step "Enter container namespace via docker exec"
run_cmd "docker exec step6-nginx sh -c 'hostname; ip addr show | sed -n \"1,14p\"; ps aux | sed -n \"1,12p\"'"
pause

step "Show low-level metadata"
run_cmd "docker inspect step6-nginx --format '{{.State.Pid}} {{.HostConfig.NetworkMode}}'"

ok "Step 6.2 complete"
info "Next: cd ../3-compose && ./demo.sh"
