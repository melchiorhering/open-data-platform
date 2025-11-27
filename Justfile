set shell := ["bash", "-c"]

# ----------------------------------------------------------------------
# VARIABLES
# ----------------------------------------------------------------------
cluster_name := "local"
config_file  := "kind-config.yml"

# Versions (Sync these with your Flux/Helmfile setup)
gateway_api_version  := "1.2.0"
cilium_version       := "1.18.4"
cert_manager_version := "1.19.0"

# ----------------------------------------------------------------------
# DEFAULT
# ----------------------------------------------------------------------
default:
    @just --list

# ----------------------------------------------------------------------
# 1. LIFECYCLE (Cluster Management)
# ----------------------------------------------------------------------

# Create the Cluster and install Base Infra
up:
    @# A. Pre-flight Check: Is Docker running?
    @if ! docker info > /dev/null 2>&1; then \
        echo "❌ Error: Docker is not running!"; \
        exit 1; \
    fi

    @# B. Create Cluster
    @set -e; \
    echo "📦 Checking for Kind cluster '{{cluster_name}}'..."; \
    if ! kind get clusters | grep -q "^{{cluster_name}}$"; then \
        echo "🚀 Creating cluster (No CNI)..."; \
        kind create cluster --config {{config_file}} --name {{cluster_name}}; \
        echo "✅ Cluster created."; \
    else \
        echo "✅ Cluster '{{cluster_name}}' is already running."; \
    fi

    @# C. Chain the base infrastructure install
    @just apply-base

# Destroy the Cluster
down:
    @echo "🧨 Deleting Kind cluster '{{cluster_name}}'..."
    @kind delete cluster --name {{cluster_name}}

# ----------------------------------------------------------------------
# 2. INFRASTRUCTURE (Helm - Replaces Helmfile for Infra)
# ----------------------------------------------------------------------

# Install the Base layer (Cilium, Gateway API, Cert-Manager) directly via Helm
apply-base:
    @echo "🔍 Detecting Kind Control Plane IP..."
    @# Capture IP in a bash variable (Fixing the Make syntax error)
    @KIND_IP=$$(kubectl get nodes {{cluster_name}}-control-plane -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}') && \
    KIND_PORT=6443 && \
    echo "🎯 Detected API Server: $$KIND_IP:$$KIND_PORT" && \
    \
    echo "📦 Installing Repos..." && \
    helm repo add cilium https://helm.cilium.io/ && \
    helm repo add jetstack https://charts.jetstack.io && \
    helm repo update > /dev/null && \
    \
    echo "🔗 Installing Gateway API CRDs..." && \
    kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v{{gateway_api_version}}/experimental-install.yaml && \
    \
    echo "🐝 Installing Cilium v{{cilium_version}}..." && \
    helm upgrade --install cilium cilium/cilium \
        --version {{cilium_version}} \
        --namespace kube-system \
        --create-namespace \
        --wait \
        -f clusters/dev/base/cilium.yaml \
        --set k8sServiceHost=$$KIND_IP \
        --set k8sServicePort=$$KIND_PORT && \
    \
    echo "🔒 Installing Cert-Manager v{{cert_manager_version}}..." && \
    helm upgrade --install cert-manager jetstack/cert-manager \
        --version v{{cert_manager_version}} \
        --namespace cert-manager \
        --create-namespace \
        --wait \
        -f clusters/dev/base/cert-manager.yaml && \
    \
    echo "🧩 Installing Cluster Config (Glue)..." && \
    helm upgrade --install cluster-config ./charts/cluster-config \
        --namespace default \
        --create-namespace && \
    \
    echo "✅ Base Infrastructure Ready!"

# ----------------------------------------------------------------------
# 3. APPLICATIONS (Helmfile - For Apps only)
# ----------------------------------------------------------------------

