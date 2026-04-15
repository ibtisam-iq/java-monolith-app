# Understanding `application.properties`

This file lives at `src/main/resources/application.properties`. It is Spring Boot's **central configuration file** — the single place where you tell the application how to connect to the database, what port to run on, what features to enable, and how to behave at runtime.

Spring Boot reads this file automatically at startup. You do not import it. You do not register it anywhere. It just has to exist at that exact path.

---

## What Are the Major Categories Inside It?

Every property in `application.properties` belongs to one of these groups:

| Category | Prefix | What It Controls |
|---|---|---|
| Application identity | `spring.application.name` | The name shown in logs and monitoring tools |
| Database connection | `spring.datasource.*` | URL, username, password, driver class |
| JPA / Hibernate | `spring.jpa.*` | Schema management, SQL dialect, SQL logging |
| H2 console | `spring.h2.*` | In-browser database UI (H2 only) |
| Thymeleaf | `spring.thymeleaf.*` | Template caching behavior |
| Server | `server.port` | Which port the app listens on |
| Actuator | `management.endpoints.*` | Health check and monitoring endpoints |
| Init mode | `spring.sql.init.*` | Whether to run SQL scripts at startup |

---

## Starting Point: What H2 Looks Like

Many Spring Boot projects start with H2 — an in-memory database that requires zero setup. This is what `application.properties` looks like in an H2-based project:

```properties
spring.application.name=twitter-app
spring.datasource.url=jdbc:h2:mem:twitterapp
spring.datasource.driverClassName=org.h2.Driver
spring.datasource.username=sa
spring.datasource.password=password
spring.jpa.database-platform=org.hibernate.dialect.H2Dialect
spring.h2.console.enabled=true
spring.h2.console.path=/h2-console
spring.thymeleaf.cache=false
```

### What Is H2?

H2 is a database written entirely in Java. It runs **inside the JVM process** of your Spring Boot application. No separate database server. No installation. No Docker container.

**The critical tradeoff:** Because it runs in memory (`mem:`), all data is destroyed the moment the application stops. Every restart = empty database.

| Aspect | H2 | MySQL |
|---|---|---|
| Where it runs | Inside the JVM (in memory) | Separate server or container |
| Setup required | None | Install MySQL or run Docker container |
| Data persistence | Lost on app stop | Persists on disk |
| Good for | Local development, unit tests | Production, Docker, CI/CD |
| Separate container in Docker? | No | Yes |
| Real credentials needed? | No (`sa`/`password` are dummy defaults) | Yes |

### H2 Property by Property

**`spring.datasource.url=jdbc:h2:mem:twitterapp`**

Breaking down the URL:

| Part | Meaning |
|---|---|
| `jdbc:` | Java's standard database connection protocol |
| `h2:` | Database type is H2 |
| `mem:` | Runs in memory (RAM only, not on disk) |
| `twitterapp` | The name given to this in-memory database |

> For a file-based H2 (persists to disk): `jdbc:h2:file:/data/twitterapp`  
> For MySQL: `jdbc:mysql://hostname:3306/databasename?params`

**`spring.datasource.driverClassName=org.h2.Driver`**

Tells Spring Boot which JDBC driver class to load. This class comes from the H2 JAR declared in `pom.xml`:
```xml
<dependency>
    <groupId>com.h2database</groupId>
    <artifactId>h2</artifactId>
    <scope>runtime</scope>
</dependency>
```
`scope: runtime` — this JAR is not needed to compile the code, only to run it.

**`spring.datasource.username=sa` / `spring.datasource.password=password`**

H2's built-in default credentials. `sa` = System Administrator. These are not real credentials — H2 accepts them out of the box. You do not create any MySQL user or set any password anywhere.

**`spring.jpa.database-platform=org.hibernate.dialect.H2Dialect`**

Tells Hibernate which SQL dialect (flavor of SQL) to use when generating queries internally. H2 and MySQL use slightly different SQL syntax — wrong dialect = SQL errors at runtime.

**`spring.h2.console.enabled=true` and `spring.h2.console.path=/h2-console`**

Enables a browser-based GUI to query the H2 database. Open `http://localhost:8080/h2-console` while the app is running to browse tables, run SQL, and inspect data.

> **H2-only.** Remove both properties entirely when switching to MySQL.

---

## This Project's `application.properties` — Line by Line

This is the actual `application.properties` in `java-monolith-app`. H2 is gone. MySQL is in. All sensitive values are environment variables:

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

