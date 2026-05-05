#!/usr/bin/env bash
# =============================================================================
# Step 2 — Resource Limits with cgroups v2  |  INTERACTIVE DEMO
# Shows: creating cgroups, memory limits, OOM kill, CPU throttle, pids limit
# Run as root: sudo ./demo.sh
# =============================================================================

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'
BLU='\033[0;34m'; CYN='\033[0;36m'; MAG='\033[0;35m'
BOLD='\033[1m'; DIM='\033[2m'; RST='\033[0m'

CGROUP_ROOT="/sys/fs/cgroup"
CGROUP_NAME="containers-demo"
CGROUP_PATH="${CGROUP_ROOT}/${CGROUP_NAME}"

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

# ── cleanup trap ──────────────────────────────────────────────────────────────

cleanup() {
    echo
    info "Cleaning up cgroup ${CGROUP_NAME} ..."
    # move our shell out of the cgroup first
    echo $$ > "${CGROUP_ROOT}/cgroup.procs" 2>/dev/null || true
    # kill any remaining procs in our cgroup
    if [[ -f "${CGROUP_PATH}/cgroup.procs" ]]; then
        while read -r pid; do
            kill -9 "$pid" 2>/dev/null || true
        done < "${CGROUP_PATH}/cgroup.procs"
    fi
    rmdir "${CGROUP_PATH}" 2>/dev/null || true
    ok "Cleanup done."
}
trap cleanup EXIT

# ── preflight ─────────────────────────────────────────────────────────────────

if [[ $EUID -ne 0 ]]; then
    warn "This demo needs root. Re-running with sudo..."
    exec sudo bash "$0" "$@"
fi

# verify cgroups v2
if ! mountpoint -q "${CGROUP_ROOT}"; then
    warn "${CGROUP_ROOT} is not a cgroup mount — is cgroups v2 enabled?"
    exit 1
fi

if ! grep -q cgroup2 /proc/mounts; then
    warn "cgroups v2 (unified hierarchy) not detected."
    warn "You may be on a mixed v1/v2 system. Some steps may differ."
fi

# ── DEMO START ────────────────────────────────────────────────────────────────

clear
banner "Step 2 — Resource Limits with cgroups v2"

echo -e "  cgroups = Control Groups"
echo -e "  The kernel's mechanism to ${BOLD}account and limit${RST} resources per process group."
echo
echo -e "  We'll demo:"
echo -e "  ${BLU}1.${RST} Explore the cgroup hierarchy"
echo -e "  ${BLU}2.${RST} Create a cgroup and set a memory limit"
echo -e "  ${BLU}3.${RST} Watch the OOM (Out-Of-Memory) killer strike"
echo -e "  ${BLU}4.${RST} CPU quota and PID limits"

pause

# ─────────────────────────────────────────────────────────────────────────────
banner "1/4 — Explore the cgroup hierarchy"

step "The unified cgroup v2 hierarchy lives here:"
run_cmd "ls ${CGROUP_ROOT}/"
echo
step "Every process on the system belongs to a cgroup:"
run_cmd "cat /proc/self/cgroup"
echo
step "Available controllers (resources we can limit):"
run_cmd "cat ${CGROUP_ROOT}/cgroup.controllers"
echo
step "Processes in the root cgroup:"
run_cmd "head -5 ${CGROUP_ROOT}/cgroup.procs"

pause

# ─────────────────────────────────────────────────────────────────────────────
banner "2/4 — Create a cgroup and set a memory limit"

step "Create our demo cgroup slice:"
run_cmd "mkdir -p ${CGROUP_PATH}"
ok "Created: ${CGROUP_PATH}"
echo

step "Enable the memory controller for this cgroup:"
run_cmd "echo '+memory' > ${CGROUP_ROOT}/cgroup.subtree_control" 2>/dev/null || \
    info "(memory controller already enabled)"
echo

