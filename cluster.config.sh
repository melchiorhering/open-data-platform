#!/bin/bash
set -e
# ====================================================================
# 1. CONFIGURATION
# ====================================================================

# --- Versions ---
export GATEWAY_API_VERSION="1.4.0"
export CILIUM_VERSION="1.18.4"
export CERT_MANAGER="1.19.0"

# --- Cluster Details ---
# The name of your Kind cluster (from kind-config.yaml)
KIND_CLUSTER_NAME="local"
# The control plane node name (usually <cluster-name>-control-plane)
KIND_CONTROL_PLANE_NODE="${KIND_CLUSTER_NAME}-control-plane"
API_SERVER_PORT=6443

# --- Network & Resources ---
GATEWAY_NAMESPACE="default"
GATEWAY_SERVICE_NAME="cilium-gateway-internet-gateway"

# --- File Paths ---
# Define all paths here so you don't hunt for them later
PATH_POLICIES="./components/network/cilium/policies"
PATH_CA_ISSUER="./components/network/cilium/ca-issuer.yaml"
PATH_GATEWAY_CONFIG="./components/network/cilium/gateway/"
PATH_IPAM_POOL="./components/network/cilium/ipam.yaml"
PATH_L2_POLICY="./components/network/cilium/l2-policy.yaml"
PATH_NODEPORT_PATCH="./components/network/cilium/gateway/nodeport-patch.yaml"

# ====================================================================
# 2. PRE-FLIGHT CHECKS
# ====================================================================
echo "🔍 Running Pre-flight checks..."

# Check if critical files exist before starting
for file in "$PATH_NODEPORT_PATCH" "$PATH_CA_ISSUER"; do
    if [ ! -f "$file" ]; then
        echo "❌ ERROR: Required file not found: $file"
        exit 1
    fi
done

# Get API Server IP dynamically
echo "   ... Fetching API Server IP from Docker container"
API_SERVER_IP=$(kubectl get nodes "$KIND_CONTROL_PLANE_NODE" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')

if [ -z "$API_SERVER_IP" ]; then
    echo "❌ ERROR: Could not detect Kind Control Plane IP. Is the cluster running?"
    exit 1
fi

echo "✅ Config Loaded. API Server: $API_SERVER_IP:$API_SERVER_PORT"
echo "🚀 Starting Cluster Setup..."

# ====================================================================
# 3. EXECUTION
# ====================================================================

# --- Helm Repos ---
echo "📦 Adding Helm repositories..."
helm repo add cilium https://helm.cilium.io/
helm repo add jetstack https://charts.jetstack.io
helm repo update > /dev/null

# --- Gateway API CRDs ---
echo "🔗 Installing Gateway API CRDs (Standard)..."
kubectl apply --server-side -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/v${GATEWAY_API_VERSION}/standard-install.yaml"

# --- Install Cilium ---
echo "🐝 Installing Cilium (v${CILIUM_VERSION})..."
helm upgrade --install cilium cilium/cilium --version ${CILIUM_VERSION} \
    --namespace kube-system \
    --create-namespace \
    --wait \
    --set ipam.mode=kubernetes \
    --set kubeProxyReplacement=true \
    --set k8sServiceHost=${API_SERVER_IP} \
    --set k8sServicePort=${API_SERVER_PORT} \
    --set gatewayAPI.enabled=true \
    --set l2announcements.enabled=true \
    --set l2announcements.leaseDuration=15s \
    --set l2announcements.leaseRenewDeadline=5s \
    --set l2announcements.leaseRetryPeriod=2s \
    --set externalIPs.enabled=true \
    --set operator.replicas=1 \
    --set hubble.relay.enabled=true \
    --set hubble.ui.enabled=true

# --- Install Cert Manager ---
echo "🔒 Installing Cert-Manager..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v${CERT_MANAGER}/cert-manager.crds.yaml

helm upgrade --install cert-manager jetstack/cert-manager --version v${CERT_MANAGER} \
    --namespace cert-manager \
    --create-namespace \
    --wait \
    --set config.apiVersion="controller.config.cert-manager.io/v1alpha1" \
    --set config.kind="ControllerConfiguration" \
    --set config.enableGatewayAPI=true

# --- Apply Zero Trust Policies ---
if [ -d "$PATH_POLICIES" ] && find "$PATH_POLICIES" -maxdepth 1 -type f \( -name "*.yaml" -o -name "*.yml" \) | grep -q .; then
    echo "🛡️  Applying ZERO TRUST Lockdown..."
    kubectl apply -f "$PATH_POLICIES"
    echo "✅  Zero Trust policies applied."
else
    echo "⚠️  No policies found in $PATH_POLICIES. Skipping Lockdown."
fi

# --- Setup Gateway Infra ---
echo "📝 Creating CA & Gateway..."
kubectl apply -f "$PATH_CA_ISSUER"
sleep 2
kubectl apply -f "$PATH_GATEWAY_CONFIG"

# --- Cluster Entrance (L2 & Patching) ---
echo "💧 Applying IPAM Pool..."
kubectl apply -f "$PATH_IPAM_POOL"

echo "📢 Applying L2 Announcement Policy..."
kubectl apply -f "$PATH_L2_POLICY"

echo "🔧 Patching Gateway to match Kind NodePorts..."

# Wait for Service Generation
attempt=0
while ! kubectl get svc "$GATEWAY_SERVICE_NAME" -n "$GATEWAY_NAMESPACE" &> /dev/null; do
    if [ $attempt -eq 30 ]; then echo "❌ Gateway Service never appeared!"; exit 1; fi
    echo "   ... waiting for Service generation ($attempt/30)"
    attempt=$((attempt+1))
    sleep 2
done

# Apply Patch
kubectl patch svc "$GATEWAY_SERVICE_NAME" -n "$GATEWAY_NAMESPACE" --patch-file "$PATH_NODEPORT_PATCH"

echo "✅ Gateway is now bound to Host Ports 80/443"

# --- Final Output ---
# Wait for IP assignment for pretty output
echo "⏳ Waiting for Gateway IP..."
while [ -z "$(kubectl get svc "$GATEWAY_SERVICE_NAME" -n "$GATEWAY_NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')" ]; do
    sleep 1
done
LB_IP=$(kubectl get svc "$GATEWAY_SERVICE_NAME" -n "$GATEWAY_NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "=================================================================="
echo "🎉 CLUSTER SETUP COMPLETE!"
echo "🚀 Gateway IP: $LB_IP"
echo "🔗 Access via: https://localhost or https://<service>.localhost"
echo "=================================================================="