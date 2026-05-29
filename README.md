# OpenShift Virtualization — DRS-style Scheduling with GitOps

A self-contained, GitOps-driven demo.

| Layer | OpenShift feature | vSphere analog |
|---|---|---|
| **1. Initial placement** | kube-scheduler: `nodeSelector`, affinity, taints, topology spread | DRS initial placement + VM/Host rules |
| **2. Continuous rebalancing** | **Descheduler `KubeVirtRelieveAndMigrate`** (load-aware, live-migrates VMs) | **DRS, Fully Automated** |
| **3. The move itself** | live migration, `evictionStrategy`, `MigrationPolicy` | **vMotion** |
| **0. Control plane** | **Argo CD / OpenShift GitOps** (Git = source of truth) | vCenter as authoritative config |

Targets OpenShift 4.22 and OpenShift Virtualization.

---

## The descheduler ("DRS") object

The DRS policy is a `KubeDescheduler` named `cluster`, in
[`manifests/20-descheduler/03-kubedescheduler-drs.yaml`](manifests/20-descheduler/03-kubedescheduler-drs.yaml)
(fully commented). The knobs that matter:

- `mode: Automatic` — DRS "Fully Automated" (`Predictive` = dry-run)
- `profiles: [KubeVirtRelieveAndMigrate]` — the load-aware, live-migrating profile
- `devDeviationThresholds: AsymmetricLow` — migration-aggressiveness threshold
- `evictionLimits: {node: 2, total: 5}` — max concurrent live migrations

It watches real node load (PSI/Prometheus) and live-migrates VMs off hot nodes
to keep spare capacity even — the same outcome DRS produces with vMotion.

---

## Repository layout

```
descheduler-virt-demo/
├── README.md                  overview and quick start
├── docs/                      documentation
│   ├── 00-concepts.md           DRS → OpenShift mapping (start here)
│   ├── 01-scheduling.md         Layer 1: placement
│   ├── 02-descheduler-drs.md    Layer 2: the "DRS" engine
│   ├── 03-live-migration.md     Layer 3: vMotion, maintenance, HA
│   ├── 04-gitops.md             Layer 0: Argo CD app-of-apps
│   └── 05-demo-runbook.md       step-by-step live walkthrough
├── gitops/                    Argo CD: bootstrap + app-of-apps
│   ├── bootstrap/               install Argo CD + root Application (apply once)
│   └── applications/            sync-wave-ordered child Applications
├── manifests/                 everything Argo CD (or oc) applies
│   ├── 00-namespaces/           demo namespace
│   ├── 10-scheduling-infra/     PSI MachineConfig (load-aware prerequisite)
│   ├── 20-descheduler/          the DRS engine (operator + KubeDescheduler)
│   ├── 30-live-migration/       HCO live-migration patch + MigrationPolicy
│   └── 40-vms/                  demo VMs, one per scheduling concept
└── scripts/
    ├── demo-up.sh               bootstrap (GitOps or --direct)
    ├── generate-load.sh         create node pressure → triggers rebalancing
    ├── watch-migrations.sh      live VM/migration dashboard
    └── demo-down.sh             teardown
```

Each VM in `manifests/40-vms/` demonstrates one scheduling concept; see the full
mapping in [`docs/00-concepts.md`](docs/00-concepts.md).

---

## Quick start

### Prerequisites
- OpenShift 4.22, **≥ 3 worker nodes**, shared (RWX) storage.
- **OpenShift Virtualization** installed and healthy.
- `oc` (and `virtctl`) logged in as `cluster-admin`.

### Option A — GitOps (recommended)
The GitOps manifests already point at this repo
(`github.com/epheo/descheduler-virt-demo.git`), so they run as-is. If you fork,
update `repoURL` in `gitops/`:
```bash
grep -rl 'epheo/descheduler-virt-demo.git' gitops/ \
  | xargs sed -i 's|epheo/descheduler-virt-demo.git|<your-org>/<your-repo>.git|'
```
Then bootstrap:
```bash
./scripts/demo-up.sh
oc get applications -n openshift-gitops -w
```

### Option B — Direct (no Git, fastest to try)
```bash
./scripts/demo-up.sh --direct
```

### Then run the demo
```bash
./scripts/watch-migrations.sh    # terminal 1: the dashboard
./scripts/generate-load.sh 6     # terminal 2: make a node hot → watch VMs move
```
Follow [`docs/05-demo-runbook.md`](docs/05-demo-runbook.md) for the full script.

### Teardown
```bash
./scripts/demo-down.sh
```

---

## Caveats

- **PSI reboots workers.** `KubeVirtRelieveAndMigrate` requires PSI, and enabling
  it triggers a rolling worker reboot — apply it ahead of time. No PSI? Use the
  `LongLifecycle` fallback (`manifests/20-descheduler/03-kubedescheduler-longlifecycle.yaml.alt`).
- **The HCO `liveMigrationConfig` is applied with `oc patch`,** not Argo CD,
  because the object is operator-owned — see [`docs/04-gitops.md`](docs/04-gitops.md).

Further gotchas (protected namespaces, `evictionLimits` ≤ HCO limits, Predictive
vs Automatic) are covered in [`docs/02-descheduler-drs.md`](docs/02-descheduler-drs.md).

---

## Sources

Built from the OpenShift 4.22 product documentation: *Descheduler overview &
configuration*, *Enabling descheduler evictions on virtual machines*,
*Configure eviction and run strategies*, *Configuring live migration*,
*Specifying nodes for virtual machines*, *Specifying nodes for OpenShift
Virtualization components*, and *About Red Hat OpenShift GitOps*.
