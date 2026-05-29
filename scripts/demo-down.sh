#!/usr/bin/env bash
# demo-down.sh -- tear the demo back down.
# Usage: ./demo-down.sh [--direct]
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
require() { command -v "$1" >/dev/null || { echo "ERROR: '$1' not found"; exit 1; }; }
require oc

echo "==> Deleting demo VMs (incl. load generators)"
oc delete vm -n virt-drs-demo -l app=drs-demo --ignore-not-found
oc delete vm -n virt-drs-demo -l role=load-generator --ignore-not-found

if [[ "${1:-}" == "--direct" ]]; then
  echo "==> DIRECT teardown"
  oc delete -f manifests/30-live-migration/01-migration-policy-production.yaml --ignore-not-found
  oc delete -f manifests/20-descheduler/03-kubedescheduler-drs.yaml --ignore-not-found
  oc delete -f manifests/20-descheduler/02-subscription.yaml --ignore-not-found
  oc delete -f manifests/20-descheduler/01-operatorgroup.yaml --ignore-not-found
  oc delete -f manifests/00-namespaces/ --ignore-not-found
  echo "    NOTE: the PSI MachineConfig is left in place (removing it reboots workers)."
  echo "          Remove manually if desired: oc delete -f manifests/10-scheduling-infra/00-machineconfig-psi.yaml"
else
  echo "==> GITOPS teardown: deleting the root app cascades to all children"
  oc delete -f gitops/bootstrap/01-root-app.yaml --ignore-not-found
  echo "    NOTE: the GitOps operator and PSI MachineConfig are left in place."
fi

echo "==> Reverting HyperConverged live-migration overrides (best effort)"
oc patch hyperconverged kubevirt-hyperconverged -n openshift-cnv --type=json \
  -p='[{"op":"remove","path":"/spec/liveMigrationConfig"}]' 2>/dev/null || true

echo "==> Done."
