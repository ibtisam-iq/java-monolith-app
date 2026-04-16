# ============================================================
# Build context = java-monolith-app/ (repo root)
# ============================================================

# ============================================================
# Stage 1 — Build
# maven:3.9.9-eclipse-temurin-21-alpine: Maven + JDK bundled together
# No need for mvnw wrapper — Maven is already available in this image
# ============================================================
FROM maven:3.9.9-eclipse-temurin-21-alpine AS builder

WORKDIR /usr/src/app

# Copy pom.xml FIRST — leverages Docker layer caching.
# If pom.xml doesn't change, Maven deps are NOT re-downloaded on rebuild.
COPY pom.xml .

# go-offline downloads both declared dependencies AND build plugins.
# More thorough than dependency:resolve which misses plugin artifacts.
# -B = batch mode (no interactive prompts), --no-transfer-progress = clean CI logs
RUN mvn dependency:go-offline -B --no-transfer-progress

# Copy source AFTER deps — this layer only rebuilds when code actually changes
COPY src ./src

# Build the fat JAR, skip tests (tests run separately in CI pipeline)
RUN mvn clean package -DskipTests -B --no-transfer-progress

# ============================================================
# Stage 2 — Runtime
# JRE-only Alpine image: ~150MB vs ~500MB for full JDK image
# Reduced attack surface — no compiler, no build tools in production
# ============================================================
FROM eclipse-temurin:21-jre-alpine AS runtime

# OCI standard labels — readable by Docker Hub, GHCR, Kubernetes, Trivy
LABEL org.opencontainers.image.title="BankApp" \
      org.opencontainers.image.description="Java Spring Boot Banking Application" \
      org.opencontainers.image.authors="Muhammad Ibtisam Iqbal <github.com/ibtisam-iq>" \
      org.opencontainers.image.source="https://github.com/ibtisam-iq/java-monolith-app" \
      org.opencontainers.image.licenses="MIT"

WORKDIR /usr/src/app

# Create a dedicated non-root user and group
# -S = system account (no password, no home dir, no shell)
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Copy only the built JAR from builder stage — no source code in final image
COPY --from=builder /usr/src/app/target/*.jar app.jar

# Targeted chown on only the JAR file — not recursive on the entire workdir
RUN chown appuser:appgroup app.jar

# Switch to non-root user — passes CIS Docker Benchmark & Trivy hardening checks
USER appuser

# Expose the application port (matches SERVER_PORT in .env)
EXPOSE 8000

# Health check using Spring Boot Actuator — /actuator/health
# --start-period=60s: Spring Boot + MySQL JPA startup can take 45-60s on cold start
# wget is available on Alpine; curl is NOT (never use curl in Alpine-based images)
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8000/actuator/health || exit 1

# JVM container-awareness flags — CRITICAL for Kubernetes/ECS/Docker deployments:
# -XX:+UseContainerSupport  : JVM reads cgroup limits, NOT host RAM (e.g., 16GB host → 512MB container)
#                             Without this, JVM over-allocates heap and causes OOM kills
# -XX:MaxRAMPercentage=75.0 : Use 75% of container memory for heap; 25% left for OS, metaspace, threads
# -Djava.security.egd       : Use /dev/urandom for entropy — faster startup, avoids /dev/random blocking
ENTRYPOINT ["java", \
    "-XX:+UseContainerSupport", \
    "-XX:MaxRAMPercentage=75.0", \
    "-Djava.security.egd=file:/dev/./urandom", \
    "-jar", "app.jar"]
    
