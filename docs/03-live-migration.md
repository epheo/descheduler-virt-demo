# Layer 3 — Live migration, maintenance & HA (the "vMotion")

Live migration is the mechanism that moves a **running** guest from one node to
another with no downtime. Both Layer 2 (descheduler rebalancing) and
maintenance drains rely on it.

## Eviction strategies — what happens when a node is drained or a VM is evicted

Set per-VM at `spec.template.spec.evictionStrategy`, or cluster-wide at
`HyperConverged.spec.evictionStrategy`.

| Strategy | Behavior | When to use |
|---|---|---|
| `LiveMigrate` (default, multi-node) | VM live-migrates on drain/eviction | normal migratable VMs |
| `LiveMigrateIfPossible` | migrate if migratable, otherwise leave running | VMs that *might* be non-migratable; **won't block upgrades** |
| `None` | never auto-migrate (pinned) | latency/licence-pinned VMs; **blocks node drains** |

Note: a non-migratable VM with `LiveMigrate` can block a node drain or cluster
upgrade indefinitely (migration stuck Pending). For such VMs use
`LiveMigrateIfPossible` or `None`.

## Tuning migrations (HyperConverged)

`manifests/30-live-migration/00-hyperconverged-livemigration.yaml.patch`:

```yaml
spec:
  liveMigrationConfig:
    bandwidthPerMigration: 64Mi          # cap so rebalancing can't saturate net
    parallelMigrationsPerCluster: 5      # ↔ descheduler evictionLimits.total
    parallelOutboundMigrationsPerNode: 2 # ↔ descheduler evictionLimits.node
    completionTimeoutPerGiB: 800
    progressTimeout: 150
    allowPostCopy: false                 # true for heavy/busy guests
```

Keep these in lockstep with the descheduler's `evictionLimits` so DRS-style
rebalancing never queues more migrations than the cluster will actually run.

## Migration policies (per-group migration tuning)

`MigrationPolicy` applies different migration settings to groups of VMs selected
by VM/namespace **labels** — e.g. fast/aggressive migration for `production`
VMs. See `manifests/30-live-migration/01-migration-policy-production.yaml`. The
policy with the most matching labels wins.

## Maintenance mode (evacuate a host)

The DRS "enter maintenance mode" equivalent:

```bash
oc adm cordon <node>                 # stop new placements
oc adm drain <node> --delete-emptydir-data --ignore-daemonsets
# VMs with LiveMigrate evacuate via live migration automatically.
```

OpenShift Virtualization also offers a **NodeMaintenance** CR (Node Maintenance
Operator) for a declarative, GitOps-friendly version of the same evacuation.

## High availability (host failure)

Live migration handles *graceful* moves. For a *failed* node:

- VMs with `runStrategy: Always` (or `RerunOnFailure`) are **re-created** on a
  healthy node — note this is a fresh boot, not a live move (the source is gone).
- This requires the node to actually be removed/fenced. With **Machine Health
  Checks** (installer-provisioned infra) the failed machine is auto-remediated
  and VMs reschedule. Without MHC on bare metal you must `oc delete node`
  manually to trigger failover.

| Concern | vSphere | OpenShift |
|---|---|---|
| Graceful move | vMotion | live migration (`LiveMigrate`) |
| Host failure restart | vSphere HA | `runStrategy: Always` + Machine Health Checks / fencing |

## Run strategies

`spec.runStrategy`: `Always` (keep a VMI running; restart/reschedule on failure),
`RerunOnFailure`, `Manual`, `Halted`. For HA behavior use `Always`.

Next: [`04-gitops.md`](04-gitops.md) — managing all of the above from Git.
