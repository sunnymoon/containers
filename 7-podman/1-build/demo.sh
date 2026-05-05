#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'; BLU='\033[0;34m'; MAG='\033[0;35m'; DIM='\033[2m'; RST='\033[0m'

step() { echo -e "${YLW}▶ $*${RST}"; }
info() { echo -e "${BLU}  i  $*${RST}"; }
ok() { echo -e "${GRN}  ok  $*${RST}"; }
pause() { echo -e "${YLW}Press ENTER to continue${RST}"; read -r; }
run_cmd() { echo -e "${DIM}$ ${MAG}$*${RST}"; eval "$@"; }

if ! command -v podman >/dev/null 2>&1; then
  echo -e "${RED}podman not found${RST}"; exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

clear
echo -e "${BLU}Podman Step 7.1 - Build${RST}"
info "Goal: daemonless image build from Containerfile"
pause

step "Build demo image"
run_cmd "podman build -t containers-demo:step7-build ."
pause

step "Show image metadata"
run_cmd "podman images | grep containers-demo"
run_cmd "podman history containers-demo:step7-build"
pause

step "Run the built image"
run_cmd "podman run --rm --name step7-build-run containers-demo:step7-build"

ok "Step 7.1 complete"
info "Next: cd ../2-run && ./demo.sh"
