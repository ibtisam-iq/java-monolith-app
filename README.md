# Java Three-Tier Monolithic Application — Multi-Environment Deployment

## Overview

This project is a Java-based three-tier application integrated with MySQL, used as a base system to demonstrate how the same application can be deployed across multiple environments.

> The focus is not on application development, but on how a real system behaves when deployed using different infrastructure and DevOps approaches.

---

## Problem Statement

How can a single application be deployed consistently across different environments such as local systems, containers, virtual machines, and Kubernetes?

What changes in setup, complexity, and operational handling when the infrastructure changes?

---

## Base Application

The underlying system is a standard three-tier architecture:

* Presentation Layer
* Application Layer (Java / Spring Boot)
* Data Layer (MySQL)

The application supports basic operations like account management and transactions, which are common in banking-style systems ([DEV Community][1]).

This application remains unchanged across all deployments.

---

## Tech Stack

* Java (Spring Boot)
* MySQL
* Maven
* REST APIs

---

## Project Structure

```
.
├── src/                # Application source code
├── resources/          # Config files
├── docker/             # Dockerfiles
├── compose/            # Docker Compose
├── terraform/          # AWS Infrastructure
├── k8s/                # Kubernetes manifests
├── docs/               # Deployment guides
└── README.md
```

---

## Deployment Environments

This project demonstrates deployment across multiple environments:

1. Local (Direct execution)
2. Docker (Containerized deployment)
3. Docker Compose (Multi-service setup)
4. EC2 + Auto Scaling + Load Balancer
5. ECS Fargate (Serverless containers)
6. EKS (Kubernetes)

Each deployment is implemented and documented separately.

---

## Key Focus

* Practical deployment workflows
* Infrastructure setup across environments
* Containerization and orchestration
* Understanding how deployment changes system behavior

---

## Why This Project

This project shows:

* How to **run the same application everywhere**
* How to **adapt infrastructure**
* How to **handle deployments in real-world scenarios**

---

## Documentation

Detailed guides are available in the `docs/` directory:

* docs/local.md
* docs/docker.md
* docs/docker-compose.md
* docs/ec2.md
* docs/fargate.md
* docs/eks.md

---

## Future Improvements

* CI/CD pipelines (Jenkins, GitHub Actions)
* Monitoring (Prometheus, Grafana)
* Logging (ELK stack)
* Secrets management

---

## Author

Muhammad Ibtisam Iqbal
DevOps Engineer | Cloud Infrastructure | Kubernetes (CKA, CKAD)
