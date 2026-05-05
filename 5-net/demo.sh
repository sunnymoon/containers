#!/usr/bin/env bash
# =============================================================================
# Step 5 — Network Namespace + veth Pair  |  INTERACTIVE DEMO
# Shows: net namespace, veth pair, IP setup, ping, NAT to internet
# Run as root: sudo ./demo.sh
# =============================================================================

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'
BLU='\033[0;34m'; CYN='\033[0;36m'; MAG='\033[0;35m'
BOLD='\033[1m'; DIM='\033[2m'; RST='\033[0m'

NS_NAME="demo-container"
VETH_HOST="veth-host"
VETH_CTR="veth-ctr"
HOST_IP="172.20.99.1"
CTR_IP="172.20.99.2"
SUBNET="172.20.99.0/24"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOTFS="${SCRIPT_DIR}/../1-fs/rootfs"

# ── helpers ───────────────────────────────────────────────────────────────────

banner() {
    echo
    echo -e "${BLU}╔══════════════════════════════════════════════════════════════╗${RST}"
    echo -e "${BLU}║${RST}  ${BOLD}$1${RST}"
    echo -e "${BLU}╚══════════════════════════════════════════════════════════════╝${RST}"
    echo
}

step()  { echo -e "${YLW}▶ ${BOLD}$*${RST}"; }
info()  { echo -e "${CYN}  ℹ  $*${RST}"; }
warn()  { echo -e "${RED}  ⚠  $*${RST}"; }
ok()    { echo -e "${GRN}  ✔  $*${RST}"; }
pause() {
    echo
    echo -e "${YLW}  ══════════ Press ENTER to continue ══════════${RST}"
    read -r
}
run_cmd() {
    echo -e "${DIM}  \$${RST} ${MAG}$*${RST}"
    eval "$@"
}

# ── cleanup ───────────────────────────────────────────────────────────────────

cleanup() {
    echo
    info "Cleaning up network resources..."
    ip netns del "${NS_NAME}" 2>/dev/null && ok "Deleted netns: ${NS_NAME}" || true
    ip link del "${VETH_HOST}" 2>/dev/null && ok "Deleted veth: ${VETH_HOST}" || true
    # restore ip_forward to original value
    if [[ -n "${ORIG_IP_FORWARD:-}" ]]; then
        echo "$ORIG_IP_FORWARD" > /proc/sys/net/ipv4/ip_forward
    fi
    # remove iptables NAT rule
    iptables -t nat -D POSTROUTING -s "${SUBNET}" ! -o "${VETH_HOST}" -j MASQUERADE 2>/dev/null || true
    ok "Network cleanup complete."
}
trap cleanup EXIT

# ── preflight ─────────────────────────────────────────────────────────────────

if [[ $EUID -ne 0 ]]; then
    warn "This demo needs root. Re-running with sudo..."
    exec sudo bash "$0" "$@"
fi

for cmd in ip iptables; do
    if ! command -v "$cmd" &>/dev/null; then
        warn "Required tool not found: ${cmd}"
        warn "Install with: apt install iproute2 iptables"
        exit 1
    fi
done

# ── DEMO START ────────────────────────────────────────────────────────────────

clear
banner "Step 5 — Network Namespace + veth Pair"

echo -e "  A ${BOLD}network namespace${RST} gives a process its own:"
echo -e "  • network interfaces  • routing table  • iptables rules  • sockets"
echo
echo -e "  A ${BOLD}veth pair${RST} is like a virtual ethernet cable:"
echo -e "  • two ends linked together"
echo -e "  • packets in one end come out the other"
echo -e "  • one end in host namespace, other end in container namespace"
echo
echo -e "  We'll show:"
echo -e "  ${BLU}1.${RST} Inspect host network stack"
echo -e "  ${BLU}2.${RST} Create a network namespace"
echo -e "  ${BLU}3.${RST} Create a veth pair and connect host ↔ container"
echo -e "  ${BLU}4.${RST} Ping between host and container"
echo -e "  ${BLU}5.${RST} NAT: give the container internet access"
echo -e "  ${BLU}6.${RST} Combine everything: the full hand-rolled container"

pause

# ─────────────────────────────────────────────────────────────────────────────
banner "1/6 — Host network stack"

step "Host network interfaces:"
run_cmd "ip link show"
echo
step "Host routing table:"
run_cmd "ip route show"
echo
step "Existing network namespaces:"
run_cmd "ip netns list"
info "(probably empty — no named namespaces yet)"

pause

# ─────────────────────────────────────────────────────────────────────────────
banner "2/6 — Create a named network namespace"

