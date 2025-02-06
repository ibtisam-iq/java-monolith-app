# Dockerizing a Spring Boot Banking Application

## Architecture

This project follows a 2-tier architecture where the frontend (Thymeleaf templates) is embedded within the backend (Spring Boot application). This means the UI is not a separate application but part of the backend.

## Project Folder Structure

### 1. Root Directory

| File/Folder      | Purpose                                                                 |
|------------------|-------------------------------------------------------------------------|
| .gitignore       | Specifies files to be ignored in version control.                      |
| .mvn/wrapper     | Contains Maven Wrapper properties.                                      |
| mvnw, mvnw.cmd   | Maven wrapper scripts for Unix and Windows.                             |
| pom.xml          | Maven project configuration file.                                       |

### 2. src/main/java/com/example/bankapp/ (Application Code)

| Folder                        | Purpose                                                                 |
|-------------------------------|-------------------------------------------------------------------------|
| BankappApplication.java       | Main entry point of the Spring Boot application.                        |
| config/                       | Configures security settings.                                           |
| controller/                   | Handles HTTP requests.                                                  |
| model/                        | Defines data structures and database entity mappings.                   |
| repository/                   | Interfaces for interacting with the database.                           |
| service/                      | Contains business logic.                                                |

### 3. src/main/resources/ (Configuration & Static Assets)

| Folder/File               | Purpose                                                                 |
|---------------------------|-------------------------------------------------------------------------|
| application.properties    | Stores database connection settings and application configurations.     |
| static/mysql/SQLScript.txt| Contains SQL scripts for setting up the MySQL database.                 |
| templates/                | HTML templates for frontend UI using Thymeleaf.                         |


---
## Docker Setup

### Dockerfile (Multi-Stage Build)

```dockerfile
# First Stage: Build the application
FROM maven:3.9.9-eclipse-temurin-17-alpine AS builder
WORKDIR /usr/src/app

# Copy pom.xml and download dependencies
COPY pom.xml .
RUN mvn dependency:go-offline

# Copy source code and build the application
COPY src ./src
RUN mvn package -DskipTests

# Runtime Stage (Alpine)
FROM openjdk:17-jdk-alpine
WORKDIR /usr/src/app
COPY --from=builder /usr/src/app/target/*.jar app.jar
EXPOSE 8080
CMD ["java", "-jar", "app.jar"]
```

### Docker Compose

```yaml
version: '3'
services:
  web:
    build: .
    container_name: bg-web
    command: java -jar /usr/src/app/app.jar
    ports:
      - "8080:8080"
    environment:
      - DATABASE_URL=jdbc:mysql://db:3306/bankingdb
      - DATABASE_USERNAME=root
      - DATABASE_PASSWORD=yourpassword
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/actuator/health"]
      interval: 30s
      timeout: 10s
      retries: 3
  db:
    image: mysql:8.0
    environment:
      - MYSQL_ROOT_PASSWORD=yourpassword
      - MYSQL_DATABASE=bankingdb
    ports:
      - "3306:3306"
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 30s
      timeout: 10s
      retries: 3
```

### Commands to Run the Project

1. **Build the Docker Image:**
   ```sh
   docker build -t banking-app .
   ```

2. **Run the Docker Container:**
   ```sh
   docker run -p 8080:8080 banking-app
   ```

3. **Using Docker Compose:**
   ```sh
   docker-compose up --build
   ```

## Reference

You can find in-depth information [here](Dockerization.md).