# RustFS

This is an object-storage setup using [RustFS](https://rustfs.com/en/)

## Helm (Local)

To start a rusfs cluster, we are using helm

```bash
# Create a namespace
helm install rustfs -n rustfs --create-namespace ./ -f local.values.yml
# Upgrading
helm upgrade rustfs ./ -n rustfs -f local.values.yml
```


## Helm (Cloudpirates)

For cloudpirates rustfs setup:
https://artifacthub.io/packages/helm/cloudpirates-rustfs/rustfs

```bash
# Install Cloudpirates RustFS repo
helm install my-rustfs oci://registry-1.docker.io/cloudpirates/rustfs

# Install based on custom values file
helm install my-rustfs oci://registry-1.docker.io/cloudpirates/rustfs -f my-values.yaml



```

## Control

```bash
# check the pods
kubectl get pods -n rustfs
# OR
kubectl get pods -n rustfs -w

# Check the storage (PVCs)
kubectl get pvc -n rustfs

# Check the internal Service
kubectl get service -n rustfs

# Check the Ingress (how you access it from outside)
kubectl get ingress -n rustfs

```
