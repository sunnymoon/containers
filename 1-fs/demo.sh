#!/usr/bin/env bash
# =============================================================================
# Step 1 — Filesystem Isolation  |  INTERACTIVE DEMO
# Shows the progression: chroot → unshare+mount → pivot_root
# Run as root: sudo ./demo.sh
# =============================================================================

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'
BLU='\033[0;34m'; CYN='\033[0;36m'; MAG='\033[0;35m'
BOLD='\033[1m'; DIM='\033[2m'; RST='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOTFS="${SCRIPT_DIR}/rootfs"

# ── helpers ──────────────────────────────────────────────────────────────────

banner() {
    echo
    echo -e "${BLU}╔══════════════════════════════════════════════════════════════╗${RST}"
    echo -e "${BLU}║${RST}  ${BOLD}$1${RST}"
    echo -e "${BLU}╚══════════════════════════════════════════════════════════════╝${RST}"
    echo
}

step() {
    echo -e "${YLW}▶ ${BOLD}$*${RST}"
}

info() {
    echo -e "${CYN}  ℹ  $*${RST}"
}

warn() {
    echo -e "${RED}  ⚠  $*${RST}"
}

ok() {
    echo -e "${GRN}  ✔  $*${RST}"
}

cmd_preview() {
    echo -e "${DIM}  \$${RST} ${MAG}$*${RST}"
}

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

if [[ ! -d "$ROOTFS/bin" ]]; then
    warn "rootfs/ not found. Run ./setup.sh first!"
    exit 1
fi

# ── DEMO START ────────────────────────────────────────────────────────────────

clear
banner "Step 1 — Filesystem Isolation"

echo -e "  We'll go through three techniques:"
echo -e "  ${BLU}1.${RST} ${BOLD}chroot${RST}      — the 1979 classic"
echo -e "  ${BLU}2.${RST} ${BOLD}unshare${RST}     — proper mount namespace"
echo -e "  ${BLU}3.${RST} ${BOLD}pivot_root${RST}  — the container way"

pause

# ─────────────────────────────────────────────────────────────────────────────
banner "1/3 — chroot: the classic approach"

step "First, look at the HOST root filesystem:"
run_cmd "ls /"
echo

step "Now look at our Alpine rootfs (this will become '/'):"
run_cmd "ls ${ROOTFS}"
echo

step "Check HOST OS release:"
run_cmd "cat /etc/os-release | head -3"
echo

info "Entering chroot into Alpine rootfs..."
info "Type 'exit' when done. Try: ls / ; cat /etc/os-release ; hostname"
echo
cmd_preview "chroot ${ROOTFS} /bin/sh"
pause

chroot "${ROOTFS}" /bin/sh || true

echo
ok "Back on the host!"
warn "Observation: hostname was the same as host — not isolated at all."

pause

# ─────────────────────────────────────────────────────────────────────────────
banner "2/3 — unshare --mount: own mount namespace"

step "unshare creates a new namespace for us"
info "With --mount we get a private mount table — mounts here don't leak to host"
echo
cmd_preview "unshare --mount bash"
echo
info "Inside the shell, we'll bind-mount the rootfs and chroot into it."
info "Type 'exit' when done."
pause

unshare --mount bash -c "
    set -e
    echo '  [inside mount namespace]'
    echo
    echo '  \$ mount --bind ${ROOTFS} ${ROOTFS}'
    mount --bind '${ROOTFS}' '${ROOTFS}'

    echo '  \$ mount -t proc proc ${ROOTFS}/proc'
    mount -t proc proc '${ROOTFS}/proc'

    echo '  \$ mount -t sysfs sysfs ${ROOTFS}/sys'
    mount -t sysfs sysfs '${ROOTFS}/sys'

    echo
    echo '  Entering chroot (now with /proc and /sys)...'
    echo '  Try: ls /proc | head   ;   cat /proc/1/cmdline   ;   ps aux'
    echo
    chroot '${ROOTFS}' /bin/sh
" || true

echo
ok "Back on host. The bind mounts are GONE — they existed only in that namespace."
warn "But: /proc/1/cmdline showed the HOST init process — PIDs still leak through!"

pause

# ─────────────────────────────────────────────────────────────────────────────
banner "3/3 — pivot_root: the real container approach"

step "pivot_root swaps the root mount — not just a chdir trick."
info "pivot_root requires we are in a new mount namespace AND rootfs is a mount point."
echo
echo -e "  The trick:"
echo -e "  ${DIM}1.${RST} bind-mount rootfs/ onto itself  (make it a mount point)"
echo -e "  ${DIM}2.${RST} pivot_root . .oldroot           (swap root mount)"
echo -e "  ${DIM}3.${RST} mount /proc                     (fresh process view)"
echo -e "  ${DIM}4.${RST} umount -l /.oldroot             (hide host fs)"
echo
info "Commands to type manually:"
cmd_preview "unshare --mount bash"
cmd_preview "  mount --bind ${ROOTFS} ${ROOTFS}"
cmd_preview "  mkdir -p ${ROOTFS}/.oldroot"
cmd_preview "  cd ${ROOTFS} && pivot_root . .oldroot"
cmd_preview "  mount -t proc proc /proc"
cmd_preview "  umount -l /.oldroot"
cmd_preview "  ls /       # only Alpine!"
cmd_preview "  ls /.oldroot   # should fail or be empty"
pause

info "Running it for you now — type 'exit' when done:"
echo

unshare --mount bash -c "
    set -e
    ROOTFS='${ROOTFS}'

    echo -e '\033[2m  \$\033[0m \033[0;35mmount --bind \$ROOTFS \$ROOTFS\033[0m'
    mount --bind \"\$ROOTFS\" \"\$ROOTFS\"

    echo -e '\033[2m  \$\033[0m \033[0;35mmkdir -p \$ROOTFS/.oldroot\033[0m'
    mkdir -p \"\$ROOTFS/.oldroot\"

    echo -e '\033[2m  \$\033[0m \033[0;35mcd \$ROOTFS && pivot_root . .oldroot\033[0m'
    cd \"\$ROOTFS\"
    pivot_root . .oldroot

    echo -e '\033[2m  \$\033[0m \033[0;35mmount -t proc proc /proc\033[0m'
    mount -t proc proc /proc

    echo -e '\033[2m  \$\033[0m \033[0;35mumount -l /.oldroot\033[0m'
    umount -l /.oldroot

    echo
    echo '  ✔  Root is now the Alpine filesystem!'
    echo '  Try: ls /    ls /.oldroot    cat /etc/os-release    cat /proc/mounts'
    echo
    exec /bin/sh
" || true

echo
ok "Excellent! The host filesystem was completely hidden."
ok "That is how real container runtimes (runc, crun) isolate the root."

pause

banner "Summary — Step 1 Complete"
echo -e "  ${GRN}chroot${RST}       simple, old, escap­able"
echo -e "  ${GRN}unshare --mount${RST}   private mount table, but still uses chdir trick"
echo -e "  ${GRN}pivot_root${RST}   replaces root mount — the container way"
echo
echo -e "  ${YLW}Next:${RST} Step 2 — Resource limits with cgroups"
echo -e "  ${DIM}  cd ../2-mem && ./demo.sh${RST}"
echo
