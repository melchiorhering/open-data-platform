set shell := ["bash", "-c"]

# ----------------------------------------------------------------------
# VARIABLES (Loaded from direnv)
# ----------------------------------------------------------------------
cluster_name      := env('CLUSTER_NAME', 'local')
config_file       := env('KIND_CONFIG', 'kind-config.yml')

# Flux Configuration
flux_gh_user      := env('FLUX_GITHUB_USER', '')
flux_gh_repo      := env('FLUX_GITHUB_REPO', '')
flux_gh_branch    := env('FLUX_GITHUB_BRANCH', 'main')
flux_cluster_path := env('FLUX_CLUSTER_PATH', 'clusters/dev')

# SSH Configuration
flux_key_path     := env('FLUX_SSH_KEY_PATH', env('HOME') / '.ssh/id_ed25519')

# Versions
gateway_api_ver   := env('GATEWAY_API_VERSION', '1.4.0')
cilium_ver        := env('CILIUM_VERSION', '1.18.4')

# ----------------------------------------------------------------------
# DEFAULT
# ----------------------------------------------------------------------
default:
    @just --list

# ----------------------------------------------------------------------
# 0. PREREQUISITES
# ----------------------------------------------------------------------

# Verify all required tools are installed
check-tools:
    @echo "🔍 Checking prerequisites..."
    @for tool in docker kind kubectl helm flux; do \
        if ! command -v $tool &> /dev/null; then \
            echo "❌ Error: '$tool' is not installed."; \
            exit 1; \
        fi; \
    done
    @if ! docker info > /dev/null 2>&1; then \
        echo "❌ Error: Docker is not running!"; \
        exit 1; \
    fi
    @echo "✅ All tools ready."

# ----------------------------------------------------------------------
# 1. LIFECYCLE
# ----------------------------------------------------------------------

# Create Cluster, Inject IP, and Bootstrap Networking
up: check-tools
    @# 1. Create Cluster
    @if ! kind get clusters | grep -q "^{{cluster_name}}$"; then \
        echo "📦 Creating Kind cluster '{{cluster_name}}'..."; \
        kind create cluster --config {{config_file}} --name {{cluster_name}}; \
    else \
        echo "✅ Cluster '{{cluster_name}}' is running."; \
    fi

    @# 2. Inject Dynamic IP for Flux/Cilium
    @echo "💉 Injecting Kind IP into Cluster ConfigMap..."
    @# We capture the IP and inject it into the 'kube-system' namespace for Cilium to read.
    @KIND_IP=$(kubectl get nodes {{cluster_name}}-control-plane -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}') && \
    kubectl create configmap cilium-env-values -n kube-system \
        --from-literal=k8sServiceHost=$$KIND_IP \
        --from-literal=k8sServicePort=6443 \
        --dry-run=client -o yaml | kubectl apply -f -

    @# 3. Install CNI (Critical: Flux cannot start without this!)
    @just bootstrap-cni

# Destroy Cluster
down:
    @echo "🧨 Destroying cluster..."
    @kind delete cluster --name {{cluster_name}}

# ----------------------------------------------------------------------
# 2. BOOTSTRAP & SYNC
# ----------------------------------------------------------------------

# Manually install Cilium to get the cluster networking Online
# (Flux will adopt this release later)
bootstrap-cni:
    @echo "🔗 Installing Gateway API CRDs (Required for Cilium)..."
    @kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v{{gateway_api_ver}}/experimental-install.yaml

    @echo "🐝 Bootstrapping Cilium CNI (Pre-Flux)..."
    @KIND_IP=$(kubectl get nodes {{cluster_name}}-control-plane -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}') && \
    helm repo add cilium https://helm.cilium.io/ && \
    helm repo update > /dev/null && \
    helm upgrade --install cilium cilium/cilium \
        --version {{cilium_ver}} \
        --namespace kube-system \
        --create-namespace \
        --wait \
        -f infrastructure/values/cilium.yaml \
        --set k8sServiceHost=$KIND_IP \
        --set k8sServicePort=6443

# Bootstrap Flux using SSH
bootstrap: check-tools
    @if [ ! -f "{{flux_key_path}}" ]; then \
        echo "❌ Error: SSH Key not found at {{flux_key_path}}"; \
        echo "   Set FLUX_SSH_KEY_PATH in .envrc if your key is elsewhere."; \
        exit 1; \
    fi
    @echo "🚀 Bootstrapping Flux via SSH..."
    @echo "   Repo: ssh://git@github.com/{{flux_gh_user}}/{{flux_gh_repo}}"
    @echo "   Key:  {{flux_key_path}}"
    flux bootstrap git \
        --url=ssh://git@github.com/{{flux_gh_user}}/{{flux_gh_repo}} \
        --branch={{flux_gh_branch}} \
        --path={{flux_cluster_path}} \
        --private-key-file={{flux_key_path}} \
        --silent

# Force Sync
sync:
    @echo "🔄 Forcing Reconciliation..."
    @# 1. Reconcile the Source (Git)
    flux reconcile source git flux-system -n flux-system

    @# 2. Reconcile the Layers (Kustomizations)
    flux reconcile kustomization crds -n flux-system
    flux reconcile kustomization infrastructure -n flux-system
    flux reconcile kustomization platform -n flux-system

# ----------------------------------------------------------------------
# 3. DEVELOPMENT ACCESS
# ----------------------------------------------------------------------

connect:
    #!/usr/bin/env bash
    BRIDGE_POD="gateway-bridge-interactive"
    # We target the internal Service DNS of the Gateway
    GATEWAY_SVC="cilium-gateway-internet-gateway.default"

    cleanup() {
        echo ""
        echo "🧹 Cleaning up bridge pod..."
        kubectl delete pod $BRIDGE_POD --force --grace-period=0 > /dev/null 2>&1
    }
    trap cleanup EXIT

    echo "🛠️  Spinning up Bridge Pod..."
    # We listen on 443 and forward to the Gateway Service
    kubectl run $BRIDGE_POD --image=alpine/socat --restart=Never -- \
        tcp-listen:443,fork,reuseaddr tcp-connect:$GATEWAY_SVC:443 > /dev/null 2>&1 || true

    echo "⏳ Waiting for Pod..."
    kubectl wait --for=condition=Ready pod/$BRIDGE_POD --timeout=30s > /dev/null

    echo "🔌 Opening Tunnel..."
    echo "   -> https://s3.localhost"
    echo "   -> https://console.localhost"
    echo "   (Press Ctrl+C to stop)"

    # Sudo required for port 443 on Mac
    sudo kubectl port-forward pod/$BRIDGE_POD 443:443