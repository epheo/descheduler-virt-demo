# Live demo runbook

A walkthrough of roughly 20 minutes covering scheduler → descheduler ("DRS") →
live migration → GitOps.

## Prerequisites

Same as the [README](../README.md#prerequisites): OpenShift 4.22, **≥ 3 workers**
(so VMs have somewhere to migrate), RWX storage, OpenShift Virtualization healthy,
`oc`/`virtctl` as `cluster-admin`. GitOps mode needs no edits — the manifests
already point at this repo (only edit `repoURL` if you fork; see
[`04-gitops.md`](04-gitops.md)).

---

## 1. Bring up the environment

```bash
# GitOps (recommended): installs Argo CD, applies the app-of-apps.
./scripts/demo-up.sh
oc get applications -n openshift-gitops -w     # watch waves sync

# …or apply directly without Argo CD:
./scripts/demo-up.sh --direct
```

Note: the PSI MachineConfig reboots workers once — expect the `worker`
MachineConfigPool to cycle. Do this before the session.

Open a second terminal for the live dashboard:

```bash
./scripts/watch-migrations.sh
```

---

## 2. Initial placement (the scheduler)

This corresponds to DRS initial placement and VM/Host rules, but declared in YAML.

1. Label two nodes and show the **nodeSelector** VM lands only there:
   ```bash
   oc label node <n1> node-role.kubernetes.io/vm-zone=gold disktype=ssd cpu-class=high
   oc label node <n2> node-role.kubernetes.io/vm-zone=silver
   oc get vmi -n virt-drs-demo vm-nodeselector -o wide   # NODE = the gold node
   ```
2. Show the **anti-affinity HA pair** sitting on *different* nodes:
   ```bash
   oc get vmi -n virt-drs-demo -l ha-group=db-cluster \
     -o custom-columns=NAME:.metadata.name,NODE:.status.nodeName
   # vm-ha-a and vm-ha-b are on different nodes — "Separate Virtual Machines".
   ```
3. Note that affinity is `IgnoredDuringExecution` — the scheduler placed these
   VMs and will not move them again. The descheduler (next section) addresses that.

---

## 3. Continuous rebalancing (the descheduler)

This is the equivalent of DRS Fully Automated mode.

1. Show the policy and that it's the DRS knob set:
   ```bash
   oc get kubedescheduler cluster -n openshift-kube-descheduler-operator -o yaml \
     | grep -A12 'spec:'
   # mode: Automatic · KubeVirtRelieveAndMigrate · devDeviationThresholds: AsymmetricLow
   ```
2. **Create load** so one node gets hot:
   ```bash
   ./scripts/generate-load.sh 6
   ```
   In the dashboard terminal watch `oc adm top nodes` — one node climbs.
3. Within an interval or two (30s each), the NODE column changes and
   `VirtualMachineInstanceMigration` objects appear — the descheduler is
   live-migrating VMs off the hot node.
   ```bash
   oc get virtualmachineinstancemigrations -n virt-drs-demo
   oc logs -n openshift-kube-descheduler-operator deploy/descheduler | tail -20
   ```
4. Predictive vs Automatic (optional): edit
   `manifests/20-descheduler/03-kubedescheduler-drs.yaml`, set `mode: Predictive`,
   then commit and push. Argo CD switches the descheduler to recommendation-only;
   switch back to `Automatic` to resume migrations. The automation level is
   controlled entirely through Git.

---

## 4. Exclusions and maintenance

1. Show that the pinned VM (`evictionStrategy: None`) never migrates and the
   prefer-no-eviction VM is skipped by rebalancing:
   ```bash
   oc get vmi -n virt-drs-demo vm-pinned-none vm-no-rebalance -o wide   # stay put
   ```
2. Maintenance mode — evacuate a node (the DRS "enter maintenance" equivalent):
   ```bash
   oc adm drain <n1> --delete-emptydir-data --ignore-daemonsets --force
   # LiveMigrate VMs evacuate; vm-no-rebalance ALSO moves (drain ≠ load-balance);
   # vm-pinned-none blocks the drain until stopped — explain why.
   oc adm uncordon <n1>
   ```

---

## 5. GitOps as the control plane

```bash
# Everything you just saw is reconciled from Git:
oc get applications -n openshift-gitops
# Change DRS aggressiveness via a commit, not a console click:
#   edit devDeviationThresholds: AsymmetricLow -> Medium, push, watch Argo sync.
```

Refer back to the table in [`00-concepts.md`](00-concepts.md): scheduler +
descheduler + live migration + GitOps together provide DRS-equivalent behavior,
declaratively and version-controlled.

---

## Teardown

```bash
oc delete vm -n virt-drs-demo -l role=load-generator   # just the load
./scripts/demo-down.sh                                  # full teardown
```

## Troubleshooting

| Symptom | Check |
|---|---|
| No migrations happen | `mode: Automatic`? PSI on (`oc debug node/<n> -- cat /proc/pressure/cpu`)? ≥3 nodes? VMs migratable? |
| VM stuck `Pending` | nodeSelector/affinity matches no node; label a node or relax the rule. |
| Migration stuck `Pending`/`Scheduling` | non-migratable VM with `LiveMigrate`; use `LiveMigrateIfPossible`/`None`. |
| Argo `OutOfSync` forever on a VM | expected mutated field — add to `ignoreDifferences` (see `40-vms-app.yaml`). |
| Descheduler won't evict a VM | namespace protected? PDB? `prefer-no-eviction` annotation present? |
