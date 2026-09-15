TF := terraform
TF_DIR := terraform

init:
	$(TF) -chdir=$(TF_DIR) init

fmt:
	$(TF) -chdir=$(TF_DIR) fmt

validate:
	$(TF) -chdir=$(TF_DIR) validate

plan:
	$(TF) -chdir=$(TF_DIR) plan

apply:
	$(TF) -chdir=$(TF_DIR) apply -auto-approve

destroy:
	$(TF) -chdir=$(TF_DIR) destroy -auto-approve

output:
	$(TF) -chdir=$(TF_DIR) output
