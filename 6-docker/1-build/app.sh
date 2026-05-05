#!/usr/bin/env bash
set -euo pipefail

echo "Container started from Docker image layer demo"
echo "Hostname: $(hostname)"
echo "Kernel: $(uname -r)"
echo "User: $(id -un)"
echo "Demo name: ${DEMO_NAME:-unset}"

echo
echo "Networking snapshot:"
ip addr show | sed -n '1,18p'

echo
echo "Process table snapshot:"
ps aux | sed -n '1,12p'
