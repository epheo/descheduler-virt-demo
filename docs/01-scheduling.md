# Layer 1 — Initial placement (the scheduler)

When a VM starts, the **kube-scheduler** picks a node. A KubeVirt
`VirtualMachine` runs as a Pod (the `virt-launcher`), so every Pod scheduling
control applies to VMs. These are placement controls — they decide where a VM
lands, not where it later moves.

Affinity rules use `requiredDuringSchedulingIgnoredDuringExecution` or
`preferredDuringSchedulingIgnoredDuringExecution`. The `IgnoredDuringExecution`
half is the key point: once a VM is running, the scheduler will not move it even
if the node stops matching. Correcting that drift is the descheduler's job — see
[`00-concepts.md`](00-concepts.md).

## Scheduling controls

| Control | What it does | DRS analog | Example |
|---|---|---|---|
| `nodeSelector` | Hard label match; VM only runs on matching nodes | VM/Host "must run on" | `manifests/40-vms/10-vm-nodeselector.yaml` |
| node affinity (required) | Same as nodeSelector but richer operators (`In`, `Gt`, …) | VM/Host "must run on" | `40-vms/11-vm-node-affinity.yaml` |
| node affinity (preferred) | Weighted preference; still schedules if unmet | VM/Host "should run on" | `40-vms/11-vm-node-affinity.yaml` |
| pod affinity | Co-locate a VM with specific pods/VMs | "Keep VMs together" | `40-vms` (commented pattern) |
| pod **anti**-affinity | Keep VMs apart for HA | "Separate Virtual Machines" | `40-vms/12-vm-antiaffinity-ha-pair.yaml` |
| taints + tolerations | Reserve nodes for a workload class | Dedicated hosts | `40-vms/13-vm-dedicated-node-toleration.yaml` |
| topology spread constraints | Even spread across zones/nodes | Spread across racks | below |

## Setting up demo node groups

Several examples expect node labels/taints (a `gold`/`silver` vm-zone and an
optional dedicated host). Create them once — the commands live with the infra
prerequisites in
[`../manifests/10-scheduling-infra/README.md`](../manifests/10-scheduling-infra/README.md#node-labels--taints-do-this-by-hand).

## Topology spread constraints (even spread)

Spread a set of VMs evenly across nodes so no single node (or zone) holds too
many. Add to `spec.template.spec` of a `VirtualMachine`:

```yaml
topologySpreadConstraints:
  - maxSkew: 1                       # at most 1 VM difference between nodes
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: DoNotSchedule # hard. Use ScheduleAnyway for soft.
    labelSelector:
      matchLabels:
        app: drs-demo
```

`whenUnsatisfiable: ScheduleAnyway` is the soft variant — and the descheduler
profile `SoftTopologyAndDuplicates` can later rebalance those soft constraints,
another place Layer 1 and Layer 2 connect.

## Cluster-component placement

You can also pin the OpenShift Virtualization **operators and workloads**
themselves to specific nodes via the `HyperConverged` CR
(`spec.infra.nodePlacement` / `spec.workloads.nodePlacement`) — e.g. operators
on infra nodes, VM workloads on the virtualization zone. See the upstream doc
*"Specifying nodes for OpenShift Virtualization components"*.

Next: [`02-descheduler-drs.md`](02-descheduler-drs.md) — the DRS engine.
