# Kyverno CEL Policies

This project installs Kyverno and applies Kubernetes `ValidatingPolicy` resources that use CEL (Common Expression Language) to check Pods.

## What It Demonstrates

- `require-labels.yaml` requires a non-empty `app.kubernetes.io/name` label.
- `disallow-privileged-containers.yaml` rejects privileged containers, including regular, init, and ephemeral containers.
- Both policies use `validationActions: Deny`, so violating Pods are rejected by the admission webhook.

The policies match Pod `CREATE` and `UPDATE` requests. Kyverno evaluates each request before it is stored by the Kubernetes API server.

## Prerequisites

- A running Kubernetes cluster
- `kubectl`
- `helm`

## Install

```bash
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update

helm install kyverno kyverno/kyverno \
  --version=3.9.1 \
  --namespace=kyverno \
  --create-namespace \
  --wait \
  --wait-for-jobs
```

Apply the policies from the repository root:

```bash
kubectl apply -f policies/
kubectl get validatingpolicies.policies.kyverno.io
```

## Test CEL Policies in Deny Mode

Check the policy definitions:

```bash
kubectl describe validatingpolicy require-labels
kubectl describe validatingpolicy disallow-privileged-containers
```

Create a Pod without the required label. The admission request should be rejected:

```bash
kubectl run missing-label \
  --image=nginx \
  --restart=Never
```
Expected result:

```bash
Error from server: admission webhook "vpol.validate.kyverno.svc-fail" denied the request: Policy require-labels failed
```

Create a Pod with the required label. It should be admitted:

```bash
kubectl run valid-pod \
  --image=nginx \
  --restart=Never \
  --labels=app.kubernetes.io/name=nginx
```

To test the privileged-container expression, apply a temporary Pod manifest. It should be rejected:

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: privileged-test
  labels:
    app.kubernetes.io/name: privileged-test
spec:
  containers:
    - name: nginx
      image: nginx
      securityContext:
        privileged: true
EOF
```

Expected result:

```bash
Error from server: error when creating "STDIN": admission webhook "vpol.validate.kyverno.svc-fail" denied the request: Policy disallow-privileged-containers failed: Privileged mode is disallowed. All containers must set the securityContext.privileged field to `false` or unset the field. 
```

Now change the privilege value to `false` (or remove `securityContext`). It should be admitted:

```yaml
    privileged: false
```

Expected result:

```text
pod/privileged-test created
```

## Inspection

In `Deny` mode, rejected Pods are not created, so there may be no policy report for them. Check the policies and existing Pods with:

```bash
kubectl get pods
 
kubectl get policyreports -A
 
kubectl describe policyreport -n default
```

## How the CEL Expressions Work

Kyverno provides `object`, which is the Kubernetes resource being evaluated. The label policy reads the Pod label with:

```yaml
spec:
  validations:
    - expression: has(object.metadata.labels) && 'app.kubernetes.io/name' in object.metadata.labels && object.metadata.labels['app.kubernetes.io/name'] != ''
```

The privileged policy combines all container lists and requires every container to have `privileged` unset or `false`:

```yaml
spec:
  validations:
    - expression: variables.allContainers.all(container, container.?securityContext.?privileged.orValue(false) == false)
```

`.?` safely accesses an optional field, and `orValue(false)` supplies a value when the field is absent.

## Cleanup

```bash
kubectl delete pod valid-pod privileged-test --ignore-not-found
kubectl delete -f policies/
helm uninstall kyverno --namespace=kyverno
```