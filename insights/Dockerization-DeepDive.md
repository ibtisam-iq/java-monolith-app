# Dockerizing a Spring Boot Banking Application

The folder structure follows standard Spring Boot conventions with a focus on a 2-tier architecture:

> **Note:** This is quite lenghty file, you can read its short version [here](dockerization.md).

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

## Project Folder Structure

### 1. Root Directory

| File/Folder      | Purpose                                                                 |
|------------------|-------------------------------------------------------------------------|
| .gitignore       | Specifies files that should be ignored in version control (e.g., logs, build artifacts). |
| .mvn/wrapper     | Contains Maven Wrapper properties to ensure consistent builds across environments. |
| mvnw, mvnw.cmd   | Maven wrapper scripts for Unix (mvnw) and Windows (mvnw.cmd).           |
| pom.xml          | Maven project configuration file (defines dependencies, build plugins, etc.). |

### 2. src/main/java/com/example/bankapp/ (Application Code)

#### Core Components

| Folder                        | Purpose                                                                 |
|-------------------------------|-------------------------------------------------------------------------|
| BankappApplication.java       | Main entry point of the Spring Boot application.                        |
| config/SecurityConfig.java    | Configures security settings, including authentication and authorization. |
| controller/BankController.java| Handles HTTP requests (acts as a bridge between frontend and backend).   |
| model/                        | Defines data structures and database entity mappings.                   |
| repository/                   | Interfaces for interacting with the database using Spring Data JPA.     |
| service/                      | Contains business logic to process transactions and accounts.           |

#### Detailed Explanation

##### BankappApplication.java
- The main class that boots up the Spring Boot application.
- Uses `@SpringBootApplication` annotation, which combines `@Configuration`, `@EnableAutoConfiguration`, and `@ComponentScan`.

##### config/SecurityConfig.java
- Configures authentication & authorization (e.g., login, user roles).
- Uses Spring Security for securing access to different endpoints.

##### controller/BankController.java
- Handles HTTP requests (REST API endpoints).
- Uses `@RestController` annotation.

**Example:**
```java
@RestController
@RequestMapping("/bank")
public class BankController {
    @Autowired
    private AccountService accountService;

    @GetMapping("/accounts")
    public List<Account> getAllAccounts() {
        return accountService.getAllAccounts();
    }
}
```

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

| Folder/File               | Purpose                                                                 |
|---------------------------|-------------------------------------------------------------------------|
| application.properties    | Stores database connection settings and application configurations.     |
| static/mysql/SQLScript.txt| Contains SQL scripts for setting up the MySQL database.                 |
| templates/                | HTML templates for frontend UI using Thymeleaf.                         |

#### Configuration File Example (application.properties):
```properties
spring.datasource.url=jdbc:mysql://localhost:3306/bankingdb
spring.datasource.username=root
spring.datasource.password=yourpassword
spring.jpa.hibernate.ddl-auto=update
spring.jpa.show-sql=true
```

#### HTML Templates (templates/)
- `dashboard.html`: Displays user account details.
- `login.html`: Login page for authentication.
- `register.html`: Registration page for new users.
- `transactions.html`: Shows transaction history.

### 4. src/test/java/com/example/bankapp/ (Testing)

| File                      | Purpose                                                                 |
|---------------------------|-------------------------------------------------------------------------|
| BankappApplicationTests.java | Contains unit tests for validating application logic.                 |

## Request Flow

1. User requests a page via a browser (e.g., `localhost:8080/bank/accounts`).
2. Controller (`BankController.java`) handles the request and calls `AccountService`.
3. Service Layer (`AccountService.java`) processes the request and fetches data.
4. Repository Layer (`AccountRepository.java`) retrieves data from MySQL.
5. Response is sent back to the UI (`dashboard.html` displays the accounts).

---

## Understanding 2-Tier vs. 3-Tier Architecture

### 1. Architecture Description

