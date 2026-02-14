# Submariner Deployment Guide (eu-de-01 ↔ na-va-01)

Use this runbook to interconnect the two Flux-managed clusters with Submariner. All commands assume they are run from the repo root on the operator workstation.

## Cluster Network Summary

| Cluster  | ClusterID  | Kubeconfig Path                          | Pod CIDR (current) | Service CIDR   | Notes                                                                           |
| -------- | ---------- | ---------------------------------------- | ------------------ | -------------- | ------------------------------------------------------------------------------- |
| eu-de-01 | `eu-de-01` | `/home/tolfx/.kube/node01-udl-tf.yaml`   | `10.42.0.0/24`     | `10.43.0.0/16` | Single node hands out the entire /24 today; expand to /16 as the cluster grows. |
| na-va-01 | `na-va-01` | `/home/tolfx/.kube/na-va-01.udl.tf.yaml` | `10.42.0.0/24`     | `10.43.0.0/16` | Mirrors eu-de-01; overlapping Pod CIDRs require Globalnet.                      |

*Source:* `kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}\t{.spec.podCIDR}\n{end}'` (per cluster) and `kubectl get svc kubernetes -o jsonpath='{.spec.clusterIP}'`.

Because both clusters currently share the same Pod/Service ranges, the Submariner broker must be deployed with Globalnet enabled. Submariner will then allocate non-overlapping Globalnet CIDRs (default `/24` each) for cross-cluster communication.

## Prerequisites

1. Install `subctl` (v0.16+ recommended):
   ```bash
   curl -Ls https://get.submariner.io | bash
   ```
2. Ensure both kubeconfig files above are present and have cluster-admin privileges.
3. Pick at least one node per cluster that can reach the other cluster over UDP 4500/500 and TCP 4490. Record the node names—they will be labeled as gateways.
4. Clone this repo (already done) and keep `broker-info.subm` secure once generated; it contains the IPSec PSK and broker credentials.

## Step 1 – Export Environment Variables & Validate Contexts

```bash
export KUBECONFIG_EU=/home/tolfx/.kube/node01-udl-tf.yaml
export KUBECONFIG_NA=/home/tolfx/.kube/na-va-01.udl.tf.yaml
export CLUSTERID_EU=eu-de-01
export CLUSTERID_NA=na-va-01

kubectl --kubeconfig="$KUBECONFIG_EU" get nodes
kubectl --kubeconfig="$KUBECONFIG_NA" get nodes
```

## Step 2 – Label Gateway Nodes

Replace `<eu-gw-node>` / `<na-gw-node>` with the chosen node names.

```bash
kubectl --kubeconfig="$KUBECONFIG_EU" label node <eu-gw-node> submariner.io/gateway=true --overwrite
kubectl --kubeconfig="$KUBECONFIG_NA" label node <na-gw-node> submariner.io/gateway=true --overwrite
```

Adding a `submariner.io/gateway=true:NoSchedule` taint keeps non-gateway workloads off those nodes if desired.

## Step 3 – Deploy the Broker on eu-de-01

```bash
subctl deploy-broker \
  --kubeconfig "$KUBECONFIG_EU" \
  --globalnet
```

This creates the `submariner-k8s-broker` namespace and writes `broker-info.subm` in the current directory. Protect that file and copy it to any machine that will run `subctl join`.
By default Submariner deploys both connectivity and service-discovery components, so no extra flags are required unless you want to limit what gets installed.

## Step 4 – Join Both Clusters

### eu-de-01 (broker owner still needs dataplane components)

```bash
subctl join \
  --kubeconfig "$KUBECONFIG_EU" \
  --clusterid "$CLUSTERID_EU" \
  --cable-driver libreswan \
  --clustercidr 10.42.0.0/24 \
  --servicecidr 10.43.0.0/16 \
  --natt \
  --label-gateway \
  broker-info.subm
```

### na-va-01

```bash
subctl join \
  --kubeconfig "$KUBECONFIG_NA" \
  --clusterid "$CLUSTERID_NA" \
  --cable-driver libreswan \
  --clustercidr 10.42.0.0/24 \
  --servicecidr 10.43.0.0/16 \
  --natt \
  --label-gateway \
  broker-info.subm
```

If additional nodes are added later, rerun the label command or set `--prefer-apache`/`--preferred-server` flags as needed.
`subctl` 0.16+ expects the condensed flag names `--clustercidr` and `--servicecidr`; older docs still show `--cluster-cidr`/`--service-cidr`, so double-check your version if commands differ.
Also note that the `broker-info.subm` file is a positional argument and must appear last; otherwise Cobra treats some flag values as extra args and aborts with “accepts at most 1 arg(s)”. For boolean flags, omit explicit values (use `--natt` instead of `--natt true`) so the parser doesn’t treat `true`/`false` as stray positional arguments.

## Step 5 – Verification

1. **Show gateways and connections**
   ```bash
   subctl show gateways --kubeconfig "$KUBECONFIG_EU"
   subctl show connections --kubeconfig "$KUBECONFIG_EU"
   subctl show networks --kubeconfig "$KUBECONFIG_EU"
   subctl diagnose all --kubeconfig "$KUBECONFIG_EU"
   ```
2. **Cross-cluster service test**
   ```bash
   kubectl --kubeconfig="$KUBECONFIG_EU" create ns submariner-test
   kubectl --kubeconfig="$KUBECONFIG_EU" -n submariner-test run nginx --image=nginx --expose --port 80
   subctl export service nginx --namespace submariner-test --kubeconfig "$KUBECONFIG_EU"

   kubectl --kubeconfig="$KUBECONFIG_NA" -n submariner-test run curl --image=appropriate/curl --restart=Never -- \
     curl nginx.submariner-test.svc.clusterset.local
   ```
   Expect an HTTP 200 response. Delete the `submariner-test` namespace afterwards.

## Ongoing Operations

- **PSK rotation:** `subctl export-config broker-info.subm` on the broker cluster, then rerun `subctl join --update ...` on each member.
- **Gateway failover:** Label/taint additional nodes. Submariner automatically promotes backups when the primary node is unavailable.
- **GitOps consideration:** If you want Flux to own the install, capture the rendered manifests (`kubectl -n submariner-operator get all -o yaml`) and wrap them in a `cluster/<name>/submariner/` kustomization or HelmRelease.
- **Cleanup:** `subctl uninstall --kubeconfig ...` removes the operator from a member cluster; `subctl delete-broker` cleans up the broker namespace.

Document any deviations (alternative cable drivers, additional clusters, custom Globalnet sizes) in this file so future operators can follow the same process.
