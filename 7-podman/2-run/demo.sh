#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'; BLU='\033[0;34m'; MAG='\033[0;35m'; DIM='\033[2m'; RST='\033[0m'

step() { echo -e "${YLW}▶ $*${RST}"; }
info() { echo -e "${BLU}  i  $*${RST}"; }
ok() { echo -e "${GRN}  ok  $*${RST}"; }
warn() { echo -e "${RED}  !  $*${RST}"; }
pause() {
  echo -e "${YLW}Press ENTER to continue${RST}"
  if ! read -r < /dev/tty; then
    read -r || true
  fi
}
run_cmd() { echo -e "${DIM}$ ${MAG}$*${RST}"; eval "$@"; }

if ! command -v podman >/dev/null 2>&1; then
  echo -e "${RED}podman not found${RST}"; exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

cleanup() {
  podman rm -f step7-nginx >/dev/null 2>&1 || true
}
trap cleanup EXIT

clear
echo -e "${BLU}Podman Step 7.2 - Run${RST}"
info "Goal: run container daemonlessly, inspect, exec"
pause

step "Run nginx mapped to host port"
run_cmd "podman run -d --name step7-nginx -p 8090:80 -v $SCRIPT_DIR/nginx.conf:/etc/nginx/nginx.conf:ro,Z docker.io/library/nginx:alpine"

if ! podman ps --filter name=step7-nginx --filter status=running --format '{{.ID}}' | grep -q .; then
  warn "step7-nginx did not stay running"
  run_cmd "podman ps -a --filter name=step7-nginx"
  run_cmd "podman logs --tail 80 step7-nginx"
  exit 1
fi

ok "Container is running"
pause

step "Inspect running containers"
run_cmd "podman ps"
run_cmd "curl -s http://127.0.0.1:8090"
pause

step "Enter container"
run_cmd "podman exec step7-nginx sh -c 'hostname; ip addr show | sed -n \"1,14p\"; ps aux | sed -n \"1,12p\"'"
pause

step "Inspect metadata"
run_cmd "podman inspect step7-nginx --format '{{.State.Pid}} {{.HostConfig.NetworkMode}}'"

ok "Step 7.2 complete"
info "Next: cd ../3-pods && ./demo.sh"
