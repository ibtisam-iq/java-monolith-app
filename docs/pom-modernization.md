# `pom.xml` Modernization — Change Log

The inherited `pom.xml` was functional but built on outdated and deprecated dependencies. Before starting any DevOps work, I audited the entire dependency tree and brought it up to current industry standards.

> I used **AI-assisted analysis (Perplexity Pro)** for this step — identifying deprecated artifacts, verifying correct replacement coordinates, and confirming Spring Boot BOM compatibility. Using the right tool efficiently is itself a DevOps skill.

---

## Changes Made

| What | Before | After | Why |
|---|---|---|---|
| Spring Boot | `3.3.3` | `3.4.4` | 3.3.x reached end of OSS support; 3.4.x has security patches and Java 21 improvements |
| Java version | `17` | `21` | Java 21 is the current LTS (supported until 2028); virtual threads, record patterns |
| `groupId` | `com.ibtisam-iq` | `com.ibtisamiq` | Hyphens are invalid in Maven `groupId` — violates Maven naming convention |
| MySQL connector | `mysql:mysql-connector-java:8.0.33` | `com.mysql:mysql-connector-j` (BOM-managed) | Old artifact deprecated since 8.0.31; new `groupId` is `com.mysql`, version managed by Spring Boot BOM |
| JaCoCo | `0.8.7` (2021) + duplicate declaration | `0.8.12`, single declaration in `<plugins>` only | Updated to latest; removed erroneous duplicate entry in `<dependencies>` |
| Added | — | `spring-boot-starter-actuator` | Provides `/actuator/health` endpoint required for Kubernetes liveness/readiness probes and Docker healthchecks |
| Added | — | `spring-boot-starter-validation` | Jakarta Bean Validation — necessary for production-grade input handling |
| Added | — | `com.h2database:h2` (runtime scope) | In-memory database for local development and testing without a running MySQL server |
| SCM / Developer / License | Empty blocks | Filled with project details | Professional standard; visible to anyone who inspects the artifact in Nexus or Maven Central |

---

## H2 Database — Why It Was Added

The original project used MySQL exclusively. I added H2 as a `runtime`-scoped dependency to support **local development and testing without requiring a running MySQL server**.

H2 is an in-memory database — it starts with the application and disappears when the process stops. It requires zero installation and zero infrastructure. This makes it ideal for:
- Running the app locally during pipeline development without Docker or MySQL
- Unit and integration tests that need a real database but shouldn't depend on external infrastructure
- Exploring the codebase quickly on any machine

> The original codebase was actually designed with H2 in mind — `application.properties` contained H2-compatible SQL dialect settings. MySQL was introduced later. I restored H2 support alongside MySQL so both paths remain available.

### How to Switch to H2

Both drivers are present in `pom.xml`. The active database is controlled entirely by `application.properties`.

**For H2 (local dev / testing):**

```properties
spring.datasource.url=jdbc:h2:mem:bankappdb;DB_CLOSE_DELAY=-1;DB_CLOSE_ON_EXIT=FALSE
spring.datasource.driver-class-name=org.h2.Driver
spring.datasource.username=sa
spring.datasource.password=
spring.jpa.database-platform=org.hibernate.dialect.H2Dialect
spring.h2.console.enabled=true
spring.h2.console.path=/h2-console
```

H2 console available at: `http://localhost:8000/h2-console`

**For MySQL (Docker Compose / production):**

```properties
spring.datasource.url=${SPRING_DATASOURCE_URL}
spring.datasource.username=${SPRING_DATASOURCE_USERNAME}
spring.datasource.password=${SPRING_DATASOURCE_PASSWORD}
spring.datasource.driver-class-name=com.mysql.cj.jdbc.Driver
spring.jpa.database-platform=org.hibernate.dialect.MySQLDialect
```

Full setup for MySQL: see [`docs/h2-database-setup.md`](h2-database-setup.md) for a side-by-side comparison of both configurations.

---

## Notes on BOM-Managed Versions

Spring Boot's parent POM (`spring-boot-starter-parent`) includes a **Bill of Materials (BOM)** that pre-defines compatible versions for all common dependencies. When a dependency is BOM-managed, you omit the `<version>` tag entirely — Maven resolves the correct version automatically.

Dependencies in this project that are BOM-managed (no `<version>` needed):
- `spring-boot-starter-*` (all Spring Boot starters)
- `com.mysql:mysql-connector-j`
- `com.h2database:h2`
- `org.springframework.security:spring-security-test`

Adding an explicit `<version>` to a BOM-managed dependency overrides the BOM — this can introduce incompatibilities and should be avoided unless there is a specific reason.
