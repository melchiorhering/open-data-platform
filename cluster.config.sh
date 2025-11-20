#!/bin/bash
set -e
# CONFIGURATION
export GATEWAY_API_VERSION="1.4.0"
export CILIUM_VERSION="1.18.4"
export CERT_MANAGER="1.19.0"

POLICY_DIR="./components/network/cilium/policies"
EXPECTED_SERVICE_NAME="cilium-gateway-internet-gateway"

echo "🚀 Starting Local Cluster Setup (Cilium + Gateway API)..."

# 1. ADD HELM REPOS
# ====================================================================
echo "📦 Adding Helm repositories..."
helm repo add cilium https://helm.cilium.io/
helm repo add jetstack https://charts.jetstack.io
helm repo update

# 2. GATEWAY API CRD SETUP
# ====================================================================
echo "🔗 Installing Gateway API CRDs..."
kubectl apply --server-side -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/v${GATEWAY_API_VERSION}/experimental-install.yaml"

# 3. INSTALL CILIUM
# ====================================================================
echo "🐝 Installing Cilium..."
# Added specific L2 settings based on documentation
helm upgrade --install cilium cilium/cilium --version ${CILIUM_VERSION} \
    --namespace kube-system \
    --create-namespace \
    --set ipam.mode=kubernetes \
    --set kubeProxyReplacement=true \
    --set gatewayAPI.enabled=true \
    --set l2announcements.enabled=true \
    --set l2announcements.leaseDuration=3s \
    --set l2announcements.leaseRenewDeadline=1s \
    --set l2announcements.leaseRetryPeriod=200ms \
    --set externalIPs.enabled=true \
    --set operator.replicas=1 \
    --set hubble.relay.enabled=true \
    --set hubble.ui.enabled=true \
    --set k8sClientRateLimit.qps=50 \
    --set k8sClientRateLimit.burst=100

echo "⏳ Waiting for Cilium to be ready..."
kubectl -n kube-system rollout status deployment/cilium-operator
kubectl -n kube-system rollout status ds/cilium --timeout=5m

# 4. INSTALL CERT MANAGER
# ====================================================================
echo "🔒 Installing Cert-Manager..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v${CERT_MANAGER}/cert-manager.crds.yaml

helm upgrade --install cert-manager jetstack/cert-manager --version v${CERT_MANAGER} \
    --namespace cert-manager \
    --create-namespace \
    --wait \
    --set config.apiVersion="controller.config.cert-manager.io/v1alpha1" \
    --set config.kind="ControllerConfiguration" \
    --set config.enableGatewayAPI=true

# 4b. APPLY ZERO TRUST BASELINE
# ====================================================================
# Check if directory exists AND contains .yaml or .yml files
if [ -d "$POLICY_DIR" ] && find "$POLICY_DIR" -maxdepth 1 -type f \( -name "*.yaml" -o -name "*.yml" \) | grep -q .; then
    echo "🛡️  Applying ZERO TRUST Lockdown (Loading from $POLICY_DIR)..."

    # Apply the whole folder
    kubectl apply -f "$POLICY_DIR"

    echo "   ✅ Zero Trust policies applied."
else
    echo "⚠️  No policies found in $POLICY_DIR. Skipping Zero Trust lockdown."
fi

# 5. SETUP CA & GATEWAY
# ====================================================================
echo "📝 Creating CA Infrastructure..."
kubectl apply -f ./components/network/cilium/ca-issuer.yaml
sleep 2

echo "🚪 Applying Gateway Configuration..."
kubectl apply -f ./components/network/cilium/gateway/

# 6. CLUSTER ENTRANCE (L2 MODE)
# ====================================================================
echo "💧 Applying IPAM Pool..."
kubectl apply -f ./components/network/cilium/ipam.yaml

echo "📢 Applying L2 Announcement Policy..."
# Ensure you created the file mentioned in step 1 above
kubectl apply -f ./components/network/cilium/l2-policy.yaml

echo "⏳ Waiting for Gateway Service to get an IP..."
attempt_counter=0
max_attempts=30
while ! kubectl get svc ${EXPECTED_SERVICE_NAME} -n default &> /dev/null; do
    if [ ${attempt_counter} -eq ${max_attempts} ];then
      echo "❌ Timeout waiting for Service '${EXPECTED_SERVICE_NAME}'"
      exit 1
    fi
    echo "   ... waiting for Service creation (${attempt_counter}/${max_attempts})"
    attempt_counter=$((attempt_counter+1))
    sleep 2
done

# Wait for an External IP to be assigned by IPAM
while [ -z "$(kubectl get svc ${EXPECTED_SERVICE_NAME} -n default -o jsonpath='{.status.loadBalancer.ingress[0].ip}')" ]; do
    echo "   ... waiting for LoadBalancer IP assignment..."
    sleep 2
done

LB_IP=$(kubectl get svc ${EXPECTED_SERVICE_NAME} -n default -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "=================================================================="
echo "🎉 CLUSTER SETUP COMPLETE!"
echo "🚀 Access your Gateway at: http://$LB_IP or https://$LB_IP"
echo "ℹ️  If using Kind on Mac/Windows, you might still need 'docker route' or NodePorts"
echo "   because the Docker VM network is isolated from your host."
echo "=================================================================="