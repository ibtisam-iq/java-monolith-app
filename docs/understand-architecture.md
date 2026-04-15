# Understanding the Application Architecture

This document explains the internal architecture of the Java monolith banking application — how it is structured, how requests flow through it, and where it sits on the 2-tier vs. 3-tier spectrum.

---

## Project Folder Structure

```
java-monolith-app/
├── src/
│   ├── main/
│   │   ├── java/com/example/bankapp/
│   │   │   ├── BankappApplication.java       # Entry point
│   │   │   ├── config/SecurityConfig.java    # Spring Security config
│   │   │   ├── controller/BankController.java # HTTP request handling
│   │   │   ├── model/                        # JPA entity classes
│   │   │   ├── repository/                   # Spring Data JPA interfaces
│   │   │   └── service/                      # Business logic
│   │   └── resources/
│   │       ├── application.properties        # Reads from environment variables
│   │       ├── static/mysql/SQLScript.txt    # DB setup script
│   │       └── templates/                   # Thymeleaf HTML templates
│   └── test/
│       └── java/com/example/bankapp/
│           └── BankappApplicationTests.java  # Unit tests
├── .env.example                              # Environment variable template
├── pom.xml                                   # Maven build config
└── mvnw                                      # Maven wrapper
```

---

## Core Components

| Component | File | Role |
|---|---|---|
| **Entry Point** | `BankappApplication.java` | Boots the Spring Boot application via `@SpringBootApplication` |
| **Security** | `config/SecurityConfig.java` | Configures authentication, authorization, and endpoint access rules |
| **Controller** | `controller/BankController.java` | Handles incoming HTTP requests, delegates to service layer, returns Thymeleaf views |
| **Model** | `model/` | JPA entity classes that map to MySQL tables |
| **Repository** | `repository/` | Spring Data JPA interfaces — no SQL needed, auto-generates queries |
| **Service** | `service/` | Business logic layer — sits between controller and repository |
| **Templates** | `resources/templates/` | Thymeleaf HTML files rendered server-side by Spring Boot |

### BankappApplication.java

- The main class that boots the Spring Boot application.
- Uses `@SpringBootApplication` — a composite of `@Configuration`, `@EnableAutoConfiguration`, and `@ComponentScan`.

### config/SecurityConfig.java

- Configures authentication & authorization (login, user roles, protected routes).
- Uses Spring Security to control access to different endpoints.

### controller/BankController.java

- Handles HTTP requests and maps them to service methods.
- Returns Thymeleaf view names, which Spring Boot renders as HTML.

### model/ (Data Layer)

Entity classes annotated with `@Entity` that map directly to MySQL tables via JPA.

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

### repository/ (Database Access)

Interfaces extending `JpaRepository` — Spring Data auto-generates all standard CRUD operations.

```java
public interface AccountRepository extends JpaRepository<Account, Long> { }
```

### service/ (Business Logic)

Service classes annotated with `@Service` that contain the application's business rules.

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

---

## Request Flow

```
Browser Request
      │
      ▼
BankController.java      ← @Controller — receives HTTP request
      │
      ▼
AccountService.java      ← @Service — applies business logic
      │
      ▼
AccountRepository.java   ← @Repository — queries MySQL via JPA
      │
      ▼
   MySQL DB
      │
      ▼
Thymeleaf Template       ← Renders HTML response back to browser
```

1. User sends a request via browser (e.g., `localhost:8000/accounts`).
2. `BankController` receives the request and calls the appropriate service method.
3. `AccountService` applies business rules and calls the repository.
4. `AccountRepository` fetches data from MySQL via Spring Data JPA.
5. The result is passed back to the controller, which returns a Thymeleaf view name.
6. Spring Boot renders the HTML template and sends it to the browser.

---

## 2-Tier vs. 3-Tier Architecture

### What is 2-Tier?

The frontend (UI) and backend (business logic + database access) are bundled in a single application. The client communicates with the backend, which talks to the database.

### What is 3-Tier?

Three fully independent layers:
- **Presentation Layer** — a separate frontend app (React, Vue, Angular)
- **Business Logic Layer** — backend API (Spring Boot, Express, Flask)
- **Data Layer** — database (MySQL, PostgreSQL)

Each layer is independently deployable and replaceable.

### Where Does This App Stand?

➡️ **This is a 2-tier application.**

The Thymeleaf HTML templates live inside `src/main/resources/templates/` and are served directly by Spring Boot. There is no separate frontend application. The UI is embedded inside the backend — that is the defining characteristic of a 2-tier monolith.

| Layer | Status in This App |
|---|---|
| Presentation | ⚠️ Embedded — Thymeleaf templates inside Spring Boot |
| Business Logic | ✅ Separated — `service/` layer |
| Data Access | ✅ Separated — `repository/` layer |
| Database | ✅ External — MySQL (separate container or server) |

### Comparing Across Tech Stacks

| Tech Stack | 2-Tier Example | 3-Tier Example |
|---|---|---|
| **Java (Spring Boot)** | Spring Boot + Thymeleaf templates inside `resources/templates/` | Spring Boot REST API + React/Vue (separate project) |
| **Python (Flask/Django)** | Flask + Jinja2 templates inside backend | Flask REST API + React frontend (separate project) |
| **JavaScript (Node.js)** | Express + EJS/Pug templates inside backend | Express REST API + React frontend (separate project) |

**The rule is the same across all stacks:**
- ✅ **2-tier** — UI is rendered and served by the backend
- ✅ **3-tier** — UI is a fully independent app that calls a backend API

### How to Convert to 3-Tier

1. Remove Thymeleaf templates from `src/main/resources/templates/`.
2. Convert all controller methods to `@RestController` returning JSON instead of view names.
3. Create a separate React or Vue.js project as the frontend.
4. The frontend calls the Spring Boot REST API and renders the UI independently.

```
Before (2-tier):  Browser → Spring Boot (UI + API + DB logic) → MySQL
After  (3-tier):  Browser → React App → Spring Boot REST API → MySQL
```

---

## Technology Stack Summary

| Layer | Technology |
|---|---|
| Language | Java 21 |
| Framework | Spring Boot 3.4.4 |
| Persistence | Spring Data JPA + Hibernate |
| Database | MySQL 8 |
| Web Server | Embedded Tomcat (port 8000) |
| Security | Spring Security |
| UI | Thymeleaf (server-side rendered) |
| Build Tool | Maven 3 (with Maven Wrapper) |
| Test Coverage | JaCoCo |
| Health Checks | Spring Boot Actuator (`/actuator/health`) |
