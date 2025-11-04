# Local Development

# Perequisites

- Kind
- Helm
- Cilium CLI

## Kind

Create the first cluster with the `kind-config.yml`

```bash
kind create cluster --config=kind-config.yml
```

Setup Cilium & Hubble using helm:
```bash
helm upgrade cilium cilium/cilium --version 1.18.3 \
   --namespace kube-system \
   --reuse-values \
   --set hubble.relay.enabled=true
```
