# Java Monolith Application

## Overview

This is a Java Spring Boot-based monolithic banking web application serving as the **source codebase** for two downstream DevOps projects:

- **[DevSecOps Pipelines](https://github.com/ibtisam-iq/devsecops-pipelines)** — CI/CD pipelines that build, scan, and package this application into a secure, deployable artifact using Jenkins, GitHub Actions, Docker, SonarQube, and Trivy.
- **[Platform Engineering Systems](https://github.com/ibtisam-iq/platform-engineering-systems)** — Deployment workflows that run this artifact across Docker Compose, AWS EC2, EKS (Kubernetes), Terraform, and GitOps-based delivery.

> I did not write this application from scratch. As a DevOps Engineer, my focus is on everything that happens **around the code** — building, securing, packaging, and operating it in production-like environments. The files I added to this repository are: `Dockerfile`, `compose.yml`, `.dockerignore`, and `.gitignore`. Everything else under `src/` belongs to the original developer.

---

## Application Structure

```
java-monolith-app/
├── src/
│   └── main/
│       ├── java/com/example/bankapp/   # Controllers, Services, Repositories
│       └── resources/
│           └── application.properties  # Reads from environment variables
├── Dockerfile                          # Multi-stage build: Maven builder → JRE runtime
├── compose.yml                         # Local containerized environment (app + MySQL)
├── .dockerignore                       # Excludes target/, .env, IDE files from build context
├── .gitignore                          # Excludes .env, target/, IDE files from version control
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
| Containerization | Docker (multi-stage) + Docker Compose |

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
| Added | — | `spring-boot-starter-actuator` | Provides `/actuator/health` endpoint required for Kubernetes liveness/readiness probes and Docker healthchecks |
| Added | — | `spring-boot-starter-validation` | Jakarta Bean Validation — necessary for any production-grade input handling |
| SCM / Developer / License | Empty blocks | Filled with project details | Professional standard; visible to anyone who inspects the artifact |

---

### Step 1 — Environment Standardization

The original codebase had hardcoded database credentials and app config. I refactored it to use environment variables, making the application portable across all environments — bare-metal, Docker, and Kubernetes alike.

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

### Step 2 — Local Build & Containerized Validation

Before building any pipeline, I validated the full application lifecycle using two methods: **bare-metal execution** directly on the host machine, and **containerized execution** via Docker Compose. Both are local environments — the distinction is whether MySQL and the JVM run natively on the OS or inside isolated containers.

#### Method 1 — Bare-Metal (Native Execution)

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

#### Method 2 — Containerized (Docker Compose)

Docker Compose spins up both the MySQL database and the Spring Boot application as isolated containers on a shared internal network — no local MySQL installation required.

**Prerequisites:** Docker and Docker Compose must be installed. The `.env` file must exist (copy from `.env.example` if not already done).

```bash
cp .env.example .env
# Fill in values: MYSQL_ROOT_PASSWORD, MYSQL_DATABASE, MYSQL_USER, MYSQL_PASSWORD, SERVER_PORT
```

**Start the full stack:**

```bash
docker compose up --build
```

> `--build` forces the Docker image to be rebuilt from the `Dockerfile`. Omit it on subsequent runs if the source code has not changed.

**What happens in sequence:**
1. Docker builds the `java-monolith-bankapp` image using the multi-stage `Dockerfile`
2. The `db` container (MySQL 8.4) starts and runs its healthcheck (`mysqladmin ping -h localhost`)
3. The `web` container waits for the `db` healthcheck to pass (`condition: service_healthy`)
4. Spring Boot connects to MySQL using the service name `db` as the hostname (overrides `localhost` from `.env`)
5. The app becomes available at `http://localhost:8000`

**Stop and clean up:**

```bash
# Stop containers but keep the database volume
docker compose down

# Stop containers AND delete the database volume (full reset)
docker compose down -v
```

> See [`docs/docker-setup.md`](docs/docker-setup.md) for a complete explanation of every decision in the `Dockerfile` and `compose.yml` — including layer caching strategy, JVM container flags, healthcheck design, and the `env_file` vs `environment:` override pattern.

---

### Step 3 — Containerization (Docker)

Before moving to automated pipelines, I packaged the application as a production-grade Docker image. I wrote the `Dockerfile` and `compose.yml` from scratch after reading the project code — `pom.xml`, `application.properties`, and `.env.example` — to understand exactly what the image needed: Java version, JAR filename, port, health endpoint, and environment variable strategy.

Key decisions I made and documented: multi-stage build to keep the runtime image lean (~165MB vs ~500MB), non-root user for CIS/Trivy compliance, JVM container-awareness flags (`-XX:+UseContainerSupport`) to prevent OOM kills in Kubernetes, and healthcheck timing tuned to Spring Boot's actual cold-start duration.

The full rationale for every line is in [`docs/docker-setup.md`](docs/docker-setup.md).

---

### Step 4 — DevSecOps Pipelines (CI/CD)

With the application validated both natively and in containers, I built automated pipelines to transform this code into a secure, deployable artifact.

Pipelines include: Maven build → SonarQube analysis → Trivy vulnerability scan → Docker image build → Nexus artifact management → Jenkins & GitHub Actions automation.

👉 **Pipelines repository:** [DevSecOps Pipelines](https://github.com/ibtisam-iq/devsecops-pipelines/tree/main/pipelines/java-monolith)

---

### Step 5 — Platform Engineering (Deployment & Operations)

Once the artifact was ready, I deployed it using multiple industry-standard approaches.

Deployment targets: Local JAR · Docker Compose · AWS EC2 · EKS (Kubernetes) · Terraform-provisioned infrastructure.

Also covered: monitoring, observability, scaling strategies, and system reliability.

👉 **Platform repository:** [Platform Engineering Systems](https://github.com/ibtisam-iq/platform-engineering-systems/tree/main/systems/java-monolith)

---

## Key Idea

> Code = Input. Pipelines secure it. Infrastructure runs it.

| Repository | Role |
|---|---|
| **This repo** | Application source code — the single input to everything below |
| **[DevSecOps Pipelines](https://github.com/ibtisam-iq/devsecops-pipelines)** | CI/CD — builds, scans, and packages the code into a deployable artifact |
| **[Platform Engineering Systems](https://github.com/ibtisam-iq/platform-engineering-systems)** | Platform — deploys, operates, and scales the artifact across multiple targets |

This separation is intentional: one repo per concern. The source code stays clean, the pipeline logic stays auditable, and the deployment configs stay independently versioned.
