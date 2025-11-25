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
# We use && to chain commands so the export persists for the helmfile command
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