---

### `spring.application.name=${SPRING_APPLICATION_NAME}`

**What it does:** Sets the application's name. Appears in:
- Log output: `[IbtisamIQBankApp] Started BankappApplication in 4.3 seconds`
- Spring Cloud service registry (if used)
- Monitoring dashboards (Grafana, Prometheus, Datadog)

**Why `${...}` instead of a hardcoded name?** In this project, every configurable value is moved to environment variables for consistency. Even the app name. This way `.env` is the single source of truth for all configuration.

---

### `spring.datasource.url=${SPRING_DATASOURCE_URL}`

**What it does:** The full address of the database server. Spring Boot passes this to the JDBC driver, which opens the actual TCP connection.

**The MySQL JDBC URL format:**
```
jdbc:mysql://<hostname>:<port>/<database_name>?<parameters>
```

| Part | Local run | Docker Compose |
|---|---|---|
| `hostname` | `localhost` | `db` (MySQL service name in `compose.yml`) |
| `port` | `3306` | `3306` |
| `database_name` | Your DB name | Must match `MYSQL_DATABASE` in `.env` |

**Full value used in this project's `.env`:**
```
SPRING_DATASOURCE_URL=jdbc:mysql://db:3306/IbtisamIQbankappdb?useSSL=false&serverTimezone=UTC&allowPublicKeyRetrieval=true
```

**Query parameters explained:**

| Parameter | Why It's There |
|---|---|
| `useSSL=false` | Disables SSL for local/Docker connections. Without it, MySQL 8 throws SSL handshake errors. |
| `serverTimezone=UTC` | MySQL 8 requires an explicit timezone. Without it, Spring Boot throws `InvalidConnectionAttributeException` at startup. |
| `allowPublicKeyRetrieval=true` | Required for MySQL 8 with password authentication over non-SSL. Without it, `RSA public key is not available` error. |

> **Why `db` and not `localhost`?** Inside the `web` container, `localhost` refers to the web container itself — not MySQL. `db` is the MySQL service name in `compose.yml`, which Docker resolves to the MySQL container's IP via its internal DNS.

---

### `spring.datasource.driver-class-name=com.mysql.cj.jdbc.Driver`

**What it does:** Tells Spring Boot which JDBC driver class to load to communicate with MySQL.

This class comes from the `mysql-connector-j` JAR in `pom.xml`:
```xml
<dependency>
    <groupId>com.mysql</groupId>
    <artifactId>mysql-connector-j</artifactId>
    <scope>runtime</scope>
</dependency>
```

**Different databases, different drivers:**

| Database | Driver Class | Maven Dependency |
|---|---|---|
| H2 | `org.h2.Driver` | `com.h2database:h2` |
| MySQL | `com.mysql.cj.jdbc.Driver` | `com.mysql:mysql-connector-j` |
| PostgreSQL | `org.postgresql.Driver` | `org.postgresql:postgresql` |
| MariaDB | `org.mariadb.jdbc.Driver` | `org.mariadb.jdbc:mariadb-java-client` |

> **If you change the database, you must change BOTH this property AND the dependency in `pom.xml`.** If the JAR is missing, Spring Boot throws `ClassNotFoundException` at startup.

---

### `spring.datasource.username` and `spring.datasource.password`

**What they do:** Credentials Spring Boot uses to authenticate with MySQL.

In this project:
```properties
spring.datasource.username=${SPRING_DATASOURCE_USERNAME}
spring.datasource.password=${SPRING_DATASOURCE_PASSWORD}
```

The values come from `.env`:
```env
SPRING_DATASOURCE_USERNAME=your_db_user
SPRING_DATASOURCE_PASSWORD=your_db_password
```

These must match the MySQL user created inside the MySQL container. The MySQL container reads:
```env
MYSQL_USER=your_db_user
MYSQL_PASSWORD=your_db_password
```

Both sides use the same values from the same `.env` file — one side creates the MySQL user, the other side connects with it.

---

### `spring.jpa.hibernate.ddl-auto=update`

**What it does:** Controls whether Hibernate automatically creates or modifies the database schema (tables, columns, indexes) at application startup.

