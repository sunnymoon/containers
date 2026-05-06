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
UNSHARE_BGPID=""

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
    if ! read -r < /dev/tty; then
        read -r || true
    fi
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
    if [[ -n "$UNSHARE_BGPID" ]]; then
        kill "$UNSHARE_BGPID" 2>/dev/null || true
    fi
    rm -f "$NS_SENTINEL"
    rm -f "${SCRIPT_DIR}/.demo_pid"
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
info "Running a non-interactive probe (stable for live demos):"
info "  echo \$\$          # should be 1"
info "  ps -ef            # only namespace-local processes"
info "  ls /proc | head   # limited list"
info "  cat /proc/1/comm  # bash"
echo

# Store the PID of our unshare process so we can nsenter later
echo -e "${DIM}  \$${RST} ${MAG}unshare --pid --fork --mount-proc bash -c 'echo \$\$; ps -ef; ls /proc | head; cat /proc/1/comm'${RST}"

# We'll launch and run deterministic commands inside the new PID namespace
unshare --pid --fork --mount-proc bash -c "
    echo \$\$ > '${NS_SENTINEL}'
    echo
    echo -e '  \033[1;32m✔  Inside PID namespace\033[0m'
    echo -e '  PID in namespace:'
    echo \$\$
    echo
    echo -e '  Process list:'
    ps -ef
    echo
    echo -e '  /proc sample:'
    ls /proc | head
    echo
    echo -e '  /proc/1/comm:'
    cat /proc/1/comm
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

# ─────────────────────────────────────────────────────────────────────────────
banner "3/3 — nsenter: joining a running namespace"

info "This is how 'docker exec' works under the hood."
echo
step "Start a background 'container' (sleeping in a new PID namespace):"
echo

# The unshare process itself stays in host PID ns.
# Its forked CHILD (bash/sleep) is what enters the new PID namespace.
# We find that child PID via pgrep after launch.
echo -e "${DIM}  \$${RST} ${MAG}unshare --pid --fork --mount-proc bash -c 'exec sleep 3600' &${RST}"
unshare --pid --fork --mount-proc bash -c 'exec sleep 3600' &
UNSHARE_BGPID=$!
sleep 0.5

# The CHILD (sleep 3600) is the process actually inside the new PID namespace
CHILD_PID=$(pgrep -P "$UNSHARE_BGPID" 2>/dev/null | head -1)
if [[ -z "$CHILD_PID" ]]; then
    warn "Could not find child PID — using unshare PID as fallback"
    CHILD_PID="$UNSHARE_BGPID"
fi
echo -e "  unshare host PID : ${BOLD}${UNSHARE_BGPID}${RST}  (still in host PID namespace)"
echo -e "  child host PID   : ${BOLD}${CHILD_PID}${RST}  (this one is inside the new PID namespace)"
echo

step "Compare PID namespaces — host vs container child:"
echo -e "${DIM}  \$${RST} ${MAG}readlink /proc/self/ns/pid        # this script${RST}"
SELF_PID_NS="$(readlink /proc/self/ns/pid)"
echo "  $SELF_PID_NS"
echo
echo -e "${DIM}  \$${RST} ${MAG}readlink /proc/${UNSHARE_BGPID}/ns/pid   # unshare process${RST}"
UNSHARE_PID_NS="$(readlink /proc/${UNSHARE_BGPID}/ns/pid 2>/dev/null || echo '(gone)')"
echo "  $UNSHARE_PID_NS"
echo
echo -e "${DIM}  \$${RST} ${MAG}readlink /proc/${CHILD_PID}/ns/pid     # child inside namespace${RST}"
CHILD_PID_NS="$(readlink /proc/${CHILD_PID}/ns/pid 2>/dev/null || echo '(gone)')"
echo "  $CHILD_PID_NS"
echo
if [[ "$CHILD_PID_NS" != "$SELF_PID_NS" ]]; then
    ok "child has a DIFFERENT PID namespace than this script — isolation confirmed!"
else
    warn "child is in the same PID namespace as this script — pgrep may have found wrong child"
fi

pause

step "nsenter: join the container's PID namespace (like 'docker exec'):"
echo -e "${DIM}  \$${RST} ${MAG}nsenter --pid --mount --target ${CHILD_PID} -- bash -c 'echo \$\$; ps -ef'${RST}"
nsenter --pid --mount --target "${CHILD_PID}" -- \
    bash -c 'echo "our PID inside namespace: $$"; echo; ps -ef' 2>/dev/null || \
    warn "nsenter into child failed (try targeting unshare PID instead)"
echo
ok "nsenter exited — we were a visitor in the container PID namespace."

# Cleanup the background process
kill "$UNSHARE_BGPID" 2>/dev/null || true

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
