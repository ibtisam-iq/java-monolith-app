# How to Dockerize a Java Spring Boot Application

This document explains **every line** of the `Dockerfile` and `compose.yml` in this project — not just what it does, but **why it is written that way**, what breaks if you change it, and what you must understand before writing your own.

---

## Before You Write a Single Line

You must answer these from `pom.xml` and `application.properties` first (see `understand-architecture.md`):

| Question | Answer for This Project |
|---|---|
| Build tool? | Maven (`pom.xml` exists) |
| Java version? | 21 (`<java.version>21</java.version>`) |
| JAR filename? | `target/bankapp-0.0.1-SNAPSHOT.jar` |
| Database? | MySQL (`mysql-connector-j` in `pom.xml`) |
| App port? | 8000 (`SERVER_PORT=8000` in `.env.example`) |
| Health endpoint? | `/actuator/health` (`spring-boot-starter-actuator` in `pom.xml`) |
| Env vars or hardcoded? | All env vars (`${...}` in `application.properties`) |

Only after answering all of these do you start writing Docker files.

---

## The Dockerfile — Line by Line

```dockerfile
# ============================================================
# Stage 1 — Build
# ============================================================
FROM maven:3.9.9-eclipse-temurin-21-alpine AS builder
```

**Why this image?**
- `maven:3.9.9` — Maven 3.9.9 is bundled. You do not need to install Maven separately.
- `eclipse-temurin-21` — Java 21 JDK is included. Matches `<java.version>21</java.version>` in `pom.xml`. If this version mismatches, the build fails.
- `alpine` — Alpine Linux base. Minimal OS. Smaller image than `slim` or `jammy` variants.
- `AS builder` — Names this stage `builder`. The second stage will reference this name to copy files from it.

> **What happens if you use Java 17 here?** The build compiles fine (backward compat), but the runtime stage must also be Java 17+. The real issue: if `pom.xml` sets `<java.version>21</java.version>`, Maven enforces it and the compile step will fail with a version mismatch error.

---

```dockerfile
WORKDIR /usr/src/app
```

**Why?** Sets the working directory inside the container. All subsequent `COPY`, `RUN`, `CMD` instructions operate relative to this path. If the directory doesn't exist, Docker creates it.

> Without `WORKDIR`, files land in `/` (root) — messy and insecure.

---

```dockerfile
COPY pom.xml .
```

**Why copy `pom.xml` first, separately from `src/`?**

This is the most important caching trick in Java Dockerization. Docker builds in layers. Each instruction is a layer. Layers are cached.

```
Layer 1: FROM maven image          ← cached forever
Layer 2: WORKDIR                   ← cached forever
Layer 3: COPY pom.xml .            ← only invalidated if pom.xml changes
Layer 4: RUN mvn dependency:resolve ← only re-runs if pom.xml changes
Layer 5: COPY src ./src            ← invalidated on any source code change
Layer 6: RUN mvn package           ← re-runs on any source code change
```

**The result:** When you change Java code (which happens constantly), only Layers 5 and 6 re-run. Dependencies are NOT re-downloaded. Build time drops from ~3 minutes to ~15 seconds.

> **What happens if you do `COPY . .` instead?** Every source change invalidates the dependency layer. Maven re-downloads all dependencies every build. Slow, wasteful, breaks CI/CD cache.

---

```dockerfile
RUN mvn dependency:resolve
```

**Why?** Downloads and caches all Maven dependencies declared in `pom.xml` into the local Maven repository (`~/.m2`). This is the layer that takes 2-3 minutes the first time. After that, it's cached — as long as `pom.xml` doesn't change.

> `dependency:resolve` only resolves. It does not compile. That happens next.

---

```dockerfile
COPY src ./src
RUN mvn clean package -DskipTests
```

**`COPY src ./src`** — Now copies the actual Java source code. This layer is invalidated on every code change — that's intentional and correct.

**`mvn clean package`** — Compiles the source, runs the Maven build lifecycle, produces the JAR at `target/bankapp-0.0.1-SNAPSHOT.jar`.

**`-DskipTests`** — Skips test execution during the Docker build. Tests are run separately in CI (SonarQube, JaCoCo pipeline step). Running them inside Docker adds time and requires a DB connection that doesn't exist at build time.

> **Output location:** `target/bankapp-0.0.1-SNAPSHOT.jar` — inside the builder container at `/usr/src/app/target/`.

---

```dockerfile
# ============================================================
# Stage 2 — Production Runtime
# ============================================================
FROM eclipse-temurin:21-jre-alpine
```

**Why a second stage?** The builder stage has Maven, the JDK, source code, test classes, and Maven's local repository (`~/.m2` with hundreds of MB of downloaded JARs). None of that belongs in production.

