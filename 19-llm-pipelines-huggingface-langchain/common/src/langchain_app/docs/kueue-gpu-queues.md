# Sharing GPUs fairly with Kueue

Kueue is an **admission** layer in front of the Kubernetes scheduler. It doesn't schedule pods.
It decides *when a whole job may start*, based on quota. A job that targets Kueue is created
suspended (`spec.suspend: true`) and only unsuspended once there is quota for all of its pods.

## Object model

- **ResourceFlavor**: a named kind of node (node labels, taints/tolerations), such as a "spot"
  flavor and an "on-demand" flavor. Cluster-scoped, no quota of its own.
- **ClusterQueue**: cluster-scoped quota holder. `spec.resourceGroups[].flavors[]` lists flavors
  **in preference order**, each with a `nominalQuota` and optional `borrowingLimit` /
  `lendingLimit`. Putting the spot flavor first gives you spot-first scheduling.
- **Cohort**: a group of ClusterQueues that lend unused quota to each other. Since the
  `kueue.x-k8s.io/v1beta2` API it is its own CRD and carries the fair-sharing weight.
- **LocalQueue**: namespaced, and points at one ClusterQueue. Users submit to this.
- **Workload**: created automatically by Kueue for every queued job. You read Workloads, you
  don't write them.
- **WorkloadPriorityClass**: sets queue order and preemption only. Independent of the
  Kubernetes PriorityClass.

## Submitting a job

Add the label `kueue.x-k8s.io/queue-name: <local-queue>` to the Job. Kueue's webhook suspends
it, creates a Workload, and releases the job when the ClusterQueue admits it.

## Borrowing and preemption

When team A's ClusterQueue is idle, team B can **borrow** its quota through the shared Cohort.
When team A submits work again, Kueue can **preempt** the borrowed workloads to give the quota
back. That lets scarce GPUs stay busy without one team starving another.

## Debugging a pending job

`kubectl get workloads -n <ns>` and `kubectl describe clusterqueue <name>` show whether a job is
waiting for quota (not yet admitted) or was admitted but its pods can't be scheduled (usually a
node selector or toleration problem).
