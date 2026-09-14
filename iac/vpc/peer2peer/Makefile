SHELL := /bin/bash
TF := terraform

init:
	$(TF) init

fmt:
	$(TF) fmt -recursive

validate:
	$(TF) validate

plan:
	$(TF) plan

apply:
	$(TF) apply -auto-approve

inspect:
	./scripts/inspect.sh

destroy:
	$(TF) destroy -auto-approve
