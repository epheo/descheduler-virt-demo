#!/usr/bin/env bash
# generate-load.sh -- create node pressure so the load-aware descheduler
# (KubeVirtRelieveAndMigrate) rebalances VMs, the OpenShift equivalent of a DRS
# vMotion to even out load.
#
# Strategy: clone the balanced VM N times and run stress-ng inside each guest so
# real CPU/PSI load builds on whatever node they land on. Once one node is
# measurably hotter than the cluster average (devDeviationThresholds:
# AsymmetricLow = 10% over avg), the descheduler live-migrates VMs away.
#
# Usage: ./generate-load.sh [count]   (default 6)
set -euo pipefail

NS="virt-drs-demo"
COUNT="${1:-6}"
require() { command -v "$1" >/dev/null || { echo "ERROR: '$1' not found"; exit 1; }; }
require oc

echo "==> Creating $COUNT CPU-stressing VMs in $NS"
for i in $(seq 1 "$COUNT"); do
  name="vm-load-$(printf '%02d' "$i")"
  cat <<EOF | oc apply -f -
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: ${name}
  namespace: ${NS}
  labels:
    app: drs-demo
    role: load-generator
    kubevirt.io/environment: production
spec:
  runStrategy: Always
  template:
    metadata:
      labels:
        kubevirt.io/domain: ${name}
        kubevirt.io/environment: production
    spec:
      evictionStrategy: LiveMigrate
      domain:
        cpu:
          cores: 2
        memory:
          guest: 2Gi
        devices:
          disks:
            - name: rootdisk
              disk: { bus: virtio }
            - name: cloudinitdisk
              disk: { bus: virtio }
          interfaces:
            - name: default
              masquerade: {}
      networks:
        - name: default
          pod: {}
      volumes:
        - name: rootdisk
          containerDisk:
            image: quay.io/containerdisks/fedora:latest
        - name: cloudinitdisk
          cloudInitNoCloud:
            userData: |
              #cloud-config
              password: fedora
              chpasswd: { expire: False }
              packages:
                - stress-ng
              runcmd:
                - [ "bash", "-c", "stress-ng --cpu 2 --timeout 1800s &" ]
EOF
done

echo
echo "==> Load VMs created. Watch them get rebalanced:"
echo "    ./scripts/watch-migrations.sh"
echo "==> Tear down just the load with:"
echo "    oc delete vm -n $NS -l role=load-generator"
