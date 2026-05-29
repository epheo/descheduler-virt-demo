# Layer 0 — GitOps (Argo CD is the control plane)

In vSphere, vCenter is the single authoritative place where cluster/DRS policy
and VMs live. In OpenShift, **Git is that source of truth** and **Argo CD**
(Red Hat OpenShift GitOps) continuously reconciles the cluster to match it.

Everything in this demo — the DRS policy, the scheduling rules, the live-
migration policy, and the VMs — is plain YAML in this repo and is applied by
Argo CD. Change DRS aggressiveness or flip Predictive→Automatic by editing YAML
and pushing; Argo rolls it out and (with `selfHeal`) reverts any drift.

## App-of-apps layout

```
gitops/
├── bootstrap/
│   ├── 00-gitops-operator.yaml   # install Argo CD (apply by hand, once)
│   └── 01-root-app.yaml          # the root Application (apply by hand, once)
└── applications/                 # children, ordered by sync-wave
    ├── 00-namespaces-app.yaml        wave -1
    ├── 10-scheduling-infra-app.yaml  wave  0   (PSI MachineConfig)
    ├── 20-descheduler-app.yaml       wave  1   (the "DRS" engine)
    ├── 30-live-migration-app.yaml    wave  1   (MigrationPolicy)
    └── 40-vms-app.yaml               wave  2   (the VMs)
```

`bootstrap/01-root-app.yaml` points Argo at `gitops/applications/`, and each
child points at a `manifests/*` directory. **Sync waves** guarantee ordering:
namespaces → PSI → descheduler/migration → VMs.

## `repoURL` — only edit if you fork

Every Application points at the canonical repo:

```yaml
repoURL: https://github.com/epheo/descheduler-virt-demo.git   # canonical repo — change if you fork
```

It works as-is against this repo. If you fork, repoint all of them at your fork:

```bash
grep -rl 'epheo/descheduler-virt-demo.git' gitops/ | xargs sed -i 's|epheo/descheduler-virt-demo.git|<your-org>/<your-repo>.git|'
```

## Two intentional exceptions to "everything in Git"

1. **HyperConverged `liveMigrationConfig`** — the HCO object is *owned* by the
   Virtualization operator, so we don't replace it from Git; we `oc patch` it
   (see `demo-up.sh`). Managing a slice of an operator-owned CR from Argo
   needs server-side-apply/patch tooling and would distract from the demo.
2. **GitOps operator install + root app** — a bootstrap dependency, applied once
   by hand.

## Drift / mutation handling

KubeVirt and the descheduler operator mutate their own objects (firmware UUIDs,
defaulted fields). The child Applications use `ignoreDifferences` so Argo
doesn't show them permanently `OutOfSync`. See `40-vms-app.yaml` and
`20-descheduler-app.yaml`.

## RBAC note

The default `openshift-gitops` Argo instance's application-controller has the
cluster-admin needed to manage the cluster-scoped objects here (`Namespace`,
`MachineConfig`, `Subscription`, `KubeDescheduler`). In a hardened setup you'd
scope an AppProject and a custom ClusterRole instead.

Next: [`05-demo-runbook.md`](05-demo-runbook.md).
