# Multi-VPC Peering Demo

A small Terraform networking demo that models a **hub-and-spoke VPC peering architecture** using LocalStack.

The project creates three isolated VPCs:

* `shared` acts as the hub.
* `app` peers with `shared`.
* `data` peers with `shared`.
* `app` and `data` have no direct route to each other.

## Architecture

```text
              shared
              /    \
             /      \
           app      data
```

Traffic between `app` and `data` is intentionally not routed through `shared`. Each VPC has explicit private routes only to its configured peering connection.

## Project Structure

```text
.
├── Makefile
├── main.tf
├── locals.tf
├── variables.tf
├── outputs.tf
└── scripts/
    └── inspect.sh
```

### Key Files

| File                 | Description                                       |
| -------------------- | ------------------------------------------------- |
| `Makefile`           | Terraform and network inspection commands         |
| `main.tf`            | VPCs, peering connections, subnets, and routes    |
| `locals.tf`          | VPC CIDR configuration                            |
| `variables.tf`       | Terraform configuration inputs                    |
| `outputs.tf`         | VPC and peering connection IDs                    |
| `scripts/inspect.sh` | Displays deployed VPC, peering, and route details |

## Local Development

### Prerequisites

The following tools are required:

* LocalStack
* `lstk` CLI wrapper
* Terraform

### Deploy the Network

Run the following commands from the project directory:

```bash
make init
make plan
make apply
```

### Inspect the Network

After applying the Terraform configuration:

```bash
make inspect
```

This displays the deployed:

* VPCs
* VPC peering connections
* Route tables
* Private routes

### Destroy the Network

To remove the deployed resources:

```bash
make destroy
```

## Network Design

The demo uses explicit private routing to enforce network segmentation.

| VPC      | Peered With   | Directly Routable To |
| -------- | ------------- | -------------------- |
| `shared` | `app`, `data` | `app`, `data`        |
| `app`    | `shared`      | `shared`             |
| `data`   | `shared`      | `shared`             |

There is **no direct peering or route between `app` and `data`**.

```text
app ───────► shared ◄─────── data

app ──X───── data
```

## What This Demo Covers

This project provides a practical example of:

* VPC CIDR planning
* VPC peering
* Route table configuration
* Private network routing
* DNS settings
* Network segmentation
* Hub-and-spoke network design

It is intended as a small, reproducible environment for practicing AWS networking concepts locally with Terraform and LocalStack.
