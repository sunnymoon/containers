#!/usr/bin/env bash
# =============================================================================
# Linux Containers — Presentation Runner
# Runs each demo step in sequence, or jump to a specific step
# Usage:  sudo ./run-demo.sh [step]
#   step = 1..5 | 6.1 | 6.2 | 6.3 | 7.1 | 7.2 | 7.3
# =============================================================================

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'
BLU='\033[0;34m'; MAG='\033[0;35m'
BOLD='\033[1m'; DIM='\033[2m'; RST='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo -e "${YLW}⚠  This demo needs elevated privileges. Re-running with sudo...${RST}"
    exec sudo bash "$0" "$@"
fi

steps=(
    "1-fs"
    "2-mem"
    "3-proc"
    "4-uts"
    "5-net"
)
labels=(
    "Filesystem Isolation   (chroot / pivot_root)"
    "Resource Limits        (cgroups v2)"
    "Process Isolation      (PID namespace)"
    "Hostname Isolation     (UTS namespace)"
    "Network Isolation      (veth pair)"
)

clear
echo -e "${BLU}╔══════════════════════════════════════════════════════════════════╗${RST}"
echo -e "${BLU}║${RST}         ${BOLD}Linux Containers — From the Ground Up${RST}"
echo -e "${BLU}╚══════════════════════════════════════════════════════════════════╝${RST}"
echo
echo -e "  ${BOLD}Available steps:${RST}"
for i in "${!steps[@]}"; do
    echo -e "    ${YLW}$((i+1))${RST}  ${labels[$i]}"
done
echo -e "    ${YLW}6.1${RST}  Docker Build            (Dockerfile -> image layers)"
echo -e "    ${YLW}6.2${RST}  Docker Run              (lifecycle, ports, exec)"
echo -e "    ${YLW}6.3${RST}  Docker Compose          (multi-service app)"
echo -e "    ${YLW}7.1${RST}  Podman Build            (Containerfile, daemonless)"
echo -e "    ${YLW}7.2${RST}  Podman Run              (rootless-friendly runtime)"
echo -e "    ${YLW}7.3${RST}  Podman Pods             (pod networking + kube yaml)"
echo

if [[ -n "${1:-}" ]] && [[ "$1" =~ ^[1-5]$ ]]; then
    selected=$((${1} - 1))
    dir="${steps[$selected]}"
    echo -e "  ${GRN}→ Running step ${1}: ${labels[$selected]}${RST}"
    echo
    # Special: step 1 needs setup first
    if [[ "$dir" == "1-fs" && ! -d "${SCRIPT_DIR}/1-fs/rootfs/bin" ]]; then
        echo -e "  ${YLW}⚠  rootfs not found — running setup first...${RST}"
        bash "${SCRIPT_DIR}/1-fs/setup.sh"
        echo
    fi
    exec bash "${SCRIPT_DIR}/${dir}/demo.sh"
fi

case "${1:-}" in
    "6.1") exec bash "${SCRIPT_DIR}/6-docker/1-build/demo.sh" ;;
    "6.2") exec bash "${SCRIPT_DIR}/6-docker/2-run/demo.sh" ;;
    "6.3") exec bash "${SCRIPT_DIR}/6-docker/3-compose/demo.sh" ;;
    "7.1") exec bash "${SCRIPT_DIR}/7-podman/1-build/demo.sh" ;;
    "7.2") exec bash "${SCRIPT_DIR}/7-podman/2-run/demo.sh" ;;
    "7.3") exec bash "${SCRIPT_DIR}/7-podman/3-pods/demo.sh" ;;
esac

echo -e "  ${DIM}Run a step:  sudo ./run-demo.sh <step>${RST}"
echo -e "  ${DIM}Examples:    sudo ./run-demo.sh 1   |   sudo ./run-demo.sh 6.2${RST}"
echo
echo -e "  ${BOLD}Or run all steps in sequence:${RST}"
echo
echo -e "  ${MAG}cd 1-fs  && ./setup.sh && ./demo.sh${RST}"
echo -e "  ${MAG}cd 2-mem && ./demo.sh${RST}"
echo -e "  ${MAG}cd 3-proc && ./demo.sh${RST}"
echo -e "  ${MAG}cd 4-uts && ./demo.sh${RST}"
echo -e "  ${MAG}cd 5-net && ./demo.sh${RST}"
echo -e "  ${MAG}cd 6-docker/1-build && ./demo.sh${RST}"
echo -e "  ${MAG}cd ../2-run && ./demo.sh${RST}"
echo -e "  ${MAG}cd ../3-compose && ./demo.sh${RST}"
echo -e "  ${MAG}cd ../../../7-podman/1-build && ./demo.sh${RST}"
echo -e "  ${MAG}cd ../2-run && ./demo.sh${RST}"
echo -e "  ${MAG}cd ../3-pods && ./demo.sh${RST}"
echo
echo -e "  ${BLU}Slides:${RST}  SLIDES.md  (open with Marp or any Markdown viewer)"
echo
