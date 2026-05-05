#!/usr/bin/env bash
# =============================================================================
# Step 3 — PID Namespace Isolation  |  INTERACTIVE DEMO
# Shows: unshare --pid, PID 1, ps visibility, nsenter (docker exec equivalent)
# Run as root: sudo ./demo.sh
# =============================================================================

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'
BLU='\033[0;34m'; CYN='\033[0;36m'; MAG='\033[0;35m'
BOLD='\033[1m'; DIM='\033[2m'; RST='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NS_SENTINEL="${SCRIPT_DIR}/.ns_pid"

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

# ── preflight ─────────────────────────────────────────────────────────────────

if [[ $EUID -ne 0 ]]; then
    warn "This demo needs root. Re-running with sudo..."
    exec sudo bash "$0" "$@"
fi

cleanup() {
    rm -f "$NS_SENTINEL"
}
trap cleanup EXIT

# ── DEMO START ────────────────────────────────────────────────────────────────

clear
banner "Step 3 — PID Namespace Isolation"

echo -e "  The ${BOLD}PID namespace${RST} gives a process its own view of the process tree."
echo -e "  The first process in a new PID namespace becomes ${BOLD}PID 1${RST}."
echo
echo -e "  We'll show:"
echo -e "  ${BLU}1.${RST} How the host sees all processes"
echo -e "  ${BLU}2.${RST} unshare --pid: isolating the PID space"
echo -e "  ${BLU}3.${RST} nsenter: joining a namespace from outside (docker exec)"

pause

# ─────────────────────────────────────────────────────────────────────────────
banner "1/3 — Host process visibility"

step "How many processes are on the host right now?"
run_cmd "ps aux | wc -l"
echo
step "Our current PID (on the host):"
run_cmd "echo \$\$"
echo
step "PID 1 on the host:"
run_cmd "cat /proc/1/comm 2>/dev/null || ps -p 1 -o comm="
echo
step "The /proc filesystem reflects the PID namespace:"
run_cmd "ls /proc | grep '^[0-9]' | wc -l"
info "All those directories = all visible PIDs"

pause

# ─────────────────────────────────────────────────────────────────────────────
banner "2/3 — unshare --pid: new PID namespace"

step "Create a new PID namespace:"
info "  --pid       = new PID namespace"
info "  --fork      = fork so we become PID 1 in the new ns (not PID 2)"
info "  --mount-proc = remount /proc for the new namespace"
echo
info "Type 'exit' when you're done exploring. Try:"
info "  echo \$\$          # should be 1"
info "  ps aux           # only this shell and ps!"
info "  ls /proc | head  # limited list"
info "  cat /proc/1/comm # bash — we ARE PID 1"
echo

# Store the PID of our unshare process so we can nsenter later
echo -e "${DIM}  \$${RST} ${MAG}unshare --pid --fork --mount-proc bash${RST}"

# We'll launch and record the unshare PID to a file
unshare --pid --fork --mount-proc bash -c "
    echo \$\$ > '${NS_SENTINEL}'
    echo
    echo -e '  \033[1;32m✔  Welcome inside the PID namespace!\033[0m'
    echo -e '  Host PID is different — inside we are always PID 1 (after fork).'
    echo
    exec bash --norc -i
" || true

CONTAINER_PID=""
if [[ -f "$NS_SENTINEL" ]]; then
    CONTAINER_PID=$(cat "$NS_SENTINEL")
fi

echo
ok "Back on the host."
echo
step "Verify: from the host, the process had a REAL PID:"
run_cmd "cat /proc/\$\$/status | grep ^Pid" || true

pause

# ─────────────────────────────────────────────────────────────────────────────
banner "3/3 — nsenter: joining a running namespace"

info "This is how 'docker exec' works under the hood."
echo
step "First, let's start a background process in a new PID namespace"
info "We'll record its PID so we can re-enter it."
echo

# Start a sleeping process in a new PID namespace, record its real PID
PIDFILE="${SCRIPT_DIR}/.demo_pid"
unshare --pid --fork --mount-proc \
    bash -c "echo \$\$ > '${PIDFILE}'; exec sleep 3600" &
UNSHARE_BGPID=$!

# Give it a moment to start
sleep 0.5

HOST_PID="$UNSHARE_BGPID"
echo -e "${DIM}  \$${RST} ${MAG}# background 'container' started${RST}"
echo -e "  Host PID of the unshare process: ${BOLD}${HOST_PID}${RST}"
echo

step "Verify PID namespace of the 'container' process:"
run_cmd "ls -la /proc/${HOST_PID}/ns/pid 2>/dev/null || echo '(process may have exited)'"
echo
run_cmd "ls -la /proc/self/ns/pid"
info "Different inode → different PID namespace!"

pause

step "nsenter: join the PID namespace of the container"
info "We keep our own terminal (mount ns) but share its PID namespace."
echo
info "Inside, try:"
info "  ps aux           # only sees the container processes"
info "  ls /proc         # limited"
info "  echo \$\$          # not 1 (we're a visitor, not PID 1)"
echo

echo -e "${DIM}  \$${RST} ${MAG}nsenter --pid --target ${HOST_PID} -- bash${RST}"
nsenter --pid --target "${HOST_PID}" -- \
    bash --norc -i || true

echo
ok "nsenter exited."

# Cleanup the background process
kill "$UNSHARE_BGPID" 2>/dev/null || true
rm -f "$PIDFILE"

pause

banner "Bonus — Entering ALL namespaces (true docker exec)"

step "nsenter can enter all namespaces at once:"
echo
echo -e "  ${MAG}nsenter --target <PID> \\\\${RST}"
echo -e "  ${MAG}        --mount --pid --uts --net --ipc \\\\${RST}"
echo -e "  ${MAG}        -- /bin/sh${RST}"
echo
info "This is ${BOLD}exactly${RST} what 'docker exec -it <container> bash' does."
info "The container runtime finds the container's init PID and nsenter's into all its namespaces."

pause

banner "Summary — Step 3 Complete"
echo -e "  ${GRN}unshare --pid --fork${RST}    new PID namespace, our process becomes PID 1"
echo -e "  ${GRN}--mount-proc${RST}            remount /proc so ps/top work correctly"
echo -e "  ${GRN}nsenter --pid --target${RST}  join an existing namespace from outside"
echo
echo -e "  Namespace isolation means: processes in the container ${BOLD}cannot see${RST}"
echo -e "  host processes — but the host ${BOLD}can see${RST} everything (it owns the kernel)."
echo
echo -e "  ${YLW}Next:${RST} Step 4 — Hostname isolation with UTS namespace"
echo -e "  ${DIM}  cd ../4-uts && ./demo.sh${RST}"
echo