step "Create network namespace '${NS_NAME}':"
run_cmd "ip netns add ${NS_NAME}"
ok "Created!"
echo
run_cmd "ip netns list"
echo

step "Inspect the namespace — it has only loopback, and it's DOWN:"
run_cmd "ip netns exec ${NS_NAME} ip link show"
echo

step "The namespace has its own (empty) routing table:"
run_cmd "ip netns exec ${NS_NAME} ip route show"
info "Empty — completely isolated from the host"

pause

# ─────────────────────────────────────────────────────────────────────────────
banner "3/6 — Create veth pair and wire it up"

echo -e "  ${BOLD}Plan:${RST}"
echo -e "  ${DIM}HOST:${RST}       ${VETH_HOST}  (${HOST_IP})"
echo -e "  ${DIM}CONTAINER:${RST}  ${VETH_CTR}  (${CTR_IP})"
echo -e "  ${DIM}Both in subnet:${RST} ${SUBNET}"
echo

step "1. Create the veth pair:"
run_cmd "ip link add ${VETH_HOST} type veth peer name ${VETH_CTR}"
echo
run_cmd "ip link show type veth"
echo

step "2. Move the container end into the network namespace:"
run_cmd "ip link set ${VETH_CTR} netns ${NS_NAME}"
echo

step "3. Configure the HOST end:"
run_cmd "ip addr add ${HOST_IP}/24 dev ${VETH_HOST}"
run_cmd "ip link set ${VETH_HOST} up"
echo
run_cmd "ip addr show dev ${VETH_HOST}"
echo

step "4. Configure the CONTAINER end:"
run_cmd "ip netns exec ${NS_NAME} ip addr add ${CTR_IP}/24 dev ${VETH_CTR}"
run_cmd "ip netns exec ${NS_NAME} ip link set ${VETH_CTR} up"
run_cmd "ip netns exec ${NS_NAME} ip link set lo up"
echo
run_cmd "ip netns exec ${NS_NAME} ip addr show"

pause

# ─────────────────────────────────────────────────────────────────────────────
banner "4/6 — Ping: host ↔ container"

step "Host pings container (${CTR_IP}):"
run_cmd "ping -c 4 ${CTR_IP}"
echo

step "Container pings host (${HOST_IP}):"
run_cmd "ip netns exec ${NS_NAME} ping -c 4 ${HOST_IP}"
echo

ok "Bidirectional communication through the veth pair!"
echo
step "Container cannot reach the internet yet:"
run_cmd "ip netns exec ${NS_NAME} ip route show"
info "No default route — container is isolated from everything else."

pause

# ─────────────────────────────────────────────────────────────────────────────
banner "5/6 — NAT: internet access from the container"

step "Enable IP forwarding on the host:"
ORIG_IP_FORWARD=$(cat /proc/sys/net/ipv4/ip_forward)
run_cmd "echo 1 > /proc/sys/net/ipv4/ip_forward"
run_cmd "cat /proc/sys/net/ipv4/ip_forward"
echo

step "Add a NAT/masquerade rule for outbound container traffic:"
info "This is exactly what 'docker run -p' sets up automatically."
run_cmd "iptables -t nat -A POSTROUTING -s ${SUBNET} ! -o ${VETH_HOST} -j MASQUERADE"
run_cmd "iptables -t nat -L POSTROUTING -n -v | grep -v '^$'"
echo

step "Add a default route inside the container:"
run_cmd "ip netns exec ${NS_NAME} ip route add default via ${HOST_IP}"
run_cmd "ip netns exec ${NS_NAME} ip route show"
echo

step "Test internet access from the container:"
info "Using 8.8.8.8 (Google DNS) as a test"
run_cmd "ip netns exec ${NS_NAME} ping -c 3 8.8.8.8" || \
    warn "Ping to 8.8.8.8 failed — check host internet & IP forwarding"

pause

# ─────────────────────────────────────────────────────────────────────────────
banner "5b/6 — Interactive shell inside the network namespace"

step "Enter the network namespace interactively:"
info "Try:"
info "  ip addr show    → only lo and ${VETH_CTR}"
info "  ip route show   → default via ${HOST_IP}"
info "  ping ${HOST_IP}  → pings the host"
info "  ping 8.8.8.8     → internet via NAT"
echo
echo -e "${DIM}  \$${RST} ${MAG}ip netns exec ${NS_NAME} bash${RST}"

ip netns exec "${NS_NAME}" bash --norc -i || true

echo
ok "Exited the network namespace."

pause

# ─────────────────────────────────────────────────────────────────────────────
banner "6/6 — The complete hand-rolled container"