| Architecture       | Description                                                                 |
|--------------------|-----------------------------------------------------------------------------|
| 2-Tier Architecture| The frontend (UI) and backend (business logic + database access) are tightly coupled in a single application. The client communicates directly with the database via the backend. |
| 3-Tier Architecture| The application is logically divided into three separate layers: Presentation Layer (UI), Business Logic Layer, and Database Layer. Each layer is independent and can be replaced/modified separately. |

### 2. Evaluating Your Java Banking App

#### Frontend (Presentation Layer)
- The project has Thymeleaf templates (`dashboard.html`, `login.html`, `transactions.html`), which are server-side rendered and located inside the backend (`src/main/resources/templates/`).
- There is no separate frontend framework like React, Angular, or Vue.
- UI is served by Spring Boot itself, meaning it is part of the backend.

#### Backend (Business Logic Layer)
- The Controller (`BankController.java`) and Service (`AccountService.java`) contain business logic, keeping it separate from data access.

#### Database (Data Access Layer)
- The Repository Layer (`AccountRepository.java`, `TransactionRepository.java`) is dedicated to handling database operations.

### 3. Is This Truly a 3-Tier Architecture?

➡️ No, this is not a full 3-tier architecture.

**Why?** Because the frontend is part of the backend, which means the presentation layer is not fully independent.

If a project is truly 3-tier, the frontend should be an independent application, built using a separate framework like React, Vue, or Angular. Here, Thymeleaf (HTML templates) is embedded within the backend, making it a 2-tier architecture, similar to your previous JavaScript/Flask projects.

### 4. Comparing 3-Tier in Different Tech Stacks

| Tech Stack                  | 2-Tier Example                                                      | 3-Tier Example                                                      |
|-----------------------------|---------------------------------------------------------------------|---------------------------------------------------------------------|
| Java (Spring Boot)          | Java backend + Thymeleaf (UI) inside `resources/templates/`         | Java backend (Spring Boot) + React/Vue frontend (Separate Project)  |
| Python (Flask/Django)       | Flask/Django backend + Jinja2 templates (UI inside backend)         | Flask backend + React frontend (separate project)                   |
| JavaScript (Node.js, Express)| Express backend + EJS/Pug templates inside backend                  | Express backend + React frontend (separate project)                 |

**Key Difference:**
- ✅ 2-tier: UI is embedded inside the backend.
- ✅ 3-tier: UI is a completely separate application, talking to the backend via REST APIs.

### 5. How to Convert This into a 3-Tier Application?

If you want to properly separate the frontend and make it a true 3-tier architecture, follow these steps:

1. Remove Thymeleaf templates from Spring Boot (`src/main/resources/templates/`).
2. Create a separate React or Vue.js frontend that runs independently.
3. Expose REST APIs from Spring Boot and consume them from the React frontend.

#### Example Folder Structure for 3-Tier

```plaintext
/JavaBankingApp-MySQL-3Tier
├── backend/  (Spring Boot Project)
│   ├── src/main/java/com/example/bankapp
│   │   ├── controller/
│   │   ├── service/
│   │   ├── repository/
│   │   ├── model/
│   │   └── config/
│   ├── src/main/resources/ (No UI templates here)
│   ├── pom.xml
│   └── ...
│
└── frontend/  (React or Vue.js Project)
    ├── src/
    │   ├── components/
    │   ├── pages/
    │   ├── services/ (API Calls)
    │   ├── App.js
    │   ├── index.js
    ├── package.json
    └── ...
```

This ensures a true separation of concerns, making it a proper 3-tier system.

## Final Answer

- ✅ Your current Java project is a 2-tier application, because the UI is embedded within the backend.
- ✅ For it to be 3-tier, you need to separate the frontend and use React/Vue instead of Thymeleaf.
- ✅ The definition of 3-tier architecture is the same across all tech stacks (Java, JavaScript, Python, etc.) but the folder structure and tools may differ.

---

## Dockerizing a 2-Tier Java Application

### Choosing the Right Dockerfile Strategy

When dockerizing a **2-tier Java application**, selecting the right approach depends on your **CI/CD setup, build performance, and deployment needs**. Below are four possible Dockerfile strategies, along with their **pros, cons, and use cases**.

---

## **Case 1: All-in-One Image with Maven**