The runtime stage starts completely fresh — a clean image with **only** the JRE and the final JAR.

**`eclipse-temurin:21-jre-alpine`:**
- `eclipse-temurin` — Adoptium's OpenJDK distribution. Industry standard for production containers.
- `21` — Must match the Java version used in the build stage.
- `jre` — Java Runtime Environment only. No compiler (`javac`), no JDK tools. Production containers never need to compile.
- `alpine` — Minimal Linux. Smaller attack surface. Fewer CVEs flagged by Trivy.

> **JDK vs JRE:** JDK = JRE + compiler + dev tools. For running a JAR, you only need the JRE. Using JDK in production is like shipping a factory with every car you sell.

---

```dockerfile
LABEL maintainer="github.com/ibtisam-iq" \
      org.opencontainers.image.title="BankApp" \
      org.opencontainers.image.description="Banking Web Application" \
      org.opencontainers.image.licenses="MIT"
```

**Why?** OCI (Open Container Initiative) standard labels. Visible in `docker inspect`, DockerHub, and artifact registries. Required for professional/portfolio images. Does not affect runtime behavior.

---

```dockerfile
WORKDIR /usr/src/app
```

Same as Stage 1 — sets working directory in the runtime container.

---

```dockerfile
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
```

**Why?** Security hardening. By default, Docker containers run as `root`. Running as root inside a container is:
- A **critical vulnerability** flagged by Trivy (and fails many security scans)
- Rejected by Kubernetes `PodSecurityPolicy` / `PodSecurityAdmission` in hardened clusters
- A risk if the container escapes — the process has root on the host

`addgroup -S appgroup` — Creates a system group (`-S` = system, no home directory, no login shell).
`adduser -S appuser -G appgroup` — Creates a system user belonging to that group.

> This is Alpine syntax. On Debian/Ubuntu images it would be: `RUN groupadd -r appgroup && useradd -r -g appgroup appuser`

---

```dockerfile
COPY --from=builder /usr/src/app/target/*.jar app.jar
```

**`--from=builder`** — Copies from the build stage (named `builder` in Stage 1), not from the host machine. This is multi-stage build in action.

**`target/*.jar`** — Wildcard matches the JAR regardless of version number. More robust than hardcoding `bankapp-0.0.1-SNAPSHOT.jar`.

**`app.jar`** — Renames to a simple, fixed name. The `ENTRYPOINT` below then references `app.jar` — it never changes even when the version bumps.

---

```dockerfile
RUN chown appuser:appgroup app.jar
```

**Why before `USER appuser`?** Ownership must be set while still running as `root`. Once you switch to `appuser`, you no longer have permission to `chown` files. Order matters:
1. Create user (root can do this)
2. Copy file (as root)
3. `chown` to new user (root can do this)
4. Switch to new user (`USER appuser`)
5. From here on, everything runs as `appuser`

---

```dockerfile
USER appuser
```

All subsequent instructions — including `ENTRYPOINT` — run as `appuser`, not root.

---

```dockerfile
EXPOSE 8000
```

**What this does:** Documents that the container listens on port 8000. It does **not** actually publish the port — that's done in `compose.yml` with `ports: "8000:8000"` or `docker run -p 8000:8000`.

**Why 8000?** Because `application.properties` has `server.port=${SERVER_PORT}` and `.env.example` sets `SERVER_PORT=8000`.

> `EXPOSE` is documentation. It does not open firewall rules. It does not bind anything. It is read by `docker-compose` and `docker run -P` for automatic port mapping.

