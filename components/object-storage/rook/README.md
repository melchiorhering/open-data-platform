# Rook-Ceph Object Storage

This guide details how to deploy a [Rook](https://rook.io/) (Ceph) S3-compatible object storage cluster onto a running Kubernetes cluster.

## Prerequisites

* A running Kubernetes cluster (either `kind` or a production cluster).
* `helm` and `kubectl` installed.
* **For Production:** Worker nodes must have unformatted, raw block devices (e.g., `/dev/sdb`, `/dev/nvme0n1`) available for Ceph to use.

## Helm Charts Overview

Rook uses a two-chart model to separate the "logic" from the "configuration."

* **Rook Ceph Operator (`rook-ceph`):** This is the **"Brain"** or **"Chef."** It's a controller that you install *first*. It knows how to build, manage, and heal a Ceph cluster.
* **Rook Ceph Cluster (`rook-ceph-cluster`):** This is the **"Blueprint"** or **"Recipe."** You install this *second*. It just creates a YAML file that tells the Operator *what* kind of storage cluster you want it to build (e.g., "use 3 nodes," "create an object store").

---

## Local `kind` Setup

This setup is configured for our 3-worker `kind` cluster. It will create a 3-node Ceph cluster with a single S3-compatible object store.

It uses the files in the `local/` directory:
* `local/operator.values.yaml`: Overrides for the "Operator" chart.
* `local/cluster.values.yaml`: Overrides for the "Cluster" chart.

### Step 1: Install the Rook-Ceph Operator (The "Brain")

```bash
helm repo add rook-release https://charts.rook.io/release
helm install --create-namespace --namespace rook-ceph rook-ceph rook-release/rook-ceph -f local/operator.values.yaml
````

Wait for the operator pod to be fully running before continuing:

```bash
# verify the rook-ceph-operator is in the `Running` state before proceeding
kubectl -n rook-ceph get pod
```

### Step 2: Install the Ceph Cluster (The "Blueprint")

Now that the "Brain" is running, we give it the "Blueprint" to build our object store.

```bash
helm repo add rook-release https://charts.rook.io/release
helm install --create-namespace --namespace rook-ceph rook-ceph-cluster \
   --set operatorNamespace=rook-ceph rook-release/rook-ceph-cluster -f values.yaml
```

This step will take several minutes. Rook is now deploying all the Ceph daemons (MONs, OSDs, RGW, etc.). You can watch the progress:

```bash
kubectl -n rook-ceph get pod
```

Wait until all pods are in the `Running` state.

-----

## Step 3: Access Your Local S3 Storage

### 1\. Access the S3 Endpoint (Port-Forward)

The easiest way to access the S3 service from your Mac is with `kubectl port-forward`.

**Open a new terminal** and run this command. It will run continuously.

```bash
# This connects your local port 8080 to the S3 gateway in the cluster
kubectl port-forward -n rook-ceph \
  svc/rook-ceph-rgw-my-store 8080:80
```

Your S3 endpoint is now: **`http://localhost:8080`**

### 2\. Access the Ceph Dashboard (Optional)

In a **second terminal**, you can do the same for the Ceph Dashboard.

```bash
# This connects your local port 8443 to the dashboard
kubectl port-forward -n rook-ceph \
  svc/rook-ceph-mgr-dashboard-external-https 8443:8443
```

You can now access the dashboard at: **`https://localhost:8443`**

### 3\. Get S3 Credentials

Rook automatically creates an S3 user. Get its credentials with these commands:

```bash
# Get Access Key
ACCESS_KEY=$(kubectl -n rook-ceph get secret rook-ceph-object-user-my-store-my-store \
  -o jsonpath="{.data.AccessKey}" | base64 -d)

# Get Secret Key
SECRET_KEY=$(kubectl -n rook-ceph get secret rook-ceph-object-user-my-store-my-store \
  -o jsonpath="{.data.SecretKey}" | base64 -d)

echo "S3_ENDPOINT_URL=http://localhost:8080"
echo "AWS_ACCESS_KEY_ID=$ACCESS_KEY"
echo "AWS_SECRET_ACCESS_KEY=$SECRET_KEY"
```

-----

## Cleanup

To remove the object store and the Ceph cluster:

```bash
helm delete -n rook-ceph rook-ceph-cluster
helm delete -n rook-ceph rook-ceph
kubectl delete namespace rook-ceph
```
