# Java Monolith Application

<!-- CI/CD Status -->
[![DevSecOps CI](https://github.com/ibtisam-iq/java-monolith-app/actions/workflows/ci.yml/badge.svg)](https://github.com/ibtisam-iq/java-monolith-app/actions/workflows/ci.yml)
[![Docker Hub](https://img.shields.io/docker/pulls/mibtisam/java-monolith?logo=docker&label=Docker%20Hub&logoColor=white)](https://hub.docker.com/r/mibtisam/java-monolith)
[![GHCR](https://img.shields.io/badge/GHCR-Available-brightgreen?logo=github&logoColor=white)](https://github.com/ibtisam-iq/java-monolith-app/pkgs/container/java-monolith)

<!-- Stack -->
[![Spring Boot](https://img.shields.io/badge/Spring%20Boot-3.4.5-6DB33F?logo=springboot&logoColor=white)](pom.xml)
[![Java](https://img.shields.io/badge/Java-21%20LTS-ED8B00?logo=openjdk&logoColor=white)](pom.xml)
[![Jenkins](https://img.shields.io/badge/Jenkins-Declarative%20Pipeline-D24939?logo=jenkins&logoColor=white)](Jenkinsfile)
[![Trivy](https://img.shields.io/badge/Trivy-CVE%20Scanned-1904DA?logo=aquasecurity&logoColor=white)](docs/trivy-troubleshooting.md)
[![SonarQube](https://img.shields.io/badge/SonarQube-Quality%20Gate-4E9BCD?logo=sonarqube&logoColor=white)](docs/sonarqube-troubleshooting.md)
[![Nexus](https://img.shields.io/badge/Nexus-Artifact%20Registry-1B9640?logo=sonatype&logoColor=white)](https://nexus.ibtisam-iq.com)

## Overview

This is a Java Spring Boot-based monolithic banking web application that I used as the base for practising and implementing real-world DevSecOps engineering (from codebase modernization and containerization to full CI/CD pipelines and production-grade deployments).

> [!NOTE]
> I did not write this application from scratch. As a DevOps Engineer, my focus is on everything that happens **around the code**. This includes building, securing, packaging, and operating the application in production-like environments.
> 
> Everything under `src/` and the original `pom.xml` structure belong to the original developer. Every other file in this repository (`Jenkinsfile`, `.github/workflows/ci.yml`, `Dockerfile`, `compose.yml`, `.dockerignore`, `.gitignore`, `.env.example`, and all `pom.xml` modernization) was written by me.

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
├── Dockerfile                          # Multi-stage build (Maven builder to JRE runtime)
├── Jenkinsfile                         # Jenkins declarative CI pipeline (14 stages)
├── compose.yml                         # Local containerized environment (app and MySQL)
├── .dockerignore                       # Excludes target/, .env, IDE files from build context
├── .gitignore                          # Excludes .env, target/, IDE files from version control
├── .env.example                        # Environment variable template
├── pom.xml                             # Maven build config (Spring Boot 3.4.5, Java 21)
└── mvnw                                # Maven wrapper
```

Three-tier architecture: Presentation (Controllers/Thymeleaf UI) to Business (Service layer) to Data (JPA and MySQL).

---

## Technology Stack

| Layer | Technology |
|---|---|
| Language | Java 21 |
| Framework | Spring Boot 3.4.5 |
| Persistence | Spring Data JPA and Hibernate |
| Database | MySQL (production) / H2 (local dev) |
| Web Server | Embedded Tomcat (port 8000) |
| Security | Spring Security |
| Build Tool | Maven (with Maven Wrapper) |
| Coverage | JaCoCo |
| Containerization | Docker (multi-stage) and Docker Compose |

---

## DevOps Implementation Journey

### Step 0: Codebase Modernization (`pom.xml`)

Before doing any DevOps work, I audited and modernized `pom.xml`. This involved upgrading to Spring Boot 3.4.5, Java 21 (LTS), fixing an invalid `groupId`, replacing the deprecated MySQL connector, adding H2 for local dev flexibility, and adding `spring-boot-starter-actuator` for Docker and Kubernetes health probes.

> [!NOTE]
> I used AI-assisted analysis (Perplexity Pro) for this step. Full change log with rationale: [`docs/pom-modernization.md`](docs/pom-modernization.md)

> During the AWS EC2 bare-metal deployment, two ALB-related issues were encountered and resolved — a health check failure caused by Spring Security blocking `/actuator/health`, and an HTTPS login redirect loop caused by SSL termination at the ALB layer. Full diagnosis and fixes: [`docs/alb-troubleshooting.md`](docs/alb-troubleshooting.md)

---

### Step 1: Environment Standardization

The original codebase had hardcoded database credentials and app config. I refactored it to use environment variables, making the application portable across all environments (bare-metal, Docker, and Kubernetes).

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

> [!IMPORTANT]
> `SPRING_DATASOURCE_URL` must be wrapped in **double quotes** in the `.env` file. The `&` character in the query string is a shell special character (background process operator). Without quotes, the shell will truncate the URL at the first `&`, causing a datasource connection failure.

---

### Step 2: Local Build & Bare-Metal Validation

Before writing any Docker config, I validated the application locally on the host machine using native MySQL and a native JVM (no containers). This confirmed the build was clean and the app connected to the database correctly before I introduced any containerization layer.

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

> [!TIP]
> **Why `set -a`?** `set -a` marks every variable sourced from `.env` for automatic export into the child process (the JVM). `set +a` turns off the flag after sourcing so subsequent shell variables are not unintentionally exported.

> [!WARNING]
> Running `java -jar` without loading env vars first will throw `PlaceholderResolutionException`. The `.jar.original` file (Maven pre-repackage output) has no main manifest. Always use the primary `.jar`.

App runs at: `http://localhost:8000`

---

### Step 3: Containerization (Docker)

With the application validated on bare metal, I wrote the `Dockerfile` and `compose.yml` from scratch. I read `pom.xml`, `application.properties`, and `.env.example` before writing a single line. This was to understand exactly what the image needed: Java version, JAR filename, exposed port, health endpoint, and environment variable strategy.

**Key decisions I made and documented:**

- Multi-stage build to keep the runtime image lean (~186MB vs ~500MB+)
- Non-root user for CIS/Trivy compliance
- JVM container-awareness flags (`-XX:+UseContainerSupport`) to prevent OOM kills in Kubernetes
- Healthcheck timing tuned to Spring Boot's actual cold-start duration

The full rationale for every line is in [`docs/docker-setup.md`](docs/docker-setup.md).

#### Validating with Docker Compose

After writing the files, I validated them end-to-end using Docker Compose by spinning up both MySQL and the app as containers on a shared internal network (no local MySQL installation needed).

```bash
cp .env.example .env
# Fill in: MYSQL_ROOT_PASSWORD, MYSQL_DATABASE, MYSQL_USER, MYSQL_PASSWORD, SERVER_PORT

docker compose up --build
```

> [!NOTE]
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

### Step 4: DevSecOps Pipelines (CI/CD)

With the application containerized and the registry strategy confirmed, I moved to automating the full build-test-scan-publish cycle. I ran the Jenkins pipeline against my own self-hosted CI/CD stack (Jenkins, SonarQube, and Nexus) provisioned and documented at [nectar.ibtisam-iq.com](https://nectar.ibtisam-iq.com/operations/cicd-stack/self-hosted-jenkins-sonarqube-nexus/). The same 14 stages were then mirrored in GitHub Actions, giving both a self-hosted and a zero-infrastructure path through the identical pipeline.

**Pipeline stages (both implementations):**

| # | Stage | What it does |
|---|---|---|
| 1 | Checkout | Clone source at the correct ref |
| 2 | Trivy FS Scan | Scan source tree for secrets, misconfigs, and dependency CVEs before build |
| 3 | Versioning | Compute image tag: `<pom-version>-<short-sha>-<build-number>` |
| 4 | Build & Test | `mvn clean verify` (compile, unit test, JaCoCo coverage in one pass) |
| 5 | SonarQube Analysis | Static analysis with blame info and JaCoCo XML coverage upload |
| 6 | Quality Gate | Block pipeline until SonarQube webhook fires back pass/fail |
| 7 | Publish JAR to Nexus | Deploy SNAPSHOT JAR to `maven-snapshots` repository |
| 8 | Docker Build | Multi-stage image built once, tagged for all three registries |
| 9 | Trivy Image Scan | Three passes: OS packages (warn), JAR CRITICALs (fail), full audit artifact |
| 10 | Push to Docker Hub | Push versioned tag and `latest` to `mibtisam/java-monolith` |
| 11 | Push to GHCR | Push to `ghcr.io/ibtisam-iq/java-monolith` |
| 12 | Push to Nexus Registry | Push to `nexus.ibtisam-iq.com/docker-hosted/java-monolith` |
| 13 | Push to AWS ECR | Planned. Ready to enable once ECR repo is provisioned |
| 14 | Update CD Repo | Commit new image tag to `platform-engineering-systems` for GitOps handoff to ArgoCD |

The build fails hard on three conditions: Trivy finds CRITICAL CVEs in JAR dependencies, SonarQube Quality Gate does not pass, or any unit test fails.

**Jenkins Pipeline: Build #12 (All 14 stages passed)**

![Jenkins pipeline all 14 stages passed](assets/jenkins-pipeline-success.png)

#### Jenkins

Built as a fully declarative pipeline in `Jenkinsfile` (no shared libraries, no scripted blocks). The file itself became a learning artifact: every stage has inline rationale. The design decisions that were not obvious (credential scoping, publisher placement, agent behaviour) are documented in [`docs/understand-jenkinsfile.md`](docs/understand-jenkinsfile.md).

#### GitHub Actions

Mirrored in `.github/workflows/ci.yml` with two decisions worth calling out. First, Trivy runs as split passes with different exit codes for OS packages versus JAR dependencies (rationale in [`docs/trivy-troubleshooting.md`](docs/trivy-troubleshooting.md)). Second, the SonarQube Quality Gate requires a specific working directory pin to reliably locate `report-task.txt` across runs (documented in [`docs/sonarqube-troubleshooting.md`](docs/sonarqube-troubleshooting.md)).

#### Built Docker Images

```text
ibtisam@dev-machine:~ $ docker images
IMAGE                                                     ID             DISK USAGE   CONTENT SIZE
ghcr.io/ibtisam-iq/java-monolith:latest                   88a727976b14        621MB          186MB
mibtisam/java-monolith:latest                             88a727976b14        621MB          186MB
nexus.ibtisam-iq.com/docker-hosted/java-monolith:latest   88a727976b14        621MB          186MB
```

---

### Step 5: Platform Engineering (Deployment & Operations)

This repository (Continuous Integration) is strictly responsible for building the artifact. The deployment and operational logic is intentionally decoupled into a dedicated Continuous Deployment repository to enforce a strict separation of concerns.

The artifacts generated by this pipeline (both the raw JAR and the Docker image) were deployed across four increasingly advanced architectural paradigms, divided into two distinct engineering groups:

#### Group 1: AWS Native Computing (Provisioned via AWS CLI)
These environments were provisioned entirely using the **AWS CLI**, constructing a complete virtual private cloud (VPC) with NAT Gateways, Bastion Hosts, and a shared **Amazon RDS** backend database.

| Architecture | Artifact | Deployment Description |
|---|---|---|
| **[EC2 Auto Scaling](https://github.com/ibtisam-iq/platform-engineering-systems/tree/main/systems/java-monolith/ec2-asg)** | Raw `.jar` | A containerless architecture. An Application Load Balancer (ALB) and Auto Scaling Group manage the EC2 instances, which use IAM Instance Profiles to dynamically pull the JAR from S3. Traffic is routed via Route 53 with ACM certificates. |
| **[Amazon ECS Fargate](https://github.com/ibtisam-iq/platform-engineering-systems/tree/main/systems/java-monolith/ecs)** | Docker Image | Shifted compute to serverless containers while mirroring the EC2 architecture's robust networking and persistence layers (ALB, Route 53, ACM, RDS). Implemented **Amazon CloudWatch** for centralized logging and metrics. |

#### Group 2: Kubernetes Orchestration (Provisioned via Kustomize & Terraform)
These environments utilize **Kustomize** for manifest management and the modern **Gateway API** for advanced ingress routing. 

| Architecture | Infrastructure Environment | Deployment Description |
|---|---|---|
| **[Bare-Metal Kubernetes](https://github.com/ibtisam-iq/platform-engineering-systems/tree/main/systems/java-monolith/k8s#bare-metal-overlay-overlaysbare-metal)** | **iximiuz Labs** | Built a custom cluster on an ephemeral iximiuz dev machine using my own automated `kubeadm` script. Resolved complex networking challenges behind a NAT by implementing NGINX Gateway Fabric and automating TLS issuance via **cert-manager**. |
| **[Amazon EKS](https://github.com/ibtisam-iq/platform-engineering-systems/tree/main/systems/java-monolith/k8s#eks-overlay-overlayseks)** | **KodeKloud AWS Lab** | A production-grade cloud-native architecture. The EKS cluster was provisioned entirely via **Terraform** within a KodeKloud sandbox environment. Integrated the **AWS Load Balancer Controller**, **EBS `gp3`** storage classes, and a **HorizontalPodAutoscaler (HPA)**. |

👉 **Platform Repository:** [Platform Engineering Systems / Java Monolith](https://github.com/ibtisam-iq/platform-engineering-systems/tree/main/systems/java-monolith)

---

## Key Idea

> Code = Input. Pipelines secure it. Infrastructure runs it.

| Repository | Role |
|---|---|
| **This repo** | Application source code and all CI/CD pipeline definitions (Jenkins, GitHub Actions) |
| **[Platform Engineering Systems](https://github.com/ibtisam-iq/platform-engineering-systems)** | Platform architecture (deploys, operates, and scales the artifact across multiple targets) |

> This separation is intentional. Pipeline logic lives with the code it builds, and deployment configs stay independently versioned in their own repo.
