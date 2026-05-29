#!/usr/bin/env bash
# demo-up.sh -- bootstrap the OpenShift Virtualization DRS/GitOps demo.
#
# Two ways to run the demo:
#   GitOps path (recommended): this script installs the GitOps operator and
#                              applies the root app-of-apps. Argo CD does the
#                              rest. (Edit repoURL in gitops/** first only if
#                              you forked this repo.)
#   Direct path (no Git):      pass --direct to `oc apply` the manifests
#                              yourself, skipping Argo CD entirely.
#
# Usage:
#   ./demo-up.sh            # GitOps app-of-apps
#   ./demo-up.sh --direct   # apply manifests directly with oc
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

CNV_NS="openshift-cnv"

require() { command -v "$1" >/dev/null || { echo "ERROR: '$1' not found in PATH"; exit 1; }; }
require oc

patch_live_migration() {
  echo "==> Patching HyperConverged with live-migration limits + LiveMigrate eviction strategy"
  if oc get hyperconverged kubevirt-hyperconverged -n "$CNV_NS" >/dev/null 2>&1; then
    oc patch hyperconverged kubevirt-hyperconverged -n "$CNV_NS" --type=merge \
      --patch-file manifests/30-live-migration/00-hyperconverged-livemigration.yaml.patch
  else
    echo "    WARNING: HyperConverged not found in $CNV_NS -- is OpenShift Virtualization installed? Skipping."
  fi
}

if [[ "${1:-}" == "--direct" ]]; then
  echo "==> DIRECT MODE: applying manifests with oc (no Argo CD)"
  oc apply -f manifests/00-namespaces/
  oc apply -f manifests/10-scheduling-infra/
  echo "    Waiting for worker MachineConfigPool to finish the PSI reboot..."
  oc wait mcp worker --for=condition=Updated=True --timeout=-1s
  oc apply -f manifests/20-descheduler/00-namespace.yaml
  oc apply -f manifests/20-descheduler/01-operatorgroup.yaml
  oc apply -f manifests/20-descheduler/02-subscription.yaml
  echo "    Waiting for the KubeDescheduler CRD to register..."
  until oc get crd kubedeschedulers.operator.openshift.io >/dev/null 2>&1; do sleep 5; done
  oc apply -f manifests/20-descheduler/03-kubedescheduler-drs.yaml
  patch_live_migration
  oc apply -f manifests/30-live-migration/01-migration-policy-production.yaml
  oc apply -f manifests/40-vms/
  echo "==> Direct apply complete."
else
  echo "==> GITOPS MODE"
  echo "    repoURL in gitops/** points at github.com/epheo/descheduler-virt-demo.git (edit only if you forked)"
  echo "==> Installing Red Hat OpenShift GitOps operator"
  oc apply -f gitops/bootstrap/00-gitops-operator.yaml
  echo "    Waiting for the openshift-gitops namespace + Argo CD to come up..."
  until oc get ns openshift-gitops >/dev/null 2>&1; do sleep 5; done
  oc rollout status deploy/openshift-gitops-server -n openshift-gitops --timeout=600s || true
  echo "==> Applying the app-of-apps root Application"
  oc apply -f gitops/bootstrap/01-root-app.yaml
  patch_live_migration
  echo "==> Argo CD will now sync the demo. Watch it with:"
  echo "    oc get applications -n openshift-gitops -w"
fi

echo
echo "Next: ./scripts/watch-migrations.sh   (see VMs and live migrations)"
echo "      ./scripts/generate-load.sh      (create node pressure -> DRS rebalances)"
