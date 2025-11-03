# Garage

This guide details how to deploy [Garage](https://garagehq.deuxfleurs.fr/), a lightweight, S3-compatible object storage system, onto our local `kind` cluster.

This setup is ideal for local development, providing a distributed 3-node storage cluster that matches our 3-worker `kind` topology.

## Prerequisites

1.  **Running `kind` Cluster:** You must have the local cluster running. (See `../../local/README.md` for setup instructions).
2.  **Tools:** You must have `git`, `helm`, and `kubectl` installed.

---

## 1. Configuration

To deploy Garage on `kind`, we need a custom configuration file to override the chart's defaults.

Create the file `kind-values.yaml` in this directory (`components/object-storage/garage/`):

**`kind-values.yaml`**
```yaml
# 1. Set replicaCount to 3, one for each of your 'kind' worker nodes.
#    This provides a perfect distributed setup.
deployment:
  replicaCount: 3

# 2. Tell Garage to use the built-in 'standard' storage class
#    that kind provides, which just uses your local disk.
persistence:
  meta:
    storageClass: "standard"
    size: 100Mi # Keep it small for local dev
  data:
    storageClass: "standard"
    size: 1Gi # Keep it small for local dev

# 3. Expose the S3-compatible gateway using a 'NodePort'
#    This makes it easy to access from your laptop (localhost)
#    without a complex Ingress.
service:
  s3:
    type: NodePort
````

-----

## 2. Installation

The Garage Helm chart must be installed from a local `git` clone. The following steps automate this process, including the **critical cluster layout configuration**.

### Quick Install (Recommended)

You can run the script below to automate the entire setup.

Create a file named `setup.sh` in this directory:

**`setup.sh`**

```bash
#!/bin/bash
set -e

# --- Configuration ---
NAMESPACE="garage"
CONFIG_FILE="./kind-values.yaml"
REPO_DIR="./garage-repo"

# --- 1. Clone the Garage Repo (as required by the docs) ---
echo "Cloning Garage repository to $REPO_DIR..."
if [ -d "$REPO_DIR" ]; then
    echo "Repo already exists, skipping clone."
else
    git clone [https://git.deuxfleurs.fr/Deuxfleurs/garage](https://git.deuxfleurs.fr/Deuxfleurs/garage) "$REPO_DIR"
fi

# --- 2. Install Garage with your 'kind' settings ---
echo "Installing Garage via Helm..."
helm install --create-namespace --namespace $NAMESPACE garage \
  -f $CONFIG_FILE \
  "$REPO_DIR/scripts/helm/garage"

# --- 3. Wait for all 3 Pods to be Ready ---
echo "Waiting for all 3 Garage pods to start..."
kubectl wait --for=condition=Ready pod \
  -n $NAMESPACE \
  -l app.kubernetes.io/name=garage \
  --timeout=300s

echo "All pods are running."

# --- 4. CRITICAL: Configure the Cluster Layout ---
# This joins node-1 and node-2 to node-0 to form the cluster.
echo "Configuring the 3-node Garage cluster layout..."
kubectl exec -n $NAMESPACE garage-0 -- ./garage node join garage-1
kubectl exec -n $NAMESPACE garage-0 -- ./garage node join garage-2

echo "Cluster layout configured successfully!"

# --- 5. Show the Final Status ---
echo "Verifying cluster status:"
kubectl exec -n $NAMESPACE garage-0 -- ./garage status
```

Make the script executable and run it:

```bash
chmod +x setup.sh
./setup.sh
```

-----

## 3. Accessing Your S3 Storage

Your Garage S3-compatible storage is now running.

### 1. Find Your Endpoint

`kind` exposes the `NodePort` on `localhost`. Find the port by running:

```bash
kubectl get svc -n garage garage-s3
```

You will see output like this. The high-number port is the one you need:

```
NAME        TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
garage-s3   NodePort   10.96.123.123   <none>        80:31234/TCP   60s
```

Your endpoint is **`http://localhost:31234`**.

### 2\. Get Your Access Keys

The chart automatically creates a secret with your S3 credentials.

```bash
# Get Access Key
ACCESS_KEY=$(kubectl get secret -n garage garage-s3 -o jsonpath="{.data.accessKey}" | base64 -d)

# Get Secret Key
SECRET_KEY=$(kubectl get secret -n garage garage-s3 -o jsonpath="{.data.secretKey}" | base64 -d)

echo "Access Key: $ACCESS_KEY"
echo "Secret Key: $SECRET_KEY"
```

### 3. Example: Connect with MinIO Client (`mc`)

You can now use any S3 client. Here is an example with `mc`:

```bash
# 1. Install mc (if you don't have it)
brew install minio/stable/mc

# 2. Add your new local Garage cluster as a host
# (Use the port and keys from the steps above)
mc alias set local-garage http://localhost:31234 $ACCESS_KEY $SECRET_KEY

# 3. Make a new bucket
mc mb local-garage/my-first-bucket

# 4. List your buckets
mc ls local-garage
```

-----

## 4. Cleanup

When you are done, you can remove Garage and all its data.

```bash
# 1. Uninstall the Helm release
helm delete --namespace garage garage

# 2. Delete the namespace (this removes PVCs and secrets)
kubectl delete namespace garage

# 3. (Optional) Remove the cloned repo
rm -rf ./garage-repo
```

**Note:** As per the official docs, a `CustomResourceDefinition` (CRD) is left behind. If you want to remove it, run:

```bash
kubectl delete crd garagenodes.deuxfleurs.fr
```
