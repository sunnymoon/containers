#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'; BLU='\033[0;34m'; MAG='\033[0;35m'; DIM='\033[2m'; RST='\033[0m'

step() { echo -e "${YLW}▶ $*${RST}"; }
info() { echo -e "${BLU}  i  $*${RST}"; }
ok() { echo -e "${GRN}  ok  $*${RST}"; }
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
  podman pod rm -f --time 0 demo-pod >/dev/null 2>&1 || true
  podman pod rm -f --time 0 demo-sharepod >/dev/null 2>&1 || true
}
trap cleanup EXIT

clear
echo -e "${BLU}Podman Step 7.3 - Pods${RST}"
info "Goal: shared network namespace between containers in a pod"
pause

step "Create a pod manually"
run_cmd "podman pod create --name demo-sharepod -p 8091:80"
run_cmd "podman run -d --pod demo-sharepod --name demo-nginx docker.io/library/nginx:alpine"
run_cmd "podman run -d --pod demo-sharepod --name demo-client docker.io/library/busybox sh -c 'sleep 3600'"
pause

step "Inspect pod and validate service"
run_cmd "podman pod ps"
run_cmd "podman ps --pod"
run_cmd "curl -sI http://127.0.0.1:8091 | sed -n '1,5p'"
echo
info "Now prove pod network sharing: client container reaches nginx on localhost"
run_cmd "podman exec demo-client wget -qO- http://127.0.0.1:80 | sed -n '1,2p'"
pause

step "Show generated kube YAML"
run_cmd "podman generate kube demo-sharepod | sed -n '1,60p'"
pause

step "Recreate from kube yaml"
run_cmd "podman pod rm -f --time 0 demo-sharepod"
run_cmd "podman play kube kube-pod.yaml"
run_cmd "podman pod ps"
run_cmd "podman ps --pod"
run_cmd "curl -sI http://127.0.0.1:8092 | sed -n '1,5p'"
echo
info "Same localhost proof after play kube"
run_cmd "podman exec demo-pod-client wget -qO- http://127.0.0.1:80 | sed -n '1,2p'"

ok "Step 7.3 complete"
info "Podman pods map naturally to Kubernetes pod concepts"
