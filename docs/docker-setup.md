# How to Dockerize a Java Spring Boot Application

This document explains **every decision** behind the `Dockerfile` and `compose.yml` in this project — not just what each line does, but **why it was written that way**, what the alternatives were, why they were rejected, and what breaks if you get it wrong.

This is also a **reusable framework** for writing Docker files for any Java Spring Boot project from scratch.

---

## Step 0 — Read the Project Before Writing a Single Line

The biggest mistake developers make is opening a blank `Dockerfile` and starting to type. The correct approach is to interrogate the project first. Every answer below was extracted from `pom.xml`, `application.properties`, and `.env.example` in this repo **before** any Docker file was written.

| Question to Answer | Where to Look | Answer for This Project |
|---|---|---|
| What is the build tool? | Root directory — `pom.xml` = Maven, `build.gradle` = Gradle | **Maven** (`pom.xml` exists) |
| What Java version? | `pom.xml` → `<java.version>` | **Java 21** (`<java.version>21</java.version>`) |
| What is the JAR filename? | `pom.xml` → `<artifactId>` + `<version>` | `target/bankapp-0.0.1-SNAPSHOT.jar` |
| What database does the app use? | `pom.xml` → `<dependencies>` | **MySQL** (`mysql-connector-j` present) |
| What port does the app listen on? | `application.properties` or `.env.example` | **8000** (`SERVER_PORT=8000` in `.env.example`) |
| Is there a health endpoint? | `pom.xml` → `spring-boot-starter-actuator` | **Yes** → `/actuator/health` |
| Are credentials hardcoded or env vars? | `application.properties` → `${...}` syntax | **All env vars** — nothing hardcoded |
| What Linux tools are available? | Base image choice (Alpine vs Debian) | **Alpine** → `wget` available, `curl` is NOT |

Only after answering all of these did the Docker files get written. This is the real skill — not syntax, but **reading the project before writing the containers**.

---

## The Dockerfile — Every Decision Explained

### Stage 1 — Build

```dockerfile
FROM maven:3.9.9-eclipse-temurin-21-alpine AS builder
```

**Why this specific image?**

This image bundles **Maven 3.9.9 + Java 21 JDK + Alpine Linux** in one. Three decisions are packed into this one line:

| Component | Decision | Reason |
|---|---|---|
| `maven:3.9.9` | Maven pre-installed | No need to copy `mvnw` wrapper or install Maven separately — it is already in the image |
| `eclipse-temurin-21` | Java 21 JDK | Must match `<java.version>21</java.version>` in `pom.xml`. Mismatch = compile failure |
| `alpine` | Alpine Linux base | Smallest OS footprint. Fewer CVEs. Faster pulls |
| `AS builder` | Stage name | The runtime stage will reference this name with `--from=builder` to copy the JAR |

> **Why not use `mvnw`?** The `mvnw` (Maven Wrapper) approach requires copying `.mvn/`, `mvnw`, and `pom.xml`, then doing `chmod +x mvnw`, then calling `./mvnw`. That is 3 extra steps. The `maven:3.9.9` image eliminates all of them. Cleaner and more reliable in CI.

---

```dockerfile
WORKDIR /usr/src/app
```

Sets the working directory for all subsequent instructions inside the container. Docker creates it if it does not exist.

`/usr/src/app` is the FHS (Filesystem Hierarchy Standard) compliant path for source code that is not part of the operating system. `/app` also works but `/usr/src/app` is the conventional choice for build containers.

> **Without `WORKDIR`:** Files land in `/` (root). Messy, insecure, and hard to debug.

---

```dockerfile
COPY pom.xml .
RUN mvn dependency:go-offline -B --no-transfer-progress
COPY src ./src
RUN mvn clean package -DskipTests -B --no-transfer-progress
```

**This ordering is the most important caching optimization in Java Dockerization.**

Docker builds in layers. Each instruction creates a layer. Layers are cached and only re-run when their inputs change.

