# Running the Application with H2 In-Memory Database

This document explains what H2 is, when to use it, and the exact changes required to run `java-monolith-app` against an H2 in-memory database instead of MySQL.

***

## What Is H2?

H2 is a relational database engine written entirely in Java. It runs **inside the JVM process** of your Spring Boot application — no separate server, no Docker container, no installation required. The moment you start the app, H2 starts with it. The moment you stop the app, H2 stops (and all data is gone).

| Aspect | H2 | MySQL |
|---|---|---|
| Where it runs | Inside the JVM (in-process) | Separate server or Docker container |
| Setup required | None | Install MySQL or run a container |
| Data persistence | Lost on every app stop | Persists on disk |
| Real credentials needed | No (`sa` / `password` are built-in defaults) | Yes |
| Separate container in Docker? | No | Yes |
| Best suited for | Local development, unit testing, CI pipelines | Production, Docker Compose, Kubernetes |

**The critical trade-off:** H2's in-memory mode (`mem:`) means every restart starts with an empty database. This is acceptable for development and testing — it is never acceptable for production.

***

## When to Use H2

Use H2 when:

- You want to run the application locally without installing or starting MySQL
- You are writing unit tests or integration tests that need a real database
- You are running the app in a CI pipeline where spinning up MySQL adds unnecessary complexity

Do **not** use H2 when:

- Running the application in Docker Compose (MySQL container is already available)
- Deploying to any environment where data must survive a restart
- Running with real user data

***

## Changes Required to Switch from MySQL to H2

Three things must change. Nothing else in the codebase needs to be touched.

### Change 1 — `pom.xml`: Add the H2 Dependency

The H2 driver JAR must be present on the classpath. Without it, Spring Boot cannot load the `org.h2.Driver` class and throws `ClassNotFoundException` at startup — even if every other configuration is correct.

The MySQL dependency stays in place. Both drivers can coexist. Spring Boot selects the correct one based on the `datasource.url`.

```xml
<!-- MySQL (production / Docker Compose) -->
<dependency>
    <groupId>com.mysql</groupId>
    <artifactId>mysql-connector-j</artifactId>
    <scope>runtime</scope>
</dependency>

<!-- H2 (local development / testing — in-memory, no server needed) -->
<dependency>
    <groupId>com.h2database</groupId>
    <artifactId>h2</artifactId>
    <scope>runtime</scope>
</dependency>
```

> **`scope: runtime`** — the H2 JAR is not needed to compile the code. It is only needed when the application actually runs. This is the correct scope for all JDBC drivers.

> **This H2 dependency has already been added to `pom.xml` in this repository.** No manual edit is required.

After adding the dependency, rebuild the artifact:

```bash
./mvnw clean package -DskipTests
```

***

### Change 2 — `.env`: Switch the Datasource URL and Driver

The `.env` file is the single place where all runtime configuration lives. To switch to H2, update three variables:

**For H2 (local / dev mode):**

```env
SPRING_DATASOURCE_URL=jdbc:h2:mem:ibtisamIQ
SPRING_DATASOURCE_USERNAME=sa
SPRING_DATASOURCE_PASSWORD=password
```

**For MySQL (production / Docker Compose):**

```env
SPRING_DATASOURCE_URL="jdbc:mysql://localhost:3306/IbtisamIQbankappdb?useSSL=false&serverTimezone=UTC&allowPublicKeyRetrieval=true"
SPRING_DATASOURCE_USERNAME=your_db_user
SPRING_DATASOURCE_PASSWORD=your_db_password
```

> **`sa` and `password` are H2's built-in default credentials.** You do not create any user or set any password anywhere. H2 accepts these out of the box.

> **The `&` in the MySQL URL must be wrapped in double quotes** in the `.env` file. Without quotes, the shell treats `&` as a background operator and silently truncates the URL, causing a connection failure. H2 URLs do not contain `&`, so quotes are not needed there.

***

### Change 3 — `application.properties`: Switch Driver and Dialect

Two properties in `src/main/resources/application.properties` must change when switching databases.

#### Full Side-by-Side Comparison