| Value | What Hibernate Does | Use When |
|---|---|---|
| `none` | Does nothing. Schema must exist manually. | Production with migrations (Flyway/Liquibase) |
| `validate` | Verifies schema matches entity classes. Fails if not. | Production safety check |
| `update` | Creates missing tables. Adds missing columns. Never deletes data. | Development and Docker |
| `create` | Drops and recreates entire schema every startup. All data lost. | Never in production |
| `create-drop` | Creates schema on start, drops it on shutdown. | H2 dev/test only |

**H2 default is `create-drop`** — which is fine because H2 data is already lost on every restart anyway. MySQL default without this property is `none` — no tables get created and the app immediately fails with `Table not found`.

**`update` is the right choice here** because:
- On first startup with an empty MySQL database, Hibernate creates all the tables
- On subsequent startups, it checks what's new and only adds missing columns
- It never drops tables or deletes rows

> **Never use `create` or `create-drop` with MySQL in production.** Your entire database gets wiped on every restart.

---

### `spring.jpa.database-platform=org.hibernate.dialect.MySQLDialect`

**What it does:** Tells Hibernate which SQL dialect to generate when building queries internally.

Hibernate does not write raw SQL — it builds SQL programmatically. Different databases use different SQL syntax. The dialect translates Hibernate's internal query representation into the correct SQL for your database.

**Wrong dialect = wrong SQL = runtime errors**, even if the JDBC connection succeeds.

| Database | Correct Dialect |
|---|---|
| H2 | `org.hibernate.dialect.H2Dialect` |
| MySQL 8+ | `org.hibernate.dialect.MySQLDialect` |
| PostgreSQL | `org.hibernate.dialect.PostgreSQLDialect` |

---

### `spring.jpa.show-sql=false`

**What it does:** Controls whether Hibernate prints every SQL statement it executes to the console/log.

- `true` — every `SELECT`, `INSERT`, `UPDATE`, `DELETE` Hibernate runs is printed. Useful for debugging.
- `false` — silent. Correct for production and Docker. A busy app generates thousands of SQL lines per minute.

---

### `spring.datasource.initialization-mode=always` and `spring.sql.init.mode=always`

**What they do:** These two properties ensure Spring Boot's SQL initialization scripts (if any exist in `src/main/resources/`) run every time the app starts.

**Why are both present?**
- `spring.datasource.initialization-mode` is the Spring Boot 2.x property
- `spring.sql.init.mode` is the Spring Boot 3.x replacement
- Both are included for compatibility across versions

**The real reason this is here:** Even without SQL scripts, these properties help ensure the datasource connection is fully validated at startup. Combined with `depends_on: condition: service_healthy` in `compose.yml`, this prevents Spring Boot from starting before MySQL is truly ready.

---

### `management.endpoints.web.exposure.include=health`

**What it does:** Enables Spring Boot Actuator's `/actuator/health` HTTP endpoint.

**Spring Boot Actuator** is a library (`spring-boot-starter-actuator` in `pom.xml`) that exposes operational endpoints about the running application.

**`/actuator/health`** returns:
```json
{"status": "UP"}
```
...when the application is healthy (DB connected, app running). Returns `DOWN` or error details otherwise.

**Why this matters for Docker:**
- The `HEALTHCHECK` in `Dockerfile` calls `wget -qO- http://localhost:8000/actuator/health`
- The `healthcheck:` in `compose.yml` does the same
- Without this property, the endpoint returns 404, health check always fails, and Docker marks the container as unhealthy

**`include=health`** — exposes only the `/health` endpoint. Other Actuator endpoints (like `/actuator/env` which exposes all environment variables including secrets) are kept hidden.

---

### `server.port=${SERVER_PORT}`

**What it does:** Sets which TCP port the Spring Boot embedded server (Tomcat) listens on.

Default without this property is `8080`. This project uses `8000` (set via `SERVER_PORT=8000` in `.env`).

**Must be consistent across three places:**

| File | Where Port Appears |
|---|---|
| `.env` | `SERVER_PORT=8000` |
| `compose.yml` | `ports: "8000:8000"` |
| `Dockerfile` | `EXPOSE 8000` and `HEALTHCHECK ... http://localhost:8000/actuator/health` |

If these are out of sync, either the container port mapping is wrong or the health check hits the wrong port and always fails.

---

## What `${...}` Means and Where the Values Come From

When you write `${VARIABLE_NAME}` in `application.properties`, Spring Boot does **not** look inside this file for that value. It looks in the **environment** — the set of key-value pairs injected into the process at startup.