```
Layer 1: FROM maven image                    ← cached forever
Layer 2: WORKDIR                             ← cached forever
Layer 3: COPY pom.xml .                      ← invalidated only if pom.xml changes
Layer 4: RUN mvn dependency:go-offline       ← invalidated only if pom.xml changes (2-3 min first time)
Layer 5: COPY src ./src                      ← invalidated on ANY source code change
Layer 6: RUN mvn clean package -DskipTests   ← invalidated on ANY source code change (~15 seconds)
```

**Result:** When you change Java code (which happens on every commit), only Layers 5 and 6 re-run. All dependencies are served from cache. Build time drops from **3+ minutes to ~15 seconds**.

> **What if you did `COPY . .` first?** Every single source change would invalidate Layer 3, which invalidates Layer 4 (the dependency download), which means Maven re-downloads all JARs on every build. Catastrophic for CI pipelines.

**`dependency:go-offline` vs `dependency:resolve`:**

| Command | What it downloads |
|---|---|
| `dependency:resolve` | Only declared `<dependencies>` in `pom.xml` |
| `dependency:go-offline` | Declared dependencies **+ all Maven build plugins** (compiler, surefire, jacoco, spring-boot-maven-plugin, etc.) |

`go-offline` is more thorough. `resolve` misses plugin artifacts and you get network calls during the `package` step — defeating the purpose of pre-caching.

**`-DskipTests`** — Tests are not run inside the Docker build. They run separately in the CI pipeline (Jenkins/GitHub Actions) with a real database available. Running tests inside Docker at build time would require a live MySQL connection that does not exist during `docker build`.

**`-B --no-transfer-progress`** — Batch mode (no ANSI colors, no interactive prompts) and no per-file transfer progress spam. CI logs are clean and readable.

---

### Stage 2 — Runtime

```dockerfile
FROM eclipse-temurin:21-jre-alpine AS runtime
```

**Why a second stage?** This is multi-stage build. The builder stage contains:
- Maven installation (~200MB)
- Full JDK with compiler (`javac`)
- All downloaded dependency JARs in `~/.m2` (~300MB+)
- Source code
- Test classes

**None of that belongs in production.** The runtime stage starts completely fresh with only what is needed to run the JAR.

| Image | Approximate Size | Contains |
|---|---|---|
| `maven:3.9.9-eclipse-temurin-21-alpine` (builder) | ~500MB | Maven + JDK + all tools |
| `eclipse-temurin:21-jre-alpine` (runtime) | ~150MB | JRE only |
| Final image with JAR | ~165MB | JRE + your app |

**`jre` vs `jdk`:** The JDK includes the compiler (`javac`), debugger, and development tools. The JRE is the runtime only. A production container has no reason to compile code. Using JDK in production is like shipping a factory with every product you sell — larger attack surface, more CVEs, larger image.

**`eclipse-temurin`** is Adoptium's distribution of OpenJDK. It is the industry standard for production containers, replacing the deprecated `openjdk` official image.

---

```dockerfile
LABEL org.opencontainers.image.title="BankApp"       org.opencontainers.image.description="Java Spring Boot Banking Application"       org.opencontainers.image.authors="Muhammad Ibtisam Iqbal <github.com/ibtisam-iq>"       org.opencontainers.image.source="https://github.com/ibtisam-iq/java-monolith-app"       org.opencontainers.image.licenses="MIT"
```

OCI (Open Container Initiative) standard metadata labels. Visible in `docker inspect`, Docker Hub, GitHub Container Registry (GHCR), and scanned by Trivy. No runtime impact — pure metadata. Required for professional and portfolio images.

---

```dockerfile
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
```

**Why create a non-root user?**

By default, Docker containers run as `root` (UID 0). This is a **critical security vulnerability** for three reasons:

1. **Trivy flags it** as a HIGH or CRITICAL finding in security scans
2. **Kubernetes rejects it** under `PodSecurityAdmission` (restricted policy) — many production clusters enforce `runAsNonRoot: true`
3. **Container escape risk** — if an attacker breaks out of the container, they land as root on the host

