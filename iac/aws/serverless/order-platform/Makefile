SHELL := /bin/bash

TF := lstk terraform -chdir=terraform
ARGS ?=

init:
	$(TF) init

fmt:
	$(TF) fmt -recursive

validate:
	$(TF) validate

plan:
	$(TF) plan

apply:
	$(TF) apply -auto-approve $(ARGS)

smoke:
	./scripts/smoke.sh

smoke-aws:
	./scripts/smoke-aws.sh

destroy:
	$(TF) destroy -auto-approve $(ARGS)