if [[ ! -d "${ROOTFS}/bin" ]]; then
    warn "Alpine rootfs not found at ${ROOTFS}"
    warn "Run cd ../1-fs && ./setup.sh first."
    info "Showing the combined unshare command instead:"
    echo
    echo -e "  ${MAG}# From the network namespace, unshare everything:${RST}"
    echo -e "  ${MAG}ip netns exec ${NS_NAME} \\\\${RST}"
    echo -e "  ${MAG}  unshare --mount --pid --uts --fork bash <<'EOF'${RST}"
    echo -e "  ${MAG}    mount --bind /path/to/rootfs /path/to/rootfs${RST}"
    echo -e "  ${MAG}    mkdir -p /path/to/rootfs/.oldroot${RST}"
    echo -e "  ${MAG}    hostname my-container${RST}"
    echo -e "  ${MAG}    cd /path/to/rootfs && pivot_root . .oldroot${RST}"
    echo -e "  ${MAG}    mount -t proc proc /proc${RST}"
    echo -e "  ${MAG}    umount -l /.oldroot${RST}"
    echo -e "  ${MAG}    exec /bin/sh${RST}"
    echo -e "  ${MAG}EOF${RST}"
    pause
else

step "Launch the complete container:"
info "  • Alpine Linux root (pivot_root)"
info "  • PID 1 (new PID namespace)"
info "  • hostname 'full-container'"
info "  • Own network via ${VETH_CTR} — ${CTR_IP}"
echo
info "Inside, try:"
info "  hostname              → full-container"
info "  echo \$\$               → 1"
info "  cat /etc/os-release   → Alpine"
info "  ip addr show          → ${CTR_IP} on ${VETH_CTR}"
info "  ping ${HOST_IP}        → pings the host"
info "  ping 8.8.8.8           → internet via NAT"
echo

echo -e "${DIM}  \$${RST} ${MAG}ip netns exec ${NS_NAME} unshare --mount --pid --uts --fork bash${RST}"

ip netns exec "${NS_NAME}" \
    unshare --mount --pid --uts --fork bash -c "
    set -e
    ROOTFS='${ROOTFS}'

    # filesystem
    mount --bind \"\$ROOTFS\" \"\$ROOTFS\"
    mount -t proc proc \"\$ROOTFS/proc\"
    mount -t sysfs sysfs \"\$ROOTFS/sys\" 2>/dev/null || true

    # copy resolv.conf so DNS works
    cp /etc/resolv.conf \"\$ROOTFS/etc/resolv.conf\" 2>/dev/null || true

    mkdir -p \"\$ROOTFS/.oldroot\"

    # UTS
    hostname full-container

    # pivot
    cd \"\$ROOTFS\"
    pivot_root . .oldroot
    umount -l /.oldroot

    echo
    echo -e '  \033[1;32m╔═══════════════════════════════════════════════╗\033[0m'
    echo -e '  \033[1;32m║  🎉  Full hand-rolled container running!     ║\033[0m'
    echo -e '  \033[1;32m╚═══════════════════════════════════════════════╝\033[0m'
    echo
    echo '  hostname: '\$(hostname)
    echo '  PID:      '\$\$
    ip addr show 2>/dev/null | grep -E 'inet |^[0-9]' || true
    echo
    exec /bin/sh -i
" || true

fi # end rootfs check

pause

# ─────────────────────────────────────────────────────────────────────────────
banner "Summary — Step 5 Complete"

echo -e "  ${GRN}ip netns add${RST}           create a named network namespace"
echo -e "  ${GRN}ip link add veth ... peer ...${RST}   create a linked veth pair"
echo -e "  ${GRN}ip link set ... netns${RST}   move one veth end into namespace"
echo -e "  ${GRN}iptables MASQUERADE${RST}     NAT for outbound internet access"
echo -e "  ${GRN}ip route add default${RST}    default gateway inside container"
echo
echo -e "  ${BOLD}The full picture:${RST}"
echo -e ""
echo -e "  HOST namespace              CONTAINER namespace"
echo -e "  ───────────────             ──────────────────────"
echo -e "  ${VETH_HOST} ${HOST_IP}   ←veth→   ${VETH_CTR} ${CTR_IP}"
echo -e "  ip_forward + NAT            default gw ${HOST_IP}"
echo -e "                              pivot_root (Alpine)"
echo -e "                              PID 1, hostname=full-container"
echo
echo -e "  ${YLW}This IS what Docker does. It just automates it.${RST}"
echo
echo -e "  ${BLU}Steps 6 & 7:${RST} Docker build/run/compose and Podman/pods"
echo -e "  ${DIM}  cd ../6-docker/1-build${RST}"
echo
