# GitOps with Argo CD

## Overview
This project runs Argo CD locally and uses it to deploy an NGINX workload from a Git repository. The local `service.yaml` exposes the deployed NGINX pods inside the cluster.

This setup is intended for a local Kubernetes cluster such as Minikube or kind. It does not require a cloud provider.

## Prerequisites
- A running local Kubernetes cluster
- `kubectl` configured to use that cluster
- `helm`
- `helmfile`

## Repository Structure
- `helmfile.yaml`: installs Argo CD.
- `application.yaml`: registers the NGINX Git repository as an Argo CD Application.
- `service.yaml`: creates a Kubernetes Service for the NGINX pods.
- `Makefile`: provides the install, port-forward, and cleanup commands.

## Usage

Run the complete local setup from this directory:

```bash
make apply
```

This installs Argo CD, creates the `nginx` Argo CD Application, and applies the NGINX Service. Argo CD then reads `nginx-deployment.yaml` from the configured Git repository and creates the Deployment and Pods in the `nginx` namespace.

## Access the Applications

Use separate terminals for the port-forwards:

```bash
make PORT=8080:443 pf-argocd
make PORT=8081:80 pf-nginx
```

Open `https://localhost:8080` for the Argo CD web interface and `http://localhost:8081` for the NGINX welcome page.

The Argo CD endpoint uses HTTPS, so your browser may display a certificate warning when accessing it locally.

## Validation

```bash
kubectl get application --namespace=argocd
kubectl describe application nginx --namespace=argocd
kubectl get deployment,pods,service --namespace=nginx
```

## Cleanup

```bash
make destroy
```