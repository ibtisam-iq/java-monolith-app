# Current Version
```bash
spring.application.name=bankapp
# MySQL Database configuration
spring.datasource.url=jdbc:mysql://localhost:3306/bankappdb?useSSL=false&serverTimezone=UTC
spring.datasource.username=root
spring.datasource.password=IbtisamIQ
spring.datasource.driver-class-name=com.mysql.cj.jdbc.Driver

# JPA & Hibernate configuration
spring.jpa.hibernate.ddl-auto=update
spring.jpa.properties.hibernate.dialect=org.hibernate.dialect.MySQL8Dialect
spring.jpa.show-sql=true
```

---

# Updated application.properties
```bash
# ------------------------------
# ✅ Application Configuration
# ------------------------------
spring.application.name=bankapp

# ------------------------------
# ✅ Database Configuration
# ------------------------------
# 🟢 Before:
# spring.datasource.url=jdbc:mysql://localhost:3306/bankappdb?useSSL=false&serverTimezone=UTC
# spring.datasource.username=ibtisam
# spring.datasource.password=Ibtisam
#
# 🟢 Now:
spring.datasource.url=jdbc:mysql://db:3306/${MYSQL_DATABASE}?useSSL=false&serverTimezone=UTC
spring.datasource.username=${MYSQL_USER}
spring.datasource.password=${MYSQL_PASSWORD}
spring.datasource.driver-class-name=com.mysql.cj.jdbc.Driver

# Reason:
# - Removed hardcoded values and replaced them with environment variables.
# - "localhost" changed to "db" (Docker service name) to enable communication.

# ------------------------------
# ✅ JPA & Hibernate Configuration
# ------------------------------
spring.jpa.hibernate.ddl-auto=update
spring.jpa.properties.hibernate.dialect=org.hibernate.dialect.MySQL8Dialect
spring.jpa.show-sql=true

# ------------------------------
# ✅ Actuator Configuration (New)
# ------------------------------
# 🟢 Added this section to enable health checks in Docker Compose
management.endpoints.web.exposure.include=health
```

---

# Production -ready

```bash
# ✅ Application Name
spring.application.name=${SPRING_APPLICATION_NAME}

# ✅ Database Connection Properties
spring.datasource.url=${SPRING_DATASOURCE_URL}  # Database URL for connecting to MySQL
spring.datasource.username=${SPRING_DATASOURCE_USERNAME}  # Username for authentication
spring.datasource.password=${SPRING_DATASOURCE_PASSWORD}  # Password for authentication
spring.datasource.driver-class-name=${SPRING_DATASOURCE_DRIVER_CLASS_NAME}  # Specifies MySQL driver

# ✅ Hibernate (JPA) Settings
spring.jpa.hibernate.ddl-auto=update  # Automatically updates database schema based on entity changes
spring.jpa.database-platform=${SPRING_JPA_PROPERTIES_HIBERNATE_DIALECT}  # MySQL dialect for Hibernate
spring.jpa.show-sql=${SPRING_JPA_SHOW_SQL}  # Enables logging of SQL queries (useful for debugging)

# ✅ Fix for "depends_on" Issue (Ensures MySQL is Fully Ready)
spring.datasource.initialization-mode=always
spring.sql.init.mode=always
# 🛠️ This makes sure the app waits for MySQL to be **fully initialized** before executing queries.

# ------------------------------
# ✅ Actuator Configuration (New)
# ------------------------------
# 🟢 Exposes the "health" endpoint for Docker health checks
management.endpoints.web.exposure.include=health


# ✅ Other Optional Settings
server.port=8080  # Ensures the app runs on port 8080
```