`-S` = system account — no home directory, no login shell, no password. Minimal footprint.

> **Alpine vs Debian syntax:** Alpine uses `addgroup` / `adduser`. Debian/Ubuntu images use `groupadd` / `useradd`. This matters when switching base images.

---

```dockerfile
COPY --from=builder /usr/src/app/target/*.jar app.jar
RUN chown appuser:appgroup app.jar
USER appuser
```

**The order here is mandatory and cannot be changed:**

```
Step 1: COPY  — runs as root, copies JAR from builder stage
Step 2: chown — runs as root, sets ownership to appuser
Step 3: USER  — switches to appuser; from here everything runs as appuser
```

If you put `USER appuser` **before** `chown`, the `chown` command runs as `appuser` who has no permission to change file ownership. It fails with `Permission denied`.

**`--from=builder`** — Copies the JAR from the `builder` stage, not from the host machine. This is multi-stage build in action — the host never needs the JAR; it was built entirely inside Docker.

**`target/*.jar`** — Wildcard. Matches the JAR regardless of version number. More robust than hardcoding `bankapp-0.0.1-SNAPSHOT.jar`. When the version bumps to `0.0.2-SNAPSHOT`, the Dockerfile requires no change.

**`app.jar`** — Renames to a fixed, simple name. The `ENTRYPOINT` references `app.jar` — it never needs to change across version bumps.

**`chown appuser:appgroup app.jar`** — Targeted `chown` on only the JAR file. Not `chown -R appuser:appgroup /app` (recursive on the entire workdir) — that is unnecessary overhead since there is only one file in `/usr/src/app`.

---

```dockerfile
EXPOSE 8000
```

`EXPOSE` is **documentation**, not a firewall rule. It does not publish the port. It tells Docker and tooling (Compose, Kubernetes, `docker run -P`) that the container listens on port 8000.

Port 8000 comes from `SERVER_PORT=8000` in `.env.example`, which is injected into `server.port=${SERVER_PORT}` in `application.properties`.

---

```dockerfile
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3     CMD wget --no-verbose --tries=1 --spider http://localhost:8000/actuator/health || exit 1
```

**Why `--start-period=60s`?**

This is one of the key improvements over the initial version of this Dockerfile which used `--start-period=30s`. Spring Boot with JPA + MySQL connection pool initialization consistently takes **45-60 seconds on a cold container start**. With `start_period=30s`, the healthcheck fires before the app is ready, marks the container `unhealthy`, and downstream `depends_on: condition: service_healthy` waits unnecessarily.

| Parameter | Value | Reason |
|---|---|---|
| `--interval=30s` | Check every 30 seconds | Frequent enough for monitoring, not so frequent it causes load |
| `--timeout=10s` | Fail if no response in 10s | 10s is generous for a local actuator ping |
| `--start-period=60s` | Grace period after start | Spring Boot + MySQL JPA cold start takes 45-60s |
| `--retries=3` | 3 consecutive failures = unhealthy | One bad check should not kill the container |

**Why `wget` and not `curl`?** Alpine Linux does not include `curl` in the base image. `wget` is available by default. Using `curl` on an Alpine image would require `RUN apk add --no-cache curl` — adding a layer and a package just for a healthcheck is wasteful.

**`--spider`** — Sends a HEAD request (no body download). Faster than a full GET. Returns 0 if the server responded, non-zero if unreachable.

**`/actuator/health`** — Provided by `spring-boot-starter-actuator` in `pom.xml`. Returns `{"status":"UP"}` when the app is fully started and the database connection is healthy. It is the canonical Spring Boot health endpoint.

---

```dockerfile
ENTRYPOINT ["java",     "-XX:+UseContainerSupport",     "-XX:MaxRAMPercentage=75.0",     "-Djava.security.egd=file:/dev/./urandom",     "-jar", "app.jar"]
```

**`ENTRYPOINT` vs `CMD`:**

