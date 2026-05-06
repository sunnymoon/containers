#!/usr/bin/env bash
# =============================================================================
# Step 4 — UTS Namespace + Composing All Namespaces  |  INTERACTIVE DEMO
# Shows: hostname isolation, then combines ALL namespaces built so far
# Run as root: sudo ./demo.sh
# =============================================================================
#
# WHY IS IT CALLED "UTS"?
# UTS stands for UNIX Time-sharing System — a 1970s operating system from Bell
# Labs that introduced the concept of a system identity (hostname + NIS domain).
# The kernel struct holding this identity is literally named `struct utsname`
# (from the uname(2) syscall), and it has always contained:
#   - nodename   → what we call "hostname"
#   - domainname → the NIS/YP domain name (not DNS)
# The UTS namespace isolates that entire struct per process group, so each
# container can have its own hostname without touching the host's utsname.
# The name "UTS namespace" is purely historical — it means "namespace that
# isolates the utsname struct", not anything to do with time-sharing today.
# =============================================================================

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'
BLU='\033[0;34m'; CYN='\033[0;36m'; MAG='\033[0;35m'
BOLD='\033[1m'; DIM='\033[2m'; RST='\033[0m'

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

# ── DEMO START ────────────────────────────────────────────────────────────────

clear
banner "Step 4 — UTS Namespace + Composing Namespaces"

echo -e "  ${BOLD}UTS${RST} = UNIX Time-sharing System"
echo -e "  The UTS namespace isolates two things: ${BOLD}hostname${RST} and ${BOLD}NIS domain name${RST}."
echo
echo -e "  ${DIM}┌─ Historical sidebar nobody asked for but you're getting anyway ──────────┐${RST}"
echo -e "  ${DIM}│${RST}  In the 1970s Bell Labs built UNIX Time-sharing System (UTS).            ${DIM}│${RST}"
echo -e "  ${DIM}│${RST}  The kernel kept system identity in a struct called ${BOLD}utsname${RST} — holding   ${DIM}│${RST}"
echo -e "  ${DIM}│${RST}  nodename (hostname) and domainname (NIS). Fast-forward 50 years:        ${DIM}│${RST}"
echo -e "  ${DIM}│${RST}  Linux namespaces isolate that struct, and the feature is named after    ${DIM}│${RST}"
echo -e "  ${DIM}│${RST}  it. So yes — Docker sets your container hostname by exploiting a        ${DIM}│${RST}"
echo -e "  ${DIM}│${RST}  struct named after a 1970s timesharing OS. Legacy: it never dies.       ${DIM}│${RST}"
echo -e "  ${DIM}└──────────────────────────────────────────────────────────────────────────┘${RST}"
echo
echo -e "  We'll show:"
echo -e "  ${BLU}1.${RST} Hostname isolation in a UTS namespace"
echo -e "  ${BLU}2.${RST} Composing all namespaces together"
echo -e "  ${BLU}3.${RST} The final 'hand-rolled container'"

pause

# ─────────────────────────────────────────────────────────────────────────────
banner "1/3 — UTS namespace: hostname isolation"

step "Current host hostname:"
run_cmd "hostname"
echo
step "Current host domainname:"
run_cmd "hostname --fqdn 2>/dev/null || domainname 2>/dev/null || echo '(none)'"
echo

step "Enter a new UTS namespace:"
info "Inside, change the hostname. Notice it does NOT affect the host."
info "Try:"
info "  hostname                    # same as host at first"
info "  hostname my-container       # change it!"
info "  hostname                    # my-container"
info "  cat /etc/hostname           # still the host file (shared fs)"
echo
echo -e "${DIM}  \$${RST} ${MAG}unshare --uts bash -c '...'${RST}"

HOST_HOSTNAME=$(hostname)

unshare --uts bash -c "
    echo
    echo -e '  \033[1;32m✔  Inside UTS namespace!\033[0m'
    echo -e '  Current hostname: \033[1m'\$(hostname)'\033[0m  (still host value, copied in)'
    echo
    hostname my-container
    echo -e '  \033[1;33m▶\033[0m Changed to: \033[1m'\$(hostname)'\033[0m'
    echo -e '  uname -n: '\$(uname -n)
" || true

echo
step "Back on host — verify hostname is unchanged:"
run_cmd "hostname"
[[ "$(hostname)" == "$HOST_HOSTNAME" ]] && ok "Host hostname preserved: ${HOST_HOSTNAME}"

pause

# ─────────────────────────────────────────────────────────────────────────────
banner "2/3 — UTS + PID + Mount: composing namespaces"

