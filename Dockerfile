# =============================================================
# Multi-Stage Dockerfile — BankApp (Java 21 Spring Boot)
# =============================================================
#
# WHY MULTI-STAGE?
# ─────────────────
# Stage 1 (builder): Contains Maven + full JDK + all build tools.
#                    Used only to compile the source and produce a JAR.
#                    This stage is DISCARDED — never shipped to any registry.
#
# Stage 2 (runtime): Minimal JRE-only image — no compiler, no Maven,
#                    no source code. Only the compiled JAR + JRE.
#                    This is the ONLY layer that gets pushed and deployed.
#
# Result: Final image is ~150-200MB instead of ~500MB+ for a full JDK image.
# Security benefit: Massively reduced attack surface — no build toolchain
#                   in production means fewer CVE vectors.
# =============================================================

# =============================================================
# Stage 1 — Builder
# Base: maven:3.9.9-eclipse-temurin-21-alpine
#
# WHY this specific image for the BUILD stage?
# ────────────────────────────────────
# Maven + JDK 21 are bundled together — no manual installation needed.
# Alpine base keeps the builder image small, which matters because:
#   - CI runners pull images on every run (smaller = faster pipeline start)
#   - The builder is never shipped, so its CVEs never reach production
#   - Alpine CVE risk in the BUILD stage is acceptable — it's ephemeral
#
# No need for the mvnw wrapper script — Maven is already in the image PATH.
# =============================================================
FROM maven:3.9.9-eclipse-temurin-21-alpine AS builder

WORKDIR /usr/src/app

# ───────────────────────────────────────────────────────
# Layer Cache Optimization — pom.xml BEFORE source code
# ───────────────────────────────────────────────────────
# Docker invalidates a layer cache when the files in that COPY change.
# By copying pom.xml first and running dependency download separately,
# we exploit Docker's layer caching:
#
#   COPY pom.xml .                    → Layer A (cache key: pom.xml hash)
#   RUN  mvn dependency:go-offline    → Layer B (only rebuilds if Layer A changes)
#   COPY src ./src                    → Layer C (cache key: src/ hash)
#   RUN  mvn clean package            → Layer D (only rebuilds if Layer C changes)
#
# Result: If only Java source code changes (the common case during development),
# Layers A and B are served from cache — Maven does NOT re-download dependencies.
# This typically saves 60-90 seconds per CI build.
# ───────────────────────────────────────────────────────
COPY pom.xml .

# dependency:go-offline vs dependency:resolve:
#   dependency:resolve   → downloads declared project dependencies only
#   dependency:go-offline→ downloads BOTH project dependencies AND Maven build
#                          plugins (compiler plugin, surefire, jar plugin, etc.)
# We use go-offline because the package step needs the plugins too.
# Without this, the first mvn clean package would still hit the internet.
RUN mvn dependency:go-offline -B --no-transfer-progress

# Copy source AFTER dependency download — so source changes don't bust the dep cache
COPY src ./src

# Build the fat executable JAR.
# -DskipTests: unit tests run separately in the CI pipeline (mvn verify).
# Running tests here would double-execute them and slow the Docker build.
RUN mvn clean package -DskipTests -B --no-transfer-progress