# Apply the Applications Layer (RustFS, Sail, etc)
apply-apps +args="":
    @# Verify cluster is reachable first
    @if ! kubectl cluster-info > /dev/null 2>&1; then \
        echo "❌ Error: Cluster is not running. Run 'just up' first."; \
        exit 1; \
    fi
    @echo "🔍 Detecting Kind Control Plane IP for Apps..."
    @export KIND_API_IP=$(kubectl get nodes {{cluster_name}}-control-plane -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}') && \
    helmfile apply {{args}}

# Install the Demo App (Echo Server)
deploy-demo:
    @echo "🚀 Deploying Demo Applications..."
    @kubectl apply -f tests/kubernetes/test-echo.yaml
    @kubectl rollout status deployment/test-echo -n default --timeout=60s

# ----------------------------------------------------------------------
# 4. INTERACTIVE ACCESS & TESTING
# ----------------------------------------------------------------------

# Interactive Access (Keep this terminal open to browse)
connect:
    #!/usr/bin/env bash
    BRIDGE_POD="gateway-bridge-interactive"
    GATEWAY_SVC="cilium-gateway-internet-gateway"

    # Define cleanup to run on exit
    cleanup() {
        echo ""
        echo "🧹 Cleaning up bridge pod..."
        kubectl delete pod $BRIDGE_POD --force --grace-period=0 > /dev/null 2>&1
    }
    trap cleanup EXIT

    echo "🛠️  Spinning up Bridge Pod ($BRIDGE_POD)..."
    # Create the bridge if it doesn't exist
    kubectl run $BRIDGE_POD --image=alpine/socat --restart=Never -- \
        tcp-listen:443,fork,reuseaddr tcp-connect:$GATEWAY_SVC:443 > /dev/null 2>&1 || true

    echo "⏳ Waiting for Pod..."
    kubectl wait --for=condition=Ready pod/$BRIDGE_POD --timeout=30s > /dev/null

    echo "🔌 Opening Tunnel..."
    echo "   -> https://echo.localhost"
    echo "   (Press Ctrl+C to stop)"

    # Sudo is required to bind port 443 on Mac
    sudo kubectl port-forward pod/$BRIDGE_POD 443:443

# Run the full test suite (Deploys apps -> runs test -> cleans up)
test: deploy-demo
    #!/usr/bin/env bash
    set -e

    BRIDGE_POD="gateway-bridge-test"
    GATEWAY_SVC="cilium-gateway-internet-gateway"

    echo "🛠️  Creating temporary Bridge Pod..."
    kubectl run $BRIDGE_POD --image=alpine/socat --restart=Never -- \
        tcp-listen:8443,fork,reuseaddr tcp-connect:$GATEWAY_SVC:443 > /dev/null 2>&1 || true

    kubectl wait --for=condition=Ready pod/$BRIDGE_POD --timeout=30s > /dev/null

    echo "🔌 Opening Tunnel..."
    kubectl port-forward pod/$BRIDGE_POD 8443:8443 > /dev/null 2>&1 &
    PID=$!

    cleanup() {
        kill $PID 2>/dev/null || true
        kubectl delete pod $BRIDGE_POD --force --grace-period=0 > /dev/null 2>&1
    }
    trap cleanup EXIT

    echo "⏳ Stabilizing..."
    sleep 2

    echo "📡 Verifying https://echo.localhost:8443 ..."
    curl -k -v --resolve echo.localhost:8443:127.0.0.1 https://echo.localhost:8443

    echo "✅ Test Passed!"

# ----------------------------------------------------------------------
# 5. UTILS
# ----------------------------------------------------------------------

# Check Gateway and Pod status
status:
    @echo "\n--- 🌐 Gateways ---"
    @kubectl get svc -n default -o wide || echo "No gateways found."
    @echo "\n--- 📦 Pods (Unhealthy Only) ---"
    @kubectl get pods -A | grep -v "Running\|Completed" || echo "All pods are healthy! 🎉"