| | `ENTRYPOINT` | `CMD` |
|---|---|---|
| Override requires | `--entrypoint` flag (explicit, uncommon) | Passing any argument to `docker run` (easy, accidental) |
| PID 1 in exec form | Yes — JVM is PID 1 | Yes — JVM is PID 1 |
| Shell form risk | Shell becomes PID 1 | Shell becomes PID 1 |
| Best for | Single-purpose containers | Containers with switchable default commands |

This container has one job: run the JAR. `ENTRYPOINT` enforces that. Nobody accidentally overrides it.

**Exec form `["java", ...]` vs shell form `java -jar app.jar`:**

Shell form runs as `/bin/sh -c "java -jar app.jar"` — the shell becomes PID 1, the JVM becomes PID 2. When Docker sends `SIGTERM` during `docker stop`, it goes to PID 1 (the shell). Alpine's `sh` does not forward signals to child processes. The JVM never receives `SIGTERM` and Docker waits the full 10-second timeout before sending `SIGKILL` — no graceful shutdown, in-flight requests are killed.

Exec form runs `java` directly as PID 1. `SIGTERM` goes directly to the JVM, which handles graceful shutdown (Spring Boot `@PreDestroy`, connection pool draining, etc.).

**The three JVM flags — why they are mandatory for containers:**

`-XX:+UseContainerSupport`
: Without this flag, the JVM inspects `/proc/meminfo` to determine available memory — which returns the **host machine's total RAM**, not the container's memory limit. On a 16GB host with a 512MB container limit, the JVM would set a ~4GB heap, triggering OOM kills from the kernel. With this flag, the JVM reads cgroup memory limits and respects them. **This flag is non-negotiable for any JVM running in Docker, Kubernetes, or ECS.**

`-XX:MaxRAMPercentage=75.0`
: Allocates 75% of the container's memory limit to the JVM heap. The remaining 25% is reserved for the OS, JVM metaspace, thread stacks, and native memory. Without this, the JVM uses a conservative default (~25% of container memory) — leaving heap unnecessarily small and causing `OutOfMemoryError` under load.

`-Djava.security.egd=file:/dev/./urandom`
: Java's `SecureRandom` used for session tokens, CSRF tokens, and SSL handshakes defaults to `/dev/random` — a blocking entropy source that can stall for seconds when the entropy pool is low (common in containers with no hardware RNG). Redirecting to `/dev/urandom` (non-blocking, still cryptographically secure for application use) eliminates startup stalls. The `/dev/./urandom` path (with the extra dot) is a workaround for a JVM path-resolution bug on some versions.

---

## The compose.yml — Every Decision Explained

### `name: bankapp`

```yaml
name: bankapp
```

Sets the Compose project name explicitly. Without this, Docker Compose uses the **directory name** as the project prefix — which varies by machine (`java-monolith-app`, `app`, `bankapp-main`, etc.). With `name: bankapp`, all containers, networks, and volumes are always prefixed with `bankapp-` on any machine.

---

### The `db` service

```yaml
db:
  image: mysql:8.4
```

**`mysql:8.4` vs `mysql:8`:**

`mysql:8` is a floating tag — it resolves to whatever MySQL 8.x is latest at pull time. In April 2026, MySQL 8.0 reached End of Life. `mysql:8` could resolve to 8.0 (EOL) on some machines. `mysql:8.4` pins to the current LTS release — explicit, reproducible, and future-safe.

---

```yaml
  env_file: .env
  environment:
    MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}   # redundant — already loaded by env_file
    MYSQL_DATABASE: ${MYSQL_DATABASE}             # redundant — already loaded by env_file
    MYSQL_USER: ${MYSQL_USER}                     # redundant — already loaded by env_file
    MYSQL_PASSWORD: ${MYSQL_PASSWORD}             # redundant — already loaded by env_file
```

**Understanding `env_file` vs `environment`:**

`env_file: .env` loads **every** `KEY=VALUE` line from `.env` and injects all of them into the container's environment automatically. You do not need to re-list them under `environment:`.

