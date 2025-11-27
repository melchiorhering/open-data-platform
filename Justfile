set shell := ["bash", "-c"]

# ----------------------------------------------------------------------
# VARIABLES
# ----------------------------------------------------------------------
cluster_name := "local"
config_file  := "kind-config.yml"
github_user  := "melchiorhering"
github_repo  := "open-data-platform"

# Default Flux settings
flux_branch  := "main"
flux_path    := "clusters/dev"

# ----------------------------------------------------------------------
# DEFAULT
# ----------------------------------------------------------------------
default:
    @just --list

# ----------------------------------------------------------------------
# 1. LIFECYCLE (Cluster Management)
# ----------------------------------------------------------------------

# Create Cluster & Prepare for Flux
up:
    @# 1. Check Docker
    @if ! docker info > /dev/null 2>&1; then \
        echo "❌ Error: Docker is not running!"; \
        exit 1; \
    fi

    @# 2. Create Kind Cluster
    @if ! kind get clusters | grep -q "^{{cluster_name}}$"; then \
        echo "📦 Creating Kind cluster..."; \
        kind create cluster --config {{config_file}} --name {{cluster_name}}; \
    else \
        echo "✅ Cluster '{{cluster_name}}' is running."; \
    fi

    @# 3. CRITICAL: Inject the Dynamic IP for Flux/Cilium
    @# We create the namespace and a ConfigMap BEFORE bootstrapping Flux.
    @# Cilium's HelmRelease will read this ConfigMap.
    @echo "💉 Injecting Kind IP into Cluster ConfigMap..."
    @# FIX: Use single $ for shell command substitution
    @KIND_IP=$(kubectl get nodes {{cluster_name}}-control-plane -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}') && \
    echo "   Detected IP: $KIND_IP" && \
    kubectl create ns flux-system --dry-run=client -o yaml | kubectl apply -f - && \
    kubectl create configmap cilium-env-values -n flux-system \
        --from-literal=k8sServiceHost=$KIND_IP \
        --from-literal=k8sServicePort=6443 \
        --dry-run=client -o yaml | kubectl apply -f -

# Destroy Cluster
down:
    @echo "🧨 Destroying cluster..."
    @kind delete cluster --name {{cluster_name}}

# ----------------------------------------------------------------------
# 2. FLUX OPERATIONS
# ----------------------------------------------------------------------

# Install Flux components and start sync
# Usage: just bootstrap [branch=main] [path=clusters/dev]
bootstrap branch=flux_branch path=flux_path:
    @echo "🚀 Bootstrapping Flux..."
    @echo "   Branch: {{branch}}"
    @echo "   Path:   {{path}}"
    @# This installs the Flux controllers and tells them to watch the specified path
    flux bootstrap github \
        --owner={{github_user}} \
        --repository={{github_repo}} \
        --branch={{branch}} \
        --path={{path}} \
        --personal

# Force a Sync (Useful during dev)
sync:
    @echo "🔄 Forcing Reconciliation..."
    flux reconcile source git open-data-platform
    flux reconcile kustomization crds
    flux reconcile kustomization infrastructure
    flux reconcile kustomization platform

# Watch the progress
watch:
    flux get kustomizations --watch

# ----------------------------------------------------------------------
# 3. LOCAL DEVELOPMENT (Tunneling)
# ----------------------------------------------------------------------

# Open the tunnel to access services
connect:
    #!/usr/bin/env bash
    BRIDGE_POD="gateway-bridge-interactive"
    GATEWAY_SVC="cilium-gateway-internet-gateway"

    # Cleanup trap
    cleanup() {
        echo ""
        echo "🧹 Cleaning up bridge pod..."
        kubectl delete pod $BRIDGE_POD --force --grace-period=0 > /dev/null 2>&1
    }
    trap cleanup EXIT

    echo "🛠️  Spinning up Bridge Pod ($BRIDGE_POD)..."
    kubectl run $BRIDGE_POD --image=alpine/socat --restart=Never -- \
        tcp-listen:443,fork,reuseaddr tcp-connect:$GATEWAY_SVC:443 > /dev/null 2>&1 || true

    echo "⏳ Waiting for Pod..."
    kubectl wait --for=condition=Ready pod/$BRIDGE_POD --timeout=30s > /dev/null

    echo "🔌 Opening Tunnel..."
    echo "   -> https://s3.localhost"
    echo "   -> https://console.localhost"
    echo "   (Press Ctrl+C to stop)"

    # Sudo required for port 443
    sudo kubectl port-forward pod/$BRIDGE_POD 443:443