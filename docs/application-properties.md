# application.properties — Evolution & Explanation

This document tracks the evolution of `src/main/resources/application.properties` across three stages: the original hardcoded version, the Docker Compose-compatible version, and the final production-ready version currently in use.

---

## Stage 1 — Original (Hardcoded)

The inherited codebase had all values hardcoded directly in the properties file:

```properties
spring.application.name=bankapp

# MySQL Database configuration
spring.datasource.url=jdbc:mysql://localhost:3306/bankappdb?useSSL=false&serverTimezone=UTC
spring.datasource.username=root
spring.datasource.password=IbtisamIQ
spring.datasource.driver-class-name=com.mysql.cj.jdbc.Driver

# JPA & Hibernate configuration
spring.jpa.hibernate.ddl-auto=update
spring.jpa.properties.hibernate.dialect=org.hibernate.dialect.MySQL8Dialect
spring.jpa.show-sql=true
```

**Problems with this approach:**
- ❌ Credentials committed to version control — a security vulnerability
- ❌ `localhost` hardcoded — breaks inside Docker (containers can't reach the host's `localhost`)
- ❌ Not portable — different environments (dev, staging, prod) require different files
- ❌ No health check endpoint exposed for Docker/Kubernetes probes

---

## Stage 2 — Docker Compose Compatible

First refactor: replaced hardcoded values with environment variables and fixed the hostname for Docker networking.

```properties
# Application Configuration
spring.application.name=bankapp

# Database Configuration
# Before: spring.datasource.url=jdbc:mysql://localhost:3306/bankappdb?...
# Now:    "localhost" → "db" (Docker Compose service name)
spring.datasource.url=jdbc:mysql://db:3306/${MYSQL_DATABASE}?useSSL=false&serverTimezone=UTC
spring.datasource.username=${MYSQL_USER}
spring.datasource.password=${MYSQL_PASSWORD}
spring.datasource.driver-class-name=com.mysql.cj.jdbc.Driver

# JPA & Hibernate Configuration
spring.jpa.hibernate.ddl-auto=update
spring.jpa.properties.hibernate.dialect=org.hibernate.dialect.MySQL8Dialect
spring.jpa.show-sql=true

# Actuator Configuration (Added)
# Exposes /actuator/health for Docker Compose health checks
management.endpoints.web.exposure.include=health
```

**Key changes:**
- ✅ `localhost` → `db` — Docker containers communicate by service name, not localhost
- ✅ Credentials replaced with `${MYSQL_USER}` / `${MYSQL_PASSWORD}` environment variables
- ✅ Added Actuator health endpoint for `HEALTHCHECK` in `compose.yml`

---

## Stage 3 — Production Ready (Current)

Final refactor: every single value — including the application name, driver class, port, and JPA settings — is driven by environment variables. No defaults, no fallbacks, no hardcoding of any kind.

```properties
# Application Name
spring.application.name=${SPRING_APPLICATION_NAME}

# Database Connection Properties
spring.datasource.username=${SPRING_DATASOURCE_USERNAME}
spring.datasource.password=${SPRING_DATASOURCE_PASSWORD}
spring.datasource.url=${SPRING_DATASOURCE_URL}
spring.datasource.driver-class-name=com.mysql.cj.jdbc.Driver

# Hibernate (JPA) Settings
spring.jpa.hibernate.ddl-auto=update
spring.jpa.database-platform=org.hibernate.dialect.MySQLDialect
spring.jpa.show-sql=false

# Fix for depends_on: ensures app waits for MySQL to be fully ready
spring.datasource.initialization-mode=always
spring.sql.init.mode=always

# Actuator: exposes /actuator/health for Docker/K8s health checks
management.endpoints.web.exposure.include=health

# Server Port
server.port=${SERVER_PORT}
```

**Why this is the right approach:**
- ✅ Zero hardcoded values — the file is completely environment-agnostic
- ✅ Same codebase runs on localhost, Docker Compose, AWS EC2, and Kubernetes without modification
- ✅ `SPRING_DATASOURCE_URL` is the full JDBC URL, passed in per-environment (different hosts, databases, ports)
- ✅ `spring.jpa.show-sql=false` — SQL logging disabled in production for performance and log hygiene
- ✅ `server.port=${SERVER_PORT}` — port is controlled externally, not baked in

---

## Environment Variable Reference

All variables are defined in `.env.example` at the repo root. Copy it to `.env` and fill in real values:

```bash
cp .env.example .env
```

| Variable | Description | Example Value |
|---|---|---|
| `SPRING_APPLICATION_NAME` | Spring application name | `IbtisamIQBankApp` |
| `SPRING_DATASOURCE_USERNAME` | DB username | `your_db_user` |
| `SPRING_DATASOURCE_PASSWORD` | DB password | `your_db_password` |
| `SPRING_DATASOURCE_URL` | Full JDBC connection URL | `"jdbc:mysql://localhost:3306/IbtisamIQbankappdb?useSSL=false&serverTimezone=UTC&allowPublicKeyRetrieval=true"` |
| `SERVER_PORT` | Application HTTP port | `8000` |

> **Note:** `SPRING_DATASOURCE_URL` must be wrapped in **double quotes** in the `.env` file. The `&` character in the query string is a shell special character — without quotes, the shell will truncate the URL at the first `&`, causing a connection failure.

---

## Running Locally with Environment Variables

```bash
# Load env vars from .env and run the application
set -a && source .env && set +a && java -jar target/bankapp-0.0.1-SNAPSHOT.jar
```

> **Why `set -a`?** `set -a` marks every variable sourced from `.env` for automatic export into the child process (the JVM). `set +a` turns off the flag after sourcing so subsequent shell variables are not unintentionally exported.

If you run `java -jar` without loading env vars first, Spring Boot will throw:
```
PlaceholderResolutionException: Could not resolve placeholder 'SPRING_APPLICATION_NAME'
```

This is the expected and correct behavior — it enforces that all required configuration must be explicitly provided.
