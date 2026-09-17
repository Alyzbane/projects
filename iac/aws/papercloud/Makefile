TF := terraform -chdir=terraform

init:
	$(TF) init -var-file=terraform.tfvars

fmt:
	$(TF) fmt -recursive

validate:
	$(TF) validate

plan:
	$(TF) plan -var-file=terraform.tfvars

dns-zone:
	$(TF) apply -target=aws_route53_zone.this -var-file=terraform.tfvars -auto-approve

apply:
	$(TF) apply -var-file=terraform.tfvars -auto-approve

destroy:
	$(TF) destroy -var-file=terraform.tfvars -auto-approve

output:
	$(TF) output
