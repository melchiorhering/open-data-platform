# Open Data Platform

This repository contains the infrastructure, code, and documentation for building a modern, end-to-end data platform using exclusively open-source components.

The entire stack is designed to be **cloud-agnostic**, capable of running on any Kubernetes cluster—from a local laptop (using `kind`) to a federated multi-cloud production environment.

## 🚀 Core Principles

- **100% Open-Source:** No vendor lock-in. Every component is open-source.
- **Cloud-Agnostic:** Built on Kubernetes and Cilium, allowing the platform to run on any cloud provider (AWS, GCP, Azure, Hetzner, OVH) or on-premise.
- **Modular:** Each component (e.g., orchestration, compute) is independent. You can swap out tools as needed.
- **Scalable:** Designed to scale from a single-node setup to a high-availability, multi-cluster mesh.

## 🛠️ Core Architecture & Tech Stack

The platform is built from the following open-source components, categorized by their function:

### Networking

Provides the core connectivity and security for all services.

| Tool                                                   | Primary Role       | Notes                                                                    |
| :----------------------------------------------------- | :----------------- | :----------------------------------------------------------------------- |
| **[Cilium](https://cilium.io/)**                       | CNI & Cluster Mesh | L3/L4/L7 networking and security. Used for connecting multiple clusters. |
| **[Headscale](https://github.com/juanfont/headscale)** | Overlay Network    | (Alternative) Self-hosted control server for Tailscale clients.          |
| **[Netbird](https://netbird.io/)**                     | Overlay Network    | (Alternative) Open-source VPN for simple L3 connectivity.                |

### Security

Handles identity, authentication, and authorization for users and services.

| Tool                                      | Primary Role            | Notes                                                       |
| :---------------------------------------- | :---------------------- | :---------------------------------------------------------- |
| **[Keycloak](https://www.keycloak.org/)** | Identity & Access (IAM) | Provides secure, single sign-on (SSO) for all platform UIs. |

### Code Storage

Manages all code, CI/CD pipelines, and container images.

| Tool                                    | Primary Role | Notes                                                             |
| :-------------------------------------- | :----------- | :---------------------------------------------------------------- |
| **[GitLab](https://about.gitlab.com/)** | Git + CI/CD  | All-in-one, self-hosted platform for code and container registry. |

### Orchestration

Defines, schedules, and monitors all data pipelines and workflows.

| Tool                                       | Primary Role      | Notes                                                              |
| :----------------------------------------- | :---------------- | :----------------------------------------------------------------- |
| **[Dagster](https://dagster.io/)**         | Data Orchestrator | A modern, asset-based orchestrator. Our primary choice.            |
| **[Prefect](https://www.prefect.io/)**     | Data Orchestrator | A Python-native workflow engine with a focus on dynamic pipelines. |
| **[Airflow](https://airflow.apache.org/)** | Data Orchestrator | The classic, battle-tested tool. Evaluated as an alternative.      |

### Data Ingestion

Handles moving data from external sources into the platform.

| Tool                                            | Primary Role    | Notes                                                          |
| :---------------------------------------------- | :-------------- | :------------------------------------------------------------- |
| **[SFTPGo](https://github.com/drakkan/sftpgo)** | SFTP Server     | For ingesting files from external partners via SFTP.           |
| _(TBD)_                                         | Database Movers | (e.g., Airbyte, Meltano) For moving data from operational DBs. |

### Object Storage

The "data lake" for storing all raw and processed data in an S3-compatible format.

| Tool                                        | Primary Role          | Notes                                                        |
| :------------------------------------------ | :-------------------- | :----------------------------------------------------------- |
| **[MinIO](https://min.io/)**                | S3-Compatible Storage | High-performance, distributed object storage.                |
| **[Garage](https://garage.deuxfleurs.fr/)** | S3-Compatible Storage | Alternative focused on distributed, multi-datacenter setups. |

### Data Compute

The processing engines for running large-scale transformations.

| Tool                                          | Primary Role        | Notes                                                         |
| :-------------------------------------------- | :------------------ | :------------------------------------------------------------ |
| **[Apache Spark](https://spark.apache.org/)** | Distributed Compute | Primary engine for large-scale data transformation (ETL/ELT). |
| **[Sail](https://github.com/squat/sail)**     | (TBD)               | (TBD)                                                         |

### Serverless Compute

For running event-driven, short-lived functions.

| Tool                                                  | Primary Role  | Notes                                                   |
| :---------------------------------------------------- | :------------ | :------------------------------------------------------ |
| **[Apache OpenWhisk](https://openwhisk.apache.org/)** | FaaS Platform | Ideal for real-time ingestion, ML model inference, etc. |

### Governance & BI

For visualizing, monitoring, and governing the data.

| Tool                                                | Primary Role          | Notes                                                 |
| :-------------------------------------------------- | :-------------------- | :---------------------------------------------------- |
| **[Apache Superset](https://superset.apache.org/)** | Business Intelligence | Data visualization, dashboards, and BI.               |
| **[Apache Nifi](https://nifi.apache.org/)**         | Data Flow             | Visual data-flow management, governance, and lineage. |

Here is a complete, polished Markdown section you can paste directly into your `README.md`. It covers prerequisites, the startup sequence, and how to use the development tunnel.

---

Based on your GitOps architecture (`clusters/dev` vs `clusters/prd`), here is the exact order of commands for both environments.

### 💻 Scenario 1: Local Development (Kind on Mac)

**Goal:** Create a cluster from scratch, hack networking to work on Mac, and start developing.

1.  **Commit your changes** (Flux pulls from Git, not your disk):
    ```sh
    git push origin main
    ```
2.  **Create Cluster & Network:**
    - Creates Kind.
    - Injects the IP into ConfigMap.
    - Installs Cilium manually (to fix `NotReady` nodes).
    <!-- end list -->
    ```sh
    just up
    ```
3.  **Install Flux:**
    - Installs controllers.
    - Adopts Cilium.
    - Installs Platform (RustFS, Sail).
    <!-- end list -->
    ```sh
    just bootstrap
    ```
4.  **Access Services:**
    - Opens the tunnel to `*.localhost`.
    <!-- end list -->
    ```sh
    just connect
    ```

---

### ☁️ Scenario 2: VPS / Cloud (Production)

**Goal:** Connect to a real remote cluster (e.g., Hetzner, AWS) that was provisioned with **No CNI** and **No Kube-Proxy**.

**Prerequisite:** You have the `KUBECONFIG` for your remote cluster.

1.  **Connect to Remote Cluster:**

    ```sh
    export KUBECONFIG=~/path/to/vps.kubeconfig
    ```

2.  **Bootstrap Networking (Manual Step):**

    - You cannot use `just up` (it tries to create Kind).
    - You must manually run the Helm command to install Cilium, but with the **Real Public IP** of your VPS.

    <!-- end list -->

    ```sh
    # 1. Install CRDs
    kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/experimental-install.yaml

    # 2. Install Cilium (Point host to API Server Internal IP)
    helm install cilium cilium/cilium \
      --version 1.18.4 \
      --namespace kube-system \
      -f values/cilium.yaml \
      --set k8sServiceHost=10.0.0.1 \   <-- YOUR VPS PRIVATE IP
      --set k8sServicePort=6443
    ```

3.  **Bootstrap Flux:**

    - You override the path to point to the Production cluster definition.

    <!-- end list -->

    ```sh
    just bootstrap path=clusters/prd
    ```

4.  **Access:**

    - **Do not** use `just connect`.
    - Get the External IP of your Gateway: `kubectl get svc -n default`.
    - Configure your DNS (Cloudflare/GoDaddy) to point `*.your-domain.com` to that IP.

---

### Summary Checklist

| Step              | Local (Kind)                          | VPS / Cloud (Strict Mode)                  |
| :---------------- | :------------------------------------ | :----------------------------------------- |
| **1. Provision**  | `just up` (Creates Kind)              | Terraform / Ansible / Manual               |
| **2. Networking** | `just up` (Auto-runs `bootstrap-cni`) | **Manual Helm Install** (Targeting VPS IP) |
| **3. GitOps**     | `just bootstrap`                      | `just bootstrap path=clusters/prd`         |
| **4. Access**     | `just connect` (Tunnel)               | Public DNS / LoadBalancer IP               |
