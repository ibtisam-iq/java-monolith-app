# How to Read a Java Project as a DevOps Engineer

When you receive a Java project and need to Dockerize it, you do not need to understand the Java code itself. You need to read **5 specific things** and answer **5 specific questions**. Everything else is irrelevant to you.

---

## The 5 Questions You Must Answer

| # | Question | Where to Find the Answer |
|---|---|---|
| 1 | What build tool is used? | Root folder — look for `pom.xml` or `build.gradle` |
| 2 | What Java version does it need? | `pom.xml` → `<java.version>` |
| 3 | What does the build produce, and what is its name? | `pom.xml` → `<artifactId>` + `<version>` |
| 4 | What database does it use, and how does it connect? | `src/main/resources/application.properties` |
| 5 | On which port does the app run? | `src/main/resources/application.properties` → `server.port` |

Once you can answer all 5, you have everything you need to write a `Dockerfile` and `compose.yml`.

---

## Step 1 — Look at the Root Folder First

When you open any Java project, the root folder tells you immediately what kind of project it is.

```
java-monolith-app/          ← root
├── pom.xml                 ← EXISTS? → This is a Maven project. Build tool = Maven.
├── build.gradle            ← EXISTS instead? → This is a Gradle project. Build tool = Gradle.
├── mvnw                    ← Maven Wrapper script (Unix). Means Maven is bundled — no need to install it separately.
├── mvnw.cmd                ← Maven Wrapper for Windows. Same purpose, different OS.
├── .mvn/                   ← Folder containing Maven Wrapper config. Part of the wrapper setup.
├── .gitignore              ← Tells Git which files to ignore (target/, .env, etc.). Not relevant to you.
├── .env.example            ← Template for required environment variables. VERY relevant — read this.
└── src/                    ← All application source code lives here. Explained below.
```

**What you learn from this:**
- `pom.xml` exists → **Maven** is the build tool → the build command is `mvn package` or `./mvnw package`
- `mvnw` exists → you do **not** need Maven installed on the machine — the wrapper downloads it
- `.env.example` exists → the app requires environment variables → you must pass them at runtime

---

## Step 2 — Read `pom.xml` (The Most Important File for DevOps)

`pom.xml` is the Maven project descriptor. As a DevOps engineer you only care about 4 things inside it.

### 2a — Java Version

```xml
<properties>
    <java.version>21</java.version>   <!-- ← THIS. The app needs Java 21. -->
</properties>
```

**Why it matters for Docker:** Your base image in the Dockerfile must match this version.

```dockerfile
# ✅ Correct — matches <java.version>21</java.version>
FROM maven:3.9.9-eclipse-temurin-21-alpine AS builder
FROM eclipse-temurin:21-jre-alpine

# ❌ Wrong — version mismatch will cause build failure
FROM eclipse-temurin:17-jre-alpine
```

### 2b — Spring Boot Version

```xml
<parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.4.4</version>   <!-- ← Spring Boot version -->
</parent>
```

**Why it matters:** Spring Boot 3.x requires Java 17+. If you see Spring Boot 2.x, Java 11+ is fine. This confirms your Java version choice.

### 2c — Build Output (The JAR filename)

```xml
<artifactId>bankapp</artifactId>       <!-- ← part 1 of filename -->
<version>0.0.1-SNAPSHOT</version>      <!-- ← part 2 of filename -->
```

**Maven always produces:** `target/<artifactId>-<version>.jar`

So for this project: `target/bankapp-0.0.1-SNAPSHOT.jar`

**Why it matters for Dockerfile:**

```dockerfile
# You need to know the exact output filename to copy it
COPY --from=builder /usr/src/app/target/bankapp-0.0.1-SNAPSHOT.jar app.jar

# Or use wildcard to avoid hardcoding the version — preferred approach
COPY --from=builder /usr/src/app/target/*.jar app.jar
```

### 2d — Dependencies (What the app needs at runtime)

