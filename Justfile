set shell := ["bash", "-c"]

# ----------------------------------------------------------------------
# VARIABLES (Loaded from direnv)
# ----------------------------------------------------------------------
cluster_name      := env('CLUSTER_NAME', 'local')
config_file       := env('KIND_CONFIG', 'kind-config.yml')

# Flux Configuration
flux_gh_user      := env('FLUX_GITHUB_USER', '')
flux_gh_repo      := env('FLUX_GITHUB_REPO', '')
flux_gh_token     := env('FLUX_GITHUB_TOKEN', '')
flux_gh_branch    := env('FLUX_GITHUB_BRANCH', 'main')
flux_cluster_path := env('FLUX_CLUSTER_PATH', 'clusters/dev')

# Versions
cilium_ver        := env('CILIUM_VERSION', '1.18.4')

# ----------------------------------------------------------------------
# DEFAULT
# ----------------------------------------------------------------------
default:
    @just --list

# ----------------------------------------------------------------------
# 1. LIFECYCLE
# ----------------------------------------------------------------------

# Create Cluster, Inject IP, and Bootstrap Networking
up:
    @if ! docker info > /dev/null 2>&1; then echo "❌ Docker not running!"; exit 1; fi

    @# 1. Create Cluster
    @if ! kind get clusters | grep -q "^{{cluster_name}}$"; then \
        echo "📦 Creating Kind cluster '{{cluster_name}}'..."; \
        kind create cluster --config {{config_file}} --name {{cluster_name}}; \
    else \
        echo "✅ Cluster '{{cluster_name}}' is running."; \
    fi

    @# 2. Inject Dynamic IP (For Flux later)
    @echo "💉 Injecting Kind IP into Cluster ConfigMap..."
    @KIND_IP=$(kubectl get nodes {{cluster_name}}-control-plane -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}') && \
    kubectl create ns flux-system --dry-run=client -o yaml | kubectl apply -f - && \
    kubectl create configmap cilium-env-values -n flux-system \
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
    @echo "🐝 Bootstrapping Cilium CNI (Pre-Flux)..."
    @KIND_IP=$(kubectl get nodes {{cluster_name}}-control-plane -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}') && \
    helm repo add cilium https://helm.cilium.io/ && \
    helm repo update > /dev/null && \
    helm upgrade --install cilium cilium/cilium \
        --version {{cilium_ver}} \
        --namespace kube-system \
        --create-namespace \
        --wait \
        -f clusters/infrastructure/base/cilium.yaml \
        --set k8sServiceHost=$$KIND_IP \
        --set k8sServicePort=6443

# Install Flux (Requires GITHUB_TOKEN)
bootstrap:
    @if [ -z "{{flux_gh_user}}" ] || [ -z "{{flux_gh_token}}" ]; then \
        echo "❌ Error: FLUX_GITHUB_USER or FLUX_GITHUB_TOKEN not set in .envrc"; \
        exit 1; \
    fi
    @echo "🚀 Bootstrapping Flux for {{flux_gh_user}}/{{flux_gh_repo}}..."
    @# Export the token as GITHUB_TOKEN so Flux CLI can find it
    @export GITHUB_TOKEN={{flux_gh_token}} && \
    flux bootstrap github \
        --owner={{flux_gh_user}} \
        --repository={{flux_gh_repo}} \
        --branch={{flux_gh_branch}} \
        --path={{flux_cluster_path}} \
        --personal

# Force Sync
sync:
    @echo "🔄 Forcing Reconciliation..."
    flux reconcile source git open-data-platform
    flux reconcile kustomization crds
    flux reconcile kustomization infrastructure
    flux reconcile kustomization platform

# ----------------------------------------------------------------------
# 3. DEVELOPMENT ACCESS
# ----------------------------------------------------------------------

connect:
    #!/usr/bin/env bash
    BRIDGE_POD="gateway-bridge-interactive"

    cleanup() {
        echo ""
        echo "🧹 Cleaning up bridge pod..."
        kubectl delete pod $BRIDGE_POD --force --grace-period=0 > /dev/null 2>&1
    }
    trap cleanup EXIT

    echo "🛠️  Spinning up Bridge Pod..."
    kubectl run $BRIDGE_POD --image=alpine/socat --restart=Never -- \
        tcp-listen:443,fork,reuseaddr tcp-connect:cilium-gateway-internet-gateway.default:443 > /dev/null 2>&1 || true

    echo "⏳ Waiting for Pod..."
    kubectl wait --for=condition=Ready pod/$BRIDGE_POD --timeout=30s > /dev/null

    echo "🔌 Opening Tunnel..."
    echo "   -> https://s3.localhost"
    echo "   -> https://console.localhost"
    echo "   (Press Ctrl+C to stop)"

    sudo kubectl port-forward pod/$BRIDGE_POD 443:443