```Dockerfile
FROM openjdk:17-jdk-slim
ENV APP_HOME=/usr/src/app
WORKDIR $APP_HOME

RUN apt-get update && apt-get install -y maven
COPY . $APP_HOME
RUN mvn package -DskipTests
COPY target/*.jar $APP_HOME/app.jar
EXPOSE 8080
CMD ["java", "-jar", "$APP_HOME/app.jar"]
```

### ✅ Pros:
- Simple setup, suitable for local development and testing.
- Everything needed is in one image.

### ❌ Cons:
- **Bloated image size** due to including Maven and unnecessary dependencies.
- **Slow build times** as dependencies are downloaded every time.
- Not ideal for CI/CD pipelines where builds should happen externally.

### 🏆 **Best For:**
- Local development where build dependencies are required inside the container.

---

## **Case 2: Pre-built JAR Image**

```Dockerfile
FROM adoptopenjdk/openjdk11
EXPOSE 8080
ENV APP_HOME /usr/src/app
COPY target/*.jar $APP_HOME/app.jar
WORKDIR $APP_HOME
CMD ["java", "-jar", "app.jar"]
```

### ✅ Pros:
- **Lightweight image** since it only contains the runtime and final JAR file.
- **Fast startup times** as the app is already built.

### ❌ Cons:
- **Requires external build process**, meaning you must build the JAR before creating the image.
- Not suitable for development where source code changes frequently.

### 🏆 **Best For:**
- CI/CD pipelines where builds happen outside the container.
- Production deployments.

---

## **Case 3: Maven-Based Build in Container**

```Dockerfile
FROM maven:3.9.9-eclipse-temurin-17-alpine
WORKDIR /usr/src/app
COPY . .
RUN mvn package -DskipTests
EXPOSE 8080
CMD ["java", "-jar", "target/app.jar"]
```

### ✅ Pros:
- Suitable for development and testing environments.
- Leverages **Alpine Linux**, making the image smaller than Case 1.

### ❌ Cons:
- **Still larger than a runtime-only image**.
- **Rebuilds entire source code on every Docker build**, slowing down development cycles.

### 🏆 **Best For:**
- Development and testing environments.
- When CI/CD pipelines are not set up yet.

---

## **Case 4: Multi-Stage Build (Optimized for Production)**

```Dockerfile
# First Stage: Build the application
FROM maven:3.9.9-eclipse-temurin-17-alpine AS builder
WORKDIR /usr/src/app
COPY pom.xml .
RUN mvn dependency:go-offline
COPY src ./src
RUN mvn package -DskipTests

# Runtime Stage (Alpine)
FROM openjdk:17-jdk-alpine
WORKDIR /usr/src/app
COPY --from=builder /usr/src/app/target/*.jar app.jar
EXPOSE 8080
CMD ["java", "-jar", "app.jar"]
```

### ✅ Pros:
- **Minimizes final image size** (only contains runtime + app, no Maven or source code).
- **Speeds up builds** using dependency caching.
- **Ideal for production** due to performance optimizations.

### ❌ Cons:
- More complex than a single-stage Dockerfile.
- Requires **understanding multi-stage builds**.

### 🏆 **Best For:**
- Production deployments.
- CI/CD pipelines that build the application before deployment.

---

## **Using Docker Compose for Deployment**

```yaml
version: '3'
services:
  web:
    build: .
    container_name: bg-web
    command: java -jar /usr/src/app/app.jar
    ports:
      - "8080:8080"
```

### 🏆 **Best For:**
- Managing multi-container environments.
- Running applications consistently across different environments.

---

## **Final Recommendations**

| Use Case            | Recommended Dockerfile |
|---------------------|-----------------------|
| **Local Development** | Case 1 or Case 3      |
| **CI/CD Pipelines**  | Case 2 or Case 4      |
| **Production Deployment** | Case 4           |

For production, **multi-stage builds (Case 4) are the best choice**, while **pre-built JAR images (Case 2) work well in CI/CD environments**. Local development can use **all-in-one images (Case 1 or 3), but they are not optimized for production**.