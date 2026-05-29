# Layer 2 — Continuous rebalancing (the Descheduler = "DRS")

The Kube Descheduler Operator with the `KubeVirtRelieveAndMigrate` profile is
the OpenShift equivalent of vSphere DRS in Fully Automated mode.

## What it does

On every interval (`deschedulingIntervalSeconds`) it:

1. Reads each worker's **real load** — CPU/memory pressure from **PSI**, surfaced
   via `devActualUtilizationProfile: PrometheusCPUCombined`.
2. Flags nodes whose load is above the cluster average by more than the
   configured deviation (`devDeviationThresholds`).
3. **Evicts** VM pods from those hot nodes — which, for a VM with
   `evictionStrategy: LiveMigrate`, triggers a **live migration** to a cooler
   node.
4. Optionally **soft-taints** hot nodes (`devEnableSoftTainter: true`) so the
   *scheduler* also stops placing new VMs there until they cool down.

The net effect: VMs continuously drift toward an even spread of spare capacity —
exactly what DRS does with vMotion.

## The profiles, and which to use

| Profile | Use for Virt? | Notes |
|---|---|---|
| `KubeVirtRelieveAndMigrate` | Recommended | Load-aware, soft-tainting, background evictions. Requires PSI. The closest equivalent to DRS. |
| `LongLifecycle` | Stable fallback | Utilization-based (under 20% / over 50%), no PSI needed. Use when PSI is unavailable. |
| `LifecycleAndUtilization` | Avoid for VMs | General workloads; conflicts with LongLifecycle. |
| `AffinityAndTaints` | On by default | Evicts VMs that violate affinity/taints — useful, but not load balancing. |

Note: `KubeVirtRelieveAndMigrate`, `LongLifecycle`, and `LifecycleAndUtilization`
are mutually exclusive — enable only one.

## Predictive vs Automatic (automation level)

```yaml
spec:
  mode: Predictive   # DRS "Manual": logs/metrics what WOULD move; nothing moves
  # mode: Automatic  # DRS "Fully Automated": actually live-migrates VMs
```

To demonstrate this, start in `Predictive`, show the recommendations in
logs/metrics, then commit the change to `Automatic` and watch GitOps roll it out
and VMs begin migrating.

## Migration threshold — conservative vs aggressive

`devDeviationThresholds` maps to the DRS migration-aggressiveness slider:

| Value | Meaning | DRS slider |
|---|---|---|
| `AsymmetricLow` (0%:10%) | only treat clearly-hot nodes as overused; never over-drain | conservative (this demo's default) |
| `Low` / `Medium` / `High` (10/20/30 % both ways) | progressively more eager to move VMs | → aggressive |

## Prerequisites checklist

- [ ] OpenShift Virtualization installed; VMs are **live-migratable** (RWX
      storage, no blocking devices).
- [ ] **PSI enabled** on workers — `manifests/10-scheduling-infra/00-machineconfig-psi.yaml`
      (`psi=1`, name must sort after `98-*`; triggers a worker reboot).
- [ ] VMs keep `evictionStrategy: LiveMigrate` (the default) so eviction = migrate.
- [ ] `evictionLimits` ≤ HCO `liveMigrationConfig` limits.

## Excluding a VM from rebalancing

| Want | Set |
|---|---|
| Never auto-migrate, even for maintenance (pinned) | `evictionStrategy: None` (blocks node drains!) |
| Still migrate for maintenance, but skip load-balancing | annotation `descheduler.alpha.kubernetes.io/prefer-no-eviction: "true"` |

See `manifests/40-vms/20-*` and `21-*`.

## What the descheduler never evicts

`openshift-*` / `kube-system` / `hypershift` pods, `system-node-critical` /
`system-cluster-critical` pods, DaemonSet pods, and pods that would violate a
PodDisruptionBudget. That's why demo VMs live in the unprotected
`virt-drs-demo` namespace.

Next: [`03-live-migration.md`](03-live-migration.md) — the mechanism that
actually moves the guest.