The four variables listed under `environment:` are **redundant** — they are already injected by `env_file`. They are kept here **explicitly for documentation purposes only**:

1. **Clarity** — Shows exactly which four variables the official `mysql:8.4` image requires for database initialization
2. **Syntax demonstration** — Shows the `${VAR_NAME}` substitution syntax (reads from `.env` at runtime — no hardcoded values)
3. **Auditability** — Makes it immediately obvious that MySQL receives exactly these four variables and nothing unexpected

In a production compose file you would remove the `environment:` block entirely and keep only `env_file: .env`.

**What MySQL does with these variables on first start:**

| Variable | MySQL action |
|---|---|
| `MYSQL_ROOT_PASSWORD` | Sets the root password |
| `MYSQL_DATABASE` | Creates this database automatically |
| `MYSQL_USER` | Creates this application user |
| `MYSQL_PASSWORD` | Sets the password for `MYSQL_USER` |

> **Important:** MySQL only reads `MYSQL_*` initialization variables on **first startup** when `/var/lib/mysql` is empty. Changing them after the volume is initialized has no effect until you run `docker compose down -v` to destroy the volume.

---

```yaml
  healthcheck:
    test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-uroot", "-p${MYSQL_ROOT_PASSWORD}"]
    interval: 10s
    timeout: 5s
    retries: 5
    start_period: 30s
```

**The `-h localhost` bug that was fixed:**

The previous version of this compose file used `-h db` in the MySQL healthcheck. This is wrong. `db` is the Docker Compose service name — it resolves to the MySQL container's IP **from other containers on the same network**. But this healthcheck runs **inside the MySQL container itself**. Inside the container, `db` is not a valid hostname. The correct hostname for the local MySQL server inside the container is `localhost` or `127.0.0.1`.

With `-h db`, the healthcheck always fails with `Unknown MySQL server host 'db'`. Because `depends_on: condition: service_healthy` in the `web` service waits for the MySQL healthcheck to pass, **the app container would never start** with the broken `-h db` version.

---

### The `web` service

```yaml
web:
  build:
    context: .
    dockerfile: Dockerfile
  image: java-monolith-bankapp
```

**`image: java-monolith-bankapp`** — Gives the built image an explicit name. Without this, the image is named `bankapp-web` (project name + service name) by default. With an explicit name, you can push it directly to a registry (`docker push java-monolith-bankapp`) without re-tagging.

---

```yaml
  env_file: .env
  environment:
    SPRING_DATASOURCE_URL: jdbc:mysql://db:3306/${MYSQL_DATABASE}?useSSL=false&serverTimezone=UTC&allowPublicKeyRetrieval=true
```

**This is the single most important override in the entire compose file.**

`env_file: .env` loads all Spring Boot variables automatically — `SPRING_APPLICATION_NAME`, `SPRING_DATASOURCE_USERNAME`, `SPRING_DATASOURCE_PASSWORD`, `SERVER_PORT`, and everything else. No need to re-list any of them.

The **only** variable that needs an explicit `environment:` override is `SPRING_DATASOURCE_URL`. Here is why:

The `.env` file contains:
```
SPRING_DATASOURCE_URL="jdbc:mysql://localhost:3306/IbtisamIQbankappdb?..."
```

`localhost` is correct when running the app directly on bare metal — MySQL is on the same machine. But in Docker Compose, each service runs in a **separate, isolated container**. Inside the `web` container, `localhost` refers to the `web` container itself — not the `db` container. The `web` container has nothing listening on port 3306. The connection fails immediately.

The correct hostname in Docker Compose is the **service name** — `db`. Docker's internal DNS resolves `db` to the MySQL container's IP on the shared `app-network`.

```
Outside Docker:   app → localhost:3306  (MySQL on same machine)
Inside Compose:   web → db:3306         (MySQL container by service name)
```

This single `environment:` entry overrides the `localhost` URL from `.env` with the correct `db` hostname — only for the Docker Compose environment. The `.env` file itself is left unchanged so it still works for bare-metal development.