step "Each --flag adds one namespace. Let's combine what we have:"
echo
echo -e "  ${MAG}unshare \\\\${RST}"
echo -e "  ${MAG}  --mount       \\\\${RST}  ${DIM}# own mount table${RST}"
echo -e "  ${MAG}  --pid         \\\\${RST}  ${DIM}# own PID space${RST}"
echo -e "  ${MAG}  --uts         \\\\${RST}  ${DIM}# own hostname${RST}"
echo -e "  ${MAG}  --fork        \\\\${RST}  ${DIM}# fork so child gets PID 1${RST}"
echo -e "  ${MAG}  --mount-proc  \\\\${RST}  ${DIM}# fresh /proc${RST}"
echo -e "  ${MAG}  bash${RST}"
echo
info "Inside, try:"
info "  echo \$\$      → 1"
info "  hostname     → host's name"
info "  hostname container-mk1"
info "  hostname     → container-mk1"
info "  ps aux       → only shell and ps"
echo
echo -e "${DIM}  \$${RST} ${MAG}unshare --mount --pid --uts --fork --mount-proc bash -c '...'${RST}"

unshare --mount --pid --uts --fork --mount-proc bash -c "
    echo
    echo -e '  \033[1;32m✔  PID + Mount + UTS namespace!\033[0m'
    echo -e \"  PID: \$\$\"
    hostname container-mk1
    echo -e \"  Hostname: \$(hostname)\"
    echo -e '  Processes:'
    ps -ef
" || true

ok "Exited combined namespace."

pause

# ─────────────────────────────────────────────────────────────────────────────
banner "3/3 — The hand-rolled container"

if [[ ! -d "${ROOTFS}/bin" ]]; then
    warn "Alpine rootfs not found at ${ROOTFS}"
    warn "Run cd ../1-fs && ./setup.sh  to download it first."
    info "Skipping pivot_root demo — showing namespace flags only."
    pause
else

step "Now we combine EVERYTHING from steps 1-4:"
echo
echo -e "  ${MAG}unshare --mount --pid --uts --fork bash${RST}"
echo -e "  ${DIM}  (inside)${RST}"
echo -e "  ${MAG}    mount --bind ${ROOTFS} ${ROOTFS}${RST}"
echo -e "  ${MAG}    mount -t proc proc ${ROOTFS}/proc${RST}"
echo -e "  ${MAG}    mkdir -p ${ROOTFS}/.oldroot${RST}"
echo -e "  ${MAG}    cd ${ROOTFS} && pivot_root . .oldroot${RST}"
echo -e "  ${MAG}    hostname hand-rolled-container${RST}"
echo -e "  ${MAG}    umount -l /.oldroot${RST}"
echo -e "  ${MAG}    exec /bin/sh${RST}"
echo
info "Inside you'll see:"
info "  → Alpine root filesystem (pivot_root)"
info "  → Own PID space (PID 1)"
info "  → Custom hostname"
info "  → Clean /proc"
echo

echo -e "${DIM}  \$${RST} ${MAG}unshare --mount --pid --uts --fork bash${RST}"

unshare --mount --pid --uts --fork bash -c "
    set -e
    ROOTFS='${ROOTFS}'

    # Mount namespace setup
    mount --bind \"\$ROOTFS\" \"\$ROOTFS\"
    mount -t proc proc \"\$ROOTFS/proc\"
    mount -t sysfs sysfs \"\$ROOTFS/sys\" 2>/dev/null || true
    mkdir -p \"\$ROOTFS/.oldroot\"

    # UTS: set hostname before pivot
    hostname hand-rolled-container

    # Filesystem: pivot_root
    cd \"\$ROOTFS\"
    pivot_root . .oldroot
    umount -l /.oldroot
    hash -r

    echo
    echo -e '  \033[1;32m╔═══════════════════════════════════════════╗\033[0m'
    echo -e '  \033[1;32m║  Hand-rolled container is running!       ║\033[0m'
    echo -e '  \033[1;32m╚═══════════════════════════════════════════╝\033[0m'
    echo
    echo -e '  hostname:        '\$(cat /proc/sys/kernel/hostname)
    echo -e '  PID (we are 1):  '\$\$
    echo -e '  /etc/os-release:'
    grep PRETTY /etc/os-release 2>/dev/null || head -2 /etc/os-release
    echo
    echo -e '  ps:'
    ps 2>/dev/null || ls /proc | grep '^[0-9]'
" || true

echo
ok "Exited the hand-rolled container!"

fi # end rootfs check

pause

banner "Summary — Step 4 Complete"
echo -e "  ${GRN}unshare --uts${RST}       isolated hostname & domain name"
echo -e "  ${GRN}hostname <name>${RST}     changes apply only inside the UTS namespace"
echo
echo -e "  ${BOLD}Namespaces composed so far:${RST}"
echo -e "  ${GRN}--mount${RST}   → own filesystem view"
echo -e "  ${GRN}--pid${RST}     → own PID space, appears as PID 1"
echo -e "  ${GRN}--uts${RST}     → own hostname"
echo
echo -e "  ${BLU}Still missing:${RST}  network isolation — the process shares the host network stack!"
echo
echo -e "  ${YLW}Next:${RST} Step 5 — Network namespace + veth pair"
echo -e "  ${DIM}  cd ../5-net && ./demo.sh${RST}"
echo
