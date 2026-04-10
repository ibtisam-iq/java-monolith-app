# Java Monolith Application

## Overview

This is a Java-based monolithic banking web application used as the **source codebase** for building real-world DevSecOps pipelines and platform engineering workflows.

I did not build this application from scratch. As a DevOps Engineer, my focus is on everything that happens **around the code** — building, securing, packaging, and running it in production-like environments using industry-standard tooling.

---

## Application Structure

```
java-monolith-app/
├── src/
│   └── main/
│       ├── java/com/example/bankapp/   # Controllers, Services, Repositories
│       └── resources/
│           └── application.properties  # Reads from environment variables
├── .env.example                        # Environment variable template
├── pom.xml                             # Maven build config (Spring Boot 3.4.4, Java 21)
└── mvnw                                # Maven wrapper
```

Three-tier architecture: Presentation (Controllers/Thymeleaf UI) → Business (Service layer) → Data (JPA + MySQL).

---

## Technology Stack

| Layer | Technology |
|---|---|
| Language | Java 21 |
| Framework | Spring Boot 3.4.4 |
| Persistence | Spring Data JPA + Hibernate |
| Database | MySQL |
| Web Server | Embedded Tomcat (port 8000) |
| Security | Spring Security |
| Build Tool | Maven (with Maven Wrapper) |
| Coverage | JaCoCo |

---

## DevOps Implementation Journey

### Step 1 — Environment Standardization

The original codebase had hardcoded database credentials and app config. I refactored it to use environment variables, making it portable across all environments.

```bash
# Copy the template and fill in real values
cp .env.example .env
```

Key variables set in `.env`:

```env
SPRING_APPLICATION_NAME=IbtisamIQBankApp
MYSQL_DATABASE=IbtisamIQbankappdb
MYSQL_USER=your_db_user
MYSQL_PASSWORD=your_db_password
SPRING_DATASOURCE_URL=jdbc:mysql://localhost:3306/IbtisamIQbankappdb?useSSL=false&serverTimezone=UTC&allowPublicKeyRetrieval=true
SERVER_PORT=8000
```

---

### Step 2 — Local Build & Validation

Before building any pipeline, I validated the full application lifecycle locally.

**Install and configure MySQL:**

```bash
sudo apt update && sudo apt install -y mysql-server
sudo systemctl start mysql
sudo systemctl enable mysql

# Secure and create DB user
sudo mysql -u root -p
```

```sql
CREATE DATABASE IbtisamIQbankappdb;
CREATE USER 'your_db_user'@'localhost' IDENTIFIED BY 'your_db_password';
GRANT ALL PRIVILEGES ON IbtisamIQbankappdb.* TO 'your_db_user'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

**Load environment variables and build the artifact:**

```bash
# Export all vars from .env into the current shell
export $(grep -v '^#' .env | xargs)

# Build the JAR (skip tests for speed)
./mvnw clean package -DskipTests
```

Output artifact: `target/bankapp-0.0.1-SNAPSHOT.jar`

**Run the application:**

```bash
# Environment must be exported first — the app reads vars at startup
export $(grep -v '^#' .env | xargs)

java -jar target/bankapp-0.0.1-SNAPSHOT.jar
```

> **Note:** Running `java -jar` without exporting env vars first will throw:
> `PlaceholderResolutionException: Could not resolve placeholder 'SPRING_APPLICATION_NAME'`
>
> The `.jar.original` file (Maven pre-repackage output) has no main manifest — always use the primary `.jar`.

App runs at: `http://localhost:8000`

---

### Step 3 — DevSecOps Pipelines (CI/CD)

With the application validated locally, I built automated pipelines to transform this code into a secure, deployable artifact.

Pipelines include: Maven build → SonarQube analysis → Trivy vulnerability scan → Docker image build → Nexus artifact management → Jenkins & GitHub Actions automation.

👉 **Pipelines repository:** [ibtisam-iq/DevSecOps-Pipelines](https://github.com/ibtisam-iq/DevSecOps-Pipelines)

---

### Step 4 — Platform Engineering (Deployment & Operations)

Once the artifact was ready, I deployed it using multiple industry-standard approaches.

Deployment targets: Local JAR · Docker Compose · AWS EC2 · EKS (Kubernetes) · Terraform-provisioned infrastructure.

Also covered: monitoring, observability, scaling strategies, and system reliability.

👉 **Platform repository:** [ibtisam-iq/Platform-Engineering-Systems](https://github.com/ibtisam-iq/Platform-Engineering-Systems)

---

## Repository Role in the Larger System

```
java-monolith-app  ←  Single source of truth (codebase only)
        │
        ├── git submodule → DevSecOps-Pipelines     (CI/CD)
        └── git submodule → Platform-Engineering-Systems  (Deployment)
```

This repository holds only the application code. All DevOps work — pipelines, deployment configs, and infrastructure — lives in the downstream repositories and references this one via Git submodules.

---

## Key Idea

> Code = Input. Everything else is built around it.

The goal is not to showcase application development. The goal is to demonstrate how **any application** can be taken as input and transformed into a production-like system using DevSecOps and platform engineering practices.
