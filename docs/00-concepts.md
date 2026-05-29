# Concepts: VMware DRS → OpenShift Virtualization

vSphere administrators treat DRS (Distributed Resource Scheduler) as a single
feature. OpenShift has no single "DRS" object; the same outcomes are produced by
three cooperating layers, all declared as YAML and driven by GitOps:

```
                 ┌───────────────────────────────────────────────┐
   New VM  ──▶   │ 1. kube-scheduler        (INITIAL PLACEMENT)    │
                 │    nodeSelector · affinity · taints · spread    │
                 └───────────────────────────────────────────────┘
                                     │  VM running on a node
                                     ▼
                 ┌───────────────────────────────────────────────┐
   Cluster ──▶   │ 2. Descheduler           (CONTINUOUS BALANCE)  │  ← "DRS"
   drifts        │    KubeVirtRelieveAndMigrate (load-aware)       │
                 │    evicts VM ⇒ triggers live migration          │
                 └───────────────────────────────────────────────┘
                                     │  eviction
                                     ▼
                 ┌───────────────────────────────────────────────┐
   Move    ──▶   │ 3. Live migration        (THE vMOTION)         │
                 │    evictionStrategy LiveMigrate · MigrationPolicy│
                 └───────────────────────────────────────────────┘
```

## Summary

"DRS" in OpenShift Virtualization is the Kube Descheduler Operator running the
`KubeVirtRelieveAndMigrate` profile in `Automatic` mode. It watches real node
load (via PSI/Prometheus) and live-migrates VMs off hot nodes to keep spare
capacity even — the same role vMotion plays for DRS.

## Mapping table

| VMware vSphere | OpenShift Virtualization | Where in this repo |
|---|---|---|
| DRS cluster | `KubeDescheduler` object named `cluster` | `manifests/20-descheduler/03-kubedescheduler-drs.yaml` |
| DRS automation: **Fully Automated** | `spec.mode: Automatic` | same file |
| DRS automation: **Manual / recommendations** | `spec.mode: Predictive` (dry-run) | same file |
| DRS **migration threshold** (conservative ↔ aggressive) | `profileCustomizations.devDeviationThresholds` (`AsymmetricLow`…`High`) | same file |
| DRS invocation interval | `spec.deschedulingIntervalSeconds` | same file |
| Load metric = real host CPU | `devActualUtilizationProfile: PrometheusCPUCombined` (needs PSI) | same file + `10-scheduling-infra` |
| **vMotion** | live migration | `manifests/30-live-migration` |
| Max concurrent vMotions | `evictionLimits` ↔ HCO `liveMigrationConfig` | `20-descheduler` + `30-live-migration` |
| VM/Host affinity rule (**must run on**) | `nodeSelector` / node affinity `required…` | `40-vms/10`, `40-vms/11` |
| VM/Host affinity rule (**should run on**) | node affinity `preferred…` | `40-vms/11` |
| **Separate Virtual Machines** anti-affinity | pod anti-affinity, `topologyKey: hostname` | `40-vms/12` |
| Dedicated hosts / host group | node taints + VM tolerations | `40-vms/13` |
| Even spread across hosts/racks | pod topology spread constraints | `docs/01-scheduling.md` |
| DRS automation **Disabled** on a VM (pinned) | `evictionStrategy: None` | `40-vms/20` |
| Migratable for maintenance but **excluded from load-balancing** | `descheduler.alpha.kubernetes.io/prefer-no-eviction` | `40-vms/21` |
| Enter Maintenance Mode (evacuate host) | `oc adm drain` / Node Maintenance + `LiveMigrate` | `docs/03-live-migration.md` |
| HA: restart VMs of a failed host | `runStrategy: Always` + machine health checks | `docs/03-live-migration.md` |
| vCenter as the single config plane | **Argo CD / OpenShift GitOps** (Git is the source of truth) | `gitops/` |

## Why three layers instead of one?

- **The scheduler only acts once**, at placement. Affinity rules are
  `IgnoredDuringExecution` — a running VM is never moved just because its node
  stopped matching.
- **The descheduler closes that gap.** It re-evaluates the cluster on an
  interval and evicts VMs that are now mis-placed or on overloaded nodes. For
  VMs, eviction is non-destructive: it becomes a **live migration**.
- **Live migration is the mechanism** both maintenance drains and the
  descheduler rely on to move a running guest without downtime.

GitOps (Argo CD) ties it together: the DRS policy, the scheduling rules, and the
VMs themselves are all versioned YAML, reconciled continuously — the analog of
having one authoritative vCenter config, but auditable in Git.

See [`05-demo-runbook.md`](05-demo-runbook.md) for the live walkthrough.