# =============================================================
# Stage 2 — Runtime
# Base: eclipse-temurin:21-jre-jammy  (Ubuntu 22.04 LTS)
#
# WHY eclipse-temurin:21-jre-JAMMY instead of alpine?
# ───────────────────────────────────────
# Alpine is widely used for its small size, but in production it has a
# significant security disadvantage: its CVE patch cycle is slow.
#
#   Alpine uses musl libc — a different C library from glibc. Security
#   patches from upstream projects (OpenSSL, zlib, expat, etc.) are written
#   for glibc first. The Alpine team must manually port them to musl. This
#   creates a lag of days to weeks before critical CVEs are patched.
#
#   Additionally, Alpine's busybox binary is a single executable that
#   implements 300+ Unix tools. A CVE in any one of those tools affects the
#   entire busybox package — and Alpine ships busybox as a core component.
#
#   Result: A Trivy scan of eclipse-temurin:21-jre-alpine will routinely
#   report 5-15 CRITICAL CVEs with status "affected" (no fix available yet
#   in Alpine's package repo), blocking a properly configured CI pipeline.
#
# Ubuntu Jammy (22.04 LTS) uses glibc and is maintained by Canonical's
# dedicated security team. They backport CVE patches within hours to days
# of upstream release. Trivy scans of Jammy-based images typically show
# zero or very few CRITICAL CVEs with available fixes.
#
# Size trade-off: Jammy is ~80MB larger than Alpine for this image.
# In 2024+, this is an acceptable trade-off given:
#   - Container registries are cheap (sub-cent per GB)
#   - Pull time difference is negligible in Kubernetes with image caching
#   - Security posture is materially better
#
# Industry standard (2024-2026):
#   Google, Netflix, Uber, Shopify, and most banks ship JVM services on
#   eclipse-temurin:*-jre-jammy or eclipse-temurin:*-jre-ubi9 (RedHat).
#   Alpine is used primarily for CLI tools, sidecars, and build containers.
#
# Future migration path (documented here for roadmap visibility):
#   gcr.io/distroless/java21-debian12 — zero shell, zero package manager,
#   effectively zero OS-level CVEs. Ideal once an observability stack
#   (sidecar-based logging, external health probes) is in place.
#   Blocked today because: no wget/curl for HEALTHCHECK, no shell for
#   kubectl exec debugging, requires init process for signal handling.
#
# TODO: Migrate to distroless/java21 once observability stack is in place
# gcr.io/distroless/java21-debian12 — eliminates shell attack surface entirely
# =============================================================
FROM eclipse-temurin:21-jre-jammy AS runtime

# OCI standard image labels — these are read by:
#   - Docker Hub (displays in image metadata)
#   - GHCR (GitHub packages UI)
#   - Trivy (links CVE report back to source)
#   - Kubernetes admission controllers
#   - ArgoCD image updater
LABEL org.opencontainers.image.title="BankApp" \
      org.opencontainers.image.description="Java Spring Boot Banking Application" \
      org.opencontainers.image.authors="Muhammad Ibtisam Iqbal <github.com/ibtisam-iq>" \
      org.opencontainers.image.source="https://github.com/ibtisam-iq/java-monolith-app" \
      org.opencontainers.image.licenses="MIT"

WORKDIR /usr/src/app

# ───────────────────────────────────────────────────────
# Non-root user setup — Debian/Ubuntu syntax
# ───────────────────────────────────────────────────────
# Running as root inside a container is a CIS Docker Benchmark violation
# and fails most enterprise security policies. If an attacker exploits
# the app, running as non-root limits what they can do on the host.
#
# Alpine syntax (what we used before with alpine base):
#   addgroup -S appgroup && adduser -S appuser -G appgroup
#   -S = system account (no password, no home dir, no login shell)
#
# Debian/Ubuntu syntax (used here with jammy base):
#   groupadd --system appgroup
#   useradd  --system --no-create-home --gid appgroup appuser
#   --system      = system account (UID < 1000, no password aging)
#   --no-create-home = no /home/appuser directory created
#   --gid         = assign primary group
#
# Both approaches produce equivalent non-root system accounts.
# The syntax difference is purely due to the init system / distro.
RUN groupadd --system appgroup && \
    useradd --system --no-create-home --gid appgroup appuser

