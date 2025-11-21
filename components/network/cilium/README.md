# Local Kubernetes (K8s) with Cilium

This guide provides a complete walkthrough for creating a high-performance, multi-cluster local Kubernetes environment. We will use `kind` to provision the clusters and then install **Cilium** as the CNI and **Hubble** for network observability.

This setup is ideal for safely developing and testing cloud-native applications, complex network policies, and multi-cluster networking.

## Why This Setup? (Cilium + Hubble)

By default, `kind` uses a simple CNI (`kindnet`). We are intentionally disabling it to install Cilium, which provides powerful features that mirror a production-grade, cloud-agnostic environment.

- ### Why Cilium?

  - **High-Performance Networking:** It uses **eBPF** (Extended Berkeley Packet Filter) to manage networking directly in the Linux kernel. This is significantly faster and more efficient than older methods that rely on `iptables`.
  - **Powerful Security:** Cilium provides identity-based security. It can enforce network policies not just at the IP level (L3/L4) but also at the application protocol level (L7).
  - **Advanced Features:** It's the foundation for **Cilium Cluster Mesh**, which connects multiple Kubernetes clusters (even across different clouds) into a single, seamless network.

- ### Why Hubble?
  - **Network Observability:** Hubble is the "UI for Cilium." It gives you deep visibility into the network traffic flowing inside your cluster.
  - **Troubleshooting:** You can visually see all network requests, see which ones are being allowed or _denied_ by a policy, and understand exactly why.
  - **Service Map:** It automatically generates a map of your services and their dependencies just by observing the network traffic.

---

### 🏗 Network Architecture

- **CNI & Data Plane:** Uses **Cilium v1.18.4** with `kubeProxyReplacement=true` for high-performance eBPF-based networking.
- **Observability:** **Hubble** (Relay & UI) is enabled for real-time visualization of network flows and dropped packets.
- **Gateway API:** Fully compliant **Gateway API v1.4.0** implementation, replacing legacy Ingress Controllers.

### 🛡️ Zero Trust Security (Day 0)

- **Default Deny:** The cluster launches in **Lockdown Mode** using a `CiliumClusterwideNetworkPolicy`.
- **Traffic Rules:**
  - **Ingress:** Blocked by default for all pods.
  - **Egress:** Blocked by default (except DNS).
  - **Infrastructure:** Explicitly whitelists Gateway and Cert-Manager functionality.
- **Onboarding:** New applications (like Sail or Prefect) require a specific `CiliumNetworkPolicy` to function.

### 🌐 Connectivity & IPAM

- **L2 Announcements:** Enabled to allow the cluster to broadcast ARP replies for LoadBalancer IPs.
- **Local IPAM:** Uses `CiliumLoadBalancerIPPool` to assign IPs from the `172.18.255.0/24` range (subnet of the Kind network).
- **Purpose:** This ensures Gateways receive a valid IP, switching their status to `Programmed: True`, allowing Cilium to spawn the required Envoy proxies.

- **Cluster Internal IPAM (Pod CIDR):** `10.244.0.0/16` — Used for Pod-to-Pod talk. Managed automatically by Cilium.

- **Service External IPAM (LoadBalancer Pool):** `172.18.255.0/24` — Used for North-South traffic (Entering the cluster).
  - Purpose: Allows the Gateway to grab an IP address that is technically "on the local Docker network," making it reachable by the host (via NodePort mapping) or other containers.

### 🔐 Identity & Certificates

- **Cert-Manager:** **v1.19.0** installed for automated certificate management.
- **Trust Chain:** Uses a local `ClusterIssuer` (CA) to issue TLS certificates for the Gateway.
- **HTTPS:** Automatic TLS termination at the Gateway for domains like `*.localhost`.

### 🚪 Local Access Point

- **Hybrid Binding:** The Gateway Service uses `type: LoadBalancer` to satisfy Cilium (to get an IP), but is patched to enforce static **NodePorts**.
- **Entry Points:**
  - **HTTP:** `http://localhost:30080`
  - **HTTPS:** `https://localhost:30443`
- **Traffic Flow:** `User (Host)` → `NodePort (30443)` → `Cilium Gateway` → `Network Policy Check` → `Application Pod`.
