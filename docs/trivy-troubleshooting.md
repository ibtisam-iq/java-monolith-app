# Trivy Security Scanning — Setup, Multi-Pass Architecture & Troubleshooting

The pipeline started with a basic single-pass Trivy image scan against an Alpine-based runtime image. Over several iterations — starting with a base image migration, then a multi-pass redesign, then CVE patching, then a pipeline ordering fix — I got it to a clean pass. This document records everything in the order it happened.

> I used **AI-assisted analysis (Perplexity Pro)** throughout this process — for CVE research, Maven BOM override mechanics, and pipeline debugging. Using the right tool efficiently is itself a DevOps skill.

---

## Phase 0 — The Alpine Problem (Root Cause of Everything)

### Original Runtime Base Image

The original `Dockerfile` used `eclipse-temurin:21-jre-alpine` as the runtime stage:

```dockerfile
# Original — Alpine runtime
FROM maven:3.9.9-eclipse-temurin-21-alpine AS builder
# ...
FROM eclipse-temurin:21-jre-alpine AS runtime
```

Alpine is popular because it is small (~5MB base). But in production, it has a critical security disadvantage that directly caused the Trivy failures.

### Why Alpine Kept Failing Trivy

Alpine uses **musl libc** — a different C library from glibc. Security patches from upstream projects (OpenSSL, zlib, expat, curl, etc.) are written for glibc first. The Alpine team must manually port them to musl. This creates a lag of **days to weeks** before critical CVEs are patched in Alpine's package repository.

Additionally, Alpine ships **busybox** — a single binary that implements 300+ Unix tools. A CVE in any one of those tools affects the entire busybox package.

**Result:** A Trivy scan of `eclipse-temurin:21-jre-alpine` routinely reported **5–15 CRITICAL CVEs** with status `affected` — meaning the CVE is confirmed present but no fix is available yet in Alpine's package repo. With `exit-code: '1'` on CRITICAL severity, the pipeline was permanently blocked on vulnerabilities I had no way to fix.

### The Fix — Migrate Runtime to `eclipse-temurin:21-jre-jammy`

I changed only the runtime stage. The builder stage stays on Alpine because:
- The builder is ephemeral — it is discarded after the JAR is compiled and never shipped to any registry
- CVEs in the builder stage never reach production
- Alpine's smaller size speeds up CI runner image pulls for the build stage

```dockerfile
# After — Jammy runtime, Alpine builder (unchanged)
FROM maven:3.9.9-eclipse-temurin-21-alpine AS builder
# ...
FROM eclipse-temurin:21-jre-jammy AS runtime   # ← only this line changed
```

**Why Jammy (Ubuntu 22.04 LTS)?**

Ubuntu Jammy uses **glibc** and is maintained by Canonical's dedicated security team. They backport CVE patches within hours to days of upstream release. Trivy scans of Jammy-based images typically show zero or very few CRITICAL CVEs with available fixes.

| Dimension | Alpine (`jre-alpine`) | Ubuntu Jammy (`jre-jammy`) |
|---|---|---|
| C library | musl libc | glibc |
| CVE patch lag | Days–weeks (manual musl port) | Hours–days (Canonical backports) |
| CRITICAL CVEs (typical Trivy scan) | 5–15, status: `affected` | 0–2, status: `fixed` |
| Image size | ~180MB | ~260MB (~80MB larger) |
| busybox exposure | Yes | No |
| Industry standard (2024–2026) | CLI tools, sidecars, build stages | JVM production services |

The ~80MB size difference is an acceptable trade-off. Container registries are cheap (sub-cent per GB), Kubernetes caches pulled images, and the security posture difference is material.

**Side effect — non-root user syntax changed:**

Alpine and Debian/Ubuntu use different commands to create system accounts:

```dockerfile
# Alpine syntax (what I used before)
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Debian/Ubuntu (Jammy) syntax — used after migration
RUN groupadd --system appgroup && \
    useradd --system --no-create-home --gid appgroup appuser
```

Both produce equivalent non-root system accounts. The difference is purely distro-specific init tooling.

**Future migration path (documented for roadmap):**
Once an observability stack is in place, the next step is `gcr.io/distroless/java21-debian12` — zero shell, zero package manager, effectively zero OS-level CVEs. Blocked today because: no `wget`/`curl` for `HEALTHCHECK`, no shell for `kubectl exec` debugging.

---

## Phase 1 — Initial Trivy Setup (Single Pass)

After the Alpine → Jammy migration, I had a single Trivy image scan step in `ci.yml` — no separation of OS vs. library vulnerabilities, no exit-code strategy, no multi-pass logic:

```yaml
- name: Trivy — image scan
  uses: aquasecurity/trivy-action@0.35.0
  with:
    scan-type: image
    image-ref: ${{ env.IMAGE_NAME }}:${{ steps.versioning.outputs.image_tag }}
    severity:  CRITICAL,HIGH
    exit-code: '1'
    format:    table
```

