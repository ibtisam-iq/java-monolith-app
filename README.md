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

### Step 0 — Codebase Modernization (`pom.xml`)

The inherited codebase was functional but built on outdated dependencies. Before doing any DevOps work, I audited and modernized `pom.xml` to bring it up to current industry standards — because running pipelines on stale, vulnerable dependencies defeats the purpose of DevSecOps.

> **Note:** Modernizing `pom.xml` is not my primary role as a DevOps Engineer. However, receiving a codebase that cannot build cleanly on current tooling is a real-world scenario. I used **AI-assisted analysis (Perplexity Pro)** to audit the dependency tree, identify outdated and deprecated artifacts, and apply the correct fixes — which is itself a practical DevOps skill: knowing what to fix, and knowing when to use the right tool to fix it efficiently.

**Changes made:**

| What | Before | After | Why |
|---|---|---|---|
| Spring Boot | `3.3.3` | `3.4.4` | 3.3.x reached end of OSS support; 3.4.x has security patches and Java 21 improvements |
| Java version | `17` | `21` | Java 21 is the current LTS (supported until 2028); virtual threads, record patterns |
| `groupId` | `com.ibtisam-iq` | `com.ibtisamiq` | Hyphens are invalid in Maven `groupId` — violates Maven naming convention |
| MySQL connector | `mysql:mysql-connector-java:8.0.33` | `com.mysql:mysql-connector-j` (BOM-managed) | Old artifact is deprecated; new groupId is `com.mysql`, version managed by Spring Boot BOM |
| JaCoCo | `0.8.7` (2021) + duplicate declaration | `0.8.12`, single declaration in `<plugins>` only | Updated to latest; removed erroneous duplicate entry in `<dependencies>` |
| Added | — | `spring-boot-starter-actuator` | Provides `/actuator/health` endpoint required for Kubernetes liveness/readiness probes |
| Added | — | `spring-boot-starter-validation` | Jakarta Bean Validation — necessary for any production-grade input handling |
| SCM / Developer / License | Empty blocks | Filled with project details | Professional standard; visible to anyone who inspects the artifact |

---

### Step 1 — Environment Standardization

The original codebase had hardcoded database credentials and app config. I refactored it to use environment variables, making it portable across all environments.

```bash
# Copy the template and fill in real values
cp .env.example .env
```

Key variables set in `.env`:

```env
SPRING_APPLICATION_NAME=IbtisamIQBankApp
SPRING_DATASOURCE_USERNAME=your_db_user
SPRING_DATASOURCE_PASSWORD=your_db_password
SPRING_DATASOURCE_URL="jdbc:mysql://localhost:3306/IbtisamIQbankappdb?useSSL=false&serverTimezone=UTC&allowPublicKeyRetrieval=true"
SERVER_PORT=8000
```

> **Note:** `SPRING_DATASOURCE_URL` must be wrapped in **double quotes** in the `.env` file. The `&` character in the query string is a shell special character (background process operator) — without quotes, the shell will truncate the URL at the first `&`, causing a datasource connection failure.

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

**Verify MySQL is running and the database exists:**

```bash
# Check MySQL is running
sudo systemctl status mysql

# Confirm the database exists
mysql -u your_db_user -p -e "SHOW DATABASES;" | grep IbtisamIQbankappdb
```

**Build the artifact:**

```bash
# Build the JAR (skip tests for speed)
./mvnw clean package -DskipTests
```

Output artifact: `target/bankapp-0.0.1-SNAPSHOT.jar`

**Run the application:**

```bash
# Load env vars and run — all in one command
set -a && source .env && set +a && java -jar target/bankapp-0.0.1-SNAPSHOT.jar
```

> **Why `set -a`?** `set -a` marks every variable sourced from `.env` for automatic export into the child process (the JVM). `set +a` turns off the flag after sourcing so subsequent shell variables are not unintentionally exported.

> **Note:** Running `java -jar` without loading env vars first will throw:
> `PlaceholderResolutionException: Could not resolve placeholder 'SPRING_APPLICATION_NAME'`
>
> The `.jar.original` file (Maven pre-repackage output) has no main manifest — always use the primary `.jar`.

App runs at: `http://localhost:8000`

---

### Step 3 — DevSecOps Pipelines (CI/CD)

With the application validated locally, I built automated pipelines to transform this code into a secure, deployable artifact.

Pipelines include: Maven build → SonarQube analysis → Trivy vulnerability scan → Docker image build → Nexus artifact management → Jenkins & GitHub Actions automation.

👉 **Pipelines repository:** [DevSecOps Pipelines](https://github.com/ibtisam-iq/devsecops-pipelines/tree/main/pipelines/java-monolith)

---

### Step 4 — Platform Engineering (Deployment & Operations)

Once the artifact was ready, I deployed it using multiple industry-standard approaches.

Deployment targets: Local JAR · Docker Compose · AWS EC2 · EKS (Kubernetes) · Terraform-provisioned infrastructure.

Also covered: monitoring, observability, scaling strategies, and system reliability.

👉 **Platform repository:** [Platform Engineering Systems](https://github.com/ibtisam-iq/platform-engineering-systems/tree/main/systems/java-monolith)

---

## Repository Role in the Larger System

```
java-monolith-app  ←  Single source of truth (codebase only)
        │
        ├── git submodule → DevSecOps Pipelines     (CI/CD)
        └── git submodule → Platform Engineering Systems  (Deployment)
```

This repository holds only the application code. All DevOps work — pipelines, deployment configs, and infrastructure — lives in the downstream repositories and references this one via Git submodules.

---

## Key Idea

> Code = Input. Everything else is built around it.

The goal is not to showcase application development. The goal is to demonstrate how **any application** can be taken as input and transformed into a production-like system using DevSecOps and platform engineering practices.
