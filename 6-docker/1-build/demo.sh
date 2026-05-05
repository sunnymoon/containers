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

clear
echo -e "${BLU}Docker Step 6.1 - Build${RST}"
info "Goal: show Dockerfile -> image layers -> runnable image"
pause

step "Build demo image"
run_cmd "docker build -t containers-demo:step6-build ."
pause

step "Show image metadata"
run_cmd "docker images | grep containers-demo"
run_cmd "docker history containers-demo:step6-build"
pause

step "Run the built image"
run_cmd "docker run --rm --name step6-build-run containers-demo:step6-build"

ok "Step 6.1 complete"
info "Next: cd ../2-run && ./demo.sh"
