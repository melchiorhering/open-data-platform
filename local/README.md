# Local Development

# Perequisites

- Kind
- Helm
- Cilium CLI

## Kind

Create the a cluster with the `kind-config.yml` for local development

```bash
kind create cluster --config=kind-config.yml
```

Setup Cilium & Hubble using helm:
```bash
helm install cilium cilium/cilium --version 1.18.3 \
    --namespace kube-system \
    --set image.pullPolicy=IfNotPresent \
    --set ipam.mode=kubernetes \
    --set hubble.relay.enabled=true \
    --set hubble.ui.enabled=true
```