| Property | H2 Value | MySQL Value | Why It Changes |
|---|---|---|---|
| `spring.datasource.url` | `${SPRING_DATASOURCE_URL}` → `jdbc:h2:mem:ibtisamIQ` | `${SPRING_DATASOURCE_URL}` → full MySQL JDBC URL | Different database, different URL format |
| `spring.datasource.driver-class-name` | `org.h2.Driver` | `com.mysql.cj.jdbc.Driver` | Each database has its own driver class |
| `spring.datasource.username` | `sa` (via env var) | `your_db_user` (via env var) | H2 uses built-in defaults; MySQL needs real credentials |
| `spring.datasource.password` | `password` (via env var) | `your_db_password` (via env var) | Same reason as above |
| `spring.jpa.database-platform` | `org.hibernate.dialect.H2Dialect` | `org.hibernate.dialect.MySQLDialect` | Different SQL syntax per database |
| `spring.h2.console.enabled` | `true` | *(remove or set `false`)* | H2-only feature; irrelevant for MySQL |
| `spring.h2.console.path` | `/h2-console` | *(remove)* | H2-only feature |

#### What `application.properties` Looks Like for H2

```properties
# Application Name
spring.application.name=${SPRING_APPLICATION_NAME}

# Database Connection (H2 In-Memory)
spring.datasource.url=${SPRING_DATASOURCE_URL}
spring.datasource.username=${SPRING_DATASOURCE_USERNAME}
spring.datasource.password=${SPRING_DATASOURCE_PASSWORD}
spring.datasource.driver-class-name=org.h2.Driver

# Hibernate (JPA) Settings
spring.jpa.hibernate.ddl-auto=update
spring.jpa.database-platform=org.hibernate.dialect.H2Dialect
spring.jpa.show-sql=false

# SQL Init
spring.sql.init.mode=embedded

# H2 Console (browser UI at /h2-console)
spring.h2.console.enabled=true
spring.h2.console.path=/h2-console

# Actuator
management.endpoints.web.exposure.include=health

# Server Port
server.port=${SERVER_PORT}
```

> **`spring.sql.init.mode=embedded`** — tells Spring Boot to only run SQL init scripts when using an embedded database like H2. This is the correct value for H2. For MySQL, use `always` or `never` depending on whether you have init scripts.

> **`spring.datasource.initialization-mode=always`** is a Spring Boot 2.x property that was removed in Spring Boot 3.x. This project uses Spring Boot 3.4.4. Remove that line entirely to avoid a warning at startup.

***

## Does Any Java Code Change?

**No.** Zero Java code changes are required.

The entity classes, repositories, service classes, and controllers do not reference the database type anywhere. That is the entire purpose of JPA — your Java code is database-agnostic. The same `@Entity`, `@Repository`, and `@Service` classes work identically against H2 and MySQL.

The one annotation to verify in entity classes:

```java
@Id
@GeneratedValue(strategy = GenerationType.IDENTITY)
private Long id;
```

`GenerationType.IDENTITY` uses the database's native auto-increment column. Both H2 and MySQL support this natively. No change needed.

***

## Running the Application with H2

```bash
# Step 1 — Set H2 values in .env
SPRING_DATASOURCE_URL=jdbc:h2:mem:ibtisamIQ
SPRING_DATASOURCE_USERNAME=sa
SPRING_DATASOURCE_PASSWORD=password

# Step 2 — Rebuild (only needed after pom.xml changes)
./mvnw clean package -DskipTests

# Step 3 — Load env vars and run
set -a && source .env && set +a && java -jar target/bankapp-0.0.1-SNAPSHOT.jar
```

The app starts at: `http://localhost:8000`

The H2 browser console is available at: `http://localhost:8000/h2-console`

**H2 Console connection settings:**
- JDBC URL: `jdbc:h2:mem:ibtisamIQ`
- Username: `sa`
- Password: `password`

***

## Switching Back to MySQL

To switch back from H2 to MySQL, reverse the three changes:

1. **`.env`** — restore the MySQL URL and real credentials
2. **`application.properties`** — restore `com.mysql.cj.jdbc.Driver` and `MySQLDialect`, remove H2 console properties
3. **MySQL** — ensure MySQL is running and the database exists before starting the app

The H2 dependency in `pom.xml` does not need to be removed. Having both drivers present is harmless — Spring Boot picks the correct one based on the URL prefix (`jdbc:h2:` vs `jdbc:mysql:`).