---

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD wget -qO- http://localhost:8000/actuator/health || exit 1
```

**Why a HEALTHCHECK?** Docker needs to know if the container is actually working, not just running. A container can be "running" but the JVM could be stuck in startup or the DB connection could have failed.

**`--interval=30s`** — Check every 30 seconds.
**`--timeout=5s`** — If the check takes more than 5s, it counts as failed.
**`--start-period=30s`** — Grace period after container starts. Spring Boot takes 10-20 seconds to initialize. Without this, the first few checks would fail and Docker would mark the container unhealthy immediately.
**`--retries=3`** — Must fail 3 consecutive times before Docker marks it `unhealthy`.

**`wget -qO-`** — Sends an HTTP GET request and prints the response body. `-q` = quiet (no progress), `-O-` = output to stdout.
**`|| exit 1`** — If `wget` fails (non-zero exit), return exit code 1. Docker interprets non-zero as unhealthy.

**Why `wget` and not `curl`?** Alpine Linux does not include `curl` by default. `wget` is available in the base Alpine image without any additional installation.

**Why `/actuator/health`?** This endpoint is provided by `spring-boot-starter-actuator` and returns `{"status":"UP"}` when the app is healthy (DB connected, app running). It is the canonical health check endpoint for Spring Boot. Requires `management.endpoints.web.exposure.include=health` in `application.properties`.

---

```dockerfile
ENTRYPOINT ["java", "-jar", "app.jar"]
```

**Why `ENTRYPOINT` and not `CMD`?**

| | `ENTRYPOINT` | `CMD` |
|---|---|---|
| Can be overridden? | Only with `--entrypoint` flag | Yes, by passing args to `docker run` |
| Typical use | Fixed command for the container's purpose | Default args, easily overridden |
| For single-purpose containers | ✅ Preferred | ❌ Too easy to accidentally override |

This container has one job: run the JAR. `ENTRYPOINT` enforces that.

**exec form `["java", "-jar", "app.jar"]`** — Runs `java` directly as PID 1. No shell wrapper. This means `SIGTERM` from Docker (during `docker stop`) goes directly to the JVM, which handles graceful shutdown correctly.

> Shell form `CMD java -jar app.jar` runs as `/bin/sh -c "java -jar app.jar"` — the JVM becomes PID 2, `SIGTERM` goes to the shell (PID 1) which may not pass it to the JVM, causing forced kills and no graceful shutdown.

---

## The compose.yml — Line by Line

```yaml
services:
  web:
    build:
      context: .               # Build context = java-monolith-app/ root
      dockerfile: Dockerfile   # Dockerfile to use (relative to context)
```

**`context: .`** — The folder Docker sends to the daemon as the build context. Everything `COPY` can access must be inside this folder. Set to `.` (project root) because `COPY pom.xml .` and `COPY src ./src` both need the root.

**`dockerfile: Dockerfile`** — Explicitly names the Dockerfile. Optional when it's named `Dockerfile` at the context root, but explicit is better.

---

```yaml
    image: java-monolith-bankapp
    container_name: bank-web
    restart: unless-stopped
```

**`image: java-monolith-bankapp`** — Tags the built image with this name. You can then push this exact name to DockerHub or ECR.

**`container_name: bank-web`** — Gives the container a fixed name instead of the auto-generated `java-monolith-app-web-1`. Useful for `docker logs bank-web`, `docker exec bank-web sh`, etc.

**`restart: unless-stopped`** — Auto-restarts the container if it crashes. Respects manual `docker compose stop` (does not restart after that). Alternative: `always` (restarts even after manual stop), `no` (never restarts).

---

```yaml
    ports:
      - "8000:8000"
```

**Format: `"host_port:container_port"`**
- Left (`8000`) — Port on your machine (or EC2 host)
- Right (`8000`) — Port inside the container (what `EXPOSE 8000` documented)

Access the app at `http://localhost:8000` (locally) or `http://<EC2-IP>:8000` (on AWS).

---

```yaml
    env_file:
      - .env
```

**Why `env_file` and not `environment:`?** `env_file` loads all variables from `.env` without listing them one by one. Cleaner, and the `.env` file is gitignored — credentials never touch the compose file.

> `.env` file path is relative to the `compose.yml` file location.

---

```yaml
    depends_on:
      db:
        condition: service_healthy
```

**Why this matters:** Without this, both containers start simultaneously. Spring Boot takes ~5 seconds to start and immediately tries to connect to MySQL. MySQL takes ~15-20 seconds to initialize on first run. Result: Spring Boot fails with `Communications link failure` and exits.

**`condition: service_healthy`** — Docker waits until the `db` service passes its `healthcheck` before starting `web`. MySQL's healthcheck (`mysqladmin ping`) only succeeds when MySQL is fully initialized and accepting connections.

> `depends_on` without `condition:` (just `depends_on: db`) only waits for the container to **start**, not for MySQL to be **ready**. That's useless for this purpose.

---

```yaml
    networks:
      - app-network
```

**Why a custom network?** By default, Docker Compose puts all services on the default bridge network. That works, but:
- Custom networks enable DNS resolution by service name (`db`, `web`)
- `SPRING_DATASOURCE_URL` uses `db` as the hostname: `jdbc:mysql://db:3306/...`
- Inside the `web` container, `db` resolves to the MySQL container's IP automatically

> Without the custom network, service name DNS still works on the default Compose network — but explicit networks are a best practice for production and multi-compose setups.

---

```yaml
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:8000/actuator/health"]
      interval: 30s
      timeout: 10s
      start_period: 30s
      retries: 3
```

This is the **Compose-level health check** for the `web` service. It mirrors the `HEALTHCHECK` in the Dockerfile. Both serve the same purpose but at different layers:

| Location | Purpose |
|---|---|
| `Dockerfile HEALTHCHECK` | Docker daemon monitors the container at all times (even outside Compose) |
| `compose.yml healthcheck` | Compose uses this for `depends_on: condition: service_healthy` from other services |

---

