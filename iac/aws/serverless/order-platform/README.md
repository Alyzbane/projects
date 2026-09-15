# Event-Driven Serverless Order Platform

A small event-driven order processing API built with AWS serverless services and tested locally using [LocalStack](https://www.localstack.cloud/).

The API uses API Gateway to receive orders, Lambda to process requests, SQS for asynchronous background processing, and DynamoDB for order persistence.

## Architecture

```text
Client
  │
  ▼
API Gateway (HTTP API)
  │
  ▼
Producer Lambda
  │
  ├───► DynamoDB (orders)
  │
  ▼
SQS Order Queue
  │
  ▼
Worker Lambda
  │
  ▼
COMPLETED

SQS Order Queue
  │
  ▼
Dead-Letter Queue (DLQ)
  │
  ▼
DLQ Reconciler
  │
  ▼
FAILED_PROCESSING
```

## Project Structure

```text
.
├── Makefile
├── scripts/
│   └── smoke.sh
│
├── src/
│   ├── producer/
│   │   └── handler.py
│   ├── worker/
│   │   └── handler.py
│   └── dlq_reconciler/
│       └── handler.py
│
└── terraform/
    ├── providers.tf
    ├── variables.tf
    ├── locals.tf
    ├── main.tf
    ├── monitoring.tf
    └── outputs.tf
```

### Key Files

| File                            | Description                               |
| ------------------------------- | ----------------------------------------- |
| `Makefile`                      | Terraform and smoke-test commands         |
| `scripts/smoke.sh`              | LocalStack end-to-end test                |
| `src/producer/handler.py`       | API request handler                       |
| `src/worker/handler.py`         | SQS message consumer                      |
| `src/dlq_reconciler/handler.py` | Failed-message consumer                   |
| `terraform/providers.tf`        | AWS and LocalStack provider configuration |
| `terraform/variables.tf`        | Configuration inputs                      |
| `terraform/locals.tf`           | Derived Terraform values                  |
| `terraform/main.tf`             | Application infrastructure                |
| `terraform/monitoring.tf`       | Logs, alarms, and dashboard               |
| `terraform/outputs.tf`          | URLs and resource names                   |

## Local Development

### Prerequisites

The following tools are required:

* Terraform
* LocalStack
* `curl`
* `jq`

### Deploy Locally

Run the following commands from the project directory:

```bash
make init
make plan
make apply
```

### Run the Smoke Test

After deploying the infrastructure:

```bash
make smoke
```

The `make smoke` target runs the end-to-end test against LocalStack.

LocalStack Cognito and API Gateway use:

```text
localhost.localstack.cloud:4566
```

### Destroy the Local Environment

To remove the deployed infrastructure:

```bash
make destroy
```

## API

The API exposes the following endpoints:

| Method   | Endpoint             | Description     |
| -------- | -------------------- | --------------- |
| `POST`   | `/orders`            | Create an order |
| `GET`    | `/orders`            | List orders     |
| `GET`    | `/orders/{order_id}` | Get an order    |
| `DELETE` | `/orders/{order_id}` | Delete an order |

### Order Processing

Order writes are asynchronous.

When an order is created, it initially has the status:

```text
PENDING
```

The order is then processed asynchronously by the worker Lambda and eventually reaches one of the following states:

```text
PENDING
   │
   ├──► COMPLETED
   │
   └──► FAILED_PROCESSING
```

`COMPLETED` indicates successful processing.

`FAILED_PROCESSING` indicates that processing failed and the message was handled by the DLQ reconciliation flow.

## AWS Deployment

The LocalStack smoke test is intended for local development.

For a real AWS deployment, use the AWS-specific smoke test:

```bash
make smoke-aws
```

## LocalStack Requirements

Some features used by this project may require a LocalStack subscription.

These include:

* Cognito
* JWT authorization
* CloudFront
* WAF

If required by the configured LocalStack features, set the following environment variable:

```bash
export LOCALSTACK_AUTH_TOKEN=<your-token>
```