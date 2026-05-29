# 10-scheduling-infra

Cluster prerequisites for load-aware, DRS-style rebalancing.

## `00-machineconfig-psi.yaml`

Enables **PSI (Pressure Stall Information)** on worker nodes via the `psi=1`
kernel argument. The `KubeVirtRelieveAndMigrate` descheduler profile is
load-aware — it needs PSI to read each node's real CPU/memory pressure.

- The name must sort after any `98-*` MachineConfig (which disables PSI by
  default), hence the `99-` prefix.
- Applying this triggers a rolling reboot of the `worker` MachineConfigPool.
  Do it before a live demo and wait:
  ```bash
  oc wait mcp worker --for=condition=Updated=True --timeout=-1s
  ```
- Verify on a node:
  ```bash
  oc debug node/<worker> -- cat /proc/pressure/cpu   # non-empty = PSI on
  ```

## Node labels & taints (do this by hand)

The example VMs in `../40-vms` expect a couple of node groups. These are
per-cluster and not GitOps-managed here; create them once:

```bash
oc label node <n1> node-role.kubernetes.io/vm-zone=gold disktype=ssd cpu-class=high
oc label node <n2> node-role.kubernetes.io/vm-zone=silver
# Optional dedicated host:
oc adm taint node <n1> dedicated=virtualization:NoSchedule
```

If you can't enable PSI, skip this profile and use the `LongLifecycle` fallback
(`../20-descheduler/03-kubedescheduler-longlifecycle.yaml.alt`).
