set shell := ["bash", "-c"]

# Variables
cluster_name := "local"
config_file  := "kind-config.yml"

# ----------------------------------------------------------------------
# DEFAULT
# ----------------------------------------------------------------------
default:
    @just --list

# ----------------------------------------------------------------------
# LIFECYCLE
# ----------------------------------------------------------------------

# Create the Cluster (Modified for No-CNI)
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
        echo "✅ Cluster created!"; \
        echo "ℹ️  Note: Nodes will stay 'NotReady' until you run 'just apply' to install Cilium."; \
    else \
        echo "✅ Cluster '{{cluster_name}}' is already running."; \
    fi

# Destroy the Cluster
down:
    @echo "🧨 Deleting Kind cluster '{{cluster_name}}'..."
    @kind delete cluster --name {{cluster_name}}

# ----------------------------------------------------------------------
# HELMFILE
# ----------------------------------------------------------------------

# Apply the infrastructure
apply +args="":
    @# Verify cluster is reachable first
    @if ! kubectl cluster-info > /dev/null 2>&1; then \
        echo "❌ Error: Cluster is not running. Run 'just up' first."; \
        exit 1; \
    fi
    @echo "🔍 Detecting Kind Control Plane IP..."
    @export KIND_API_IP=$(kubectl get nodes {{cluster_name}}-control-plane -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}') && \
    echo "🎯 Kind IP detected: $KIND_API_IP" && \
    helmfile apply {{args}}

# See what would change
diff:
    @just apply --diff

# Re-run specific releases only
sync app:
    @just apply --selector name={{app}}

# ----------------------------------------------------------------------
# UTILS
# ----------------------------------------------------------------------

# Check Gateway and Pod status
status:
    @echo "\n--- 🌐 Gateways ---"
    @kubectl get svc -n default -o wide || echo "No gateways found."
    @echo "\n--- 📦 Pods (Unhealthy Only) ---"
    @kubectl get pods -A | grep -v "Running\|Completed" || echo "All pods are healthy! 🎉"

# ----------------------------------------------------------------------
# APPLICATIONS
# ----------------------------------------------------------------------

# Install the Demo App (Echo Server)
# Run this once so you have something to look at!
deploy-apps:
    @echo "🚀 Deploying Demo Applications..."
    @kubectl apply -f tests/kubernetes/test-echo.yaml
    @kubectl rollout status deployment/test-echo -n default --timeout=60s

# ----------------------------------------------------------------------
# INTERACTIVE ACCESS
# ----------------------------------------------------------------------

# Interactive Access (Keep this terminal open to browse)
connect:
    #!/usr/bin/env bash
    BRIDGE_POD="gateway-bridge-interactive"
    GATEWAY_SVC="cilium-gateway-internet-gateway"

    # 1. Define cleanup first so it runs even if we crash/exit
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
    # When you Ctrl+C this, the 'trap' above triggers automatically
    sudo kubectl port-forward pod/$BRIDGE_POD 443:443

# ----------------------------------------------------------------------
# AUTOMATED TESTING
# ----------------------------------------------------------------------

# Run the full test suite (Deploys apps -> runs test -> cleans up)
test: deploy-apps
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