**If the variable is not set**, Spring Boot throws at startup:
```
Could not resolve placeholder 'SPRING_DATASOURCE_URL' in value "${SPRING_DATASOURCE_URL}"
```
The application refuses to start. This is intentional — fail loudly at startup rather than silently use a wrong or missing database.

**Where the environment comes from depending on how you run the app:**

| Run Method | How to Provide Variables |
|---|---|
| `docker compose up` | `env_file: .env` in `compose.yml` |
| `docker run` | `-e SPRING_DATASOURCE_URL=...` flags |
| Kubernetes | `envFrom: secretRef` or `configMapRef` in Pod spec |
| Local terminal | `export SPRING_DATASOURCE_URL=...` before running |
| IDE (IntelliJ/VS Code) | Run Configuration → Environment Variables section |

---

## Full Migration: H2 → MySQL + Environment Variables

This is the complete set of changes made to convert this project from H2 to production-ready MySQL.

### Change 1 — `pom.xml`

```xml
<!-- Remove this -->
<dependency>
    <groupId>com.h2database</groupId>
    <artifactId>h2</artifactId>
    <scope>runtime</scope>
</dependency>

<!-- Add this -->
<dependency>
    <groupId>com.mysql</groupId>
    <artifactId>mysql-connector-j</artifactId>
    <scope>runtime</scope>
</dependency>
```

### Change 2 — `application.properties` (before vs after)

| Property | H2 (before) | MySQL (after) | Why |
|---|---|---|---|
| `datasource.url` | `jdbc:h2:mem:twitterapp` | `${SPRING_DATASOURCE_URL}` | External server; moved to env var |
| `driverClassName` | `org.h2.Driver` | `com.mysql.cj.jdbc.Driver` | Different driver per database |
| `datasource.username` | `sa` | `${SPRING_DATASOURCE_USERNAME}` | Real credentials; never hardcode |
| `datasource.password` | `password` | `${SPRING_DATASOURCE_PASSWORD}` | Real credentials; never hardcode |
| `database-platform` | `H2Dialect` | `MySQLDialect` | Different SQL syntax per database |
| `ddl-auto` | *(not set, defaults to `create-drop`)* | `update` | H2 resets data anyway; MySQL must persist |
| `show-sql` | *(not set)* | `false` | Suppress SQL noise in production logs |
| `h2.console.enabled` | `true` | *(removed)* | H2-only; irrelevant for MySQL |
| `h2.console.path` | `/h2-console` | *(removed)* | H2-only; irrelevant for MySQL |
| `server.port` | *(not set, default 8080)* | `${SERVER_PORT}` | Explicit and configurable via env |
| `management.endpoints...` | *(not set)* | `include=health` | Required for Docker health checks |

### Change 3 — Does Any Java Code Change?

**No.** The entity classes, repositories, service classes, and controllers do not reference the database type anywhere. That is the entire point of JPA — your Java code is database-agnostic.

The one thing to verify in entity classes:

```java
@Id
@GeneratedValue(strategy = GenerationType.IDENTITY)
private Long id;
```

`GenerationType.IDENTITY` uses the database's native auto-increment — works identically for both H2 and MySQL. If you see `GenerationType.SEQUENCE`, change it to `IDENTITY` because MySQL does not support Oracle-style sequences.

---

## Complete `.env` File Reference

```env
# Spring Boot application config
SPRING_APPLICATION_NAME=IbtisamIQBankApp
SPRING_DATASOURCE_URL=jdbc:mysql://db:3306/IbtisamIQbankappdb?useSSL=false&serverTimezone=UTC&allowPublicKeyRetrieval=true
SPRING_DATASOURCE_USERNAME=your_db_user
SPRING_DATASOURCE_PASSWORD=your_db_password
SERVER_PORT=8000

# MySQL container initialization (read by mysql:8 Docker image on first startup)
MYSQL_ROOT_PASSWORD=your_root_password
MYSQL_DATABASE=IbtisamIQbankappdb
MYSQL_USER=your_db_user
MYSQL_PASSWORD=your_db_password
```

**Critical relationships:**
- `MYSQL_DATABASE` must match the database name in `SPRING_DATASOURCE_URL`
- `MYSQL_USER` must match `SPRING_DATASOURCE_USERNAME`
- `MYSQL_PASSWORD` must match `SPRING_DATASOURCE_PASSWORD`
- `SERVER_PORT` must match `ports:` in `compose.yml` and `EXPOSE` in `Dockerfile`