With Jammy as the runtime base, the OS-layer CVEs were gone and this single pass worked. The scan passed and the pipeline moved on.

---

## Phase 2 — Multi-Pass Architecture (Why I Redesigned It)

As I added more dependency upgrades to `pom.xml`, CRITICAL CVEs started appearing in the **library layer** (application JARs). I also learned that treating OS-level CVEs (vendor's responsibility) the same as JAR-level CVEs (my responsibility) was wrong — even on Jammy, mixing the two layers in one pass creates ambiguity about who owns the fix.

I redesigned the Trivy image scan into **three distinct passes**:

### The Architecture Decision

A Docker image contains two completely different layers of software with different ownership:

| Layer | Examples | Who owns fixing it |
|---|---|---|
| **OS packages** | glibc, openssl, zlib, libcurl | Base image vendor (Canonical for Jammy) |
| **Library JARs** | Spring Boot, Tomcat, Hibernate, Jackson | Me — declared in `pom.xml` |

Failing the build on OS CVEs blocks the pipeline on issues outside my control. The industry-standard approach separates these two layers:

### Pass A — OS Packages (warn only)

```yaml
- name: Trivy — image scan OS packages (CRITICAL → warn only)
  uses: aquasecurity/trivy-action@0.35.0
  with:
    scan-type:  image
    image-ref:  ${{ env.IMAGE_NAME }}:${{ steps.versioning.outputs.image_tag }}
    vuln-type:  os
    severity:   CRITICAL,HIGH
    exit-code:  '0'       # never fail — vendor's responsibility
    format:     table
```

`exit-code: '0'` — findings are reported in the log but the build never fails on OS CVEs. Canonical decides if and when to patch these.

### Pass B — Library JARs (CRITICAL fails the build)

```yaml
- name: Trivy — image scan JAR/library (CRITICAL → fail)
  uses: aquasecurity/trivy-action@0.35.0
  with:
    scan-type:  image
    image-ref:  ${{ env.IMAGE_NAME }}:${{ steps.versioning.outputs.image_tag }}
    vuln-type:  library
    severity:   CRITICAL
    exit-code:  '1'       # fail — these are MY dependencies in pom.xml
    format:     table
```

`exit-code: '1'` — any CRITICAL CVE in application JARs fails the build immediately. These are my dependencies. I own them. Fix = bump version in `pom.xml`.

### Pass C — Full Audit Artifact (all severities, never fails)

```yaml
- name: Trivy — image scan full report (audit artifact)
  uses: aquasecurity/trivy-action@0.35.0
  if: always()
  with:
    scan-type: image
    image-ref: ${{ env.IMAGE_NAME }}:${{ steps.versioning.outputs.image_tag }}
    severity:  CRITICAL,HIGH,MEDIUM,LOW
    exit-code: '0'
    format:    json
    output:    trivy-image-report.json
```

Runs with `if: always()` so it is never skipped. Generates a full JSON report uploaded as a GitHub Actions artifact for security audit trail.

I also added a **filesystem scan** (Pass 0) that runs *before* the Docker build — scanning the repository itself for secrets, misconfigurations, and dependency vulnerabilities in source files before the image is even built.

---

## Phase 3 — CVE Failures After `pom.xml` Update

Once Pass B had `exit-code: '1'`, the real work began. The pipeline started failing because Trivy was correctly detecting CRITICAL CVEs in my application JARs.

### CVEs Found and Fixed

After upgrading `pom.xml` to Spring Boot 3.4.4 and Java 21, Trivy's Pass B reported **7 CRITICAL vulnerabilities**. All were transitive dependencies — libraries I did not declare directly but that the Spring Boot BOM pulled in at specific versions.

#### Understanding the Two Override Mechanisms in Maven

| Mechanism | How it works | When to use |
|---|---|---|
| `<properties>` key override | Maven resolves `<properties>` before the BOM. If the BOM reads a known property key (e.g. `tomcat.version`), your value wins. | When the BOM exposes a documented property key for that library |
| `<dependencyManagement>` block | Entries in your own `pom.xml` always win over the parent BOM — Maven spec guarantee. | When the BOM does NOT expose a property key, or the key is unreliable |

**Critical lesson learned:** Setting `<thymeleaf.version>3.1.4.RELEASE</thymeleaf.version>` in `<properties>` had **no effect** — Spring Boot 3.4.5's BOM does not expose that property key for the Thymeleaf artifacts. The property was silently ignored and the BOM's vulnerable `3.1.3.RELEASE` version won. I had to use `<dependencyManagement>` instead.

#### CVE Fix Table

| Library | BOM-Pinned Version | Fixed Version | CVEs Resolved | Override Method |
|---|---|---|---|---|
| `tomcat-embed-core` | `10.1.39` | `10.1.54` | CVE-2026-29145 (CRITICAL), CVE-2026-34483 (HIGH), CVE-2026-34487 (HIGH) | `<tomcat.version>` in `<properties>` |
| `spring-security-core` | `6.4.4` | `6.5.9` | CVE-2025-41232 (CRITICAL), CVE-2025-41248 (HIGH) | `<spring-security.version>` in `<properties>` |
| `spring-security-web` | `6.4.4` | `6.5.9` | CVE-2026-22732 (CRITICAL) | Same key — both artifacts share `spring-security.version` |
| `thymeleaf` | `3.1.3.RELEASE` | `3.1.4.RELEASE` | CVE-2026-40477 (CRITICAL), CVE-2026-40478 (CRITICAL) | `<dependencyManagement>` block (property key silently ignored) |
| `thymeleaf-spring6` | `3.1.3.RELEASE` | `3.1.4.RELEASE` | CVE-2026-40477 (CRITICAL), CVE-2026-40478 (CRITICAL) | `<dependencyManagement>` block (separate artifact, same fix) |
| `spring-framework` | `6.2.x` | `6.2.17` | CVE-2025-41249, CVE-2025-41234, CVE-2026-22737 | `<spring-framework.version>` in `<properties>` |
| `logback-core` | `1.5.18` | `1.5.19` | CVE-2025-11226 (MEDIUM) | `<logback.version>` in `<properties>` |
| `jackson` (BOM) | `2.18.x` | `2.18.6` | GHSA-72hv-8253-57qq (MEDIUM) | `<jackson-bom.version>` in `<properties>` (NOT `jackson.version`) |

#### Important: Spring Security 6.5.9 — Why Not 6.4.x?

CVE-2026-22732 (CRITICAL) has **no fix in any 6.4.x release**. Trivy explicitly reports: *Fixed Version: 6.5.9, 7.0.4*. The fix was backported only into the 6.5.x and 7.0.x branches. Spring Security 6.5.x is fully compatible with Spring Boot 3.4.x — Spring Boot does not lock the Security minor version.

I also upgraded `spring-boot-starter-parent` from `3.4.4` to `3.4.5` as the first step — this resolved the majority of CVEs in a single BOM bump.

---

## Phase 4 — Pipeline Ordering Bug (Trivy Cannot Find the Image)

After fixing the CVEs in `pom.xml`, the pipeline failed again — but for a completely different reason:

```
FATAL — unable to find image "mibtisam/bankapp:0.0.1-SNAPSHOT-f7ff8dc-12"
* docker:  No such image
* remote:  MANIFEST_UNKNOWN — unknown tag
```

### Root Cause

The Docker build step used `docker/build-push-action@v6` with `load: true`:

```yaml
- name: Docker Build
  uses: docker/build-push-action@v6
  with:
    push: false
    load: true   # ← loads into Buildx's internal store, NOT the Docker daemon
```

`load: true` with Buildx puts the image into BuildKit's **isolated internal store** — not the standard Docker daemon that Trivy queries. The four backends Trivy tried all failed:

| Backend | Why it failed |
|---|---|
| `docker` | Image in Buildx store, not daemon — `No such image` |
| `containerd` | `permission denied` on socket |
| `podman` | No socket found |
| `remote` (Docker Hub) | Image was never pushed yet — `MANIFEST_UNKNOWN` |

### The Fix

Replace the `build-push-action` local build step with a plain `docker build` command, which puts the image directly into the standard Docker daemon that Trivy queries. After Trivy passes, use `docker push` to push to all registries.

```bash
docker build \
  --tag ${{ env.IMAGE_NAME }}:${{ steps.versioning.outputs.image_tag }} \
  --tag ${{ env.IMAGE_NAME }}:latest \
  --build-arg SERVER_PORT=8000 \
  ${{ env.APP_DIR }}
```

---

## Verification Command

After all fixes, confirm no vulnerable versions remain in the dependency tree:

```bash
mvn dependency:tree | grep -E "tomcat|spring-security|spring-framework|thymeleaf|logback|jackson"
```

Expected output shows patched versions (`10.1.54`, `6.5.9`, `3.1.4.RELEASE`, etc.) with no old pinned versions anywhere.

---

## Final State — What Passes Now

| Trivy Pass | Scope | exit-code | Result |
|---|---|---|---|
| Pass 0 (FS scan) | Repository files, secrets, misconfig | `0` | Warn only |
| Pass A (image — OS) | Ubuntu Jammy base packages | `0` | Warn only — vendor's responsibility |
| Pass B (image — library, CRITICAL) | Application JARs | `1` | ✅ 0 CRITICAL CVEs — passes |
| Pass B (image — library, HIGH/MEDIUM) | Application JARs | `0` | Warn only |
| Pass C (image — full audit) | All layers, all severities | `0` | JSON artifact uploaded |
