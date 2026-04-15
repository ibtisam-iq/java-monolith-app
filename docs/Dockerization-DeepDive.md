# Dockerizing a Spring Boot Banking Application

The folder structure follows standard Spring Boot conventions with a focus on a 2-tier architecture:

## Table of Contents
- [Project Folder Structure](#project-folder-structure)
  - [1. Root Directory](#1-root-directory)
  - [2. src/main/java/com/example/bankapp/ (Application Code)](#2-srcmainjavacomexamplebankapp-application-code)
    - [Core Components](#core-components)
    - [Detailed Explanation](#detailed-explanation)
  - [3. src/main/resources/ (Configuration & Static Assets)](#3-srcmainresources-configuration--static-assets)
  - [4. src/test/java/com/example/bankapp/ (Testing)](#4-srctestjavacomexamplebankapp-testing)
- [Request Flow](#request-flow)
- [Understanding 2-Tier vs. 3-Tier Architecture](#understanding-2-tier-vs-3-tier-architecture)
  - [1. Architecture Description](#1-architecture-description)
  - [2. Evaluating Your Java Banking App](#2-evaluating-your-java-banking-app)
  - [3. Is This Truly a 3-Tier Architecture?](#3-is-this-truly-a-3-tier-architecture)
  - [4. Comparing 3-Tier in Different Tech Stacks](#4-comparing-3-tier-in-different-tech-stacks)
  - [5. How to Convert This into a 3-Tier Application?](#5-how-to-convert-this-into-a-3-tier-application)
- [Dockerizing a 2-Tier Java Application](#dockerizing-a-2-tier-java-application)
  - [Case 1: All-in-One Image with Maven](#case-1-all-in-one-image-with-maven)
  - [Case 2: Pre-built JAR Image](#case-2-pre-built-jar-image)
  - [Case 3: Maven-Based Build in Container](#case-3-maven-based-build-in-container)
  - [Case 4: Multi-Stage Build (Optimized for Production)](#case-4-multi-stage-build-optimized-for-production)
- [Using Docker Compose for Deployment](#using-docker-compose-for-deployment)
- [Final Recommendations](#final-recommendations)

---

## Project Folder Structure

### 1. Root Directory

| File/Folder | Purpose |
|---|---|
| `.gitignore` | Specifies files ignored in version control (e.g., logs, build artifacts) |
| `.mvn/wrapper` | Contains Maven Wrapper properties to ensure consistent builds across environments |
| `mvnw`, `mvnw.cmd` | Maven wrapper scripts for Unix (`mvnw`) and Windows (`mvnw.cmd`) |
| `pom.xml` | Maven project configuration file (defines dependencies, build plugins, etc.) |

### 2. src/main/java/com/example/bankapp/ (Application Code)

#### Core Components

| Folder | Purpose |
|---|---|
| `BankappApplication.java` | Main entry point of the Spring Boot application |
| `config/SecurityConfig.java` | Configures security settings, including authentication and authorization |
| `controller/BankController.java` | Handles HTTP requests (acts as a bridge between frontend and backend) |
| `model/` | Defines data structures and database entity mappings |
| `repository/` | Interfaces for interacting with the database using Spring Data JPA |
| `service/` | Contains business logic to process transactions and accounts |

#### Detailed Explanation

##### BankappApplication.java
- The main class that boots up the Spring Boot application.
- Uses `@SpringBootApplication` annotation, which combines `@Configuration`, `@EnableAutoConfiguration`, and `@ComponentScan`.

##### config/SecurityConfig.java
- Configures authentication & authorization (e.g., login, user roles).
- Uses Spring Security for securing access to different endpoints.

##### controller/BankController.java
- Handles HTTP requests.
- Uses `@Controller` annotation with Thymeleaf view resolution.

##### model/ (Data Layer)
- Contains entity classes that map to database tables.

**Example: Account.java**
```java
@Entity
public class Account {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    private String accountNumber;
    private Double balance;
}
```

##### repository/ (Database Access)
- Uses Spring Data JPA to interact with MySQL.

**Example: AccountRepository.java**
```java
public interface AccountRepository extends JpaRepository<Account, Long> { }
```

##### service/ (Business Logic Layer)
- Contains service methods to manage business logic.

**Example: AccountService.java**
```java
@Service
public class AccountService {
    @Autowired
    private AccountRepository accountRepository;

    public List<Account> getAllAccounts() {
        return accountRepository.findAll();
    }
}
```

### 3. src/main/resources/ (Configuration & Static Assets)

| Folder/File | Purpose |
|---|---|
| `application.properties` | Stores database connection settings and application configurations (reads from env vars) |
| `static/mysql/SQLScript.txt` | Contains SQL scripts for setting up the MySQL database |
| `templates/` | HTML templates for frontend UI using Thymeleaf |

#### HTML Templates (templates/)
- `dashboard.html` — Displays user account details
- `login.html` — Login page for authentication
- `register.html` — Registration page for new users
- `transactions.html` — Shows transaction history

### 4. src/test/java/com/example/bankapp/ (Testing)

| File | Purpose |
|---|---|
| `BankappApplicationTests.java` | Contains unit tests for validating application logic |

---

## Request Flow

1. User requests a page via a browser (e.g., `localhost:8000/bank/accounts`).
2. Controller (`BankController.java`) handles the request and calls `AccountService`.
3. Service Layer (`AccountService.java`) processes the request and fetches data.
4. Repository Layer (`AccountRepository.java`) retrieves data from MySQL.
5. Response is sent back to the UI (Thymeleaf template renders the HTML).

---

## Understanding 2-Tier vs. 3-Tier Architecture

### 1. Architecture Description

| Architecture | Description |
|---|---|
| **2-Tier** | The frontend (UI) and backend (business logic + database access) are coupled in a single application. The client communicates directly with the database via the backend. |
| **3-Tier** | The application is logically divided into three separate layers: Presentation Layer (UI), Business Logic Layer, and Database Layer. Each layer is independent. |

### 2. Evaluating This Java Banking App

- **Frontend**: Thymeleaf templates (`dashboard.html`, `login.html`, `transactions.html`) are server-side rendered and live inside the backend (`src/main/resources/templates/`). There is no separate frontend framework.
- **Backend**: The Controller and Service layers contain business logic, keeping it separate from data access.
- **Database**: The Repository layer is dedicated to handling database operations.

### 3. Is This Truly a 3-Tier Architecture?

➡️ **No, this is a 2-tier application** — because the frontend is embedded inside the backend (Thymeleaf templates served by Spring Boot itself). For a true 3-tier setup, the frontend must be a completely independent application (React, Vue, Angular) communicating with the backend via REST APIs.

### 4. Comparing 3-Tier in Different Tech Stacks

| Tech Stack | 2-Tier Example | 3-Tier Example |
|---|---|---|
| Java (Spring Boot) | Spring Boot + Thymeleaf inside `resources/templates/` | Spring Boot backend + React/Vue frontend (separate project) |
| Python (Flask/Django) | Flask + Jinja2 templates inside backend | Flask backend + React frontend (separate project) |
| JavaScript (Node.js) | Express + EJS/Pug templates inside backend | Express backend + React frontend (separate project) |

**Key Difference:**
- ✅ **2-tier**: UI is embedded inside the backend
- ✅ **3-tier**: UI is a completely separate application, talking to the backend via REST APIs

### 5. How to Convert to 3-Tier

1. Remove Thymeleaf templates from Spring Boot.
2. Create a separate React or Vue.js frontend that runs independently.
3. Expose REST APIs from Spring Boot and consume them from the React frontend.

---

## Dockerizing a 2-Tier Java Application

When dockerizing a 2-tier Java application, selecting the right approach depends on your CI/CD setup, build performance, and deployment needs. Below are four possible Dockerfile strategies.

### Case 1: All-in-One Image with Maven

```dockerfile
FROM openjdk:21-jdk-slim
ENV APP_HOME=/usr/src/app
WORKDIR $APP_HOME
RUN apt-get update && apt-get install -y maven
COPY . $APP_HOME
RUN mvn package -DskipTests
EXPOSE 8000
CMD ["java", "-jar", "target/bankapp-0.0.1-SNAPSHOT.jar"]
```

**✅ Pros:** Simple setup, suitable for local development and testing. Everything needed is in one image.

**❌ Cons:** Bloated image size due to including Maven and unnecessary dependencies. Slow build times as dependencies are re-downloaded every build.

**🏆 Best For:** Local development where build dependencies are required inside the container.

---

### Case 2: Pre-built JAR Image

```dockerfile
FROM eclipse-temurin:21-jre-alpine
EXPOSE 8000
ENV APP_HOME=/usr/src/app
WORKDIR $APP_HOME
COPY target/*.jar app.jar
CMD ["java", "-jar", "app.jar"]
```

**✅ Pros:** Lightweight image — only contains the runtime and final JAR. Fast startup times.

**❌ Cons:** Requires an external build process (must build the JAR before creating the image).

**🏆 Best For:** CI/CD pipelines where builds happen outside the container. Production deployments.

---

### Case 3: Maven-Based Build in Container

```dockerfile
FROM maven:3.9.9-eclipse-temurin-21-alpine
WORKDIR /usr/src/app
COPY . .
RUN mvn package -DskipTests
EXPOSE 8000
CMD ["java", "-jar", "target/bankapp-0.0.1-SNAPSHOT.jar"]
```

**✅ Pros:** Suitable for development and testing. Leverages Alpine Linux for a smaller image.

**❌ Cons:** Still larger than a runtime-only image. Rebuilds entire source code on every Docker build.

**🏆 Best For:** Development and testing environments. When CI/CD pipelines are not yet set up.

---

### Case 4: Multi-Stage Build (Optimized for Production)

This is the approach used in this project's `Dockerfile`.

```dockerfile
# Stage 1 — Build
FROM maven:3.9.9-eclipse-temurin-21-alpine AS builder
WORKDIR /usr/src/app
COPY pom.xml .
RUN mvn dependency:resolve
COPY src ./src
RUN mvn clean package -DskipTests

# Stage 2 — Production Runtime
FROM eclipse-temurin:21-jre-alpine
WORKDIR /usr/src/app
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
COPY --from=builder /usr/src/app/target/*.jar app.jar
RUN chown appuser:appgroup app.jar
USER appuser
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD wget -qO- http://localhost:8000/actuator/health || exit 1
ENTRYPOINT ["java", "-jar", "app.jar"]
```

**✅ Pros:** Minimizes final image size (only runtime + app, no Maven or source code). Speeds up builds using dependency caching. Security hardened (non-root user).

**❌ Cons:** More complex than a single-stage Dockerfile.

**🏆 Best For:** Production deployments. CI/CD pipelines.

---

## Using Docker Compose for Deployment

This project uses Docker Compose to run both the Spring Boot app and MySQL together.

Key design decisions in `compose.yml`:
- `depends_on` with `condition: service_healthy` — app only starts after MySQL passes its health check
- `env_file` — all credentials loaded from `.env`, never hardcoded in the compose file
- Named volume `mysql_data` — database persists across container restarts
- Custom bridge network `app-network` — containers communicate by service name
- Health checks on both services — Docker monitors liveness continuously

---

## Final Recommendations

| Use Case | Recommended Approach |
|---|---|
| Local Development | Case 1 or Case 3 |
| CI/CD Pipelines | Case 2 or Case 4 |
| Production Deployment | Case 4 (Multi-Stage) |

For production, **multi-stage builds (Case 4) are the best choice** — smallest image, non-root security, and dependency caching. Pre-built JAR images (Case 2) work well in CI/CD environments where the build step happens in the pipeline before Docker image creation.