step "Set a 32 MiB memory limit:"
run_cmd "echo $((32 * 1024 * 1024)) > ${CGROUP_PATH}/memory.max"
run_cmd "cat ${CGROUP_PATH}/memory.max"
echo

step "Enable the OOM killer (kill the process, not just throttle):"
run_cmd "echo 1 > ${CGROUP_PATH}/memory.oom.group"
echo

step "Assign current shell to the cgroup:"
run_cmd "echo \$\$ > ${CGROUP_PATH}/cgroup.procs"
run_cmd "cat /proc/self/cgroup"
echo

step "Current memory usage of this cgroup:"
run_cmd "cat ${CGROUP_PATH}/memory.current"

pause

# ─────────────────────────────────────────────────────────────────────────────
banner "3/4 — Trigger the OOM killer"

step "We'll try to allocate 50 MiB inside our 32 MiB cgroup."
info "The kernel OOM killer will terminate the process."
echo

warn "Watch what happens..."
echo

# Run the allocator as a child so it gets OOM-killed but our shell survives
run_cmd "bash -c \"python3 -c 'x = bytearray(50 * 1024 * 1024); print(\\\"allocated!\\\")' && echo OK\""
EXIT_CODE=$?

echo
if [[ $EXIT_CODE -ne 0 ]]; then
    ok "The child process was killed (exit code: ${EXIT_CODE})"
    ok "Our shell survived — only the offending process was terminated."
else
    info "Process completed (cgroup memory might allow burstable usage on this kernel)."
fi

echo
step "Check the kernel OOM log:"
run_cmd "dmesg 2>/dev/null | grep -i 'oom\|killed' | tail -5" || \
    info "(no OOM entries — the allocator may have been swapped or kernel didn't log it)"

pause

# ─────────────────────────────────────────────────────────────────────────────
banner "4/4 — CPU quota and PID limits"

step "Remove memory limit (infinity = no limit):"
run_cmd "echo max > ${CGROUP_PATH}/memory.max"
echo

step "Set CPU quota: 50% of one CPU"
info "Format: 'quota_us period_us'  →  50000 100000 = 50% of one core"
run_cmd "echo '50000 100000' > ${CGROUP_PATH}/cpu.max" 2>/dev/null || \
    info "(cpu controller not enabled in subtree_control — skipping)"
run_cmd "cat ${CGROUP_PATH}/cpu.max 2>/dev/null || echo '(N/A)'"
echo

step "PID limit: max 20 processes in this cgroup:"
run_cmd "echo 20 > ${CGROUP_PATH}/pids.max" 2>/dev/null || \
    info "(pids controller not enabled — skipping)"
run_cmd "cat ${CGROUP_PATH}/pids.max 2>/dev/null || echo '(N/A)'"
echo

step "Try to exceed the PID limit:"
run_cmd "for i in \$(seq 1 25); do sleep 60 & done; echo spawned; jobs | wc -l" || true
# cleanup background sleep jobs
kill %% 2>/dev/null || true
disown -a 2>/dev/null || true

pause

# ─────────────────────────────────────────────────────────────────────────────

# move shell out before cleanup trap fires
echo $$ > "${CGROUP_ROOT}/cgroup.procs" 2>/dev/null || true

banner "Summary — Step 2 Complete"
echo -e "  ${GRN}cgroups v2${RST}      unified hierarchy under /sys/fs/cgroup"
echo -e "  ${GRN}memory.max${RST}      hard memory ceiling → triggers OOM killer"
echo -e "  ${GRN}cpu.max${RST}         quota/period for CPU throttle"
echo -e "  ${GRN}pids.max${RST}        prevent fork bombs"
echo
echo -e "  ${BOLD}Namespaces${RST} = isolation  ${BOLD}cgroups${RST} = limits"
echo -e "  Together they form the two pillars of containers."
echo
echo -e "  ${YLW}Next:${RST} Step 3 — PID namespace isolation"
echo -e "  ${DIM}  cd ../3-proc && ./demo.sh${RST}"
echo
