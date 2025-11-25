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

## 🛠️ Local Development

This project uses a local **Kind** cluster powered by **Cilium** and **Gateway API**. Due to Docker networking limitations on macOS, we use a bridge pattern to access services locally via `https://*.localhost`.

### 📋 Prerequisites

Ensure you have the following tools installed:

- **Docker Desktop**
- **Just** (`brew install just`)
- **Kubectl** (`brew install kubectl`)
- **Helmfile** (`brew install helmfile`)
- **Helm** (`brew install helm`)

### 🚀 Quick Start

1.  **Initialize the Cluster**
    Creates the Kind cluster and prepares the nodes.

    ```bash
    just up
    ```

2.  **Install Infrastructure**
    Deploys Cilium, Cert-Manager, and the Gateway configuration via Helmfile.

    ```bash
    just apply
    ```

3.  **Deploy Applications**
    Installs the demo applications (Echo Server) and HTTPRoutes.

    ```bash
    just deploy-apps
    ```

### 🌐 Accessing Services (The Tunnel)

To access your services from your browser (e.g., `https://echo.localhost`), you must open a bridge tunnel. This bypasses NodePort limitations on macOS.

1.  **Open the Tunnel** in a dedicated terminal window:

    ```bash
    just connect
    ```

    _(Note: This requires `sudo` to bind to your local port 443)._

2.  **Browse:**
    Open your browser to **[https://echo.localhost](https://www.google.com/search?q=https://echo.localhost)**.

    _You should see the success message from the Echo server via the Cilium Gateway._

### ✅ Verification

To run a full end-to-end automated test suite (which spins up a temporary bridge, curls the gateway, and cleans up):

```bash
just test
```

### 🧹 Teardown

To destroy the cluster and clean up all resources:

```bash
just down
```

---

### 📖 Command Reference

| Command            | Description                                                   |
| :----------------- | :------------------------------------------------------------ |
| `just up`          | Creates the Kind cluster (if missing).                        |
| `just apply`       | Installs system infrastructure (Cilium, Certs, Gateway).      |
| `just deploy-apps` | Installs application workloads and Routes.                    |
| `just connect`     | **Interactive Mode:** Opens a tunnel to access `*.localhost`. |
| `just test`        | **CI Mode:** Runs automated connectivity tests.               |
| `just status`      | Shows the status of Gateways and Pods.                        |
| `just down`        | Destroys the local cluster.                                   |
