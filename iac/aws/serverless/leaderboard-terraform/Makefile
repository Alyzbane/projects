default:
	@echo "Deploy locally or on cloud"
	@echo "Usage: make <target>"
	@echo "Targets:"
	@echo "  cloud-deploy: Deploy on AWS"
	@echo "  cloud-web: Setup Cloud web frontend"
	@echo "  destroy: Destroy AWS resources"
	@echo "  local-deploy: Deploy on Localstack"
	@echo "  local-destroy: Destroy Localstack resources"
	@echo "  local-web: Deploy Web Interface on Localstack"
	@echo "  local-test: Run Localstack smoke test"

# Deploy the Terraform stack on AWS
cloud-deploy:
	@echo "Deploying on AWS"
	./deploy.sh

cloud-web:
	@echo "Setting up Cloud web frontend"
	./scripts/setup-www-cloud.sh

destroy:
	@echo "Destroying AWS resources"
	./destroy.sh

# Localstack targets
# Default docker tagged image for Localstack EC2 container
AMI_ID ?= ami-df5de72bdb3b
# Default ports for web interface
PORTS ?= 80

# Deploy the Terraform stack on Localstack
local-deploy:
	@echo Setting up the security group for Localstack EC2 container
	for port in $(PORTS); do \
		lstk aws ec2 authorize-security-group-ingress \
			--group-id default \
			--protocol tcp \
			--port $$port \
			--cidr 0.0.0/0; \
	done

	@echo "Deploying on Localstack"
	lstk terraform -chdir=terraform/ apply -auto-approve -var="ami_id=$(AMI_ID)"

local-destroy:
	@echo "Destroying Localstack resources"
	lstk terraform -chdir=terraform/ destroy -auto-approve -var="ami_id=$(AMI_ID)"

	@echo Revoke security group ingress rules for Localstack EC2 container
	for port in $(PORTS); do \
		lstk aws ec2 revoke-security-group-ingress \
			--group-id default \
			--protocol tcp \
			--port $$port \
			--cidr 0.0.0.0/0; \
	done


local-web:
	@echo "Deploying Web Interface on Localstack"
	./scripts/setup-www-local.sh

local-test:
	@echo "Localstack Test"
	./scripts/localstack-smoke-test.sh
