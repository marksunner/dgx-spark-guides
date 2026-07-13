#!/usr/bin/env bash
# preflight.sh — Auto-detect RoCE v2 GID indices before launching.
#
# The RoCE GID table on DGX Spark is NOT stable across reboots.
# An IPv4-mapped GID entry can shift to a different index after a
# power cycle. If NCCL_GID_INDEX in your launch script doesn't match,
# you get "WorkerProc initialization failed" — no error message,
# no obvious clue, just a silent crash during NCCL init.
#
# This script checks every node, compares against launch-castle.sh,
# and (with --fix) auto-updates the GID array.
#
# Usage:  ./preflight.sh          (check)
#         ./preflight.sh --fix    (check + auto-update)
#
set -uo pipefail

SAY() { printf '\n\033[1;34m  %s\033[0m\n' "$*"; }
OK()  { printf '  \033[32m✓ %s\033[0m\n' "$*"; }
WARN() { printf '  \033[33m⚠ %s\033[0m\n' "$*"; }
ERR() { printf '  \033[31m✗ %s\033[0m\n' "$*"; }

# ---- EDIT THESE to match your cluster ----
NODES=(${QSFP_1} ${QSFP_2} ${QSFP_3} ${QSFP_4})
USERS=(${SPARK_USER} ${SPARK_USER} ${SPARK_USER} ${SPARK_USER})
HCA=(${NCCL_HCA_1} ${NCCL_HCA_2} ${NCCL_HCA_3} ${NCCL_HCA_4})
# -------------------------------------------

FIX=false
[ "${1:-}" = "--fix" ] && FIX=true

SAY "GLM 5.2 Pre-Flight: RoCE v2 GID Check"
echo "  Verifying each node resolves its fabric IP via RoCE v2..."
echo

GID_FOUND=()
ALL_OK=true

for i in "${!NODES[@]}"; do
  node="${NODES[$i]}"
  user="${USERS[$i]}"
  hca="${HCA[$i]}"

  if [ "$i" = 0 ]; then
    gid=$(ibv_devinfo -v "$hca" 2>/dev/null | grep "GID\[" | grep "::ffff:${node}, RoCE v2" | head -1 | sed -E 's/.*GID\[ *([0-9]+)\].*/\1/')
  else
    gid=$(ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      "$user@$node" \
      "ibv_devinfo -v $hca 2>/dev/null | grep 'GID\[' | grep '::ffff:${node}, RoCE v2' | head -1 | sed -E 's/.*GID\[ *([0-9]+)\].*/\1/'" 2>/dev/null)
  fi

  if [ -z "$gid" ]; then
    ERR "Node $((i+1)): $node — GID(v2) NOT FOUND on $hca"
    ALL_OK=false
    GID_FOUND+=(0)
  else
    printf '  Node %d: %-12s  GID=%-2s  HCA=%s\n' "$((i+1))" "$node" "$gid" "$hca"
    GID_FOUND+=("$gid")
  fi
done

NEW_GID_STR="${GID_FOUND[0]} ${GID_FOUND[1]} ${GID_FOUND[2]} ${GID_FOUND[3]}"

if [ -f launch-castle.sh ]; then
  CURRENT_GID_STR=$(grep -oP 'NCCL_GID=\(\K[^)]+' launch-castle.sh)

  echo
  echo "  launch-castle.sh: NCCL_GID=($CURRENT_GID_STR)"
  echo "  live cluster:     NCCL_GID=($NEW_GID_STR)"

  if [ "$CURRENT_GID_STR" = "$NEW_GID_STR" ]; then
    OK "GID indices match — ready to launch."
  elif $FIX; then
    sed -i "s/NCCL_GID=($CURRENT_GID_STR)/NCCL_GID=($NEW_GID_STR)/" launch-castle.sh
    OK "Auto-fixed: launch-castle.sh now NCCL_GID=($NEW_GID_STR)"
  else
    WARN "GID MISMATCH — run ./preflight.sh --fix to correct"
    ALL_OK=false
  fi
fi

echo
if $ALL_OK; then
  echo -e '\033[32m✓ Pre-flight passed. Clear to launch.\033[0m'
  exit 0
else
  echo -e '\033[33m⚠ Run ./preflight.sh --fix before launching.\033[0m'
  exit 1
fi