```xml
<dependencies>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-data-jpa</artifactId>
        <!-- ← JPA present → app uses a relational database (needs DB container) -->
    </dependency>

    <dependency>
        <groupId>com.mysql</groupId>
        <artifactId>mysql-connector-j</artifactId>
        <!-- ← MySQL driver → database is MySQL specifically (not Postgres, not H2) -->
    </dependency>

    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-actuator</artifactId>
        <!-- ← Actuator present → /actuator/health endpoint is available → use it for HEALTHCHECK -->
    </dependency>

    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-thymeleaf</artifactId>
        <!-- ← Thymeleaf present → UI is server-side rendered → this is a 2-tier app, no separate frontend container needed -->
    </dependency>

    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-security</artifactId>
        <!-- ← Security present → app has login/auth → not a public open API -->
    </dependency>
</dependencies>
```

**What each dependency tells you as a DevOps engineer:**

| Dependency | What It Tells You |
|---|---|
| `spring-boot-starter-data-jpa` | App uses a relational DB → you need a DB container |
| `mysql-connector-j` | DB is **MySQL** → use `mysql:8` image in compose |
| `mysql-connector-j` (scope runtime) | Driver not needed at build time → only needed when app runs |
| `spring-boot-starter-actuator` | `/actuator/health` available → use it in `HEALTHCHECK` |
| `spring-boot-starter-thymeleaf` | UI is embedded in backend → no separate frontend container |
| `spring-boot-starter-security` | App has protected routes → health check endpoint may need special config |
| `scope: test` on any dependency | Test-only → not packaged in final JAR → irrelevant to Docker |

### 2e — Nexus / Artifact Repository

```xml
<distributionManagement>
    <repository>
        <id>maven-releases</id>
        <url>NEXUS-URL/repository/maven-releases/</url>   <!-- ← where built JARs get published -->
    </repository>
    <snapshotRepository>
        <id>maven-snapshots</id>
        <url>NEXUS-URL/repository/maven-snapshots/</url>
    </snapshotRepository>
</distributionManagement>
```

**Why it matters:** In a CI/CD pipeline, the built JAR is pushed to Nexus. When deploying, you can pull the JAR from Nexus instead of rebuilding from source. This is how `Case 2` (pre-built JAR Dockerfile) works in production pipelines.

---

## Step 3 — Read `application.properties`

This is the second most important file for DevOps. It tells you everything about how the app connects to the outside world.

```properties
# application.properties — current state of this project

spring.application.name=${SPRING_APPLICATION_NAME}
# ↑ App name comes from env var. Required at startup.

spring.datasource.url=${SPRING_DATASOURCE_URL}
# ↑ Full JDBC connection string. Tells you:
#   - Database type: jdbc:mysql → MySQL
#   - Host: whatever is in SPRING_DATASOURCE_URL (localhost for local, "db" for Docker)
#   - Port: 3306 (MySQL default)
#   - Database name: part of the URL

spring.datasource.username=${SPRING_DATASOURCE_USERNAME}
spring.datasource.password=${SPRING_DATASOURCE_PASSWORD}
# ↑ DB credentials from env vars. Never hardcoded.

spring.datasource.driver-class-name=com.mysql.cj.jdbc.Driver
# ↑ Hardcoded — this is fine. The driver class never changes for MySQL.

spring.jpa.hibernate.ddl-auto=update
# ↑ Hibernate will auto-create/update tables on startup.
#   Means: you do NOT need to run SQL migration scripts manually.
#   The app handles schema creation itself.

management.endpoints.web.exposure.include=health
# ↑ VERY important. This means /actuator/health is exposed.
#   Use this as your HEALTHCHECK URL in both Dockerfile and compose.yml.

server.port=${SERVER_PORT}
# ↑ Port comes from env var. Check .env.example → SERVER_PORT=8000
#   This tells you: EXPOSE 8000 in Dockerfile, ports: "8000:8000" in compose.
```

### What `application.properties` Tells You for Dockerization

| Property | What You Learn | Action in Docker |
|---|---|---|
| `jdbc:mysql://...` | Database = MySQL | Use `mysql:8` image in compose |
| `${SPRING_DATASOURCE_URL}` | DB URL is env var | Pass it via `env_file` in compose |
| `ddl-auto=update` | App manages schema itself | No init SQL script needed in compose |
| `management...health` | `/actuator/health` is available | Use in `HEALTHCHECK` |
| `server.port=${SERVER_PORT}` | Port is configurable | `EXPOSE 8000`, ports `8000:8000` |

---

