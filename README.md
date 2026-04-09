# Java Monolith Application

## Overview

This is a Java-based monolithic application that I use as a base system to build and demonstrate real DevSecOps pipelines and platform engineering workflows.

I did not build this application from scratch. Instead, I use it to focus on what happens **around the code** — building, securing, packaging, and running it in real environments.

---

## Application Structure

The application follows a three-tier structure:

- Presentation Layer → Controllers / UI
- Business Layer → Service logic
- Data Layer → Database interaction

All components are packaged into a single deployable unit (monolith).

---

## Technology Stack

- Java 21
- Spring Boot
- Spring Data JPA
- MySQL
- Embedded Tomcat

---

## Runtime Behavior

The application runs as a standalone JAR and starts an embedded web server on port 8000.

It connects to a MySQL database and automatically creates required tables at startup. 

---

## Implementation Journey

This repository represents the starting point of a larger system. I used this application to build and validate real-world DevSecOps and platform engineering workflows.

---

### 1. Environment Standardization

The original application contained hardcoded configuration values.

I refactored the configuration to use environment variables, making it portable and deployment-ready.

- Replaced hardcoded database and application settings
- Introduced environment-based configuration via `.env`
- Added `.env.example` for reproducibility

This step ensures the application can run consistently across different environments.

---

### 2. Local Execution & Validation

Before building any pipelines, I validated the application locally.

I:

- Installed and configured MySQL
- Created and connected the database
- Ran the application as a JAR
- Verified end-to-end functionality

This step ensured the system works correctly before automation.

---

### 3. DevSecOps Pipelines (CI/CD)

After validation, I built pipelines to transform this code into a secure, deployable artifact.

In these pipelines, I:

- Built the application using Maven
- Performed code quality analysis using SonarQube
- Scanned for vulnerabilities using Trivy
- Packaged the application into a Docker image
- Managed artifacts using Nexus
- Automated workflows using Jenkins and GitHub Actions

👉 Pipelines repository:
https://github.com/ibtisam-iq/devsecops-pipelines

---

### 4. Platform Engineering (Deployment & Operations)

Once the artifact was ready, I deployed and operated the system using multiple approaches.

I implemented:

- Local deployment (JAR + MySQL)
- Docker and Docker Compose
- AWS EC2 with Auto Scaling
- Kubernetes deployment using EKS
- Infrastructure provisioning using Terraform

I also explored:

- Monitoring and observability
- Scaling strategies
- System reliability and recovery

👉 Platform repository:
https://github.com/ibtisam-iq/platform-engineering-systems

---

## Key Idea

This repository represents:

> Code → Input

Everything else (CI/CD, security, deployment, scaling) is built **around it**.

---

## Note

The goal is not to showcase application development.

The goal is to demonstrate:

- How any application can be taken as input
- And transformed into a production-like system using DevSecOps and platform engineering practices
