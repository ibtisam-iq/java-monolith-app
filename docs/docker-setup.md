# Docker Setup — Dockerfile & Compose

This document explains the Docker setup for the Java monolith banking application: the multi-stage `Dockerfile` and the `compose.yml` used to run the full 2-tier stack (Spring Boot + MySQL).

---

## Directory Layout

```
java-monolith-app/
├── src/                        # Application source code
├── pom.xml                     # Maven build config
├── .env.example                # Environment variable template
├── Dockerfile                  # Multi-stage production Dockerfile
└── compose.yml                 # Docker Compose for local/dev deployment
```

---

## Dockerfile

This project uses a **multi-stage build** — the industry standard for production Java containers.

```dockerfile
# ============================================================
# Stage 1 — Build
# Java 21 (current LTS) with Maven 3.9.9 on Alpine
# ============================================================
FROM maven:3.9.9-eclipse-temurin-21-alpine AS builder

WORKDIR /usr/src/app

# Copy pom.xml first to leverage Docker layer caching for dependencies
COPY pom.xml .

# Resolve dependencies separately from source changes for better caching
RUN mvn dependency:resolve

# Copy source and build
COPY src ./src
RUN mvn clean package -DskipTests

# ============================================================
# Stage 2 — Production Runtime
# JRE-only image: smaller size + reduced attack surface vs JDK
# ============================================================
FROM eclipse-temurin:21-jre-alpine

# OCI standard image labels
LABEL maintainer="github.com/ibtisam-iq" \
      org.opencontainers.image.title="BankApp" \
      org.opencontainers.image.description="Banking Web Application — Platform Engineering Project" \
      org.opencontainers.image.licenses="MIT"

WORKDIR /usr/src/app

# Security hardening: run as non-root user
# Running as root inside a container is a critical vulnerability flagged by Trivy
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Copy built JAR from builder stage
COPY --from=builder /usr/src/app/target/*.jar app.jar

# Set correct ownership before switching user
RUN chown appuser:appgroup app.jar

USER appuser

EXPOSE 8000

# Health check using Spring Boot Actuator endpoint
# Requires spring-boot-starter-actuator in pom.xml
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD wget -qO- http://localhost:8000/actuator/health || exit 1

ENTRYPOINT ["java", "-jar", "app.jar"]
```

### Key Design Decisions

| Decision | Reason |
|---|---|
| **Two-stage build** | Build tools (Maven, JDK) stay out of the final image — smaller size, smaller attack surface |
| **`mvn dependency:resolve` before `COPY src`** | Docker layer cache: dependency layer only rebuilds when `pom.xml` changes, not on every source change |
| **`eclipse-temurin:21-jre-alpine` runtime** | JRE-only (not JDK) on Alpine — minimal OS, no compiler, no debugging tools in production |
| **Non-root user (`appuser`)** | Running as root is a critical vulnerability flagged by Trivy and rejected by Kubernetes PodSecurityPolicy |
| **`chown` before `USER`** | Ownership must be set while still running as root, before switching to `appuser` |
| **`EXPOSE 8000`** | Documents the port; matches `server.port=${SERVER_PORT}` in `application.properties` |
| **`HEALTHCHECK` via Actuator** | Docker monitors container health using `/actuator/health` — requires `spring-boot-starter-actuator` in `pom.xml` |
| **`wget` not `curl`** | Alpine Linux does not include `curl` by default; `wget` is available in the base image |
| **`ENTRYPOINT` not `CMD`** | `ENTRYPOINT` is not overridable by accident; appropriate for a single-purpose application container |

---

## compose.yml

```yaml
services:
  web:
    build:
      context: .               # java-monolith-app/ root
      dockerfile: Dockerfile
    image: java-monolith-bankapp
    container_name: bank-web
    restart: unless-stopped
    ports:
      - "8000:8000"
    env_file:
      - .env
    depends_on:
      db:
        condition: service_healthy
    networks:
      - app-network
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:8000/actuator/health"]
      interval: 30s
      timeout: 10s
      start_period: 30s
      retries: 3

  db:
    image: mysql:8
    container_name: mysql-db
    restart: unless-stopped
    env_file:
      - .env
    volumes:
      - mysql_data:/var/lib/mysql
    networks:
      - app-network
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-uroot", "-p$MYSQL_ROOT_PASSWORD"]
      interval: 30s
      timeout: 10s
      start_period: 20s
      retries: 3

networks:
  app-network:
    driver: bridge

volumes:
  mysql_data:
```

### Key Design Decisions

| Decision | Reason |
|---|---|
| **`depends_on: condition: service_healthy`** | App container only starts after MySQL passes its health check — prevents `PlaceholderResolutionException` or connection refused on startup |
| **`env_file: .env`** | All credentials loaded from `.env` file — never hardcoded in `compose.yml` |
| **Named volume `mysql_data`** | Database data persists across `docker compose down` and container restarts |
| **Custom bridge network `app-network`** | Containers communicate by service name (`db`) — required for `SPRING_DATASOURCE_URL` to resolve correctly |
| **`restart: unless-stopped`** | Auto-restarts on crash but respects manual `docker compose stop` |
| **Health checks on both services** | Docker tracks liveness of both containers independently |
| **`wget` in web health check** | Alpine image doesn't have `curl`; `wget -qO-` is the correct alternative |
| **`-h localhost` in MySQL health check** | Inside the MySQL container, the server is at `localhost` — not the Docker service name `db` |

---

## Running with Docker Compose

```bash
# 1. Copy and fill in the environment file
cp .env.example .env
# Edit .env with your actual values

# 2. Build and start both services
docker compose up --build -d

# 3. Follow logs
docker compose logs -f

# 4. Check health status
docker compose ps

# 5. Access the application
open http://localhost:8000

# 6. Stop everything (data persists in volume)
docker compose down

# 7. Stop and remove all data
docker compose down -v
```

---

## Environment Variables for Docker

The `.env` file must contain the following variables (see `.env.example`):

```env
# Spring Boot app config
SPRING_APPLICATION_NAME=IbtisamIQBankApp
SPRING_DATASOURCE_USERNAME=your_db_user
SPRING_DATASOURCE_PASSWORD=your_db_password
SPRING_DATASOURCE_URL="jdbc:mysql://db:3306/IbtisamIQbankappdb?useSSL=false&serverTimezone=UTC&allowPublicKeyRetrieval=true"
SERVER_PORT=8000

# MySQL container config (consumed by mysql:8 image directly)
MYSQL_ROOT_PASSWORD=your_root_password
MYSQL_DATABASE=IbtisamIQbankappdb
MYSQL_USER=your_db_user
MYSQL_PASSWORD=your_db_password
```

> **Important:** In the Docker Compose context, `SPRING_DATASOURCE_URL` must use `db` as the hostname (the MySQL service name), **not** `localhost`. Spring Boot running inside the `web` container reaches MySQL through the Docker bridge network by service name.
