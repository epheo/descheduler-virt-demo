#!/usr/bin/env bash
# watch-migrations.sh -- live view of VM placement and in-flight migrations.
set -euo pipefail
NS="virt-drs-demo"
require() { command -v "$1" >/dev/null || { echo "ERROR: '$1' not found"; exit 1; }; }
require oc

watch -n 3 "
echo '===== VMs and the NODE each runs on (watch the NODE column change) ====='
oc get vmi -n $NS -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,NODE:.status.nodeName 2>/dev/null
echo
echo '===== In-flight live migrations (descheduler-driven rebalancing) ====='
oc get virtualmachineinstancemigrations -n $NS -o custom-columns=NAME:.metadata.name,VMI:.spec.vmiName,PHASE:.status.phase 2>/dev/null
echo
echo '===== Node CPU load (the signal the load-aware descheduler reacts to) ====='
oc adm top nodes -l node-role.kubernetes.io/worker 2>/dev/null || echo '(metrics not ready)'
"
