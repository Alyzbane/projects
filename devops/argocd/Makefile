SHELL := /bin/bash

PORT :=

apply: argocd nginx nginx-svc

nginx:
	kubectl apply -f application.yaml

argocd:
	helmfile --file=helmfile.yaml sync

nginx-svc:
	kubectl apply -f service.yaml

destroy:
	kubectl delete -f application.yaml --ignore-not-found
	kubectl delete -f service.yaml --ignore-not-found
	kubectl delete ns nginx --ignore-not-found
	helmfile --file=helmfile.yaml destroy

# Port forward

pf-argocd:
	kubectl port-forward svc/argocd-server -n argocd ${PORT}

pf-raw-nginx:
	kubectl port-forward -n nginx $$(kubectl get pod -n nginx -l app=nginx -o jsonpath='{.items[0].metadata.name}') ${PORT}

pf-nginx:
	kubectl port-forward svc/nginx -n nginx ${PORT}