**The rule:**
- `env_file` loads everything from `.env` automatically
- `environment:` is only needed when a value from `.env` is **wrong** for Docker and needs to be overridden
- Never re-list variables under `environment:` just because they came from `env_file` — that is redundant noise

---

```yaml
  depends_on:
    db:
      condition: service_healthy
```

**`condition: service_healthy` vs just `depends_on: db`:**

`depends_on: db` (no condition) only waits for the `db` **container to start**. A MySQL container becomes "started" in ~2 seconds, but MySQL itself takes 15-30 seconds to initialize. Spring Boot will try to connect immediately, fail with `Communications link failure`, and crash.

`condition: service_healthy` waits for the `db` healthcheck (`mysqladmin ping`) to return success. That only happens when MySQL is **fully initialized and accepting connections** — exactly when the app needs it.

---

```yaml
  healthcheck:
    start_period: 60s
```

Matches the `HEALTHCHECK --start-period=60s` in the Dockerfile. Spring Boot with JPA + MySQL connection pool on a cold container consistently takes 45-60 seconds. With `start_period=30s`, the first few health checks fire before the app is ready. Those failures count against `retries`, potentially marking the container unhealthy before it has had a chance to fully start.

---

## How `env_file` Works — The Complete Mental Model

```
.env file:
  MYSQL_ROOT_PASSWORD=secret
  MYSQL_DATABASE=bankappdb
  SPRING_DATASOURCE_URL=jdbc:mysql://localhost:3306/bankappdb
  SPRING_DATASOURCE_USERNAME=appuser
  SERVER_PORT=8000
  ...

When env_file: .env is processed:
  → ALL variables injected into container environment automatically
  → No listing required

When environment: is also present:
  → Those entries OVERRIDE the matching values from env_file
  → Variables not in environment: still come from env_file unchanged
  → Variables in environment: that are NOT in env_file are added fresh
```

This is why the `web` service only needs one `environment:` entry — the URL override. Everything else loads correctly from `.env` as-is.

---

## How the Two Files Work Together — End to End

```
docker compose up --build
        │
        ├── Reads compose.yml
        │
        ├── Builds Dockerfile → image: java-monolith-bankapp
        │       Stage 1 (maven:3.9.9-eclipse-temurin-21-alpine):
        │         COPY pom.xml → mvn dependency:go-offline (cached after first run)
        │         COPY src     → mvn clean package -DskipTests
        │         Output: /usr/src/app/target/bankapp-0.0.1-SNAPSHOT.jar
        │
        │       Stage 2 (eclipse-temurin:21-jre-alpine):
        │         Non-root user created (appuser:appgroup)
        │         JAR copied from Stage 1 → renamed to app.jar
        │         JVM flags set for container-aware memory management
        │
        ├── Starts db (mysql:8.4)
        │       Reads MYSQL_* from .env → creates database + user on first start
        │       Healthcheck: mysqladmin ping -h localhost
        │       Status: starting → healthy (after ~30s)
        │
        ├── Waits for db healthcheck to pass (condition: service_healthy)
        │
        └── Starts web (java-monolith-bankapp)
                Reads ALL Spring variables from .env
                SPRING_DATASOURCE_URL overridden to jdbc:mysql://db:3306/...
                JVM starts with UseContainerSupport + MaxRAMPercentage=75.0
                Spring Boot connects to MySQL via service name "db"
                Healthcheck: wget /actuator/health → UP after ~60s
                Serves on port 8000
```

---

## Decision Log — What Was Changed and Why

This Dockerfile and compose.yml went through two iterations. The table below documents every change made and the exact reason.

