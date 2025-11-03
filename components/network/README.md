# Local Kubernetes (K8s) with Cilium

This guide provides a complete walkthrough for creating a high-performance, multi-cluster local Kubernetes environment. We will use `kind` to provision the clusters and then install **Cilium** as the CNI and **Hubble** for network observability.

This setup is ideal for safely developing and testing cloud-native applications, complex network policies, and multi-cluster networking.

## Why This Setup? (Cilium + Hubble)

By default, `kind` uses a simple CNI (`kindnet`). We are intentionally disabling it to install Cilium, which provides powerful features that mirror a production-grade, cloud-agnostic environment.

* ### Why Cilium?
    * **High-Performance Networking:** It uses **eBPF** (Extended Berkeley Packet Filter) to manage networking directly in the Linux kernel. This is significantly faster and more efficient than older methods that rely on `iptables`.
    * **Powerful Security:** Cilium provides identity-based security. It can enforce network policies not just at the IP level (L3/L4) but also at the application protocol level (L7).
    * **Advanced Features:** It's the foundation for **Cilium Cluster Mesh**, which connects multiple Kubernetes clusters (even across different clouds) into a single, seamless network.

* ### Why Hubble?
    * **Network Observability:** Hubble is the "UI for Cilium." It gives you deep visibility into the network traffic flowing inside your cluster.
    * **Troubleshooting:** You can visually see all network requests, see which ones are being allowed or *denied* by a policy, and understand exactly why.
    * **Service Map:** It automatically generates a map of your services and their dependencies just by observing the network traffic.

---

## 1. Create First Cluster (`cluster1`)

First, we create our primary `kind` cluster.

### Configuration (`kind-config-cluster1.yml`)

This file defines our first cluster (`cluster1`) with **one control-plane** and **three worker nodes**.

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
# We explicitly name our cluster to manage it
name: cluster1
nodes:
  - role: control-plane
  - role: worker
  - role: worker
  - role: worker
networking:
  disableDefaultCNI: true
  podSubnet: "10.244.0.0/16"
  serviceSubnet: "10.96.0.0/12"
````

**Configuration Details:**

  * `disableDefaultCNI: true`: This is the most important setting. It tells `kind` **not** to install its default `kindnet` networking, freeing us up to install Cilium.
  * `podSubnet` / `serviceSubnet`: These explicitly define the internal IP address ranges. **This is critical for multi-cluster**, as each cluster *must* have unique, non-overlapping subnets.

### Create the Cluster

```bash
kind create cluster --config kind-config-cluster1.yml
```

Your `kubectl` context will now be `kind-cluster1`.

-----

## 2\. Install Cilium & Hubble on `cluster1`

The cluster nodes are now in a `NotReady` state. This is normal. We will now install Cilium to bring the network online.

### 2.1. Install Cilium CLI

```bash
brew install cilium-cli
```

### 2.2. Install Cilium with Helm

We use Helm to install Cilium. **Note the `cluster.name` and `cluster.id` flags**—these are essential for enabling multi-cluster networking.

```bash
# 1. Add the Cilium Helm repo
helm repo add cilium [https://helm.cilium.io/](https://helm.cilium.io/)

# 2. (Optional) Pre-load the image for 'kind' to speed up installation
docker pull quay.io/cilium/cilium:stable
kind load docker-image quay.io/cilium/cilium:stable --name cluster1

# 3. Install Cilium release via helm
# (Find the latest chart version 'x.x.x' from 'helm search repo cilium')
helm install cilium cilium/cilium --version x.x.x \
    --namespace kube-system \
    --set image.pullPolicy=IfNotPresent \
    --set ipam.mode=kubernetes \
    --set cluster.name=cluster1 \
    --set cluster.id=1 # Must be a unique ID (1-255)
```

### 2.3. Verify Cluster & Install Hubble

After a minute, the nodes will become `Ready`.

```bash
# Check that nodes are 'Ready'
kubectl get nodes

# Verify Cilium is operational
cilium status --wait
```

Now, enable Hubble's UI:

```bash
# Upgrade the Helm release to enable Hubble
# (Use the same chart version 'x.x.x' as before)
helm upgrade cilium cilium/cilium --version x.x.x \
    --namespace kube-system \
    --reuse-values \
    --set hubble.relay.enabled=true \
    --set hubble.ui.enabled=true
```

You have now set up your first standalone cluster.

-----

## 3\. Multi-Cluster Setup (Cilium Cluster Mesh)

To connect this cluster to other clusters, we use **Cilium Cluster Mesh**. Here is how to create a *second* `kind` cluster and connect it.

### 3.1. Create a Second Cluster (`cluster2`)

First, create a new config file: `kind-config-cluster2.yml`

**`kind-config-cluster2.yml`**

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: cluster2
nodes:
  - role: control-plane
  - role: worker
networking:
  disableDefaultCNI: true
  # --- CRITICAL: These IP ranges MUST be different from cluster1 ---
  podSubnet: "10.245.0.0/16"
  serviceSubnet: "10.97.0.0/12"
```

Now, create this second cluster:

```bash
kind create cluster --config kind-config-cluster2.yml
```

### 3.2. Install Cilium on `cluster2`

The process is identical, but we use the new `kubectl` context (`kind-cluster2`) and give it a **unique cluster name and ID**.

```bash
# 1. (Optional) Pre-load image on cluster2
kind load docker-image quay.io/cilium/cilium:stable --name cluster2

# 2. Install Cilium on cluster2, targeting the new context
# (Use the same chart version 'x.x.x')
helm install cilium cilium/cilium --version x.x.x \
    --kube-context kind-cluster2 \
    --namespace kube-system \
    --set image.pullPolicy=IfNotPresent \
    --set ipam.mode=kubernetes \
    --set cluster.name=cluster2 \
    --set cluster.id=2 # Must be a unique ID
```

### 3.3. Enable & Connect the Cluster Mesh

Now we use the `cilium-cli` to connect the two.

```bash
# 1. Enable Cluster Mesh on cluster1
cilium --context kind-cluster1 clustermesh enable

# 2. Enable Cluster Mesh on cluster2
cilium --context kind-cluster2 clustermesh enable

# 3. Connect cluster1 to cluster2
cilium --context kind-cluster1 clustermesh connect --destination-context kind-cluster2
```

### 3.4. Verify the Connection

The clusters are now connected\! You can verify this from either cluster.

```bash
cilium --context kind-cluster1 clustermesh status --wait
```

You can now deploy applications (like the `rook-ceph-cluster`) to either cluster, and they will be able to communicate seamlessly.
