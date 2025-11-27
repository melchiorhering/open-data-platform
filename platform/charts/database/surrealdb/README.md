# SurrealDB

For setting up SurrealDB in your Kubernetes cluster, refer to the [SurrealDB Docs](https://surrealdb.com/docs/surrealdb/deployment/kubernetes).

## TiDB

```bash
# First we need to extend the existing CRD to include the TiDBCluster resource.
kubectl create -f https://raw.githubusercontent.com/pingcap/tidb-operator/v1.4.5/manifests/crd.yaml
```