| Area | v1 (Initial) | v2 (Current) | Why Changed |
|---|---|---|---|
| **Builder base image** | `eclipse-temurin:21-jdk-alpine` + `mvnw` wrapper (3 extra steps) | `maven:3.9.9-eclipse-temurin-21-alpine` | Maven pre-bundled — no wrapper needed, cleaner and more reliable in CI |
| **Dependency pre-cache** | `mvn dependency:resolve` | `mvn dependency:go-offline -B --no-transfer-progress` | `go-offline` downloads plugins too; `-B` and `--no-transfer-progress` clean CI logs |
| **JVM flags** | None — bare `java -jar app.jar` | `-XX:+UseContainerSupport`, `-XX:MaxRAMPercentage=75.0`, `-Djava.security.egd` | Without `UseContainerSupport`, JVM reads host RAM and OOM-kills itself in containers |
| **`chown` scope** | `chown -R appuser:appgroup /app` (recursive) | `chown appuser:appgroup app.jar` (targeted) | Only one file exists — recursive chown is unnecessary overhead |
| **Healthcheck `start_period`** | `30s` — too short | `60s` | Spring Boot + MySQL JPA cold start consistently takes 45-60s |
| **MySQL image tag** | `mysql:8` (floating) | `mysql:8.4` (LTS pinned) | `mysql:8` could resolve to EOL 8.0; `8.4` is explicit and reproducible |
| **MySQL healthcheck host** | `-h db` (**BUG** — service name invalid inside container) | `-h localhost` | `db` only resolves from other containers; inside MySQL container use `localhost` |
| **Datasource URL in Compose** | Not overridden — `.env` value `localhost:3306` used | Overridden to `db:3306` | `localhost` inside `web` container points to `web` itself — MySQL is unreachable |
| **Compose project name** | Not set — used directory name | `name: bankapp` | Consistent naming across all machines regardless of clone directory name |
| **`image:` field in `web`** | Not set | `image: java-monolith-bankapp` | Explicit image name enables direct registry push without re-tagging |
| **Redundant `environment:` in `db`** | Fully expanded (non-redundant per old structure) | Kept with inline comments explaining redundancy | `env_file` already loads them — documented for clarity only, not functional need |

---

## Common Mistakes Reference

| Mistake | What Breaks | Correct Approach |
|---|---|---|
| `COPY . .` before dependency resolution | Maven re-downloads all dependencies on every source change | Copy `pom.xml` first, resolve deps, then copy `src/` |
| `dependency:resolve` instead of `dependency:go-offline` | Build plugins not cached, network calls during `package` | Use `dependency:go-offline` |
| Using `jdk` image in runtime stage | Image 3× larger, unnecessary attack surface, more CVEs | Always use `jre-alpine` for the runtime stage |
| Not creating non-root user | Trivy CRITICAL finding, fails Kubernetes `PodSecurityAdmission` | `addgroup` + `adduser` before `USER` |
| `chown` after `USER appuser` | `Permission denied` — non-root cannot change file ownership | Always `chown` before switching `USER` |
| Shell form `CMD java -jar app.jar` | JVM becomes PID 2, `SIGTERM` not forwarded, no graceful shutdown | Use exec form `ENTRYPOINT ["java", "-jar", "app.jar"]` |
| No JVM container flags | JVM reads host RAM, over-allocates heap, OOM killed by kernel | Always add `-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0` |
| `depends_on: db` without `condition` | Web starts before MySQL is ready, immediate connection failure | Use `condition: service_healthy` |
| `-h db` in MySQL healthcheck | Healthcheck always fails, `web` service never starts | Use `-h localhost` — service name is invalid inside the container |
| `SPRING_DATASOURCE_URL` with `localhost` in Compose | `localhost` inside `web` container = `web` itself — MySQL unreachable | Override URL to use `db:3306` (service name) |
| `docker compose down` loses DB data | `/var/lib/mysql` is inside the container — destroyed on `down` | Always mount `/var/lib/mysql` to a named volume |
| Using `curl` in Alpine healthcheck | `curl` not in Alpine base image — command not found | Use `wget --spider` (available by default in Alpine) |
| Floating `mysql:8` tag | May resolve to EOL 8.0 depending on when image is pulled | Pin to `mysql:8.4` (current LTS) |
