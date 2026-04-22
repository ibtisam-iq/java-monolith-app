# Java Monolith Application

[![DevSecOps CI — Java Monolith](https://github.com/ibtisam-iq/java-monolith-app/actions/workflows/ci.yml/badge.svg)](https://github.com/ibtisam-iq/java-monolith-app/actions/workflows/ci.yml)

## Overview

This is a Java Spring Boot-based monolithic banking web application that I used as the base for practising and implementing real-world DevOps engineering — from codebase modernization and containerization to full CI/CD pipelines and production-grade deployments.

> I did not write this application from scratch. As a DevOps Engineer, my focus is on everything that happens **around the code** — building, securing, packaging, and operating it in production-like environments.

> Everything under `src/` and the original `pom.xml` structure belong to the original developer. Every other file in this repository — `Jenkinsfile`, `.github/workflows/ci.yml`, `Dockerfile`, `compose.yml`, `.dockerignore`, `.gitignore`, `.env.example`, and all `pom.xml` modernization — was written by me.

---

## Application Structure

```
java-monolith-app/
├── .github/
│   └── workflows/
│       └── ci.yml                      # GitHub Actions DevSecOps CI pipeline (14 stages)
├── src/
│   └── main/
│       ├── java/com/example/bankapp/   # Controllers, Services, Repositories
│       └── resources/
│           └── application.properties  # Reads from environment variables
├── Dockerfile                          # Multi-stage build: Maven builder → JRE runtime
├── Jenkinsfile                         # Jenkins declarative CI pipeline (14 stages)
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
| Database | MySQL (production) / H2 (local dev) |
| Web Server | Embedded Tomcat (port 8000) |
| Security | Spring Security |
| Build Tool | Maven (with Maven Wrapper) |
| Coverage | JaCoCo |
| Containerization | Docker (multi-stage) + Docker Compose |

---

## DevOps Implementation Journey

### Step 0 — Codebase Modernization (`pom.xml`)

Before doing any DevOps work, I audited and modernized `pom.xml` — upgrading to Spring Boot 3.4.4, Java 21 (LTS), fixing an invalid `groupId`, replacing the deprecated MySQL connector, adding H2 for local dev flexibility, and adding `spring-boot-starter-actuator` for Docker and Kubernetes health probes.

> I used AI-assisted analysis (Perplexity Pro) for this step. Full change log with rationale: [`docs/pom-modernization.md`](docs/pom-modernization.md)

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

### Step 2 — Local Build & Bare-Metal Validation

Before writing any Docker config, I validated the application locally on the host machine — native MySQL, native JVM, no containers. This confirmed the build was clean and the app connected to the database correctly before I introduced any containerization layer.

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
sudo systemctl status mysql
mysql -u your_db_user -p -e "SHOW DATABASES;" | grep IbtisamIQbankappdb
```

**Build the artifact:**

```bash
./mvnw clean package -DskipTests
```

Output artifact: `target/bankapp-0.0.1-SNAPSHOT.jar`

**Run the application:**

```bash
set -a && source .env && set +a && java -jar target/bankapp-0.0.1-SNAPSHOT.jar
```

> **Why `set -a`?** `set -a` marks every variable sourced from `.env` for automatic export into the child process (the JVM). `set +a` turns off the flag after sourcing so subsequent shell variables are not unintentionally exported.

> **Note:** Running `java -jar` without loading env vars first will throw:
> `PlaceholderResolutionException: Could not resolve placeholder 'SPRING_APPLICATION_NAME'`
>
> The `.jar.original` file (Maven pre-repackage output) has no main manifest — always use the primary `.jar`.

App runs at: `http://localhost:8000`

---

### Step 3 — Containerization (Docker)

With the application validated on bare metal, I wrote the `Dockerfile` and `compose.yml` from scratch. I read `pom.xml`, `application.properties`, and `.env.example` before writing a single line — to understand exactly what the image needed: Java version, JAR filename, exposed port, health endpoint, and environment variable strategy.

**Key decisions I made and documented:**

- Multi-stage build to keep the runtime image lean (~190MB vs ~600MB)
- Non-root user for CIS/Trivy compliance
- JVM container-awareness flags (`-XX:+UseContainerSupport`) to prevent OOM kills in Kubernetes
- Healthcheck timing tuned to Spring Boot's actual cold-start duration

The full rationale for every line is in [`docs/docker-setup.md`](docs/docker-setup.md).

#### Validating with Docker Compose

After writing the files, I validated them end-to-end using Docker Compose — spinning up both MySQL and the app as containers on a shared internal network, with no local MySQL installation needed.

```bash
cp .env.example .env
# Fill in: MYSQL_ROOT_PASSWORD, MYSQL_DATABASE, MYSQL_USER, MYSQL_PASSWORD, SERVER_PORT

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

---

### Step 4 — DevSecOps Pipelines (CI/CD)

With the application containerized and the registry strategy confirmed, I moved to automating the full build-test-scan-publish cycle. I ran the Jenkins pipeline against my own self-hosted CI/CD stack — Jenkins, SonarQube, and Nexus — provisioned and documented separately in [silver-stack](https://nectar.ibtisam-iq.com/operations/cicd-stack/self-hosted-jenkins-sonarqube-nexus/). The same 14 stages were then mirrored in GitHub Actions, giving both a self-hosted and a zero-infrastructure path through the identical pipeline.

**Pipeline stages (both implementations):**

| # | Stage | What it does |
|---|---|---|
| 1 | Checkout | Clone source at the correct ref |
| 2 | Trivy FS Scan | Scan source tree for secrets, misconfigs, and dependency CVEs before build |
| 3 | Versioning | Compute image tag: `<pom-version>-<short-sha>-<build-number>` |
| 4 | Build & Test | `mvn clean verify` — compile, unit test, JaCoCo coverage in one pass |
| 5 | SonarQube Analysis | Static analysis with blame info and JaCoCo XML coverage upload |
| 6 | Quality Gate | Block pipeline until SonarQube webhook fires back pass/fail |
| 7 | Publish JAR to Nexus | Deploy SNAPSHOT JAR to `maven-snapshots` repository |
| 8 | Docker Build | Multi-stage image built once, tagged for all three registries |
| 9 | Trivy Image Scan | Three passes: OS packages (warn), JAR CRITICALs (fail), full audit artifact |
| 10 | Push to Docker Hub | Push versioned tag + `latest` to `mibtisam/java-monolith` |
| 11 | Push to GHCR | Push to `ghcr.io/ibtisam-iq/java-monolith` |
| 12 | Push to Nexus Registry | Push to `nexus.ibtisam-iq.com/docker-hosted/java-monolith` |
| 13 | Push to AWS ECR | Planned — ready to enable once ECR repo is provisioned |
| 14 | Update CD Repo | Commit new image tag to `platform-engineering-systems` — GitOps handoff to ArgoCD |

The build fails hard on three conditions: Trivy finds CRITICAL CVEs in JAR dependencies, SonarQube Quality Gate does not pass, or any unit test fails.

#### Jenkins

The pipeline is defined in `Jenkinsfile` at the repo root using Jenkins declarative syntax, designed to run on any Jenkins instance without shared libraries or scripted blocks — just point a job at this repo. The non-obvious design decisions, stage-level rationale, and every problem I hit while building it are documented in [`docs/understand-jenkinsfile.md`](docs/understand-jenkinsfile.md).

#### GitHub Actions

The same pipeline runs in `.github/workflows/ci.yml` on GitHub-hosted runners — no server provisioning needed. It triggers on push and pull request to `main`, with path filters so documentation-only changes do not trigger a build. The Trivy scan strategy and why the filesystem and image scan gates are configured differently are explained in [`docs/trivy-troubleshooting.md`](docs/trivy-troubleshooting.md). SonarQube Quality Gate wiring specifics are in [`docs/sonarqube-troubleshooting.md`](docs/sonarqube-troubleshooting.md).

#### Built Docker Images

```text
ibtisam@dev-machine:~ $ docker images
IMAGE                                                     ID             DISK USAGE   CONTENT SIZE
ghcr.io/ibtisam-iq/java-monolith:latest                   88a727976b14        621MB          186MB
mibtisam/java-monolith:latest                             88a727976b14        621MB          186MB
nexus.ibtisam-iq.com/docker-hosted/java-monolith:latest   88a727976b14        621MB          186MB
```

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
| **This repo** | Application source code + all CI/CD pipeline definitions (Jenkins, GitHub Actions) |
| **[Platform Engineering Systems](https://github.com/ibtisam-iq/platform-engineering-systems)** | Platform — deploys, operates, and scales the artifact across multiple targets |

This separation is intentional: pipeline logic lives with the code it builds, and deployment configs stay independently versioned in their own repo.