## Step 4 — Read `.env.example`

This file is the complete list of every environment variable the app requires. If this file exists, read it before writing anything else.

```env
SPRING_APPLICATION_NAME=IbtisamIQBankApp
SPRING_DATASOURCE_USERNAME=your_db_user
SPRING_DATASOURCE_PASSWORD=your_db_password
SPRING_DATASOURCE_URL="jdbc:mysql://localhost:3306/IbtisamIQbankappdb?useSSL=false&serverTimezone=UTC&allowPublicKeyRetrieval=true"
SERVER_PORT=8000

MYSQL_ROOT_PASSWORD=your_root_password
MYSQL_DATABASE=IbtisamIQbankappdb
MYSQL_USER=your_db_user
MYSQL_PASSWORD=your_db_password
```

**Two groups of variables — and this is critical:**

**Group 1 — Spring Boot variables** (`SPRING_*`, `SERVER_PORT`):
- Consumed by the **app container** (`web` service in compose)
- Spring Boot reads them via `${VARIABLE_NAME}` in `application.properties`

**Group 2 — MySQL variables** (`MYSQL_*`):
- Consumed by the **database container** (`db` service in compose)
- The official `mysql:8` Docker image reads `MYSQL_ROOT_PASSWORD`, `MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_PASSWORD` automatically on first startup to initialize the database

Both groups live in the same `.env` file. Both services read from it via `env_file: - .env`. Each service only uses the variables it understands — the rest are ignored.

**Also notice:** `SPRING_DATASOURCE_URL` has `localhost` in `.env.example`. This is for **local development** (running with `java -jar` directly). When running in Docker Compose, you must change `localhost` to `db` (the MySQL service name) because containers reach each other by service name, not localhost.

---

## Step 5 — Look at `src/main/resources/` for Static Assets

```
src/main/resources/
├── application.properties        ← Already read in Step 3
├── static/
│   └── mysql/
│       └── SQLScript.txt         ← SQL setup script. BUT since ddl-auto=update, this is NOT needed for Docker.
└── templates/
    ├── login.html
    ├── dashboard.html
    ├── register.html
    └── transactions.html         ← Thymeleaf templates. Packaged INSIDE the JAR automatically by Maven.
```

**What this tells you:**
- `templates/` contains Thymeleaf HTML files → these are the UI → they get bundled **inside** the JAR at build time → you do NOT copy them separately in the Dockerfile
- `SQLScript.txt` exists but `ddl-auto=update` means Hibernate handles schema → you do not need to mount or run this script in Docker
- Everything in `src/main/resources/` gets packaged into the JAR by Maven automatically — you never copy these files manually in your Dockerfile

---

## Putting It All Together — From Reading to Dockerfile

Here is exactly what you extract from each file and what it maps to in Docker:

| What You Read | Where You Read It | Maps To |
|---|---|---|
| Build tool = Maven | Root folder has `pom.xml` | `FROM maven:...` in build stage |
| Java version = 21 | `pom.xml` → `<java.version>21</java.version>` | `eclipse-temurin:21-...` base image |
| JAR filename = `bankapp-0.0.1-SNAPSHOT.jar` | `pom.xml` → `<artifactId>bankapp` + `<version>0.0.1-SNAPSHOT` | `COPY target/*.jar app.jar` |
| Database = MySQL | `pom.xml` → `mysql-connector-j` dependency | `image: mysql:8` in compose |
| DB credentials = env vars | `application.properties` → `${SPRING_DATASOURCE_*}` | `env_file: .env` in compose |
| App port = 8000 | `.env.example` → `SERVER_PORT=8000` | `EXPOSE 8000`, `ports: "8000:8000"` |
| Health endpoint available | `application.properties` → `management...health` | `HEALTHCHECK` via `/actuator/health` |
| UI is embedded | `pom.xml` → `thymeleaf` dependency | No separate frontend container |
| Schema managed by app | `application.properties` → `ddl-auto=update` | No SQL init script in compose |
| Maven wrapper exists | `mvnw` file in root | Use `./mvnw` or just `mvn` inside builder stage |

---

## The `src/` Folder Structure — What Each Folder Does

You do not need to read the Java code. But knowing what each folder is for helps you understand what the app does and whether it needs additional services.