```yaml
  db:
    image: mysql:8
    container_name: mysql-db
    restart: unless-stopped
    env_file:
      - .env
```

**`image: mysql:8`** — Official MySQL 8 image from DockerHub. No build step — it's pulled directly.

**Why does the `db` service also use `env_file: .env`?** The official `mysql:8` image reads these specific variables on **first startup** to initialize the database:

| Variable | What MySQL Does With It |
|---|---|
| `MYSQL_ROOT_PASSWORD` | Sets the root password |
| `MYSQL_DATABASE` | Creates this database automatically |
| `MYSQL_USER` | Creates this user |
| `MYSQL_PASSWORD` | Sets the password for `MYSQL_USER` |

These are the same values referenced by `SPRING_DATASOURCE_USERNAME`, `SPRING_DATASOURCE_PASSWORD`, etc. That's why both services share the `.env` file — the variables overlap intentionally.

> **Important:** MySQL only reads `MYSQL_*` variables on first startup (when the data volume is empty). Changing them after the volume is initialized has no effect until you `docker compose down -v` and restart.

---

```yaml
    volumes:
      - mysql_data:/var/lib/mysql
```

**Why?** MySQL stores all database files in `/var/lib/mysql` inside the container. Without a volume, every `docker compose down` destroys all your data.

**`mysql_data`** — A named Docker volume. Docker manages it outside the container lifecycle. Data persists across:
- `docker compose down` (container removed, volume survives)
- Container restarts
- Image updates

> `docker compose down -v` removes both containers AND volumes. Use this to completely reset the database.

---

```yaml
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-uroot", "-p$MYSQL_ROOT_PASSWORD"]
      interval: 30s
      timeout: 10s
      start_period: 20s
      retries: 3
```

**`mysqladmin ping`** — A MySQL CLI tool that checks if the MySQL server is accepting connections. Returns exit 0 if MySQL is up, non-zero if not.

**`-h localhost`** — Inside the MySQL container, the server listens on `localhost`. Do NOT use `-h db` here — `db` is the Docker service name, which resolves from other containers, not from inside the MySQL container itself.

**`-uroot -p$MYSQL_ROOT_PASSWORD`** — Authenticates as root. `$MYSQL_ROOT_PASSWORD` is expanded from the environment (loaded via `env_file`).

**`start_period: 20s`** — MySQL takes ~15-20 seconds to initialize on first run (creating system tables, setting up the database). Failures during this grace period don't count against `retries`.

---

```yaml
networks:
  app-network:
    driver: bridge

volumes:
  mysql_data:
```

**`networks: app-network: driver: bridge`** — Declares the custom network. `bridge` is the standard Docker network driver for single-host communication between containers.

**`volumes: mysql_data:`** — Declares the named volume at the top level. Without this declaration, the volume reference under `db` would fail.

---

## How the Two Files Work Together

```
docker compose up --build
        │
        ├── Reads compose.yml
        │
        ├── Builds Dockerfile → produces image: java-monolith-bankapp
        │       Stage 1: Maven compiles → produces target/*.jar
        │       Stage 2: JRE image + JAR only
        │
        ├── Starts db container (mysql:8)
        │       Reads MYSQL_* from .env → initializes database
        │       Healthcheck: mysqladmin ping
        │
        ├── Waits for db to be healthy (depends_on: service_healthy)
        │
        └── Starts web container
                Reads SPRING_* from .env → Spring Boot connects to mysql://db:3306
                Healthcheck: wget /actuator/health
                Serves on port 8000
```

---

## Common Mistakes and Why They Fail

| Mistake | What Breaks | Fix |
|---|---|---|
| `COPY . .` before `mvn dependency:resolve` | Dependencies re-downloaded on every source change | Copy `pom.xml` first, then source |
| Using JDK image in runtime stage | Image 3x larger, unnecessary tools in production | Use `jre-alpine` for runtime |
| Not creating non-root user | Trivy critical vulnerability, fails K8s security policy | `adduser` before `USER` |
| `chown` after `USER appuser` | Permission denied — non-root can't chown | Always `chown` before `USER` |
| Shell form `CMD java -jar app.jar` | JVM doesn't receive `SIGTERM`, no graceful shutdown | Use exec form `ENTRYPOINT ["java", "-jar", "app.jar"]` |
| `depends_on: db` without `condition` | Web starts before MySQL is ready, connection refused | Use `condition: service_healthy` |
| `-h db` in MySQL healthcheck | `db` doesn't resolve inside MySQL container | Use `-h localhost` |
| `SPRING_DATASOURCE_URL` with `localhost` in Docker | `localhost` inside `web` container = `web` itself, not MySQL | Use `db` (service name) as hostname |
| `docker compose down` loses DB data | Volume not declared | Always mount `/var/lib/mysql` to a named volume |
