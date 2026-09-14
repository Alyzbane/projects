SHELL := /bin/bash

TF := terraform -chdir=terraform

default: init validate

init:
	$(TF) init

fmt:
	$(TF) fmt

validate:
	$(TF) validate

output:
	$(TF) output

plan:
	$(TF) plan

apply:
	$(TF) apply -auto-approve

destroy:
	$(TF) destroy -auto-approve

test:
	./scripts/test.sh