# Copy only the compiled JAR from the builder stage.
# The *.jar glob picks up the fat executable JAR produced by spring-boot-maven-plugin.
# Nothing else from the builder (source, .m2 cache, build plugins) is copied.
COPY --from=builder /usr/src/app/target/*.jar app.jar

# Targeted chown on the JAR file only.
# NOT recursive (no chown -R) — only this file needs to be owned by appuser.
# /usr/src/app itself remains owned by root, which prevents the app from
# writing arbitrary files to its own working directory (defense-in-depth).
RUN chown appuser:appgroup app.jar

# Drop privileges — all subsequent instructions and the final process run as appuser.
# This applies to both HEALTHCHECK and ENTRYPOINT.
USER appuser

# ───────────────────────────────────────────────────────
# Port configuration
# ───────────────────────────────────────────────────────
# ARG: build-time variable. Can be overridden with --build-arg SERVER_PORT=9090.
#      Default is 8000. Only available during docker build, not at runtime.
# ENV: runtime variable. Makes SERVER_PORT available to the JVM process
#      and to HEALTHCHECK at runtime. Also readable by Spring Boot's
#      server.port property via ${SERVER_PORT} in application.properties.
# EXPOSE: documents which port the container listens on. Does NOT publish
#         the port — that is done by -p or Kubernetes containerPort.
#         Required for docker network routing and service mesh discovery.
ARG SERVER_PORT=8000
ENV SERVER_PORT=${SERVER_PORT}
EXPOSE ${SERVER_PORT}

# ───────────────────────────────────────────────────────
# Health Check
# ───────────────────────────────────────────────────────
# Polls Spring Boot Actuator to confirm the app is alive and accepting requests.
# Docker marks the container unhealthy if this fails --retries times in a row.
# Kubernetes uses this (via livenessProbe) to restart stuck containers.
#
# --interval=30s    : check every 30 seconds
# --timeout=10s     : if wget does not respond within 10s, count as failure
# --start-period=60s: grace period before health checks begin.
#                     Spring Boot + Hibernate JPA schema validation on cold
#                     start can take 45-60 seconds. Without this, Docker
#                     marks the container unhealthy before it has even finished
#                     starting, triggering unnecessary restarts.
# --retries=3       : mark as unhealthy only after 3 consecutive failures
#
# WHY wget and not curl?
#   Both wget and curl are available on Jammy (Ubuntu). We use wget because:
#   - wget is installed by default in the eclipse-temurin:21-jre-jammy image
#   - curl requires a separate apt-get install layer (unnecessary extra layer)
#   - wget --spider performs a HEAD-like request — does not download the body,
#     just checks that the server responds with HTTP 2xx
#
# NOTE: On Alpine we were also using wget because curl is NOT installed by
# default on Alpine and would require apk add. The wget approach is portable
# across both Alpine and Jammy — no change needed here.
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider \
        http://localhost:${SERVER_PORT:-8000}/actuator/health || exit 1

# ───────────────────────────────────────────────────────
# JVM Entrypoint — container-aware tuning flags
# ───────────────────────────────────────────────────────
# WHY exec form (["java", ...]) instead of shell form (java ...)?
#   Shell form: /bin/sh -c "java ..." — the JVM becomes a CHILD of sh.
#               Docker/Kubernetes sends SIGTERM to sh, not to the JVM.
#               The JVM never receives the signal — it gets SIGKILL after
#               the grace period, losing in-flight requests and dirty state.
#   Exec form: java becomes PID 1 directly.
#               SIGTERM is delivered straight to the JVM, which triggers
#               Spring Boot's graceful shutdown (drains active requests,
#               closes DB connections, flushes caches). Required for
#               zero-downtime rolling deployments in Kubernetes.
#
# -XX:+UseContainerSupport
#   Enables JVM awareness of Linux cgroup memory/CPU limits.
#   WITHOUT this flag (Java < 10 behavior): the JVM reads the HOST's total
#   RAM (e.g., 64GB on a cloud VM) and sizes its heap accordingly. Inside a
#   512MB container this causes immediate OOM kill.
#   WITH this flag: JVM reads the cgroup limit and sizes heap relative to
#   the container's actual memory budget.
#
# -XX:MaxRAMPercentage=75.0
#   Allocate 75% of container memory to the JVM heap.
#   The remaining 25% is reserved for:
#     - JVM metaspace (class metadata, ~100-200MB for Spring Boot)
#     - Thread stacks (1MB per thread, ~50-100 threads typical)
#     - OS page cache and kernel buffers
#     - Native memory used by NIO, Netty, etc.
#   A common mistake is setting -Xmx equal to the container limit, which
#   causes the JVM to be OOM-killed by the kernel before it can GC.
#
# -Djava.security.egd=file:/dev/./urandom
#   Java's SecureRandom blocks on /dev/random when the kernel's entropy
#   pool is low (common in VMs and containers with no hardware RNG).
#   Redirecting to /dev/urandom (non-blocking) avoids startup hangs during
#   SSL initialization, session token generation, and Spring Security setup.
#   The /dev/./ path trick bypasses a legacy JVM path check that would
#   otherwise redirect urandom back to random on some JVM versions.
ENTRYPOINT ["java", \
    "-XX:+UseContainerSupport", \
    "-XX:MaxRAMPercentage=75.0", \
    "-Djava.security.egd=file:/dev/./urandom", \
    "-jar", "app.jar"]