```
src/main/java/com/example/bankapp/
├── BankappApplication.java   → The main() method. Spring Boot starts here.
│                               As DevOps: this is your entrypoint. The JAR runs this.
│
├── config/                   → Configuration classes (Security, CORS, etc.)
│   └── SecurityConfig.java   → Spring Security setup. Tells you: app has authentication.
│                               As DevOps: login page exists, /actuator/health may need
│                               to be whitelisted in security config to work unauthenticated.
│
├── controller/               → HTTP request handlers. Maps URLs to actions.
│   └── BankController.java   → Handles routes like /login, /dashboard, /transfer
│                               As DevOps: tells you what URLs the app serves.
│
├── model/                    → Data model classes (Account, Transaction, User)
│                               As DevOps: tells you what tables exist in the database.
│
├── repository/               → Database query interfaces
│                               As DevOps: confirms the app talks to a DB. No action needed.
│
└── service/                  → Business logic (transfer money, check balance, etc.)
                                As DevOps: not relevant to containerization.
```

---

## Common Patterns in Java Projects — What to Look For

### Pattern 1 — H2 In-Memory Database

```xml
<!-- If you see this in pom.xml -->
<dependency>
    <groupId>com.h2database</groupId>
    <artifactId>h2</artifactId>
    <scope>runtime</scope>
</dependency>
```

**What it means:** App uses an in-memory database. **No separate DB container needed.** Data is lost when the container stops. Usually for testing/dev only.

### Pattern 2 — PostgreSQL Instead of MySQL

```xml
<dependency>
    <groupId>org.postgresql</groupId>
    <artifactId>postgresql</artifactId>
</dependency>
```

**What it means:** Use `postgres:16` image instead of `mysql:8` in compose. Connection URL will be `jdbc:postgresql://db:5432/dbname`.

### Pattern 3 — Hardcoded `application.properties`

```properties
# If you see this (no ${} placeholders):
spring.datasource.url=jdbc:mysql://localhost:3306/bankappdb
spring.datasource.username=root
spring.datasource.password=secret
```

**What it means:** Values are hardcoded. You CANNOT pass them as env vars at runtime. You must either:
1. Edit `application.properties` to use `${VAR_NAME}` before Dockerizing, OR
2. Override them via Spring's env var naming convention: `SPRING_DATASOURCE_URL`, `SPRING_DATASOURCE_USERNAME`, `SPRING_DATASOURCE_PASSWORD` — Spring Boot automatically maps these to the matching properties.

### Pattern 4 — No Actuator

If `spring-boot-starter-actuator` is NOT in `pom.xml` and `management.endpoints...health` is NOT in `application.properties`:

**What it means:** No `/actuator/health` endpoint. For `HEALTHCHECK`, use a different approach:

```dockerfile
# Check if the app is responding on its port
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -qO- http://localhost:8000/ || exit 1
```

### Pattern 5 — Multiple `application-*.properties` Files

```
src/main/resources/
├── application.properties          ← base config (always loaded)
├── application-dev.properties      ← loaded when SPRING_PROFILES_ACTIVE=dev
├── application-prod.properties     ← loaded when SPRING_PROFILES_ACTIVE=prod
└── application-docker.properties   ← loaded when SPRING_PROFILES_ACTIVE=docker
```

**What it means:** App uses Spring profiles. In Docker, set:

```yaml
environment:
  - SPRING_PROFILES_ACTIVE=docker
```

Or in `.env`: `SPRING_PROFILES_ACTIVE=docker`

---

## Quick Reference Checklist — Before Writing Any Dockerfile

Open the project and answer these before writing a single line:

```
□ pom.xml or build.gradle?       → Determines build command (mvn vs gradle)
□ Java version?                  → pom.xml <java.version>
□ artifactId + version?          → Determines JAR filename in target/
□ Which database driver?         → mysql-connector-j / postgresql / h2
□ application.properties hardcoded or env vars?
□ What is server.port?           → .env.example or application.properties
□ Is Actuator present?           → For HEALTHCHECK
□ Is there a docker profile?     → application-docker.properties
□ Does ddl-auto handle schema?   → No init SQL script needed in compose
□ Is Thymeleaf present?          → UI is embedded, no frontend container needed
```
